package Slim::Hardware::mas35x9;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Hardware::mas35x9

=head1 DESCRIPTION

L<Slim::Hardware::mas35x9>

=cut

use strict;

my %masRegisters  = ();
my $isInitialized = 0;

#my $deviceWrite     = "3c";  # device read/write addr for DVS connected to VSS
#my $deviceRead      = "3d";  # for DVS connected to VCC, use 3e/3f
my $deviceWrite     = "3e";
my $deviceRead      = "3f";

my $subaddr_control = "6a";  # for writing the CONTROL register
my $subaddr_dccf    = "76";  # dc/dc #1
my $subaddr_dcfr    = "77";  # dc/dc #2
my $subaddr_dwrite  = "68";  # data write
my $subaddr_dread   = "69";  # data read
my $subaddr_cwrite  = "6c";  # codec write
my $subaddr_cread   = "6d";  # codec read

my $command_run0     = "0";
my $command_run1     = "1";
my $command_run2     = "2";
my $command_run3     = "3";
my $command_readanc  = "5";
my $command_prog     = "6";
my $command_readver  = "7";
my $command_readreg  = "a";
my $command_writereg = "b";
my $command_read_d0  = "c";
my $command_read_d1  = "d";
my $command_write_d0 = "e";
my $command_write_d1 = "f";

# initialization values:
			
my $init_control = "4f00";  # 01       AGNDC=1.3V 
                            # 00       disable DC/DC converters
                            # 1111     enable and reset codec/core
                            # 0        no clock divisor
                            # 0000000  reserved


my $masRegisters='

# special registers: these are the subaddr followed by just a 16-bit value
# see data sheet, page 20-22

control		direct:006a    # these are the subaddresses listed above, not register address like
dccf	 	direct:0076    # the ones below
dcfr		direct:0077

# d0 memory cells (pages 28..37)

AppSelect         d0:034b	# which codecs to enable
AppRunning        d0:034c	# which codec is actually running
IOControlMain     d0:0346	# select io ports and formats
InterfaceControl  d0:0347	# more io config
OfreqControl      d0:0348	# oscillator freq in kHz
OutClkConfig      d0:0349	# configure CLKO options
SoftMute          d0:0350	# SoftMute
SpdOutBits        d0:0351	# s/pdif channel status
UserControl       d0:034d	# encode/decode mode, pause, decoding speed
SDISDOConfig      d0:034e	# more serial IO options
g729_Interface    d0:034f	# interface options only for g.729 mode
in_L              d0:0352	# volume input control: left gain
in_R              d0:0353	# volume input control: right gain
out_LL            d0:0354	# volume output control: left->left gain
out_LR            d0:0355	# volume output control: left->right gain
out_RL            d0:0356	# volume output control: right->left gain
out_RR            d0:0357	# volume output control: right->right gain
AACbitrate        d0:0fcf	# aac bit rate in bps
MPEGFrameCount    d0:0fd0	# number of frames decoded since last sync
MPEGStatus1       d0:0fd1	# MPEG header and status information
MPEGStatus2       d0:0fd2	# more header info (bit rate, sampling freq)
CRCErrorCount     d0:0fd3       # CRC error counter
NumAncillaryBits  d0:0fd4	# number of ancillary bits in the current frame
AncDataBegin      d0:0fd5	# begin ancillary data (p.38)
AncDataEnd        d0:0ff1	# end ancillary data

# writeable codec control registers on i2c subaddress 0x6c (see pages 41..

CONV_CONF         cwrite:0000	# DAC/ADC enable/disable/gain
ADC_IN_MODE       cwrite:0008	# ADC config: mono/stereo, deemphasis
DAC_IN_ADC        cwrite:0006	# D/A converter source mixer: ADC scale
DAC_IN_DSP        cwrite:0007	# DSP scale
DAC_OUT_MODE      cwrite:000e	# D/A converter output mode
BASS		  cwrite:0014	# bass range
TREBLE		  cwrite:0015	# treble
LDNESS		  cwrite:001e	# loudneess gain, mode
MDB_STR		  cwrite:0022	# Micronas Dynamic Bass effect strength
MDB_HAR		  cwrite:0023	# MDB harmonics
MDB_FC		  cwrite:0024	# MDB center frequency
MDB_SHAPE	  cwrite:0021	# MDB shape/switch
MDB_VOLUME	  cwrite:0012	# Automatic volume correction on/off, decay time
BALANCE           cwrite:0011	# Balance range
VOLUME		  cwrite:0010	# volume

# readable codec control registers on i2c subaddress 0x6d (see pages 47..

QPEAK_L		  cread:000A	# input a/d quasi-peak detector readout, left
QPEAK_R		  cread:000B	# "" right
QPEAK_L		  cread:000C	# output quasi-peak detector readout, left
QPEAK_R		  cread:000D	# "" right

#END
';

