#!/usr/bin/perl

open INFILE, pop @ARGV;
while ($line=<INFILE>) {
	$line=~s/([0-9a-fA-f])([0-9a-fA-f])([0-9a-fA-f])([0-9a-fA-f])([0-9a-fA-f])([0-9a-fA-f])([0-9a-fA-f])([0-9a-fA-f])/$7$8$5$6$3$4$1$2/;
	print $line;
}
