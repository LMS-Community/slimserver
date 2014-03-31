package Slim::Formats::DFF;

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Utils::Log;

use base qw(Slim::Formats::DSD);

my $sourcelog = logger('player.source');

sub getInitialAudioBlock {
	my ($class, $fh, $track) = @_;

	open my $localFh, '<&=', $fh;
	seek $localFh, 0, 0;
	
	my $s = Audio::Scan->scan_fh( dff => $localFh );
	
	main::DEBUGLOG && $sourcelog->is_debug && $sourcelog->debug( 'Reading initial audio block: length ' . $s->{info}->{audio_offset} );
	
	seek $localFh, 0, 0;
	read $localFh, my $buffer, $s->{info}->{audio_offset};
	
	close $localFh;

	return $buffer;
}

sub findFrameBoundaries {
	my ( $class, $fh, $offset, $time ) = @_;

	if ( !defined $fh || !defined $time ) {
		return 0;
	}

	open my $localFh, '<&=', $fh;
	seek $localFh, 0, 0;

	my $s = Audio::Scan->scan_fh( dff => $localFh );
	my $info = $s->{info};

	close $localFh;

	return $info->{audio_offset} + (int($info->{samplerate} / 8 * $time) * $info->{channels});
}

1;
