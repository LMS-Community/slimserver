package Slim::Web::Graphics;

use strict;

use Scalar::Util qw(blessed);
use File::Basename;

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::ArtworkCache;
use Slim::Utils::Prefs;
use Slim::Utils::ImageResizer;

use constant ONE_DAY  => 86400;
use constant ONE_YEAR => ONE_DAY * 365;

my $prefs = preferences('server');
my $log   = logger('artwork');

my $skinMgr;

my $cache;

sub init {
	# Get cache for artwork
	$cache = Slim::Utils::ArtworkCache->new();

	if (main::SCANNER) {
		require Slim::Web::Template::NoWeb;
		$skinMgr = Slim::Web::Template::NoWeb->new();
	}
	else {
		$skinMgr = Slim::Web::HTTP::getSkinManager();
	}
}

sub serverResizesArt { 1 }

sub _cached {
	my $path = shift;
	
	my $isInfo = main::INFOLOG && $log->is_info;
	
	if ( my $cached = $cache->get($path) ) {
		if ( my $orig = $cached->{original_path} ) {
			# Check mtime of original artwork has not changed,
			# unless it's a /music path, where we don't care if
			# it has changed.  The scanner should deal with changes there.
			if ( $path !~ /^music/ && -r $orig ) {
				my $mtime = (stat _)[9];
				if ( $cached->{mtime} != $mtime ) {
					main::INFOLOG && $isInfo && $log->info( "  current mtime $mtime != cached mtime " . $cached->{mtime} );
					return;
				}
			}
	
			if ( main::INFOLOG && $isInfo ) {
				my $type = $cached->{content_type};
				my $size = length( ${ $cached->{data_ref} } );
				$log->info( "  from cache: $type ($size bytes)" );
			}

			return $cached;
		}
	}
	
	return;
}

