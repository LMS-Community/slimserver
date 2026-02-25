package Clone::PP;

use 5.006;
use strict;
use warnings;
use vars qw($VERSION @EXPORT_OK);
use Exporter;

$VERSION = 1.08;

@EXPORT_OK = qw( clone );
sub import { goto &Exporter::import } # lazy Exporter

# These methods can be temporarily overridden to work with a given class.
use vars qw( $CloneSelfMethod $CloneInitMethod );
$CloneSelfMethod ||= 'clone_self';
$CloneInitMethod ||= 'clone_init';

# Used to detect looped networks and avoid infinite recursion. 
use vars qw( %CloneCache );

# Generic cloning function
sub clone {
  my $source = shift;

  return undef if not defined($source);
  
  # Optional depth limit: after a given number of levels, do shallow copy.
  my $depth = shift;
  return $source if ( defined $depth and $depth -- < 1 );
  
  # Maintain a shared cache during recursive calls, then clear it at the end.
  local %CloneCache = ( undef => undef ) unless ( exists $CloneCache{undef} );
  
  return $CloneCache{ $source } if ( defined $CloneCache{ $source } );
  
  # Non-reference values are copied shallowly
  my $ref_type = ref $source or return $source;
  
  # Extract both the structure type and the class name of referent
  my $class_name;
  if ( "$source" =~ /^\Q$ref_type\E\=([A-Z]+)\(0x[0-9a-f]+\)$/ ) {
    $class_name = $ref_type;
    $ref_type = $1;
    # Some objects would prefer to clone themselves; check for clone_self().
    return $CloneCache{ $source } = $source->$CloneSelfMethod() 
				  if $source->can($CloneSelfMethod);
  }
  
  # To make a copy:
  # - Prepare a reference to the same type of structure;
  # - Store it in the cache, to avoid looping if it refers to itself;
  # - Tie in to the same class as the original, if it was tied;
  # - Assign a value to the reference by cloning each item in the original;
  
  my $copy;
  if ($ref_type eq 'HASH') {
    $CloneCache{ $source } = $copy = {};
    if ( my $tied = tied( %$source ) ) { tie %$copy, ref $tied }
    %$copy = map { ! ref($_) ? $_ : clone($_, $depth) } %$source;
  } elsif ($ref_type eq 'ARRAY') {
    $CloneCache{ $source } = $copy = [];
    if ( my $tied = tied( @$source ) ) { tie @$copy, ref $tied }
    @$copy = map { ! ref($_) ? $_ : clone($_, $depth) } @$source;
  } elsif ($ref_type eq 'REF' or $ref_type eq 'SCALAR') {
    $CloneCache{ $source } = $copy = \( my $var = "" );
    if ( my $tied = tied( $$source ) ) { tie $$copy, ref $tied }
    $$copy = clone($$source, $depth);
  } else {
    # Shallow copy anything else; this handles a reference to code, glob, regex
    $CloneCache{ $source } = $copy = $source;
  }
  
  # - Bless it into the same class as the original, if it was blessed;
  # - If it has a post-cloning initialization method, call it.
  if ( $class_name ) {
    bless $copy, $class_name;
    $copy->$CloneInitMethod() if $copy->can($CloneInitMethod);
  }
  
  return $copy;
}

1;

__END__

=head1 NAME

Clone::PP - Recursively copy Perl datatypes

=head1 SYNOPSIS

  use Clone::PP qw(clone);
  
  $item = { 'foo' => 'bar', 'move' => [ 'zig', 'zag' ]  };
  $copy = clone( $item );

  $item = [ 'alpha', 'beta', { 'gamma' => 'vlissides' } ];
  $copy = clone( $item );

  $item = Foo->new();
  $copy = clone( $item );

Or as an object method:

  require Clone::PP;
  push @Foo::ISA, 'Clone::PP';
  
  $item = Foo->new();
  $copy = $item->clone();

=head1 DESCRIPTION

This module provides a general-purpose clone function to make deep
copies of Perl data structures. It calls itself recursively to copy
nested hash, array, scalar and reference types, including tied
variables and objects.

The clone() function takes a scalar argument to copy. To duplicate
arrays or hashes, pass them in by reference:

  my $copy = clone(\@array);    my @copy = @{ clone(\@array) };
  my $copy = clone(\%hash);     my %copy = %{ clone(\%hash) };

The clone() function also accepts an optional second parameter that
can be used to limit the depth of the copy. If you pass a limit of
0, clone will return the same value you supplied; for a limit of
1, a shallow copy is constructed; for a limit of 2, two layers of
copying are done, and so on.

  my $shallow_copy = clone( $item, 1 );

To allow objects to intervene in the way they are copied, the
clone() function checks for a couple of optional methods. If an
object provides a method named C<clone_self>, it is called and the
result returned without further processing. Alternately, if an
object provides a method named C<clone_init>, it is called on the
copied object before it is returned.

=head1 BUGS

Some data types, such as globs, regexes, and code refs, are always copied shallowly.

References to hash elements are not properly duplicated. (This is why two tests in t/dclone.t that are marked "todo".) For example, the following test should succeed but does not:

  my $hash = { foo => 1 }; 
  $hash->{bar} = \{ $hash->{foo} }; 
  my $copy = clone( \%hash ); 
  $hash->{foo} = 2; 
  $copy->{foo} = 2; 
  ok( $hash->{bar} == $copy->{bar} );

To report bugs via the CPAN web tracking system, go to 
C<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Clone-PP> or send mail 
to C<Dist=Clone-PP#rt.cpan.org>, replacing C<#> with C<@>.

=head1 SEE ALSO

L<Clone> - a baseclass which provides a C<clone()> method.

L<MooseX::Clone> - find-grained cloning for Moose objects.

The C<dclone()> function in L<Storable>.

L<Data::Clone> -
polymorphic data cloning (see its documentation for what that means).

L<Clone::Any> - use whichever of the cloning methods is available.

=head1 REPOSITORY

L<https://github.com/neilbowers/Clone-PP>

=head1 AUTHOR AND CREDITS

Developed by Matthew Simon Cavalletto at Evolution Softworks. 
More free Perl software is available at C<www.evoscript.org>.


=head1 COPYRIGHT AND LICENSE

Copyright 2003 Matthew Simon Cavalletto. You may contact the author
directly at C<evo@cpan.org> or C<simonm@cavalletto.org>.

Code initially derived from Ref.pm. Portions Copyright 1994 David Muir Sharnoff.

Interface based by Clone by Ray Finch with contributions from chocolateboy.
Portions Copyright 2001 Ray Finch. Portions Copyright 2001 chocolateboy. 

You may use, modify, and distribute this software under the same terms as Perl.

=cut
