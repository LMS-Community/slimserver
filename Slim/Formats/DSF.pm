package Slim::Formats::DSF;

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
	
	my $s = Audio::Scan->scan_fh( dsf => $localFh );
	
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

	my $s = Audio::Scan->scan_fh( dsf => $localFh );
	my $info = $s->{info};

	close $localFh;

	# reduce total size of audio stream by one sample block when scanning
	# this will discard the end samples, but is better than playing the padding at the end of the file
	# a better solution would be to rewrite the audio header with a reduced sample count, but this is more complex..
	${*$fh}{logicalEndOfStream} -= $s->{info}->{'channels'} * $s->{info}->{'block_size_per_channel'};

	return $info->{audio_offset} + 
		(int(int($info->{samplerate} / 8 * $time) / $info->{block_size_per_channel}) * $info->{channels} * $info->{block_size_per_channel});
}

1;
