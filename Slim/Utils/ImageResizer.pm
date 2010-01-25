package Slim::Utils::ImageResizer;

use strict;

use constant ISWINDOWS => ( $^O =~ /^m?s?win/i ) ? 1 : 0;

use GD;

# rotation methods matching the EXIF Orientation flag
my %orientationToRotateMethod = (
#	2 => 'copyFlipHorizontal',
	3 => 'copyRotate180',
#	4 => 'copyFlipVertical',
	6 => 'copyRotate90',
	8 => 'copyRotate270',
);

my $hasEXIF;

my %typeToMethod = (
	'gif' => 'newFromGifData',
	'jpg' => 'newFromJpegData',
	'png' => 'newFromPngData',
);

# XXX: see if we can remove all modes besides pad/max

=head1 ($dataref, $format) = resize( %args )

Supported args:
	original => $dataref, # Required, original image data as a scalar ref
	mode     => $mode     # Optional, resize mode:
						  #   m: max         (default)
						  #   p: pad         (same as max)
						  #   s: stretch
						  #   S: squash
						  #   f: fitstretch
						  #   F: fitsquash
						  #   c: crop
						  #   o: original
	format   => $format   # Optional, output format (png, jpg, gif)
	                      #   Defaults to jpg if source is jpg, otherwise png
	width    => $width    # Output size.  One of width or height is required
	height   => $height   #
	bgcolor  => $bgcolor  # Optional, background color to use
	faster   => 1         # Optional, use fast but ugly copyResized function
	debug    => 1         # Optional, print debug messages during resize

Returns an array with the resized image data as a scalar ref, and the image format.

=cut

