package Class::XSAccessor;

use 5.006;
use strict;
use warnings;
use Carp qw/croak/;

our $VERSION = '1.03';

require XSLoader;
XSLoader::load('Class::XSAccessor', $VERSION);

sub import {
  my $own_class = shift;
  my ($caller_pkg) = caller();

  my %opts = @_;

  $caller_pkg = $opts{class} if defined $opts{class};

  my $replace = $opts{replace} || 0;
  my $chained = $opts{chained} || 0;

  # TODO: Refactor. This code sucks really bad.
  
  my $read_subs      = $opts{getters} || {};
  my $set_subs       = $opts{setters} || {};
  my $acc_subs       = $opts{accessors} || {};
  my $pred_subs      = $opts{predicates} || {};
  my $construct_subs = $opts{constructors} || [defined($opts{constructor}) ? $opts{constructor} : ()];
  my $true_subs      = $opts{true} || [];
  my $false_subs     = $opts{false} || [];

  foreach my $subname (keys %$read_subs) {
    my $hashkey = $read_subs->{$subname};
    _generate_method($caller_pkg, $subname, $hashkey, $replace, $chained, "getter");
  }

  foreach my $subname (keys %$set_subs) {
    my $hashkey = $set_subs->{$subname};
    _generate_method($caller_pkg, $subname, $hashkey, $replace, $chained, "setter");
  }

  foreach my $subname (keys %$acc_subs) {
    my $hashkey = $acc_subs->{$subname};
    _generate_method($caller_pkg, $subname, $hashkey, $replace, $chained, "accessor");
  }

  foreach my $subname (keys %$pred_subs) {
    my $hashkey = $pred_subs->{$subname};
    _generate_method($caller_pkg, $subname, $hashkey, $replace, $chained, "predicate");
  }
  
  foreach my $subname (@$construct_subs) {
    _generate_method($caller_pkg, $subname, "", $replace, $chained, "constructor");
  }

  foreach my $subname (@$true_subs) {
    _generate_method($caller_pkg, $subname, "", $replace, $chained, "true");
  }

  foreach my $subname (@$false_subs) {
    _generate_method($caller_pkg, $subname, "", $replace, $chained, "false");
  }
}

sub _generate_method {
  my ($caller_pkg, $subname, $hashkey, $replace, $chained, $type) = @_;

  if (not defined $hashkey) {
    croak("Cannot use undef as a hash key for generating an XS $type accessor. (Sub: $subname)");
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
      croak("Cannot replace existing subroutine '$bare_subname' in package '$sub_package' with XS $type accessor. If you wish to force a replacement, add the 'replace => 1' parameter to the arguments of 'use ".__PACKAGE__."'.");
    }
  }

  if ($type eq 'getter') {
    newxs_getter($subname, $hashkey);
  }
  elsif ($type eq 'setter') {
    newxs_setter($subname, $hashkey, $chained);
  }
  elsif ($type eq 'predicate') {
    newxs_predicate($subname, $hashkey);
  }
  elsif ($type eq 'constructor') {
    newxs_constructor($subname);
  }
  elsif ($type eq 'true') {
    newxs_boolean($subname, 1);
  }
  elsif ($type eq 'false') {
    newxs_boolean($subname, 0);
  }
  else {
    newxs_accessor($subname, $hashkey, $chained);
  }
}


1;
__END__

=head1 NAME

Class::XSAccessor - Generate fast XS accessors without runtime compilation

=head1 SYNOPSIS
  
  package MyClass;
  use Class::XSAccessor
    constructor => 'new',
    getters => {
      get_foo => 'foo', # 'foo' is the hash key to access
      get_bar => 'bar',
    },
    setters => {
      set_foo => 'foo',
      set_bar => 'bar',
    },
    accessors => {
      foo => 'foo',
      bar => 'bar',
    },
    predicates => {
      has_foo => 'foo',
      has_bar => 'bar',
    }
    true => [ 'is_token', 'is_whitespace' ],
    false => [ 'significant' ];

  # The imported methods are implemented in fast XS.
  
  # normal class code here.

