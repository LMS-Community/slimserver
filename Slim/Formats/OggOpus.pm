package Slim::Formats::OggOpus;

use strict;
use base qw(Slim::Formats::Ogg);

use Fcntl qw(:seek);
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);

use Audio::Scan;

my $log       = logger('scan.scanner');
my $sourcelog = logger('player.source');

sub scanBitrate {
	my $class = shift;
	my $fh    = shift;
	my $url   = shift;
	
	my $isDebug = $log->is_debug;
	
	local $ENV{AUDIO_SCAN_NO_ARTWORK} = 0;
	
	seek $fh, 0, 0;
	
	my $s = Audio::Scan->scan_fh( opus => $fh );
	
	if ( !$s->{info}->{audio_offset} ) {

		logWarning('Unable to parse Opus stream');

		return (-1, undef);
	}
	
	my $info = $s->{info};
	my $tags = $s->{tags};
	
	# Save tag data if available
	if ( my $title = $tags->{TITLE} ) {		
		# XXX: Schema ignores ARTIST, ALBUM, YEAR, and GENRE for remote URLs
		# so we have to format our title info manually.
		my $track = Slim::Schema->updateOrCreate( {
			url        => $url,
			attributes => {
				TITLE => $title,
			},
		} );

		main::DEBUGLOG && $isDebug && $log->debug("Read Opus tags from stream: " . Data::Dump::dump($tags));
		
		$title .= ' ' . string('BY') . ' ' . $tags->{ARTIST} if $tags->{ARTIST};
		$title .= ' ' . string('FROM') . ' ' . $tags->{ALBUM} if $tags->{ALBUM};

		Slim::Music::Info::setCurrentTitle( $url, $title );

		# Save artwork if found
		# Read cover art if available
		if ( $tags->{ALLPICTURES} ) {
			my $coverart;
			my $mime;

			my @allpics = sort { $a->{picture_type} <=> $b->{picture_type} } 
				@{ $tags->{ALLPICTURES} };

			if ( my @frontcover = grep ( $_->{picture_type} == 3, @allpics ) ) {
				# in case of many type 3 (front cover) just use the first one
				$coverart = $frontcover[0]->{image_data};
				$mime     = $frontcover[0]->{mime_type};
			}
			else {
				# fall back to use lowest type image found
				$coverart = $allpics[0]->{image_data};
				$mime     = $allpics[0]->{mime_type};
			}
			
			$track->cover( length($coverart) );
			$track->update;

			my $data = {
				image => $coverart,
				type  => $tags->{COVERARTMIME} || $mime,
			};

			my $cache = Slim::Utils::Cache->new();
			$cache->set( "cover_$url", $data, 86400 * 7 );

			main::DEBUGLOG && $isDebug && $log->debug( 'Found embedded cover art, saving for ' . $track->url );
		}
	}
	
	my $vbr = 0;

	if ( defined $info->{bitrate_upper} && defined $info->{bitrate_lower} ) {
		if ( $info->{bitrate_upper} != $info->{bitrate_lower} ) {
			$vbr = 1;
		}
	}
	
	if ( my $bitrate = ( $info->{bitrate_average} || $info->{bitrate_nominal} ) ) {

		main::DEBUGLOG && $isDebug && $log->debug("Found bitrate header: $bitrate kbps " . ( $vbr ? 'VBR' : 'CBR' ));

		return ( $bitrate, $vbr );
	}
	
	logWarning("Unable to read bitrate from stream!");

	return (-1, undef);
}

sub getInitialAudioBlock {
	my ($class, $fh) = @_;
	
	open my $localFh, '<&=', $fh;
	
	seek $localFh, 0, 0;
	
	my $s = Audio::Scan->scan_fh( opus => $localFh );
	
	main::DEBUGLOG && $sourcelog->is_debug && $sourcelog->debug( 'Reading initial audio block: length ' . $s->{info}->{audio_offset} );
	
	seek $localFh, 0, 0;
	read $localFh, my $buffer, $s->{info}->{audio_offset};
	
	close $localFh;
	
	return $buffer;
}

=head2 findFrameBoundaries( $fh, $offset, $time )

Seeks to the Ogg block containing the sample at $time.

The only caller is L<Slim::Player::Source> at this time.

=cut

sub findFrameBoundaries {
	my ( $class, $fh, $offset, $time ) = @_;

	if ( !defined $fh || !defined $time ) {
		return 0;
	}
	
	return Audio::Scan->find_frame_fh( opus => $fh, int($time * 1000) );
}

sub canSeek { 1 }

1;
