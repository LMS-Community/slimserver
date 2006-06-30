#!/usr/bin/perl -w

package MPEG::Audio::Frame;

# BLECH! With 5.005_04 compatibility the pretty 0b000101001 notation went away,
# and now we're stuck using hex. Phooey!

use strict;
#use warnings;
use integer;

# fields::new is not used because it is very costly in such a tight loop. about 1/4th of the time, according to DProf
#use fields qw/
#	headhash
#	binhead
#	header
#	content
#	length
#	bitrate
#	sample
#	offset
#	crc_sum
#	calculated_sum
#	broken
#/;

use overload '""' => \&asbin;

use vars qw/$VERSION $free_bitrate $lax $mpeg25/;
$VERSION = 0.09;

$mpeg25 = 1; # normally support it

# constants and tables

BEGIN {
	if ($] <= 5.006){
		require Fcntl; Fcntl->import(qw/SEEK_CUR/);
	} else {
		require POSIX; POSIX->import(qw/SEEK_CUR/);
	}
}

my @version = (
	1,		# 0b00 MPEG 2.5
	undef,	# 0b01 is reserved
	1,		# 0b10 MPEG 2
	0,		# 0b11 MPEG 1
);

my @layer = (
	undef,	# 0b00 is reserved
	2,		# 0b01 Layer III
	1,		# 0b10 Layer II
	0,		# 0b11 Layer I
);

my @bitrates = (
		# 0/free 1   10  11  100  101  110  111  1000 1001 1010 1011 1100 1101 1110 # bits
	[	# mpeg 1
		[ undef, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448 ], # l1
		[ undef, 32, 48, 56, 64,  80,  96,  112, 128, 160, 192, 224, 256, 320, 384 ], # l2
		[ undef, 32, 40, 48, 56,  64,  80,  96,  112, 128, 160, 192, 224, 256, 320 ], # l3
	],
	[	# mpeg 2
		[ undef, 32, 48, 56, 64,  80,  96,  112, 128, 144, 160, 176, 192, 224, 256 ], # l1
		[ undef, 8,  16, 24, 32,  40,  48,  56,  64,  80,  96,  112, 128, 144, 160 ], # l3
		[ undef, 8,  16, 24, 32,  40,  48,  56,  64,  80,  96,  112, 128, 144, 160 ], # l3
	],
);

my @samples = (
	[ # MPEG 2.5
		11025, # 0b00
		12000, # 0b01
		8000,  # 0b10
		undef, # 0b11 is reserved
	],
	undef, # version 0b01 is reserved
	[ # MPEG 2
		22050, # 0b00
		24000, # 0b01
		16000, # 0b10
		undef, # 0b11 is reserved
	],
	[ # MPEG 1
		44100, # 0b00
		48000, # 0b01
		32000, # 0b10
		undef, # 0b11 is reserved
	],
);


