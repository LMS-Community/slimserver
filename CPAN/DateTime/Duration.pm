package DateTime::Duration;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '1.66';

use Carp ();
use DateTime;
use DateTime::Helpers;
use DateTime::Types;
use Params::ValidationCompiler 0.26 qw( validation_for );
use Scalar::Util qw( blessed );

use overload (
    fallback => 1,
    '+'      => '_add_overload',
    '-'      => '_subtract_overload',
    '*'      => '_multiply_overload',
    '<=>'    => '_compare_overload',
    'cmp'    => '_compare_overload',
);

sub MAX_NANOSECONDS () {1_000_000_000}    # 1E9 = almost 32 bits

my @all_units = qw( months days minutes seconds nanoseconds );

{
    my %units = map {
        $_ => {

            # XXX - what we really want is to accept an integer, Inf, -Inf,
            # and NaN, but I can't figure out how to accept NaN since it never
            # compares to anything.
            type    => t('Defined'),
            default => 0,
        }
        } qw(
        years
        months
        weeks
        days
        hours
        minutes
        seconds
        nanoseconds
        );

    my $check = validation_for(
        name             => '_check_new_params',
        name_is_optional => 1,
        params           => {
            %units,
            end_of_month => {
                type     => t('EndOfMonthMode'),
                optional => 1,
            },
        },
    );

    sub new {
        my $class = shift;
        my %p     = $check->(@_);

        my $self = bless {}, $class;

        $self->{months} = ( $p{years} * 12 ) + $p{months};

        $self->{days} = ( $p{weeks} * 7 ) + $p{days};

        $self->{minutes} = ( $p{hours} * 60 ) + $p{minutes};

        $self->{seconds} = $p{seconds};

        if ( $p{nanoseconds} ) {
            $self->{nanoseconds} = $p{nanoseconds};
            $self->_normalize_nanoseconds;
        }
        else {

            # shortcut - if they don't need nanoseconds
            $self->{nanoseconds} = 0;
        }

        $self->{end_of_month} = (
              defined $p{end_of_month} ? $p{end_of_month}
            : $self->{months} < 0      ? 'preserve'
            :                            'wrap'
        );

        return $self;
    }
}

# make the signs of seconds, nanos the same; 0 < abs(nanos) < MAX_NANOS
# NB this requires nanoseconds != 0 (callers check this already)
sub _normalize_nanoseconds {
    my $self = shift;

    return
        if ( $self->{nanoseconds} == DateTime::INFINITY()
        || $self->{nanoseconds} == DateTime::NEG_INFINITY()
        || $self->{nanoseconds} eq DateTime::NAN() );

    my $seconds = $self->{seconds} + $self->{nanoseconds} / MAX_NANOSECONDS;
    $self->{seconds}     = int($seconds);
    $self->{nanoseconds} = $self->{nanoseconds} % MAX_NANOSECONDS;
    $self->{nanoseconds} -= MAX_NANOSECONDS if $seconds < 0;
}

sub clone { bless { %{ $_[0] } }, ref $_[0] }

sub years       { abs( $_[0]->in_units('years') ) }
sub months      { abs( $_[0]->in_units( 'months', 'years' ) ) }
sub weeks       { abs( $_[0]->in_units('weeks') ) }
sub days        { abs( $_[0]->in_units( 'days', 'weeks' ) ) }
sub hours       { abs( $_[0]->in_units('hours') ) }
sub minutes     { abs( $_[0]->in_units( 'minutes', 'hours' ) ) }
sub seconds     { abs( $_[0]->in_units('seconds') ) }
sub nanoseconds { abs( $_[0]->in_units( 'nanoseconds', 'seconds' ) ) }

sub is_positive { $_[0]->_has_positive  && !$_[0]->_has_negative }
sub is_negative { !$_[0]->_has_positive && $_[0]->_has_negative }

sub _has_positive {
    ( grep { $_ > 0 } @{ $_[0] }{@all_units} ) ? 1 : 0;
}

