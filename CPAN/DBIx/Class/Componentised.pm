package # hide from PAUSE
    DBIx::Class::Componentised;

use strict;
use warnings;

use Class::C3;
use Class::Inspector;
use Carp::Clan qw/DBIx::Class/;

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
          warn "Possible incorrect order of components in ".
               "${target}::load_components($first_comp) call: Core loaded ".
               "before $first_comp. See the documentation for ".
               "DBIx::Class::$first_comp for more information";
        }
      }
      unshift( @{"${target}::ISA"}, $to )
        unless ($target eq $to || $target->isa($to));
    }
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
    $class->ensure_class_loaded($comp);
  }
  $class->inject_base($class => @comp);
}

# Given a class name, tests to see if it is already loaded or otherwise
# defined. If it is not yet loaded, the package is require'd, and an exception
# is thrown if the class is still not loaded.
#
# TODO: handle ->has_many('rel', 'Class'...) instead of
#              ->has_many('rel', 'Some::Schema::Class'...)
#
# BUG: For some reason, packages with syntax errors are added to %INC on
#      require
sub ensure_class_loaded {
  my ($class, $f_class) = @_;
  return if Class::Inspector->loaded($f_class);
  eval "require $f_class"; # require needs a bareword or filename
  if ($@) {
    if ($class->can('throw_exception')) {
      $class->throw_exception($@);
    } else {
      croak $@;
    }
  }
}

# Returns true if the specified class is installed or already loaded, false
# otherwise
sub ensure_class_found {
  my ($class, $f_class) = @_;
  return Class::Inspector->loaded($f_class) ||
         Class::Inspector->installed($f_class);
}

# Returns a true value if the specified class is installed and loaded
# successfully, throws an exception if the class is found but not loaded
# successfully, and false if the class is not installed
sub load_optional_class {
  my ($class, $f_class) = @_;
  if ($class->ensure_class_found($f_class)) {
    $class->ensure_class_loaded($f_class);
    return 1;
  } else {
    return 0;
  }
}

1;