# stolen from libmad, bin.c
my @crc_table = (
	0x0000, 0x8005, 0x800f, 0x000a, 0x801b, 0x001e, 0x0014, 0x8011,
	0x8033, 0x0036, 0x003c, 0x8039, 0x0028, 0x802d, 0x8027, 0x0022,
	0x8063, 0x0066, 0x006c, 0x8069, 0x0078, 0x807d, 0x8077, 0x0072,
	0x0050, 0x8055, 0x805f, 0x005a, 0x804b, 0x004e, 0x0044, 0x8041,
	0x80c3, 0x00c6, 0x00cc, 0x80c9, 0x00d8, 0x80dd, 0x80d7, 0x00d2,
	0x00f0, 0x80f5, 0x80ff, 0x00fa, 0x80eb, 0x00ee, 0x00e4, 0x80e1,
	0x00a0, 0x80a5, 0x80af, 0x00aa, 0x80bb, 0x00be, 0x00b4, 0x80b1,
	0x8093, 0x0096, 0x009c, 0x8099, 0x0088, 0x808d, 0x8087, 0x0082,

	0x8183, 0x0186, 0x018c, 0x8189, 0x0198, 0x819d, 0x8197, 0x0192,
	0x01b0, 0x81b5, 0x81bf, 0x01ba, 0x81ab, 0x01ae, 0x01a4, 0x81a1,
	0x01e0, 0x81e5, 0x81ef, 0x01ea, 0x81fb, 0x01fe, 0x01f4, 0x81f1,
	0x81d3, 0x01d6, 0x01dc, 0x81d9, 0x01c8, 0x81cd, 0x81c7, 0x01c2,
	0x0140, 0x8145, 0x814f, 0x014a, 0x815b, 0x015e, 0x0154, 0x8151,
	0x8173, 0x0176, 0x017c, 0x8179, 0x0168, 0x816d, 0x8167, 0x0162,
	0x8123, 0x0126, 0x012c, 0x8129, 0x0138, 0x813d, 0x8137, 0x0132,
	0x0110, 0x8115, 0x811f, 0x011a, 0x810b, 0x010e, 0x0104, 0x8101,

	0x8303, 0x0306, 0x030c, 0x8309, 0x0318, 0x831d, 0x8317, 0x0312,
	0x0330, 0x8335, 0x833f, 0x033a, 0x832b, 0x032e, 0x0324, 0x8321,
	0x0360, 0x8365, 0x836f, 0x036a, 0x837b, 0x037e, 0x0374, 0x8371,
	0x8353, 0x0356, 0x035c, 0x8359, 0x0348, 0x834d, 0x8347, 0x0342,
	0x03c0, 0x83c5, 0x83cf, 0x03ca, 0x83db, 0x03de, 0x03d4, 0x83d1,
	0x83f3, 0x03f6, 0x03fc, 0x83f9, 0x03e8, 0x83ed, 0x83e7, 0x03e2,
	0x83a3, 0x03a6, 0x03ac, 0x83a9, 0x03b8, 0x83bd, 0x83b7, 0x03b2,
	0x0390, 0x8395, 0x839f, 0x039a, 0x838b, 0x038e, 0x0384, 0x8381,

	0x0280, 0x8285, 0x828f, 0x028a, 0x829b, 0x029e, 0x0294, 0x8291,
	0x82b3, 0x02b6, 0x02bc, 0x82b9, 0x02a8, 0x82ad, 0x82a7, 0x02a2,
	0x82e3, 0x02e6, 0x02ec, 0x82e9, 0x02f8, 0x82fd, 0x82f7, 0x02f2,
	0x02d0, 0x82d5, 0x82df, 0x02da, 0x82cb, 0x02ce, 0x02c4, 0x82c1,
	0x8243, 0x0246, 0x024c, 0x8249, 0x0258, 0x825d, 0x8257, 0x0252,
	0x0270, 0x8275, 0x827f, 0x027a, 0x826b, 0x026e, 0x0264, 0x8261,
	0x0220, 0x8225, 0x822f, 0x022a, 0x823b, 0x023e, 0x0234, 0x8231,
	0x8213, 0x0216, 0x021c, 0x8219, 0x0208, 0x820d, 0x8207, 0x0202
);

sub CRC_POLY () { 0x8005 }

###

my @protbits = (
	[ 128, 256 ], # layer one
	undef,
	[ 136, 256 ], # layer three
);


my @consts;
sub B ($) { $_[0] == 12 ? 3 : (1 + ($_[0] / 4)) }
sub M ($) {
	my $s = 0;
	$s += $consts[$_][1] for (0 .. $_[0]-1);
	$s%=8;
	my $v = '';
	vec($v,8-$_,1) = 1 for $s+1 .. $s+$consts[$_[0]][1];
	"0x" . unpack("H*", $v);
}
sub R ($) { 
	my $i = 0;
	my $m = eval "M_$consts[$_[0]][0]()";
	$i++ until (($m >> $i) & 1);
	$i;
}

BEGIN {
	@consts = (
		# [ $name, $width ]
		[ SYNC => 3 ],
		[ VERSION => 2 ],
		[ LAYER => 2 ],
		[ CRC => 1 ],	
		[ BITRATE => 4 ],
		[ SAMPLE => 2 ],
		[ PAD => 1 ],
		[ PRIVATE => 1 ],
		[ CHANMODE => 2 ],
		[ MODEXT => 2 ],
		[ COPY => 1 ],
		[ HOME => 1 ],
		[ EMPH => 2 ],
	);
	my $i = 0;
	foreach my $c (@consts){
		my $CONST = $c->[0];
		eval "sub $CONST () { $i }"; # offset in $self->{header}
		eval "sub M_$CONST () { " . M($i) ." }"; # bit mask
		eval "sub B_$CONST () { " . B($i) . " }"; # offset in read()'s @hb
		eval "sub R_$CONST () { " . R($i) . " }"; # amount to right shift
		$i++;
	}
}


