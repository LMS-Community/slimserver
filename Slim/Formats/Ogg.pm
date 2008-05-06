package Slim::Formats::Ogg;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
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

use MIME::Base64 qw(decode_base64);
use Ogg::Vorbis::Header::PurePerl;

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
);

=head2 getTag( $filename )

Extract and return audio information & any embedded metadata found.

=cut

sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	# This hash will map the keys in the tag to their values.
	my $tags = {};
	my $ogg  = undef;

	# some ogg files can blow up - especially if they are invalid.
	eval {
		local $^W = 0;
		$ogg = Ogg::Vorbis::Header::PurePerl->new($file);
	};

	if (!$ogg or $@) {

		logWarning("Warning Can't open Ogg file $file: [$@]");

		return $tags;
	}

	if (!$ogg->info('length')) {

		logWarning("Length for Ogg file: $file is 0 - skipping.");

		return $tags;
	}

	# Tags can be stacked, in an array.
	foreach my $key ($ogg->comment_tags) {

		my $ucKey  = uc($key);
		my @values = $ogg->comment($key);
		my $count  = scalar @values;

		for my $value (@values) {

			if ($] > 5.007) {
				$value = Slim::Utils::Unicode::utf8decode($value, 'utf8');
			} else {
				$value = Slim::Utils::Unicode::utf8toLatin1($value);
			}

			if ($count == 1) {

				$tags->{$ucKey} = $value;

			} else {

				push @{$tags->{$ucKey}}, $value;
			}
		}
	}

	# Correct ogginfo tags
	while (my ($old,$new) = each %tagMapping) {

		if (exists $tags->{$old}) {

			$tags->{$new} = delete $tags->{$old};
		}
	}

	# Special handling for DATE tags
	# Parse the date down to just the year, for compatibility with other formats
	if (defined $tags->{'DATE'} && !defined $tags->{'YEAR'}) {
		($tags->{'YEAR'} = $tags->{'DATE'}) =~ s/.*(\d\d\d\d).*/$1/;
	}

	# Add additional info
	$tags->{'SIZE'}	    = -s $file;

	$tags->{'SECS'}	    = $ogg->info('length');
	$tags->{'BITRATE'}  = $ogg->info('bitrate_average') || $ogg->info('bitrate_nominal');
	$tags->{'STEREO'}   = $ogg->info('channels') == 2 ? 1 : 0;
	$tags->{'CHANNELS'} = $ogg->info('channels');
	$tags->{'RATE'}	    = $ogg->info('rate');

	if (defined $ogg->info('bitrate_upper') && defined $ogg->info('bitrate_lower')) {

		if ($ogg->info('bitrate_upper') != $ogg->info('bitrate_lower')) {

			$tags->{'VBR_SCALE'} = 1;
		} else {
			$tags->{'VBR_SCALE'} = 0;
		}

	} else {

		$tags->{'VBR_SCALE'} = 0;
	}

	$tags->{'OFFSET'}   =  0; # the header is an important part of the file. don't skip it
	
	# Read cover art if available
	if ( $tags->{'COVERART'} ) {
		$tags->{'ARTWORK'} = decode_base64( delete $tags->{'COVERART'} );
	}

	return $tags;
}

=head2 getCoverArt( $filename )

Extract and return cover image from the file.

=cut

