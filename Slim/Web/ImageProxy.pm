package Slim::Web::ImageProxy;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Web::ImageProxy

=head1 SYNOPSIS

	use Slim::Web::ImageProxy;
	
	# get an artwork file's url, including potential proxy path
	my $resize_url = Slim::Web::ImageProxy::proxiedImage($songData->{artwork_url});
	
	# register a custom handler to define an image's URL based on some URL
	Slim::Web::ImageProxy->registerHandler(
		match => qr/someradio\.com\/graphics\/covers\/[sml]\/.*/,
		func  => sub {
			my ($url, $spec) = @_;

			# figure out what minimum file size we'll need to satisfy the resizing spec
			my $size = Slim::Web::ImageProxy->getRightSize($spec, {
				70  => 's',
				160 => 'm',
				300 => 'l',
			}) || 'l';
			$url =~ s/\/[sml]\//\/$size\//;
			
			return $url;
		},
	);
	
	# register an external image proxy to be used for all external images
	# using an external resizing proxy can improve performance on slow LMS systems
 	Slim::Web::ImageProxy->registerHandler(
 		id => 'someExternalImageProxy',
		func  => sub {
			my ($url, $spec) = @_;
			
			# parse the resizing parameters
			my ($width, $height, $mode, $bgcolor, $ext) = Slim::Web::Graphics->parseSpec($spec);
			
			# return the full URL to your resizing service
			return sprintf(
				'http://www.yourdomain.com/imageresizer?url=%s&width=%s&height=%s', 
				uri_escape_utf8($url),
				$width,
				$height
			);
		},
		external => 1,
		desc => 'Some fast external image proxy'
 	);
	

=head1 DESCRIPTION

The ImageProxy module allows you to have artwork resized on the server-side without relying on mysqueezebox.com

Besides resizing artwork, custom handlers can eg. convert track IDs to image URLs, build a query string to request 
the smallest image possible for the given resizing spec etc.

By registering an external image proxy you can off-load the downloading and resizing of potentially large external
artwork to some other machine. This can be considerably faster if you're running LMS on a slow system, or if the
original artwork is of considerable size, where the bandwidth to download the image would be the bottleneck.

=cut

use strict;
use Digest::MD5;
use File::Spec::Functions qw(catdir);
use File::Slurp ();
use Tie::RegexpHash;
use URI::Escape qw(uri_escape_utf8);

use Exporter::Lite;
our @EXPORT_OK = qw(proxiedImage);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Web::Graphics;

tie my %handlers, 'Tie::RegexpHash';
my %externalHandlers;

use constant ONE_YEAR => 86400 * 365;

my $log   = logger('artwork.imageproxy');
my $prefs = preferences('server');
my $cache;

my %queue;

sub init {
 	$cache ||= Slim::Web::ImageProxy::Cache->new();

	# clean up  stale cache files
	Slim::Utils::Misc::deleteFiles($prefs->get('cachedir'), qr/^imgproxy_[a-f0-9]+$/i);			
}

