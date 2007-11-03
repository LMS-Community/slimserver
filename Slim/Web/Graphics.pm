package Slim::Web::Graphics;

use strict;

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Cache;
use Slim::Utils::Prefs;
use File::Basename;
use File::Spec::Functions qw(:ALL);

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
	my ($client, $path) = @_;

	my ($body, $mtime, $inode, $size, $actualContentType); 

	# Allow the client to specify dimensions, etc.
	$path =~ /music\/(\w+)\//;
	my $trackid = $1;

	my $imgName = File::Basename::basename($path);
	my ($imgBasename, $dirPath, $suffix)  = File::Basename::fileparse($path, '\..*');
	my $actualPathToImage;
	my $requestedContentType = "image/" . $suffix;
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

	# typical cover art request would come across as something like cover_300x300_c_000000.jpg
	# delimiter on "fields" is an underscore '_'
	$imgName =~ /(cover|thumb|[A-Za-z0-9]+)  # image name is first string before resizing parameters
			(?:_(X|\d+)x(X|\d+))?    # width and height are given here, e.g. 300x300
			(?:_([sSfFpc]))?         # resizeMode, given by a single character
			(?:_([\da-fA-F]+))?      # background color, optional
			\.(jpg|png|gif)$         # file suffixes allowed are jpg png gif
			/x;	

	my $image               = $1;
	my $requestedWidth      = $2; # it's ok if it didn't match and we get undef
	my $requestedHeight     = $3; # it's ok if it didn't match and we get undef
	my $resizeMode          = $4; # fitstretch, fitsquash, pad, stretch, crop, squash, or frappe
	my $bgColor             = defined($5) ? $5 : '';

	# if the image is a png and bgColor wasn't explicitly sent, image should be transparent
	my $transparentRequest = 0;
	if ($suffix =~ /png/) { 
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

	my @bgColor             = split(//, $bgColor);

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
	} elsif ($resizeMode eq "s" || $requestedWidth) {
		$resizeMode = "stretch";
	} else {
		$resizeMode = "squash";
	}

	my ($obj, $imageData, $cachedImage, $cacheKey);

	if ($trackid eq "current" && defined $client) {

		$obj = Slim::Player::Playlist::song($client);

	} elsif ($trackid eq 'notCoverArt') {

		($body, $mtime, $inode, $size) = Slim::Web::HTTP::getStaticContent($actualPathToImage);
		$imageData = $$body;
		
	} else {

		$obj = Slim::Schema->find('Track', $trackid);
	}

	if ( $log->is_info ) {
		$log->info("Asking for trackid: $trackid - $image" . 
			($requestedWidth ? (" at size " . $requestedWidth . "x" . $requestedHeight) : ""));
	}

	if (blessed($obj) && $obj->can('coverArt')) {

		$cacheKey = join('-', $trackid, $resizeMode, $requestedWidth, $requestedHeight, $requestedBackColour, $suffix);

		$log->info("  artwork cache key: $cacheKey");

		$cachedImage = $cache->get($cacheKey);
		
		if ($cachedImage && $cachedImage->{'mtime'} != $obj->coverArtMtime($image)) {
			$cachedImage = undef;
		}

		if (!$cachedImage) {

			($imageData, $actualContentType, $mtime) = $obj->coverArt;
			if (!defined $actualContentType || $actualContentType eq '') {
				$actualContentType = $requestedContentType;
			}
			$log->info("  The variable \$actualContentType, which attempts to understand what image type the original file is, is set to " . $actualContentType);
		}
	}

	# if $obj->coverArt didn't send back data, then fill with a placeholder
	if ( (!$cachedImage && !$imageData) ) {

		my $image = blessed($obj) && $obj->remote ? 'radio' : 'cover';
		
		$log->info("  missing artwork replaced by placeholder.");

		$cacheKey = "$image-$resizeMode-$requestedWidth-$requestedHeight-$requestedBackColour-$suffix";	

		$cachedImage = $cache->get($cacheKey);

		unless ($cachedImage) {

			($body, $mtime, $inode, $size) = Slim::Web::HTTP::getStaticContent("html/images/$image.png");
			$actualContentType = 'image/png';
			$imageData = $$body;
		}
	}

	if ($cachedImage) {

		$log->info("  returning cached artwork image.");

		return ($cachedImage->{'body'}, $cachedImage->{'mtime'}, $inode, $cachedImage->{'size'}, $cachedImage->{'contentType'});
	}

	if ( $log->is_info ) {
		$log->info("  got cover art image $actualContentType of ". length($imageData) . " bytes");
	}

	if ($canUseGD && $typeToMethod{$actualContentType}) {

		# If this is a thumb, a size has been given, or this is a png and the background color isn't 100% transparent
		# then the overhead of loading the image with GD is necessary.  Otherwise, the original content
		# can be passed straight through.
		if ($image eq "thumb" || $requestedWidth || ($requestedContentType eq "image/png" && ($transparentRequest eq 'png' || ($requestedBackColour >> 24) != 0x7F))) {

			# Bug: 3850 - new() can't auto-identify the
			# ContentType (for things like non-JFIF JPEGs) - but
			# we already have. So use the proper constructor for
			# the CT. Set the image to true color.

			GD::Image->trueColor(1);

			my $constructor = $typeToMethod{$actualContentType};
			my $origImage   = GD::Image->$constructor($imageData);

			if ($origImage) {

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

						my $prefs = preferences('server');

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
				if ($requestedContentType eq "image/png" || $returnedWidth != $origImage->width || $returnedHeight != $origImage->height) {

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

					}elsif ($resizeMode eq "pad") {

						$sourceX = 0; $sourceY = 0;
						$sourceWidth = $origImage->width; $sourceHeight = $origImage->height;

						($destX, $destY, $destWidth, $destHeight) = 
							getResizeCoords($origImage->width, $origImage->height, $returnedWidth, $returnedHeight);

					}elsif ($resizeMode eq "crop") {

						$destX = 0; $destY = 0;
						$destWidth = $returnedWidth; $destHeight = $returnedHeight;

						($sourceX, $sourceY, $sourceWidth, $sourceHeight) = 
							getResizeCoords($returnedWidth, $returnedHeight, $origImage->width, $origImage->height);
					}

					my $newImage = GD::Image->new($returnedWidth, $returnedHeight);

					# PNG with 7 bit transparency
					if ($transparentRequest eq 'png') {
						$log->info("SET ALPHA FOR TRANSPARENT PNGs");
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
						$newImage->filledRectangle(0, 0, $returnedWidth, $returnedHeight, $requestedBackColour);
					}

					$newImage->copyResampled(
						$origImage,
						$destX, $destY,
						$sourceX, $sourceY,
						$destWidth, $destHeight,
						$sourceWidth, $sourceHeight
					);

					my $newImageData;

					# if the source image was a png and GD can output png data
					# then return a png, else return a jpg
					if (($returnedType eq "png" || $transparentRequest eq 'png') && GD::Image->can('png') ) {

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

		$log->warn("Can't use GD for $path");
		$body = \$imageData;
	}

	if ($cacheKey) {
	
		my $cached = {
			'mtime'       => $mtime,
			'body'        => $body,
			'contentType' => $requestedContentType,
			'size'        => $size,
		};

		$log->info("  caching result key: $cacheKey");

		$cache->set($cacheKey, $cached, "10days");
	}

	return ($body, $mtime, $inode, $size, $requestedContentType);
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
