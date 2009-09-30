#!/usr/bin/perl
#
# Stand-alone image resizer
#
# TODO:
# Better error handling
#

use strict;

use constant RESIZER      => 1;
use constant SLIM_SERVICE => 0;
use constant PERFMON      => 0;
use constant SCANNER      => 0;
use constant ISWINDOWS    => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant DEBUG        => ( grep { /--debug/ } @ARGV ) ? 1 : 0;

use constant FASTGD_QUALITY => 3;

BEGIN {
   use Slim::bootstrap ();
   Slim::bootstrap->loadModules( ['GD'], [] );
};

use Getopt::Long;

if ( DEBUG ) {
	use Time::HiRes qw(time);
}

my $help;
our ($tag, $file, $url);
our ($format, $width, $height, $mode, $bgcolor);
our ($faster, $cacheroot, $save, $debug);

GD::Image->trueColor(1);

my %typeToMethod = (
	'gif' => 'newFromGifData',
	'jpg' => 'newFromJpegData',
	'png' => 'newFromPngData',
);

my $ok = GetOptions(
	'help|?'      => \$help,
	'tag=s'       => \$tag,
	'file=s'      => \$file,
	'url=s'       => \$url,
	'format=s'    => \$format,
	'width=s'     => \$width,
	'height=s'    => \$height,
	'mode=s'      => \$mode,
	'bgcolor=s'   => \$bgcolor,
	'cacheroot=s' => \$cacheroot,
	'faster'      => \$faster,
	'save=s'      => \$save,
	'debug'       => \$debug,
);

if ( !$ok || $help || ( !$tag && !$file && !$url ) || ( !$width && !$height ) ) {
	require Pod::Usage;
	Pod::Usage::pod2usage(0);
}

# Get the raw image data
my $raw;

if ( $tag ) {
	$raw = read_tag($tag);
}
elsif ( $file ) {
	open my $fh, '<', $file or die "ERROR Unable to open $file: $!\n";
	$raw = do { local $/; <$fh> };
	close $fh;
}
elsif ( $url ) {
	$raw = read_url($url);
}

if ( !$raw ) {
	die "No image found in " . ($tag || $file || $url) . "\n";
}

# Format of original image
my $in_format = content_type(\$raw);

# Remember if image should remain transparent
my $transparent = 0;
if ( !$bgcolor ) {
	if ( $in_format eq 'gd' ) { 
		$transparent = 'gd';
	}
	elsif ( $in_format eq 'png' ) {
		$transparent = 'png';
	}
	elsif ( $in_format eq 'gif' ) {
		$transparent = 'gif';
	}
}

if ( length($bgcolor) != 6 && length($bgcolor) != 8 ) {
	$bgcolor = 'FFFFFF';
}
$bgcolor = hex $bgcolor;

if ( !$mode ) {
	# if both width and height are given but no resize mode, resizeMode is pad
	if ( $width && $height ) {
		$mode = 'p';
	}
	elsif ( $width ) {
		$mode = 's';
	}
	else {
		$mode = 'S';
	}
}

# Bug 6458, filter JPEGs on win32 through Imager to handle any corrupt files
# XXX: Remove this when we get a newer build of GD
if ( ISWINDOWS && $in_format eq 'jpg' ) {
	require Imager;
	my $img = Imager->new;
	eval {
		$img->read( data => $raw ) or die $img->errstr;
		$img->write( data => \$raw, type => 'jpeg', jpegquality => 100 ) or die $img->errstr;
	};
	if ( $@ ) {
		die "Unable to process JPEG image using Imager: $@\n";
	}
}

my $constructor = $typeToMethod{$in_format};
my $origImage   = GD::Image->$constructor($raw);


my ($in_width, $in_height) = ($origImage->width, $origImage->height);

# Output format
if ( !$format ) {
	# If no format was given optimize for the common case: square JPEG cover art
	if ( $in_format eq 'jpg' && ( $in_width == $in_height || $mode eq 'o' ) ) {
		$format = 'jpg';
		$transparent = 0;
	}
	else {
		# Default to png
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
		my @r = getResizeCoords($in_width, $in_height, $out_width, $out_height);
		($out_width, $out_height) = ($r[2], $r[3]);
	}
}

# if the image is a png, it still needs to be processed in case it has an alpha channel
# hence, if we're squashing the image, the size of the returned image needs to be corrected
if ( $mode =~ /[SF]/ && $out_width > $in_width && $out_height > $in_height ) {
	$out_width  = $in_width;
	$out_height = $in_height;
}