sub getImage {
	my ($class, $client, $path, $params, $callback, $spec, @args) = @_;
	
	main::DEBUGLOG && $log->debug("Get artwork for URL: $path");

	# check the cache for this url
 	$cache ||= Slim::Web::ImageProxy::Cache->new();
 	
 	my $path2;

	# some clients require the .png ending, but we don't store it in the cache - try them both 	
 	if ($path =~ /(.*)\.png$/) {
		$path2 = $1;
 	}

	if ( my $cached = $cache->get($path) || ($path2 && $cache->get($path2)) ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( 'Got cached artwork of type ' . $cached->{content_type} . ' and ' . length(${$cached->{data_ref}}) . ' bytes length' );

		_setHeaders($args[1], $cached->{content_type});

		$callback && $callback->( $client, $params, $cached->{data_ref}, @args );
		
		return;
	}
	
	my ($url) = $path =~ m|imageproxy/(.*)/[^/]*|;

	if ( !$url ) {
		main::INFOLOG && $log->info("Artwork ID not found, returning 404");

		_artworkError( $client, $params, $spec, 404, $callback, @args );
		return;
	}

	my $handleProxiedUrl = sub {
		my $url = shift;
		
		if ( !$url || $url !~ /^(?:file|https?):/i ) {
			main::INFOLOG && $log->info("No artwork found, returning 404");
	
			_artworkError( $client, $params, $spec, 404, $callback, @args );
			return;
		}

		main::DEBUGLOG && $log->debug("Found URL to get artwork: $url");

		my $pre_shrunk;
		# use external image proxy if one is defined
		if ( $url =~ /^https?:/ && $spec && $spec !~ /^\.(png|jpe?g)/i && (my $imageproxy = $prefs->get('useLocalImageproxy')) ) {
			if ( my $external = $externalHandlers{$imageproxy} ) {
				my ($host, $port, $path, $user, $pass) = Slim::Utils::Misc::crackURL($url);
				
				if ( $external->{func} && !($host && (Slim::Utils::Network::ip_is_private($host) || $host =~ /localhost/i)) ) {
					my $url2 = $external->{func}->(uri_escape_utf8($url), $spec);
					$url = $url2 if $url2;
					$pre_shrunk = 1;
					 
					main::DEBUGLOG && $log->debug("Using custom image proxy: $url");
				}
			}
		}
		
		$queue{$url} ||= [];
		
		# we're going to queue up requests, so we don't need to download 
		# the same file multiple times due to a race condition
		push @{ $queue{$url} }, {
			client   => $client,
			cachekey => $path,
			params   => $params,
			callback => $callback,
			spec     => $spec,
			args     => \@args,
			pre_shrunk => $pre_shrunk,
		};
		
		if ( $url =~ /^file:/ ) {
			my $path = Slim::Utils::Misc::pathFromFileURL($url);
			_resizeFromFile($url, $path);
		}
		elsif ( $url =~ /^https?:/ ) {
			# no need to do the http request if we're already fetching it
			return if scalar @{ $queue{$url} } > 1;
			
			my $http = Slim::Networking::SimpleAsyncHTTP->new(
				\&_gotArtwork,
				\&_gotArtworkError,
				{
					timeout => 30,
					cache   => 1,
				},
			);
			
			$http->get( $url );
		}
	};
	
	# some plugin might have registered to deal with this image URL
	if ( my $handler = $class->getHandlerFor($url) ) {
		$url = $handler->($url, $spec, $handleProxiedUrl);
		return unless defined $url;
	}
	
	$handleProxiedUrl->($url);
}

sub _gotArtwork {
	my $http = shift;
	my $url  = $http->url;
	
	if (main::DEBUGLOG && $log->is_debug) {
		$log->debug('Received artwork of type ' . $http->headers->content_type . ' and ' . ($http->headers->content_length || length(${$http->contentRef})) . ' bytes length' );
	}
	
	# shortcut if we received an error message back
	if ($http->headers->content_type =~ /text/) {
		return _gotArtworkError($http);
	}

	if ( Slim::Utils::ImageResizer::hasDaemon() ) {
		# We don't use SimpleAsyncHTTP's saveAs feature, as this wouldn't keep a copy in the cache, which we might need
		# if we wanted other sizes of the same url
		my $fullpath = catdir( $prefs->get('cachedir'), 'imgproxy_' . Digest::MD5::md5_hex($url) );

		# Unfortunately we have to write the data to a file, in case LMS was using an external image resizer (TinyLMS)
		File::Slurp::write_file($fullpath, $http->contentRef);
	
		_resizeFromFile($http->url, $fullpath);
	
		unlink $fullpath;
	}
	else {
		_resizeFromFile($http->url, $http->contentRef, $http);
	}
}

sub _gotArtworkError {
	my $http = shift;
	my $url  = $http->url;
	
	my $error = 404;
	
	if ($http->headers && $http->headers->content_type =~ /text/) {
		$error = 500;
		main::INFOLOG && $log->is_info && $log->info("Server returned error: " . $http->content);
	}
	elsif ($http->error && $http->error =~ /(\d{3})/) {
		$error = $1;
		main::INFOLOG && $log->is_info && $log->info("Server returned error: " . $http->error);
	}

	# File does not exist, return error
	main::INFOLOG && $log->info("Artwork not found, returning $error: " . $url);

	while ( my $item = shift @{ $queue{$url} }) {
		my $client   = $item->{client};
		my $spec     = $item->{spec};
		my $args     = $item->{args};
		my $params   = $item->{params};
		my $callback = $item->{callback};
	
		_artworkError( $client, $params, $spec, $error, $callback, @$args );
	}
	
	delete $queue{$url};
}

