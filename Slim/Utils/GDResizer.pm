package Slim::Utils::GDResizer;

use strict;

use Image::Scale;

my $debug;

=head1 ($dataref, $format) = resize( %args )

Supported args:
	original => $dataref  # Optional, original image data as a scalar ref
	file     => $path     # Optional, File path to resize from. May be an image or audio file.
	                      #   If an audio file, artwork is extracted from tags based on the
	                      #   file extension.
	                      # One of original or file is required.
	mode     => $mode     # Optional, resize mode:
						  #   m: max         (default, fit image into given space while keeping aspect ratio)
						  #   p: pad
						  #   o: original    (ignore height if given, resize only based on width)
						  #   F: ???         (return original if req. size is bigger, return downsized if req. size is smaller)
	format   => $format   # Optional, output format (png, jpg)
	                      #   Defaults to jpg if source is jpg, otherwise png
	width    => $width    # Output size.  One of width or height is required
	height   => $height   #
	bgcolor  => $bgcolor  # Optional, background color to use
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
	
	# if $file is a scalar ref, then it's the image data itself
	if ( ref $file && ref $file eq 'SCALAR' ) {
		$origref = $file;
		$file    = undef;
	}
	
	my ($offset, $length) = (0, 0); # used if an audio file is passed in
	my $in_format;
	
	if ( $file && !-e $file ) {
		die "Unable to resize from $file: File does not exist\n";
	}
	
	# Load image data from tags if necessary
	if ( $file && $file !~ /\.(?:jpe?g|gif|png)$/i ) {
		# Double-check that this isn't an image file
		if ( !_content_type_file($file, 0, 1) ) {
			($offset, $length, $origref) = _read_tag($file);
		
			if ( !$offset ) {
				if ( !$origref ) {
					die "Unable to find any image tag in $file\n";
				}
				
				$file = undef;
			}
			# sometimes we get an invalid offset, but Audio::Scan is able to read the image data anyway
			# this is a workaround for this known bug: https://rt.cpan.org/Public/Bug/Display.html?id=95410
			elsif ( !($in_format = _content_type_file($file, $offset, 'silent')) ) {
				($offset, $length, $origref) = _read_data_from_tag($file);
				$file = undef if $origref;
			}
		}
	}
	
	# Remember if user requested a specific format
	my $explicit_format = $format;
	
	# Format of original image
	$in_format ||= $file ? _content_type_file($file, $offset) : _content_type($origref);
	
	# Ignore width/height of 'X'
	$width  = undef if $width eq 'X';
	$height = undef if $height eq 'X';
	
	# Short-circuit if no width/height specified, and formats match, return original image
	if ( !$width && !$height ) {
		if ( !$explicit_format || ($explicit_format eq $in_format) ) {
			return $file ? (_slurp($file, $length ? $offset : undef, $length || undef), $in_format) : ($origref, $in_format);
		}
	}
	
	# Abort if invalid params
	if ( ($width && $width !~ /^\d+$/) || ($height && $height !~ /^\d+$/) ) {
		return $file ? (_slurp($file, $length ? $offset : undef, $length || undef), $in_format) : ($origref, $in_format);
	}
	
	# Fixup bgcolor and convert from hex
	if ( $bgcolor && length($bgcolor) != 6 && length($bgcolor) != 8 ) {
		$bgcolor = 0xFFFFFF;
	}
	
	if ( !$mode ) {
		# default mode is always max
		$mode = 'm';
	}
	
	if ( $debug && $file ) {
		warn "Loading image from $file\n";
	}
	
	my $im = $file
		? Image::Scale->new( $file, { offset => $offset, length => $length } )
		: Image::Scale->new($origref);
	
	my ($in_width, $in_height) = ($im->width, $im->height);

	# Output format
	if ( !$format ) {
		if ( $in_format eq 'jpg' ) {
			$format = 'jpg';
		}
		else {
			$format = 'png';
		}
	}
	
	if ( !$width && !$height ) {
		$width = $in_width;
		$height = $in_height;
	}
	
	main::idleStreams() unless main::RESIZER;
	
	if ( $mode eq 'm' || $mode eq 'p' ) {
		# Bug 17140, switch to png if image will contain any padded space
		if ( $format ne 'png' ) {
			if ( $width && $in_width && ($in_height / $in_width) != ($height / $width) ) {
				$format = 'png';
			}
			elsif ( $height && $in_height && ($in_width / $in_height) != ($width / $height) ) {
				$format = 'png';
			}
		}

		# requested size is larger than original - don't upscale
		if ( $width > $in_width && $height > $in_height ) {
			if ( $in_height / $in_width > 1 ) {
				$height = $height * ($in_width / $width);
				$width  = $in_width;
			}
			else {
				$width  = $width * ($in_height / $height);
				$height = $in_height;
			}
		}
	
		$debug && warn "Resizing from ${in_width}x${in_height} $in_format @ ${offset} to ${width}x${height} $format\n";
		
		$im->resize( {
			width       => $width,
			height      => $height,
			keep_aspect => 1,
			# XXX memory_limit on SqueezeOS
		} );
	}

	elsif ( $mode eq 'F' ) {
		# Requested size is bigger than original -> return original size
		if (( $width >= $in_width ) && ( $height >= $in_height)) {
			$debug && warn "Return original size ${in_width}x${in_height} $in_format @ ${offset} to ${width}x${height} $format\n";
			$im->resize( {
				width       => $in_width,
				height      => $in_height,
				keep_aspect => 1,
				# XXX memory_limit on SqueezeOS
			} );
		# Requested size is smaller than original -> resize to requested size
		} else {
			$debug && warn "Resizing from ${in_width}x${in_height} $in_format @ ${offset} to ${width}x${height} $format\n";
			$im->resize( {
				width       => $width,
				height      => $height,
				keep_aspect => 1,
				# XXX memory_limit on SqueezeOS
			} );
		}
	}

	else { # mode 'o', only use the width
		$debug && warn "Resizing from ${in_width}x${in_height} $in_format @ ${offset} to ${width}xX $format\n";

		if ( $width > $in_width && $height > $in_height ) {
			if ( $in_height / $in_width > 1 ) {
				$width = $width * ($in_height / $height);
			}
			else {
				$width = $in_width;
			}
		}
		
		$im->resize( {
			width => $width,
			# XXX memory_limit on SqueezeOS
		} );
	}
	
	main::idleStreams() unless main::RESIZER;
	
	my $out;

	if ( $format eq 'png' ) {
		$out = $im->as_png;
		$format = 'png';
	}
	else {
		$out = $im->as_jpeg;
		$format = 'jpg';
	}
	
	return (\$out, $format);
}