=head1 DESCRIPTION

Class::XSAccessor implements fast read, write and read/write accessors in XS.
Additionally, it can provide predicates such as C<has_foo()> for testing
whether the attribute C<foo> is defined in the object.
It only works with objects that are implemented as ordinary hashes.
L<Class::XSAccessor::Array> implements the same interface for objects
that use arrays for their internal representation.

Since version 0.10, the module can also generate simple constructors
(implemented in XS) for you. Simply supply the
C<constructor =E<gt> 'constructor_name'> option or the
C<constructors =E<gt> ['new', 'create', 'spawn']> option.
These constructors do the equivalent of the following perl code:

  sub new {
    my $class = shift;
    return bless { @_ }, ref($class)||$class;
  }

That means they can be called on objects and classes but will not
clone objects entirely. Parameters to C<new()> are added to the
object.

The XS accessor methods were between 1.6 and 2.5 times faster than typical
pure-perl accessors in some simple benchmarking.
The lower factor applies to the potentially slightly obscure
C<sub set_foo_pp {$_[0]-E<gt>{foo} = $_[1]}>, so if you usually
write clear code, a factor of two speed-up is a good estimate.

The method names may be fully qualified. In the example of the
synopsis, you could have written C<MyClass::get_foo> instead
of C<get_foo>. This way, you can install methods in classes other
than the current class. See also: The C<class> option below.

By default, the setters return the new value that was set
and the accessors (mutators) do the same. You can change this behaviour
with the C<chained> option, see below. The predicates obviously return a boolean.

Since version 1.01, you can generate extremely simply methods which
simply return true or false (and always do so). If that seems like a
really superfluous thing to you, then think of a large class hierarchy
with interfaces such as PPI. This is implemented as the C<true>
and C<false> options, see synopsis.

=head1 OPTIONS

In addition to specifying the types and names of accessors, you can add options
which modify behaviour. The options are specified as key/value pairs just as the
accessor declaration. Example:

  use Class::XSAccessor
    getters => {
      get_foo => 'foo',
    },
    replace => 1;

The list of available options is:

=head2 replace

Set this to a true value to prevent C<Class::XSAccessor> from
complaining about replacing existing subroutines.

=head2 chained

Set this to a true value to change the return value of setters
and mutators (when called with an argument).
If C<chained> is enabled, the setters and accessors/mutators will
return the object. Mutators called without an argument still
return the value of the associated attribute.

As with the other options, C<chained> affects all methods generated
in the same C<use Class::XSAccessor ...> statement.

=head2 class

By default, the accessors are generated in the calling class. Using
the C<class> option, you can explicitly specify where the methods
are to be generated.

=head1 CAVEATS

Probably wouldn't work if your objects are I<tied> hashes. But that's a strange thing to do anyway.

Scary code exploiting strange XS features.

If you think writing an accessor in XS should be a laughably simple exercise, then
please contemplate how you could instantiate a new XS accessor for a new hash key
that's only known at run-time. Note that compiling C code at run-time a la Inline::C
is a no go.

Threading. With version 1.00, a memory leak has been B<fixed> that would leak a small amount of
memory if you loaded C<Class::XSAccessor>-based classes in a subthread that hadn't been loaded
in the "main" thread before. If the subthread then terminated, a hash key and an int per
associated method used ot be lost. Note that this mattered only if classes were B<only> loaded
in a sort of throw-away thread.

In the new implementation as of 1.00, the memory will not be released again either in the above
situation. But it will be recycled when the same class or a similar class is loaded
again in B<any> thread.

=head1 SEE ALSO

L<Class::XSAccessor::Array>

L<AutoXS>

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

Chocolateboy, E<lt>chocolate@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2009 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