sub _has_negative {
    ( grep { $_ < 0 } @{ $_[0] }{@all_units} ) ? 1 : 0;
}

sub is_zero {
    return 0 if grep { $_ != 0 } @{ $_[0] }{@all_units};
    return 1;
}

sub delta_months      { $_[0]->{months} }
sub delta_days        { $_[0]->{days} }
sub delta_minutes     { $_[0]->{minutes} }
sub delta_seconds     { $_[0]->{seconds} }
sub delta_nanoseconds { $_[0]->{nanoseconds} }

sub deltas {
    map { $_ => $_[0]->{$_} } @all_units;
}

sub in_units {
    my $self  = shift;
    my @units = @_;

    my %units = map { $_ => 1 } @units;

    my %ret;

    my ( $months, $days, $minutes, $seconds )
        = @{$self}{qw( months days minutes seconds )};

    if ( $units{years} ) {
        $ret{years} = int( $months / 12 );
        $months -= $ret{years} * 12;
    }

    if ( $units{months} ) {
        $ret{months} = $months;
    }

    if ( $units{weeks} ) {
        $ret{weeks} = int( $days / 7 );
        $days -= $ret{weeks} * 7;
    }

    if ( $units{days} ) {
        $ret{days} = $days;
    }

    if ( $units{hours} ) {
        $ret{hours} = int( $minutes / 60 );
        $minutes -= $ret{hours} * 60;
    }

    if ( $units{minutes} ) {
        $ret{minutes} = $minutes;
    }

    if ( $units{seconds} ) {
        $ret{seconds} = $seconds;
        $seconds = 0;
    }

    if ( $units{nanoseconds} ) {
        $ret{nanoseconds} = $seconds * MAX_NANOSECONDS + $self->{nanoseconds};
    }

    wantarray ? @ret{@units} : $ret{ $units[0] };
}

sub is_wrap_mode     { $_[0]->{end_of_month} eq 'wrap'     ? 1 : 0 }
sub is_limit_mode    { $_[0]->{end_of_month} eq 'limit'    ? 1 : 0 }
sub is_preserve_mode { $_[0]->{end_of_month} eq 'preserve' ? 1 : 0 }

sub end_of_month_mode { $_[0]->{end_of_month} }

sub calendar_duration {
    my $self = shift;

    return ( ref $self )
        ->new( map { $_ => $self->{$_} } qw( months days end_of_month ) );
}

sub clock_duration {
    my $self = shift;

    return ( ref $self )
        ->new( map { $_ => $self->{$_} }
            qw( minutes seconds nanoseconds end_of_month ) );
}

sub inverse {
    my $self = shift;
    my %p    = @_;

    my %new;
    foreach my $u (@all_units) {
        $new{$u} = $self->{$u};

        # avoid -0 bug
        $new{$u} *= -1 if $new{$u};
    }

    $new{end_of_month} = $p{end_of_month}
        if exists $p{end_of_month};

    return ( ref $self )->new(%new);
}

sub add_duration {
    my ( $self, $dur ) = @_;

    foreach my $u (@all_units) {
        $self->{$u} += $dur->{$u};
    }

    $self->_normalize_nanoseconds if $self->{nanoseconds};

    return $self;
}

sub add {
    my $self = shift;

    return $self->add_duration( $self->_duration_object_from_args(@_) );
}

sub subtract {
    my $self = shift;

    return $self->subtract_duration( $self->_duration_object_from_args(@_) );
}

# Syntactic sugar for add and subtract: use a duration object if it's
# supplied, otherwise build a new one from the arguments.
sub _duration_object_from_args {
    my $self = shift;

    return $_[0]
        if @_ == 1 && blessed( $_[0] ) && $_[0]->isa(__PACKAGE__);

    return __PACKAGE__->new(@_);
}

sub subtract_duration { return $_[0]->add_duration( $_[1]->inverse ) }

