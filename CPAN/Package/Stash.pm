package Package::Stash; # git description: v0.39-2-ga9a8cce
use strict;
use warnings;
use 5.008001;
# ABSTRACT: Routines for manipulating stashes

our $VERSION = '0.40';
our $IMPLEMENTATION;

use Module::Implementation 0.06;

BEGIN {
    local $ENV{PACKAGE_STASH_IMPLEMENTATION} = $IMPLEMENTATION
      if ( $IMPLEMENTATION and not $ENV{PACKAGE_STASH_IMPLEMENTATION} );

    Module::Implementation::build_loader_sub(
        implementations => [ 'XS', 'PP' ],
        symbols         => [qw(
            new
            name
            namespace
            add_symbol
            remove_glob
            has_symbol
            get_symbol
            get_or_add_symbol
            remove_symbol
            list_all_symbols
            get_all_symbols
        )],
    )->();
    $IMPLEMENTATION = Module::Implementation::implementation_for(__PACKAGE__);
}

__END__

=pod

=encoding UTF-8

=head1 NAME

Package::Stash - Routines for manipulating stashes

=head1 VERSION

version 0.40

=head1 SYNOPSIS

  my $stash = Package::Stash->new('Foo');
  $stash->add_symbol('%foo', {bar => 1});
  # $Foo::foo{bar} == 1
  $stash->has_symbol('$foo') # false
  my $namespace = $stash->namespace;
  *{ $namespace->{foo} }{HASH} # {bar => 1}

=head1 DESCRIPTION