sub getSize {
	my $class = shift;
	my $ref   = shift;
	
	my $im = Image::Scale->new($ref) || return (0, 0);
	
	return ($im->width, $im->height);
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
		
		# Don't use source artwork < 100, as this results in blurry images
		if ( !$args{original} || ($args{width} >= 100 && $args{height} >= 100) ) {
			$args{original} = $resized_ref;
		}
		
		push @ret, [ $resized_ref, $format, $args{width}, $args{height}, $args{mode} ];
	}
	
	return wantarray ? @ret : \@ret;
}

sub _read_tag {
	my $file = shift;
	
	my ($offset, $length);
	
	require Audio::Scan;
	
	# First try to get offset/length if possible
	
	local $ENV{AUDIO_SCAN_NO_ARTWORK} = 1;
	
	$debug && warn "Reading tags from audio file...\n";
	
	my $s = eval { Audio::Scan->scan_tags($file) };
	if ( $@ ) {
		die "Unable to read image tag from $file: $@\n";
	}
	
	my $tags = $s->{tags};
	
	# MP3, other files with ID3v2
	if ( my $pic = $tags->{APIC} ) {
		if ( ref $pic->[0] eq 'ARRAY' ) {
			# multiple images, return image with lowest image_type value
			$pic = ( sort { $a->[1] <=> $b->[1] } @{$pic} )[0];
		}
		
		if ( $pic->[4] ) { # offset is available
			return ( $pic->[4], $pic->[3] );
		}
	}
	
	# FLAC/Vorbis picture block
	if ( $tags->{ALLPICTURES} ) {
		my $pic = ( sort { $a->{picture_type} <=> $b->{picture_type} } @{ $tags->{ALLPICTURES} } )[0];
		if ( $pic->{offset} ) {
			return ( $pic->{offset}, $pic->{image_data} );
		}
	}
	
	# ALAC/M4A
	if ( $tags->{COVR} ) {
		return ( $tags->{COVR_offset}, $tags->{COVR} );
	}
	
	# WMA
	if ( my $pic = $tags->{'WM/Picture'} ) {
		if ( ref $pic eq 'ARRAY' ) {
			# return image with lowest image_type value
			$pic = ( sort { $a->{image_type} <=> $b->{image_type} } @{$pic} )[0];
		}
		
		return ( $pic->{offset}, $pic->{image} );
	}
	
	# APE
	if ( $tags->{'COVER ART (FRONT)'} ) {
		return ( $tags->{'COVER ART (FRONT)_offset'}, $tags->{'COVER ART (FRONT)'} );
	}
	
	# Escient artwork app block (who uses this??)
	if ( $tags->{APPLICATION} && $tags->{APPLICATION}->{1163084622} ) {
		my $artwork = $tags->{APPLICATION}->{1163084622};
		if ( substr($artwork, 0, 4, '') eq 'PIC1' ) {
			return (undef, undef, \$artwork);
		}
	}
	
	# We get here if the embedded image is either ID3 APIC with unsync null bytes, or a Vorbis base64 tag
	# In this case we need to re-read the full artwork using Audio::Scan
	
	return _read_data_from_tag($file);
}