# constructor and work horse
sub read {
	my $pkg = shift || return undef;
	my $fh = shift || return undef;
	
	local $/ = "\xff"; # get readline to find 8 bits of sync.
	
	my $offset;	# where in the handle
	my $header; # the binary header data... what a fabulous pun.
	my @hr; # an array of integer

	OUTER: {
		while (defined(<$fh>)){ # readline, readline, find me a header, make me a header, catch me a header. somewhate wasteful, perhaps. But I don't want to seek.
			$header = "\xff";
			(read $fh, $header, 3, 1 or return undef) == 3 or return undef; # read the rest of the header

			my @hb = unpack("CCCC",$header); # an array of 4 integers for convenient access, each representing a byte of the header
			# I wish vec could take non powers of 2 for the bit width param... *sigh*
			# make sure there are no illegal values in the header
			($hr[SYNC]		= ($hb[B_SYNC] 		& M_SYNC)		>> R_SYNC)		!= 0x07 and next; # see if the sync remains
			($hr[VERSION]	= ($hb[B_VERSION]	& M_VERSION)	>> R_VERSION)	== 0x00 and ($mpeg25 or next);
			($hr[VERSION])														== 0x01 and next;
			($hr[LAYER]		= ($hb[B_LAYER]		& M_LAYER)		>> R_LAYER)		== 0x00 and next;
			($hr[BITRATE]	= ($hb[B_BITRATE]	& M_BITRATE)	>> R_BITRATE)	== 0x0f and next;
			($hr[SAMPLE]	= ($hb[B_SAMPLE]	& M_SAMPLE) 	>> R_SAMPLE)	== 0x03 and next;
			($hr[EMPH]		= ($hb[B_EMPH]		& M_EMPH) 		>> R_EMPH)		== 0x02 and ($lax or next);
			# and drink up all that we don't bother verifying
			$hr[CRC]		= ($hb[B_CRC] & M_CRC) >> R_CRC;
			$hr[PAD]		= ($hb[B_PAD] & M_PAD) >> R_PAD;
			$hr[PRIVATE]	= ($hb[B_PRIVATE] & M_PRIVATE) >> R_PRIVATE;
			$hr[CHANMODE]	= ($hb[B_CHANMODE] & M_CHANMODE) >> R_CHANMODE;
			$hr[MODEXT]		= ($hb[B_MODEXT] & M_MODEXT) >> R_MODEXT;
			$hr[COPY]		= ($hb[B_COPY] & M_COPY) >> R_COPY;
			$hr[HOME]		= ($hb[B_HOME] & M_HOME) >> R_HOME;

			# record the offset	
			$offset = tell($fh) - 4;

			last OUTER; # were done reading for the header
		}
		seek $fh, -3, SEEK_CUR;
		return undef;
	}

	
	my $sum = '';
	if (!$hr[CRC]){
		(read $fh, $sum, 2 or return undef) == 2 or return undef;
	}

	my $bitrate	= $bitrates[$version[$hr[VERSION]]][$layer[$hr[LAYER]]][$hr[BITRATE]] || $free_bitrate or return undef;
	my $sample	= $samples[$hr[VERSION]][$hr[SAMPLE]];

	my $use_smaller = $hr[VERSION] == 2 || $hr[VERSION] == 0; # FIXME VERSION == 2 means no support for MPEG2 multichannel
	my $length = $layer[$hr[LAYER]]
		?  (($use_smaller ? 72 : 144) * ($bitrate * 1000) / $sample + $hr[PAD])		# layers 2 & 3
		: ((($use_smaller ? 6  : 12 ) * ($bitrate * 1000) / $sample + $hr[PAD]) * 4);	# layer 1
	
	my $clength = $length - 4 - ($hr[CRC] ? 0 : 2);
	(read $fh, my($content), $clength or return undef) == $clength or return undef; # appearantly header length is included... learned this the hard way.
	
	my $self = bless {}, $pkg;
	
	%$self = (
		binhead	=> $header,		# binary header
		header	=> \@hr,		# array of integer header records
		content	=> $content,	# the actuaol content of the frame, excluding the header and crc
		length	=> $length,		# the length of the header + content == length($frame->content()) + 4 + ($frame->crc() ? 2 : 0);
		bitrate	=> $bitrate,	# the bitrate, in kilobits
		sample	=> $sample,		# the sample rate, in Hz
		offset	=> $offset,		# the offset where the header was found in the handle, based on tell
		crc_sum	=> $sum,		# the bytes of the network order short that is the crc sum
	);

	$self;
}