sub init {
	my $line;
	foreach $line (split(/\n/, $masRegisters)) {
		$line=~s/\s*#.*//;
		$line=~s/^\s+$//;
		next unless ($line=~/^(\S+)\s+(.+:.+)$/);

		$masRegisters{$1}=$2;
	}
	
	$isInitialized=1;
};

my @volumetable = 
        	("FFFFA", "FFFF9", "FFFF9", "FFFF8", "FFFF7", "FFFF6", "FFFF4", "FFFF3", "FFFF1", "FFFEF", 
        	"FFFED", "FFFEB", "FFFE9", "FFFE6", "FFFE3", "FFFDF", "FFFDB", "FFFD6", "FFFD1", "FFFCC", 
        	"FFFC5", "FFFBE", "FFFB6", "FFFAD", "FFFA3", "FFF97", "FFF8B", "FFF7C", "FFF6C", "FFF5A", 
        	"FFF46", "FFF2F", "FFF16", "FFEF9", "FFED9", "FFEB5", "FFE8D", "FFE60", "FFE2D", "FFDF4", 
        	"FFDB4", "FFD6C", "FFD1B", "FFCC1", "FFC5C", "FFBEA", "FFB6A", "FFADB", "FFA3A", "FF986", 
        	"FF8BC", "FF7D9", "FF6DA", "FF5BC", "FF47C", "FF314", "FF180", "FEFBB", "FEDBF", "FEB85", 
        	"FE905", "FE638", "FE312", "FDF8B", "FDB95", "FD723", "FD227", "FCC8E", "FC648", "FBF3D", 
        	"FB756", "FAE78", "FA485", "F995B", "F8CD5", "F7EC8", "F6F03", "F5D52", "F4979", "F3333", 
        	"F1A36", "EFE2C", "EDEB6", "EBB6A", "E93CF", "E675F", "E3583", "DFD91", "DBECC", "D785E", 
        	"D2958", "CD0AD", "C6D31", "BFD92", "B8053", "AF3CD", "A5621", "9A537", "8DEB8", "80000");

sub dbToHex {
	my $db=shift;
	return $volumetable[$db];
}

#applies to both bass and treble
my @tonetable = (
	 'A000' #-12db
	,'A800' #-11db
	,'B000' #-10db
	,'B800' #-9db
	,'C000' #-8db
	,'C800' #-7db
	,'D000' #-6db
	,'D800' #-5db
	,'E000' #-4db
	,'E800' #-3db
	,'F000' #-2db
	,'F800' #-1db
	,'0000' #0db
	,'0800' #+1db
	,'1000' #+2db
	,'1800' #+3db
	,'2000' #+4db
	,'2800' #+5db
	,'3000' #+6db
	,'3800' #+7db
	,'4000' #+8db
	,'4800' #+9db
	,'5000' #+10db
	,'5800' #+11db
	,'6000' #+12db
);

sub getToneCode {
	my $toneSetting = shift;
	#my $toneType = shift; #not needed here
	my $index = int(($toneSetting / Slim::Player::Player::maxTreble()) * (scalar(@tonetable)-1));

	return $tonetable[$index];
}

#--------------------------------------------
# Generate the i2c sequence for writing to the MAS35x9

sub masWrite {
	my ($key, $data) = @_;

	init() unless $isInitialized;

	my (@a,@d) = ((),());

	# This *must* be undef!
	my $i2c = undef;

	die "Unknown MAS35x9 setting: $key\n" unless ($masRegisters{$key});

	$masRegisters{$key}=~/(.+):(.+)/ || die "bad micronas bank/addr for $key";
	my $bank    = $1;
	my $address = $2;

	# Turn address and data into an array of nibbles with least significant at [0]
	while ((length($address)) > 0) {
		push @a, chop($address); 
	}

	if (defined $data) {

		$data =~ s/[^0-9a-fA-F]//g;

		while (length($data)>0) {
			push @d, chop($data); 
		}
	}

	# See MAS35x9 data sheet p.24 for exaplanation of the i2c data formats
	if ($bank eq 'direct') {
		# a[1..0] actually contains the subaddress for these:
		$i2c = "s$deviceWrite $a[1]$a[0] $d[3]$d[2]p$d[1]$d[0]";
	
	} elsif ($bank eq 'd0') {

		$i2c = 	"s$deviceWrite $subaddr_dwrite $command_write_d0".
		       	"0 00 00 01 $a[3]$a[2] $a[1]$a[0] 00 0$d[4] $d[3]$d[2]p$d[1]$d[0]";

	} elsif ($bank eq 'd1') {

		$i2c = 	"s$deviceWrite $subaddr_dwrite $command_write_d1".
		       	"0 00 00 01 $a[3]$a[2] $a[1]$a[0] 00 0$d[4] $d[3]$d[2]p$d[1]$d[0]";

	} elsif ($bank eq 'cwrite') {

		$i2c = "s$deviceWrite $subaddr_cwrite $a[3]$a[2] $a[1]$a[0] $d[3]$d[2]p$d[1]$d[0]";

	} else {
		die "$bank";
	}

	# pack hex values and add write commands
	$i2c =~ s/s([\dA-Fa-f][\dA-Fa-f]) ?/'s'.pack ("C", hex ($1))/eg;
	$i2c =~ s/p([\dA-Fa-f][\dA-Fa-f]) ?/'p'.pack ("C", hex ($1))/eg;
	$i2c =~ s/ ?([\dA-Fa-f][\dA-Fa-f]) ?/'w'.pack ("C", hex ($1))/eg;

	return $i2c;
}

