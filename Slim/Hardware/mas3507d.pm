package Slim::Hardware::mas3507d;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Hardware::mas3507d

=head1 DESCRIPTION

L<Slim::Hardware::mas3507d>

=cut

use strict;

my %masRegisters  = ();
my $isInitialized = 0;

sub init {

	$masRegisters{"dccf.bank"}						= "r";
	$masRegisters{"dccf.address"}					= "8e";
	$masRegisters{"mute.bank"}						= "r";
	$masRegisters{"mute.address"}					= "aa";
	$masRegisters{"treble.bank"}					= "r";
	$masRegisters{"treble.address"}					= "6f";
	$masRegisters{"bass.bank"}						= "r";
	$masRegisters{"bass.address"}					= "6b";
	$masRegisters{"prefactor.bank"}					= "r";
	$masRegisters{"prefactor.address"}				= "e7";
	$masRegisters{"piodata.bank"}					= "r";
	$masRegisters{"piodata.address"}				= "ed";
	$masRegisters{"config.bank"}					= "r";
	$masRegisters{"config.address"}					= "e6";
	$masRegisters{"mpegstatus1.bank"}				= "d0";
	$masRegisters{"mpegstatus1.address"}			= "0301";
	$masRegisters{"mpegstatus2.bank"}				= "d0";
	$masRegisters{"mpegstatus2.address"}			= "0302";
	$masRegisters{"crcerrorcount.bank"}				= "d0";
	$masRegisters{"crcerrorcount.address"}			= "0303";
	$masRegisters{"numberofancillarybits.bank"}		= "d0";
	$masRegisters{"numberofancillarybits.address"}	= "0304";
	$masRegisters{"ancillary.bank"}					= "d0";
	$masRegisters{"ancillary.address"}				= "0305";
	$masRegisters{"ancillarydata.bank"}				= "d0";
	$masRegisters{"ancillarydata.address"}			= "0305";
	$masRegisters{"plloffset48.bank"}				= "d0";
	$masRegisters{"plloffset48.address"}			= "032d";
	$masRegisters{"plloffset44.bank"}				= "d0";
	$masRegisters{"plloffset44.address"}			= "032e";
	$masRegisters{"outputconfig.bank"}				= "d0";
	$masRegisters{"outputconfig.address"}			= "032f";
	$masRegisters{"ll.bank"}						= "d1";
	$masRegisters{"ll.address"}						= "07f8";
	$masRegisters{"lr.bank"}						= "d1";
	$masRegisters{"lr.address"}						= "07f9";
	$masRegisters{"rl.bank"}						= "d1";
	$masRegisters{"rl.address"}						= "07fa";
	$masRegisters{"rr.bank"}						= "d1";
	$masRegisters{"rr.address"}						= "07fb";
	$masRegisters{"version.bank"}					= "d1";
	$masRegisters{"version.address"}				= "0ff6";
	$masRegisters{"designcode.bank"}				= "d1";
	$masRegisters{"designcode.address"}				= "0ff7";
	$masRegisters{"idunno.bank"}					= "d1";
	$masRegisters{"idunno.address"}					= "0ff8";
	$masRegisters{"desc1.bank"}						= "d1";
	$masRegisters{"desc1.address"}					= "0ff9";
	$masRegisters{"desc2.bank"}						= "d1";
	$masRegisters{"desc2.address"}					= "0ffa";
	$masRegisters{"desc3.bank"}						= "d1";
	$masRegisters{"desc3.address"}					= "0ffb";
	$masRegisters{"desc4.bank"}						= "d1";
	$masRegisters{"desc4.address"}					= "0ffc";
	$masRegisters{"desc5.bank"}						= "d1";
	$masRegisters{"desc5.address"}					= "0ffd";
	$masRegisters{"desc6.bank"}						= "d1";
	$masRegisters{"desc6.address"}					= "0ffe";
	$masRegisters{"desc7.bank"}						= "d1";
	$masRegisters{"desc7.address"}					= "0fff";
	$masRegisters{"loadconfig.bank"}				= "run";
	$masRegisters{"loadconfig.address"}				= "0fcd";
	$masRegisters{"setpll.bank"}					= "run";
	$masRegisters{"setpll.address"}					= "0475";
	$isInitialized = 1;

}

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

# The codes come from the MAS3507D datasheet 

