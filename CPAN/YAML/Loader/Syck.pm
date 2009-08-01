package YAML::Loader::Syck;
use strict;

sub new { $_[0] }
sub load { shift; YAML::Syck::Load($_[0]) }

1;
