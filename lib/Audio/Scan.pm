package Audio::Scan;

use strict;

our $VERSION;

require XSLoader;

BEGIN {
	foreach ('0.93', '0.95', '0.94') {
		eval { XSLoader::load('Audio::Scan', $_); };
		
		if (!$@) {
			$VERSION = $_;
			last;
		}
	}
}


use constant FILTER_INFO_ONLY => 1;
use constant FILTER_TAGS_ONLY => 2;

sub scan_info {
    my ( $class, $path, $opts ) = @_;
    
    $opts ||= {};
    $opts->{filter} = FILTER_INFO_ONLY;
    
    $class->scan( $path, $opts );
}

sub scan_tags {
    my ( $class, $path, $opts ) = @_;
    
    $opts ||= {};
    $opts->{filter} = FILTER_TAGS_ONLY;
    
    $class->scan( $path, $opts );
}

sub scan {
    my ( $class, $path, $opts ) = @_;
    
    my ($filter, $md5_size, $md5_offset);
      
    open my $fh, '<', $path or do {
        warn "Could not open $path for reading: $!\n";
        return;
    };
    
    binmode $fh;
    
    my ($suffix) = $path =~ /\.(\w+)$/;
    
    return if !$suffix;
    
    if ( defined $opts ) {
        if ( !ref $opts ) {
            # Back-compat to support filter as normal argument
            warn "The Audio::Scan::scan() filter passing method is deprecated, please pass a hashref instead.\n";
            $filter = $opts;
        }
        else {
            $filter     = $opts->{filter} || FILTER_INFO_ONLY | FILTER_TAGS_ONLY;
            $md5_size   = $opts->{md5_size};
            $md5_offset = $opts->{md5_offset};
        }
    }
    
    if ( !defined $filter ) {
        $filter = FILTER_INFO_ONLY | FILTER_TAGS_ONLY;
    }
    
    my $ret = $class->_scan( $suffix, $fh, $path, $filter, $md5_size || 0, $md5_offset || 0 );
    
    close $fh;
    
    return $ret;
}

sub scan_fh {
    my ( $class, $suffix, $fh, $opts ) = @_;
    
    my ($filter, $md5_size, $md5_offset);
    
    binmode $fh;
    
    if ( defined $opts ) {
        if ( !ref $opts ) {
            # Back-compat to support filter as normal argument
            warn "The Audio::Scan::scan_fh() filter passing method is deprecated, please pass a hashref instead.\n";
            $filter = $opts;
        }
        else {
            $filter     = $opts->{filter} || FILTER_INFO_ONLY | FILTER_TAGS_ONLY;
            $md5_size   = $opts->{md5_size};
            $md5_offset = $opts->{md5_offset};
        }
    }
    
    if ( !defined $filter ) {
        $filter = FILTER_INFO_ONLY | FILTER_TAGS_ONLY;
    }
    
    return $class->_scan( $suffix, $fh, '(filehandle)', $filter, $md5_size || 0, $md5_offset || 0 );
}

sub find_frame {
    my ( $class, $path, $offset ) = @_;
    
    open my $fh, '<', $path or do {
        warn "Could not open $path for reading: $!\n";
        return;
    };
    
    binmode $fh;
    
    my ($suffix) = $path =~ /\.(\w+)$/;
    
    return -1 if !$suffix;
    
    my $ret = $class->_find_frame( $suffix, $fh, $path, $offset );
    
    close $fh;
    
    return $ret;
}

sub find_frame_fh {
    my ( $class, $suffix, $fh, $offset ) = @_;
    
    binmode $fh;
    
    return $class->_find_frame( $suffix, $fh, '(filehandle)', $offset );
}

sub find_frame_return_info {
    my ( $class, $path, $offset ) = @_;
    
    open my $fh, '<', $path or do {
        warn "Could not open $path for reading: $!\n";
        return;
    };
    
    binmode $fh;
    
    my ($suffix) = $path =~ /\.(\w+)$/;
    
    return if !$suffix;
    
    my $ret = $class->_find_frame_return_info( $suffix, $fh, $path, $offset );
    
    close $fh;
    
    return $ret;
}

