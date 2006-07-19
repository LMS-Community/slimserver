#
# Copyright (c) 2004, 2005, Jonathan Harris <jhar@cpan.org>
#
# This program is free software; you can redistribute it and/or modify it
# under the the same terms as Perl itself.
#

package MP4::Info;

use overload;
use strict;
use Carp;
use Symbol;
use Encode;
use Encode::Guess qw(latin1);

use vars qw(
	    $VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $AUTOLOAD
	    %data_atoms %other_atoms %container_atoms @mp4_genres
	   );

@ISA = 'Exporter';
@EXPORT      = qw(get_mp4tag get_mp4info);
@EXPORT_OK   = qw(use_mp4_utf8);
%EXPORT_TAGS = (
		utf8	=> [qw(use_mp4_utf8)],
		all	=> [@EXPORT, @EXPORT_OK]
	       );

$VERSION = '1.10';

my $debug = 0;


=head1 NAME

MP4::Info - Fetch info from MPEG-4 files (.mp4, .m4a, .m4p, .3gp)

=head1 SYNOPSIS

	#!perl -w
	use MP4::Info;
	my $file = 'Pearls_Before_Swine.m4a';

	my $tag = get_mp4tag($file) or die "No TAG info";
	printf "$file is a %s track\n", $tag->{GENRE};

	my $info = get_mp4info($file);
	printf "$file length is %d:%d\n", $info->{MM}, $info->{SS};

	my $mp4 = new MP4::Info $file;
	printf "$file length is %s, title is %s\n",
		$mp4->time, $mp4->title;

=head1 DESCRIPTION

The MP4::Info module can be used to extract tag and meta information from
MPEG-4 audio (AAC) and video files. It is designed as a drop-in replacement
for L<MP3::Info|MP3::Info>.

Note that this module does not allow you to update the information in MPEG-4
files.

=over 4

=item $mp4 = MP4::Info-E<gt>new(FILE)

OOP interface to the rest of the module. The same keys available via
C<get_mp4info> and C<get_mp4tag> are available via the returned object
(using upper case or lower case; but note that all-caps 'VERSION' will
return the module version, not the MPEG-4 version).

Passing a value to one of the methods will B<not> set the value for that tag
in the MPEG-4 file.

=cut

sub new
{
    my ($class, $file) = @_;

    # Supported tags
    my %tag_names =
	(
	 ALB => 1, APID => 1, ART => 1, CMT => 1, COVR => 1, CPIL => 1, CPRT => 1, DAY => 1, DISK => 1, GNRE => 1, GRP => 1, NAM => 1, RTNG => 1, TMPO => 1, TOO => 1, TRKN => 1, WRT => 1,
	 TITLE => 1, ARTIST => 1, ALBUM => 1, YEAR => 1, COMMENT => 1, GENRE => 1, TRACKNUM => 1,
	 VERSION => 1, LAYER => 1,
	 BITRATE => 1, FREQUENCY => 1, SIZE => 1,
	 SECS => 1, MM => 1, SS => 1, MS => 1, TIME => 1,
	 COPYRIGHT => 1, ENCODING => 1, ENCRYPTED => 1,
	);

    my $tags = get_mp4tag ($file) or return undef;
    my $self = {
		_permitted => \%tag_names,
		%$tags
	       };
    return bless $self, $class;
}


# Create accessor functions - see perltoot manpage
sub AUTOLOAD
{
    my $self = shift;
    my $type = ref($self) or croak "$self is not an object";
    my $name = $AUTOLOAD;
    $name =~ s/.*://;	# strip fully-qualified portion

    unless (exists $self->{_permitted}->{uc $name} )
    {
	croak "No method '$name' available in class $type";
    }

    # Ignore any parameter
    return $self->{uc $name};
}


sub DESTROY
{
}


############################################################################

=item use_mp4_utf8([STATUS])

Tells MP4::Info whether to assume that ambiguously encoded TAG info is UTF-8
or Latin-1. 1 is UTF-8, 0 is Latin-1. Default is UTF-8.

Function returns new status (1/0). If no argument is supplied, or an
unaccepted argument is supplied, function merely returns existing status.