# methods

sub asbin { # binary representation of the frame
	my $self = shift;
	$self->{binhead} . $self->{crc_sum} . $self->{content}
}

sub content { # byte content of frame, no header, no CRC sum
	my $self = shift;
	$self->{content}
}

sub header { # array of records in list context, binary header in scalar context
	my $self = shift;
	wantarray
		? @{ $self->{header} }
		: $self->{binhead}
}

sub crc	{ # the actual sum bytes
	my $self = shift;
	$self->{crc_sum}
}

sub has_crc { # does a crc exist?
	my $self = shift;
	not $self->{header}[CRC];
}

sub length { # length of frame in bytes, including header and header CRC
	my $self = shift;
	$self->{length}
}

sub bitrate { # symbolic bit rate
	my $self = shift;
	$self->{bitrate}
}

sub free_bitrate {
	my $self = shift;
	$self->{header}[BITRATE] == 0;
}

sub sample { # symbolic sample rate
	my $self = shift;
	$self->{sample}
}

sub channels { # the data we want is the data in the header in this case
	my $self = shift;
	$self->{header}[CHANMODE]
}

sub stereo {
	my $self = shift;
	$self->channels == 0;
}

sub joint_stereo {
	my $self = shift;
	$self->channels == 1;
}

sub dual_channel {
	my $self = shift;
	$self->channels == 2;
}

sub mono {
	my $self = shift;
	$self->channels == 3;
}

sub modext {
	my $self = shift;
	$self->{header}[MODEXT];
}

sub _jmodes {
	my $self = shift;
	$self->layer3 || die "Joint stereo modes only make sense with layer III"
}

sub normal_joint_stereo {
	my $self = shift;
	$self->_jmodes && $self->joint_stereo && !$self->intensity_stereo && !$self->ms_stereo;
}

sub intensity_stereo {
	my $self = shift;
	$self->_jmodes and $self->joint_stereo and $self->modext % 2 == 1;
}

sub intensity_stereo_only {
	my $self = shift;
	$self->_jmodes && $self->intensity_stereo && !$self->ms_stereo;
}

sub ms_stereo {
	my $self = shift;
	$self->_jmodes and $self->joint_stereo and $self->modext > 1;
}

sub ms_stereo_only {
	my $self = shift;
	$self->_jmodes and $self->ms_stereo && !$self->intensity_stereo;
}

sub ms_and_intensity_stereo {
	my $self = shift;
	$self->_jmodes and $self->ms_stereo && $self->intensity_stereo;
}
*intensity_and_ms_stereo = \&ms_and_intensity_stereo;

sub _bands {
	my $self = shift;
	!$self->layer3 || die "Intensity stereo bands only make sense with layers I I";
}

sub band_4 {
	my $self = shift;
	$self->_bands and $self->modext == 0;
}

sub band_8 {
	my $self = shift;
	$self->_bands and $self->modext == 1;
}

sub band_12 {
	my $self = shift;
	$self->_bands and $self->modext == 2;
}

sub band_16 {
	my $self = shift;
	$self->_bands and $self->modext == 3;
}

sub any_stereo {
	my $self = shift;
	$self->stereo or $self->joint_stereo;
}

sub seconds { # duration in floating point seconds
	my $self = shift;

	no integer;
	$layer[$self->{header}[LAYER]]
		? (($version[$self->{header}[VERSION]] == 0 ? 1152 : 576) / $self->sample())
		: (($version[$self->{header}[VERSION]] == 0 ? 384 : 192) / $self->sample())
}

