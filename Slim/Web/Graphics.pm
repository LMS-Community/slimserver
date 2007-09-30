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

	my ($body, $mtime, $inode, $size, $contentType); 

	# Allow the client to specify dimensions, etc.
	$path =~ /music\/(\w+)\//;
	my $trackid = $1;

	my $imgName = File::Basename::basename($path);
	my ($imgBasename, $dirPath, $suffix)  = File::Basename::fileparse($path, '\..*');
	my $actualPathToImage;

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
	$imgName =~ /(cover|thumb|[A-Za-z0-9]+)		# image name is first string before resizing parameters
			(?:_(X|\d+)x(X|\d+))?	# width and height are given here, e.g. 300x300
			(?:_([sSfFpc]))?	# resizeMode, given by a single character
			(?:_([\da-fA-F]+))? # background color, optional
			\.(jpg|png|gif)$		# file suffixes allowed are jpg png gif
			/x;	

	my $image               = $1;
	my $requestedWidth      = $2; # it's ok if it didn't match and we get undef
	my $requestedHeight     = $3; # it's ok if it didn't match and we get undef
	my $resizeMode          = $4; # stretch, pad or crop
	my $bgColor             = defined($5) ? $5 : '000000';
	my @bgColor             = split(//, $bgColor);
	if (scalar(@bgColor) != 6 && scalar(@bgColor) != 8) {
		$log->info("BG color was not defined correctly. Defaulting to 000000 (white)");
		$bgColor = '000000';
	}

	my $requestedBackColour = hex $bgColor; # bg color used when padding

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

	} elsif ($trackid eq 'notCoverArt') {

		#($body, $cachedImage->{'mtime'}, $inode, $cachedImage->{'size'}) = Slim::Web::HTTP::getStaticContent($actualPathToImage);
		#$cachedImage->{'body'} = $body;
		#$cachedImage->{'contentType'} = "image/" . $suffix;

		($body, $mtime, $inode, $size) = Slim::Web::HTTP::getStaticContent($actualPathToImage);
		$contentType = "image/" . $suffix;
		$contentType =~ s/\.//;
		$imageData = $$body;
		
	} else {

		$obj = Slim::Schema->find('Track', $trackid);
	}

	if ( $log->is_info ) {
		$log->info("Asking for trackid: $trackid - $image" . 
			($requestedWidth ? (" at size " . $requestedWidth . "x" . $requestedHeight) : ""));
	}

	if (blessed($obj) && $obj->can('coverArt')) {

		$cacheKey = join('-', $trackid, $resizeMode, $requestedWidth, $requestedHeight, $requestedBackColour);

		$log->info("  artwork cache key: $cacheKey");

		$cachedImage = $cache->get($cacheKey);
		
		if ($cachedImage && $cachedImage->{'mtime'} != $obj->coverArtMtime($image)) {
			$cachedImage = undef;
		}

		if (!$cachedImage) {

			($imageData, $contentType, $mtime) = $obj->coverArt;
		}
	}

	if ( (!$cachedImage && !$imageData) ) {

		my $image = blessed($obj) && $obj->remote ? 'radio' : 'cover';
		
		$log->info("  missing artwork replaced by placeholder.");

		$cacheKey = "$image-$resizeMode-$requestedWidth-$requestedHeight-$requestedBackColour";	

		$cachedImage = $cache->get($cacheKey);

		unless ($cachedImage) {

			($body, $mtime, $inode, $size) = Slim::Web::HTTP::getStaticContent("html/images/$image.png");
			$contentType = "image/png";
			$imageData = $$body;
		}
	}

	if ($cachedImage) {

		$log->info("  returning cached artwork image.");

		return ($cachedImage->{'body'}, $cachedImage->{'mtime'}, $inode, $cachedImage->{'size'}, $cachedImage->{'contentType'});
	}

	if ( $log->is_info ) {
		$log->info("  got cover art image $contentType of ". length($imageData) . " bytes");
	}

	if ($canUseGD && $typeToMethod{$contentType}) {

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
				if ($contentType eq "image/png" || $returnedWidth != $origImage->width || $returnedHeight != $origImage->height) {

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

					if ( $log->is_info ) {
						$log->info("  outputting cover art image $contentType of ". length($newImageData) . " bytes");
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
			'contentType' => $contentType,
			'size'        => $size,
		};

		$log->info("  caching result key: $cacheKey");

		$cache->set($cacheKey, $cached, "10days");
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
