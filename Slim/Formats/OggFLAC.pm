package Slim::Formats::OggFLAC;

use base qw(Slim::Formats::FLAC);

use Slim::Utils::Log;
use Audio::Scan;

my $log       = logger('scan.scanner');
my $sourcelog = logger('player.source');

=head2 getInitialAudioBlock( $fh, $offset, $time )

Get the OggFlac header. For now, we use a fixed header
that resets MD5 and frame number to 0 upon seeking. 
NB: that function is only used when seeking, othersise
the entire file us used untouched.

=cut

sub getInitialAudioBlock {
	my ($class, $fh, $track, $time) = @_;

	open my $localFh, '<&=', $fh;
	my $info = Audio::Scan->find_frame_fh_return_info( ogf => $localFh, 0 );

	main::INFOLOG && $sourcelog->is_info && $sourcelog->info('Reading initial audio block of ', length $info->{seek_header});

	return $info->{seek_header};
}

=head2 findFrameBoundaries( $fh, $offset, $time )

Seeks to the Ogg block containing the sample at $time.

=cut

sub findFrameBoundaries {
	my ( $class, $fh, $offset, $time ) = @_;

	return (defined $fh && defined $time) ? 
		   Audio::Scan->find_frame_fh( ogf => $fh, int($time * 1000) ) : 
		   0;		
}

=head2 scanBitrate( $fh )

Intended to scan the bitrate of a remote stream, although for FLAC this data
is not accurate, but we can get the duration of the remote file from the header,
so we use this to set the track duaration value.

=cut

sub scanBitrate { 
	my ( $class, $fh, $url ) = @_;
	return $class->SUPER($fh, $url, 'ogf');
}


1;