sub framerate {
	no integer;
	1 / $_[0]->seconds();
}

sub pad	{
	my $self = shift;
	$self->{header}[PAD];
}

sub home {
	my $self = shift;
	$self->{header}[HOME];
}

sub copyright {
	my $self = shift;
	$self->{header}[COPY];
}

sub private {
	my $self = shift;
	$self->{header}[PRIVATE];
}

sub version {
	my $self = shift;
	$self->{header}[VERSION];
}

sub mpeg1 {
	my $self = shift;
	$self->version == 3;
}

sub mpeg2 {
	my $self = shift;
	$self->version == 2;
}

sub mpeg25 {
	my $self = shift;
	$self->version == 0;
}

sub layer {
	my $self = shift;
	$self->{header}[LAYER];
}

sub layer1 {
	my $self = shift;
	$self->layer == 3;
}

sub layer2 {
	my $self = shift;
	$self->layer == 2;
}

sub layer3 {
	my $self = shift;
	$self->layer == 1;
}

sub emph {
	my $self = shift;
	$self->{header}[EMPH];
}
*emphasize = \&emph;
*emphasise = \&emph;
*emphasis = \&emph;

sub offset { # the position in the handle where the frame was found
	my $self = shift;
	$self->{offset}
}

sub crc_ok {
	not shift->broken;
}

sub broken { # was the crc broken?
    my $self = shift;
    if (not defined $self->{broken}){
		return $self->{broken} = 0 unless $self->has_crc; # we assume it's OK if we have no CRC at all
		return $self->{broken} = 0 unless (($self->{header}[LAYER] & 0x02) == 0x00); # can't sum

		my $bits = $protbits[$layer[$self->{header}[LAYER]]][$self->{header}[CHANMODE] == 0x03 ? 0 : 1 ];
		my $i;
			
		my $c = 0xffff;
			
		$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ord((substr($self->{binhead},2,1)))) & 0xff];
		$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ord((substr($self->{binhead},3,1)))) & 0xff];

		for ($i = 0; $bits >= 32; do { $bits-=32; $i+=4 }){
			my $data = unpack("N",substr($self->{content},$i,4));
				
			$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ($data >> 24)) & 0xff];
			$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ($data >> 16)) & 0xff];
			$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ($data >>  8)) & 0xff];
			$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ ($data >>  0)) & 0xff];
				
		}
		while ($bits >= 8){
			$c = ($c << 8) ^ $crc_table[(($c >> 8) ^ (ord(substr($self->{content},$i++,1)))) & 0xff];
		} continue { $bits -= 8 }
		$self->{broken} = (( $c & 0xffff ) != unpack("n",$self->{crc_sum})) ? 1 : 0;
    }

    return $self->{broken};
}


# tie hack

sub TIEHANDLE { bless \$_[1],$_[0] } # encapsulate the handle to save on unblessing and stuff
sub READLINE { (ref $_[0])->read(${$_[0]}) } # read from the encapsulated handle

1; # keep your mother happy

__END__

=pod

=head1 NAME

MPEG::Audio::Frame - a class for weeding out MPEG audio frames out of a file
handle.

=head1 SYNOPSIS

	use MPEG::Audio::Frame;

	open FILE,"file.mp3";

	while(my $frame = MPEG::Audio::Frame->read(\*FILE)){
		print $frame->offset(), ": ", $frame->bitrate(), "Kbps/", $frame->sample()/1000, "KHz\n"; # or something.
	}

=head1 DESCRIPTION

A very simple, pure Perl module which allows parsing out data from mp3 files,
or streams, and chunking them up into different frames. You can use this to
accurately determine the length of an mp3, filter nonaudio data, or chunk up
the file for streaming via datagram. Virtually anything is possible.

=head1 MPEG FORMAT SUPPORT

L<MPEG::Audio::Frame> supports various types of MPEG data.

=over 4

=item MPEG-1

Any type of MPEG1 audio is supported, including the backwards compatible
multichannel extensions to MPEG-1. See F<t/20-mpeg1-*.t>.

=item MPEG-2 Multichannel

MPEG 2 has a variation on the multichannel extension, which is not backwards
compatible. It still structurally resembles MPEG 1, but there is no publically
documented method for telling apart MPEG-2 MC from MPEG-2 LSF.