sub artworkRequest {
	my ( $client, $path, $params, $callback, @args ) = @_;
	
	my $isInfo = main::INFOLOG && $log->is_info;
	
	main::INFOLOG && $isInfo && $log->info("Artwork request: $path");
	
	# We need the HTTP::Response object to control caching
	my $response = $args[1];
	
	# Handling artwork works like this:
	# * Check if desired version exists in the cache and is fresh
	# * If so, use it
	# * If not:
	# * Determine the absolute path to the requested object
	# * Fire off an async resize call
	# * When resize is done, read newly cached image and callback
	
	# XXX remote URLs (from protocol handler icon)
	
	# Check cache for this path
	if ( my $c = _cached($path) ) {
		my $ct = 'image/' . $c->{content_type};
		$ct =~ s/jpg/jpeg/;
		$response->content_type($ct);
		
		# Cache music URLs for 1 year, others for 1 day
		my $exptime = $path =~ /^music/ ? ONE_YEAR : ONE_DAY;
		
		$response->header( 'Cache-Control' => 'max-age=' . $exptime );
		$response->expires( time() + $exptime );
		
		$callback->( $client, $params, $c->{data_ref}, @args );
		
		return;
	}
	
	my $fullpath;
	my $no_cache;
	
	# Parse out spec from path
	# WxH[_m][_bg][.ext]
	my ($spec) = File::Basename::basename($path) =~ /_([^_x\s]+?x[^_\s]+?(?:_(\w))?(?:_[\da-fA-F]+?)?)(?:\.\w+)?$/;

	main::DEBUGLOG && $log->debug("  Resize specification: $spec");
	
	# Special cases:
	# /music/current/cover.jpg (mentioned in CLI docs)
	if ( $path =~ m{^music/current} ) {
		# XXX
		main::INFOLOG && $isInfo && $log->info("  Special path translated to $path");
	}
	
	# /music/all_items (used in BrowseDB, just returns html/images/albums.png)
	elsif ( $path =~ m{^music/all_items} ) {
		# Poor choice of special names...
		$spec =~ s{^items/[^_]+_}{};
		$path = 'html/images/albums_' . $spec;
		
		# Make sure we have an extension
		if ( $path !~ /\./ ) {
			$path .= '.png';
		}
		
		main::INFOLOG && $isInfo && $log->info("  Special path translated to $path");
	}
	
	# If path begins with "music" it's a cover path using either coverid
	# or the old trackid format
	elsif ( $path =~ m{^music/([^/]+)/} ) {
		my $id = $1;
		
		# Fetch the url and cover values
		my $sth;
		my ($url, $cover);
		
		if ( $id =~ /^[0-9a-f]{8}$/ ) {
			# ID is a coverid
			$sth = Slim::Schema->dbh->prepare_cached( qq{
				SELECT url, cover FROM tracks WHERE coverid = ?
			} );
		}
		elsif ( $id =~ /^-\d+$/ ) {
			# XXX ID is a remote track
		}
		else {
			# ID is the trackid, this is deprecated because
			# the artwork can be stale after a rescan
			$sth = Slim::Schema->dbh->prepare_cached( qq{
				SELECT url, cover FROM tracks WHERE id = ?
			} );
		}
		
		if ( $sth ) {
			$sth->execute($id);
			($url, $cover) = $sth->fetchrow_array;
			$sth->finish;
		}
		
		if ( !$url || !$cover ) {
			# Invalid ID or no cover available, use generic CD image
			$path = $id =~ /^-/ ? 'html/images/radio_' : 'html/images/cover_';
			$path .= $spec;
			$path =~ s/\.\w+//;
			$path .= '.png';
			
			# Don't allow browsers to cache this error image
			$no_cache = 1;
			
			main::INFOLOG && $isInfo && $log->info("  No cover found, translated to $path");
			
			# Check cache for this image
			if ( my $c = _cached($path) ) {
				# Don't allow browsers to cache this error image
				my $ct = 'image/' . $c->{content_type};
				$ct =~ s/jpg/jpeg/;
				$response->content_type($ct);
				$response->header( 'Cache-Control' => 'no-cache' );
				$response->expires( time() - 1 );

				$callback->( $client, $params, $c->{data_ref}, @args );
				return;
			}
			
			my $skin = $params->{skinOverride} || $prefs->get('skin');			
			$fullpath = $skinMgr->fixHttpPath($skin, $path);
		}
		else {
			# Image to resize is either a cover path or the audio file if cover is
			# a number (length of embedded art)
			$fullpath = $cover =~ /^\d+$/
				? Slim::Utils::Misc::pathFromFileURL($url)
				: $cover;
		}
	}
	
	# If path begins with "plugins/cache" it is a special path
	# meaning we need to lookup the actual path in our cache directory
	elsif ( $path =~ m{^plugins/cache} ) {
		my $cachedir = $prefs->get('cachedir');
		$cachedir =~ s{/$}{};
		$path =~ s{^plugins/cache}{$cachedir};
	}
	
	if ( !$fullpath ) {
		$fullpath = $path;
	}
	
	if ( $spec ) {
		# Strip spec off fullpath if necessary, keeping the file extension
		my ($ext) = $spec =~ /(\.\w+)$/;
		$ext ||= '';
		$fullpath =~ s/_${spec}/$ext/;
	}
	
	# Resolve full path if it's not already a full path (checks Unix and Windows path prefixes)
	if ( $fullpath !~ m{^/} && $fullpath !~ /^[a-z]:\\/i ) {
		my $skin = $params->{skinOverride} || $prefs->get('skin');
		main::INFOLOG && $isInfo && $log->info("  Looking for: $fullpath in skin $skin");	
		$fullpath = $skinMgr->fixHttpPath($skin, $fullpath);
	}
	
	if ( $fullpath && -e $fullpath ) {
		main::idleStreams();
		
		main::INFOLOG && $isInfo && $log->info("  Resizing: $fullpath using spec $spec");
			
		Slim::Utils::ImageResizer->resize($fullpath, $path, $spec, sub {
			# Resized image should now be in cache
			my $body;
		
			if ( my $c = _cached($path) ) {
				$body = $c->{data_ref};
				
				my $ct = 'image/' . $c->{content_type};
				$ct =~ s/jpg/jpeg/;
				$response->content_type($ct);
				
				# Cache music URLs for 1 year, others for 1 day
				my $exptime = $path =~ /^music/ ? ONE_YEAR : ONE_DAY;
				
				if ( $no_cache ) {
					$response->header( 'Cache-Control' => 'no-cache' );
					$response->expires( time() - 1 );
				}
				else {
					$response->header( 'Cache-Control' => 'max-age=' . $exptime );
					$response->expires( time() + $exptime );
				}
			}
			else {
				# resize command failed, return 500
				main::INFOLOG && $isInfo && $log->info("  Resize failed, returning 500");
				
				$log->error("Artwork resize for $path failed");
				$response->code(500);
				$response->content_type('text/html');
				$response->expires( time() - 1 );
				$response->header( 'Cache-Control' => 'no-cache' );
				
				$body = \'';
			}
		
			$callback->( $client, $params, $body, @args );
		} );
	
	}
	else {
		# File does not exist, return 404
		main::INFOLOG && $isInfo && $log->info("  File not found, returning 404");
		
		$response->code(404);
		$response->content_type('text/html');
		$response->expires( time() - 1 );
		$response->header( 'Cache-Control' => 'no-cache' );
		
		my $body = Slim::Web::HTTP::filltemplatefile('html/errors/404.html', $params);
		
		$callback->( $client, $params, $body, @args );
	}
	
	return;
}
=pod XXX remove later
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
	
	# Check for a cached resize
	if ( $trackid ne 'current' ) {
		if ( length($trackid) != 8 && $trackid =~ /^\d+$/ && $trackid ne '0' ) {
			# Old-style /music/<id>/ request, throw a deprecated warning and lookup the coverid
			$log->error("Warning: $path request is deprecated, use coverid instead of trackid");
			
			if ( my $track = Slim::Schema->rs('Track')->find($trackid) ) {
				$trackid = $track->coverid;
			}
			else {
				$trackid = 0;
			}
		}
			
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
		
	} elsif ( $trackid ) {

	 	($obj) = Slim::Schema->rs('Track')->single( { coverid => $trackid } );
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
		($body, $requestedContentType) = Slim::Utils::GDResizer->resize(
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
		
		my $imageFilePath = blessed($obj) ? $obj->cover : 0;
		$imageFilePath = $obj->path if $imageFilePath && $imageFilePath =~ /^\d+$/;
		
		if ( $trackid eq 'notCoverArt' ) {
			# Cache the path to a non-cover icon image
			my $skin = $params->{'skinOverride'} || $prefs->get('skin');
			
			$imageFilePath = $skinMgr->fixHttpPath($skin, $actualPathToImage) || $actualPathToImage;			
		}
		
		my $cached = {
			'orig'        => $imageFilePath, # '0' means no file to check mtime against
			'mtime'       => $mtime,
			'body'        => $body,
			'contentType' => $requestedContentType,
			'size'        => $size || length($$body),
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
=cut

1;