{
    my $check = validation_for(
        name             => '_check_multiply_params',
        name_is_optional => 1,
        params           => [
            { type => t('Int') },
        ],
    );

    sub multiply {
        my $self = shift;
        my ($multiplier) = $check->(@_);

        foreach my $u (@all_units) {
            $self->{$u} *= $multiplier;
        }

        $self->_normalize_nanoseconds if $self->{nanoseconds};

        return $self;
    }
}

sub compare {
    my ( undef, $dur1, $dur2, $dt ) = @_;

    $dt ||= DateTime->now;

    return DateTime->compare(
        $dt->clone->add_duration($dur1),
        $dt->clone->add_duration($dur2)
    );
}

sub _add_overload {
    my ( $d1, $d2, $rev ) = @_;

    ( $d1, $d2 ) = ( $d2, $d1 ) if $rev;

    if ( DateTime::Helpers::isa( $d2, 'DateTime' ) ) {
        $d2->add_duration($d1);
        return;
    }

    # will also work if $d1 is a DateTime.pm object
    return $d1->clone->add_duration($d2);
}

sub _subtract_overload {
    my ( $d1, $d2, $rev ) = @_;

    ( $d1, $d2 ) = ( $d2, $d1 ) if $rev;

    Carp::croak(
        'Cannot subtract a DateTime object from a DateTime::Duration object')
        if DateTime::Helpers::isa( $d2, 'DateTime' );

    return $d1->clone->subtract_duration($d2);
}

sub _multiply_overload {
    my $self = shift;

    my $new = $self->clone;

    return $new->multiply(shift);
}

sub _compare_overload {
    Carp::croak( 'DateTime::Duration does not overload comparison.'
            . '  See the documentation on the compare() method for details.'
    );
}

1;

# ABSTRACT: Duration objects for date math

__END__

=pod

=encoding UTF-8

=head1 NAME

DateTime::Duration - Duration objects for date math

=head1 VERSION

version 1.66

=head1 SYNOPSIS

    use DateTime::Duration;

    $dur = DateTime::Duration->new(
        years        => 3,
        months       => 5,
        weeks        => 1,
        days         => 1,
        hours        => 6,
        minutes      => 15,
        seconds      => 45,
        nanoseconds  => 12000,
        end_of_month => 'limit',
    );

    my ( $days, $hours, $seconds )
        = $dur->in_units( 'days', 'hours', 'seconds' );

    # Human-readable accessors, always positive, but consider using
    # DateTime::Format::Duration instead
    $dur->years;
    $dur->months;
    $dur->weeks;
    $dur->days;
    $dur->hours;
    $dur->minutes;
    $dur->seconds;
    $dur->nanoseconds;

    $dur->is_wrap_mode;
    $dur->is_limit_mode;
    $dur->is_preserve_mode;

    print $dur->end_of_month_mode;

    # Multiply all values by -1
    my $opposite = $dur->inverse;

    my $bigger  = $dur1 + $dur2;
    my $smaller = $dur1 - $dur2;    # the result could be negative
    my $bigger  = $dur1 * 3;

    my $base_dt = DateTime->new( year => 2000 );
    my @sorted
        = sort { DateTime::Duration->compare( $a, $b, $base_dt ) } @durations;

    if ( $dur->is_positive ) {...}
    if ( $dur->is_zero )     {...}
    if ( $dur->is_negative ) {...}

=head1 DESCRIPTION

This is a simple class for representing duration objects. These objects are
used whenever you do date math with L<DateTime>.

See the L<How DateTime Math Works|DateTime/"How DateTime Math Works"> section
of the L<DateTime> documentation for more details. The short course: One cannot
in general convert between seconds, minutes, days, and months, so this class
will never do so. Instead, create the duration with the desired units to begin
with, for example by calling the appropriate subtraction/delta method on a
L<DateTime> object.

=head1 METHODS