This function is not exported by default, but may be exported
with the C<:utf8> or C<:all> export tag.

=cut

my $utf8 = 1;

sub use_mp4_utf8
{
    my ($val) = @_;
    $utf8 = $val if (($val == 0) || ($val == 1));
    return $utf8;
}


=item get_mp4tag (FILE)

Returns hash reference containing the tag information from the MP4 file.
The following keys may be defined:

	ALB	Album
	APID	Apple Store ID
	ART	Artist
	CMT	Comment
	COVR	Album art (typically jpeg data)
	CPIL	Compilation (boolean)
	CPRT	Copyright statement
	DAY	Year
	DISK	Disk number & total (2 integers)
	GNRE	Genre
	GRP	Grouping
	NAM	Title
	RTNG	Rating (integer)
	TMPO	Tempo (integer)
	TOO	Encoder
	TRKN	Track number & total (2 integers)
	WRT	Author or composer

For compatibility with L<MP3::Info|MP3::Info>, the MP3 ID3v1-style keys
TITLE, ARTIST, ALBUM, YEAR, COMMENT, GENRE and TRACKNUM are defined as
synonyms for NAM, ART, ALB, DAY, CMT, GNRE and TRKN[0].

Any and all of these keys may be undefined if the corresponding information
is missing from the MPEG-4 file.

On error, returns nothing and sets C<$@>.

=cut

sub get_mp4tag
{
    my ($file) = @_;
    my (%tags);

    return parse_file ($file, \%tags) ? undef : {%tags};
}


=item get_mp4info (FILE)

Returns hash reference containing file information from the MPEG-4 file.
The following keys may be defined:

	VERSION		MPEG version (=4)
	LAYER		MPEG layer description (=1 for compatibility with MP3::Info)
	BITRATE		bitrate in kbps (average for VBR files)
	FREQUENCY	frequency in kHz
	SIZE		bytes in audio stream

	SECS		total seconds, rounded to nearest second
	MM		minutes
	SS		leftover seconds
	MS		leftover milliseconds, rounded to nearest millisecond
	TIME		time in MM:SS, rounded to nearest second

	COPYRIGHT	boolean for audio is copyrighted
	ENCODING        Audio codec name. Possible values include:
			'mp4a' - AAC, aacPlus
			'alac' - Apple lossless
			'drms' - Apple encrypted AAC
			'samr' - 3GPP narrow-band AMR
			'sawb' - 3GPP wide-band AMR
			'enca' - Unspecified encrypted audio
	ENCRYPTED	boolean for audio data is encrypted

Any and all of these keys may be undefined if the corresponding information
is missing from the MPEG-4 file.

On error, returns nothing and sets C<$@>.

=cut

sub get_mp4info
{
    my ($file) = @_;
    my (%tags);

    return parse_file ($file, \%tags) ? undef : {%tags};
}


############################################################################
# No user-servicable parts below


# Interesting atoms that contain data in standard format.
# The items marked ??? contain integers - I don't know what these are for
# but return them anyway because the user might know.
my %data_atoms =
    (
     AART => 1,	# Album artist - returned in ART field no ART found
     ALB  => 1,
     ART  => 1,
     CMT  => 1,
     COVR => 1, # Cover art
     CPIL => 1,
     CPRT => 1,
     DAY  => 1,
     DISK => 1,
     GEN  => 1,	# Custom genre - returned in GNRE field no GNRE found
     GNRE => 1,	# Standard ID3/WinAmp genre
     GRP  => 1,
     NAM  => 1,
     RTNG => 1,
     TMPO => 1,
     TOO  => 1,
     TRKN => 1,
     WRT  => 1,
     # Apple store
     APID => 1,
     AKID => 1,	# ???
     ATID => 1,	# ???
     CNID => 1,	# ???
     GEID => 1,	# Some kind of watermarking ???
     PLID => 1,	# ???
     # 3GPP
     TITL => 1,	# title       - returned in NAM field no NAM found
     DSCP => 1, # description - returned in CMT field no CMT found
     #CPRT=> 1,
     PERF => 1, # performer   - returned in ART field no ART found
     AUTH => 1,	# author      - returned in WRT field no WRT found
     #GNRE=> 1,
     MEAN => 1,
     NAME => 1,
     DATA => 1,
    );

