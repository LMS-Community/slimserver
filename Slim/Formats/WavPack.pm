package Slim::Formats::WavPack;

use strict;
use base qw(Slim::Formats);

use Audio::Scan;
use Slim::Formats::APE;

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub getTag {
	my $class = shift;
	my $file  = shift || return {};
	
	my $s = Audio::Scan->scan($file);

	my $info = $s->{info};
	my $tags = $s->{tags};
	
	# Check for the presence of the info block here
	return unless $info->{song_length_ms};
	
	# Add info
	$tags->{SIZE}       = $info->{file_size};
	$tags->{BITRATE}    = $info->{bitrate};
	$tags->{SECS}       = $info->{song_length_ms} / 1000;
	$tags->{RATE}       = $info->{samplerate};
	$tags->{SAMPLESIZE} = $info->{bits_per_sample};
	$tags->{CHANNELS}   = $info->{channels};
	$tags->{VBR_SCALE}  = 1;
	
	if ( $info->{bits_per_sample} == 1 ) {
	    $tags->{WAVPACKDSD} = 1;
	}

	Slim::Formats::APE->doTagMapping($tags);

	return $tags;
}

*getCoverArt = \&Slim::Formats::APE::getCoverArt;

1;
