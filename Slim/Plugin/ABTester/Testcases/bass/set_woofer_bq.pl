use strict;
use set_woofer_bq;


sub usage
{
    print ("usage: perl set_woofer_bq.pl <playername> <cutoff frequency>\n");
    exit(-1);
}

if (@ARGV != 2) {usage()};
my $playername = $ARGV[0];
my $frequency  = $ARGV[1];

set_woofer_bq::main($playername,$frequency);