# More interesting atoms, but with non-standard data layouts
my %other_atoms =
    (
     MDAT => \&parse_mdat,
     META => \&parse_meta,
     MVHD => \&parse_mvhd,
     STSD => \&parse_stsd,
    );

# Standard container atoms that contain either kind of above atoms
my %container_atoms =
    (
     ILST => 1,
     MDIA => 1,
     MINF => 1,
     MOOV => 1,
     STBL => 1,
     TRAK => 1,
     UDTA => 1,
     '----' => 1,	# iTunes and aacgain info
    );


# Standard ID3 plus non-standard WinAmp genres
my @mp4_genres =
    (
     'N/A', 'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco',
     'Funk', 'Grunge', 'Hip-Hop', 'Jazz', 'Metal', 'New Age', 'Oldies',
     'Other', 'Pop', 'R&B', 'Rap', 'Reggae', 'Rock', 'Techno',
     'Industrial', 'Alternative', 'Ska', 'Death Metal', 'Pranks',
     'Soundtrack', 'Euro-Techno', 'Ambient', 'Trip-Hop', 'Vocal',
     'Jazz+Funk', 'Fusion', 'Trance', 'Classical', 'Instrumental',
     'Acid', 'House', 'Game', 'Sound Clip', 'Gospel', 'Noise',
     'AlternRock', 'Bass', 'Soul', 'Punk', 'Space', 'Meditative',
     'Instrumental Pop', 'Instrumental Rock', 'Ethnic', 'Gothic',
     'Darkwave', 'Techno-Industrial', 'Electronic', 'Pop-Folk',
     'Eurodance', 'Dream', 'Southern Rock', 'Comedy', 'Cult', 'Gangsta',
     'Top 40', 'Christian Rap', 'Pop/Funk', 'Jungle', 'Native American',
     'Cabaret', 'New Wave', 'Psychadelic', 'Rave', 'Showtunes',
     'Trailer', 'Lo-Fi', 'Tribal', 'Acid Punk', 'Acid Jazz', 'Polka',
     'Retro', 'Musical', 'Rock & Roll', 'Hard Rock', 'Folk',
     'Folk/Rock', 'National Folk', 'Swing', 'Fast-Fusion', 'Bebob',
     'Latin', 'Revival', 'Celtic', 'Bluegrass', 'Avantgarde',
     'Gothic Rock', 'Progressive Rock', 'Psychedelic Rock',
     'Symphonic Rock', 'Slow Rock', 'Big Band', 'Chorus',
     'Easy Listening', 'Acoustic', 'Humour', 'Speech', 'Chanson',
     'Opera', 'Chamber Music', 'Sonata', 'Symphony', 'Booty Bass',
     'Primus', 'Porn Groove', 'Satire', 'Slow Jam', 'Club', 'Tango',
     'Samba', 'Folklore', 'Ballad', 'Power Ballad', 'Rhythmic Soul',
     'Freestyle', 'Duet', 'Punk Rock', 'Drum Solo', 'A capella',
     'Euro-House', 'Dance Hall', 'Goa', 'Drum & Bass', 'Club House',
     'Hardcore', 'Terror', 'Indie', 'BritPop', 'NegerPunk',
     'Polsk Punk', 'Beat', 'Christian Gangsta', 'Heavy Metal',
     'Black Metal', 'Crossover', 'Contemporary C', 'Christian Rock',
     'Merengue', 'Salsa', 'Thrash Metal', 'Anime', 'JPop', 'SynthPop'
    );