sub find_frame_fh_return_info {
    my ( $class, $suffix, $fh, $offset ) = @_;
    
    binmode $fh;
    
    return $class->_find_frame_return_info( $suffix, $fh, '(filehandle)', $offset );
}

1;
__END__

=head1 NAME

Audio::Scan - Fast C metadata and tag reader for all common audio file formats

=head1 SYNOPSIS

    use Audio::Scan;

    my $data = Audio::Scan->scan('/path/to/file.mp3');

    # Just file info
    my $info = Audio::Scan->scan_info('/path/to/file.mp3');

    # Just tags
    my $tags = Audio::Scan->scan_tags('/path/to/file.mp3');
    
    # Scan without reading (possibly large) artwork into memory.
    # Instead of binary artwork data, the size of the artwork will be returned instead.
    {
        local $ENV{AUDIO_SCAN_NO_ARTWORK} = 1;
        my $data = Audio::Scan->scan('/path/to/file.mp3');
    }
    
    # Scan a filehandle
    open my $fh, '<', 'my.mp3';
    my $data = Audio::Scan->scan_fh( mp3 => $fh );
    close $fh;
    
    # Scan and compute an audio MD5 checksum
    my $data = Audio::Scan->scan( '/path/to/file.mp3', { md5_size => 100 * 1024 } );
    my $md5 = $data->{info}->{audio_md5};

=head1 DESCRIPTION

Audio::Scan is a C-based scanner for audio file metadata and tag information. It currently
supports MP3, MP4, Ogg Vorbis, FLAC, ASF, WAV, AIFF, Musepack, Monkey's Audio, and WavPack.

See below for specific details about each file format.

=head1 METHODS

=head2 scan( $path, [ \%OPTIONS ] )

Scans $path for both metadata and tag information.  The type of scan performed is
determined by the file's extension.  Supported extensions are:

    MP3:  mp3, mp2
    MP4:  mp4, m4a, m4b, m4p, m4v, m4r, k3g, skm, 3gp, 3g2, mov
    AAC (ADTS): aac
    Ogg:  ogg, oga
    FLAC: flc, flac, fla
    ASF:  wma, wmv, asf
    Musepack:  mpc, mpp, mp+
    Monkey's Audio:  ape, apl
    WAV: wav
    AIFF: aiff, aif
    WavPack: wv

This method returns a hashref containing two other hashrefs: info and tags.  The
contents of the info and tag hashes vary depending on file format, see below for details.

An optional hashref may be provided with the following values:

    md5_size => $audio_bytes_to_checksum

An MD5 will be computed of the first N audio bytes. Any tags in the file are automatically
skipped, so this is a useful way of determining if a file's audio content is the same even
if tags may have been changed.  The hex MD5 value is returned in the $info->{audio_md5}
key.  This option will reduce performance, so choose a small enough size that works for you,
you should probably avoid using more than 64K for example.

For FLAC files that already contain an MD5 checksum, this value will be used instead
of calculating a new one.

    md5_offset => $offset

Begin computing the audio_md5 value starting at $offset.  If this value is not specified,
$offset defaults to a point in the middle of the file.

=head2 scan_info( $path, [ \%OPTIONS ] )

If you only need file metadata and don't care about tags, you can use this method.

=head2 scan_tags( $path, [ \%OPTIONS ] )

If you only need the tags and don't care about the metadata, use this method.

=head2 scan_fh( $type => $fh, [ \%OPTIONS ] )

Scans a filehandle. $type is the type of file to scan as, i.e. "mp3" or "ogg".
Note that FLAC does not support reading from a filehandle.

=head2 find_frame( $path, $timestamp_in_ms )

Returns the byte offset to the first audio frame starting from the given timestamp
(in milliseconds).

=over 4

=item MP3, Ogg, FLAC, ASF, MP4

The byte offset to the data packet containing this timestamp will be returned. For
file formats that don't provide timestamp information such as MP3, the best estimate for
the location of the timestamp will be returned.  This will be more accurate if the
file has a Xing header or is CBR for example.

=item WAV, AIFF, Musepack, Monkey's Audio, WavPack

Not yet supported by find_frame.

=back

=head2 find_frame_return_info( $mp4_path, $timestamp_in_ms )

