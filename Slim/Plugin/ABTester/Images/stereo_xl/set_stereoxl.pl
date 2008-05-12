use strict;
use set_stereoxl;

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

set_stereoxl::main($playername,$depth_db);
