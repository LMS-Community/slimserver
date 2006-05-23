# $Id$
package Number::Compare;
use strict;
use Carp qw(croak);
use vars qw/$VERSION/;
$VERSION = '0.01';

sub new  {
    my $referent = shift;
    my $class = ref $referent || $referent;
    my $expr = $class->parse_to_perl( shift );

    bless eval "sub { \$_[0] $expr }", $class;
}

sub parse_to_perl {
    shift;
    my $test = shift;

    $test =~ m{^
               ([<>]=?)?   # comparison
               (.*?)       # value
               ([kmg]i?)?  # magnitude
              $}ix
       or croak "don't understand '$test' as a test";

    my $comparison = $1 || '==';
    my $target     = $2;
    my $magnitude  = $3;
    $target *=           1000 if lc $magnitude eq 'k';
    $target *=           1024 if lc $magnitude eq 'ki';
    $target *=        1000000 if lc $magnitude eq 'm';
    $target *=      1024*1024 if lc $magnitude eq 'mi';
    $target *=     1000000000 if lc $magnitude eq 'g';
    $target *= 1024*1024*1024 if lc $magnitude eq 'gi';

    return "$comparison $target";
}

sub test { $_[0]->( $_[1] ) }

1;

__END__

=head1 NAME

Number::Compare - numeric comparisons

=head1 SYNOPSIS

 Number::Compare->new(">1Ki")->test(1025); # is 1025 > 1024

 my $c = Number::Compare->new(">1M");
 $c->(1_200_000);                          # slightly terser invocation

=head1 DESCRIPTION

Number::Compare compiles a simple comparison to an anonymous
subroutine, which you can call with a value to be tested again.

Now this would be very pointless, if Number::Compare didn't understand
magnitudes.

The target value may use magnitudes of kilobytes (C<k>, C<ki>),
megabytes (C<m>, C<mi>), or gigabytes (C<g>, C<gi>).  Those suffixed
with an C<i> use the appropriate 2**n version in accordance with the
IEC standard: http://physics.nist.gov/cuu/Units/binary.html

=head1 METHODS

=head2 ->new( $test )

Returns a new object that compares the specified test.

=head2 ->test( $value )

A longhanded version of $compare->( $value ).  Predates blessed
subroutine reference implementation.

=head2 ->parse_to_perl( $test )

Returns a perl code fragment equivalent to the test.

=head1 AUTHOR

Richard Clamp <richardc@unixbeard.net>

=head1 COPYRIGHT

Copyright (C) 2002 Richard Clamp.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

http://physics.nist.gov/cuu/Units/binary.html

=cut