=item MPEG-2 LSF

There is another type of MPEG 2, which is more similar to MPEG 2.5, called
MPEG-2 low sampling frequency. It the only type of MPEG-2 supported. See
F<t/20-mpeg2-22050>.

=item MPEG-2.5

This unofficial standard is also supported. Since it is unofficial, and
sometimes causes problems when streams contain garbage between frames, it can be disabled.

There is a test, F<t/20-mpeg2-test30.t>, which fails if MPEG 2.5 is allowed. It
is not included in the distribution because MPEG-2 multichannel is not
supported and those tests are just failing bloat. Ask me about darcs access if
you're curious.

=back

=head1 METHODS

There are two types of methods in this module, aside from the constructor
C<read>.

The first kind are accessors, which return the value of a certain header field,
like C<version>, which will return the actual integer value of the bits of that
field.

The second kind is sorts of queries on the accessible data. For example,
C<is_mono> checks to see of the C<channels> accessor returns the value for
mono.

=over 4

=item read GLOB

This is the constructor method. It receives a reference to a filehandle, and
reads the next (hopefully) valid frame it can find on the stream. Please make
sure use binmode if you're on a funny platform - the module doesn't know the
difference, and shouldn't change stuff, IMHO.

=item offset

The offset where the frame was found in the handle, as reported by tell().

=item asbin

Returns the binary data extracted from the handle. This is
(definately|probably) a valid MPEG 1 or 2 audio frame.

asbin is also called via the overloaded operator "", so if you treat the frame
object like a string, you'd get the binary data you'd get by calling asbin
directly.

=item content

Returns the content of the frame, minus the header and the crc. This is
(definately|probably) a valid MPEG 1 or 2 audio frame entity.

=item header

Returns a list of integers in list context, or a 4 byte long binary string in
scalar context. The hash represents the header, split into it's parts, with
bits translated into '0' and '1'. The binary string is (definately|probably) a
valid MPEG 1 or 2 audio frame header.

=item crc

Returns the bytes of the checksum, as extracted from the handle. This is
(definately) a valid checksum, unless there was none in the frame, in which
case it will be undef. It (definately|probably) applies to the frame.

=item version

Returns the value of the MPEG version bits.

=item layer

Returns the value of the layer bits.

=item length

Returns the length, in bytes, of the entire frame. This is the length of the
content, plus the four bytes of the header, and the two bytes of the crc, if
applicable.

=item bitrate

Returns the bitrate in kilobits. Note that 128Kbps means 128000, and not
131072. This not the actual integer value from the header.

=item free_bitrate

This returns true if the bit rate is free. Since free bit rate files have a
constant rate, that is anything. The bitrate must be known in advance for the
file to be parsable.

See C<$MPEG::Audio::Frame::free_bitrate>.

=item sample

Returns the sample rate in Hz, not the integer value from the header.

=item seconds

Returns the length, in floating seconds, of the frame.

=item framerate

Given a constant rate file, of frames like this one, the value returned would
be the number of such frames needed to get one second of audio.

=item channels

Returns the integer value of the channels bits.

=item pad

Wether or not the frame was padded.

=item private

Returns the value of the private bit.

=item copyright

Returns the vavlue of the copyright bit.

=item home

Returns the value of the original home bit.

=item modext

The mode extension bits. It is used to specify type of joint stereo to use in
layer III, and the bands to apply intensity stereo to on layers I and II.

=item emphasis

=item emph

=item emphasize

=item emphasise

Returns the value of the emphasis bits, 

=item broken

=item crc_ok

This returns true if the CRC computation failed for a protected layer I or III
frame. It will always return false on unprotected frames, because we can't know
if they're bad or not.

C<crc_ok> is the opposite.

=item has_crc

Whether not the frame has a checksum.

=item mono

=item dual_channel

Dual channel is not stereo, but two separate mono channels.

=item stereo

Stereo means 'normal' stereo... That is two channels.

=item any_stereo

Some kind of variation on two channel audio that isn't C<dual_channel>.

=item joint_stereo

Joint stereo is a type of stereo.

=item normal_joint_stereo

