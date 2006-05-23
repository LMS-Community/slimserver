package # hide from PAUSE
    DBIx::Class::ClassResolver::PassThrough;

use strict;
use warnings;

sub class {
  shift;
  return shift;
}

1;
