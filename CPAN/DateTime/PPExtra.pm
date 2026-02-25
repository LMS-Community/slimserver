package DateTime::PPExtra;

use strict;
use warnings;

our $VERSION = '1.66';

use DateTime::LeapSecond;

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _normalize_tai_seconds {
    return
        if
        grep { $_ == DateTime::INFINITY() || $_ == DateTime::NEG_INFINITY() }
        @_[ 1, 2 ];

    # This must be after checking for infinity, because it breaks in
    # presence of use integer !
    use integer;

    my $adj;

    if ( $_[2] < 0 ) {
        $adj = ( $_[2] - 86399 ) / 86400;
    }
    else {
        $adj = $_[2] / 86400;
    }

    $_[1] += $adj;

    $_[2] -= $adj * 86400;
}

sub _normalize_leap_seconds {

    # args: 0 => days, 1 => seconds
    my $delta_days;

    use integer;

    # rough adjust - can adjust many days
    if ( $_[2] < 0 ) {
        $delta_days = ( $_[2] - 86399 ) / 86400;
    }
    else {
        $delta_days = $_[2] / 86400;
    }

    my $new_day = $_[1] + $delta_days;
    my $delta_seconds
        = ( 86400 * $delta_days )
        + DateTime::LeapSecond::leap_seconds($new_day)
        - DateTime::LeapSecond::leap_seconds( $_[1] );

    $_[2] -= $delta_seconds;
    $_[1] = $new_day;

    # fine adjust - up to 1 day
    my $day_length = DateTime::LeapSecond::day_length($new_day);
    if ( $_[2] >= $day_length ) {
        $_[2] -= $day_length;
        $_[1]++;
    }
    elsif ( $_[2] < 0 ) {
        $day_length = DateTime::LeapSecond::day_length( $new_day - 1 );
        $_[2] += $day_length;
        $_[1]--;
    }
}

my @subs = qw(
    _normalize_tai_seconds
    _normalize_leap_seconds
);

for my $sub (@subs) {
    ## no critic (TestingAndDebugging::ProhibitNoStrict)
    no strict 'refs';
    *{ 'DateTime::' . $sub } = __PACKAGE__->can($sub);
}

1;