sub _read_data_from_tag {
	my $file = shift;
	
	local $ENV{AUDIO_SCAN_NO_ARTWORK} = 0;
	
	$debug && warn "Offset information not found or invalid, re-reading file for direct artwork\n";
	
	my $s = Audio::Scan->scan_tags($file);
	my $tags = $s->{tags};
	
	# MP3, other files with ID3v2
	if ( my $pic = $tags->{APIC} ) {
		if ( ref $pic->[0] eq 'ARRAY' ) {
			# multiple images, return image with lowest image_type value
			$pic = ( sort { $a->[1] <=> $b->[1] } @{$pic} )[0];
		}
		
		return ( undef, undef, \($pic->[3]) );
	}
	
	# Vorbis picture block
	if ( $tags->{ALLPICTURES} ) {
		my $pic = ( sort { $a->{picture_type} <=> $b->{picture_type} } @{ $tags->{ALLPICTURES} } )[0];
		return ( undef, undef, \($pic->{image_data}) );
	}
	
	return;
}

sub _content_type_file {
	my $file = shift;
	my $offset = shift;
	
	open my $fh, '<', $file;
	binmode $fh;
	
	if ($offset) {
		sysseek $fh, $offset, 0;
	}
	
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
	elsif ( $magic =~ /^BM/ ) {
		$ct = 'bmp';
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

sub _slurp {
	my $file = shift;
	my $offset = shift;
	my $data;
	
	open my $fh, '<', $file or die "Cannot open $file";
	binmode $fh;
	
	if ( defined $offset ) {
		my $length = shift;
		# Read only a portion of the file
		sysseek $fh, $offset, 0;
		while ( $length ) {
			my $n = sysread $fh, my $buf, $length > 4096 ? 4096 : $length;
			$data .= $buf;
			$length -= $n;
		}
	}
	else {
		# Read entire file
		$data = do { local $/; <$fh> };
	}
	
	close $fh;
	
	return \$data;
}

sub gdresize {
	my ($class, %args) = @_;
	
	my $file     = $args{file};
	my $spec     = $args{spec};
	my $cache    = $args{cache};
	my $cachekey = $args{cachekey};
	
	$debug       = $args{debug};
	
	if ( @$spec > 1 ) {
		# Resize in series
		
		# Construct spec hashes
		my $specs = [];
		for my $s ( @$spec ) {
			my ($width, $height, $mode) = $s =~ /^([^x]+)x([^_]+)_(\w)$/;
			
			if ( !$width || !$height || !$mode ) {
				warn "Invalid spec: $s\n";
				next;
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
				debug  => $debug,
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
				my $spec = "${width}x${height}_${mode}";
				if (! ($key =~ s/(\.\w{3,4})$/_$spec$1/)) {
					$key .= $spec;
				}
			
				_cache( $cache, $key, $s->[0], $file, $s->[1] );
			}
		}
	}
	else {
		my ($width, $height, $mode, $bgcolor, $ext) = $spec->[0] =~ /^(?:([0-9X]+)x([0-9X]+))?(?:_(\w))?(?:_([\da-fA-F]+))?(?:\.(\w+))?$/;
				
		# XXX If cache is available, pull pre-cached size values from cache
		# to see if we can use a smaller version of this image than the source
		# to reduce resizing time.

		my ($ref, $format);
		eval {
			($ref, $format) = $class->resize(
				file    => $file,
				width   => $width,
				height  => $height,
				mode    => $mode,
				bgcolor => $bgcolor,
				format  => $ext,
				debug   => $debug,
			);
			
			$file = undef if ref $file;
		};
		
		if ( $@ ) {
			die "$@\n";
		}
		
		if ( $cache && $cachekey ) {
			# When doing a single resize, the cachekey passed in is all we store
			# XXX Don't cache images that aren't resized, i.e. /cover.jpg
			_cache( $cache, $cachekey, $ref, $file, $format );
		}

		return ($ref, $format);
	}
}

sub _cache {
	my ( $cache, $key, $imgref, $file, $ct ) = @_;
	
	my $cached = {
		content_type  => $ct,
		mtime         => $file ? (stat($file))[9] : 0,
		original_path => $file,
		data_ref      => $imgref,
	};

	$cache->set( $key, $cached );
	
	$debug && warn "Cached $key (" . length($$imgref) . " bytes)\n";
}

1;
