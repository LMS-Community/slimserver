package YAML::Dumper::Syck;
use strict;

sub new { $_[0] }
sub dump { shift; YAML::Syck::Dump($_[0]) }

1;
