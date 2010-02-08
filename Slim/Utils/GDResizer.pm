package Slim::Utils::GDResizer;

use strict;

use constant ISWINDOWS => ( $^O =~ /^m?s?win/i ) ? 1 : 0;

use GD;

my %typeToMethod = (
	'gif' => 'newFromGifData',
	'jpg' => 'newFromJpegData',
	'png' => 'newFromPngData',
);

my %typeToFileMethod = (
	'gif' => 'newFromGif',
	'jpg' => 'newFromJpeg',
	'png' => 'newFromPng',
);

# rotation methods matching the EXIF Orientation flag
my %orientationToRotateMethod = (
#	2 => 'copyFlipHorizontal',
	3 => 'copyRotate180',
#	4 => 'copyFlipVertical',
	6 => 'copyRotate90',
	8 => 'copyRotate270',
);

my $debug;
my $hasEXIF;

# XXX: see if we can remove all modes besides pad/max

=head1 ($dataref, $format) = resize( %args )

Supported args:
	original => $dataref  # Optional, original image data as a scalar ref
	file     => $path     # Optional, File path to resize from. May be an image or audio file.
	                      #   If an audio file, artwork is extracted from tags based on the
	                      #   file extension.
	                      # One of original or file is required.
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
	my $file    = $args{file};
	my $format  = $args{format};
	my $width   = $args{width}  || 'X';
	my $height  = $args{height} || 'X';
	my $bgcolor = $args{bgcolor};
	my $mode    = $args{mode};
	
	$debug      = $args{debug} if defined $args{debug};
	
	if ( $file && !-e $file ) {
		die "Unable to resize from $file: File does not exist\n";
	}
	
	# Load image data from tags if necessary
	if ( $file && $file !~ /\.(?:jpe?g|gif|png)$/i ) {
		# Double-check that this isn't an image file
		if ( !_content_type_file($file, 1) ) {
			$origref = _read_tag($file);
		
			if ( !$origref ) {
				die "Unable to find any image tag in $file\n";
			}

			$file = undef;
		}
	}
	
	# Remember if user requested a specific format
	my $explicit_format = $format;
	
	# Format of original image
	my $in_format = $file ? _content_type_file($file) : _content_type($origref);
	
	# Ignore width/height of 'X'
	$width  = undef if $width eq 'X';
	$height = undef if $height eq 'X';
	
	# Short-circuit if no width/height specified, and formats match, return original image
	if ( !$width && !$height ) {
		if ( !$explicit_format || ($explicit_format eq $in_format) ) {
			return $file ? (_slurp($file), $in_format) : ($origref, $in_format);
		}
	}
	
	# Abort if invalid params
	if ( ($width && $width !~ /^\d+$/) || ($height && $height !~ /^\d+$/) ) {
		return $file ? (_slurp($file), $in_format) : ($origref, $in_format);
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
		$orientation = Image::ExifTool::ImageInfo($file || $origref, 'Orientation#', { FastScan => 2 });
	}
	
	# Bug 6458, filter JPEGs on win32 through Imager to handle any corrupt files
	# XXX: Remove this when we get a newer build of GD
	if ( ISWINDOWS && $in_format eq 'jpg' ) {
		require Imager;
		my $img = Imager->new;
		my $orig;
		eval {
			if ( $file ) {
				$img->read( file => $file ) or die $img->errstr;
				$file = undef;
				$origref = \$orig;
			}
			else {
				$img->read( data => $$origref ) or die $img->errstr;
			}
			$img->write( data => $origref, type => 'jpeg', jpegquality => 100 ) or die $img->errstr;
		};
		if ( $@ ) {
			die "Unable to process JPEG image using Imager: $@\n";
		}
	}
	
	GD::Image->trueColor(1);
	
	if ( $debug && $file ) {
		warn "Loading image from $file\n";
	}

	my $constructor = $file ? $typeToFileMethod{$in_format} : $typeToMethod{$in_format};
	
	my $origImage;
	
	# Use JPEG scaling if available
	# Tests if an XS-only method is available so that the presence of our custom GD::Image won't break things
	if ( $in_format eq 'jpg' && ($width || $height) ) {
		if ( GD::Image->can('_newFromJpegScaled') ) {
			$debug && warn "  Using JPEG scaling (target ${width}x${height})\n";
			my $constructor_scaled = $constructor . 'Scaled';
			$origImage = GD::Image->$constructor_scaled($file || $$origref, $width, $height);
			$debug && warn "  Got pre-scaled image of size " . $origImage->width . "x" . $origImage->height . "\n";
		}
	}
	
	if ( !$origImage ) {
		$origImage = GD::Image->$constructor($file || $$origref);
	}
	
	# rotate image if original image had rotation information stored in the EXIF data
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
	if ( !$width && !$height ) {
		# no size specified, retain original size
		$out_width  = $in_width;
		$out_height = $in_height;
	}
	elsif ( !$width ) {
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

		main::idleStreams() unless main::RESIZER;
		
		if ( $args{faster} ) {
			# copyResized is very ugly but fast
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

		main::idleStreams() unless main::RESIZER;

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

=head1 resizeSeries( %args )

Supported args:
	... same as resize() ...
	series => [
		{ width => X, height => Y, mode => Z },
		...
	],

Resize the same image multiple times in descending size order,
using the result of the previous resize as input for the next.
Can dramatically speed up the creation of different sized thumbnails.

Returns arrayref of [ resized image data as a scalar ref, image format, width, height, mode ].

=cut

sub resizeSeries {
	my ( $class, %args ) = @_;
	
	my @series  = sort { $b->{width} <=> $a->{width} } @{ delete $args{series} };

	$debug      = $args{debug} if defined $args{debug};
	
	my @ret;
	
	for my $next ( @series ) {
		$args{width}  = $next->{width};
		$args{height} = $next->{height} || $next->{width};
		$args{mode}   = $next->{mode}   if $next->{mode};
			
		$debug && warn "Resizing series: " . $args{width} . 'x' . $args{height} . "\n";
			
		my ($resized_ref, $format) = $class->resize( %args );
		
		delete $args{file};
		$args{original} = $resized_ref;
		
		push @ret, [ $resized_ref, $format, $args{width}, $args{height}, $args{mode} ];
	}
	
	return wantarray ? @ret : \@ret;
}

sub _read_tag {
	my $file = shift;
	
	require Audio::Scan;
	
	local $ENV{AUDIO_SCAN_NO_ARTWORK} = 0;
	
	my $s = eval { Audio::Scan->scan_tags($file) };
	if ( $@ ) {
		die "Unable to read image tag from $file: $@\n";
	}
	
	my $tags = $s->{tags};
	
	# MP3, other files with ID3v2
	if ( my $pic = $tags->{APIC} ) {
		if ( ref $pic->[0] eq 'ARRAY' ) {
			# multiple images, return image with lowest image_type value
			return \(( sort { $a->[2] <=> $b->[2] } @{$pic} )[0]->[4]);
		}
		else {
			return \($pic->[4]);
		}
	}
	
	# FLAC picture block
	if ( $tags->{ALLPICTURES} ) {
		return \($tags->{ALLPICTURES}->[0]->{image_data});
	}
	
	# FLAC/Ogg base64 coverart
	if ( $tags->{COVERART} ) {
		require MIME::Base64;
		my $artwork = eval { MIME::Base64::decode_base64( $tags->{COVERART} ) };
		if ( $@ ) {
			die "Unable to read image tag from $file: $@\n";
		}
		return \$artwork;
	}
	
	# ALAC/M4A
	if ( $tags->{COVR} ) {
		return \($tags->{COVR});
	}
	
	# WMA
	if ( my $pic = $tags->{'WM/Picture'} ) {
		if ( ref $pic eq 'ARRAY' ) {
			# return image with lowest image_type value
			return \(( sort { $a->{image_type} <=> $b->{image_type} } @{$pic} )[0]->{image});
		}
		else {
			return \($pic->{image});
		}
	}
	
	# APE
	if ( $tags->{'COVER ART (FRONT)'} ) {
		return \($tags->{'COVER ART (FRONT)'});
	}
	
	# Escient artwork app block (who uses this??)
	if ( $tags->{APPLICATION} && $tags->{APPLICATION}->{1163084622} ) {
		my $artwork = $tags->{APPLICATION}->{1163084622};
		if ( substr($artwork, 0, 4, '') eq 'PIC1' ) {
			return \$artwork;
		}
	}
	
	return;
}

sub _content_type_file {
	my $file = shift;
	
	open my $fh, '<', $file;
	sysread $fh, my $buf, 8;
	close $fh;
	
	return _content_type(\$buf, @_);
}

sub _content_type {
	my ( $dataref, $silent ) = @_;
	
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
		if ( !$silent ) {
			require Data::Dump;
			die "Can't resize unknown type, magic: " . Data::Dump::dump($magic) . "\n";
		}
		
		return;
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

sub _slurp {
	my $file = shift;
	
	require File::Slurp;
	
	my $data = File::Slurp::read_file($file);
	return \$data;
}

sub gdresize {
	my ($class, %args) = @_;
	
	my $file     = $args{'file'};
	my $spec     = $args{'spec'};
	my $cache    = $args{'cache'};
	my $cachekey = $args{'cachekey'};
	
	$debug       = $args{'debug'};
	
	if ( @$spec > 1 ) {
		# Resize in series
		
		# Construct spec hashes
		my $specs = [];
		for my $s ( @$spec ) {
			my ($width, $height, $mode) = $s =~ /^([^x]+)x([^_]+)_(\w)$/;
			
			if ( !$width || !$height || !$mode ) {
				die "Invalid spec: $s\n";
			}
			
			push @{$specs}, {
				width  => $width,
				height => $height,
				mode   => $mode,
			};
		}
			
		my $series = eval {
			$class->resizeSeries(
				file   => $file,
				series => $specs,
				faster => $args{'faster'},
			);
		};
		
		if ( $@ ) {
			die "$@\n";
		}
		
		if ( $cache && $cachekey ) {
			for my $s ( @{$series} ) {
				my $width  = $s->[2];
				my $height = $s->[3];
				my $mode   = $s->[4];
			
				# Series-based resize has to append to the cache key
				my $key = $cachekey;
				$key .= "${width}x${height}_${mode}";
			
				_cache( $cache, $key, $s->[0], $file, $s->[1] );
			}
		}
	}
	else {
		my ($width, $height, $mode, $bgcolor, $ext) = $spec->[0] =~ /^([^x]+)x([^_]+)(?:_(\w))?(?:_([\da-fA-F]+))?\.?(\w+)?$/;
		
		# XXX If cache is available, pull pre-cached size values from cache
		# to see if we can use a smaller version of this image than the source
		# to reduce resizing time.
		
		my ($ref, $format) = eval {
			$class->resize(
				file    => $file,
				faster  => $args{'faster'},
				width   => $width,
				height  => $height,
				mode    => $mode,
				bgcolor => $bgcolor,
				format  => $ext,
			);
		};
		
		if ( $@ ) {
			die "$@\n";
		}
		
		if ( $cache && $cachekey ) {
			# When doing a single resize, the cachekey passed in is all we store
			_cache( $cache, $cachekey, $ref, $file, $format );
		}
	}
}

sub _cache {
	my ( $cache, $key, $imgref, $file, $ct ) = @_;
	
	my $cached = {
		content_type  => $ct,
		mtime         => (stat($file))[9],
		original_path => $file,
		data_ref      => $imgref,
	};

	$cache->set( $key, $cached );
	
	$debug && warn "Cached $key (" . length($$imgref) . " bytes)\n";
}

1;
