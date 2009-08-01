package Class::C3::Componentised;

=head1 NAME

Class::C3::Componentised

=head1 DESCRIPTION

Load mix-ins or components to your C3-based class.

=head1 SYNOPSIS

  package MyModule;

  use strict;
  use warnings;

  use base 'Class::C3::Componentised';

  sub component_base_class { "MyModule::Component" }

  package main;

  MyModule->load_components( qw/Foo Bar/ ); 
  # Will load MyModule::Component::Foo an MyModule::Component::Bar

=head1 DESCRIPTION

This will inject base classes to your module using the L<Class::C3> method
resolution order.

Please note: these are not plugins that can take precedence over methods 
declared in MyModule. If you want something like that, consider
L<MooseX::Object::Pluggable>.

=head1 METHODS

=cut

use strict;
use warnings;

# see Makefile.PL for discussion on why we load both Class::C3 and MRO::Compat
use Class::C3 ();
use MRO::Compat;
use Class::Inspector;
use Carp;

our $VERSION = 1.0005;

=head2 load_components( @comps )

Loads the given components into the current module. If a module begins with a 
C<+> character, it is taken to be a fully qualified class name, otherwise
C<< $class->component_base_class >> is prepended to it.

Calling this will call C<Class::C3::reinitialize>.

=cut

sub load_components {
  my $class = shift;
  my $base = $class->component_base_class;
  my @comp = map { /^\+(.*)$/ ? $1 : "${base}::$_" } grep { $_ !~ /^#/ } @_;
  $class->_load_components(@comp);
}

=head2 load_own_components( @comps )

Similar to L<load_components>, but assumes every class is C<"$class::$comp">.

=cut

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
  Class::C3::reinitialize();
}

=head2 load_optional_components

As L<load_components>, but will silently ignore any components that cannot be 
found.

=cut

sub load_optional_components {
  my $class = shift;
  my $base = $class->component_base_class;
  my @comp = grep { $class->load_optional_class( $_ ) }
             map { /^\+(.*)$/ ? $1 : "${base}::$_" } 
             grep { $_ !~ /^#/ } @_;

  $class->_load_components( @comp ) if scalar @comp;
}

=head2 ensure_class_loaded

Given a class name, tests to see if it is already loaded or otherwise
defined. If it is not yet loaded, the package is require'd, and an exception
is thrown if the class is still not loaded.

 BUG: For some reason, packages with syntax errors are added to %INC on
      require
=cut

#
# TODO: handle ->has_many('rel', 'Class'...) instead of
#              ->has_many('rel', 'Some::Schema::Class'...)
#
sub ensure_class_loaded {
  my ($class, $f_class) = @_;

  croak "Invalid class name $f_class"
      if ($f_class=~m/(?:\b:\b|\:{3,})/);
  return if Class::Inspector->loaded($f_class);
  my $file = $f_class . '.pm';
  $file =~ s{::}{/}g;
  eval { CORE::require($file) }; # require needs a bareword or filename
  if ($@) {
    if ($class->can('throw_exception')) {
      $class->throw_exception($@);
    } else {
      croak $@;
    }
  }
}

=head2 ensure_class_found

Returns true if the specified class is installed or already loaded, false
otherwise

=cut

sub ensure_class_found {
  my ($class, $f_class) = @_;
  return Class::Inspector->loaded($f_class) ||
         Class::Inspector->installed($f_class);
}


=head2 inject_base

Does the actual magic of adjusting @ISA on the target module.

=cut

sub inject_base {
  my ($class, $target, @to_inject) = @_;
  {
    no strict 'refs';
    foreach my $to (reverse @to_inject) {
      unshift ( @{"${target}::ISA"}, $to )
        unless ($target eq $to || $target->isa($to));
    }
  }

  mro::set_mro($target, 'c3');
}

=head2 load_optional_class

Returns a true value if the specified class is installed and loaded
successfully, throws an exception if the class is found but not loaded
successfully, and false if the class is not installed

=cut

sub load_optional_class {
  my ($class, $f_class) = @_;
  eval { $class->ensure_class_loaded($f_class) };
  my $err = $@;   # so we don't lose it
  if (! $err) {
    return 1;
  }
  else {
    my $fn = (join ('/', split ('::', $f_class) ) ) . '.pm';
    if ($err =~ /Can't locate ${fn} in \@INC/ ) {
      return 0;
    }
    else {
      die $err;
    }
  }
}

=head1 AUTHOR

Matt S. Trout and the DBIx::Class team

Pulled out into seperate module by Ash Berlin C<< <ash@cpan.org> >>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