The header of an MP4 file contains various metadata that refers to the structure of
the audio data, making seeking more difficult to perform. This method will return
the usual $info hash with 2 additional keys:

    seek_offset - The seek offset in bytes
    seek_header - A rewritten MP4 header that can be prepended to the audio data
                  found at seek_offset to construct a valid bitstream. Specifically,
                  the following boxes are rewritten: stts, stsc, stsz, stco

For example, to seek 30 seconds into a file and write out a new MP4 file seeked to
this point:

    my $info = Audio::Scan->find_frame_return_info( $file, 30000 );
    
    open my $f, '<', $file;
    sysseek $f, $info->{seek_offset}, 1;

    open my $fh, '>', 'seeked.m4a';
    print $fh $info->{seek_header};

    while ( sysread( $f, my $buf, 65536 ) ) {
        print $fh $buf;
    }

    close $f;
    close $fh;

=head2 find_frame_fh( $type => $fh, $offset )

Same as C<find_frame>, but with a filehandle.

=head2 find_frame_fh_return_info( $type => $fh, $offset )

Same as C<find_frame_return_info>, but with a filehandle.

=head2 has_flac()

Deprecated.  Always returns 1 now that FLAC is always enabled.

=head2 is_supported( $path )

Returns 1 if the given path can be scanned by Audio::Scan, or 0 if not.

=head2 get_types()

Returns an array of strings of the file types supported by Audio::Scan.

=head2 extensions_for( $type )

Returns an array of strings of the file extensions that are considered to
be the file type I<$type>.

=head2 type_for( $extension )

Returns file type for a given extension. Returns I<undef> for unsupported
extensions.

=head1 SKIPPING ARTWORK

To save memory while reading tags, you can opt to skip potentially large 
embedded artwork.  To do this, set the environment variable AUDIO_SCAN_NO_ARTWORK:

    local $ENV{AUDIO_SCAN_NO_ARTWORK} = 1;
    my $tags = Audio::Scan->scan_tags($file);

This will return the length of the embedded artwork instead of the actual image data.
In some cases it will also return a byte offset to the image data, which can be used
to extract the image using more efficient means.  Note that the offset is not always
returned so if you want to use this data make sure to check for offset.  If offset
is not present, the only way to get the image data is to perform a normal tag scan
without the environment variable set.

One limitation that currently exists is that memory for embedded images is still
allocated for ASF and Ogg Vorbis files.

This information is returned in different ways depending on the format:

ID3 (MP3, AAC, WAV, AIFF):

    $tags->{APIC}->[3]: image length
    $tags->{APIC}->[4]: image offset (unless APIC would need unsynchronization)

MP4:

    $tags->{COVR}: image length
    $tags->{COVR_offset}: image offset (always available)

Ogg Vorbis:

    $tags->{ALLPICTURES}->[0]->{image_data}: image length
    Image offset is not supported with Vorbis because the data is always base64-encoded.

FLAC:

    $tags->{ALLPICTURES}->[0]->{image_data}: image length
    $tags->{ALLPICTURES}->[0]->{offset}: image offset (always available)

ASF:

    $tags->{'WM/Picture'}->{image}: image length
    $tags->{'WM/Picture'}->{offset}: image offset (always available)

APE, Musepack, WavPack, MP3 with APEv2:

    $tags->{'COVER ART (FRONT)'}: image length
    $tags->{'COVER ART (FRONT)_offset'}: image offset (always available)

=head1 MP3

=head2 INFO

The following metadata about a file may be returned:

    id3_version (i.e. "ID3v2.4.0")
    song_length_ms (duration in milliseconds)
    layer (i.e. 3)
    stereo
    samples_per_frame
    padding
    audio_size (size of all audio frames)
    audio_offset (byte offset to first audio frame)
    bitrate (in bps, determined using Xing/LAME/VBRI if possible, or average in the worst case)
    samplerate (in kHz)
    vbr (1 if file is VBR)
    dlna_profile (if file is compliant)

    If a Xing header is found:
    xing_frames
    xing_bytes
    xing_quality

    If a VBRI header is found:
    vbri_delay
    vbri_frames
    vbri_bytes
    vbri_quality

    If a LAME header is found:
    lame_encoder_version
    lame_tag_revision
    lame_vbr_method
    lame_lowpass
    lame_replay_gain_radio
    lame_replay_gain_audiophile
    lame_encoder_delay
    lame_encoder_padding
    lame_noise_shaping
    lame_stereo_mode
    lame_unwise_settings
    lame_source_freq
    lame_surround
    lame_preset

