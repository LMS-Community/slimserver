package Slim::Formats::Ogg;

# $Id$

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Formats::Ogg

=head1 SYNOPSIS

my $tags = Slim::Formats::Ogg->getTag( $filename );

=head1 DESCRIPTION

Read tags & metadata embedded in Ogg Vorbis files.

=head1 METHODS

=cut

use strict;
use base qw(Slim::Formats);

use Fcntl qw(:seek);
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Unicode;

use Audio::Scan;
use MIME::Base64 qw(decode_base64);

my $log       = logger('scan.scanner');
my $sourcelog = logger('player.source');

my %tagMapping = (
	'TRACKNUMBER'               => 'TRACKNUM',
	'DISCNUMBER'                => 'DISC',
	'URL'                       => 'URLTAG',
	'MUSICBRAINZ_SORTNAME'      => 'ARTISTSORT',
	'MUSICBRAINZ_ALBUMARTIST'   => 'ALBUMARTIST',
	'MUSICBRAINZ_ALBUMARTISTID' => 'MUSICBRAINZ_ALBUMARTIST_ID',
	'MUSICBRAINZ_ALBUMID'       => 'MUSICBRAINZ_ALBUM_ID',
	'MUSICBRAINZ_ALBUMSTATUS'   => 'MUSICBRAINZ_ALBUM_STATUS',
	'MUSICBRAINZ_ALBUMTYPE'     => 'MUSICBRAINZ_ALBUM_TYPE',
	'MUSICBRAINZ_ARTISTID'      => 'MUSICBRAINZ_ARTIST_ID',
	'MUSICBRAINZ_TRACKID'       => 'MUSICBRAINZ_ID',
	'MUSICBRAINZ_TRMID'         => 'MUSICBRAINZ_TRM_ID',
	'DESCRIPTION'               => 'COMMENT',

	# for dBpoweramp CD Ripper
	'TOTALDISCS'                => 'DISCC',
);

=head2 getTag( $filename )

Extract and return audio information & any embedded metadata found.

=cut

sub getTag {
	my $class = shift;
	my $file  = shift || return {};
	
	my $s = Audio::Scan->scan($file);
	
	my $info = $s->{info};
	my $tags = $s->{tags};
	
	return unless $info->{song_length_ms};
	
	# Map tags
	while ( my ($old, $new) = each %tagMapping ) {

		if ( exists $tags->{$old} ) {
			$tags->{$new} = delete $tags->{$old};
		}
	}

	# Special handling for DATE tags
	# Parse the date down to just the year, for compatibility with other formats
	if (defined $tags->{DATE} && !defined $tags->{YEAR}) {
		($tags->{YEAR} = $tags->{DATE}) =~ s/.*(\d\d\d\d).*/$1/;
	}

	# Add additional info
	$tags->{SIZE}	  = $info->{file_size};
	$tags->{SECS}	  = $info->{song_length_ms} / 1000;
	$tags->{BITRATE}  = $info->{bitrate_average} || $info->{bitrate_nominal};
	$tags->{STEREO}   = $info->{channels} == 2 ? 1 : 0;
	$tags->{CHANNELS} = $info->{channels};
	$tags->{RATE}	  = $info->{samplerate};

	if ( defined $info->{bitrate_upper} && defined $info->{bitrate_lower} ) {
		if ( $info->{bitrate_upper} != $info->{bitrate_lower} ) {
			$tags->{VBR_SCALE} = 1;
		}
		else {
			$tags->{VBR_SCALE} = 0;
		}
	}
	else {
		$tags->{VBR_SCALE} = 0;
	}

	$tags->{OFFSET} = 0; # the header is an important part of the file. don't skip it
	
	# Read cover art if available
	if ( $tags->{COVERART} ) {
		# In 'no artwork' mode, ARTWORK is the length
		if ( $ENV{AUDIO_SCAN_NO_ARTWORK} ) {
			$tags->{COVER_LENGTH} = $tags->{COVERART};
		}
		else {
			$tags->{ARTWORK} = eval { decode_base64( delete $tags->{COVERART} ) };
		
			if ( !$@ ) {
				# Flag if we have embedded cover art
				$tags->{COVER_LENGTH} = length( $tags->{ARTWORK} );
			}
		}
	}

	return $tags;
}

=head2 getCoverArt( $filename )

Extract and return cover image from the file.

=cut

sub getCoverArt {
	my $class = shift;
	my $file  = shift || return undef;
	
	# Enable artwork in Audio::Scan
	local $ENV{AUDIO_SCAN_NO_ARTWORK} = 0;
	
	my $s = Audio::Scan->scan_tags($file);

	if ( $s->{tags}->{COVERART} ) {
		my $coverart = eval { decode_base64( $s->{tags}->{COVERART} ) };
		return if $@;
		return $coverart;
	}

	return;
}

=head2 scanBitrate( $fh )

Scans a file and returns just the bitrate and VBR setting.  This is used
to determine the bitrate for remote streams.  This method is not very accurate
for Ogg files because we only know the nominal bitrate value, not the actual average
bitrate.

=cut

sub scanBitrate {
	my $class = shift;
	my $fh    = shift;
	my $url   = shift;
	
	my $isDebug = $log->is_debug;
	
	local $ENV{AUDIO_SCAN_NO_ARTWORK} = 0;
	
	my $s = Audio::Scan->scan_fh( ogg => $fh );
	
	if ( !$s->{info}->{audio_offset} ) {

		logWarning('Unable to parse Ogg stream');

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

		main::DEBUGLOG && $isDebug && $log->debug("Read Ogg tags from stream: " . Data::Dump::dump($tags));
		
		$title .= ' ' . string('BY') . ' ' . $tags->{ARTIST} if $tags->{ARTIST};
		$title .= ' ' . string('FROM') . ' ' . $tags->{ALBUM} if $tags->{ALBUM};

		Slim::Music::Info::setCurrentTitle( $url, $title );

		# Save artwork if found
		# Read cover art if available
		if ( my $coverart = $tags->{COVERART} ) {
			$coverart = eval { decode_base64($coverart) };

			if ( !$@ ) {
				$track->cover( length($coverart) );
				$track->update;

				my $data = {
					image => $coverart,
					type  => $tags->{COVERARTMIME} || 'image/jpeg',
				};

				my $cache = Slim::Utils::Cache->new( 'Artwork', 1, 1 );
				$cache->set( "cover_$url", $data, $Cache::Cache::EXPIRES_NEVER );

				main::DEBUGLOG && $isDebug && $log->debug( 'Found embedded cover art, saving for ' . $track->url );
			}
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
	
	my $s = Audio::Scan->scan_fh( ogg => $localFh );
	
	main::DEBUGLOG && $sourcelog->is_debug && $sourcelog->debug( 'Reading initial audio block: length ' . $s->{info}->{audio_offset} );
	
	seek $localFh, 0, 0;
	read $localFh, my $buffer, $s->{info}->{audio_offset};
	
	close $localFh;
	
	return $buffer;
}

=head2 findFrameBoundaries( $fh, $offset, $seek )

Starts seeking from $offset (bytes relative to beginning of file) until it
finds the next valid frame header. Returns the offset of the first and last
bytes of the frame if any is found, otherwise (0, 0).

If the caller does not request an array context, only the first (start) position is returned.

The only caller is L<Slim::Player::Source> at this time.

=cut

sub findFrameBoundaries {
	my ($class, $fh, $offset) = @_;

	if (!defined $fh || !defined $offset) {
		return 0;
	}
	
	return Audio::Scan->find_frame_fh( ogg => $fh, $offset );
}

sub canSeek { 1 }

1;
