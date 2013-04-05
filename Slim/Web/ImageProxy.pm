package Slim::Web::ImageProxy;

use strict;
use Digest::MD5;
use File::Spec::Functions qw(catdir);
use File::Slurp ();
use Tie::RegexpHash;
use URI::Escape qw(uri_escape_utf8);

use Exporter::Lite;
our @EXPORT_OK = qw(proxiedImage);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::ArtworkCache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Web::Graphics;

tie my %handlers, 'Tie::RegexpHash';

use constant ONE_YEAR => 86400 * 365;

my $log   = logger('artwork.imageproxy');
my $prefs = preferences('server');
my $cache = Slim::Web::ImageProxy::Cache->new();

sub getImage {
	my ($class, $client, $path, $params, $callback, $spec, @args) = @_;
	
	main::DEBUGLOG && $log->debug("Get artwork for URL: $path");

	# check the cache for this url
	if ( my $cached = $cache->get($path) ) {
		my $ct = 'image/' . $cached->{content_type};
		$ct =~ s/jpg/jpeg/;

		main::DEBUGLOG && $log->is_debug && $log->debug( 'Got cached artwork of type ' . $ct . ' and ' . length(${$cached->{data_ref}}) . ' bytes length' );

		my $response = $args[1];
		
		$response->content_type($ct);
		$response->header( 'Cache-Control' => 'max-age=' . ONE_YEAR );
		$response->expires( time() + ONE_YEAR );

		$callback && $callback->( $client, $params, $cached->{data_ref}, @args );
		
		return;
	}
	
	my ($url) = $path =~ m|imageproxy/(.*)/[^/]*|;

	if ( !$url ) {
		main::INFOLOG && $log->info("Artwork ID not found, returning 404");

		my $body = Slim::Web::HTTP::filltemplatefile('html/errors/404.html', $params);
		_artworkError( $client, $params, $body, 404, $callback, @args );
		return;
	}
	
	# some plugin might have registered to deal with this image URL
	if ( my $handler = $class->getHandlerFor($url) ) {
		$url = $handler->($url, $spec);
	}
	
	main::DEBUGLOG && $log->debug("Found URL to get artwork: $url");
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_gotArtwork,
		\&_gotArtworkError,
		{
			client   => $client,
			spec     => $spec,
			timeout  => 15,
			cache    => 1,
			cachekey => $path,
			params   => $params,
			callback => $callback,
			args     => \@args,
		},
	);
	
	$http->get( $url );
}

# Return a proxied image URL if
# - the given url is a fully qualified url, and
# - the useLocalImageproxy pref is set (optional, as long as mysb.com is around), or
# - a custom handler for the given url has been defined (eg. radiotime), or
# - or the $force parameter is passed in
#
# $force can be used to create custom handlers dealing with custom "urls".
# Eg. there could be a pattern to only pass some album id, together with a keyword, 
# like "spotify::album::123456". It's then up to the image handler to get the real url.
sub proxiedImage {
	my ($url, $force) = @_;

	# use external proxy on mysb.com
	return $url if main::SLIM_SERVICE;

	# only proxy external URLs
	return $url unless $force || ($url && $url =~ /^https?:/);

	# don't use for all external URLs just yet, but only for URLs which have a handler defined
	return $url unless $force || $prefs->get('useLocalImageproxy') || __PACKAGE__->getHandlerFor($url);

	main::DEBUGLOG && $log->debug("Use proxied image URL for: $url");
	
	my $ext = '.png';
	
	if ($url =~ /(\.(?:jpg|jpeg|png|gif))/) {
		$ext = $1;
		$ext =~ s/jpeg/jpg/;
	}
	
	return 'imageproxy/' . uri_escape_utf8($url) . '/image' . $ext;
}

sub _gotArtwork {
	my $http     = shift;
	my $client   = $http->params('client');
	my $spec     = $http->params('spec');
	my $cachekey = $http->params('cachekey');
	my $params   = $http->params('params');
	my $callback = $http->params('callback');
	my $args     = $http->params('args');
	
	my $ct = $http->headers->content_type;
	$ct =~ s/jpeg/jpg/;
	$ct =~ s/image\///;

	# unfortunately we have to write the data to a file, in case LMS was using an external image resizer (TinyLMS)
	my $fullpath = catdir( $prefs->get('cachedir'), 'imgproxy_' . Digest::MD5::md5_hex($cachekey) );
	File::Slurp::write_file($fullpath, $http->contentRef);

	main::DEBUGLOG && $log->is_debug && $log->debug('Received artwork of type ' . $ct . ' and ' . $http->headers->content_length . ' bytes length' );

	Slim::Utils::ImageResizer->resize($fullpath, $cachekey, $spec, sub {
		# Resized image should now be in cache
		my $body;
		my $response = $args->[1];
	
		unlink $fullpath;
	
		if ( my $c = $cache->get($cachekey) ) {
			$body = $c->{data_ref};
			
			my $ct = 'image/' . $c->{content_type};
			$ct =~ s/jpg/jpeg/;
			$response->content_type($ct);
			$response->header( 'Cache-Control' => 'max-age=' . ONE_YEAR );
			$response->expires( time() + ONE_YEAR );
		}
		else {
			# resize command failed, return 500
			main::INFOLOG && $log->info("  Resize failed, returning 500");
			$log->error("Artwork resize for $cachekey failed");
			
			_artworkError( $client, $params, \'', 500, $callback, @$args );
			return;
		}
	
		$callback && $callback->( $client, $params, $body, @$args );
	}, $cache );
}