my @trebleCodes =(
    'b2c00',    
    'bb400',    
    'c1800',    
    'c6c00',    
    'cbc00',
    'd0400',
    'd5000',
    'd9800',
    'de000',
    'e2800',    
    'e7e00',    
    'ec000',
    'f0c00',
    'f5c00',
    '0fac00',
    '00000',    # midpoint (50% or no adjustment)
    '05400',
    '0ac00',
    '10400',
    '16000',
    '1c000',
    '22000',
    '28400',
    '2ec00',
    '35400',
    '3c000',
    '42c00',
    '49c00',
    '51800',
    '58400',
    '5f800',
);



my @bassCodes =(
    '9e400',    
    'a2800',    
    'a7400',    
    'ac400',    
    'b1800',    
    'b7400',    
    'bd400',    
    'c3c00',    
    'ca400',    
    'd1800',    
    'd8c00',    
    'e0400',    
    'e8000',    
    'efc00',
    'f7c00',
    '00000',  # midpoint (50% or no adjustment)
    '00800',
    '10000',
    '17c00',
    '1f800',
    '27000',
    '2e400',
    '35800',
    '3c000',
    '42800',
    '48800',
    '4e400',
    '53800',
    '58800',
    '5d400',
    '61800',
);


my @prefactorCodes =(
    'e9400',
    'e6800',
    'e3400',
    'dfc00',
    'dc000',
    'd7800',
    'd25c0',
    'cd000',
    'c6c00',
    'bfc00',
    'b8000',
    'af400',
    'a5800',
    '9a400',
    '8e000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000',
    '80000'    
);

sub getToneCode {
	my $toneSetting = shift;
	my $toneType = shift;
	my $toneCodes = ($toneType eq 'bass') ? \@bassCodes : \@trebleCodes;
	my $index = int($toneSetting / Slim::Player::Player::maxTreble() * (scalar(@$toneCodes)-1) + 0.5);
	return $toneCodes->[$index];
}

#--------------------------------------------
# Generate the i2c sequence for writing to the MAS3507D

sub masWrite {
	my ($key, $data) = @_;

	init() unless $isInitialized;

	my (@a,@d) = ((),());

	# This *must* be undef!
	my $i2c = undef;

	die "Unknown MAS3507D setting: $key\n" unless ($masRegisters{"$key.address"});

	my $bank    = $masRegisters{"$key.bank"};
	my $address = $masRegisters{"$key.address"};

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

	# See MAS3507D data sheet for exaplanation of their i2c functions
	if ($bank eq 'r') {

		$i2c = "s 3a 68 9$a[1] $a[0]$d[0] $d[4]$d[3] $d[2]$d[1] p";

	} elsif ($bank eq 'd0') {

		$i2c = "s 3a 68 a0 00 00 01 $a[3]$a[2] $a[1]$a[0] $d[3]$d[2] $d[1]$d[0] 00 0$d[4] p";

	} elsif ($bank eq 'd1') {

		$i2c = "s 3a 68 b0 00 00 01 $a[3]$a[2] $a[1]$a[0] $d[3]$d[2] $d[1]$d[0] 00 0$d[4] p";

	} elsif ($bank eq 'run') {

		$i2c = "s 3a 68 $a[3]$a[2] $a[1]$a[0] p";
	}

	# pack hex values and add write, ack commands
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

	die "Unknown MAS3507D setting: $key\n" unless ($masRegisters{"$key.address"});

	my $bank    = $masRegisters{"$key.bank"};
	my $address = $masRegisters{"$key.address"};

	while (length($address)>0) {
		push @a, chop($address); 
	}

	if ($bank eq 'r') {

		# reads two bytes;
		$i2c = "s 3a 68 d$a[1] $a[0]0 p s 3a 69 s 3b ra ra ra rn p";

	} elsif ($bank eq 'd0') {

		# 8 bytes, 5 sig nibbles
		$i2c = "s 3a 68 e0 00 00 01 $a[3]$a[2] $a[1]$a[0] p s 3a 69 s 3b ra ra ra rn p";

	} elsif ($bank eq 'd1') {

		$i2c = "s 3a 68 f0 00 00 01 $a[3]$a[2] $a[1]$a[0] p s 3a 69 s 3b ra ra ra rn p";

	} elsif ($bank eq 'run') {

		die "Invalid MAS3507D operation: read run offset??";
	}

	# pack hex values and add write, ack commands
	$i2c =~ s/ ?([\dA-Fa-f][\dA-Fa-f]) ?/'w'.pack ("C", hex ($1))/eg;

	return $i2c;
}

1;
__END__
