package Slim::Web::Graphics;

use strict;

use Scalar::Util qw(blessed);

use Slim::Music::Artwork;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Cache;
use Slim::Utils::Prefs;
use File::Basename;
use File::Spec::Functions qw(:ALL);

my $prefs = preferences('server');

my %typeToMethod = (
	'image/gif'  => 'newFromGifData',
	'image/jpeg' => 'newFromJpegData',
	'image/png'  => 'newFromPngData',
);

my $log = logger('artwork');

my $canUseGD = 0;
my $cache;

sub init {
	# Artwork resizing support by using GD, requires JPEG support built in
	$canUseGD = eval {
		require GD;
		if (GD::Image->can('jpeg')) {
			return 1;
		} else {
			return 0;
		}
	};

	# create cache for artwork which is not purged periodically due to potential size of cache
	$cache = Slim::Utils::Cache->new('Artwork', 1, 1);
}

sub serverResizesArt {
	return $canUseGD;
}

sub processCoverArtRequest {
	my ($client, $path, $params, $callback, @args) = @_;

	my ($body, $mtime, $inode, $size, $actualContentType, $autoType); 

	# Allow the client to specify dimensions, etc.
	$path =~ /music\/(\w+)\//;
	my $trackid = $1;

	my $imgName = File::Basename::basename($path);
	my ($imgBasename, $dirPath, $suffix)  = File::Basename::fileparse($path, '\..*');
	
	if ( !$suffix ) {
		$autoType = 1;
		
		# Assume PNG until later
		$suffix = 'png';
	}
	
	my $actualPathToImage;
	my $requestedContentType = "image/" . $suffix;
	$requestedContentType =~ s/jpg/jpeg/;
	$requestedContentType =~ s/\.//;
	$actualContentType = $requestedContentType;

	# this is not cover art, but we should be able to resize it, dontcha think?
	# need to excavate real path to the static image here
	if ($path !~ /^music\//) {
		$trackid = 'notCoverArt';
		$imgBasename =~ s/([A-Za-z0-9]+)_.*/$1/;
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
			(?:_([sSfFpco]))?        # resizeMode, given by a single character
			(?:_([\da-fA-F]+))?      # background color, optional
			(?:\.(jpg|png|gif|gd))?$ # optional file suffixes allowed are jpg png gif gd [libgd uncompressed]
			/x;	

	my $image               = $1;
	my $requestedWidth      = $2; # it's ok if it didn't match and we get undef
	my $requestedHeight     = $3; # it's ok if it didn't match and we get undef
	my $resizeMode          = $4; # fitstretch, fitsquash, pad, stretch, crop, squash, or frappe
	my $bgColor             = defined($5) ? $5 : '';

	# if the image is a png and bgColor wasn't explicitly sent, image should be transparent
	my $transparentRequest = 0;
	if ($suffix =~ /gd/) { 
		if ($bgColor eq '') {
			$log->info('this is a transparent gd request');
			$transparentRequest = 'gd';
		}
	} elsif ($suffix =~ /png/) { 
		if ($bgColor eq '') {
			$log->info('this is a transparent png request');
			$transparentRequest = 'png';
		}
	} elsif ($suffix =~ /gif/) { 
		if ($bgColor eq '') {
			$log->info('this is a transparent gif request');
			$transparentRequest = 'gif';
		}
	} else {
		if ($bgColor eq '') {
			$bgColor = 'FFFFFF';
		}
	}

	my @bgColor = split(//, $bgColor);

	# allow for slop in the bg color request-- if the correct amount of chars weren't set, default to white
	if ($bgColor ne '' && !$transparentRequest && scalar(@bgColor) != 6 && scalar(@bgColor) != 8) {
		$log->error("BG color for $imgName was not defined correctly. Defaulting to FFFFFF (white)");
		$bgColor = 'FFFFFF';
	}

	my $requestedBackColour = hex $bgColor; # bg color used when padding

	if (!defined $resizeMode) {
		# if both width and height are given but no resize mode, resizeMode is pad
		if ($requestedWidth && $requestedHeight) {
			$resizeMode = 'p';
		# otherwise let the logic below handle it
		} else {
			$resizeMode = '';
		}
	}

	# If a size is specified then default to stretch, else default to squash
	if ($resizeMode eq "f") {
		$resizeMode = "fitstretch";
	}elsif ($resizeMode eq "F") {
		$resizeMode = "fitsquash"
	}elsif ($resizeMode eq "p") {
		$resizeMode = "pad";
	} elsif ($resizeMode eq "c") {
		$resizeMode = "crop";
	} elsif ($resizeMode eq "S") {
		$resizeMode = "squash";
	} elsif ($resizeMode eq "o") {
		$resizeMode = "original";
	} elsif ($resizeMode eq "s" || $requestedWidth) {
		$resizeMode = "stretch";
	} else {
		$resizeMode = "squash";
	}

	my ($obj, $imageData, $cachedImage, $cacheKey);
	
	# Check for a cached resize
	if ( $trackid ne 'current' ) {
		$cacheKey = $path;
		
		if ( $cachedImage = $cache->get($cacheKey) ) {
			my $artworkFile = $cachedImage->{'orig'};
		
			if ( defined $artworkFile ) {
				# Check mtime of original artwork has not changed
				if ( $artworkFile && -r $artworkFile ) {
					my $origMtime = (stat _)[9];
					if ( $cachedImage->{'mtime'} != $origMtime ) {
						$log->info( "  artwork mtime $origMtime differs from cached mtime " . $cachedImage->{'mtime'} );
						$cachedImage = undef;
					}
				}
		
				if ( $cachedImage ) {

					if ( $log->is_info ) {
						my $type = $cachedImage->{contentType};
						my $size = length( ${$cachedImage->{body}} );
						$log->info( "  returning cached artwork image, $type ($size bytes)" );
					}

					return ($cachedImage->{'body'}, $cachedImage->{'mtime'}, $inode, $cachedImage->{'size'}, $cachedImage->{'contentType'});
				}
			} else {
				$log->info(" cached image not usable because 'orig' undef");
			}
		}
	}

	if ($trackid eq "current" && defined $client) {

		$obj = Slim::Player::Playlist::song($client);

	} elsif ($trackid eq 'all_items') {

		($body, $mtime, $inode, $size) = Slim::Web::HTTP::getStaticContent('html/images/albums.png', $params);
		$imageData = $$body if defined $body;
		

	} elsif ($trackid eq 'notCoverArt') {

		($body, $mtime, $inode, $size) = Slim::Web::HTTP::getStaticContent($actualPathToImage, $params);
		$imageData = $$body if defined $body;
		
	} else {

		$obj = Slim::Schema->find('Track', $trackid);
	}

	if ( $log->is_info ) {
		$log->info("Asking for trackid: $trackid - $image" . 
			($requestedWidth ? (" at size " . $requestedWidth . "x" . $requestedHeight) : ""));
	}

	if (blessed($obj) && $obj->can('coverArt')) {
		($imageData, $actualContentType, $mtime) = $obj->coverArt;
		if (!defined $actualContentType || $actualContentType eq '') {
			$actualContentType = $requestedContentType;
		}
		$log->info("  The variable \$actualContentType, which attempts to understand what image type the original file is, is set to " . $actualContentType);
	}

	# if $obj->coverArt didn't send back data, then fill with the station icon
	if ( !$imageData && $trackid eq 'current' && blessed($obj) && $obj->url
		&& (my $image = Slim::Player::ProtocolHandlers->iconForURL($obj->url, $client))) {

		$log->info("  looking up artwork $image.");

		$cacheKey = "$image-$resizeMode-$requestedWidth-$requestedHeight-$requestedBackColour-$suffix";	

		$cachedImage = $cache->get($cacheKey);
		
		if ( $cachedImage ) {

			$log->info( "  returning cached artwork image, " . $cachedImage->{'contentType'} );

			return ($cachedImage->{'body'}, $cachedImage->{'mtime'}, $inode, $cachedImage->{'size'}, $cachedImage->{'contentType'});
		}

		# resized version wasn't in cache - is there a local copy of the raw file?
		$cachedImage = $cache->get($image);

		if (Slim::Music::Info::isRemoteURL($image) && defined $cachedImage) {

			$imageData = ${$cachedImage->{body}};

			$log->info( "  found cached remote artwork image" );

		}

		# need to fetch remote artwork
		elsif (Slim::Music::Info::isRemoteURL($image)) {

			$log->info( "  catching remote artwork image" );
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
			
			($body, $mtime, $inode, $size) = Slim::Web::HTTP::getStaticContent("$image", $params);		
			$imageData = $$body;
		}

		$actualContentType = Slim::Music::Artwork->_imageContentType(\$imageData);
	}

	# if $obj->coverArt didn't send back data, then fill with a placeholder
	if ( !$imageData ) {

		my $image = blessed($obj) && $obj->remote ? 'radio' : 'cover';
		
		$log->info("  missing artwork replaced by placeholder.");

		$cacheKey = "$image-$resizeMode-$requestedWidth-$requestedHeight-$requestedBackColour-$suffix";	

		$cachedImage = $cache->get($cacheKey);
		
		if ( $cachedImage ) {

			$log->info( "  returning cached artwork image, " . $cachedImage->{'contentType'} );

			return ($cachedImage->{'body'}, $cachedImage->{'mtime'}, $inode, $cachedImage->{'size'}, $cachedImage->{'contentType'});
		}

		($body, $mtime, $inode, $size) = Slim::Web::HTTP::getStaticContent("html/images/$image.png", $params);
		$actualContentType = 'image/png';
		$imageData = $$body;
	}

	if ( $log->is_info ) {
		$log->info("  got cover art image $actualContentType of ". length($imageData) . " bytes");
	}

	if ($canUseGD && $typeToMethod{$actualContentType}) {

		# If this is a thumb, a size has been given, or this is a png and the background color isn't 100% transparent
		# then the overhead of loading the image with GD is necessary.  Otherwise, the original content
		# can be passed straight through.
		if ($image eq "thumb" || $requestedWidth || ($requestedContentType =~ /image\/(png|gd)/ && ($transparentRequest eq 'png' || ($requestedBackColour >> 24) != 0x7F))) {

			# Bug: 3850 - new() can't auto-identify the
			# ContentType (for things like non-JFIF JPEGs) - but
			# we already have. So use the proper constructor for
			# the CT. Set the image to true color.

			GD::Image->trueColor(1);

			my $constructor = $typeToMethod{$actualContentType};

			# Bug 6458, filter JPEGs on win32 through Imager to handle any corrupt files
			# XXX: Remove this when we get a newer build of GD
			if ( $actualContentType eq 'image/jpeg' && Slim::Utils::OSDetect::isWindows() ) {
				require Imager;
				my $img = Imager->new;
				eval {
					$img->read( data => $imageData ) or die $img->errstr;
					$img->write( data => \$imageData, type => 'jpeg', jpegquality => 100 ) or die $img->errstr;
				};
				if ( $@ ) {
					$log->error( "Unable to process JPEG image using Imager: $@" );
					$body = \$imageData;
					$requestedContentType = $actualContentType;
					return ($body, $mtime, $inode, $size, $requestedContentType);
				}
			}

			my $origImage   = GD::Image->$constructor($imageData);

			if ($origImage) {
				
				
				# If no extension was given optimize for the common case: square JPEG cover art
				if ( $autoType && $actualContentType eq 'image/jpeg' && ($origImage->width == $origImage->height || $resizeMode eq "original") ) {
					$log->info( "  No file type requested, returning jpeg for square image" );
					$requestedContentType = 'image/jpeg';
					$transparentRequest   = 0;
				}

				# deterime the size and of type image to be returned
				my $returnedWidth;
				my $returnedHeight;
				my ($returnedType) = $requestedContentType =~ /\/(\w+)/;
				$returnedType =~ s/jpg/jpeg/;

				# if an X is supplied for the width (height) then the returned image's width (height)
				# is chosen to maintain the aspect ratio of the original.  This only makes sense with 
				# a resize mode of 'stretch' or 'squash'
				if ($requestedWidth eq "X") {

					if ($requestedHeight eq "X") {

						$returnedWidth  = $origImage->width;
						$returnedHeight = $origImage->height;

					} else {

						$returnedWidth  = $origImage->width / $origImage->height * $requestedHeight;
						$returnedHeight = $requestedHeight;
					}

				} elsif ($requestedHeight eq "X") {

					$returnedWidth  = $requestedWidth;
					$returnedHeight = $origImage->height / $origImage->width * $requestedWidth;

				} else {

					if ($image eq "cover") {

						$returnedWidth  = $requestedWidth  || $origImage->width;
						$returnedHeight = $requestedHeight || $origImage->height;

					} else {

						$returnedWidth  = $requestedWidth;
						$returnedHeight = $requestedHeight;

						# don't cache if width or height not set so pref can be changed
						unless (defined($returnedWidth)) {
							$returnedWidth = $prefs->get('thumbSize') || 100;
							$cacheKey = undef;
						}
						unless (defined($returnedHeight)) {
							$returnedHeight = $prefs->get('thumbSize') || 100;
							$cacheKey = undef;
						}

					}

					if ($resizeMode =~ /^fit/) {
						my @r = getResizeCoords($origImage->width, $origImage->height, $returnedWidth, $returnedHeight);
						($returnedWidth, $returnedHeight) = ($r[2], $r[3]);
					}
				}

				# if the image is a png, it still needs to be processed in case it has an alpha channel
				# hence, if we're squashing the image, the size of the returned image needs to be corrected
				if ($resizeMode =~ /squash$/ && $returnedWidth > $origImage->width && $returnedHeight > $origImage->height) {

					$returnedWidth  = $origImage->width;
					$returnedHeight = $origImage->height;
				}

				# the image needs to be processed if the sizes differ, or the image is a png
				if ($requestedContentType =~ /image\/(png|gd)/ || $returnedWidth != $origImage->width || $returnedHeight != $origImage->height) {

					if ( $log->is_info ) {
						$log->info("  resizing from " . $origImage->width . "x" . $origImage->height .
							 " to $returnedWidth x $returnedHeight using $resizeMode");
					}

					# determine source and destination upper left corner and width / height
					my ($sourceX, $sourceY, $sourceWidth, $sourceHeight);
					my ($destX, $destY, $destWidth, $destHeight);

					if ($resizeMode =~ /(stretch|squash)$/) {

						$sourceX = 0; $sourceY = 0;
						$sourceWidth = $origImage->width; $sourceHeight = $origImage->height;

						$destX = 0; $destY = 0;
						$destWidth = $returnedWidth; $destHeight = $returnedHeight;

					} elsif ($resizeMode eq "pad") {

						$sourceX = 0; $sourceY = 0;
						$sourceWidth = $origImage->width; $sourceHeight = $origImage->height;

						($destX, $destY, $destWidth, $destHeight) = 
							getResizeCoords($origImage->width, $origImage->height, $returnedWidth, $returnedHeight);

					} elsif ($resizeMode eq "crop") {

						$destX = 0; $destY = 0;
						$destWidth = $returnedWidth; $destHeight = $returnedHeight;

						($sourceX, $sourceY, $sourceWidth, $sourceHeight) = 
							getResizeCoords($returnedWidth, $returnedHeight, $origImage->width, $origImage->height);
					} elsif ($resizeMode eq "original") {
						$destX = $sourceX = 0;
						$destY = $sourceY = 0;
						
						$sourceWidth  = $origImage->width;
						$sourceHeight = $origImage->height;
	
						# For resize mode 'o', maintain the original aspect ratio.
						# The requested height value is not used in this case

						if ( $sourceWidth > $sourceHeight ) {
							$destWidth  = $requestedWidth;
							$destHeight = $sourceHeight / ( $sourceWidth / $requestedWidth );
						}
						elsif ( $sourceHeight > $sourceWidth ) {
							$destWidth  = $sourceWidth / ( $sourceHeight / $requestedWidth );
							$destHeight = $requestedWidth;
						}
						else {
							$destWidth = $destHeight = $requestedWidth;
						}
					}
					
					my $newImage;
					
					if ( $resizeMode eq 'original' ) {
						$newImage = GD::Image->new($destWidth, $destHeight);
					}
					else {
						$newImage = GD::Image->new($returnedWidth, $returnedHeight);
					}

					# PNG/GD with 7 bit transparency
					if ($transparentRequest =~ /png|gd/) {
						$log->info("Set alpha for transparent $transparentRequest");
						$newImage->saveAlpha(1);
						$newImage->alphaBlending(0);
						$newImage->filledRectangle(0, 0, $returnedWidth, $returnedHeight, 0x7f000000);
					# GIF with 1-bit transparency
					} elsif ($transparentRequest eq 'gif') {
						$log->info("This is a gif with transparency");
						# a transparent gif has to choose a color to be transparent, so let's pick one at random

						$newImage->filledRectangle(0, 0, $returnedWidth, $returnedHeight, 0xaaaaaa);
						$newImage->transparent(0xaaaaaa) or $log->warn("COULD NOT SET TRANSPARENCY");

					# not transparent
					} else {
						if ( $resizeMode ne 'original' ) {
							$newImage->filledRectangle(0, 0, $returnedWidth, $returnedHeight, $requestedBackColour);
						}
					}

					# use faster Resize algorithm on slower machines
					if (preferences('server')->get('resampleArtwork')) {

						$log->info("Resampling file for better quality");
						$newImage->copyResampled(
							$origImage,
							$destX, $destY,
							$sourceX, $sourceY,
							$destWidth, $destHeight,
							$sourceWidth, $sourceHeight
						);

					} else {

						$log->info("Resizing file for faster processing");
						$newImage->copyResized(
							$origImage,
							$destX, $destY,
							$sourceX, $sourceY,
							$destWidth, $destHeight,
							$sourceWidth, $sourceHeight
						);
					}

					my $newImageData;

					# if the source image was a png and GD can output png data
					# then return a png, else return a jpg
					if ($transparentRequest eq 'gd') {

						$newImageData = $newImage->gd;
						$requestedContentType = 'image/gd';
						
					} elsif (($returnedType eq "png" || $transparentRequest eq 'png') && GD::Image->can('png') ) {

						$newImageData = $newImage->png;
						$requestedContentType = 'image/png';

					} elsif (($returnedType eq "gif" || $transparentRequest eq 'gif') && GD::Image->can('gif') ) {

						$newImageData = $newImage->gif;
						$requestedContentType = 'image/gif';

					} else {

						$newImageData = $newImage->jpeg(90);
						$requestedContentType = 'image/jpeg';
					}

					if ( $log->is_info ) {
						$log->info("  outputting cover art image $requestedContentType of ". length($newImageData) . " bytes");
					}
					
					$body = \$newImageData;

				} else {

					$log->info("  not resizing");
					$body = \$imageData;
				}

			} else {

				$log->info("GD wouldn't create image object from $path");
				$body = \$imageData;
			}

		} else {

			$log->info("No need to process image for $path");
			$body = \$imageData;
		}

	} else {

		$log->warn("Can't use GD for $actualContentType ($path)");
		$body = \$imageData;
		$requestedContentType = $actualContentType;
	}

	if ($cacheKey) {
		
		my $imageFilePath = blessed($obj) ? $obj->cover : 0;
		$imageFilePath = $obj->path if $imageFilePath eq 1;
		
		if ( $trackid eq 'notCoverArt' ) {
			# Cache the path to a non-cover icon image
			my $skin = $params->{'skinOverride'} || $prefs->get('skin');
			
			$imageFilePath = Slim::Web::HTTP::fixHttpPath($skin, $actualPathToImage);
		}
		
		my $cached = {
			'orig'        => $imageFilePath, # '0' means no file to check mtime against
			'mtime'       => $mtime,
			'body'        => $body,
			'contentType' => $requestedContentType,
			'size'        => $size,
		};

		$log->info("  caching result key: $cacheKey, orig=$imageFilePath");

		$cache->set( $cacheKey, $cached, $Cache::Cache::EXPIRES_NEVER );
	}

	return ($body, $mtime, $inode, $size, $requestedContentType);
}

sub _gotRemoteArtwork {
	my $http = shift;

	my $imageData = $http->content();
	my $url       = $http->url();

	$log->info( "got remote artwork from $url, size " . length($imageData) );

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

	$log->info("  failure looking up remote artwork - using placeholder.");

	my ($body, $mtime, $inode, $size) = Slim::Web::HTTP::getStaticContent("html/images/radio.png", $http->params('params'));

	$http->params('callback')->( 
		$http->params('client'),
		$http->params('params'),
		$body,
		@{$http->params('args')},
	);
}

sub getResizeCoords {
	my $sourceImageWidth = shift;
	my $sourceImageHeight = shift;
	my $destImageWidth = shift;
	my $destImageHeight = shift;

	my $sourceImageAR = 1.0 * $sourceImageWidth / $sourceImageHeight;
	my $destImageAR = 1.0 * $destImageWidth / $destImageHeight;

	my ($destX, $destY, $destWidth, $destHeight);

	if ($sourceImageAR >= $destImageAR) {
		$destX = 0;
		$destWidth = $destImageWidth;
		$destHeight = $destImageWidth / $sourceImageAR;
		$destY = ($destImageHeight - $destHeight) / 2
	} else {
		$destY = 0;
		$destHeight = $destImageHeight;
		$destWidth = $destImageHeight * $sourceImageAR;
		$destX = ($destImageWidth - $destWidth) / 2
	}

	return ($destX, $destY, $destWidth, $destHeight);
}

1;