#
# Currently unused. Hasn't been tested in a *long* time.
#
sub masRead {
	my $key = shift;

	init() unless $isInitialized;

	# address array
	my @a = ();

	# This *must* be undef!
	my $i2c = undef;

	die "Unknown MAS35x9 setting: $key\n" unless ($masRegisters{"$key.address"});

	my $bank    = $masRegisters{"$key.bank"};
	my $address = $masRegisters{"$key.address"};

	while (length($address)>0) {
		push @a, chop($address); 
	}

	if ($bank eq 'r') {

		# reads two bytes;
		$i2c = "s $deviceWrite 68 d$a[1] $a[0]0 p s $deviceRead 69 s 3b ra ra ra rn p";

	} elsif ($bank eq 'd0') {

		# 8 bytes, 5 sig nibbles
		$i2c = "s $deviceWrite 68 e0 00 00 01 $a[3]$a[2] $a[1]$a[0] p s $deviceRead 69 s 3b ra ra ra rn p";

	} elsif ($bank eq 'd1') {

		$i2c = "s $deviceWrite 68 f0 00 00 01 $a[3]$a[2] $a[1]$a[0] p s $deviceRead 69 s 3b ra ra ra rn p";

	} elsif ($bank eq 'run') {

		die "Invalid MAS35x9 operation: read run offset??";
	}

	# pack hex values and add write, ack commands
	$i2c =~ s/ ?([\dA-Fa-f][\dA-Fa-f]) ?/'w'.pack ("C", hex ($1))/eg;
	return $i2c;
}