=head2 TAGS

Raw tags are returned as found.  This means older tags such as ID3v1 and ID3v2.2/v2.3
are converted to ID3v2.4 tag names.  Multiple instances of a tag in a file will be returned
as arrays.  Complex tags such as APIC and COMM are returned as arrays.  All tag fields are
converted to upper-case.  All text is converted to UTF-8.

Sample tag data:

    tags => {
          ALBUMARTISTSORT => "Solar Fields",
          APIC => [ "image/jpeg", 3, "", <binary data snipped> ],
          CATALOGNUMBER => "INRE 017",
          COMM => ["eng", "", "Amazon.com Song ID: 202981429"],
          "MUSICBRAINZ ALBUM ARTIST ID" => "a2af1f31-c9eb-4fff-990c-c4f547a11b75",
          "MUSICBRAINZ ALBUM ID" => "282143c9-6191-474d-a31a-1117b8c88cc0",
          "MUSICBRAINZ ALBUM RELEASE COUNTRY" => "FR",
          "MUSICBRAINZ ALBUM STATUS" => "official",
          "MUSICBRAINZ ALBUM TYPE" => "album",
          "MUSICBRAINZ ARTIST ID" => "a2af1f31-c9eb-4fff-990c-c4f547a11b75",
          "REPLAYGAIN_ALBUM_GAIN" => "-2.96 dB",
          "REPLAYGAIN_ALBUM_PEAK" => "1.045736",
          "REPLAYGAIN_TRACK_GAIN" => "+3.60 dB",
          "REPLAYGAIN_TRACK_PEAK" => "0.892606",
          TALB => "Leaving Home",
          TCOM => "Magnus Birgersson",
          TCON => "Ambient",
          TCOP => "2005 ULTIMAE RECORDS",
          TDRC => "2004-10",
          TIT2 => "Home",
          TPE1 => "Solar Fields",
          TPE2 => "Solar Fields",
          TPOS => "1/1",
          TPUB => "Ultimae Records",
          TRCK => "1/11",
          TSOP => "Solar Fields",
          UFID => [
                "http://musicbrainz.org",
                "1084278a-2254-4613-a03c-9fed7a8937ca",
          ],
    },


=head1 MP4

=head2 INFO

The following metadata about a file may be returned:

    audio_offset (byte offset to start of mdat)
    audio_size
    compatible_brands
    file_size
    leading_mdat (if file has mdat before moov)
    major_brand
    minor_version
    song_length_ms
    timescale
    dlna_profile (if file is compliant)
    tracks (array of tracks in the file)
        Each track may contain:
        
        audio_type
        avg_bitrate
        bits_per_sample
        channels
        duration
        encoding
        handler_name
        handler_type
        id
        max_bitrate
        samplerate
        
=head2 TAGS

Tags are returned in a hash with all keys converted to upper-case.  Keys starting with
0xA9 (copyright symbol) will have this character stripped out.  Sample tag data:

    tags => {
       AART              => "Album Artist",
       ALB               => "Album",
       ART               => "Artist",
       CMT               => "Comments",
       COVR              => <binary data snipped>,
       CPIL              => 1,
       DAY               => 2009,
       DESC              => "Video Description",
       DISK              => "1/2",
       "ENCODING PARAMS" => "vers\0\0\0\1acbf\0\0\0\2brat\0\1w\0cdcv\0\1\6\5",
       GNRE              => "Jazz",
       GRP               => "Grouping",
       ITUNNORM          => " 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000",
       ITUNSMPB          => " 00000000 00000840 000001E4 00000000000001DC 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000",
       LYR               => "Lyrics",
       NAM               => "Name",
       PGAP              => 1,
       SOAA              => "Sort Album Artist",
       SOAL              => "Sort Album",
       SOAR              => "Sort Artist",
       SOCO              => "Sort Composer",
       SONM              => "Sort Name",
       SOSN              => "Sort Show",
       TMPO              => 120,
       TOO               => "iTunes 8.1.1, QuickTime 7.6",
       TRKN              => "1/10",
       TVEN              => "Episode ID",
       TVES              => 12,
       TVSH              => "Show",
       TVSN              => 12,
       WRT               => "Composer",
    },

