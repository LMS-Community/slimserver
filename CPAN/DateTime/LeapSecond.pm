package DateTime::LeapSecond;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '1.66';

our ( @RD, @LEAP_SECONDS, %RD_LENGTH );

use DateTime;

# Generates a Perl binary decision tree
sub _make_utx {
    my ( $beg, $end, $tab, $op ) = @_;
    my $step = int( ( $end - $beg ) / 2 );
    my $tmp;
    if ( $step <= 0 ) {
        $tmp = "${tab}return $LEAP_SECONDS[$beg + 1];\n";
        return $tmp;
    }
    $tmp = "${tab}if (\$val < " . $RD[ $beg + $step ] . ") {\n";
    $tmp .= _make_utx( $beg, $beg + $step, $tab . q{    }, $op );
    $tmp .= "${tab}}\n";
    $tmp .= "${tab}else {\n";
    $tmp .= _make_utx( $beg + $step, $end, $tab . q{    }, $op );
    $tmp .= "${tab}}\n";
    return $tmp;
}

# Process BEGIN data and write binary tree decision table
sub _init {
    my $value = -1;
    while (@_) {
        my ( $year, $mon, $mday, $leap_seconds )
            = ( shift, shift, shift, shift );

        # print "$year,$mon,$mday\n";

        ## no critic (Subroutines::ProtectPrivateSubs)
        my $utc_epoch
            = DateTime->_ymd2rd( $year, ( $mon =~ /Jan/i ? 1 : 7 ), $mday );

        $value++;
        push @LEAP_SECONDS, $value;
        push @RD,           $utc_epoch;

        $RD_LENGTH{ $utc_epoch - 1 } = $leap_seconds;

        # warn "$year,$mon,$mday = $utc_epoch +$value";
    }

    push @LEAP_SECONDS, ++$value;

    my $tmp;

    # write binary tree decision table

    $tmp = "sub leap_seconds {\n";
    $tmp .= "    my \$val = shift;\n";
    $tmp .= _make_utx( -1, 1 + $#RD, q{    }, '+' );
    $tmp .= "}; 1\n";

    # NOTE: uncomment the line below to see the code:
    #warn $tmp;

    ## no critic (BuiltinFunctions::ProhibitStringyEval)
    eval $tmp or die $@;
}

sub extra_seconds {
    exists $RD_LENGTH{ $_[0] } ? $RD_LENGTH{ $_[0] } : 0;
}

sub day_length {
    exists $RD_LENGTH{ $_[0] } ? 86400 + $RD_LENGTH{ $_[0] } : 86400;
}

sub _initialize {

    # There are no leap seconds before 1972, because that's the
    # year this system was implemented.
    #
    # year month day number-of-leapseconds
    #
    _init(
        qw(
            1972  Jul. 1  +1
            1973  Jan. 1  +1
            1974  Jan. 1  +1
            1975  Jan. 1  +1
            1976  Jan. 1  +1
            1977  Jan. 1  +1
            1978  Jan. 1  +1
            1979  Jan. 1  +1
            1980  Jan. 1  +1
            1981  Jul. 1  +1
            1982  Jul. 1  +1
            1983  Jul. 1  +1
            1985  Jul. 1  +1
            1988  Jan. 1  +1
            1990  Jan. 1  +1
            1991  Jan. 1  +1
            1992  Jul. 1  +1
            1993  Jul. 1  +1
            1994  Jul. 1  +1
            1996  Jan. 1  +1
            1997  Jul. 1  +1
            1999  Jan. 1  +1
            2006  Jan. 1  +1
            2009  Jan. 1  +1
            2012  Jul. 1  +1
            2015  Jul. 1  +1
            2017  Jan. 1  +1
        )
    );
}

__PACKAGE__->_initialize();

1;

# ABSTRACT: leap seconds table and utilities

__END__

=pod

=encoding UTF-8

=head1 NAME

DateTime::LeapSecond - leap seconds table and utilities

=head1 VERSION

version 1.66

=head1 SYNOPSIS

    use DateTime;
    use DateTime::LeapSecond;

    print "Leap seconds between years 1990 and 2000 are ";
    print DateTime::Leapsecond::leap_seconds($utc_rd_2000)
        - DateTime::Leapsecond::leap_seconds($utc_rd_1990);

=head1 DESCRIPTION

This module is used to calculate leap seconds for a given Rata Die day. It is
used when L<DateTime> cannot compile the XS version of this code.

This library is known to be accurate for dates until Jun 2020.

There are no leap seconds before 1972, because that's the year this system was
implemented.

=over 4

=item * leap_seconds($rd)

Returns the number of accumulated leap seconds for a given day.

=item * extra_seconds($rd)

Returns the number of leap seconds for a given day, in the range -2 .. 2.

=item * day_length($rd)

Returns the number of seconds for a given day, in the range 86398 .. 86402.

=back

=head1 SEE ALSO

L<http://hpiers.obspm.fr/eop-pc/earthor/utc/leapsecond.html>

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/DateTime.pm/issues>.

There is a mailing list available for users of this distribution,
L<mailto:datetime@perl.org>.

=head1 SOURCE

The source code repository for DateTime can be found at L<https://github.com/houseabsolute/DateTime.pm>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2003 - 2025 by Dave Rolsky.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