sub uncompressed_firmware_init_string {

	my $i2c =

's3e 68 00p00' .  # freeze

's3e 68 b3 b0 03p18' . # stop all internal transfers
's3e 68 b4 30 03p00' .
's3e 68 b4 b0 00p00' .
's3e 68 b5 30 03p18' .
's3e 68 b6 b0 00p00' .
's3e 68 bb b0 03p18' .
's3e 68 bc 30 03p00' .
's3e 68 b0 60 00p00' .

's3e 68 e0 00 04 63 08 00'.	# download 1123 words at D0:0800

'
00 0a ff 40
00 07 6f 00
00 02 10 09
00 07 2c 00
00 06 bc 45
00 06 bc 46
00 06 bc 66
00 06 a8 6b
00 06 ac 01
00 07 7c 07
00 07 3f ff
00 07 74 00
00 07 36 80
00 07 6c 00
00 07 2f 45
00 0a db 40
00 07 4c 00
00 07 0f 24
00 06 b8 15
00 07 54 00
00 07 14 00
00 06 b0 1f
00 07 74 12
00 07 34 00
00 0b 40 70
00 07 46 00
00 07 04 00
00 06 a8 1e
00 07 80 0d
00 07 88 0d
00 07 90 0d
00 06 90 4f
00 07 74 20
00 07 36 00
00 07 b0 0d
00 07 4d 99
00 07 0e 66
00 07 7c 00
00 07 3c 03
00 07 04 00
00 07 46 00
00 07 80 3d
00 07 98 0d
00 07 b0 0d
00 07 88 0d
00 07 b8 0d
00 07 80 0d
00 07 98 0d
00 07 98 0d
00 07 80 05
00 07 1e 10
00 07 5c 01
00 0a c9 40
00 07 14 00
00 07 54 00
00 07 1c 00
00 07 5c 00
00 06 98 1e
00 07 24 00
00 07 64 00
00 07 88 0d
00 07 98 0d
00 07 a0 0d
00 07 88 0d
00 07 88 0d
00 07 1f ff
00 07 5c 07
00 07 16 90
00 07 54 00
00 07 5c 00
00 07 1f 46
00 06 98 15
00 06 90 1f
00 07 5c 00
00 07 1f 00
00 06 98 1e
00 04 15 08
00 0a db c2
00 07 64 00
00 07 24 80
00 07 6c 00
00 07 2c 40
00 0a cc c2
00 07 64 00
00 07 24 04
00 0a f5 c2
00 0a ec c2
00 09 89 7b
00 09 b6 45
00 09 ad 43
00 08 09 c6
00 08 2d c1
00 07 4c 00
00 07 0c 40
00 04 11 00
00 06 ac 78
00 0a c9 c2
00 07 26 0f
00 07 64 01
00 09 9b 78
00 09 89 7c
00 08 0b c1
00 06 90 4f
00 06 a0 1e
00 00 00 00
00 07 88 01
00 07 17 18
00 07 54 00
00 07 1f 00
00 07 5c 00
00 07 27 00
00 07 64 00
00 07 2f 18
00 07 6c 00
00 06 90 3b
00 06 90 5b
00 06 9c 43
00 06 9c 3b
00 06 a4 53
00 06 a8 53
00 07 16 90
00 07 54 01
00 07 1d 00
00 07 5c 00
00 07 0c 00
00 06 90 25
00 06 90 2f
00 06 9c 05
00 06 90 2d
00 06 90 23
00 06 94 27
00 06 94 25
00 08 83 41
00 07 4c 01
00 06 94 2f
00 06 94 23
00 06 80 17
00 06 84 17
00 06 88 24
00 06 88 2e
00 07 0c 00
00 07 4c 01
00 06 88 2c
00 06 88 22
00 0a db 40
00 06 8c 26
00 06 8c 24
00 06 8c 2e
00 01 41 00
00 06 8c 22
00 07 98 03
00 07 9c 03
00 06 9c 7d
00 07 1e 0f
00 07 5c 01
00 07 1e 00
00 07 5c 01
00 07 2d 99
00 06 98 1e
00 04 01 00
00 02 3f cc
00 06 98 1e
00 07 6c 04
00 09 98 7a
00 02 83 10
00 07 2c af
00 07 6c 04
00 07 a8 02
00 02 12 14
00 00 00 00
00 00 00 00
00 00 00 00
00 00 00 00
00 00 00 00
00 00 00 00
00 07 3f 48
00 07 7c 00
00 07 6c 0c
00 07 2c 00
00 07 3e 00
00 02 14 0d
00 06 b8 1e
00 07 7c 01
00 04 31 00
00 07 3c bb
00 07 7c 04
00 06 b8 1e
00 02 13 fc
00 07 7c 00
00 07 3c 04
00 06 ac 77
00 07 3c c2
00 07 7c 04
00 06 bc 44
00 08 20 40
00 07 34 00
00 07 74 00
00 07 7c 00
00 07 3c 00
00 06 2c 78
00 08 36 c5
00 09 ac 7b
00 06 bc 43
00 02 83 18
00 02 11 97
00 02 10 d2
00 02 81 28
00 02 11 98
00 02 10 d2
00 02 81 28
00 0a c9 40
00 0b 40 40
00 0a d2 40
00 0a db 40
00 06 3c 26
00 09 ac 7b
00 06 30 2e
00 02 83 08
00 06 30 24
00 06 b8 7b
00 06 88 7a
00 06 80 79
00 06 90 78
00 06 98 77
00 06 b0 76
00 06 a0 75
00 02 3f cc
00 07 2c e6
00 07 6c 04
00 02 81 18
00 02 13 c9
00 07 6c 04
00 07 2c ea
00 02 81 18
00 06 38 7b
00 06 08 7a
00 06 00 79
00 06 10 78
00 06 18 77
00 06 30 76
00 06 20 75
00 08 00 c2
00 08 09 c3
00 08 16 40
00 08 1f 40
00 06 30 2e
00 09 ac 7b
00 02 83 08
00 06 30 24
00 06 3c 26
00 08 96 c2
00 08 9f c3
00 08 12 50
00 08 1b 50
00 0a d2 4f
00 0a db 4f
00 0a 29 70
00 06 b8 7b
00 02 9e 08
00 02 10 e2
00 06 88 7a
00 06 80 79
00 06 90 78
00 06 98 77
00 06 b0 76
00 06 a0 75
00 08 08 c0
00 08 08 c1
00 06 84 7e
00 07 15 21
00 07 54 04
00 07 2c 34
00 07 6c 2e
00 07 88 01
00 0a c0 40
00 06 90 0f
00 01 02 30
00 0a d2 40
00 08 00 c1
00 08 12 41
00 08 98 c5
00 00 c6 87
00 02 10 41
00 07 17 ff
00 07 57 ff
00 00 00 00
00 00 00 00
00 00 00 00
00 07 90 01
00 08 b3 c1
00 0b 76 c6
00 08 9b c6
00 02 87 10
00 08 80 c1
00 08 92 41
00 02 13 30
00 07 7c 04
00 07 3d 2b
00 02 81 18
00 07 37 48
00 07 74 00
00 07 36 01
00 07 74 01
00 0a 28 7e
00 06 b0 1e
00 02 14 0d
00 04 31 00
00 06 b0 1e
00 07 3d 38
00 07 7c 04
00 07 a8 01
00 00 00 00
00 02 13 e0
00 07 7c 04
00 07 3d 3c
00 02 81 18
00 02 13 3e
00 07 7c 04
00 07 3d 40
00 02 81 18
00 02 13 fc
00 07 3d 44
00 07 7c 04
00 02 81 18
00 07 4c 01
00 07 0e 0f
00 00 00 00
00 00 00 00
00 00 00 00
00 06 88 1e
00 04 21 00
00 00 00 00
00 09 bc 7a
00 02 82 10
00 02 11 6e
00 02 81 28
00 07 7c 04
00 07 3c 00
00 07 74 00
00 07 34 64
00 06 04 7e
00 06 10 7f
00 0b 49 7e
00 08 a2 46
00 02 9f 88
00 0b 49 7d
00 08 92 44
00 02 9e 88
00 08 a7 c0
00 06 14 7e
00 0b a4 c4
00 0b 49 7f
00 08 a4 c6
00 07 7c 03
00 07 3e b3
00 02 89 30
00 08 a7 c0
00 0b a0 c4
00 0b 49 40
00 08 a4 c6
00 02 89 08
00 0b 49 7d
00 00 00 00
00 00 00 00
00 00 00 00
00 06 8c 7f
00 07 4c 01
00 07 0e 0f
00 07 74 01
00 07 34 80
00 07 5c 01
00 07 1e 06
00 06 88 1e
00 04 21 00
00 06 28 2c
00 09 bc 7a
00 02 83 20
00 06 28 2e
00 09 bc 7b
00 02 83 08
00 06 28 24
00 06 98 1e
00 0a e4 40
00 07 7c 01
00 07 3c 00
00 09 2e c5
00 07 74 00
00 07 35 00
00 02 88 08
00 08 2d c6
00 07 74 01
00 07 34 00
00 07 7c 01
00 08 2d c6
00 07 3c 80
00 07 b8 01
00 07 a0 01
00 0a ed 7e
00 07 7c 00
00 07 3c 80
00 02 13 55
00 07 b8 01
00 07 7c 04
00 07 3c a8
00 07 b8 01
00 07 b8 01
00 07 a8 01
00 06 b0 3b
00 06 b0 5b
00 07 7c 00
00 07 3c 14
00 07 5c 00
00 07 1c 00
00 07 37 48
00 07 74 00
00 07 36 00
00 07 74 01
00 06 bc 44
00 06 b0 1e
00 04 31 00
00 06 b0 1e
00 06 9c 43
00 07 1c 00
00 07 5c 0c
00 02 14 0d
00 07 2c 00
00 07 6c 06
00 07 3d af
00 07 7c 04
00 07 98 01
00 07 a8 01
00 02 11 d6
00 0b 49 7f
00 07 5c 01
00 07 1f 00
00 07 64 04
00 07 25 b6
00 0b 52 7e
00 07 1c 1a
00 07 5c 0b
00 02 14 0d
00 07 2e 0d
00 07 6c 05
00 07 3d bf
00 07 7c 04
00 07 98 01
00 07 a8 01
00 02 11 d6
00 0b 49 40
00 07 5c 01
00 07 1f 00
00 07 64 04
00 07 25 c6
00 0b 52 7e
00 07 1c 00
00 07 5c 08
00 02 14 0d
00 07 2c 00
00 07 6c 0c
00 07 3d cf
00 07 7c 04
00 07 98 01
00 07 a8 01
00 02 11 d6
00 0b 49 7e
00 07 5c 02
00 07 1e 00
00 07 64 04
00 07 25 a6
00 0b 52 7a
00 00 00 00
00 00 00 00
00 06 98 74
00 06 a0 0b
00 06 8c 7f
00 06 90 7f
00 02 13 e0
00 07 7c 04
00 07 3d e0
00 02 81 18
00 02 13 3e
00 07 7c 04
00 07 3d e4
00 02 81 18
00 02 13 fc
00 07 3d e8
00 07 7c 04
00 02 81 18
00 07 7c 01
00 07 3c 00
00 07 27 18
00 07 64 00
00 06 08 74
00 07 64 00
00 07 24 20
00 06 a0 53
00 06 b8 2c
00 07 7c 01
00 07 3c 00
00 06 88 54
00 07 54 01
00 07 14 fb
00 06 a0 53
00 06 bc 26
00 02 13 c9
00 07 6c 04
00 07 2d fc
00 02 81 18
00 06 2c 26
00 08 aa c5
00 02 87 20
00 02 3f cc
00 07 6c 04
00 07 2d f8
00 02 81 18
00 07 37 48
00 07 74 00
00 07 0e 00
00 07 4c 01
00 06 38 52
00 06 b0 1e
00 04 31 00
00 06 88 1e
00 09 bf 4f
00 00 c2 83
00 02 13 30
00 06 10 7f
00 07 7c 04
00 07 3d 6e
00 00 00 00
00 00 00 00
00 00 00 00
00 02 3f cc
00 07 2e 18
00 07 6c 04
00 02 81 18
00 02 13 c9
00 07 6c 04
00 07 2e 1c
00 02 81 18
00 07 7c 01
00 07 3e 0f
00 06 28 52
00 00 00 00
00 0b 7f 46
00 06 b8 1e
00 09 b9 87
00 02 82 38
00 06 10 56
00 09 ad 4f
00 02 82 10
00 0a d2 42
00 02 9f 10
00 02 13 d3
00 02 81 28
00 07 3c 02
00 07 7c 00
00 00 00 00
00 00 00 00
00 00 00 00
00 06 bc 05
00 00 00 00
00 01 41 00
00 00 00 00
00 00 00 00
00 00 00 00
00 02 12 3d
00 07 3e 14
00 07 7c 04
00 00 00 00
00 00 00 00
00 00 00 00
00 00 00 00
00 07 2e 90
00 07 6c 00
00 07 37 ff
00 06 b8 0c
00 07 74 07
00 07 6c 01
00 07 2e 0f
00 06 a8 1f
00 06 b0 15
00 07 2e 08
00 07 6c 01
00 07 74 01
00 07 36 90
00 08 2d 43
00 06 a8 1e
00 04 39 00
00 06 b4 23
00 06 b0 23
00 06 a8 1e
00 06 bc 22
00 04 31 00
00 07 2e 06
00 07 6c 01
00 06 24 26
00 06 b0 22
00 0b 76 41
00 06 a8 1e
00 04 3d 00
00 07 a0 01
00 09 bf c6
00 09 a4 c6
00 0a ff 7f
00 0a e4 7f
00 09 3f c4
00 07 24 ff
00 07 64 00
00 00 00 00
00 09 a4 c6
00 0a ff c4
00 04 25 00
00 08 27 c4
00 08 25 4a
00 07 2e 6e
00 07 6c 04
00 07 a0 01
00 02 12 cf
00 02 81 28
00 06 a0 1e
00 07 b8 05
00 07 2e 07
00 07 6c 01
00 07 3c 20
00 07 7c 00
00 08 2d 44
00 06 a8 1e
00 04 25 00
00 09 3f c4
00 02 87 08
00 08 27 40
00 08 bf 40
00 06 3c 22
00 00 c7 04
00 06 20 22
00 07 a0 01
00 07 b8 01
00 08 2d 44
00 06 a8 1e
00 07 a0 01
00 06 30 2c
00 00 00 00
00 06 a8 1e
00 04 39 00
00 00 00 00
00 09 af 7a
00 02 83 20
00 09 bf 7b
00 06 30 2e
00 02 83 08
00 06 30 24
00 07 2e 09
00 07 6c 01
00 09 3c c6
00 07 64 00
00 07 24 ff
00 06 a8 1e
00 04 31 00
00 0a fc c7
00 06 a8 1e
00 08 b7 c6
00 07 3c 80
00 07 7c 00
00 07 b8 01
00 0a f4 c6
00 09 37 c6
00 02 86 10
00 08 36 c7
00 02 81 08
00 08 b6 c7
00 04 2d 00
00 08 36 c5
00 07 2e 0c
00 07 6c 01
00 08 be c7
00 07 b0 01
00 0a 37 76
00 00 00 00
00 0a f6 7f
00 02 86 28
00 08 36 41
00 02 9f 10
00 07 3c 00
00 07 7f ff
00 02 81 18
00 02 9f 10
00 07 3f ff
00 07 7c 00
00 00 00 00
00 0a 37 4a
00 08 2d 41
00 06 a8 1e
00 04 21 00
00 00 00 00
00 06 a8 1e
00 04 31 00
00 0c 24 26
00 08 36 c7
00 04 39 00
00 06 a8 1e
00 00 00 00
00 07 b0 01
00 06 a8 1e
00 04 31 00
00 08 2d 75
00 0c 36 27
00 00 00 00
00 00 00 00
00 06 a8 1e
00 04 39 00
00 08 36 c4
00 00 c1 04
00 08 37 c6
00 00 00 00
00 00 00 00
00 00 00 00
00 06 b4 0f
00 06 b4 77
00 08 3f 40
00 02 9e 10
00 02 13 28
00 02 81 28
00 06 a8 0d
00 02 13 9c
00 07 74 04
00 07 36 d8
00 02 81 18
00 07 64 01
00 07 26 0f
00 0b 76 6c
00 00 00 00
00 00 00 00
00 06 a0 1e
00 04 21 00
00 08 2d 4b
00 00 00 00
00 06 30 5a
00 09 9c 7b
00 02 83 08
00 06 30 3a
00 00 00 00
00 0a f6 5f
00 02 9f 10
00 08 9e 54
00 02 87 08
00 0b 76 6c
00 09 9c 7a
00 02 82 08
00 0b 76 6c
00 06 a8 20
00 09 16 54
00 04 32 00
00 0b 5b 44
00 0a f6 41
00 02 9f 08
00 0a db 40
00 0b 40 7f
00 07 5c 01
00 07 1c 80
00 07 4c 00
00 07 0f 40
00 06 80 16
00 06 98 21
00 0b 64 44
00 06 88 20
00 06 08 7d
00 06 28 7c
00 09 89 48
00 09 ad 50
00 09 89 74
00 08 2d c1
00 09 8f 8a
00 09 b7 8a
00 06 18 7e
00 00 00 00
00 07 c8 0e
00 07 f0 0e
00 0c 4a 0d
00 0c 76 0d
00 0e 4a 0d
00 0e 76 0d
00 00 00 00
00 00 00 00
00 00 00 00
00 00 00 00
00 00 00 00
00 07 88 06
00 0a ce 8c
00 07 b0 06
00 0a f6 8c
00 09 ad 7f
00 02 82 10
00 08 09 42
00 08 36 42
00 08 9b 41
00 02 9e 28
00 02 13 b4
00 07 5c 04
00 07 1f 22
00 06 98 7e
00 02 81 10
00 08 bf 41
00 02 89 10
00 02 13 04
00 02 81 28
00 07 8c 0f
00 07 b4 0f
00 09 8d 44
00 00 c1 05
00 09 ad 70
00 00 00 00
00 06 c8 7d
00 00 00 00
00 06 a8 7c
00 00 00 00
00 07 7c 00
00 07 3f 46
00 07 7c 00
00 06 b8 0e
00 07 3c 10
00 06 b8 1e
00 0a f9 87
00 00 c1 06
00 02 9f 08
00 09 92 41
00 06 94 3c
00 06 90 7f
00 06 95 54
00 06 94 44
00 07 7c 00
00 07 3f 49
00 07 55 00
00 06 b8 0e
00 07 14 00
00 07 7e 00
00 06 b8 1e
00 07 3c 00
00 04 19 00
00 0a ff c3
00 08 36 c7
00 07 7c 80
00 07 3c 00
00 00 00 00
00 0a ff c3
00 08 36 c7
00 00 c1 06
00 09 9b 54
00 02 82 10
00 07 54 00
00 07 14 00
00 00 00 00
00 08 32 c6
00 00 00 00
00 00 00 00
00 00 00 00
00 06 b8 0e
00 07 74 01
00 07 36 90
00 07 7c 00
00 07 3f c0
00 07 74 01
00 07 34 00
00 06 b4 23
00 06 b0 23
00 0a ed 40
00 06 b8 22
00 06 b4 22
00 01 01 20
00 00 00 00
00 07 a8 0f
00 07 a8 0f
00 06 b8 22
00 02 13 b4
00 07 5c 04
00 07 1f 6d
00 02 81 18
00 09 9d 44
00 09 9d 70
00 0b 7f 60
00 00 00 00
00 06 d8 7d
00 06 98 7c
00 02 12 cf
00 07 6c 04
00 07 2f 77
00 02 81 20
00 0a ed 40
00 07 37 00
00 07 74 00
00 07 1f 00
00 06 a8 7d
00 06 a8 7c
00 07 5c 00
00 06 b4 43
00 06 b4 3b
00 07 74 00
00 07 37 46
00 06 9c 53
00 07 74 12
00 07 34 30
00 06 b0 1e
00 06 24 7f
00 04 3d 00
00 08 a4 42
00 02 88 10
00 07 5c 00
00 07 1c 0c
00 0a f6 c7
00 07 6c 00
00 07 2c 80
00 0a ff 40
00 07 6c 01
00 07 2c 00
00 06 a8 7e
00 06 9c 53
00 07 6c 00
00 00 c1 06
00 06 ac 26
00 07 2d e2
00 06 b4 3b
00 06 b4 43
00 06 b8 31
00 06 a8 34
00 07 64 00
00 07 26 80
00 07 44 00
00 06 b0 09
00 07 07 54
00 0b 64 7d
00 06 a0 21
00 07 74 00
00 07 36 80
00 07 44 03
00 07 07 fc
00 06 80 20
00 06 a4 15
00 06 b4 1f
00 06 84 1e
00 04 36 08
00 04 06 08
00 00 c1 01
00 04 26 08
00 04 32 00
00 07 b4 0d
00 07 84 0d
00 07 a4 0d
00 07 b4 0d
00 07 5c 00
00 07 1f 51
00 06 04 7f
00 06 98 08
00 07 6c 00
00 07 2c c0
00 06 98 1e
00 04 19 00
00 0a ed 40
00 06 a8 7e
00 09 9b 7c
00 08 80 40
00 02 9f 20
00 07 2e 00
00 08 80 41
00 02 9f 08
00 07 2f 00
00 00 c1 00
00 09 ad 4c
00 08 2b c5
00 02 81 18
00 07 6c 00
00 07 2f 46
00 00 00 00
00 06 a8 0f
00 0b 7f 7f
00 06 a8 20
00 0a fe 87
00 00 df 87
00 02 13 d3
00 02 81 28
00 07 7c 00
00 07 3e 80
00 07 6c 00
00 07 2f 46
00 00 00 00
00 06 b8 21
00 00 00 00
00 06 a8 20
00 02 10 a7
00 02 10 41
00 0b 6d 42
00 0a ee 85
00 02 81 18
00 07 14 00
00 07 54 60
00 07 0e 0c
00 06 ac 77
00 07 a8 01
00 06 b8 0e
00 0a d6 c2
00 0a 3d 6e
00 09 92 72
00 07 4c 01
00 08 3f c2
00 07 17 d0
00 07 54 01
00 07 1f e8
00 07 5c 00
00 08 3f 4a
00 0a c0 40
00 0c 12 27
00 0d 10 00
00 0c 1b 27
00 0d 18 00
00 00 c1 06
00 06 88 1e
00 00 00 00
00 00 00 00
00 07 90 01
00 07 80 01
00 07 98 01
00 0b 64 68
00 0a be c4
00 09 a4 46
00 0b 7f c7
00 06 b8 0f
00 00 00 00
00 06 a4 05
00 06 bc 0d
00 01 41 00
00 06 ac 0f
00 00 00 00
00 00 00 00
00 00 c1 87
00 06 b4 0d
00 00 00 00
00 00 00 00
00 00 00 00
00 0a e4 40
00 09 bd 4a
00 09 b6 7c
00 06 b8 0f
00 07 6f ff
00 07 2f ff
00 01 03 a6
00 0a 2d 7c
00 09 a4 41
00 09 bf 41
00 08 e4 c5
00 09 1e c4
00 02 87 10
00 0a e3 c3
00 08 bf c5
00 07 75 d9
00 07 36 23
00 09 a7 40
00 07 6d 14
00 0c 36 27
00 07 2f 2c
00 0b 7d 75
00 08 ad c4
00 00 c7 87
00 0a 6e c6
00 09 a4 44
00 08 ad 41
00 09 a4 c5
00 09 ad 43
00 09 b4 6d
00 09 a4 49
00 0a f6 7f
00 0a 24 77
00 02 86 30
00 08 36 41
00 08 be 48
00 02 87 18
00 09 a4 49
00 08 b6 41
00 09 a4 77
00 0b 7f 74
00 08 b6 44
00 02 9e 20
00 0b 5b 41
00 08 36 41
00 09 9b 53
00 08 24 c3
00 08 b6 41
00 00 c7 87
00 00 c1 07
00 09 b6 4f
00 08 35 c6
00 0b 3f c7
00 0a ec c4
00 00 00 00
00 00 00 00
00 07 7d aa
00 09 b6 7d
00 07 3e ab
00 06 b8 0f
00 0a f6 43
00 09 ad c6
00 09 a4 50
00 0c 35 27
00 08 3c c4
00 08 3c c7
00 07 6f ff
00 07 2f ff
00 0a e4 40
00 01 03 a4
00 0a 2d 7c
00 09 a4 41
00 09 bf 41
00 08 e4 c5
00 09 1e c4
00 02 87 10
00 0a e3 c3
00 08 bf c5
00 0b 76 7f
00 00 c1 07
00 0a 2e 7f
00 09 b6 4c
00 08 3f c5
00 00 00 00
00 0a ff 7f
00 08 bepc7'.

's3e 68 b6 bc 00p00'.	# switch memory range from data to program

's3e 68 10p0a'.		# run at D0:100a

#'s3e 6c 00 01 02p87'.	# codec config, passthru 22.05KHz (for testing)
's3e 6c 00 01 03p87'.	# codec config, passthru 44.1KHz

's3e 68 e0 00 00 01 03 4b 00 00 00p0c'.  # appselect mp3???
's3e 68 e0 00 00 01 03 47 00 00 00p04'.  # enable s/pdif&sdo out
's3e 68 e0 00 00 01 03 48 00 00 4ep5e'.  # tweak PLL to get 44.1 instead of 48
#'s3e 68 e0 00 00 01 03 4e 00 00 10p60'.  # 1 bit delay of data relative to word strobe
's3e 68 e0 00 00 01 03 46 00 00 01p11'.  # IO control init (SDIB, 16bit)
#'s3e 68 e0 00 00 01 03 46 00 00 01p15'.  # IO control init (SDIB, 16bit, latch falling)
 
's3e 6c 00 00 00p01'.	# enable d/a, disable all a/d
's3e 6c 00 06 00p00'.   # no input from adc
's3e 6c 00 07 40p00'.   # 100% input from DSP(??)
's3e 6c 00 10 73p00'.   # main volume 0db


'';

	$i2c =~ s/\n/ /g;
	$i2c =~ s/s([\dA-Fa-f][\dA-Fa-f]) ?/'s'.pack ("C", hex ($1))/eg;
	$i2c =~ s/p([\dA-Fa-f][\dA-Fa-f]) ?/'p'.pack ("C", hex ($1))/eg;
	$i2c =~ s/ ?([\dA-Fa-f][\dA-Fa-f]) ?/'w'.pack ("C", hex ($1))/eg;

#	open TEMP, ">temp";
#	print TEMP unpack("H*", $i2c), "\n";
#	close TEMP;

	return $i2c;
}

1;
__END__