sub resize {
	my ( $class, %args ) = @_;
	
	my $origref = $args{original};
	my $format  = $args{format};
	my $width   = $args{width};
	my $height  = $args{height};
	my $bgcolor = $args{bgcolor};
	my $mode    = $args{mode};
	my $debug   = $args{debug} || 0;
	
	# Remember if user requested a specific format
	my $explicit_format = $format;
	
	# Format of original image
	my $in_format = _content_type($origref);
	
	# Ignore width/height of 'X'
	$width  = undef if $width eq 'X';
	$height = undef if $height eq 'X';
	
	# Short-circuit if no width/height specified, return original image
	if ( !$width && !$height ) {
		return ($origref, $in_format);
	}
	
	# Abort if invalid params
	if ( ($width && $width !~ /^\d+$/) || ($height && $height !~ /^\d+$/) ) {
		return ($origref, $in_format);
	}
	
	if ( !$bgcolor ) {
		$bgcolor = 'FFFFFF';
	}
	
	# Fixup bgcolor and convert from hex
	if ( length($bgcolor) != 6 && length($bgcolor) != 8 ) {
		$bgcolor = 'FFFFFF';
	}
	$bgcolor = hex $bgcolor;
	
	if ( !$mode ) {
		# default mode is always max
		$mode = 'm';
	}
	
	# optionally load Image::ExifTool to automatically rotate images if possible
	# load late as it might be provided by some plugin instead of the system
	if ( !defined $hasEXIF ) {
		$hasEXIF = 0;
		eval {
			require Image::ExifTool;
			$hasEXIF = 1;
		};
	}

	my $orientation;
	if ( $hasEXIF && $in_format eq 'jpg' ) {
		$orientation = Image::ExifTool::ImageInfo($origref, 'Orientation#', { FastScan => 2 });
	}
		
	# Bug 6458, filter JPEGs on win32 through Imager to handle any corrupt files
	# XXX: Remove this when we get a newer build of GD
	if ( ISWINDOWS && $in_format eq 'jpg' ) {
		require Imager;
		my $img = Imager->new;
		eval {
			$img->read( data => $$origref ) or die $img->errstr;
			$img->write( data => $origref, type => 'jpeg', jpegquality => 100 ) or die $img->errstr;
		};
		if ( $@ ) {
			die "Unable to process JPEG image using Imager: $@\n";
		}
	}
	
	GD::Image->trueColor(1);

	my $constructor = $typeToMethod{$in_format};
	my $origImage   = GD::Image->$constructor($$origref);
	
	# rotate image if original had rotation information
	if ( $orientation && $orientation->{Orientation} && (my $rotateMethod = $orientationToRotateMethod{$orientation->{Orientation}}) ) {
		$origImage = $origImage->$rotateMethod();
		$debug && warn "  Rotating image based on EXIF data using $rotateMethod()\n";
	}
		
	my ($in_width, $in_height) = ($origImage->width, $origImage->height);

	# Output format
	if ( !$format ) {
		if ( $in_format eq 'jpg' ) {
			$format = 'jpg';
		}
		else {
			$format = 'png';
		}
	}
	
	# Determine output size
	my ($out_width, $out_height);

	# if no value is supplied for the width (height) then the returned image's width (height)
	# is chosen to maintain the aspect ratio of the original.  This only makes sense with 
	# a resize mode of 'stretch' or 'squash'
	if ( !$width ) {
		# only height specified
		$out_width  = $in_width / $in_height * $height;
		$out_height = $height;
	}
	elsif ( !$height ) {
		# only width specified
		$out_width  = $width;
		$out_height = $in_height / $in_width * $width;
	}
	else {
		# both width/height specified
		$out_width  = $width;
		$out_height = $height;

		if ( $mode =~ /[Ff]/ ) { # fitstretch, fitsquash
			my @r = _getResizeCoords($in_width, $in_height, $out_width, $out_height);
			($out_width, $out_height) = ($r[2], $r[3]);
			$debug && warn "output changed to ${out_width}x${out_height}\n";
		}
	}
	
	# if the image is a png, it still needs to be processed in case it has an alpha channel
	# hence, if we're squashing the image, the size of the returned image needs to be corrected
	if ( $mode =~ /[SF]/ && $out_width > $in_width && $out_height > $in_height ) {
		$out_width  = $in_width;
		$out_height = $in_height;
	}
	
	# the image needs to be processed if the sizes differ, or the image is a png
	if ( $format eq 'png' || $out_width != $in_width || $out_height != $in_height ) {
		# determine source and destination upper left corner and width / height
		my ($sourceX, $sourceY, $sourceWidth, $sourceHeight) = (0, 0, $in_width, $in_height);
		my ($destX, $destY, $destWidth, $destHeight)         = (0, 0, $out_width, $out_height);

		if ( $mode =~ /[sSfF]/ ) { # stretch or squash
			# no change
		}
		elsif ( $mode eq 'c' ) { # crop
			($sourceX, $sourceY, $sourceWidth, $sourceHeight) = 
				_getResizeCoords($out_width, $out_height, $in_width, $in_height);

			$debug && warn "cropped source to $sourceX, $sourceY, input ${sourceWidth}x${sourceHeight}\n";
		}
		elsif ( $mode eq 'o' ) { # original
			# For resize mode 'o', maintain the original aspect ratio.
			# The requested height value is not used in this case
			if ( $sourceWidth > $sourceHeight ) {
				$destHeight = $sourceHeight / ( $sourceWidth / $out_width );
			}
			elsif ( $sourceHeight > $sourceWidth ) {
				$destWidth  = $sourceWidth / ( $sourceHeight / $out_width );
				$destHeight = $out_width;
			}
			else {
				$destWidth = $destHeight = $out_width;
			}
			
			$out_width  = $destWidth;
			$out_height = $destHeight;

			$debug && warn "original mode using ${destWidth}x${destHeight}\n";
		}
		elsif ( $mode eq 'm' || $mode eq 'p' ) { # max
			# For resize mode 'm', maintain the original aspect ratio.
			# Return the largest image which fits within the size specified
			($destX, $destY, $destWidth, $destHeight) = 
				_getResizeCoords($in_width, $in_height, $out_width, $out_height);
			
			$debug && warn "max mode: ${destWidth}x${destHeight} @ ($destX, $destY)\n";
			
			# Switch to png if there is any blank padded space
			if ( !$explicit_format ) {
				# Maintain jpeg if source is jpeg and output is square with no padding
				if ( $in_format eq 'jpg' && $out_width == $out_height && !$destX && !$destY ) {
					$debug && warn "keeping jpeg due to square output\n";
					$format = 'jpg';
				}
				# Switch to png if there is any blank padded space
				elsif ( $out_width != $destWidth || $out_height != $destHeight ) {
					$debug && warn "switched to png output due to blank padding\n";
					$format = 'png';
				}
			}
		}

		# GD doesn't round correctly
		$destHeight = _round($destHeight);
		$destWidth  = _round($destWidth);
		$out_height = _round($out_height);
		$out_width  = _round($out_width);

		my $newImage = GD::Image->new($out_width, $out_height);

		# PNG with 7 bit transparency
		if ( $format eq 'png' ) {
			$newImage->saveAlpha(1);
			$newImage->alphaBlending(0);
			$newImage->filledRectangle(0, 0, $out_width, $out_height, 0x7f000000);
		}
		# GIF with 1-bit transparency
		elsif ( $format eq 'gif' ) {
			# a transparent gif has to choose a color to be transparent, so let's pick one at random
			$newImage->filledRectangle(0, 0, $out_width, $out_height, 0xaaaaaa);
			$newImage->transparent(0xaaaaaa);
		}
		# not transparent
		else {
			if ( $mode ne 'o' ) {
				$newImage->filledRectangle(0, 0, $out_width, $out_height, $bgcolor);
			}
		}
		
		$debug && warn "Resizing: $in_format => $format, mode $mode, " 
			. "${sourceWidth}x${sourceHeight} @ ($sourceX, $sourceY) => "
			. "${out_width}x${out_height} inner ${destWidth}x${destHeight} @ ($destX, $destY), "
			. "bgcolor $bgcolor\n";

		if ( $args{faster} ) {
			# copyResampled is very ugly but fast
			$newImage->copyResized(
				$origImage,
				$destX, $destY,
				$sourceX, $sourceY,
				$destWidth, $destHeight,
				$sourceWidth, $sourceHeight
			);

			$debug && warn "Resized using fast copyResized\n";
		}
		else {
			if (0) {
	 		# XXX needs more work, i.e. does not do transparency
			if ( $destWidth * FASTGD_QUALITY < $sourceWidth || $destHeight * FASTGD_QUALITY < $sourceHeight ) {
				# Combination of copyResampled plus copyResized provides the best
				# performance and quality.  Based on some code from
				# http://us.php.net/manual/en/function.imagecopyresampled.php#77679
				# Unfortunately, it also uses more memory...
				my $temp = GD::Image->new(
					$destWidth  * FASTGD_QUALITY + 1,
					$destHeight * FASTGD_QUALITY + 1
				);

				$temp->copyResized(
					$origImage,
					0, 0,
					$sourceX, $sourceY,
					$destWidth * FASTGD_QUALITY + 1,
					$destHeight * FASTGD_QUALITY + 1,
					$sourceWidth, $sourceHeight
				);

				$newImage->copyResampled(
					$temp,
					$destX, $destY,
					0, 0,
					$destWidth, $destHeight,
					$destWidth * FASTGD_QUALITY, $destHeight * FASTGD_QUALITY
				);

				$debug && warn "Resized using fast combo method\n";
			}
			}
			else {
				$newImage->copyResampled(
					$origImage,
					$destX, $destY,
					$sourceX, $sourceY,
					$destWidth, $destHeight,
					$sourceWidth, $sourceHeight
				);
				
				$debug && warn "Resized using slow copyResampled\n";
			}
		}

		my $out;

		if ( $format eq 'png' ) {
			$out = $newImage->png;
			$format = 'png';
		}
		elsif ( $format eq 'gif' ) {
			$out = $newImage->gif;
			$format = 'gif';
		}
		else {
			$out = $newImage->jpeg(90);
			$format = 'jpg';
		}
		
		return (\$out, $format);
	}
	
	# Return original image unchanged
	return ($origref, $in_format);
}