=head1 AAC (ADTS)

=head2 INFO

The following metadata about a file is returned:

    audio_offset
    audio_size
    bitrate (in bps)
    channels
    file_size
    profile (Main, LC, or SSR)
    samplerate (in kHz)
    song_length_ms (duration in milliseconds)
    dlna_profile (if file is compliant)

=head1 OGG VORBIS

=head2 INFO

The following metadata about a file is returned:

    version
    channels
    stereo
    samplerate (in kHz)
    bitrate_average (in bps)
    bitrate_upper
    bitrate_nominal
    bitrate_lower
    blocksize_0
    blocksize_1
    audio_offset (byte offset to audio)
    audio_size
    song_length_ms (duration in milliseconds)

=head2 TAGS

Raw Vorbis comments are returned.  All comment keys are capitalized.

=head1 FLAC

=head2 INFO

The following metadata about a file is returned:

    channels
    samplerate (in kHz)
    bitrate (in bps)
    file_size
    audio_offset (byte offset to first audio frame)
    audio_size
    song_length_ms (duration in milliseconds)
    bits_per_sample
    frames
    minimum_blocksize
    maximum_blocksize
    minimum_framesize
    maximum_framesize
    audio_md5
    total_samples

=head2 TAGS

Raw FLAC comments are returned.  All comment keys are capitalized.  Some data returned is special:

APPLICATION

    Each application block is returned in the APPLICATION tag keyed by application ID.

CUESHEET_BLOCK

    The CUESHEET_BLOCK tag is an array containing each line of the cue sheet.

ALLPICTURES

    Embedded pictures are returned in an ALLPICTURES array.  Each picture has the following metadata:
    
        mime_type
        description
        width
        height
        depth
        color_index
        image_data
        picture_type

=head1 ASF (Windows Media Audio/Video)

=head2 INFO

