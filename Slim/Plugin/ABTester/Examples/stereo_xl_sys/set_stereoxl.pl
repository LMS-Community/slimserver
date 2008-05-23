#!/usr/bin/perl -w

use strict;
use IO::Socket;
use FileHandle;
use Data::Dumper;
# Send woofer/sub crossover data via the Squeezecenter CLI to Boom DSP.
sub usage
{
    print ("usage: perl set_stereoxl.pl <playername> <depth_in_db>\n");
    print ("       where playername is your boom playername, and depth is a number between 10 and -100 in dB.\n");
    print ("\n");
    print ("Try this\n");
    print ("   perl set_stereoxl.pl boom 0\n");
    print ("Then try\n");
    print ("   perl set_stereoxl.pl boom -6\n");
    print ("Then try\n");
    print ("   perl set_stereoxl.pl boom off\n");
    exit(-1);
}

if (@ARGV != 2) {usage()};
my $playername = $ARGV[0];
my $depth_db  = $ARGV[1];

sub asc2i2c
{
    my ($asc_data) = @_;
    my $len = length($asc_data);
    my $result = '';
    for (my $i = 0; $i < $len; $i+=2) {
	$result = $result . "%" . substr($asc_data, $i, 2);
    }
    return $result;
}

# Convert depth in db to linear
if ($depth_db ne 'off' && $depth_db > 10) {
    print "You really, really don't want stereoxl depth to be this big.  Try something like 0 or -6";
    exit(0);
}

my $depth;
if ($depth_db eq 'off') {
	$depth = 0;
} else {
	$depth = 10.0**($depth_db/20.0);
}
my $depth_int  = (int(($depth  * 0x00800000)+0.5)) & 0xFFFFFFFF ;
my $depth_int_ = (-int(($depth * 0x00800000)+0.5)) & 0xFFFFFFFF ;

my $stereoxl_i2c_address = 41;
my $command = sprintf("%02x%08x%08x%08x%08x", $stereoxl_i2c_address, 
		   $depth_int, $depth_int_, 0, 0);
my $sock = new IO::Socket::INET(
			  PeerAddr => 'localhost',
			  PeerPort => '9090',
			  Proto    => 'tcp',
			  );

die "Couldn't open socket $!\n" unless $sock;
print "Setting stereoXL depth to $depth_db dB ($depth)\n";
print $sock "$playername boomdac " . asc2i2c($command) . "\n";
print "$playername boomdac " . asc2i2c($command) . "\n";
close($sock);