DEBUG && warn "Resizing: $in_format => $format, mode $mode, " 
	. "${in_width}x${in_height} => ${out_width}x${out_height}, "
	. "transparent $transparent, bgcolor $bgcolor\n"; 

# the image needs to be processed if the sizes differ, or the image is a png
if ( $format =~ /(?:png|gd)/ || $out_width != $in_width || $out_height != $in_height ) {
	# determine source and destination upper left corner and width / height
	my ($sourceX, $sourceY, $sourceWidth, $sourceHeight) = (0, 0, $in_width, $in_height);
	my ($destX, $destY, $destWidth, $destHeight)         = (0, 0, $out_width, $out_height);

	if ( $mode =~ /[sSfF]/ ) { # stretch or squash
		# no change
	}
	elsif ( $mode eq 'p' ) { # pad
		($destX, $destY, $destWidth, $destHeight) = 
			getResizeCoords($in_width, $in_height, $out_width, $out_height);
		
		DEBUG && warn "padded to $destX, $destY, output ${destWidth}x${destHeight}\n";
	}
	elsif ( $mode eq 'c' ) { # crop
		($sourceX, $sourceY, $sourceWidth, $sourceHeight) = 
			getResizeCoords($out_width, $out_height, $in_width, $in_height);
		
		DEBUG && warn "cropped source to $sourceX, $sourceY, input ${sourceWidth}x${sourceHeight}\n";
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
		
		DEBUG && warn "original mode using ${destWidth}x${destHeight}\n";
	}
	
	# GD doesn't round correctly
	$destHeight = round($destHeight);
	$destWidth  = round($destWidth);
	$out_height = round($out_height);
	$out_width  = round($out_width);
	
	if ( $mode ne 'o' ) {
		$destWidth  = $out_width;
		$destHeight = $out_height;
	}
	
	my $newImage = GD::Image->new($destWidth, $destHeight);
	
	# PNG/GD with 7 bit transparency
	if ( $transparent =~ /png|gd/ ) {
		$newImage->saveAlpha(1);
		$newImage->alphaBlending(0);
		$newImage->filledRectangle(0, 0, $out_width, $out_height, 0x7f000000);
	}
	# GIF with 1-bit transparency
	elsif ( $transparent eq 'gif' ) {
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
	
	if ($faster) {
		# copyResampled is very ugly but fast
		DEBUG && (my $start = time);
		
		$newImage->copyResized(
			$origImage,
			$destX, $destY,
			$sourceX, $sourceY,
			$destWidth, $destHeight,
			$sourceWidth, $sourceHeight
		);
		
		if ( DEBUG ) {
			my $diff = time - $start;
			warn "Resized using fast copyResized ($diff)\n";
		}
	}
	else {
=pod XXX needs more work, i.e. does not do transparency
		if ( $destWidth * FASTGD_QUALITY < $sourceWidth || $destHeight * FASTGD_QUALITY < $sourceHeight ) {
			# Combination of copyResampled plus copyResized provides the best
			# performance and quality.  Based on some code from
			# http://us.php.net/manual/en/function.imagecopyresampled.php#77679
			# Unfortunately, it also uses more memory...
			DEBUG && (my $start = time);
			
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
			
			if ( DEBUG ) {
				my $diff = time - $start;
				warn "Resized using fast combo method ($diff)\n";
			}
		}
		else {
=cut
			DEBUG && (my $start = time);
			
			$newImage->copyResampled(
				$origImage,
				$destX, $destY,
				$sourceX, $sourceY,
				$destWidth, $destHeight,
				$sourceWidth, $sourceHeight
			);
			
			if ( DEBUG ) {
				my $diff = time - $start;
				warn "Resized using slow copyResampled ($diff)\n";
			}
#		}
	}
	
	my $out;
	
	if ( $transparent eq 'gd' ) {
		$out = $newImage->gd;
		$format = 'gd';
	}
	elsif ( $format eq 'png' || $transparent eq 'png' ) {
		$out = $newImage->png;
		$format = 'png';
	}
	elsif ( $format eq 'gif' || $transparent eq 'gif' ) {
		$out = $newImage->gif;
		$format = 'gif';
	}
	else {
		$out = $newImage->jpeg(90);
		$format = 'jpg';
	}
	
	if ( $save ) {
		open my $fh, '>', $save;
		print $fh $out;
		close $fh;
		
		DEBUG && warn "Resized image saved to $save\n";
		
		print "OK $save\n";
	}
	elsif ( $cacheroot ) {
		require Cache::FileCache;
		
		my $cache = Cache::FileCache->new( {
			namespace       => 'Artwork',
			cache_root      => $cacheroot,
			directory_umask => umask(),
		} );
		
		my $src = $tag || $file || $url;
		
		my $cached = {
			source => $src,
			stamp  => -f $src ? (stat _)[9] + (stat _)[7] : -1,
			data   => $out,
		};
		
		my $key = join( '-', 
			$src,
			$format,
			$width,
			$height,
			$mode,
			$bgcolor,
		);
		
		$cache->set( $key, $cached, $Cache::Cache::EXPIRES_NEVER );
		
		DEBUG && warn "Cached image as $key\n";
		
		print "OK $key\n";
	}
}

sub read_tag {
	my $tag = shift;
	
	require Audio::Scan;
	my $s = Audio::Scan->scan_tags($tag);
	
	my $tags = $s->{tags};
	
	# MP3, other files with ID3v2
	if ( my $pic = $tags->{APIC} ) {
		DEBUG && warn "Found image in ID3v2 APIC tag\n";
		if ( ref $pic->[0] eq 'ARRAY' ) {
			# multiple images, return image with lowest image_type value
			return ( sort { $a->[2] <=> $b->[2] } @{$pic} )[0]->[4];
		}
		else {
			return $pic->[4];
		}
	}
	
	# FLAC picture block
	if ( $tags->{ALLPICTURES} ) {
		DEBUG && warn "Found image in FLAC picture block\n";
		return $tags->{ALLPICTURES}->[0]->{image_data};
	}
	
	# FLAC/Ogg base64 coverart
	if ( $tags->{COVERART} ) {
		DEBUG && warn "Found image in FLAC/Ogg coverart tag\n";
		require MIME::Base64;
		return eval { MIME::Base64::decode_base64( $tags->{COVERART} ) };
	}
	
	# ALAC/M4A
	if ( $tags->{COVR} ) {
		DEBUG && warn "Found image in MPEG-4 COVR tag\n";
		return $tags->{COVR};
	}
	
	# WMA
	if ( my $pic = $tags->{'WM/Picture'} ) {
		DEBUG && warn "Found image in WM/Picture tag\n";
		if ( ref $pic eq 'ARRAY' ) {
			# return image with lowest image_type value
			return ( sort { $a->{image_type} <=> $b->{image_type} } @{$pic} )[0]->{image};
		}
		else {
			return $pic->{image};
		}
	}
	
	# Escient artwork app block (who uses this??)
	if ( $tags->{APPLICATION} && $tags->{APPLICATION}->{1163084622} ) {
		my $artwork = $tags->{APPLICATION}->{1163084622};
		if ( substr($artwork, 0, 4, '') eq 'PIC1' ) {
			return $artwork;
		}
	}
	
	return;
}

sub read_url {
	my $url = shift;
	
	require LWP::UserAgent;
	my $ua = LWP::UserAgent->new(
		timeout => 5,
	);
	
	my $res = $ua->get($url);
	
	if ( $res->is_success && $res->content_type =~ /^image/ ) {
		DEBUG && warn "Fetched image from $url\n";
		return $res->content;
	}
	
	return;
}

sub content_type {
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
	# XXX .gd format, still need to support it?
	else {
		# Unknown file type, don't try to resize
		require Data::Dump;
		die "Can't resize unknown type, magic: " . Data::Dump::dump($magic) . "\n";
	}
	
	return $ct;
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
	}
	else {
		$destY = 0;
		$destHeight = $destImageHeight;
		$destWidth = $destImageHeight * $sourceImageAR;
		$destX = ($destImageWidth - $destWidth) / 2
	}

	return ($destX, $destY, $destWidth, $destHeight);
}

sub round {
	my $number = shift;
	return int($number + .5 * ($number <=> 0));
}

__END__

=head1 NAME

gdresize.pl - Standalone artwork resizer

=head1 SYNOPSIS

Resize image embedded in audio file:

  --tag file.mp3

Resize normal image file:

  --file image.jpg

Resize remote URL:

  --url http://...

Options:

  --format  [jpg | png | gif | gd]
  --width   [X]
  --height  [Y]
  --mode    [mode]
     p: pad         (default if width & height specified)
     s: stretch     (default if only width specified)
     S: squash      (default if no width/height)
     f: fitstretch
     F: fitsquash
     c: crop
     o: original
  --bgcolor  [FFFFFF]
  --faster                 Use ugly but fast copyResized function
  --cacheroot [dir]        Cache resulting image in FileCache located in dir
  --save [file]            Save the resulting image to file

=cut