sub parse_file
{
    my ($file, $tags) = @_;
    my ($fh, $err, $header);

    if (not (defined $file && $file ne ''))
    {
	$@ = 'No file specified';
	return -1;
    }

    if (ref $file)	# filehandle passed
    {
	$fh = $file;
    }
    else
    {
	$fh = gensym;
	if (not open $fh, "< $file\0")
	{
	    $@ = "Can't open $file: $!";
	    return -1;
	}
    }

    binmode $fh;

    # Sanity check that this looks vaguely like an MP4 file
    if ((read ($fh, $header, 8) != 8) || (lc substr ($header, 4) ne 'ftyp'))
    {
	close ($fh);
	$@ = 'Not an MPEG-4 file';
	return -1;
    }
    seek $fh, 0, 0;

    $err = parse_container($fh, 0, (stat $fh)[7], $tags);
    close ($fh);
    return $err if $err;

    # MP3::Info compatibility
    $tags->{TITLE}    = $tags->{NAM}     if defined ($tags->{NAM});
    $tags->{ARTIST}   = $tags->{ART}     if defined ($tags->{ART});
    $tags->{ALBUM}    = $tags->{ALB}     if defined ($tags->{ALB});
    $tags->{YEAR}     = $tags->{DAY}     if defined ($tags->{DAY});
    $tags->{COMMENT}  = $tags->{CMT}     if defined ($tags->{CMT});
    $tags->{GENRE}    = $tags->{GNRE}    if defined ($tags->{GNRE});
    $tags->{TRACKNUM} = $tags->{TRKN}[0] if defined ($tags->{TRKN});

    # remaining get_mp4info() stuff
    $tags->{VERSION}  = 4;
    $tags->{LAYER}    = 1                if defined ($tags->{FREQUENCY});
    $tags->{BITRATE}  = int (0.5 + $tags->{SIZE} / (($tags->{MM}*60+$tags->{SS}+$tags->{MS}/1000)*128))
	if (defined($tags->{SIZE}) && defined($tags->{MS}));	# A bit bogus
    $tags->{COPYRIGHT}= 1                if defined ($tags->{CPRT});
    $tags->{ENCRYPTED}= 0                unless defined ($tags->{ENCRYPTED});

    # Post process '---' container
    if ($tags->{MEAN} && ref($tags->{MEAN}) eq 'ARRAY')
    {
	for (my $i = 0; $i < scalar @{$tags->{MEAN}}; $i++)
	{
	    push @{$tags->{META}}, {
				    MEAN => $tags->{MEAN}->[$i],
				    NAME => $tags->{NAME}->[$i],
				    DATA => $tags->{DATA}->[$i],
				   };
	}

	delete $tags->{MEAN};
	delete $tags->{NAME};
	delete $tags->{DATA};
    }

    return 0;
}


# Pre:	$size=size of container contents
#	$fh points to start of container contents
# Post:	$fh points past end of container contents
sub parse_container
{
    my ($fh, $level, $size, $tags) = @_;
    my ($end, $err);

    $level++;
    $end = (tell $fh) + $size;
    while (tell $fh < $end)
    {
	$err = parse_atom($fh, $level, $end-(tell $fh), $tags);
	return $err if $err;
    }
    if (tell $fh != $end)
    {
	$@ = 'Parse error';
	return -1;
    }
    return 0;
}


# Pre:	$fh points to start of atom
#	$parentsize is remaining size of parent container
# Post:	$fh points past end of atom
sub parse_atom
{
    my ($fh, $level, $parentsize, $tags) = @_;
    my ($header, $size, $id, $err);
    if (read ($fh, $header, 8) != 8)
    {
	$@ = 'Premature eof';
	return -1;
    }

    ($size,$id) = unpack 'Na4', $header;
    if ($size==0)
    {
	# Special zero-sized atom at top-level means we're done (14496-12 S4.2)
	return 0 if $level==1;
	$@ = 'Parse error';
	return -1;
    }
    elsif ($size == 1)
    {
	# extended size
	my ($hi, $lo);
	if (read ($fh, $header, 8) != 8)
	{
	    $@ = 'Premature eof';
	    return -1;
	}
	($hi,$lo) = unpack 'NN', $header;
	$size=$hi*(2**32) + $lo;
	if ($size>$parentsize)
	{
	    # atom extends outside of parent container - skip to end of parent
	    seek $fh, $parentsize-16, 1;
	    return 0;
	}
	$size -= 16;
    }
    else
    {
	if ($size>$parentsize)
	{
	    # atom extends outside of parent container - skip to end of parent
	    seek $fh, $parentsize-8, 1;
	    return 0;
	}
	$size -= 8;
    }
    if ($size<0)
    {
	$@ = 'Parse error';
	return -1;
    }
    $id =~ s/[^\w\-]//;
    $id = uc $id;

    printf "%s%s: %d bytes\n", ' 'x(2*$level), $id, $size if $debug;

    if (defined($data_atoms{$id}))
    {
	return parse_data ($fh, $level, $size, $id, $tags);
    }
    elsif (defined($other_atoms{$id}))
    {
	return &{$other_atoms{$id}}($fh, $level, $size, $tags);
    }
    elsif ($container_atoms{$id})
    {
	return parse_container ($fh, $level, $size, $tags);
    }

    # Unkown atom - skip past it
    seek $fh, $size, 1;
    return 0;
}


