package # hide from PAUSE 
    DBIx::Class::Componentised;

use strict;
use warnings;

use Class::C3;

sub inject_base {
  my ($class, $target, @to_inject) = @_;
  {
    no strict 'refs';
    unshift(@{"${target}::ISA"}, grep { $target ne $_ && !$target->isa($_)} @to_inject);
  }

  # Yes, this is hack. But it *does* work. Please don't submit tickets about
  # it on the basis of the comments in Class::C3, the author was on #dbix-class
  # while I was implementing this.

  my $table = { Class::C3::_dump_MRO_table };
  eval "package $target; import Class::C3;" unless exists $table->{$target};
}

sub load_components {
  my $class = shift;
  my $base = $class->component_base_class;
  my @comp = map { /^\+(.*)$/ ? $1 : "${base}::$_" } grep { $_ !~ /^#/ } @_;
  $class->_load_components(@comp);
  Class::C3::reinitialize();
}

sub load_own_components {
  my $class = shift;
  my @comp = map { "${class}::$_" } grep { $_ !~ /^#/ } @_;
  $class->_load_components(@comp);
}

sub _load_components {
  my ($class, @comp) = @_;
  foreach my $comp (@comp) {
    eval "use $comp";
    die $@ if $@;
  }
  $class->inject_base($class => @comp);
}

1;