Neither of the below joint stereo variations.

Intensity and MS stereo apply to layer III.

=item intensity_stereo

Intensity stereo is a type of joint stereo.

Note that this method also dies on layers I or II. This is behavior might
change if I change my mind and decide that this is stupid.

Since layers I and II joint stereo is always implemented in terms of intensity
stereo, however, I reckoned it was more appropriate to make this apply only to
the layer III case, to provide stricter error checking.

=item intensity_and_ms_stereo

Both intensity and ms stereo.

=item intensity_stereo_only

Intensity stereo without ms stereo.

=item ms_stereo

=item ms_and_intensity_stereo

=item ms_stereo_only

See above.

=item band_4

=item band_8

=item band_12

=item band_16

These methods all query whether the mode extension field specifies band N to
31. They only apply to layers I and II.

=item mpeg1

=item mpeg2

=item mpeg25

The whether the version is equal to N.

=item layer1

=item layer2

=item layer3

Same for layers.

=back

=head1 PACKAGE VARIBLES

=over 4

=item $MPEG::Audio::Frame::lax

This tells L<MPEG::Audio::Frame> to let non-critical data invalidations pass.
The L<emphasize> value, for example, has an invalid value, C<2>, which is
meaningless to L<MPEG::Audio::Frame>.

This does not apply to any of the header values used to actually mine the data,
and any invalid values in these fields (like the MPEG version, or the bitrate)
cause the current header start to be skipped under the assumption that it is
simply not MPEG data.

This really only applies to the emphasis header field.

=item $MPEG::Audio::Frame::free_bitrate

This is the bitrate to assume when frames are marked with the 'free' bit rate.

This is undefined by default.

=item $MPEG::Audio::Frame::mpeg25

When true, as is the default, MPEG-2.5 is supported. If that causes trouble, it
can be disabled.

=back

=head1 TIED HANDLE USAGE

You can also read frame objects via the readline operator by tying a filehandle
to this package in the following manner:

	tie *MP3, 'MPEG::Audio::Frame',*FH;
	while(<MP3>){
		print "frame at ", $_->offset(), "\n";
	}

Way cool.

=head1 HISTORY

=head2 0.09 January 13th 2005

Yasuhiro Sasama submitted a patch to properly handle MPEG2.5 files.

Dropped support for MPEG-2 multichannel in favour of MPEG-2 LSF. No one seems
to support MC. If you know how to tell them apart, or have the money to pay the
ISO guys for the MC/LSF docs, and would like support for them in this module,
contact me. Otherwise it doesn't look like it's going to happen.

Completely rehauled everything internal. Now nearly 50% faster (thanks
L<Devel::DProf> and L<Devel::Cover>). B<< NOTE! This introduces an incompatible
change! $frame->header will no longer return a hash of string values, but an
array of integers >>.

Test suite redone and expanded. Some "official" test files included.

Repackaged with L<Module::Build>, and various goodnesses.

Trashed the useless README

Perl 5.005_04 compatibility.

Wrapped pod.

=head2 0.08 October 21st 2003

Johan Vromans cought a glitch in asbin, which surfaced in 0.07 - now fixed.

=head2 0.07 October 19th 2003

Made broken compute the CRC on demand instead of always.

Cryptographically signed distribution.

=head2 0.06 October 17th 2003

Fixed some doc errors, thanks to Nikolaus Schusser and Suleyman Gulsuner.

Fixed CRC computation on little endian machines.

=head2 0.05 August 3rd 2003

Added overloading of object to asbin by default.

Added real CRC checking for layers III and I (layer II is a longer story).

=head2 0.04 August 2nd 2003

Fixed the calculation of frame lengths when a CRC is present, thanks to Johan
Vromans.

=head2 0.03 April 19th 2003

Reimplemented C<offset> method, which came out of sync whilst working on
various copies, thanks to Jeff Anderson.

=head2 0.02 April 18th 2003

Some minor documentation and distribution fixes were made.

=head1 AUTHOR

Yuval Kojman <nothingmuch@altern.org>

=head1 COPYRIGHT

	Copyright (c) 2003 Yuval Kojman. All rights reserved
	This program is free software; you can redistribute
	it and/or modify it under the same terms as Perl itself.

=cut