# Pre:	$size=size of atom contents
#	$fh points to start of atom contents
# Post:	$fh points past end of atom contents
sub parse_mdat
{
    my ($fh, $level, $size, $tags) = @_;

    $tags->{SIZE} = 0 unless defined($tags->{SIZE});
    $tags->{SIZE} += $size;
    seek $fh, $size, 1;

    return 0;
}


# Pre:	$size=size of atom contents
#	$fh points to start of atom contents
# Post:	$fh points past end of atom contents
sub parse_meta
{
    my ($fh, $level, $size, $tags) = @_;

    # META is just a container preceded by a version field
    seek $fh, 4, 1;
    return parse_container ($fh, $level, $size-4, $tags);
}


# Pre:	$size=size of atom contents
#	$fh points to start of atom contents
# Post:	$fh points past end of atom contents
sub parse_mvhd
{
    my ($fh, $level, $size, $tags) = @_;
    my ($data, $version, $scale, $duration, $secs);

    if ($size < 32)
    {
	$@ = 'Parse error';
	return -1;
    }
    if (read ($fh, $data, $size) != $size)
    {
	$@ = 'Premature eof';
	return -1;
    }

    $version = unpack('C', $data) & 255;
    if ($version==0)
    {
	($scale,$duration) = unpack 'NN', substr ($data, 12, 8);
    }
    elsif ($version==1)
    {
	my ($hi,$lo);
	print "Long version\n" if $debug;
	($scale,$hi,$lo) = unpack 'NNN', substr ($data, 20, 12);
	$duration=$hi*(2**32) + $lo;
    }
    else
    {
	return 0;
    }

    printf "  %sDur/Scl=$duration/$scale\n", ' 'x(2*$level) if $debug;
    $secs=$duration/$scale;
    $tags->{SECS} = int (0.5+$secs);
    $tags->{MM}   = int ($secs/60);
    $tags->{SS}   = int ($secs - $tags->{MM}*60);
    $tags->{MS}   = int (0.5 + 1000*($secs - int ($secs)));
    $tags->{TIME} = sprintf "%02d:%02d",
	$tags->{MM}, $tags->{SECS} - $tags->{MM}*60;

    return 0;
}


