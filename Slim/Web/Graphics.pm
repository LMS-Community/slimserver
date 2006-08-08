package Slim::Web::Graphics;

use strict;

use Scalar::Util qw(blessed);

use Slim::Utils::Misc;
use Slim::Utils::Cache;

my %typeToMethod = (
	'image/gif'  => 'newFromGifData',
	'image/jpeg' => 'newFromJpegData',
	'image/png'  => 'newFromPngData',
);

{
	# Artwork resizing support by using GD, requires JPEG support built in
	my $canUseGD = eval {
		require GD;
		if (GD::Image->can('jpeg')) {
			return 1;
		} else {
			return 0;
		}
	};

	sub serverResizesArt {
		return $canUseGD;
	}
}

sub processCoverArtRequest {
	my ($client, $path) = @_;

	my ($body, $mtime, $inode, $size, $contentType); 

	# Allow the client to specify dimensions, etc.
	$path =~ /music\/(\w+)\/(cover|thumb)(?:_(X|\d+)x(X|\d+))?(?:_([sSfFpc]))?(?:_([\da-fA-F]{6,8}))?\.jpg$/;

	my $trackid             = $1;
	my $image               = $2;
	my $requestedWidth      = $3; # it's ok if it didn't match and we get undef
	my $requestedHeight     = $4; # it's ok if it didn't match and we get undef
	my $resizeMode          = $5; # stretch, pad or crop
	my $requestedBackColour = defined($6) ? hex $6 : 0x7FFFFFFF; # bg color used when padding

	if (!defined $resizeMode) {
		$resizeMode = '';
	}

	# It a size is specified then default to stretch, else default to squash
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

	} else {

		$obj = Slim::Schema->find('Track', $trackid);
	}

	$::d_artwork && msg("Cover Art asking for trackid: $trackid - $image" . 
		($requestedWidth ? (" at size " . $requestedWidth . "x" . $requestedHeight) : "") . "\n");

	if (blessed($obj) && $obj->can('coverArt')) {

		$cacheKey = join('-', $trackid, $resizeMode, $requestedWidth, $requestedHeight, $requestedBackColour);

		$::d_artwork && msg("  artwork cache key: $cacheKey\n");

		$cachedImage = Slim::Utils::Cache->new()->get($cacheKey);
		
		if ($cachedImage && $cachedImage->{'mtime'} != $obj->coverArtMtime($image)) {
			$cachedImage = undef;
		}

		unless ($cachedImage) {

			($imageData, $contentType, $mtime) = $obj->coverArt($image);
		}
	}

	unless ($cachedImage || $imageData) {
		
		$::d_artwork && msg("  missing artwork replaced by placeholder.\n");

		$cacheKey = "BLANK-$resizeMode-$requestedWidth-$requestedHeight-$requestedBackColour";	

		$cachedImage = Slim::Utils::Cache->new()->get($cacheKey);

		unless ($cachedImage) {

			($body, $mtime, $inode, $size) = Slim::Web::HTTP::getStaticContent("html/images/cover.png");
			$contentType = "image/png";
			$imageData = $$body;
		}
	}

	if ($cachedImage) {

		$::d_artwork && msg("  returning cached artwork image.\n");

		return ($cachedImage->{'body'}, $cachedImage->{'mtime'}, $inode, $cachedImage->{'size'}, $cachedImage->{'contentType'});
	}

	$::d_artwork && msg("  got cover art image $contentType of ". length($imageData) . " bytes\n");

	if (serverResizesArt() && $typeToMethod{$contentType}) {

		# If this is a thumb, a size has been given, or this is a png and the background color isn't 100% transparent
		# then the overhead of loading the image with GD is necessary.  Otherwise, the original content
		# can be passed straight through.
		if ($image eq "thumb" || $requestedWidth || ($contentType eq "image/png" && ($requestedBackColour >> 24) != 0x7F)) {

			# Bug: 3850 - new() can't auto-identify the
			# ContentType (for things like non-JFIF JPEGs) - but
			# we already have. So use the proper constructor for
			# the CT. Set the image to true color.

			GD::Image->trueColor(1);

			my $constructor = $typeToMethod{$contentType};
			my $origImage   = GD::Image->$constructor($imageData);

			if ($origImage) {

				# deterime the size and of type image to be returned
				my $returnedWidth;
				my $returnedHeight;
				my ($returnedType) = $contentType =~ /\/(\w+)/;

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
							$returnedWidth = Slim::Utils::Prefs::get('thumbSize') || 100;
							$cacheKey = undef;
						}
						unless (defined($returnedHeight)) {
							$returnedHeight = Slim::Utils::Prefs::get('thumbSize') || 100;
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
				if ($contentType eq "image/png" || $returnedWidth != $origImage->width || $returnedHeight != $origImage->height) {

					$::d_artwork && msg("  resizing from " . $origImage->width . "x" . $origImage->height . " to " 
						 . $returnedWidth . "x" . $returnedHeight ." using " . $resizeMode . "\n");

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

					$newImage->alphaBlending(0);
					$newImage->filledRectangle(0, 0, $returnedWidth, $returnedHeight, $requestedBackColour);

					$newImage->alphaBlending(1);
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
					if ($returnedType eq "png" && GD::Image->can('png')) {

						$newImage->saveAlpha(1);
						$newImageData = $newImage->png;
						$contentType = 'image/png';

					} else {

						$newImageData = $newImage->jpeg;
						$contentType = 'image/jpeg';
					}

					$::d_artwork && msg("  outputting cover art image $contentType of ". length($newImageData) . " bytes\n");
					$body = \$newImageData;

				} else {

					$::d_artwork && msg("  not resizing\n");
					$body = \$imageData;
				}

			} else {

				$::d_artwork && msg("GD wouldn't create image object\n");
				$body = \$imageData;
			}

		} else {

			$::d_artwork && msg("no need to process image\n");
			$body = \$imageData;
		}

	} else {

		$::d_artwork && msg("can't use GD\n");
		$body = \$imageData;
	}

	if ($cacheKey) {
	
		my $cached = {
			'mtime'       => $mtime,
			'body'        => $body,
			'contentType' => $contentType,
			'size'        => $size,
		};

		$::d_artwork && msg("  caching result key: $cacheKey\n");

		Slim::Utils::Cache->new()->set($cacheKey, $cached, "10days");
	}

	return ($body, $mtime, $inode, $size, $contentType);
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
