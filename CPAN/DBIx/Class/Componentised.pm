package # hide from PAUSE
    DBIx::Class::Componentised;

use strict;
use warnings;

use base 'Class::C3::Componentised';
use Carp::Clan qw/^DBIx::Class/;

sub inject_base {
  my ($class, $target, @to_inject) = @_;
  {
    no strict 'refs';
    foreach my $to (reverse @to_inject) {
      my @comps = qw(DigestColumns ResultSetManager Ordered UTF8Columns);
           # Add components here that need to be loaded before Core
      foreach my $first_comp (@comps) {
        if ($to eq 'DBIx::Class::Core' &&
            $target->isa("DBIx::Class::${first_comp}")) {
          carp "Possible incorrect order of components in ".
               "${target}::load_components($first_comp) call: Core loaded ".
               "before $first_comp. See the documentation for ".
               "DBIx::Class::$first_comp for more information";
        }
      }
      unshift( @{"${target}::ISA"}, $to )
        unless ($target eq $to || $target->isa($to));
    }
  }

  $class->next::method($target, @to_inject);
}

1;