The following metadata about a file may be returned.  Reading the ASF spec is encouraged if you
want to find out more about any of these values.

    audio_offset (byte offset to first data packet)
    audio_size
    broadcast (boolean, whether the file is a live broadcast or not)
    codec_list (array of information about codecs used in the file)
    creation_date (UNIX timestamp when file was created)
    data_packets
    drm_key
    drm_license_url
    drm_protection_type
    drm_data
    file_id (unique file ID)
    file_size
    index_blocks
    index_entry_interval (in milliseconds)
    index_offsets (byte offsets for each second of audio, per stream. Useful for seeking)
    index_specifiers (indicates which stream a given index_offset points to)
    language_list (array of languages referenced by the file's metadata)
    lossless (boolean)
    max_bitrate
    max_packet_size
    min_packet_size
    mutex_list (mutually exclusive stream information)
    play_duration_ms
    preroll
    script_commands
    script_types
    seekable (boolean, whether the file is seekable or not)
    send_duration_ms
    song_length_ms (the actual length of the audio, in milliseconds)
    dlna_profile (if file is compliant)

STREAMS

The streams array contains metadata related to an individul stream within the file.
The following metadata may be returned:
    
    DeviceConformanceTemplate
    IsVBR
    alt_bitrate
    alt_buffer_fullness
    alt_buffer_size
    avg_bitrate (most accurate bitrate for this stream)
    avg_bytes_per_sec (audio only)
    bitrate
    bits_per_sample (audio only)
    block_alignment (audio only)
    bpp (video only)
    buffer_fullness
    buffer_size
    channels (audio only)
    codec_id (audio only)
    compression_id (video only)
    encode_options
    encrypted (boolean)
    error_correction_type
    flag_seekable (boolean)
    height (video only)
    index_type
    language_index (offset into language_list array)
    max_object_size
    samplerate (in kHz) (audio only)
    samples_per_block
    stream_number
    stream_type
    super_block_align
    time_offset
    width (video only)

=head2 TAGS

Raw tags are returned.  Tags that occur more than once are returned as arrays.
In contrast to the other formats, tag keys are NOT capitalized. There is one special key:

WM/Picture

Pictures are returned as a hash with the following keys:

    image_type (numeric type, same as ID3v2 APIC)
    mime_type
    description
    image

=head1 WAV

=head2 INFO

The following metadata about a file may be returned.

    audio_offset
    audio_size
    bitrate (in bps)
    bits_per_sample
    block_align
    channels
    dlna_profile (if file is compliant)
    file_size
    format (WAV format code, 1 == PCM)
    id3_version (if an ID3v2 tag is found)
    samplerate (in kHz)
    song_length_ms

=head2 TAGS

WAV files can contain several different types of tags.  "Native" WAV tags
found in a LIST block may include these and others:

    IARL - Archival Location
    IART - Artist
    ICMS - Commissioned
    ICMT - Comment
    ICOP - Copyright
    ICRD - Creation Date
    ICRP - Cropped
    IENG - Engineer
    IGNR - Genre
    IKEY - Keywords
    IMED - Medium
    INAM - Name (Title)
    IPRD - Product (Album)
    ISBJ - Subject
    ISFT - Software
    ISRC - Source
    ISRF - Source Form
    TORG - Label
    LOCA - Location
    TVER - Version
    TURL - URL
    TLEN - Length
    ITCH - Technician
    TRCK - Track
    ITRK - Track

ID3v2 tags can also be embedded within WAV files.  These are returned exactly as for MP3 files.

=head1 AIFF

=head2 INFO

The following metadata about a file may be returned.

    audio_offset
    audio_size
    bitrate (in bps)
    bits_per_sample
    block_align
    channels
    compression_name (if AIFC)
    compression_type (if AIFC)
    dlna_profile (if file is compliant)
    file_size
    id3_version (if an ID3v2 tag is found)
    samplerate (in kHz)
    song_length_ms

=head2 TAGS

ID3v2 tags can be embedded within AIFF files.  These are returned exactly as for MP3 files.

=head1 MONKEY'S AUDIO (APE)

=head2 INFO

The following metadata about a file may be returned.

    audio_offset
    audio_size
    bitrate (in bps)
    channels
    compression
    file_size
    samplerate (in kHz)
    song_length_ms
    version

=head2 TAGS

APEv2 tags are returned as a hash of key/value pairs.

=head1 MUSEPACK

=head2 INFO

The following metadata about a file may be returned.

    audio_offset
    audio_size
    bitrate (in bps)
    channels
    encoder
    file_size
    profile
    samplerate (in kHz)
    song_length_ms

=head2 TAGS

Musepack uses APEv2 tags.  They are returned as a hash of key/value pairs.

=head1 WAVPACK

=head2

The following metadata about a file may be returned.

    audio_offset
    audio_size
    bitrate (in bps)
    bits_per_sample
    channels
    encoder_version
    file_size
    hybrid (1 if file is lossy) (v4 only)
    lossless (1 if file is lossless) (v4 only)
    samplerate
    song_length_ms
    total_samples

=head2 TAGS

WavPack uses APEv2 tags.  They are returned as a hash of key/value pairs.

=head1 

=head1 THANKS

Some code from the Rockbox project was very helpful in implementing ASF and
MP4 seeking.

Some of the file format parsing code was derived from the mt-daapd project,
and adapted by Netgear.  It has been heavily rewritten to fix bugs and add
more features.

The source to the original Netgear C scanner for SqueezeCenter is located
at L<http://svn.slimdevices.com/repos/slim/7.3/trunk/platforms/readynas/contrib/scanner>

The audio MD5 feature uses an MD5 implementation by L. Peter Deutsch,
E<lt>ghost@aladdin.comE<gt>.

=head1 SEE ALSO

ASF Spec L<http://www.microsoft.com/windows/windowsmedia/forpros/format/asfspec.aspx>

MP4 Info:
L<http://standards.iso.org/ittf/PubliclyAvailableStandards/c051533_ISO_IEC_14496-12_2008.zip>
L<http://www.geocities.com/xhelmboyx/quicktime/formats/mp4-layout.txt>

=head1 AUTHORS

Andy Grundman, E<lt>andy@slimdevices.comE<gt>

Dan Sully, E<lt>daniel@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 Logitech, Inc.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

=cut
