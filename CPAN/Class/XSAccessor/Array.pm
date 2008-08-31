package Class::XSAccessor::Array;

use 5.006;
use strict;
use warnings;
use Carp qw/croak/;

our $VERSION = '0.05';

require XSLoader;
XSLoader::load('Class::XSAccessor::Array', $VERSION);

sub import {
  my $own_class = shift;
  my ($caller_pkg) = caller();

  my %opts = @_;

  my $replace = $opts{replace} || 0;
  my $chained = $opts{chained} || 0;

  my $read_subs = $opts{getters} || {};
  my $set_subs  = $opts{setters} || {};
  my $acc_subs  = $opts{accessors} || {};
  my $pred_subs = $opts{predicates} || {};

  foreach my $subname (keys %$read_subs) {
    my $arrayIndex = $read_subs->{$subname};
    _generate_accessor($caller_pkg, $subname, $arrayIndex, $replace, $chained, "getter");
  }

  foreach my $subname (keys %$set_subs) {
    my $arrayIndex = $set_subs->{$subname};
    _generate_accessor($caller_pkg, $subname, $arrayIndex, $replace, $chained, "setter");
  }

  foreach my $subname (keys %$acc_subs) {
    my $arrayIndex = $acc_subs->{$subname};
    _generate_accessor($caller_pkg, $subname, $arrayIndex, $replace, $chained, "accessor");
  }

  foreach my $subname (keys %$pred_subs) {
    my $arrayIndex = $pred_subs->{$subname};
    _generate_accessor($caller_pkg, $subname, $arrayIndex, $replace, $chained, "predicate");
  }
}

sub _generate_accessor {
  my ($caller_pkg, $subname, $arrayIndex, $replace, $chained, $type) = @_;

  if (not defined $arrayIndex) {
    croak("Cannot use undef as a array index for generating an XS $type accessor. (Sub: $subname)");
  }

  if ($subname !~ /::/) {
    $subname = "${caller_pkg}::$subname";
  }

  if (not $replace) {
    my $sub_package = $subname;
    $sub_package =~ s/([^:]+)$// or die;
    my $bare_subname = $1;
    
    my $sym;
    {
      no strict 'refs';
      $sym = \%{"$sub_package"};
    }
    no warnings;
    local *s = $sym->{$bare_subname};
    my $coderef = *s{CODE};
    if ($coderef) {
      croak("Cannot replace existing subroutine '$bare_subname' in package '$sub_package' with XS method of type '$type'. If you wish to force a replacement, add the 'replace => 1' parameter to the arguments of 'use ".__PACKAGE__."'.");
    }
  }

  if ($type eq 'getter') {
    newxs_getter($subname, $arrayIndex);
  }
  elsif ($type eq 'setter') {
    newxs_setter($subname, $arrayIndex, $chained);
  }
  elsif ($type eq 'predicate') {
    newxs_predicate($subname, $arrayIndex);
  }
  else {
    newxs_accessor($subname, $arrayIndex, $chained);
  }
}


1;
__END__

=head1 NAME

Class::XSAccessor::Array - Generate fast XS accessors without runtime compilation

=head1 SYNOPSIS
  
  package MyClassUsingArraysAsInternalStorage;
  use Class::XSAccessor::Array
    getters => {
      get_foo => 0, # 0 is the array index to access
      get_bar => 1,
    },
    setters => {
      set_foo => 0,
      set_bar => 1,
    },
    accessors => { # a mutator
      buz => 2,
    },
    predicates => { # test for definedness
      has_buz => 2,
    };
  # The imported methods are implemented in fast XS.
  
  # normal class code here.

=head1 DESCRIPTION

The module implements fast XS accessors both for getting at and
setting an object attribute. Additionally, the module supports
mutators and simple predicates (C<has_foo()> like tests for definedness
of an attributes).
The module works only with objects
that are implemented as B<arrays>. Using it on hash-based objects is
bound to make your life miserable. Refer to L<Class::XSAccessor> for
an implementation that works with hash-based objects.

A simple benchmark showed more than a factor of two performance
advantage over writing accessors in Perl.

While generally more obscure than hash-based objects,
objects using blessed arrays as internal representation
are a bit faster as its somewhat faster to access arrays than hashes.
Accordingly, this module is slightly faster (~10-15%) than
L<Class::XSAccessor>, which works on hash-based objects.

The method names may be fully qualified. In the example of the
synopsis, you could have written C<MyClass::get_foo> instead
of C<get_foo>.

=head1 OPTIONS

In addition to specifying the types and names of accessors, you can add options
which modify behaviour. The options are specified as key/value pairs just as the
accessor declaration. Example:

  use Class::XSAccessor::Array
    getters => {
      get_foo => 0,
    },
    replace => 1;

The list of available options is:

=head2 replace

Set this to a true value to prevent C<Class::XSAccessor::Array> from
complaining about replacing existing subroutines.

=head2 chained

Set this to a true value to change the return value of setters
and mutators (when called with an argument).
If C<chained> is enabled, the setters and accessors/mutators will
return the object. Mutators called without an argument still
return the value of the associated attribute.

As with the other options, C<chained> affects all methods generated
in the same C<use Class::XSAccessor::Array ...> statement.

=head1 CAVEATS

Probably wouldn't work if your objects are I<tied>. But that's a strange thing to do anyway.

Scary code exploiting strange XS features.

If you think writing an accessor in XS should be a laughably simple exercise, then
please contemplate how you could instantiate a new XS accessor for a new hash key
or array index that's only known at run-time. Note that compiling C code at run-time
a la Inline::C is a no go.

=head1 SEE ALSO

L<Class::XSAccessor>

L<AutoXS>

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

