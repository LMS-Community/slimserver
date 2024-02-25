package Slim::Formats::OggFLAC;

use base qw(Slim::Formats::FLAC);

use Slim::Utils::Log;
use Audio::Scan;

my $log       = logger('scan.scanner');
my $sourcelog = logger('player.source');

=head2 getInitialAudioBlock( $fh, $offset, $time )

Get the OggFlac header. For now, we use a fixed header
that resets MD5 and frame number to 0 upon seeking. 
NB: that function is only used when seeking, otherwise
the entire file is used unmodified.

=cut

sub getInitialAudioBlock {
	my ($class, $fh, $track, $time) = @_;

	# it should be already here
	$class->findFrameBoundaries( $fh, undef, $1 ) unless exists ${*$fh}{_ogf_seek_header};
	main::INFOLOG && $sourcelog->is_info && $sourcelog->info('Reading initial audio block of ', length ${${*$fh}{_ogf_seek_header}});
	return ${${*$fh}{_ogf_seek_header}};
}

=head2 findFrameBoundaries( $fh, $offset, $time )

Seeks to the Ogg block containing the sample at $time.

=cut

sub findFrameBoundaries {
	my ( $class, $fh, $offset, $time ) = @_;
	
	# need a localFh to have own seek pointer
	open(my $localFh, '<&=', $fh);
	# should not be beeded as find_frame_fh_return_info seeks 
	$localFh->seek(0, SEEK_SET);
	
	# stash the header here as getInitialBlock should be called right after
	my $info = Audio::Scan->find_frame_fh_return_info( ogf => $localFh, int($time * 1000) );
	${*$fh}{_ogf_seek_header} = \$info->{seek_header};
	
	return $info->{seek_offset} || -1;
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
