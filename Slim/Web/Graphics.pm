package Slim::Web::Graphics;

use strict;

use Scalar::Util qw(blessed);

use Slim::Music::Artwork;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Cache;
use Slim::Utils::ImageResizer;
use Slim::Utils::Prefs;
use File::Basename;
use File::Spec::Functions qw(:ALL);

my $prefs = preferences('server');

my $log = logger('artwork');

my $skinMgr;

my $cache;

sub init {
	# create cache for artwork which is not purged periodically due to potential size of cache
	$cache = Slim::Utils::Cache->new('Artwork', 1, 1);

	if (main::SCANNER) {
		require Slim::Web::Template::NoWeb;
		$skinMgr = Slim::Web::Template::NoWeb->new();
	}
	else {
		$skinMgr = Slim::Web::HTTP::getSkinManager();
	}
}

sub serverResizesArt { 1 }

sub processCoverArtRequest {
	my ($client, $path, $params, $callback, @args) = @_;

	my ($body, $mtime, $inode, $size, $actualContentType, $autoType); 

	# Allow the client to specify dimensions, etc.
	$path =~ /music\/(-*\w+)\//;
	my $trackid = $1;
	main::INFOLOG && defined $trackid && $log->is_info && $log->info("trackid has been parsed from path as: $trackid");

	my $imgName = File::Basename::basename($path);
	my ($imgBasename, $dirPath, $suffix)  = File::Basename::fileparse($path, '\..*');
	
	if ( !$suffix ) {
		$autoType = 1;
		
		# Assume PNG until later
		$suffix = 'png';
	}
	
	my $actualPathToImage;
	my $requestedContentType = "image/" . $suffix;
	$requestedContentType =~ s/jpg/jpeg/i;
	$requestedContentType =~ s/\.//;
	$actualContentType = $requestedContentType;

	# this is not cover art, but we should be able to resize it, dontcha think?
	# need to excavate real path to the static image here
	if ($path !~ /^music\//) {
		$trackid = 'notCoverArt';
		$imgBasename =~ s/(-*[A-Za-z0-9]+)_.*/$1/;
		$actualPathToImage = $path;
		$actualPathToImage =~ s/$imgName/$imgBasename$suffix/;
	}
	
	# If path begins with "plugins/cache" it is a special path
	# meaning we need to lookup the actual path in our cache directory
	if ( $actualPathToImage && $actualPathToImage =~ m{^plugins/cache} ) {
		my $cachedir = $prefs->get('cachedir');
		$cachedir =~ s{/$}{};
		$actualPathToImage =~ s{^plugins/cache}{$cachedir};
	}

	# typical cover art request would come across as something like cover_300x300_c_000000.jpg
	# delimiter on "fields" is an underscore '_'
	$imgName =~ /(cover|thumb|[A-Za-z0-9]+)  # image name is first string before resizing parameters
			(?:_(X|\d+)x(X|\d+))?    # width and height are given here, e.g. 300x300
			(?:_([sSfFpcom]))?       # resizeMode, given by a single character
			(?:_([\da-fA-F]+))?      # background color, optional
			(?:\.(jpg|png|gif))?$ # optional file suffixes allowed are jpg png gif
			/ix;	

	my $image               = $1;
	my $requestedWidth      = $2; # it's ok if it didn't match and we get undef
	my $requestedHeight     = $3; # it's ok if it didn't match and we get undef
	my $resizeMode          = $4; # fitstretch, fitsquash, pad, stretch, crop, squash, or frappe
	my $bgColor             = defined($5) ? $5 : '';
	$suffix                 = $6;

	my ($obj, $imageData, $cachedImage, $cacheKey);
	
	$cacheKey = $path;
	
	main::INFOLOG && $log->info("artwork cache key: $cacheKey");
	
	# Check for a cached resize
	if ( $trackid ne 'current' ) {
		if ( $cachedImage = $cache->get($cacheKey) ) {
			my $artworkFile = $cachedImage->{'orig'};
		
			if ( defined $artworkFile ) {
				# Check mtime of original artwork has not changed
				if ( $artworkFile && -r $artworkFile ) {
					my $origMtime = (stat _)[9];
					if ( $cachedImage->{'mtime'} != $origMtime ) {
						main::INFOLOG && $log->info( "  artwork mtime $origMtime differs from cached mtime " . $cachedImage->{'mtime'} );
						$cachedImage = undef;
					}
				}
		
				if ( $cachedImage ) {

					if ( main::INFOLOG && $log->is_info ) {
						my $type = $cachedImage->{contentType};
						my $size = length( ${$cachedImage->{body}} );
						$log->info( "  returning cached artwork image, $type ($size bytes)" );
					}

					return ($cachedImage->{'body'}, $cachedImage->{'mtime'}, $inode, $cachedImage->{'size'}, $cachedImage->{'contentType'});
				}
			} else {
				main::INFOLOG && $log->info(" cached image not usable because 'orig' undef");
			}
		}
	}

	if ($trackid eq "current" && defined $client) {

		$obj = Slim::Player::Playlist::song($client);

	} elsif ($trackid eq 'all_items') {

		($body, $mtime, $inode, $size) = $skinMgr->_generateContentFromFile('get', 'html/images/albums.png', $params);
		$imageData = $$body if defined $body;
		

	} elsif ($trackid eq 'notCoverArt') {

		($body, $mtime, $inode, $size) = $skinMgr->_generateContentFromFile('get', $actualPathToImage, $params);
		$imageData = $$body if defined $body;
		
	} else {

		$obj = Slim::Schema->find('Track', $trackid);
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("Asking for trackid: $trackid - $image" . 
			($requestedWidth ? (" at size " . $requestedWidth . "x" . $requestedHeight) : ""));
	}

	if (blessed($obj) && $obj->can('coverArt')) {
		($imageData, $actualContentType, $mtime) = $obj->coverArt;
		if (!defined $actualContentType || $actualContentType eq '') {
			$actualContentType = $requestedContentType;
		}
		main::INFOLOG && $log->info("  The variable \$actualContentType, which attempts to understand what image type the original file is, is set to " . $actualContentType);
	}

	# if $obj->coverArt didn't send back data, then fill with the station icon
	if ( !$imageData && $trackid eq 'current' && blessed($obj) && $obj->url
		&& (my $image = Slim::Player::ProtocolHandlers->iconForURL($obj->url, $client))) {

		main::INFOLOG && $log->info("  looking up artwork $image.");

		$cachedImage = $cache->get($cacheKey);
		
		if ( $cachedImage ) {

			main::INFOLOG && $log->info( "  returning cached artwork image, " . $cachedImage->{'contentType'} );

			return ($cachedImage->{'body'}, $cachedImage->{'mtime'}, $inode, $cachedImage->{'size'}, $cachedImage->{'contentType'});
		}

		# resized version wasn't in cache - is there a local copy of the raw file?
		$cachedImage = $cache->get($image);

		if (Slim::Music::Info::isRemoteURL($image) && defined $cachedImage) {

			$imageData = ${$cachedImage->{body}};

			main::INFOLOG && $log->info( "  found cached remote artwork image" );

		}

		# need to fetch remote artwork
		elsif (Slim::Music::Info::isRemoteURL($image)) {

			main::INFOLOG && $log->info( "  catching remote artwork image" );
			my $http = Slim::Networking::SimpleAsyncHTTP->new(
				\&_gotRemoteArtwork,
				\&_errorGettingRemoteArtwork, 
				{
					client   => $client,
					params   => $params,
					callback => $callback,
					args     => \@args,
					path     => $path,
					timeout  => 15,
				}
			);

			$http->get($image);
			return undef;
		}

		else {
			
			($body, $mtime, $inode, $size) = $skinMgr->_generateContentFromFile('get', "$image", $params);		
			$imageData = $$body;
		}

		$actualContentType = Slim::Music::Artwork->_imageContentType(\$imageData);
	}

	# if $obj->coverArt didn't send back data, then fill with a placeholder
	if ( !$imageData ) {

		my $image = ( blessed($obj) && $obj->remote ) || $trackid =~ /^-[0-9]+$/ ? 'radio' : 'cover';
		
		main::INFOLOG && $log->info("  missing artwork replaced by $image placeholder");

		$cachedImage = $cache->get($cacheKey);
		
		if ( $cachedImage ) {

			main::INFOLOG && $log->info( "  returning cached artwork image, " . $cachedImage->{'contentType'} );

			return ($cachedImage->{'body'}, $cachedImage->{'mtime'}, $inode, $cachedImage->{'size'}, $cachedImage->{'contentType'});
		}

		($body, $mtime, $inode, $size) = $skinMgr->_generateContentFromFile('get', "html/images/$image.png", $params);
		$actualContentType = 'image/png';
		$imageData = $$body;
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("  got cover art image $actualContentType of ". length($imageData) . " bytes");
	}
	
	eval {
		($body, $requestedContentType) = Slim::Utils::ImageResizer->resize(
			original => $imageData ? \$imageData : $body,
			mode     => $resizeMode,
			width    => $requestedWidth,
			height   => $requestedHeight,
			bgcolor  => $bgColor,
			faster   => !$prefs->get('resampleArtwork'),
		);
	};
	
	my $imageFilePath = blessed($obj) ? $obj->cover : 0;
	$imageFilePath = $obj->path if $imageFilePath eq 1;
	
	if ( $trackid eq 'notCoverArt' ) {
		# Cache the path to a non-cover icon image
		my $skin = $params->{'skinOverride'} || $prefs->get('skin');
		
		$imageFilePath = $skinMgr->fixHttpPath($skin, $actualPathToImage) || $actualPathToImage;			
	}
	
	if ( $@ ) {
		logError("Unable to resize $path (original file: $imageFilePath): $@");

		my $staticImg;
		if ($trackid =~ /^-[0-9]+$/) {
			$staticImg = 'html/images/radio.png';
		} else {
			$staticImg = 'html/images/cover.png';
		}
		
		my ($body, $mtime, $inode, $size) = $skinMgr->_generateContentFromFile('get', $staticImg, $params);

		return ($body, $mtime, $inode, $size, 'image/png');
	}
	
	$requestedContentType = 'image/' . $requestedContentType;
	$requestedContentType =~ s/jpg/jpeg/;

	if ($cacheKey) {		
		my $cached = {
			'orig'        => $imageFilePath, # '0' means no file to check mtime against
			'mtime'       => $mtime,
			'body'        => $body,
			'contentType' => $requestedContentType,
			'size'        => $size,
		};

		main::INFOLOG && $log->info("  caching result key: $cacheKey, orig=$imageFilePath");

		$cache->set( $cacheKey, $cached, $Cache::Cache::EXPIRES_NEVER );
	}

	return ($body, $mtime, $inode, $size, $requestedContentType);
}

sub _gotRemoteArtwork {
	my $http = shift;

	my $imageData = $http->content();
	my $url       = $http->url();

	main::INFOLOG && $log->info( "got remote artwork from $url, size " . length($imageData) );

	my $cached = {
		'body'        => \$imageData,
		'size'        => length($imageData),
	};

	$cache->set( $url, $cached, $Cache::Cache::EXPIRES_NEVER );

	my $client   = $http->params('client');
	my $params   = $http->params('params');
	my @args     = @{$http->params('args')};
	my $callback = $http->params('callback');

	my ($body, @more) = processCoverArtRequest($client, $http->params('path'), $params, $callback, @args);

	$callback->( $client, $params, $body, @args );
}

sub _errorGettingRemoteArtwork {
	my $http = shift;

	main::INFOLOG && $log->info("  failure looking up remote artwork - using placeholder.");

	my ($body, $mtime, $inode, $size) = $skinMgr->_generateContentFromFile('get', "html/images/radio.png", $http->params('params'));

	$http->params('callback')->( 
		$http->params('client'),
		$http->params('params'),
		$body,
		@{$http->params('args')},
	);
}

1;
