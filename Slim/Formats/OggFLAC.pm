package Slim::Formats::OggFLAC;

use base qw(Slim::Formats::FLAC);

sub findFrameBoundaries { 0 }

sub scanBitrate{ 
	return (-1, undef);
}

sub canSeek { 0 }

1;