sub _gotArtworkError {
	my $http     = shift;
	my $client   = $http->params('client');
	my $params   = $http->params('params');
	my $callback = $http->params('callback');
	my $args     = $http->params('args');

	# File does not exist, return 404
	main::INFOLOG && $log->info("Artwork not found, returning 404: " . $http->url);
	
	my $body = Slim::Web::HTTP::filltemplatefile('html/errors/404.html', $params);
	_artworkError( $client, $params, $body, 404, $callback, @$args );
}

sub _artworkError {
	my ($client, $params, $body, $code, $callback, @args) = @_;

	my $response = $args[1];

	$response->code($code);
	$response->content_type('text/html');
	$response->expires( time() - 1 );
	$response->header( 'Cache-Control' => 'no-cache' );
		
	$callback->( $client, $params, $body, @args );
}

# allow plugins to register custom handlers for the image url
sub registerHandler {
	my ( $class, %params ) = @_;
	
	if ( ref $params{match} ne 'Regexp' ) {
		$log->error( 'registerProvider called without a regular expression ' . ref $params{match} );
		return;
	}
	
	if ( ref $params{func} ne 'CODE' ) {
		$log->error( 'registerProider called without a code reference' );
		return;
	}
	
	$handlers{ $params{match} } = $params{func};
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		my $name = Slim::Utils::PerlRunTime::realNameForCodeRef( $params{func} );
		$log->debug( "Registered new artwork URL handler for " . $params{match} . ": $name" );
	}
	
	return 1;
}

sub getHandlerFor {
	my ( $class, $url ) = @_;
	return $handlers{ $url };
}

# helper method to get the correc sizing parameter out of a list of possible sizes
# my $size = Slim::Web::ImageProxy->getRightSize("180x180_m.jpg", {
# 	70  => 's',
#	150 => 'm',
#	300 => 'l',
#	600 => 'g',
# });
# -> would return 'l', which is the smallest to cover 180px width/height
sub getRightSize {
	my $class = shift;
	my $spec  = shift;      # resizing specification
	my $sizes = shift;      # a list of size/param tuples - param will be returned for the smallest fit

	my ($width, $height) = Slim::Web::Graphics->parseSpec($spec);

	if ($width || $height) {
		$width  ||= $height;
		$height ||= $width;
		
		my $min = ($width > $height ? $width : $height);

		# get smallest size larger than what we need
		foreach (sort keys %$sizes) {
			return $sizes->{$_} if $_ >= $min;
		}
	}
}

1;


# custom artwork cache, extended to expire content after 30 days
package Slim::Web::ImageProxy::Cache;

use base 'Slim::Utils::DbArtworkCache';

use strict;

my $cache;

sub new {
	my $class = shift;
	my $root = shift;

	if ( !$cache ) {
		$cache = $class->SUPER::new($root, 'imgproxy', 86400*30);

		# Set highmem params for the artwork cache
		if ( $prefs->get('dbhighmem') ) {
			$cache->pragma('cache_size = 20000');
			$cache->pragma('temp_store = MEMORY');
		}
		else {
			$cache->pragma('cache_size = 300');
		}

		if ( !main::SLIM_SERVICE && !main::SCANNER ) {
			# start purge routine in a few seconds
			require Slim::Utils::Timers;
			Slim::Utils::Timers::setTimer( undef, time() + 10 + int(rand(5)), \&cleanup );
		}
	}
	
	return $cache;
}

sub cleanup {
	my ($class, $force) = @_;
	
	# after startup don't purge if a player is on - retry later
	my $interval;
	
	unless ($force) {
		for my $client ( Slim::Player::Client::clients() ) {
			if ($client->power()) {
				main::INFOLOG && $log->is_info && $log->info('Skipping cache purge due to client activity: ' . $client->name);
				$interval = 600;
				last;
			}
		}
	}
	
	my $now = time();
	
	if (!$interval) {
		my $start = $now;
			
		$cache->purge;
			
		main::INFOLOG && $log->is_info && $log->info(sprintf("ImageProxy cache purge: %f sec", $now - $start));
	}

	Slim::Utils::Timers::setTimer( undef, $now + ($interval || 86400), \&cleanup );
}

1;