sub _resizeFromFile {
	my ($url, $fullpath, $http) = @_;

 	$cache ||= Slim::Web::ImageProxy::Cache->new();

	while ( my $item = shift @{ $queue{$url} }) {
		my $client   = $item->{client};
		my $spec     = $item->{spec};
		my $args     = $item->{args};
		my $params   = $item->{params};
		my $callback = $item->{callback};
		my $cachekey = $item->{cachekey};
		
		# no need to resize data if we've got it from an external image proxy
		if ( ($spec =~ /^\.(?:png|jpe?g)/i || $item->{pre_shrunk}) && $http && $http->headers->content_type =~ /image\/(png|jpe?g)/ ) {
			main::DEBUGLOG && $log->debug("No resizing required - already resized remotely, or original size requested");

			my $ct = $1;
			$ct =~ s/jpeg/jpg/;

			$cache->set( $cachekey, {
				content_type  => $ct,
				mtime         => 0,
				original_path => undef,
				data_ref      => $fullpath,
			} );
			
			_setHeaders($args->[1], $ct);

			$callback && $callback->( $client, $params, $fullpath, @$args );
		}
		else {
			Slim::Utils::ImageResizer->resize($fullpath, $cachekey, $spec, sub {
				my ($body, $format) = @_;
	
				# Resized image should now be in cache
				my $response = $args->[1];
				
				if ( !($body && $format && ref $body eq 'SCALAR') && (my $c = $cache->get($cachekey)) ) {
					$body = $c->{data_ref};
					$format = $c->{content_type};
				}
				elsif ( !($body && $format && ref $body eq 'SCALAR') ) {
					# resize command failed, return 500
					main::INFOLOG && $log->info("  Resize failed, returning 500");
					$log->error("Artwork resize for $cachekey failed");
					
					_artworkError( $client, $params, $spec, 500, $callback, @$args );
					return;
				}
	
				if ($body && $format) {
					_setHeaders($args->[1], $format);
				}
			
				$callback && $callback->( $client, $params, $body, @$args );
			}, $cache );
		}
	}
	
	delete $queue{$url};
}

sub _setHeaders {
	my ($response, $format) = @_;

	my $ct = $format =~ /image/ ? $format : "image/$format";
	$ct =~ s/jpg/jpeg/;

	$response->content_type($ct);
	$response->header( 'Cache-Control' => 'max-age=' . ONE_YEAR );
	$response->expires( time() + ONE_YEAR );
}

sub _artworkError {
	my ($client, $params, $spec, $code, $callback, @args) = @_;

	my $response = $args[1];

	my ($width, $height, $mode, $bgcolor, $ext) = Slim::Web::Graphics->parseSpec($spec);
	
	require Slim::Utils::GDResizer;
	my ($res, $format) = Slim::Utils::GDResizer->resize(
		file   => Slim::Web::HTTP::fixHttpPath($params->{'skinOverride'} || $prefs->get('skin'), 'html/images/radio.png'),
		width  => $width,
		height => $height,
		mode   => $mode,
	);

	my $ct = 'image/' . $format;
	$ct =~ s/jpg/jpeg/;

	$response->content_type($ct);
#	$response->code($code);
	$response->expires( time() - 1 );
	$response->header( 'Cache-Control' => 'no-cache' );
	
	$callback->( $client, $params, $res, @args );
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

	# only proxy external URLs
	return $url unless $force || ($url && $url =~ /^https?:/);

	# don't use for all external URLs just yet, but only for URLs which have a handler defined
	return $url unless main::NOMYSB || $force || $prefs->get('useLocalImageproxy') || __PACKAGE__->getHandlerFor($url);

#	main::DEBUGLOG && $log->debug("Use proxied image URL for: $url");
	
	# Unfortunately Squeezeplay can't handle images without a file extension?!? We need to return some extension, 
	# though it might be different from the actual content type returned. But we don't know better at this point.
	my $ext = '.png';
	
	if ($url =~ /(\.(?:jpg|jpeg|png|gif))/) {
		$ext = $1;
		$ext =~ s/jpeg/jpg/;
	}
	
	return '/imageproxy/' . uri_escape_utf8($url) . '/image' . $ext;
}

# allow plugins to register custom handlers for the image url
sub registerHandler {
	my ( $class, %params ) = @_;
	
	if ( $params{external} && $params{desc} && $params{id} && $params{func} ) {
		$externalHandlers{ $params{id} } = \%params;
		main::DEBUGLOG && $log->is_debug && $log->debug("Registered external image proxy: " . $params{desc});
		return 1;
	}
	
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

sub getExternalHandlers {
	return \%externalHandlers;
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
		# use <=> comparison to make sure the sort is done numerically!
		foreach (sort { $a <=> $b } keys %$sizes) {
			return $sizes->{$_} if $_ >= $min;
		}
	}
}

1;


# custom artwork cache, extended to expire content after 30 days
package Slim::Web::ImageProxy::Cache;

use base 'Slim::Utils::DbArtworkCache';

use strict;

sub new {
	my $class = shift;
	my $root = shift;

	if ( !$cache ) {
		$cache = $class->SUPER::new($root, 'imgproxy', 86400*30);

		if ( !main::SCANNER ) {
			# start purge routine in a few seconds
			require Slim::Utils::Timers;
			Slim::Utils::Timers::setTimer( undef, time() + 10 + int(rand(5)), \&cleanup, 1 );
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