Manipulating stashes (Perl's symbol tables) is occasionally necessary, but
incredibly messy, and easy to get wrong. This module hides all of that behind a
simple API.

NOTE: Most methods in this class require a variable specification that includes
a sigil. If this sigil is absent, it is assumed to represent the IO slot.

Due to limitations in the typeglob API available to perl code, and to typeglob
manipulation in perl being quite slow, this module provides two
implementations - one in pure perl, and one using XS. The XS implementation is
to be preferred for most usages; the pure perl one is provided for cases where
XS modules are not a possibility. The current implementation in use can be set
by setting C<$ENV{PACKAGE_STASH_IMPLEMENTATION}> or
C<$Package::Stash::IMPLEMENTATION> before loading Package::Stash (with the
environment variable taking precedence), otherwise, it will use the XS
implementation if possible, falling back to the pure perl one.

=head1 METHODS

=head2 new $package_name

Creates a new C<Package::Stash> object, for the package given as the only
argument.

=head2 name

Returns the name of the package that this object represents.

=head2 namespace

Returns the raw stash itself.

=head2 add_symbol $variable $value %opts

Adds a new package symbol, for the symbol given as C<$variable>, and optionally
gives it an initial value of C<$value>. C<$variable> should be the name of
variable including the sigil, so

  Package::Stash->new('Foo')->add_symbol('%foo')

will create C<%Foo::foo>.

Valid options (all optional) are C<filename>, C<first_line_num>, and
C<last_line_num>.

C<$opts{filename}>, C<$opts{first_line_num}>, and C<$opts{last_line_num}> can
be used to indicate where the symbol should be regarded as having been defined.
Currently these values are only used if the symbol is a subroutine ('C<&>'
sigil) and only if C<$^P & 0x10> is true, in which case the special C<%DB::sub>
hash is updated to record the values of C<filename>, C<first_line_num>, and
C<last_line_num> for the subroutine. If these are not passed, their values are
inferred (as much as possible) from C<caller> information.

=head2 remove_glob $name

Removes all package variables with the given name, regardless of sigil.

=head2 has_symbol $variable

Returns whether or not the given package variable (including sigil) exists.

=head2 get_symbol $variable

Returns the value of the given package variable (including sigil).

=head2 get_or_add_symbol $variable

Like C<get_symbol>, except that it will return an empty hashref or
arrayref if the variable doesn't exist.

=head2 remove_symbol $variable

Removes the package variable described by C<$variable> (which includes the
sigil); other variables with the same name but different sigils will be
untouched.

=head2 list_all_symbols $type_filter

Returns a list of package variable names in the package, without sigils. If a
C<type_filter> is passed, it is used to select package variables of a given
type, where valid types are the slots of a typeglob ('SCALAR', 'CODE', 'HASH',
etc). Note that if the package contained any C<BEGIN> blocks, perl will leave
an empty typeglob in the C<BEGIN> slot, so this will show up if no filter is
used (and similarly for C<INIT>, C<END>, etc).

=head2 get_all_symbols $type_filter

Returns a hashref, keyed by the variable names in the package. If
C<$type_filter> is passed, the hash will contain every variable of that type in
the package as values, otherwise, it will contain the typeglobs corresponding
to the variable names (basically, a clone of the stash).

=for stopwords profilers

This is especially useful for debuggers and profilers, which use C<%DB::sub> to
determine where the source code for a subroutine can be found.  See
L<http://perldoc.perl.org/perldebguts.html#Debugger-Internals> for more
information about C<%DB::sub>.

=head1 WORKING WITH VARIABLES

It is important to note, that when working with scalar variables, the default
behavior is to B<copy> values.

  my $stash = Package::Stash->new('Some::Namespace');
  my $variable = 1;
  # $Some::Namespace::name is a copy of $variable
  $stash->add_symbol('$name', $variable);
  $variable++
  # $Some::Namespace::name == 1 , $variable == 2

This will likely confuse people who expect it to work the same as typeglob
assignment, which simply creates new references to existing variables.

  my $variable = 1;
  {
      no strict 'refs';
      # assign $Package::Stash::name = $variable
      *{'Package::Stash::name'} = \$variable;
  }
  $variable++ # affects both names

If this behaviour is desired when working with Package::Stash, simply pass
Package::Stash a scalar ref:

  my $stash = Package::Stash->new('Some::Namespace');
  my $variable = 1;
  # $Some::Namespace::name is now $variable
  $stash->add_symbol('$name', \$variable);
  $variable++
  # $Some::Namespace::name == 2 , $variable == 2

This will be what you want as well if you're ever working with L<Readonly>
variables:

  use Readonly;
  Readonly my $value, 'hello';

  $stash->add_symbol('$name', \$value); # reference
  print $Some::Namespace::name; # hello
  # Tries to modify the read-only 'hello' and dies.
  $Some::Namespace::name .= " world";

  $stash->add_symbol('$name', $value); # copy
  print $Some::Namespace::name; # hello
  # No problem, modifying a copy, not the original
  $Some::Namespace::name .= " world";

=head1 BUGS / CAVEATS

=over 4

=item * Prior to perl 5.10, scalar slots are only considered to exist if they are defined

This is due to a shortcoming within perl itself. See
L<perlref/Making References> point 7 for more information.

=item * GLOB and FORMAT variables are not (yet) accessible through this module.

=item * Also, see the BUGS section for the specific backends (L<Package::Stash::XS> and L<Package::Stash::PP>)

=back

=head1 SEE ALSO

=over 4

=item * L<Class::MOP::Package>

This module is a factoring out of code that used to live here

=back

=head1 HISTORY

Based on code from L<Class::MOP::Package>, by Stevan Little and the Moose
Cabal.

=head1 SUPPORT

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Package-Stash>
(or L<bug-Package-Stash@rt.cpan.org|mailto:bug-Package-Stash@rt.cpan.org>).

=head1 AUTHORS

=over 4

=item *

Stevan Little <stevan.little@iinteractive.com>

=item *

Jesse Luehrs <doy@tozt.net>

=back

=head1 CONTRIBUTORS

=for stopwords Karen Etheridge Carlos Lima Christian Walde Dave Rolsky Justin Hunter Kent Fredric Niko Tyni Renee Tim Bunce

=over 4

=item *

Karen Etheridge <ether@cpan.org>

=item *

Carlos Lima <carlos@multi>

=item *

Christian Walde <walde.christian@googlemail.com>

=item *

Dave Rolsky <autarch@urth.org>

=item *

Justin Hunter <justin.d.hunter@gmail.com>

=item *

Kent Fredric <kentfredric@gmail.com>

=item *

Niko Tyni <ntyni@debian.org>

=item *

Renee <reb@perl-services.de>

=item *

Tim Bunce <Tim.Bunce@pobox.com>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2022 by Jesse Luehrs.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