sub getCoverArt {
	my $class = shift;
	my $file  = shift || return undef;
	
	my $ogg;

	# some ogg files can blow up - especially if they are invalid.
	eval {
		local $^W = 0;
		$ogg = Ogg::Vorbis::Header::PurePerl->new( $file );
	};

	if ( !$ogg || $@ ) {
		logWarning("Unable to parse Ogg stream");
		return;
	}
	
	my ($coverart) = $ogg->comment('coverart');

	if ( $coverart ) {
		$coverart = eval { decode_base64( $coverart ) };
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
	
	my $ogg;
	my $log   = logger('scan.scanner');
	
	# some ogg files can blow up - especially if they are invalid.
	eval {
		local $^W = 0;
		$ogg = Ogg::Vorbis::Header::PurePerl->new( $fh );
	};

	if ( !$ogg || $@ ) {

		logWarning("Unable to parse Ogg stream $@");

		return (-1, undef);
	}
	
	# Save tag data if available
	if ( my $title = $ogg->comment('title') ) {
		my $artist = $ogg->comment('artist');
		my $album  = $ogg->comment('album');
		my $date   = $ogg->comment('date');
		my $genre  = $ogg->comment('genre');
		
		# XXX: Schema ignores ARTIST, ALBUM, YEAR, and GENRE for remote URLs
		# so we have to format our title info manually.
		my $track = Slim::Schema->rs('Track')->updateOrCreate({
			url        => $url,
			attributes => {
				TITLE   => $title,
				ARTIST  => $artist,
				ALBUM   => $album,
				YEAR    => $date,
				GENRE   => $genre,
			},
		});

		if ( $log->is_debug ) {
			$log->debug("Read Ogg tags from stream: " . Data::Dump::dump( $ogg->{COMMENTS} ));
		}
		
		$title .= ' ' . string('BY') . ' ' . $artist if $artist;
		$title .= ' ' . string('FROM') . ' ' . $album if $album;

		Slim::Music::Info::setCurrentTitle( $url, $title );

		# Save artwork if found
		# Read cover art if available
		if ( my $coverart = $ogg->comment('coverart') ) {
			$coverart = decode_base64($coverart);

			$track->cover(1);
			$track->update;

			my $data = {
				image => $coverart,
				type  => $ogg->comment('coverartmime') || 'image/jpeg',
			};

			my $cache = Slim::Utils::Cache->new( 'Artwork', 1, 1 );
			$cache->set( "cover_$url", $data, $Cache::Cache::EXPIRES_NEVER );

			$log->debug( 'Found embedded cover art, saving for ' . $track->url );
		}
	}
	
	my $vbr = 0;

	if (defined $ogg->info('bitrate_upper') && defined $ogg->info('bitrate_lower')) {

		if ($ogg->info('bitrate_upper') != $ogg->info('bitrate_lower')) {

			$vbr = 1;
		}
	}
	
	if ( my $bitrate = $ogg->info('bitrate_nominal') ) {

		if ( $log->is_debug ) {
			$log->debug("Found bitrate header: $bitrate kbps " . ( $vbr ? 'VBR' : 'CBR' ));
		}

		return ( $bitrate, $vbr );
	}
	
	logWarning("Unable to read bitrate from stream!");

	return (-1, undef);
}

sub getInitialAudioBlock {
	my ($class, $fh) = @_;
	
	open(my $localFh, '<&=', $fh);
	
	seek($localFh, 0, 0);
	my $ogg = Ogg::Vorbis::Header::PurePerl->new($localFh);
	
	seek($localFh, 0, 0);
	logger('player.source')->debug('Reading initial audio block: length ' . ($ogg->info('offset')));
	read ($localFh, my $buffer, $ogg->info('offset'));
	
	close($localFh);
	
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
	my ($class, $fh, $offset, $seek) = @_;

	if (!defined $fh || !defined $offset) {
		logError("Invalid arguments!");
		return wantarray ? (0, 0) : 0;
	}

	my $start = $class->_seekNextFrame($fh, $offset, 1);
	my $end   = 0;

	if (defined $seek) {
		$end = $class->_seekNextFrame($fh, $offset + $seek, 1);
		return ($start, $end);
	}

	return wantarray ? ($start, $end) : $start;
}

my $HEADERLEN   = 28; # minumum
my $MAXDISTANCE = 255 * 255 + 26 + 256;

# seekNextFrame:
#
# when scanning forward ($direction=1), simply detects the next frame header.
#
# when scanning backwards ($direction=-1), returns the next frame header whose
# frame length is within the distance scanned (so that when scanning backwards 
# from EOF, it skips any truncated frame at the end of block.

sub _seekNextFrame {
	my ($class, $fh, $startoffset, $direction) = @_;

	use bytes;

	if (!defined $fh || !defined $startoffset || !defined $direction) {
		logError("Invalid arguments!");
		return 0;
	}

	my $filelen = -s $fh;
	if ($startoffset > $filelen) {
		$startoffset = $filelen;
	}

	# TODO: MAXDISTANCE is far too far to seek backwards in most cases, so we don't
	# use negative direction for the moment.
	my $seekto = ($direction == 1) ? $startoffset : $startoffset - $MAXDISTANCE;
	my $log    = logger('player.source');

	$log->debug("Reading $MAXDISTANCE bytes at: $seekto (to scan direction: $direction)");

	sysseek($fh, $seekto, SEEK_SET);
	sysread($fh, my $buf, $MAXDISTANCE, 0);

	my $len = length($buf);

	if ($len < $HEADERLEN) {
		$log->warn("Got less than $HEADERLEN bytes");
		return 0;
	}

	my ($start, $end) = (0, 0);

	if ($direction == 1) {
		$start = 0;
		$end   = $len - $HEADERLEN;
	} else {
		$start = $len - $HEADERLEN;
		$end   = 0;
	}

	$log->debug("Scanning: len = $len, start = $start, end = $end");

	for (my $pos = $start; $pos != $end; $pos += $direction) {

		my $head = substr($buf, $pos, $HEADERLEN);

		if (!_isOggPageHeader($head)) {
			next;
		}

		my $found_at_offset = $seekto + $pos;

		$log->debug("Found frame header at $found_at_offset");

		return $found_at_offset;
	}

	$log->warn("Couldn't find any frame header");

	return 0;
}

# This is a pretty minimal test, liable to false positives
# but it does not really matter as the player decoder will
# resync properly if need be (as it has to anyway because 
# of the non-coincidence or page and packet boundaries).
sub _isOggPageHeader {
	my $buffer = shift;
	
	if (substr($buffer, 0, 4) ne 'OggS') {return 0;}
	
	if (ord(substr($buffer, 4, 1)) != 0) {return 0;}
	
	if (ord(substr($buffer, 5, 1)) & ~5) {return 0;}
	
	return 1;
}

1;