Like L<DateTime> itself, C<DateTime::Duration> returns the object from mutator
methods in order to make method chaining possible.

C<DateTime::Duration> has the following methods:

=head2 DateTime::Duration->new( ... )

This class method accepts the following parameters:

=over 4

=item * years

An integer containing the number of years in the duration. This is optional.

=item * months

An integer containing the number of months in the duration. This is optional.

=item * weeks

An integer containing the number of weeks in the duration. This is optional.

=item * days

An integer containing the number of days in the duration. This is optional.

=item * hours

An integer containing the number of hours in the duration. This is optional.

=item * minutes

An integer containing the number of minutes in the duration. This is optional.

=item * seconds

An integer containing the number of seconds in the duration. This is optional.

=item * nanoseconds

An integer containing the number of nanoseconds in the duration. This is
optional.

=item * end_of_month

This must be either C<"wrap">, C<"limit">, or C<"preserve">. This parameter
specifies how date math that crosses the end of a month is handled.

In C<"wrap"> mode, adding months or years that result in days beyond the end of
the new month will roll over into the following month. For instance, adding one
year to Feb 29 will result in Mar 1.

If you specify C<"limit">, the end of the month is never crossed. Thus, adding
one year to Feb 29, 2000 will result in Feb 28, 2001. If you were to then add
three more years this will result in Feb 28, 2004.

If you specify C<"preserve">, the same calculation is done as for C<"limit">
except that if the original date is at the end of the month the new date will
also be. For instance, adding one month to Feb 29, 2000 will result in Mar 31,
2000.

For positive durations, this parameter defaults to C<"wrap">. For negative
durations, the default is C<"preserve">. This should match how most people
"intuitively" expect datetime math to work.

=back

All of the duration units can be positive or negative. However, if any of the
numbers are negative, the entire duration is negative.

All of the numbers B<must be integers>.

Internally, years as just treated as 12 months. Similarly, weeks are treated as
7 days, and hours are converted to minutes. Seconds and nanoseconds are both
treated separately.

=head2 $dur->clone

Returns a new object with the same properties as the object on which this
method was called.

=head2 $dur->in_units( ... )

Returns the length of the duration in the units (any of those that can be
passed to C<< DateTime::Duration->new >>) given as arguments. All lengths are
integral, but may be negative. Smaller units are computed from what remains
after taking away the larger units given, so for example:

    my $dur = DateTime::Duration->new( years => 1, months => 15 );

    $dur->in_units('years');                # 2
    $dur->in_units('months');               # 27
    $dur->in_units( 'years', 'months' );    # (2, 3)
    $dur->in_units( 'weeks', 'days' );      # (0, 0) !

The last example demonstrates that there will not be any conversion between
units which don't have a fixed conversion rate. The only conversions possible
are:

=over 4

=item * years <=> months

=item * weeks <=> days

=item * hours <=> minutes

=item * seconds <=> nanoseconds

=back

For the explanation of why this is the case, please see the L<How DateTime Math
Works|DateTime/"How DateTime Math Works"> section of the DateTime documentation

Note that the numbers returned by this method may not match the values given to
the constructor.

In list context, C<< $dur->in_units >> returns the lengths in the order of the
units given. In scalar context, it returns the length in the first unit (but
still computes in terms of all given units).

If you need more flexibility in presenting information about durations, please
take a look a L<DateTime::Format::Duration>.

=head2 $dur->is_positive, $dur->is_zero, $dur->is_negative

Indicates whether or not the duration is positive, zero, or negative.

If the duration contains both positive and negative units, then it will return
false for B<all> of these methods.

=head2 $dur->is_wrap_mode, $dur->is_limit_mode, $dur->is_preserve_mode

Indicates what mode is used for end of month wrapping.

=head2 $dur->end_of_month_mode

Returns one of C<"wrap">, C<"limit">, or C<"preserve">.

=head2 $dur->calendar_duration

Returns a new object with the same I<calendar> delta (months and days only) and
end of month mode as the current object.