sub getSize {
	my $class = shift;
	my $ref   = shift;

	my $in_format = _content_type($ref);

	if (my $constructor = $typeToMethod{$in_format}) {

		if (my $image = GD::Image->$constructor($$ref)) {

			return ($image->width, $image->height);
		}
	}

	return (0, 0);
}

sub _content_type {
	my $dataref = shift;
	
	my $ct;
	
	my $magic = substr $$dataref, 0, 8;
	if ( $magic =~ /^\x89PNG\x0d\x0a\x1a\x0a/ ) {
		$ct = 'png';
	}
	elsif ( $magic =~ /^GIF(?:\d\d)[a-z]/ ) {
		$ct = 'gif';
	}
	elsif ( $magic =~ /^\xff\xd8/ ) {
		$ct = 'jpg';
	}
	else {
		# Unknown file type, don't try to resize
		require Data::Dump;
		die "Can't resize unknown type, magic: " . Data::Dump::dump($magic) . "\n";
	}
	
	return $ct;
}

sub _getResizeCoords {
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
	}
	else {
		$destY = 0;
		$destHeight = $destImageHeight;
		$destWidth = $destImageHeight * $sourceImageAR;
		$destX = ($destImageWidth - $destWidth) / 2
	}

	return ($destX, $destY, $destWidth, $destHeight);
}

sub _round {
	my $number = shift;
	return int($number + .5 * ($number <=> 0));
}

1;