# Pre:	$size=size of atom contents
#	$fh points to start of atom contents
# Post:	$fh points past end of atom contents
sub parse_stsd
{
    my ($fh, $level, $size, $tags) = @_;
    my ($data, $data_format);

    if ($size < 44)
    {
	$@ = 'Parse error';
	return -1;
    }
    if (read ($fh, $data, $size) != $size)
    {
	$@ = 'Premature eof';
	return -1;
    }

    # Assumes first entry in table contains the data
    printf "  %sSample=%s\n", ' 'x(2*$level), substr ($data, 12, 4) if $debug;
    $data_format = lc substr ($data, 12, 4);

    # Is this an audio track? (Ought to look for presence of an SMHD uncle
    # atom instead to allow for other audio data formats).
    if (($data_format eq 'mp4a') ||	# AAC, aacPlus
	($data_format eq 'alac') ||	# Apple lossless
	($data_format eq 'drms') ||	# Apple encrypted AAC
	($data_format eq 'samr') ||	# Narrow-band AMR
	($data_format eq 'sawb') ||	# AMR wide-band
	($data_format eq 'sawp') ||	# AMR wide-band +
	($data_format eq 'enca'))	# Generic encrypted audio
    {
	$tags->{ENCODING} = $data_format;
#	$version = unpack "n", substr ($data, 24, 2);
#       s8.16 is inconsistent. In practice, channels always appears == 2.
#	$tags->{STEREO}  = (unpack ("n", substr ($data, 32, 2))  >  1) ? 1 : 0;
#       Old Quicktime field. No longer used.
#	$tags->{VBR}     = (unpack ("n", substr ($data, 36, 2)) == -2) ? 1 : 0;
	$tags->{FREQUENCY} = unpack ('N', substr ($data, 40, 4)) / 65536000;
	printf "  %sFreq=%s\n", ' 'x(2*$level), $tags->{FREQUENCY} if $debug;
    }

    $tags->{ENCRYPTED}=1 if (($data_format eq 'drms') ||
			     (substr($data_format, 0, 3) eq 'enc'));

    return 0;
}


# Pre:	$size=size of atom contents
#	$fh points to start of atom contents
# Post:	$fh points past end of atom contents
sub parse_data
{
    my ($fh, $level, $size, $id, $tags) = @_;
    my ($data, $atom, $type);

    if (read ($fh, $data, $size) != $size)
    {
	$@ = 'Premature eof';
	return -1;
    }

    # 3GPP - different format when child of 'udta'
    if (($id eq 'TITL') ||
	($id eq 'DSCP') ||
	($id eq 'CPRT') ||
	($id eq 'PERF') ||
	($id eq 'AUTH') ||
	($id eq 'GNRE'))
    {
	my ($ver) = unpack 'N', $data;
	if ($ver == 0)
	{
	    ($size > 7) || return 0;
	    $size -= 7;
	    $type = 1;
	    $data = substr ($data, 6, $size);

	    if ($id eq 'TITL')
	    {
		return 0 if defined ($tags->{NAM});
		$id = 'NAM';
	    }
	    elsif ($id eq 'DSCP')
	    {
		return 0 if defined ($tags->{CMT});
		$id = 'CMT';
	    }
	    elsif ($id eq 'PERF')
	    {
		return 0 if defined ($tags->{ART});
		$id = 'ART';
	    }
	    elsif ($id eq 'AUTH')
	    {
		return 0 if defined ($tags->{WRT});
		$id = 'WRT';
	    }
	}
    }

    # Parse out the tuple that contains aacgain data, etc.
    if (($id eq 'MEAN') ||
	($id eq 'NAME') ||
	($id eq 'DATA'))
    {
	# The first 4 or 8 bytes are nulls.
	if ($id eq 'DATA')
	{
	    $data = substr ($data, 8);
	}
	else
	{
	    $data = substr ($data, 4);
	}

	push @{$tags->{$id}}, $data;
	return 0;
    }

    if (!defined($type))
    {
	($size > 16) || return 0;

	# Assumes first atom is the data atom we're after
	($size,$atom,$type) = unpack 'Na4N', $data;
	(lc $atom eq 'data') || return 0;
	($size > 16) || return 0;
	$size -= 16;
	$type &= 255;
	$data = substr ($data, 16, $size);
    }
    printf "  %sType=$type, Size=$size, $data\n", ' 'x(2*$level) if $debug;

    if ($id eq 'COVR')
    {
	# iTunes appears to use random data types for cover art
	$tags->{$id} = $data;
    }
    elsif ($type==0)	# 16bit int data array
    {
	my @ints = unpack 'n' x ($size / 2), $data;
	if ($id eq 'GNRE')
	{
	    $tags->{$id} = $mp4_genres[$ints[0]];
	}
	elsif ($id eq 'DISK' or $id eq 'TRKN')
	{
	    # Real 10.0 sometimes omits the second integer, but we require it
	    $tags->{$id} = [$ints[1], ($size>=6 ? $ints[2] : 0)] if ($size>=4);
	}
	elsif ($size>=4)
	{
	    $tags->{$id} = $ints[1];
	}
    }
    elsif ($type==1)	# Char data
    {
	# faac 1.24 and Real 10.0 encode data as unspecified 8 bit, which
	# goes against s8.28 of ISO/IEC 14496-12:2004. How tedious.
	# Assume data is utf8 if it could be utf8, otherwise assume latin1.
	my $decoder = Encode::Guess->guess ($data);
	$data = (ref ($decoder)) ?
	    $decoder->decode($data) :	# found one of utf8, utf16, latin1
	    decode($utf8 ? 'utf8' : 'latin1', $data);	# ambiguous so force

	if ($id eq 'GEN')
	{
	    return 0 if defined ($tags->{GNRE});
	    $id='GNRE';
	}
	elsif ($id eq 'AART')
	{
	    return 0 if defined ($tags->{ART});
	    $id = 'ART';
	}
	elsif ($id eq 'DAY')
	{
	    $data = substr ($data, 0, 4);
	    # Real 10.0 supplies DAY=0 instead of deleting the atom if the
	    # year is not known. What's wrong with these people?
	    return 0 if $data==0;
	}
	$tags->{$id} = $data;
    }
    elsif ($type==21)	# Integer data
    {
	# Convert to an integer if of an appropriate size
	if ($size==1)
	{
	    $tags->{$id} = unpack 'C', $data;
	}
	elsif ($size==2)
	{
	    $tags->{$id} = unpack 'n', $data;
	}
	elsif ($size==4)
	{
	    $tags->{$id} = unpack 'N', $data;
	}
	elsif ($size==8)
	{
	    my ($hi,$lo);
	    ($hi,$lo) = unpack 'NN', $data;
	    $tags->{$id} = $hi*(2**32) + $lo;
	}
	else
	{
	    # Non-standard size - just return the raw data
	    $tags->{$id} = $data;
	}
    }

    # Silently ignore other data types
    return 0;
}