=head2 $dur->clock_duration

Returns a new object with the same I<clock> deltas (minutes, seconds, and
nanoseconds) and end of month mode as the current object.

=head2 $dur->inverse( ... )

Returns a new object with the same deltas as the current object, but multiplied
by -1. The end of month mode for the new object will be the default end of
month mode, which depends on whether the new duration is positive or negative.

You can set the end of month mode in the inverted duration explicitly by
passing an C<end_of_month> parameter to the C<< $dur->inverse >> method.

=head2 $dur->add_duration($duration_object), $dur->subtract_duration($duration_object)

Adds or subtracts one duration from another.

=head2 $dur->add( ... ), $dur->subtract( ... )

These accept either constructor parameters for a new C<DateTime::Duration>
object or an already-constructed duration object.

=head2 $dur->multiply($number)

Multiplies each unit in the C<DateTime::Duration> object by the specified
integer number.

=head2 DateTime::Duration->compare( $duration1, $duration2, $base_datetime )

This is a class method that can be used to compare or sort durations.
Comparison is done by adding each duration to the specified L<DateTime> object
and comparing the resulting datetimes. This is necessary because without a
base, many durations are not comparable. For example, 1 month may or may not be
longer than 29 days, depending on what datetime it is added to.

If no base datetime is given, then the result of C<< DateTime->now >> is used
instead. Using this default will give non-repeatable results if used to compare
two duration objects containing different units. It will also give
non-repeatable results if the durations contain multiple types of units, such
as months and days.

However, if you know that both objects only consist of one type of unit (months
I<or> days I<or> hours, etc.), and each duration contains the same type of
unit, then the results of the comparison will be repeatable.

=head2 $dur->delta_months, $dur->delta_days, $dur->delta_minutes, $dur->delta_seconds, $dur->delta_nanoseconds

These methods provide the information L<DateTime> needs for doing date math.
The numbers returned may be positive or negative. This is mostly useful for
doing date math in L<DateTime>.

=head2 $dur->deltas

Returns a hash with the keys "months", "days", "minutes", "seconds", and
"nanoseconds", containing all the delta information for the object. This is
mostly useful for doing date math in L<DateTime>.

=head2 $dur->years, $dur->months, $dur->weeks, $dur->days, $dur->hours, $dur->minutes, $dur->seconds, $dur->nanoseconds

These methods return numbers indicating how many of the given unit the object
represents, after having done a conversion to any larger units. For example,
days are first converted to weeks, and then the remainder is returned. These
numbers are always positive.

Here's what each method returns:

    $dur->years       == abs( $dur->in_units('years') )
    $dur->months      == abs( ( $dur->in_units( 'months', 'years' ) )[0] )
    $dur->weeks       == abs( $dur->in_units( 'weeks' ) )
    $dur->days        == abs( ( $dur->in_units( 'days', 'weeks' ) )[0] )
    $dur->hours       == abs( $dur->in_units( 'hours' ) )
    $dur->minutes     == abs( ( $dur->in_units( 'minutes', 'hours' ) )[0] )
    $dur->seconds     == abs( $dur->in_units( 'seconds' ) )
    $dur->nanoseconds == abs( ( $dur->in_units( 'nanoseconds', 'seconds' ) )[0] )

If this seems confusing, remember that you can always use the C<<
$dur->in_units >> method to specify exactly what you want.

Better yet, if you are trying to generate output suitable for humans, use the
C<DateTime::Format::Duration> module.

=head2 Overloading

This class overloads addition, subtraction, and mutiplication.

Comparison is B<not> overloaded. If you attempt to compare durations using C<<
<=> >> or C<cmp>, then an exception will be thrown!  Use the C<compare> class
method instead.

=head1 SEE ALSO

datetime@perl.org mailing list

=head1 SUPPORT

Support for this module is provided via the datetime@perl.org email list. See
http://lists.perl.org/ for more details.

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
