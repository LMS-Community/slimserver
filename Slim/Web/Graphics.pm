package Slim::Web::Graphics;

use strict;

use Scalar::Util qw(blessed);
use File::Basename;
use File::Slurp ();

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
	
	# Set highmem params for the artwork cache
	if ( $prefs->get('dbhighmem') ) {
		$cache->pragma('cache_size = 20000');
		$cache->pragma('temp_store = MEMORY');
	}

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
				$log->info( "  from cache: $type ($size bytes for $path)" );
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
	my ($spec) = File::Basename::basename($path) =~ /_?((?:\d+x\d+)?(?:_\w)?(?:_[\da-fA-F]+)?(?:\.\w+)?)$/;

	main::DEBUGLOG && $isInfo && $log->info("  Resize specification: $spec");
	
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
			# if $id starts with a negative sign, ID is a remote track

			# Bug 16491: Grab the remoteTrack's coverArt and do the resizing on the fly
			my $remoteTrack = Slim::Schema::RemoteTrack->fetchById($id);
			my $coverArtImage = $remoteTrack->coverArt();
			if( $coverArtImage) {
				require Slim::Utils::GDResizer;

				my @arrSpec = split(',', $spec);
				my ($width, $height, $mode, $bgcolor, $ext) = $arrSpec[0] =~ /^(?:(\d+)x(\d+))?(?:_(\w))?(?:_([\da-fA-F]+))?(?:\.(\w+))?$/;
				my ($res, $format) = Slim::Utils::GDResizer->resize(
					original => \$coverArtImage,
					width    => $width,
					height   => $height,
					mode     => $mode,
				);

				my $ct = 'image/' . $format;
				$ct =~ s/jpg/jpeg/;
				$response->content_type($ct);
				
				$callback->( $client, $params, $res, @args );
				return;
			}
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
			$path =~ s/_$//;
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
	# Bug 16814: We also need to check for UNC prefix
	if ( $fullpath !~ m{^/} && $fullpath !~ /^[a-z]:\\/i && $fullpath !~ /^\\\\/i ) {
		my $skin = $params->{skinOverride} || $prefs->get('skin');
		main::INFOLOG && $isInfo && $log->info("  Looking for: $fullpath in skin $skin");	
		$fullpath = $skinMgr->fixHttpPath($skin, $fullpath);
	}
	
	# Support pre-sized files already in place, this is used on SB Touch
	# for app icons because it can't handle resizing so many icons at once
	if ( $fullpath && $fullpath =~ /\.(?:jpg|png|gif)$/i ) {
		# Add the spec back to the fullpath
		my $fullpathspec = $fullpath;
		
		if ( $spec ) {
			$fullpathspec =~ s/(\.\w+)$/_${spec}$1/;
		}
		
		if ( -e $fullpathspec ) {
			main::INFOLOG && $isInfo && $log->info("  Using existing pre-cached file: $fullpathspec");
		
			my ($ext) = $fullpathspec =~ /\.(\w+)$/;
			my $ct = 'image/' . $ext;
			$ct =~ s/jpg/jpeg/;
			$response->content_type($ct);
		
			my $exptime = ONE_DAY;
			$response->header( 'Cache-Control' => 'max-age=' . $exptime );
			$response->expires( time() + $exptime );
		
			my $body = File::Slurp::read_file($fullpathspec);
		
			$callback->( $client, $params, \$body, @args );
			return;
		}
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

1;