1;

__END__

############################################################################

=back

=head1 BUGS

Doesn't support writing tag information to MPEG-4 files.

The calculation of bitrate is not very accurate, and tends to be under the
real bitrate.

If you find a bug, please send me a patch. If you cannot figure out why it
does not work for you, please put the MP4 file in a place where I can get it
(preferably via FTP, or HTTP) and send me mail regarding where I can get the
file, with a detailed description of the problem. I will keep a copy of the
file only for as long as necessary to debug the problem.

=head1 AUTHOR

Jonathan Harris E<lt>jhar@cpan.orgE<gt>.

=head1 THANKS

Chris Nandor E<lt>pudge@pobox.comE<gt> for writing L<MP3::Info|MP3::Info>

Dan Sully for cover art and iTunes/aacgain metadata patches.

=head1 SEE ALSO

=over 4

=item MP4::Info Project Page

L<http://search.cpan.org/~jhar/MP4-Info>

=item ISO 14496-12:2004 - Coding of audio-visual objects - Part 12: ISO base media file format

L<http://www.iso.ch/iso/en/ittf/PubliclyAvailableStandards/c038539_ISO_IEC_14496-12_2004(E).zip>

=item ISO 14496-14:2003 - Coding of audio-visual objects - Part 14: MP4 file format

L<http://www.iso.org/iso/en/CatalogueDetailPage.CatalogueDetail?CSNUMBER=38538>
(Not worth buying - the interesting stuff is in Part 12).

=item 3GPP TS 26.244 - 3GPP file format (3GP)

L<http://www.3gpp.org/ftp/Specs/html-info/26244.htm>

=item QuickTime File Format

L<http://developer.apple.com/documentation/QuickTime/QTFF/>

=item ISO 14496-1 Media Format

L<http://www.geocities.com/xhelmboyx/quicktime/formats/mp4-layout.txt>

=item MP3::Info

L<http://search.cpan.org/~cnandor/MP3-Info/>

=back

=head1 COPYRIGHT and LICENSE

Copyright (c) 2004, 2005, Jonathan Harris E<lt>jhar@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the the same terms as Perl itself.

=cut

# Local Variables:
# cperl-set-style: BSD
# End:
