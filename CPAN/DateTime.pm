## no critic (Modules::ProhibitExcessMainComplexity)
package DateTime;

use 5.008004;

use strict;
use warnings;
use warnings::register;
use namespace::autoclean 0.19;

our $VERSION = '1.66';

use Carp;
use DateTime::Duration;
use DateTime::Helpers;
use DateTime::Locale 1.06;
use DateTime::TimeZone 2.44;
use DateTime::Types;
use POSIX                           qw( floor fmod );
use Params::ValidationCompiler 0.26 qw( validation_for );
use Scalar::Util                    qw( blessed );
use Specio::Subs                    qw( Specio::Library::Builtins );
use Try::Tiny;

## no critic (Variables::ProhibitPackageVars)
our $IsPurePerl;

{
    my $loaded = 0;

    unless ( $ENV{PERL_DATETIME_PP} ) {
        try {
            require XSLoader;
            XSLoader::load(
                __PACKAGE__,
                exists $DateTime::{VERSION} && ${ $DateTime::{VERSION} }
                ? ${ $DateTime::{VERSION} }
                : 42
            );

            $loaded     = 1;
            $IsPurePerl = 0;
        }
        catch {
            die $_ if $_ && $_ !~ /object version|loadable object/;
        };
    }

    if ($loaded) {
        ## no critic (Variables::ProtectPrivateVars)
        require DateTime::PPExtra
            unless defined &DateTime::_normalize_tai_seconds;
    }
    else {
        require DateTime::PP;
    }
}

# for some reason, overloading doesn't work unless fallback is listed
# early.
#
# 3rd parameter ( $_[2] ) means the parameters are 'reversed'.
# see: "Calling conventions for binary operations" in overload docs.
#
use overload (
    fallback => 1,
    '<=>'    => '_compare_overload',
    'cmp'    => '_string_compare_overload',
    q{""}    => 'stringify',
    bool     => sub {1},
    '-'      => '_subtract_overload',
    '+'      => '_add_overload',
    'eq'     => '_string_equals_overload',
    'ne'     => '_string_not_equals_overload',
);

# Have to load this after overloading is defined, after BEGIN blocks
# or else weird crashes ensue
require DateTime::Infinite;

sub MAX_NANOSECONDS () {1_000_000_000}                  # 1E9 = almost 32 bits
sub INFINITY ()        { 100**100**100**100 }
sub NEG_INFINITY ()    { -1 * ( 100**100**100**100 ) }
sub NAN ()             { INFINITY - INFINITY }

sub SECONDS_PER_DAY () {86400}

sub duration_class () {'DateTime::Duration'}

my (
    @MonthLengths,
    @LeapYearMonthLengths,
    @QuarterLengths,
    @LeapYearQuarterLengths,
);

BEGIN {
    @MonthLengths = ( 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );

    @LeapYearMonthLengths = @MonthLengths;
    $LeapYearMonthLengths[1]++;

    @QuarterLengths = ( 90, 91, 92, 92 );

    @LeapYearQuarterLengths = @QuarterLengths;
    $LeapYearQuarterLengths[0]++;
}

{

    # I'd rather use Class::Data::Inheritable for this, but there's no
    # way to add the module-loading behavior to an accessor it
    # creates, despite what its docs say!
    my $DefaultLocale;

    sub DefaultLocale {
        shift;

        if (@_) {
            my $lang = shift;

            $DefaultLocale = DateTime::Locale->load($lang);
        }

        return $DefaultLocale;
    }
}
__PACKAGE__->DefaultLocale('en-US');

{
    my $validator = validation_for(
        name             => '_check_new_params',
        name_is_optional => 1,
        params           => {
            year  => { type => t('Year') },
            month => {
                type    => t('Month'),
                default => 1,
            },
            day => {
                type    => t('DayOfMonth'),
                default => 1,
            },
            hour => {
                type    => t('Hour'),
                default => 0,
            },
            minute => {
                type    => t('Minute'),
                default => 0,
            },
            second => {
                type    => t('Second'),
                default => 0,
            },
            nanosecond => {
                type    => t('Nanosecond'),
                default => 0,
            },
            locale => {
                type     => t('Locale'),
                optional => 1,
            },
            formatter => {
                type     => t('Formatter'),
                optional => 1,
            },
            time_zone => {
                type     => t('TimeZone'),
                optional => 1,
            },
        },
    );

    sub new {
        my $class = shift;
        my %p     = $validator->(@_);

        Carp::croak(
            "Invalid day of month (day = $p{day} - month = $p{month} - year = $p{year})\n"
            )
            if $p{day} > 28
            && $p{day} > $class->_month_length( $p{year}, $p{month} );

        return $class->_new(%p);
    }
}

sub _new {
    my $class = shift;
    my %p     = @_;

    Carp::croak('Constructor called with reference, we expected a package')
        if ref $class;

    # If this method is called from somewhere other than new(), then some of
    # these defaults may not get applied.
    $p{month}      = 1                          unless exists $p{month};
    $p{day}        = 1                          unless exists $p{day};
    $p{hour}       = 0                          unless exists $p{hour};
    $p{minute}     = 0                          unless exists $p{minute};
    $p{second}     = 0                          unless exists $p{second};
    $p{nanosecond} = 0                          unless exists $p{nanosecond};
    $p{time_zone}  = $class->_default_time_zone unless exists $p{time_zone};

    my $self = bless {}, $class;

    $self->_set_locale( $p{locale} );

    $self->{tz} = (
        ref $p{time_zone}
        ? $p{time_zone}
        : DateTime::TimeZone->new( name => $p{time_zone} )
    );

    $self->{local_rd_days} = $class->_ymd2rd( @p{qw( year month day )} );

    $self->{local_rd_secs}
        = $class->_time_as_seconds( @p{qw( hour minute second )} );

    $self->{offset_modifier} = 0;

    $self->{rd_nanosecs} = $p{nanosecond};
    $self->{formatter}   = $p{formatter};

    $self->_normalize_nanoseconds(
        $self->{local_rd_secs},
        $self->{rd_nanosecs}
    );

    # Set this explicitly since it can't be calculated accurately
    # without knowing our time zone offset, and it's possible that the
    # offset can't be calculated without having at least a rough guess
    # of the datetime's year. This year need not be correct, as long
    # as its equal or greater to the correct number, so we fudge by
    # adding one to the local year given to the constructor.
    $self->{utc_year} = $p{year} + 1;

    $self->_maybe_future_dst_warning( $p{year}, $p{time_zone} );

    $self->_calc_utc_rd;

    $self->_handle_offset_modifier( $p{second} );

    $self->_calc_local_rd;

    if ( $p{second} > 59 ) {
        if (
            $self->{tz}->is_floating
            ||

            # If true, this means that the actual calculated leap
            # second does not occur in the second given to new()
            ( $self->{utc_rd_secs} - 86399 < $p{second} - 59 )
        ) {
            Carp::croak("Invalid second value ($p{second})\n");
        }
    }

    return $self;
}

# Warning: do not use this environment variable unless you have no choice in
# the matter.
sub _default_time_zone {
    return $ENV{PERL_DATETIME_DEFAULT_TZ} || 'floating';
}

sub _set_locale {
    my $self   = shift;
    my $locale = shift;

    if ( defined $locale && ref $locale ) {
        $self->{locale} = $locale;
    }
    else {
        $self->{locale}
            = $locale
            ? DateTime::Locale->load($locale)
            : $self->DefaultLocale;
    }

    return;
}

# This method exists for the benefit of internal methods which create
# a new object based on the current object, like set() and truncate().
sub _new_from_self {
    my $self = shift;
    my %p    = @_;

    my %old = map { $_ => $self->$_() } qw(
        year month day
        hour minute second
        nanosecond
        locale time_zone
    );
    $old{formatter} = $self->formatter
        if defined $self->formatter;

    my $method = delete $p{_skip_validation} ? '_new' : 'new';

    return ( ref $self )->$method( %old, %p );
}

sub _handle_offset_modifier {
    my $self = shift;

    $self->{offset_modifier} = 0;

    return if $self->{tz}->is_floating;

    my $second       = shift;
    my $utc_is_valid = shift;

    my $utc_rd_days = $self->{utc_rd_days};

    my $offset
        = $utc_is_valid ? $self->offset : $self->_offset_for_local_datetime;

    if (   $offset >= 0
        && $self->{local_rd_secs} >= $offset ) {
        if ( $second < 60 && $offset > 0 ) {
            $self->{offset_modifier}
                = $self->_day_length( $utc_rd_days - 1 ) - SECONDS_PER_DAY;

            $self->{local_rd_secs} += $self->{offset_modifier};
        }
        elsif (
            $second == 60
            && (
                ( $self->{local_rd_secs} == $offset && $offset > 0 )
                || (   $offset == 0
                    && $self->{local_rd_secs} > 86399 )
            )
        ) {
            my $mod
                = $self->_day_length( $utc_rd_days - 1 ) - SECONDS_PER_DAY;

            unless ( $mod == 0 ) {
                $self->{utc_rd_secs} -= $mod;

                $self->_normalize_seconds;
            }
        }
    }
    elsif ($offset < 0
        && $self->{local_rd_secs} >= SECONDS_PER_DAY + $offset ) {
        if ( $second < 60 ) {
            $self->{offset_modifier}
                = $self->_day_length( $utc_rd_days - 1 ) - SECONDS_PER_DAY;

            $self->{local_rd_secs} += $self->{offset_modifier};
        }
        elsif ($second == 60
            && $self->{local_rd_secs} == SECONDS_PER_DAY + $offset ) {
            my $mod
                = $self->_day_length( $utc_rd_days - 1 ) - SECONDS_PER_DAY;

            unless ( $mod == 0 ) {
                $self->{utc_rd_secs} -= $mod;

                $self->_normalize_seconds;
            }
        }
    }
}

sub _calc_utc_rd {
    my $self = shift;

    delete $self->{utc_c};

    if ( $self->{tz}->is_utc || $self->{tz}->is_floating ) {
        $self->{utc_rd_days} = $self->{local_rd_days};
        $self->{utc_rd_secs} = $self->{local_rd_secs};
    }
    else {
        my $offset = $self->_offset_for_local_datetime;

        $offset += $self->{offset_modifier};

        $self->{utc_rd_days} = $self->{local_rd_days};
        $self->{utc_rd_secs} = $self->{local_rd_secs} - $offset;
    }

    # We account for leap seconds in the new() method and nowhere else
    # except date math.
    $self->_normalize_tai_seconds(
        $self->{utc_rd_days},
        $self->{utc_rd_secs}
    );
}

sub _normalize_seconds {
    my $self = shift;

    return if $self->{utc_rd_secs} >= 0 && $self->{utc_rd_secs} <= 86399;

    if ( $self->{tz}->is_floating ) {
        $self->_normalize_tai_seconds(
            $self->{utc_rd_days},
            $self->{utc_rd_secs}
        );
    }
    else {
        $self->_normalize_leap_seconds(
            $self->{utc_rd_days},
            $self->{utc_rd_secs}
        );
    }
}

sub _calc_local_rd {
    my $self = shift;

    delete $self->{local_c};

    # We must short circuit for UTC times or else we could end up with
    # loops between DateTime.pm and DateTime::TimeZone
    if ( $self->{tz}->is_utc || $self->{tz}->is_floating ) {
        $self->{local_rd_days} = $self->{utc_rd_days};
        $self->{local_rd_secs} = $self->{utc_rd_secs};
    }
    else {
        my $offset = $self->offset;

        $self->{local_rd_days} = $self->{utc_rd_days};
        $self->{local_rd_secs} = $self->{utc_rd_secs} + $offset;

        # intentionally ignore leap seconds here
        $self->_normalize_tai_seconds(
            $self->{local_rd_days},
            $self->{local_rd_secs}
        );

        $self->{local_rd_secs} += $self->{offset_modifier};
    }

    $self->_calc_local_components;
}

sub _calc_local_components {
    my $self = shift;

    @{ $self->{local_c} }{
        qw( year month day day_of_week
            day_of_year quarter day_of_quarter)
        }
        = $self->_rd2ymd( $self->{local_rd_days}, 1 );

    @{ $self->{local_c} }{qw( hour minute second )}
        = $self->_seconds_as_components(
        $self->{local_rd_secs},
        $self->{utc_rd_secs}, $self->{offset_modifier}
        );
}

{
    my $named_validator = validation_for(
        name             => '_check_named_from_epoch_params',
        name_is_optional => 1,
        params           => {
            epoch     => { type => t('Num') },
            formatter => {
                type     => t('Formatter'),
                optional => 1
            },
            locale => {
                type     => t('Locale'),
                optional => 1
            },
            time_zone => {
                type     => t('TimeZone'),
                optional => 1
            },
        },
    );

    my $one_param_validator = validation_for(
        name             => '_check_one_from_epoch_param',
        name_is_optional => 1,
        params           => [ { type => t('Num') } ],
    );

    sub from_epoch {
        my $class = shift;
        my %p;
        if ( @_ == 1 && !is_HashRef( $_[0] ) ) {
            ( $p{epoch} ) = $one_param_validator->(@_);
        }
        else {
            %p = $named_validator->(@_);
        }

        my %args;

        # This does two things. First, if given a negative non-integer epoch,
        # it will round the epoch _down_ to the next second and then adjust
        # the nanoseconds to be positive. In other words, -0.5 corresponds to
        # a second of -1 and a nanosecond value of 500,000. Before this code
        # was implemented our handling of negative non-integer epochs was
        # quite broken, and would end up rounding some values up, so that -0.5
        # become 0.5 (which is obviously wrong!).
        #
        # Second, it rounds any decimal values to the nearest microsecond
        # (1E6). Here's what Christian Hansen, who wrote this patch, says:
        #
        #     Perl is typically compiled with NV as a double. A double with a
        #     significand precision of 53 bits can only represent a nanosecond
        #     epoch without loss of precision if the duration from zero epoch
        #     is less than ≈ ±104 days. With microseconds the duration is
        #     ±104,000 days, which is ≈ ±285 years.
        if ( int $p{epoch} != $p{epoch} ) {
            my ( $floor, $nano, $second );

            $floor  = $nano = fmod( $p{epoch}, 1.0 );
            $second = floor( $p{epoch} - $floor );
            if ( $nano < 0 ) {
                $nano += 1;
            }
            $p{epoch}         = $second + floor( $floor - $nano );
            $args{nanosecond} = floor( $nano * 1E6 + 0.5 ) * 1E3;
        }

        # Note, for very large negative values this may give a
        # blatantly wrong answer.
        @args{qw( second minute hour day month year )}
            = ( gmtime( $p{epoch} ) )[ 0 .. 5 ];
        $args{year} += 1900;
        $args{month}++;

        my $self = $class->_new( %p, %args, time_zone => 'UTC' );

        $self->_maybe_future_dst_warning( $self->year, $p{time_zone} );

        $self->set_time_zone( $p{time_zone} ) if exists $p{time_zone};

        return $self;
    }
}

sub now {
    my $class = shift;
    return $class->from_epoch( epoch => $class->_core_time, @_ );
}

sub _maybe_future_dst_warning {
    shift;
    my $year = shift;
    my $tz   = shift;

    return unless $year >= 5000 && $tz;

    my $tz_name = ref $tz ? $tz->name : $tz;
    return if $tz_name eq 'floating' || $tz_name eq 'UTC';

    warnings::warnif(
        "You are creating a DateTime object with a far future year ($year) and a time zone ($tz_name)."
            . ' If the time zone you specified has future DST changes this will be very slow.'
    );
}

# use scalar time in case someone's loaded Time::Piece
sub _core_time {
    return scalar time;
}

sub today { shift->now(@_)->truncate( to => 'day' ) }

{
    my $validator = validation_for(
        name             => '_check_from_object_params',
        name_is_optional => 1,
        params           => {
            object => { type => t('ConvertibleObject') },
            locale => {
                type     => t('Locale'),
                optional => 1,
            },
            formatter => {
                type     => t('Formatter'),
                optional => 1,
            },
        },
    );

    sub from_object {
        my $class = shift;
        my %p     = $validator->(@_);

        my $object = delete $p{object};

        if ( $object->isa('DateTime::Infinite') ) {
            return $object->clone;
        }

        my ( $rd_days, $rd_secs, $rd_nanosecs ) = $object->utc_rd_values;

        # A kludge because until all calendars are updated to return all
        # three values, $rd_nanosecs could be undef
        $rd_nanosecs ||= 0;

        # This is a big hack to let _seconds_as_components operate naively
        # on the given value. If the object _is_ on a leap second, we'll
        # add that to the generated seconds value later.
        my $leap_seconds = 0;
        if (   $object->can('time_zone')
            && !$object->time_zone->is_floating
            && $rd_secs > 86399
            && $rd_secs <= $class->_day_length($rd_days) ) {
            $leap_seconds = $rd_secs - 86399;
            $rd_secs -= $leap_seconds;
        }

        my %args;
        @args{qw( year month day )} = $class->_rd2ymd($rd_days);
        @args{qw( hour minute second )}
            = $class->_seconds_as_components($rd_secs);
        $args{nanosecond} = $rd_nanosecs;

        $args{second} += $leap_seconds;

        my $new = $class->new( %p, %args, time_zone => 'UTC' );

        if ( $object->can('time_zone') ) {
            $new->set_time_zone( $object->time_zone );
        }
        else {
            $new->set_time_zone( $class->_default_time_zone );
        }

        return $new;
    }
}

{
    my $validator = validation_for(
        name             => '_check_last_day_of_month_params',
        name_is_optional => 1,
        params           => {
            year  => { type => t('Year') },
            month => { type => t('Month') },
            day   => {
                type    => t('DayOfMonth'),
                default => 1,
            },
            hour => {
                type    => t('Hour'),
                default => 0,
            },
            minute => {
                type    => t('Minute'),
                default => 0,
            },
            second => {
                type    => t('Second'),
                default => 0,
            },
            nanosecond => {
                type    => t('Nanosecond'),
                default => 0,
            },
            locale => {
                type     => t('Locale'),
                optional => 1,
            },
            formatter => {
                type     => t('Formatter'),
                optional => 1,
            },
            time_zone => {
                type     => t('TimeZone'),
                optional => 1,
            },
        },
    );

    sub last_day_of_month {
        my $class = shift;
        my %p     = $validator->(@_);

        my $day = $class->_month_length( $p{year}, $p{month} );

        return $class->_new( %p, day => $day );
    }
}

sub _month_length {
    return (
          $_[0]->_is_leap_year( $_[1] )
        ? $LeapYearMonthLengths[ $_[2] - 1 ]
        : $MonthLengths[ $_[2] - 1 ]
    );
}

{
    my $validator = validation_for(
        name             => '_check_from_day_of_year_params',
        name_is_optional => 1,
        params           => {
            year        => { type => t('Year') },
            day_of_year => { type => t('DayOfYear') },
            hour        => {
                type    => t('Hour'),
                default => 0,
            },
            minute => {
                type    => t('Minute'),
                default => 0,
            },
            second => {
                type    => t('Second'),
                default => 0,
            },
            nanosecond => {
                type    => t('Nanosecond'),
                default => 0,
            },
            locale => {
                type     => t('Locale'),
                optional => 1,
            },
            formatter => {
                type     => t('Formatter'),
                optional => 1,
            },
            time_zone => {
                type     => t('TimeZone'),
                optional => 1,
            },
        },
    );

    sub from_day_of_year {
        my $class = shift;
        my %p     = $validator->(@_);

        Carp::croak("$p{year} is not a leap year.\n")
            if $p{day_of_year} == 366 && !$class->_is_leap_year( $p{year} );

        my $month = 1;
        my $day   = delete $p{day_of_year};

        if ( $day > 31 ) {
            my $length = $class->_month_length( $p{year}, $month );

            while ( $day > $length ) {
                $day -= $length;
                $month++;
                $length = $class->_month_length( $p{year}, $month );
            }
        }

        return $class->_new(
            %p,
            month => $month,
            day   => $day,
        );
    }
}

sub formatter { $_[0]->{formatter} }

sub clone { bless { %{ $_[0] } }, ref $_[0] }

sub year {
    Carp::carp('year() is a read-only accessor') if @_ > 1;
    return $_[0]->{local_c}{year};
}

sub ce_year {
    $_[0]->{local_c}{year} <= 0
        ? $_[0]->{local_c}{year} - 1
        : $_[0]->{local_c}{year};
}

sub era_name { $_[0]->{locale}->era_wide->[ $_[0]->_era_index ] }

sub era_abbr { $_[0]->{locale}->era_abbreviated->[ $_[0]->_era_index ] }

# deprecated
*era = \&era_abbr;

sub _era_index { $_[0]->{local_c}{year} <= 0 ? 0 : 1 }

sub christian_era { $_[0]->ce_year > 0 ? 'AD' : 'BC' }
sub secular_era   { $_[0]->ce_year > 0 ? 'CE' : 'BCE' }

sub year_with_era           { ( abs $_[0]->ce_year ) . $_[0]->era_abbr }
sub year_with_christian_era { ( abs $_[0]->ce_year ) . $_[0]->christian_era }
sub year_with_secular_era   { ( abs $_[0]->ce_year ) . $_[0]->secular_era }

sub month {
    Carp::carp('month() is a read-only accessor') if @_ > 1;
    return $_[0]->{local_c}{month};
}
*mon = \&month;

sub month_0 { $_[0]->{local_c}{month} - 1 }
*mon_0 = \&month_0;

sub month_name { $_[0]->{locale}->month_format_wide->[ $_[0]->month_0 ] }

sub month_abbr {
    $_[0]->{locale}->month_format_abbreviated->[ $_[0]->month_0 ];
}

sub day_of_month {
    Carp::carp('day_of_month() is a read-only accessor') if @_ > 1;
    $_[0]->{local_c}{day};
}
*day  = \&day_of_month;
*mday = \&day_of_month;

sub weekday_of_month { use integer; ( ( $_[0]->day - 1 ) / 7 ) + 1 }

sub quarter { $_[0]->{local_c}{quarter} }

sub quarter_name {
    $_[0]->{locale}->quarter_format_wide->[ $_[0]->quarter_0 ];
}

sub quarter_abbr {
    $_[0]->{locale}->quarter_format_abbreviated->[ $_[0]->quarter_0 ];
}

sub quarter_0 { $_[0]->{local_c}{quarter} - 1 }

sub day_of_month_0 { $_[0]->{local_c}{day} - 1 }
*day_0  = \&day_of_month_0;
*mday_0 = \&day_of_month_0;

sub day_of_week { $_[0]->{local_c}{day_of_week} }
*wday = \&day_of_week;
*dow  = \&day_of_week;

sub day_of_week_0 { $_[0]->{local_c}{day_of_week} - 1 }
*wday_0 = \&day_of_week_0;
*dow_0  = \&day_of_week_0;

sub local_day_of_week {
    my $self = shift;
    return 1
        + ( $self->day_of_week - $self->{locale}->first_day_of_week ) % 7;
}

sub day_name { $_[0]->{locale}->day_format_wide->[ $_[0]->day_of_week_0 ] }

sub day_abbr {
    $_[0]->{locale}->day_format_abbreviated->[ $_[0]->day_of_week_0 ];
}

sub day_of_quarter { $_[0]->{local_c}{day_of_quarter} }
*doq = \&day_of_quarter;

sub day_of_quarter_0 { $_[0]->day_of_quarter - 1 }
*doq_0 = \&day_of_quarter_0;

sub day_of_year { $_[0]->{local_c}{day_of_year} }
*doy = \&day_of_year;

sub day_of_year_0 { $_[0]->{local_c}{day_of_year} - 1 }
*doy_0 = \&day_of_year_0;

sub am_or_pm {
    $_[0]->{locale}->am_pm_abbreviated->[ $_[0]->hour < 12 ? 0 : 1 ];
}

sub ymd {
    my ( $self, $sep ) = @_;
    $sep = '-' unless defined $sep;

    return sprintf(
        '%0.4d%s%0.2d%s%0.2d',
        $self->year,             $sep,
        $self->{local_c}{month}, $sep,
        $self->{local_c}{day}
    );
}
*date = sub { shift->ymd(@_) };

sub mdy {
    my ( $self, $sep ) = @_;
    $sep = '-' unless defined $sep;

    return sprintf(
        '%0.2d%s%0.2d%s%0.4d',
        $self->{local_c}{month}, $sep,
        $self->{local_c}{day},   $sep,
        $self->year
    );
}

sub dmy {
    my ( $self, $sep ) = @_;
    $sep = '-' unless defined $sep;

    return sprintf(
        '%0.2d%s%0.2d%s%0.4d',
        $self->{local_c}{day},   $sep,
        $self->{local_c}{month}, $sep,
        $self->year
    );
}

sub hour {
    Carp::carp('hour() is a read-only accessor') if @_ > 1;
    return $_[0]->{local_c}{hour};
}
sub hour_1 { $_[0]->{local_c}{hour} == 0 ? 24 : $_[0]->{local_c}{hour} }

sub hour_12   { my $h = $_[0]->hour % 12; return $h ? $h : 12 }
sub hour_12_0 { $_[0]->hour % 12 }

sub minute {
    Carp::carp('minute() is a read-only accessor') if @_ > 1;
    return $_[0]->{local_c}{minute};
}
*min = \&minute;

sub second {
    Carp::carp('second() is a read-only accessor') if @_ > 1;
    return $_[0]->{local_c}{second};
}
*sec = \&second;

sub fractional_second { $_[0]->second + $_[0]->nanosecond / MAX_NANOSECONDS }

sub nanosecond {
    Carp::carp('nanosecond() is a read-only accessor') if @_ > 1;
    return $_[0]->{rd_nanosecs};
}

sub millisecond { floor( $_[0]->{rd_nanosecs} / 1000000 ) }

sub microsecond { floor( $_[0]->{rd_nanosecs} / 1000 ) }

sub leap_seconds {
    my $self = shift;

    return 0 if $self->{tz}->is_floating;

    return $self->_accumulated_leap_seconds( $self->{utc_rd_days} );
}

sub stringify {
    my $self = shift;

    return $self->iso8601 unless $self->{formatter};
    return $self->{formatter}->format_datetime($self);
}

sub hms {
    my ( $self, $sep ) = @_;
    $sep = ':' unless defined $sep;

    return sprintf(
        '%0.2d%s%0.2d%s%0.2d',
        $self->{local_c}{hour},   $sep,
        $self->{local_c}{minute}, $sep,
        $self->{local_c}{second}
    );
}

# don't want to override CORE::time()
*DateTime::time = sub { shift->hms(@_) };

sub iso8601 { $_[0]->datetime('T') }

sub rfc3339 {
    my $self = shift;

    return $self->datetime('T')
        if $self->{tz}->is_floating;

    my $secs = $self->offset;
    my $offset
        = $secs
        ? DateTime::TimeZone->offset_as_string( $secs, q{:} )
        : 'Z';

    return $self->datetime('T') . $offset;
}

sub datetime {
    my ( $self, $sep ) = @_;
    $sep = 'T' unless defined $sep;
    return join $sep, $self->ymd('-'), $self->hms(':');
}

sub is_leap_year { $_[0]->_is_leap_year( $_[0]->year ) }

sub month_length {
    $_[0]->_month_length( $_[0]->year, $_[0]->month );
}

sub quarter_length {
    return (
          $_[0]->_is_leap_year( $_[0]->year )
        ? $LeapYearQuarterLengths[ $_[0]->quarter - 1 ]
        : $QuarterLengths[ $_[0]->quarter - 1 ]
    );
}

sub year_length {
    $_[0]->_is_leap_year( $_[0]->year ) ? 366 : 365;
}

sub is_last_day_of_month {
    $_[0]->day == $_[0]->_month_length( $_[0]->year, $_[0]->month );
}

sub is_last_day_of_quarter {
    $_[0]->day_of_quarter == $_[0]->quarter_length;
}

sub is_last_day_of_year {
    $_[0]->day_of_year == $_[0]->year_length;
}

sub week {
    my $self = shift;

    $self->{utc_c}{week_year} ||= $self->_week_values;

    return @{ $self->{utc_c}{week_year} }[ 0, 1 ];
}

# This algorithm comes from
# https://en.wikipedia.org/wiki/ISO_week_date#Calculating_the_week_number_of_a_given_date
sub _week_values {
    my $self = shift;

    my $week
        = int( ( ( $self->day_of_year - $self->day_of_week ) + 10 ) / 7 );

    my $year = $self->year;
    if ( $week == 0 ) {
        $year--;
        return [ $year, $self->_weeks_in_year($year) ];
    }
    elsif ( $week == 53 && $self->_weeks_in_year($year) == 52 ) {
        return [ $year + 1, 1 ];
    }

    return [ $year, $week ];
}

sub _weeks_in_year {
    my $self = shift;
    my $year = shift;

    my $dow = $self->_ymd2rd( $year, 1, 1 ) % 7;

    # Years starting with a Thursday and leap years starting with a Wednesday
    # have 53 weeks.
    return ( $dow == 4 || ( $dow == 3 && $self->_is_leap_year($year) ) )
        ? 53
        : 52;
}

sub week_year   { ( $_[0]->week )[0] }
sub week_number { ( $_[0]->week )[1] }

# ISO says that the first week of a year is the first week containing
# a Thursday. Extending that says that the first week of the month is
# the first week containing a Thursday. ICU agrees.
sub week_of_month {
    my $self = shift;
    my $thu  = $self->day + 4 - $self->day_of_week;
    return int( ( $thu + 6 ) / 7 );
}

sub time_zone {
    Carp::carp('time_zone() is a read-only accessor') if @_ > 1;
    return $_[0]->{tz};
}

sub offset { $_[0]->{tz}->offset_for_datetime( $_[0] ) }

sub _offset_for_local_datetime {
    $_[0]->{tz}->offset_for_local_datetime( $_[0] );
}

sub is_dst { $_[0]->{tz}->is_dst_for_datetime( $_[0] ) }

sub time_zone_long_name  { $_[0]->{tz}->name }
sub time_zone_short_name { $_[0]->{tz}->short_name_for_datetime( $_[0] ) }

sub locale {
    Carp::carp('locale() is a read-only accessor') if @_ > 1;
    return $_[0]->{locale};
}

sub utc_rd_values {
    @{ $_[0] }{ 'utc_rd_days', 'utc_rd_secs', 'rd_nanosecs' };
}

sub local_rd_values {
    @{ $_[0] }{ 'local_rd_days', 'local_rd_secs', 'rd_nanosecs' };
}

# NOTE: no nanoseconds, no leap seconds
sub utc_rd_as_seconds {
    ( $_[0]->{utc_rd_days} * SECONDS_PER_DAY ) + $_[0]->{utc_rd_secs};
}

# NOTE: no nanoseconds, no leap seconds
sub local_rd_as_seconds {
    ( $_[0]->{local_rd_days} * SECONDS_PER_DAY ) + $_[0]->{local_rd_secs};
}

# RD 1 is MJD 678,576 - a simple offset
sub mjd {
    my $self = shift;

    my $mjd = $self->{utc_rd_days} - 678_576;

    my $day_length = $self->_day_length( $self->{utc_rd_days} );

    return (  $mjd
            + ( $self->{utc_rd_secs} / $day_length )
            + ( $self->{rd_nanosecs} / $day_length / MAX_NANOSECONDS ) );
}

sub jd { $_[0]->mjd + 2_400_000.5 }

{
    my %strftime_patterns = (
        'a' => sub { $_[0]->day_abbr },
        'A' => sub { $_[0]->day_name },
        'b' => sub { $_[0]->month_abbr },
        'B' => sub { $_[0]->month_name },
        'c' => sub {
            $_[0]->format_cldr( $_[0]->{locale}->datetime_format_default );
        },
        'C' => sub { int( $_[0]->year / 100 ) },
        'd' => sub { sprintf( '%02d', $_[0]->day_of_month ) },
        'D' => sub { $_[0]->strftime('%m/%d/%y') },
        'e' => sub { sprintf( '%2d', $_[0]->day_of_month ) },
        'F' => sub { $_[0]->strftime('%Y-%m-%d') },
        'g' => sub { substr( $_[0]->week_year, -2 ) },
        'G' => sub { $_[0]->week_year },
        'H' => sub { sprintf( '%02d', $_[0]->hour ) },
        'I' => sub { sprintf( '%02d', $_[0]->hour_12 ) },
        'j' => sub { sprintf( '%03d', $_[0]->day_of_year ) },
        'k' => sub { sprintf( '%2d',  $_[0]->hour ) },
        'l' => sub { sprintf( '%2d',  $_[0]->hour_12 ) },
        'm' => sub { sprintf( '%02d', $_[0]->month ) },
        'M' => sub { sprintf( '%02d', $_[0]->minute ) },
        'n' => sub {"\n"},                   # should this be OS-sensitive?
        'N' => \&_format_nanosecs,
        'p' => sub { $_[0]->am_or_pm },
        'P' => sub { lc $_[0]->am_or_pm },
        'r' => sub { $_[0]->strftime('%I:%M:%S %p') },
        'R' => sub { $_[0]->strftime('%H:%M') },
        's' => sub { $_[0]->epoch },
        'S' => sub { sprintf( '%02d', $_[0]->second ) },
        't' => sub {"\t"},
        'T' => sub { $_[0]->strftime('%H:%M:%S') },
        'u' => sub { $_[0]->day_of_week },
        'U' => sub {
            my $sun = $_[0]->day_of_year - ( $_[0]->day_of_week + 7 ) % 7;
            return sprintf( '%02d', int( ( $sun + 6 ) / 7 ) );
        },
        'V' => sub { sprintf( '%02d', $_[0]->week_number ) },
        'w' => sub {
            my $dow = $_[0]->day_of_week;
            return $dow % 7;
        },
        'W' => sub {
            my $mon = $_[0]->day_of_year - ( $_[0]->day_of_week + 6 ) % 7;
            return sprintf( '%02d', int( ( $mon + 6 ) / 7 ) );
        },
        'x' => sub {
            $_[0]->format_cldr( $_[0]->{locale}->date_format_default );
        },
        'X' => sub {
            $_[0]->format_cldr( $_[0]->{locale}->time_format_default );
        },
        'y' => sub { sprintf( '%02d', substr( $_[0]->year, -2 ) ) },
        'Y' => sub { return $_[0]->year },
        'z' => sub { DateTime::TimeZone->offset_as_string( $_[0]->offset ) },
        'Z' => sub { $_[0]->{tz}->short_name_for_datetime( $_[0] ) },
        '%' => sub {'%'},
    );

    $strftime_patterns{h} = $strftime_patterns{b};

    sub strftime {
        my $self = shift;

        # make a copy or caller's scalars get munged
        my @patterns = @_;

        my @r;
        for my $p (@patterns) {
            $p =~ s/
                    (?:
                      %\{(\w+)\}       # method name like %{day_name}
                      |
                      %([%a-zA-Z])     # single character specifier like %d
                      |
                      %(\d+)N          # special case for %N
                    )
                   /
                    ( $1
                      ? ( $self->can($1) ? $self->$1() : "\%{$1}" )
                      : $2
                      ? ( $strftime_patterns{$2} ? $strftime_patterns{$2}->($self) : "\%$2" )
                      : $3
                      ? $strftime_patterns{N}->($self, $3)
                      : ''  # this won't happen
                    )
                   /sgex;

            return $p unless wantarray;

            push @r, $p;
        }

        return @r;
    }
}

{

    # It's an array because the order in which the regexes are checked
    # is important. These patterns are similar to the ones Java uses,
    # but not quite the same. See
    # http://www.unicode.org/reports/tr35/tr35-9.html#Date_Format_Patterns.
    my @patterns = (
        qr/GGGGG/ =>
            sub { $_[0]->{locale}->era_narrow->[ $_[0]->_era_index ] },
        qr/GGGG/   => 'era_name',
        qr/G{1,3}/ => 'era_abbr',

        qr/(y{3,5})/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->year ) },

        # yy is a weird special case, where it must be exactly 2 digits
        qr/yy/ => sub {
            my $year = $_[0]->year;
            my $y2   = length $year > 2 ? substr( $year, -2, 2 ) : $year;
            $y2 *= -1 if $year < 0;
            $_[0]->_zero_padded_number( 'yy', $y2 );
        },
        qr/y/    => 'year',
        qr/(u+)/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->year ) },
        qr/(Y+)/ =>
            sub { $_[0]->_zero_padded_number( $1, $_[0]->week_year ) },

        qr/QQQQ/  => 'quarter_name',
        qr/QQQ/   => 'quarter_abbr',
        qr/(QQ?)/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->quarter ) },

        qr/qqqq/ => sub {
            $_[0]->{locale}->quarter_stand_alone_wide->[ $_[0]->quarter_0 ];
        },
        qr/qqq/ => sub {
            $_[0]->{locale}
                ->quarter_stand_alone_abbreviated->[ $_[0]->quarter_0 ];
        },
        qr/(qq?)/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->quarter ) },

        qr/MMMMM/ =>
            sub { $_[0]->{locale}->month_format_narrow->[ $_[0]->month_0 ] },
        qr/MMMM/  => 'month_name',
        qr/MMM/   => 'month_abbr',
        qr/(MM?)/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->month ) },

        qr/LLLLL/ => sub {
            $_[0]->{locale}->month_stand_alone_narrow->[ $_[0]->month_0 ];
        },
        qr/LLLL/ => sub {
            $_[0]->{locale}->month_stand_alone_wide->[ $_[0]->month_0 ];
        },
        qr/LLL/ => sub {
            $_[0]->{locale}
                ->month_stand_alone_abbreviated->[ $_[0]->month_0 ];
        },
        qr/(LL?)/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->month ) },

        qr/(ww?)/ =>
            sub { $_[0]->_zero_padded_number( $1, $_[0]->week_number ) },
        qr/W/ => 'week_of_month',

        qr/(dd?)/ =>
            sub { $_[0]->_zero_padded_number( $1, $_[0]->day_of_month ) },
        qr/(D{1,3})/ =>
            sub { $_[0]->_zero_padded_number( $1, $_[0]->day_of_year ) },

        qr/F/    => 'weekday_of_month',
        qr/(g+)/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->mjd ) },

        qr/EEEEE/ => sub {
            $_[0]->{locale}->day_format_narrow->[ $_[0]->day_of_week_0 ];
        },
        qr/EEEE/   => 'day_name',
        qr/E{1,3}/ => 'day_abbr',

        qr/eeeee/ => sub {
            $_[0]->{locale}->day_format_narrow->[ $_[0]->day_of_week_0 ];
        },
        qr/eeee/  => 'day_name',
        qr/eee/   => 'day_abbr',
        qr/(ee?)/ => sub {
            $_[0]->_zero_padded_number( $1, $_[0]->local_day_of_week );
        },

        qr/ccccc/ => sub {
            $_[0]->{locale}->day_stand_alone_narrow->[ $_[0]->day_of_week_0 ];
        },
        qr/cccc/ => sub {
            $_[0]->{locale}->day_stand_alone_wide->[ $_[0]->day_of_week_0 ];
        },
        qr/ccc/ => sub {
            $_[0]->{locale}
                ->day_stand_alone_abbreviated->[ $_[0]->day_of_week_0 ];
        },
        qr/(cc?)/ =>
            sub { $_[0]->_zero_padded_number( $1, $_[0]->day_of_week ) },

        qr/a/ => 'am_or_pm',

        qr/(hh?)/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->hour_12 ) },
        qr/(HH?)/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->hour ) },
        qr/(KK?)/ =>
            sub { $_[0]->_zero_padded_number( $1, $_[0]->hour_12_0 ) },
        qr/(kk?)/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->hour_1 ) },
        qr/(jj?)/ => sub {
            my $h
                = $_[0]->{locale}->prefers_24_hour_time
                ? $_[0]->hour
                : $_[0]->hour_12;
            $_[0]->_zero_padded_number( $1, $h );
        },

        qr/(mm?)/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->minute ) },

        qr/(ss?)/ => sub { $_[0]->_zero_padded_number( $1, $_[0]->second ) },

        # The LDML spec is not 100% clear on how to truncate this field, but
        # this way seems as good as anything.
        qr/(S+)/ => sub { $_[0]->_format_nanosecs( length($1) ) },
        qr/A+/   =>
            sub { ( $_[0]->{local_rd_secs} * 1000 ) + $_[0]->millisecond },

        qr/zzzz/   => 'time_zone_long_name',
        qr/z{1,3}/ => 'time_zone_short_name',
        qr/ZZZZZ/  => sub {
            DateTime::TimeZone->offset_as_string( $_[0]->offset, q{:} );
        },
        qr/ZZZZ/ => sub {
            $_[0]->time_zone_short_name
                . DateTime::TimeZone->offset_as_string( $_[0]->offset );
        },
        qr/Z{1,3}/ =>
            sub { DateTime::TimeZone->offset_as_string( $_[0]->offset ) },
        qr/vvvv/   => 'time_zone_long_name',
        qr/v{1,3}/ => 'time_zone_short_name',
        qr/VVVV/   => 'time_zone_long_name',
        qr/V{1,3}/ => 'time_zone_short_name',
    );

    sub _zero_padded_number {
        my $self = shift;
        my $size = length shift;
        my $val  = shift;

        return sprintf( "%0${size}d", $val );
    }

    sub format_cldr {
        my $self = shift;

        # make a copy or caller's scalars get munged
        my @p = @_;

        my @r;
        for my $p (@p) {
            $p =~ s/\G
                    (?:
                      '((?:[^']|'')*)' # quote escaped bit of text
                                       # it needs to end with one
                                       # quote not followed by
                                       # another
                      |
                      (([a-zA-Z])\3*)     # could be a pattern
                      |
                      (.)                 # anything else
                    )
                   /
                    defined $1
                    ? $1
                    : defined $2
                    ? $self->_cldr_pattern($2)
                    : defined $4
                    ? $4
                    : undef # should never get here
                   /sgex;

            $p =~ s/\'\'/\'/g;

            return $p unless wantarray;

            push @r, $p;
        }

        return @r;
    }

    sub _cldr_pattern {
        my $self    = shift;
        my $pattern = shift;

        ## no critic (ControlStructures::ProhibitCStyleForLoops)
        for ( my $i = 0; $i < @patterns; $i += 2 ) {
            if ( $pattern =~ /$patterns[$i]/ ) {
                my $sub = $patterns[ $i + 1 ];

                return $self->$sub();
            }
        }

        return $pattern;
    }
}

sub _format_nanosecs {
    my $self      = shift;
    my $precision = @_ ? shift : 9;

    my $exponent     = 9 - $precision;
    my $formatted_ns = floor(
        (
              $exponent < 0
            ? $self->{rd_nanosecs} * 10**-$exponent
            : $self->{rd_nanosecs} / 10**$exponent
        )
    );

    return sprintf(
        '%0' . $precision . 'u',
        $formatted_ns
    );
}

sub epoch {
    my $self = shift;

    return $self->{utc_c}{epoch}
        if exists $self->{utc_c}{epoch};

    return $self->{utc_c}{epoch}
        = ( $self->{utc_rd_days} - 719163 ) * SECONDS_PER_DAY
        + $self->{utc_rd_secs};
}

sub hires_epoch {
    my $self = shift;

    my $epoch = $self->epoch;

    return undef unless defined $epoch;

    my $nano = $self->{rd_nanosecs} / MAX_NANOSECONDS;

    return $epoch + $nano;
}

sub is_finite   {1}
sub is_infinite {0}

# added for benefit of DateTime::TimeZone
sub utc_year { $_[0]->{utc_year} }

# returns a result that is relative to the first datetime
sub subtract_datetime {
    my $dt1 = shift;
    my $dt2 = shift;

    $dt2 = $dt2->clone->set_time_zone( $dt1->time_zone )
        unless $dt1->time_zone eq $dt2->time_zone;

    # We only want a negative duration if $dt2 > $dt1 ($self)
    my ( $bigger, $smaller, $negative ) = (
        $dt1 >= $dt2
        ? ( $dt1, $dt2, 0 )
        : ( $dt2, $dt1, 1 )
    );

    my $is_floating = $dt1->time_zone->is_floating
        && $dt2->time_zone->is_floating;

    my $minute_length = 60;
    unless ($is_floating) {
        my ( $utc_rd_days, $utc_rd_secs ) = $smaller->utc_rd_values;

        if ( $utc_rd_secs >= 86340 && !$is_floating ) {

            # If the smaller of the two datetimes occurs in the last
            # UTC minute of the UTC day, then that minute may not be
            # 60 seconds long. If we need to subtract a minute from
            # the larger datetime's minutes count in order to adjust
            # the seconds difference to be positive, we need to know
            # how long that minute was. If one of the datetimes is
            # floating, we just assume a minute is 60 seconds.

            $minute_length = $dt1->_day_length($utc_rd_days) - 86340;
        }
    }

    # This is a gross hack that basically figures out if the bigger of
    # the two datetimes is the day of a DST change. If it's a 23 hour
    # day (switching _to_ DST) then we subtract 60 minutes from the
    # local time. If it's a 25 hour day then we add 60 minutes to the
    # local time.
    #
    # This produces the most "intuitive" results, though there are
    # still reversibility problems with the resultant duration.
    #
    # However, if the two objects are on the same (local) date, and we
    # are not crossing a DST change, we don't want to invoke the hack
    # - see 38local-subtract.t
    my $bigger_min = $bigger->hour * 60 + $bigger->minute;
    if (   $bigger->time_zone->has_dst_changes
        && $bigger->is_dst != $smaller->is_dst ) {

        $bigger_min -= 60

            # it's a 23 hour (local) day
            if (
            $bigger->is_dst
            && do {
                my $prev_day = try { $bigger->clone->subtract( days => 1 ) };
                $prev_day && !$prev_day->is_dst ? 1 : 0;
            }
            );

        $bigger_min += 60

            # it's a 25 hour (local) day
            if (
            !$bigger->is_dst
            && do {
                my $prev_day = try { $bigger->clone->subtract( days => 1 ) };
                $prev_day && $prev_day->is_dst ? 1 : 0;
            }
            );
    }

    my ( $months, $days, $minutes, $seconds, $nanoseconds )
        = $dt1->_adjust_for_positive_difference(
        $bigger->year * 12 + $bigger->month,
        $smaller->year * 12 + $smaller->month,

        $bigger->day, $smaller->day,

        $bigger_min, $smaller->hour * 60 + $smaller->minute,

        $bigger->second, $smaller->second,

        $bigger->nanosecond, $smaller->nanosecond,

        $minute_length,

        # XXX - using the smaller as the month length is
        # somewhat arbitrary, we could also use the bigger -
        # either way we have reversibility problems
        $dt1->_month_length( $smaller->year, $smaller->month ),
        );

    if ($negative) {
        for ( $months, $days, $minutes, $seconds, $nanoseconds ) {

            # Some versions of Perl can end up with -0 if we do "0 * -1"!!
            $_ *= -1 if $_;
        }
    }

    return $dt1->duration_class->new(
        months      => $months,
        days        => $days,
        minutes     => $minutes,
        seconds     => $seconds,
        nanoseconds => $nanoseconds,
    );
}

## no critic (Subroutines::ProhibitManyArgs)
sub _adjust_for_positive_difference {
    my (
        $self,
        $month1, $month2,
        $day1,   $day2,
        $min1,   $min2,
        $sec1,   $sec2,
        $nano1,  $nano2,
        $minute_length,
        $month_length,
    ) = @_;

    if ( $nano1 < $nano2 ) {
        $sec1--;
        $nano1 += MAX_NANOSECONDS;
    }

    if ( $sec1 < $sec2 ) {
        $min1--;
        $sec1 += $minute_length;
    }

    # A day always has 24 * 60 minutes, though the minutes may vary in
    # length.
    if ( $min1 < $min2 ) {
        $day1--;
        $min1 += 24 * 60;
    }

    if ( $day1 < $day2 ) {
        $month1--;
        $day1 += $month_length;
    }

    return (
        $month1 - $month2,
        $day1 - $day2,
        $min1 - $min2,
        $sec1 - $sec2,
        $nano1 - $nano2,
    );
}

sub subtract_datetime_absolute {
    my $self = shift;
    my $dt   = shift;

    my $utc_rd_secs1 = $self->utc_rd_as_seconds;
    $utc_rd_secs1 += $self->_accumulated_leap_seconds( $self->{utc_rd_days} )
        if !$self->time_zone->is_floating;

    my $utc_rd_secs2 = $dt->utc_rd_as_seconds;
    $utc_rd_secs2 += $self->_accumulated_leap_seconds( $dt->{utc_rd_days} )
        if !$dt->time_zone->is_floating;

    my $seconds     = $utc_rd_secs1 - $utc_rd_secs2;
    my $nanoseconds = $self->nanosecond - $dt->nanosecond;

    if ( $nanoseconds < 0 ) {
        $seconds--;
        $nanoseconds += MAX_NANOSECONDS;
    }

    return $self->duration_class->new(
        seconds     => $seconds,
        nanoseconds => $nanoseconds,
    );
}

sub delta_md {
    my $self = shift;
    my $dt   = shift;

    my ( $smaller, $bigger ) = sort $self, $dt;

    my ( $months, $days, undef, undef, undef )
        = $dt->_adjust_for_positive_difference(
        $bigger->year * 12 + $bigger->month,
        $smaller->year * 12 + $smaller->month,

        $bigger->day, $smaller->day,

        0, 0,

        0, 0,

        0, 0,

        60,

        $smaller->_month_length( $smaller->year, $smaller->month ),
        );

    return $self->duration_class->new(
        months => $months,
        days   => $days
    );
}

sub delta_days {
    my $self = shift;
    my $dt   = shift;

    my $days
        = abs( ( $self->local_rd_values )[0] - ( $dt->local_rd_values )[0] );

    $self->duration_class->new( days => $days );
}

sub delta_ms {
    my $self = shift;
    my $dt   = shift;

    my ( $smaller, $greater ) = sort $self, $dt;

    my $days = int( $greater->jd - $smaller->jd );

    my $dur = $greater->subtract_datetime($smaller);

    my %p;
    $p{hours}   = $dur->hours + ( $days * 24 );
    $p{minutes} = $dur->minutes;
    $p{seconds} = $dur->seconds;

    return $self->duration_class->new(%p);
}

sub _add_overload {
    my ( $dt, $dur, $reversed ) = @_;

    if ($reversed) {
        ( $dur, $dt ) = ( $dt, $dur );
    }

    unless ( DateTime::Helpers::isa( $dur, 'DateTime::Duration' ) ) {
        my $class     = ref $dt;
        my $dt_string = overload::StrVal($dt);

        Carp::croak( "Cannot add $dur to a $class object ($dt_string).\n"
                . ' Only a DateTime::Duration object can '
                . " be added to a $class object." );
    }

    return $dt->clone->add_duration($dur);
}

sub _subtract_overload {
    my ( $date1, $date2, $reversed ) = @_;

    if ($reversed) {
        ( $date2, $date1 ) = ( $date1, $date2 );
    }

    if ( DateTime::Helpers::isa( $date2, 'DateTime::Duration' ) ) {
        my $new = $date1->clone;
        $new->add_duration( $date2->inverse );
        return $new;
    }
    elsif ( DateTime::Helpers::isa( $date2, 'DateTime' ) ) {
        return $date1->subtract_datetime($date2);
    }
    else {
        my $class     = ref $date1;
        my $dt_string = overload::StrVal($date1);

        Carp::croak(
            "Cannot subtract $date2 from a $class object ($dt_string).\n"
                . ' Only a DateTime::Duration or DateTime object can '
                . " be subtracted from a $class object." );
    }
}

sub add {
    my $self = shift;

    return $self->add_duration( $self->_duration_object_from_args(@_) );
}

sub subtract {
    my $self = shift;

    my %eom;
    if ( @_ % 2 == 0 ) {
        my %p = @_;

        $eom{end_of_month} = delete $p{end_of_month}
            if exists $p{end_of_month};
    }

    my $dur = $self->_duration_object_from_args(@_)->inverse(%eom);

    return $self->add_duration($dur);
}

# Syntactic sugar for add and subtract: use a duration object if it's
# supplied, otherwise build a new one from the arguments.

sub _duration_object_from_args {
    my $self = shift;

    return $_[0]
        if @_ == 1 && blessed( $_[0] ) && $_[0]->isa( $self->duration_class );

    return $self->duration_class->new(@_);
}

sub subtract_duration { return $_[0]->add_duration( $_[1]->inverse ) }

{
    my $validator = validation_for(
        name             => '_check_add_duration_params',
        name_is_optional => 1,
        params           => [
            { type => t('Duration') },
        ],
    );

    ## no critic (Subroutines::ProhibitExcessComplexity)
    sub add_duration {
        my $self = shift;
        my ($dur) = $validator->(@_);

        # simple optimization
        return $self if $dur->is_zero;

        my %deltas = $dur->deltas;

        # This bit isn't quite right since DateTime::Infinite::Future -
        # infinite duration should NaN
        for my $val ( values %deltas ) {
            my $inf;
            if ( $val == INFINITY ) {
                $inf = DateTime::Infinite::Future->new;
            }
            elsif ( $val == NEG_INFINITY ) {
                $inf = DateTime::Infinite::Past->new;
            }

            if ($inf) {
                %$self = %$inf;
                bless $self, ref $inf;

                return $self;
            }
        }

        return $self if $self->is_infinite;

        my %orig = %{$self};
        try {
            $self->_add_duration($dur);
        }
        catch {
            %{$self} = %orig;
            die $_;
        };
    }
}

sub _add_duration {
    my $self = shift;
    my $dur  = shift;

    my %deltas = $dur->deltas;

    if ( $deltas{days} ) {
        $self->{local_rd_days} += $deltas{days};

        $self->{utc_year} += int( $deltas{days} / 365 ) + 1;
    }

    if ( $deltas{months} ) {

        # For preserve mode, if it is the last day of the month, make
        # it the 0th day of the following month (which then will
        # normalize back to the last day of the new month).
        my ( $y, $m, $d ) = (
              $dur->is_preserve_mode
            ? $self->_rd2ymd( $self->{local_rd_days} + 1 )
            : $self->_rd2ymd( $self->{local_rd_days} )
        );

        $d -= 1 if $dur->is_preserve_mode;

        if ( !$dur->is_wrap_mode && $d > 28 ) {

            # find the rd for the last day of our target month
            $self->{local_rd_days}
                = $self->_ymd2rd( $y, $m + $deltas{months} + 1, 0 );

            # what day of the month is it? (discard year and month)
            my $last_day
                = ( $self->_rd2ymd( $self->{local_rd_days} ) )[2];

            # if our original day was less than the last day,
            # use that instead
            $self->{local_rd_days} -= $last_day - $d if $last_day > $d;
        }
        else {
            $self->{local_rd_days}
                = $self->_ymd2rd( $y, $m + $deltas{months}, $d );
        }

        $self->{utc_year} += int( $deltas{months} / 12 ) + 1;
    }

    if ( $deltas{days} || $deltas{months} ) {
        $self->_calc_utc_rd;

        $self->_handle_offset_modifier( $self->second );
    }

    if ( $deltas{minutes} ) {
        $self->{utc_rd_secs} += $deltas{minutes} * 60;

        # This intentionally ignores leap seconds
        $self->_normalize_tai_seconds(
            $self->{utc_rd_days},
            $self->{utc_rd_secs}
        );
    }

    if ( $deltas{seconds} || $deltas{nanoseconds} ) {
        $self->{utc_rd_secs} += $deltas{seconds};

        if ( $deltas{nanoseconds} ) {
            $self->{rd_nanosecs} += $deltas{nanoseconds};
            $self->_normalize_nanoseconds(
                $self->{utc_rd_secs},
                $self->{rd_nanosecs}
            );
        }

        $self->_normalize_seconds;

        # This might be some big number much bigger than 60, but
        # that's ok (there are tests in 19leap_second.t to confirm
        # that)
        $self->_handle_offset_modifier( $self->second + $deltas{seconds} );
    }

    my $new = ( ref $self )->from_object(
        object => $self,
        locale => $self->{locale},
        ( $self->{formatter} ? ( formatter => $self->{formatter} ) : () ),
    );

    %$self = %$new;

    return $self;
}

sub _compare_overload {

    # note: $_[1]->compare( $_[0] ) is an error when $_[1] is not a
    # DateTime (such as the INFINITY value)

    return undef unless defined $_[1];

    return $_[2] ? -$_[0]->compare( $_[1] ) : $_[0]->compare( $_[1] );
}

sub _string_compare_overload {
    my ( $dt1, $dt2, $flip ) = @_;

    # One is a DateTime object, one isn't. Just stringify and compare.
    if ( !DateTime::Helpers::can( $dt2, 'utc_rd_values' ) ) {
        my $sign = $flip ? -1 : 1;
        return $sign * ( "$dt1" cmp "$dt2" );
    }
    else {
        my $meth = $dt1->can('_compare_overload');
        goto $meth;
    }
}

sub compare {
    shift->_compare( @_, 0 );
}

sub compare_ignore_floating {
    shift->_compare( @_, 1 );
}

sub _compare {
    my ( undef, $dt1, $dt2, $consistent ) = ref $_[0] ? ( undef, @_ ) : @_;

    return undef unless defined $dt2;

    if ( !ref $dt2 && ( $dt2 == INFINITY || $dt2 == NEG_INFINITY ) ) {
        return $dt1->{utc_rd_days} <=> $dt2;
    }

    unless ( DateTime::Helpers::can( $dt1, 'utc_rd_values' )
        && DateTime::Helpers::can( $dt2, 'utc_rd_values' ) ) {
        my $dt1_string = overload::StrVal($dt1);
        my $dt2_string = overload::StrVal($dt2);

        Carp::croak( 'A DateTime object can only be compared to'
                . " another DateTime object ($dt1_string, $dt2_string)." );
    }

    if (   !$consistent
        && DateTime::Helpers::can( $dt1, 'time_zone' )
        && DateTime::Helpers::can( $dt2, 'time_zone' ) ) {
        my $is_floating1 = $dt1->time_zone->is_floating;
        my $is_floating2 = $dt2->time_zone->is_floating;

        if ( $is_floating1 && !$is_floating2 ) {
            $dt1 = $dt1->clone->set_time_zone( $dt2->time_zone );
        }
        elsif ( $is_floating2 && !$is_floating1 ) {
            $dt2 = $dt2->clone->set_time_zone( $dt1->time_zone );
        }
    }

    my @dt1_components = $dt1->utc_rd_values;
    my @dt2_components = $dt2->utc_rd_values;

    for my $i ( 0 .. 2 ) {
        return $dt1_components[$i] <=> $dt2_components[$i]
            if $dt1_components[$i] != $dt2_components[$i];
    }

    return 0;
}

sub is_between {
    my $self  = shift;
    my $lower = shift;
    my $upper = shift;

    return $self->compare($lower) > 0 && $self->compare($upper) < 0;
}

sub _string_equals_overload {
    my ( $class, $dt1, $dt2 ) = ref $_[0] ? ( undef, @_ ) : @_;

    if ( !DateTime::Helpers::can( $dt2, 'utc_rd_values' ) ) {
        return "$dt1" eq "$dt2";
    }

    $class ||= ref $dt1;
    return !$class->compare( $dt1, $dt2 );
}

sub _string_not_equals_overload {
    return !_string_equals_overload(@_);
}

sub _normalize_nanoseconds {
    use integer;

    # seconds, nanoseconds
    if ( $_[2] < 0 ) {
        my $overflow = 1 + $_[2] / MAX_NANOSECONDS;
        $_[2] += $overflow * MAX_NANOSECONDS;
        $_[1] -= $overflow;
    }
    elsif ( $_[2] >= MAX_NANOSECONDS ) {
        my $overflow = $_[2] / MAX_NANOSECONDS;
        $_[2] -= $overflow * MAX_NANOSECONDS;
        $_[1] += $overflow;
    }
}

{
    my $validator = validation_for(
        name             => '_check_set_params',
        name_is_optional => 1,
        params           => {
            year => {
                type     => t('Year'),
                optional => 1,
            },
            month => {
                type     => t('Month'),
                optional => 1,
            },
            day => {
                type     => t('DayOfMonth'),
                optional => 1,
            },
            hour => {
                type     => t('Hour'),
                optional => 1,
            },
            minute => {
                type     => t('Minute'),
                optional => 1,
            },
            second => {
                type     => t('Second'),
                optional => 1,
            },
            nanosecond => {
                type     => t('Nanosecond'),
                optional => 1,
            },
            locale => {
                type     => t('Locale'),
                optional => 1,
            },
        },
    );

    ## no critic (NamingConventions::ProhibitAmbiguousNames)
    sub set {
        my $self = shift;
        my %p    = $validator->(@_);

        if ( $p{locale} ) {
            carp 'You passed a locale to the set() method.'
                . ' You should use set_locale() instead, as using set() may alter the local time near a DST boundary.';
        }

        my $new_dt = $self->_new_from_self(%p);

        %$self = %$new_dt;

        return $self;
    }
}

sub set_year       { $_[0]->set( year       => $_[1] ) }
sub set_month      { $_[0]->set( month      => $_[1] ) }
sub set_day        { $_[0]->set( day        => $_[1] ) }
sub set_hour       { $_[0]->set( hour       => $_[1] ) }
sub set_minute     { $_[0]->set( minute     => $_[1] ) }
sub set_second     { $_[0]->set( second     => $_[1] ) }
sub set_nanosecond { $_[0]->set( nanosecond => $_[1] ) }

# These two are special cased because ... if the local time is the hour of a
# DST change where the same local time occurs twice then passing it through
# _new() can actually change the underlying UTC time, which is bad.

{
    my $validator = validation_for(
        name             => '_check_set_locale_params',
        name_is_optional => 1,
        params           => [
            { type => t( 'Maybe', of => t('Locale') ) },
        ],
    );

    sub set_locale {
        my $self = shift;
        my ($locale) = $validator->(@_);

        $self->_set_locale($locale);

        return $self;
    }
}

{
    my $validator = validation_for(
        name             => '_check_set_formatter_params',
        name_is_optional => 1,
        params           => [
            { type => t( 'Maybe', of => t('Formatter') ) },
        ],
    );

    sub set_formatter {
        my $self = shift;
        my ($formatter) = $validator->(@_);

        $self->{formatter} = $formatter;

        return $self;
    }
}

{
    my %TruncateDefault = (
        month      => 1,
        day        => 1,
        hour       => 0,
        minute     => 0,
        second     => 0,
        nanosecond => 0,
    );

    my $validator = validation_for(
        name             => '_check_truncate_params',
        name_is_optional => 1,
        params           => {
            to => { type => t('TruncationLevel') },
        },
    );

    my $re = join '|', 'year', 'week', 'local_week', 'quarter',
        grep { $_ ne 'nanosecond' } keys %TruncateDefault;
    my $spec = { to => { regex => qr/^(?:$re)$/ } };

    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    sub truncate {
        my $self = shift;
        my %p    = $validator->(@_);

        my %new;
        if ( $p{to} eq 'week' || $p{to} eq 'local_week' ) {
            my $first_day_of_week
                = ( $p{to} eq 'local_week' )
                ? $self->{locale}->first_day_of_week
                : 1;

            my $day_diff = ( $self->day_of_week - $first_day_of_week ) % 7;

            if ($day_diff) {
                $self->add( days => -1 * $day_diff );
            }

            # This can fail if the truncate ends up giving us an invalid local
            # date time. If that happens we need to reverse the addition we
            # just did. See https://rt.cpan.org/Ticket/Display.html?id=93347.
            try {
                $self->truncate( to => 'day' );
            }
            catch {
                $self->add( days => $day_diff );
                die $_;
            };
        }
        elsif ( $p{to} eq 'quarter' ) {
            %new = (
                year       => $self->year,
                month      => int( ( $self->month - 1 ) / 3 ) * 3 + 1,
                day        => 1,
                hour       => 0,
                minute     => 0,
                second     => 0,
                nanosecond => 0,
            );
        }
        else {
            my $truncate;
            for my $f (qw( year month day hour minute second nanosecond )) {
                $new{$f} = $truncate ? $TruncateDefault{$f} : $self->$f();

                $truncate = 1 if $p{to} eq $f;
            }
        }

        my $new_dt = $self->_new_from_self( %new, _skip_validation => 1 );

        %$self = %$new_dt;

        return $self;
    }
}

sub set_time_zone {
    my ( $self, $tz ) = @_;

    if ( ref $tz ) {

        # This is a bit of a hack but it works because time zone objects
        # are singletons, and if it doesn't work all we lose is a little
        # bit of speed.
        return $self if $self->{tz} eq $tz;
    }
    else {
        return $self if $self->{tz}->name eq $tz;
    }

    my $was_floating = $self->{tz}->is_floating;

    my $old_tz = $self->{tz};
    $self->{tz} = ref $tz ? $tz : DateTime::TimeZone->new( name => $tz );

    $self->_handle_offset_modifier( $self->second, 1 );

    my $e;
    try {
        # if it either was or now is floating (but not both)
        if ( $self->{tz}->is_floating xor $was_floating ) {
            $self->_calc_utc_rd;
        }
        elsif ( !$was_floating ) {
            $self->_calc_local_rd;
        }
    }
    catch {
        $e = $_;
    };

    # If we can't recalc the RD values then we shouldn't keep the new TZ. RT
    # #83940
    if ($e) {
        $self->{tz} = $old_tz;
        die $e;
    }

    return $self;
}

sub STORABLE_freeze {
    my $self = shift;

    my $serialized = q{};
    for my $key (
        qw( utc_rd_days
        utc_rd_secs
        rd_nanosecs )
    ) {
        $serialized .= "$key:$self->{$key}|";
    }

    # not used yet, but may be handy in the future.
    $serialized .= 'version:' . ( $DateTime::VERSION || 'git' );

    # Formatter needs to be returned as a reference since it may be
    # undef or a class name, and Storable will complain if extra
    # return values aren't refs
    return $serialized, $self->{locale}, $self->{tz}, \$self->{formatter};
}

sub STORABLE_thaw {
    my $self = shift;
    shift;
    my $serialized = shift;

    my %serialized = map { split /:/ } split /\|/, $serialized;

    my ( $locale, $tz, $formatter );

    # more recent code version
    if (@_) {
        ( $locale, $tz, $formatter ) = @_;
    }
    else {
        $tz = DateTime::TimeZone->new( name => delete $serialized{tz} );

        $locale = DateTime::Locale->load( delete $serialized{locale} );
    }

    delete $serialized{version};

    my $object = bless {
        utc_vals => [
            $serialized{utc_rd_days},
            $serialized{utc_rd_secs},
            $serialized{rd_nanosecs},
        ],
        tz => $tz,
        },
        'DateTime::_Thawed';

    my %formatter = defined $$formatter ? ( formatter => $$formatter ) : ();
    my $new       = ( ref $self )->from_object(
        object => $object,
        locale => $locale,
        %formatter,
    );

    %$self = %$new;

    return $self;
}

## no critic (Modules::ProhibitMultiplePackages)
package    # hide from PAUSE
    DateTime::_Thawed;

sub utc_rd_values { @{ $_[0]->{utc_vals} } }

sub time_zone { $_[0]->{tz} }

1;

# ABSTRACT: A date and time object for Perl

__END__

=pod

=encoding UTF-8

=head1 NAME

DateTime - A date and time object for Perl

=head1 VERSION

version 1.66

=head1 SYNOPSIS

    use DateTime;

    $dt = DateTime->new(
        year       => 1964,
        month      => 10,
        day        => 16,
        hour       => 16,
        minute     => 12,
        second     => 47,
        nanosecond => 500000000,
        time_zone  => 'Asia/Taipei',
    );

    $dt = DateTime->from_epoch( epoch => $epoch );
    $dt = DateTime->now;    # same as ( epoch => time )

    $year  = $dt->year;
    $month = $dt->month;        # 1-12

    $day = $dt->day;            # 1-31

    $dow = $dt->day_of_week;    # 1-7 (Monday is 1)

    $hour   = $dt->hour;        # 0-23
    $minute = $dt->minute;      # 0-59

    $second = $dt->second;      # 0-61 (leap seconds!)

    $doy = $dt->day_of_year;    # 1-366 (leap years)

    $doq = $dt->day_of_quarter; # 1..

    $qtr = $dt->quarter;        # 1-4

    # all of the start-at-1 methods above have corresponding start-at-0
    # methods, such as $dt->day_of_month_0, $dt->month_0 and so on

    $ymd = $dt->ymd;         # 2002-12-06
    $ymd = $dt->ymd('/');    # 2002/12/06

    $mdy = $dt->mdy;         # 12-06-2002
    $mdy = $dt->mdy('/');    # 12/06/2002

    $dmy = $dt->dmy;         # 06-12-2002
    $dmy = $dt->dmy('/');    # 06/12/2002

    $hms = $dt->hms;         # 14:02:29
    $hms = $dt->hms('!');    # 14!02!29

    $is_leap = $dt->is_leap_year;

    # these are localizable, see Locales section
    $month_name = $dt->month_name;    # January, February, ...
    $month_abbr = $dt->month_abbr;    # Jan, Feb, ...
    $day_name   = $dt->day_name;      # Monday, Tuesday, ...
    $day_abbr   = $dt->day_abbr;      # Mon, Tue, ...

    # May not work for all possible datetime, see the docs on this
    # method for more details.
    $epoch_time = $dt->epoch;

    $dt2 = $dt + $duration_object;

    $dt3 = $dt - $duration_object;

    $duration_object = $dt - $dt2;

    $dt->set( year => 1882 );

    $dt->set_time_zone('America/Chicago');

    $dt->set_formatter($formatter);

=head1 DESCRIPTION

DateTime is a class for the representation of date/time combinations, and is
part of the Perl DateTime project.

It represents the Gregorian calendar, extended backwards in time before its
creation (in 1582). This is sometimes known as the "proleptic Gregorian
calendar". In this calendar, the first day of the calendar (the epoch), is the
first day of year 1, which corresponds to the date which was (incorrectly)
believed to be the birth of Jesus Christ.

The calendar represented does have a year 0, and in that way differs from how
dates are often written using "BCE/CE" or "BC/AD".

For infinite datetimes, please see the L<DateTime::Infinite|DateTime::Infinite>
module.

=head1 USAGE

=head2 0-based Versus 1-based Numbers

The C<DateTime> module follows a simple logic for determining whether or not a
given number is 0-based or 1-based.

Month, day of month, day of week, and day of year are 1-based. Any method that
is 1-based also has an equivalent 0-based method ending in C<_0>. So for
example, this class provides both C<day_of_week> and C<day_of_week_0> methods.

The C<day_of_week_0> method still treats Monday as the first day of the week.

All I<time>-related numbers such as hour, minute, and second are 0-based.

Years are neither, as they can be both positive or negative, unlike any other
datetime component. There I<is> a year 0.

There is no C<quarter_0> method.

=head2 Error Handling

Some errors may cause this module to die with an error string. This can only
happen when calling constructor methods, methods that change the object, such
as C<set>, or methods that take parameters. Methods that retrieve information
about the object, such as C<year> or C<epoch>, will never die.

=head2 Locales

All the object methods which return names or abbreviations return data based on
a locale. This is done by setting the locale when constructing a DateTime
object. If this is not set, then C<"en-US"> is used.

=head2 Floating DateTimes

The default time zone for new DateTime objects, except where stated otherwise,
is the "floating" time zone. This concept comes from the iCal standard. A
floating datetime is one which is not anchored to any particular time zone. In
addition, floating datetimes do not include leap seconds, since we cannot apply
them without knowing the datetime's time zone.

The results of date math and comparison between a floating datetime and one
with a real time zone are not really valid, because one includes leap seconds
and the other does not. Similarly, the results of datetime math between two
floating datetimes and two datetimes with time zones are not really comparable.

If you are planning to use any objects with a real time zone, it is strongly
recommended that you B<do not> mix these with floating datetimes.

=head2 Math

If you are going to be doing date math, please read the section L<How DateTime
Math Works>.

=head2 Determining the Local Time Zone Can Be Slow

If C<$ENV{TZ}> is not set, it may involve reading a number of files in F</etc>
or elsewhere. If you know that the local time zone won't change while your code
is running, and you need to make many objects for the local time zone, it is
strongly recommended that you retrieve the local time zone once and cache it:

    my $local_time_zone = DateTime::TimeZone->new( name => 'local' );

    # then everywhere else

    my $dt = DateTime->new( ..., time_zone => $local_time_zone );

DateTime itself does not do this internally because local time zones can
change, and there's no good way to determine if it's changed without doing all
the work to look it up.

=head2 Far Future DST

Do not try to use named time zones (like "America/Chicago") with dates very far
in the future (thousands of years). The current implementation of
C<DateTime::TimeZone> will use a huge amount of memory calculating all the DST
changes from now until the future date. Use UTC or the floating time zone and
you will be safe.

=head2 Globally Setting a Default Time Zone

B<Warning: This is very dangerous. Do this at your own risk!>

By default, C<DateTime> uses either the floating time zone or UTC for newly
created objects, depending on the constructor.

You can force C<DateTime> to use a different time zone by setting the
C<PERL_DATETIME_DEFAULT_TZ> environment variable.

As noted above, this is very dangerous, as it affects all code that creates a
C<DateTime> object, including modules from CPAN. If those modules expect the
normal default, then setting this can cause confusing breakage or subtly broken
data. Before setting this variable, you are strongly encouraged to audit your
CPAN dependencies to see how they use C<DateTime>. Try running the test suite
for each dependency with this environment variable set before using this in
production.

=head2 Upper and Lower Bounds

Internally, dates are represented the number of days before or after
0001-01-01. This is stored as an integer, meaning that the upper and lower
bounds are based on your Perl's integer size (C<$Config{ivsize}>).

The limit on 32-bit systems is around 2^29 days, which gets you to year
(+/-)1,469,903. On a 64-bit system you get 2^62 days, to year
(+/-)12,626,367,463,883,278 (12.626 quadrillion).

=head1 METHODS

DateTime provides many methods. The documentation breaks them down into groups
based on what they do (constructor, accessors, modifiers, etc.).

=head2 Constructors

All constructors can die when invalid parameters are given.

=head3 Warnings

Currently, constructors will warn if you try to create a far future DateTime
(year >= 5000) with any time zone besides floating or UTC. This can be very
slow if the time zone has future DST transitions that need to be calculated. If
the date is sufficiently far in the future this can be I<really> slow
(minutes).

All warnings from DateTime use the C<DateTime> category and can be suppressed
with:

    no warnings 'DateTime';

This warning may be removed in the future if L<DateTime::TimeZone> is made much
faster.

=head3 DateTime->new( ... )

    my $dt = DateTime->new(
        year       => 1966,
        month      => 10,
        day        => 25,
        hour       => 7,
        minute     => 15,
        second     => 47,
        nanosecond => 500000000,
        time_zone  => 'America/Chicago',
    );

This class method accepts the following parameters:

=over 4

=item * year

An integer year for the DateTime. This can be any integer number within the
valid range for your system (See L</Upper and Lower Bounds>). This is required.

=item * month

An integer from 1-12. Defaults to 1.

=item * day

An integer from 1-31. The value will be validated based on the month, to
prevent creating invalid dates like February 30. Defaults to 1.

=item * hour

An integer from 0-23. Hour 0 is midnight at the beginning of the given date.
Defaults to 0.

=item * minute

An integer from 0-59. Defaults to 0.

=item * second

An integer from 0-61. Values of 60 or 61 are only allowed when the specified
date and time have a leap second. Defaults to 0.

=item * nanosecond

An integer that is greater than or equal to 0. If this number is greater than 1
billion, it will be normalized into the second value for the DateTime object.
Defaults to 0

=item * locale

A string containing a locale code, like C<"en-US"> or C<"zh-Hant-TW">, or an
object returned by C<< DateTime::Locale->load >>. See the L<DateTime::Locale>
documentation for details. Defaults to the value of C<< DateTime->DefaultLocale
>>, or C<"en-US"> if the class default has not been set.

=item * time_zone

A string containing a time zone name like "America/Chicago" or a
L<DateTime::TimeZone> object. Defaults to the value of
C<$ENV{PERL_DATETIME_DEFAULT_TZ}> or "floating" if that env var is not set. See
L</Globally Setting a Default Time Zone> for more details on that env var (and
why you should not use it).

A string will simply be passed to the C<< DateTime::TimeZone->new >> method as
its C<name> parameter. This string may be an Olson DB time zone name
("America/Chicago"), an offset string ("+0630"), or the words "floating" or
"local". See the C<DateTime::TimeZone> documentation for more details.

=item * formatter

An object or class name with a C<format_datetime> method. This will be used to
stringify the DateTime object. This is optional. If it is not specified, then
stringification calls C<< $self->iso8601 >>.

=back

Invalid parameter types (like an array reference) will cause the constructor to
die.

=head4 Parsing Dates

B<This module does not parse dates!> That means there is no constructor to
which you can pass things like "March 3, 1970 12:34".

Instead, take a look at the various
L<DateTime::Format::*|https://metacpan.org/search?q=datetime%3A%3Aformat>
modules on CPAN. These parse all sorts of different date formats, and you're
bound to find something that can handle your particular needs.

=head4 Ambiguous Local Times

Because of Daylight Saving Time, it is possible to specify a local time that is
ambiguous. For example, in the US in 2003, the transition from to saving to
standard time occurred on October 26, at 02:00:00 local time. The local clock
changed from 01:59:59 (saving time) to 01:00:00 (standard time). This means
that the hour from 01:00:00 through 01:59:59 actually occurs twice, though the
UTC time continues to move forward.

If you specify an ambiguous time, then the latest UTC time is always used, in
effect always choosing standard time. In this case, you can simply subtract an
hour from the object in order to move to saving time, for example:

    # This object represent 01:30:00 standard time
    my $dt = DateTime->new(
        year      => 2003,
        month     => 10,
        day       => 26,
        hour      => 1,
        minute    => 30,
        second    => 0,
        time_zone => 'America/Chicago',
    );

    print $dt->hms;    # prints 01:30:00

    # Now the object represent 01:30:00 saving time
    $dt->subtract( hours => 1 );

    print $dt->hms;    # still prints 01:30:00

Alternately, you could create the object with the UTC time zone and then call
the C<set_time_zone> method to change the time zone. This is a good way to
ensure that the time is not ambiguous.

=head4 Invalid Local Times

Another problem introduced by Daylight Saving Time is that certain local times
just do not exist. For example, in the US in 2003, the transition from standard
to saving time occurred on April 6, at the change to 2:00:00 local time. The
local clock changed from 01:59:59 (standard time) to 03:00:00 (saving time).
This means that there is no 02:00:00 through 02:59:59 on April 6!

Attempting to create an invalid time currently causes a fatal error.

=head3 DateTime->from_epoch( epoch => $epoch, ... )

This class method can be used to construct a new DateTime object from an epoch
time instead of components. Just as with the C<new> method, it accepts
C<time_zone>, C<locale>, and C<formatter> parameters.

You can also call it with a single unnamed argument, which will be treated as
the epoch value.

If the epoch value is a non-integral value, it will be rounded to nearest
microsecond.

By default, the returned object will be in the UTC time zone.

If you pass a C<time_zone>, then this time zone will be applied I<after> the
object is constructed. In other words, the epoch value is always interpreted as
being in the UTC time zone. Here's an example:

    my $dt = DateTime->from_epoch(
        epoch     => 0,
        time_zone => 'Asia/Tokyo'
    );
    say $dt; # Prints 1970-01-01T09:00:00 as Asia/Tokyo is +09:00 from UTC.
    $dt->set_time_zone('UTC');
    say $dt; # Prints 1970-01-01T00:00:00

=head3 DateTime->now( ... )

This class method is equivalent to calling C<from_epoch> with the value
returned from Perl's C<time> function. Just as with the C<new> method, it
accepts C<time_zone> and C<locale> parameters.

By default, the returned object will be in the UTC time zone.

If you want sub-second resolution, use the L<DateTime::HiRes> module's C<<
DateTime::HiRes->now >> method instead.

=head3 DateTime->today( ... )

This class method is equivalent to:

    DateTime->now(@_)->truncate( to => 'day' );

=head3 DateTime->last_day_of_month( ... )

This constructor takes the same arguments as can be given to the C<new> method,
except for C<day>. Additionally, both C<year> and C<month> are required.

=head3 DateTime->from_day_of_year( ... )

This constructor takes the same arguments as can be given to the C<new> method,
except that it does not accept a C<month> or C<day> argument. Instead, it
requires both C<year> and C<day_of_year>. The day of year must be between 1 and
366, and 366 is only allowed for leap years.

=head3 DateTime->from_object( object => $object, ... )

This class method can be used to construct a new DateTime object from any
object that implements the C<utc_rd_values> method. All C<DateTime::Calendar>
modules must implement this method in order to provide cross-calendar
compatibility. This method accepts a C<locale> and C<formatter> parameter

If the object passed to this method has a C<time_zone> method, that is used to
set the time zone of the newly created C<DateTime> object.

Otherwise, the returned object will be in the floating time zone.

=head3 $dt->clone

This object method returns a new object that is replica of the object upon
which the method is called.

=head2 "Get" Methods

This class has many methods for retrieving information about an object.

=head3 $dt->year

Returns the year.

=head3 $dt->ce_year

Returns the year according to the BCE/CE numbering system. The year before year
1 in this system is year -1, aka "1 BCE".

=head3 $dt->era_name

Returns the long name of the current era, something like "Before Christ". See
the L</Locales> section for more details.

=head3 $dt->era_abbr

Returns the abbreviated name of the current era, something like "BC". See the
L</Locales> section for more details.

=head3 $dt->christian_era

Returns a string, either "BC" or "AD", according to the year.

=head3 $dt->secular_era

Returns a string, either "BCE" or "CE", according to the year.

=head3 $dt->year_with_era

Returns a string containing the year immediately followed by the appropriate
era abbreviation, based on the object's locale. The year is the absolute value
of C<ce_year>, so that year 1 is "1" and year 0 is "1BC". See the L</Locales>
section for more details.

=head3 $dt->year_with_christian_era

Like C<year_with_era>, but uses the C<christian_era> method to get the era
name.

=head3 $dt->year_with_secular_era

Like C<year_with_era>, but uses the C<secular_era> method to get the era name.

=head3 $dt->month

Returns the month of the year, from 1..12.

Also available as C<< $dt->mon >>.

=head3 $dt->month_name

Returns the name of the current month. See the L</Locales> section for more
details.

=head3 $dt->month_abbr

Returns the abbreviated name of the current month. See the L</Locales> section
for more details.

=head3 $dt->day

Returns the day of the month, from 1..31.

Also available as C<< $dt->mday >> and C<< $dt->day_of_month >>.

=head3 $dt->day_of_week

Returns the day of the week as a number, from 1..7, with 1 being Monday and 7
being Sunday.

Also available as C<< $dt->wday >> and C<< $dt->dow >>.

=head3 $dt->local_day_of_week

Returns the day of the week as a number, from 1..7. The day corresponding to 1
will vary based on the locale. See the L</Locales> section for more details.

=head3 $dt->day_name

Returns the name of the current day of the week. See the L</Locales> section
for more details.

=head3 $dt->day_abbr

Returns the abbreviated name of the current day of the week. See the
L</Locales> section for more details.

=head3 $dt->day_of_year

Returns the day of the year.

Also available as C<< $dt->doy >>.

=head3 $dt->quarter

Returns the quarter of the year, from 1..4.

=head3 $dt->quarter_name

Returns the name of the current quarter. See the L</Locales> section for more
details.

=head3 $dt->quarter_abbr

Returns the abbreviated name of the current quarter. See the L</Locales>
section for more details.

=head3 $dt->day_of_quarter

Returns the day of the quarter.

Also available as C<< $dt->doq >>.

=head3 $dt->weekday_of_month

Returns a number from 1..5 indicating which week day of the month this is. For
example, June 9, 2003 is the second Monday of the month, and so this method
returns 2 for that date.

=head3 $dt->ymd($optional_separator), $dt->mdy(...), $dt->dmy(...)

Each method returns the year, month, and day, in the order indicated by the
method name. Years are zero-padded to four digits. Months and days are 0-padded
to two digits.

By default, the values are separated by a dash (-), but this can be overridden
by passing a value to the method.

The C<< $dt->ymd >> method is also available as C<< $dt->date >>.

=head3 $dt->hour

Returns the hour of the day, from 0..23.

=head3 $dt->hour_1

Returns the hour of the day, from 1..24.

=head3 $dt->hour_12

Returns the hour of the day, from 1..12.

=head3 $dt->hour_12_0

Returns the hour of the day, from 0..11.

=head3 $dt->am_or_pm

Returns the appropriate localized abbreviation, depending on the current hour.

=head3 $dt->minute

Returns the minute of the hour, from 0..59.

Also available as C<< $dt->min >>.

=head3 $dt->second

Returns the second, from 0..61. The values 60 and 61 are used for leap seconds.

Also available as C<< $dt->sec >>.

=head3 $dt->fractional_second

Returns the second, as a real number from 0.0 until 61.999999999

The values 60 and 61 are used for leap seconds.

=head3 $dt->millisecond

Returns the fractional part of the second as milliseconds (1E-3 seconds).

Half a second is 500 milliseconds.

This value will always be rounded down to the nearest integer.

=head3 $dt->microsecond

Returns the fractional part of the second as microseconds (1E-6 seconds).

Half a second is 500,000 microseconds.

This value will always be rounded down to the nearest integer.

=head3 $dt->nanosecond

Returns the fractional part of the second as nanoseconds (1E-9 seconds).

 Half a second is 500,000,000 nanoseconds.

=head3 $dt->hms($optional_separator)

Returns the hour, minute, and second, all zero-padded to two digits. If no
separator is specified, a colon (:) is used by default.

Also available as C<< $dt->time >>.

=head3 $dt->datetime($optional_separator)

This method is equivalent to:

    $dt->ymd('-') . 'T' . $dt->hms(':')

The C<$optional_separator> parameter allows you to override the separator
between the date and time, for e.g. C<< $dt->datetime(q{ }) >>.

This method is also available as C<< $dt->iso8601 >>, but it's not really a
very good ISO8601 format, as it lacks a time zone. If called as C<<
$dt->iso8601 >> you cannot change the separator, as ISO8601 specifies that "T"
must be used to separate them.

=head3 $dt->rfc3339

This formats a datetime in RFC3339 format. This is the same as C<<
$dt->datetime >> with an added offset at the end of the string except if the
time zone is the floating time zone.

If the offset is '+00:00' then this is represented as 'Z'. Otherwise the offset
is formatted with a leading sign (+/-) and a colon separated numeric offset
with hours and minutes. If the offset has a non-zero seconds component, that is
also included.

=head3 $dt->stringify

This method returns a stringified version of the object. It is also how
stringification overloading is implemented. If the object has a formatter, then
its C<format_datetime> method is used to produce a string. Otherwise, this
method calls C<< $dt->iso8601 >> to produce a string. See L</Formatters And
Stringification> for details.

=head3 $dt->is_leap_year

This method returns a boolean value indicating whether or not the datetime
object is in a leap year.

=head3 $dt->is_last_day_of_month

This method returns a boolean value indicating whether or not the datetime
object is the last day of the month.

=head3 $dt->is_last_day_of_quarter

This method returns a boolean value indicating whether or not the datetime
object is the last day of the quarter.

=head3 $dt->is_last_day_of_year

This method returns a boolean value indicating whether or not the datetime
object is the last day of the year.

=head3 $dt->month_length

This method returns the number of days in the current month.

=head3 $dt->quarter_length

This method returns the number of days in the current quarter.

=head3 $dt->year_length

This method returns the number of days in the current year.

=head3 $dt->week

   my ( $week_year, $week_number ) = $dt->week;

Returns information about the calendar week for the date. The values returned
by this method are also available separately through the C<< $dt->week_year >>
and C<< $dt->week_number >> methods.

The first week of the year is defined by ISO as the one which contains the
fourth day of January, which is equivalent to saying that it's the first week
to overlap the new year by at least four days.

Typically the week year will be the same as the year that the object is in, but
dates at the very beginning of a calendar year often end up in the last week of
the prior year, and similarly, the final few days of the year may be placed in
the first week of the next year.

=head3 $dt->week_year

Returns the year of the week. See C<< $dt->week >> for details.

=head3 $dt->week_number

Returns the week of the year, from 1..53. See C<< $dt->week >> for details.

=head3 $dt->week_of_month

The week of the month, from 0..5. The first week of the month is the first week
that contains a Thursday. This is based on the ICU definition of week of month,
and correlates to the ISO8601 week of year definition. A day in the week
I<before> the week with the first Thursday will be week 0.

=head3 $dt->jd, $dt->mjd

These return the Julian Day and Modified Julian Day, respectively. The value
returned is a floating point number. The fractional portion of the number
represents the time portion of the datetime.

The Julian Day is a count of days since the beginning of the Julian Period,
which starts with day 0 at noon on January 1, -4712.

The Modified Julian Day is a count of days since midnight on November 17, 1858.

These methods always refer to the local time, so the Julian Day is the same for
a given datetime regardless of its time zone. Or in other words,
2020-12-04T13:01:57 in "America/Chicago" has the same Julian Day as
2020-12-04T13:01:57 in "Asia/Taipei".

=head3 $dt->time_zone

This returns the L<DateTime::TimeZone> object for the datetime object.

=head3 $dt->offset

This returns the offset from UTC, in seconds, of the datetime object's time
zone.

=head3 $dt->is_dst

Returns a boolean indicating whether or not the datetime's time zone is
currently in Daylight Saving Time or not.

=head3 $dt->time_zone_long_name

This is a shortcut for C<< $dt->time_zone->name >>. It's provided so that one
can use "%{time_zone_long_name}" as a strftime format specifier.

=head3 $dt->time_zone_short_name

This method returns the time zone abbreviation for the current time zone, such
as "PST" or "GMT". These names are B<not> definitive, and should not be used in
any application intended for general use by users around the world. That's
because it's possible for multiple time zones to have the same abbreviation.

=head3 $dt->strftime( $format, ... )

This method implements functionality similar to the C<strftime> method in C.
However, if given multiple format strings, then it will return multiple
scalars, one for each format string.

See the L<strftime Patterns> section for a list of all possible strftime
patterns.

If you give a pattern that doesn't exist, then it is simply treated as text.

Note that any deviation from the POSIX standard is probably a bug. DateTime
should match the output of C<POSIX::strftime> for any given pattern.

=head3 $dt->format_cldr( $format, ... )

This method implements formatting based on the CLDR date patterns. If given
multiple format strings, then it will return multiple scalars, one for each
format string.

See the L<CLDR Patterns> section for a list of all possible CLDR patterns.

If you give a pattern that doesn't exist, then it is simply treated as text.

=head3 $dt->epoch

Returns the UTC epoch value for the datetime object. Datetimes before the start
of the epoch will be returned as a negative number.

The return value from this method is always an integer number of seconds.

Since the epoch does not account for leap seconds, the epoch time for
1972-12-31T23:59:60 (UTC) is exactly the same as that for 1973-01-01T00:00:00.

=head3 $dt->hires_epoch

Returns the epoch as a floating point number. The floating point portion of the
value represents the nanosecond value of the object. This method is provided
for compatibility with the C<Time::HiRes> module.

Note that this method suffers from the imprecision of floating point numbers,
and the result may end up rounded to an arbitrary degree depending on your
platform.

    my $dt = DateTime->new( year => 2012, nanosecond => 4 );
    say $dt->hires_epoch;

On my system, this simply prints C<1325376000> because adding C<0.000000004> to
C<1325376000> returns C<1325376000>.

=head3 $dt->is_finite, $dt->is_infinite

These methods allow you to distinguish normal datetime objects from infinite
ones. Infinite datetime objects are documented in L<DateTime::Infinite>.

=head3 $dt->utc_rd_values

Returns the current UTC Rata Die days, seconds, and nanoseconds as a three
element list. This exists primarily to allow other calendar modules to create
objects based on the values provided by this object.

=head3 $dt->local_rd_values

Returns the current local Rata Die days, seconds, and nanoseconds as a three
element list. This exists for the benefit of other modules which might want to
use this information for date math, such as L<DateTime::Event::Recurrence>.

=head3 $dt->leap_seconds

Returns the number of leap seconds that have happened up to the datetime
represented by the object. For floating datetimes, this always returns 0.

=head3 $dt->utc_rd_as_seconds

Returns the current UTC Rata Die days and seconds purely as seconds. This
number ignores any fractional seconds stored in the object, as well as leap
seconds.

=head3 $dt->locale

Returns the datetime's L<DateTime::Locale> object.

=head3 $dt->formatter

Returns the current formatter object or class. See L<Formatters And
Stringification> for details.

=head2 "Set" Methods

The remaining methods provided by C<DateTime>, except where otherwise
specified, return the object itself, thus making method chaining possible. For
example:

    my $dt = DateTime->now->set_time_zone( 'Australia/Sydney' );

    my $first = DateTime
                    ->last_day_of_month( year => 2003, month => 3 )
                    ->add( days => 1 )
                    ->subtract( seconds => 1 );

=head3 $dt->set( .. )

This method can be used to change the local components of a date time. This
method accepts any parameter allowed by the C<new> method except for C<locale>
or C<time_zone>. Use C<set_locale> and C<set_time_zone> for those instead.

This method performs parameter validation just like the C<new> method.

B<Do not use this method to do date math. Use the C<add> and C<subtract>
methods instead.>

=head3 $dt->set_year, $dt->set_month, etc.

DateTime has a C<set_*> method for every item that can be passed to the
constructor:

=over 4

=item * $dt->set_year

=item * $dt->set_month

=item * $dt->set_day

=item * $dt->set_hour

=item * $dt->set_minute

=item * $dt->set_second

=item * $dt->set_nanosecond

=back

These are shortcuts to calling C<set> with a single key. They all take a single
parameter.

=head3 $dt->truncate( to => ... )

This method allows you to reset some of the local time components in the object
to their "zero" values. The C<to> parameter is used to specify which values to
truncate, and it may be one of C<"year">, C<"quarter">, C<"month">, C<"week">,
C<"local_week">, C<"day">, C<"hour">, C<"minute">, or C<"second">.

For example, if C<"month"> is specified, then the local day becomes 1, and the
hour, minute, and second all become 0.

If C<"week"> is given, then the datetime is set to the Monday of the week in
which it occurs, and the time components are all set to 0. If you truncate to
C<"local_week">, then the first day of the week is locale-dependent. For
example, in the C<"en-US"> locale, the first day of the week is Sunday.

=head3 $dt->set_locale($locale)

Sets the object's locale. You can provide either a locale code like C<"en-US">
or an object returned by C<< DateTime::Locale->load >>.

=head3 $dt->set_time_zone($tz)

This method accepts either a time zone object or a string that can be passed as
the C<name> parameter to C<< DateTime::TimeZone->new >>. If the new time zone's
offset is different from the old time zone, then the I<local> time is adjusted
accordingly.

For example:

    my $dt = DateTime->new(
        year      => 2000,
        month     => 5,
        day       => 10,
        hour      => 15,
        minute    => 15,
        time_zone => 'America/Los_Angeles',
    );

    print $dt->hour;    # prints 15

    $dt->set_time_zone('America/Chicago');

    print $dt->hour;    # prints 17

If the old time zone was a floating time zone, then no adjustments to the local
time are made, except to account for leap seconds. If the new time zone is
floating, then the I<UTC> time is adjusted in order to leave the local time
untouched.

Fans of Tsai Ming-Liang's films will be happy to know that this does work:

    my $dt = DateTime->now( time_zone => 'Asia/Taipei' );
    $dt->set_time_zone('Europe/Paris');

Yes, now we can know "ni3 na4 bian1 ji2 dian3?"

=head3 $dt->set_formatter($formatter)

Sets the formatter for the object. See L<Formatters And Stringification> for
details.

You can set this to C<undef> to revert to the default formatter.

=head2 Math Methods

Like the set methods, math related methods always return the object itself, to
allow for chaining:

    $dt->add( days => 1 )->subtract( seconds => 1 );

=head3 $dt->duration_class

This returns L<C<"DateTime::Duration">|DateTime::Duration>, but exists so that
a subclass of C<DateTime> can provide a different value.

=head3 $dt->add_duration($duration_object)

This method adds a L<DateTime::Duration> to the current datetime. See the
L<DateTime::Duration> docs for more details.

=head3 $dt->add( parameters for DateTime::Duration )

This method is syntactic sugar around the C<< $dt->add_duration >> method. It
simply creates a new L<DateTime::Duration> object using the parameters given,
and then calls the C<< $dt->add_duration >> method.

=head3 $dt->add($duration_object)

A synonym of C<< $dt->add_duration($duration_object) >>.

=head3 $dt->subtract_duration($duration_object)

When given a L<DateTime::Duration> object, this method simply calls C<<
$dur->inverse >> on that object and passes that new duration to the C<<
$self->add_duration >> method.

=head3 $dt->subtract( DateTime::Duration->new parameters )

Like C<< $dt->add >>, this is syntactic sugar for the C<<
$dt->subtract_duration >> method.

=head3 $dt->subtract($duration_object)

A synonym of C<< $dt->subtract_duration($duration_object) >>.

=head3 $dt->subtract_datetime($datetime)

This method returns a new L<DateTime::Duration> object representing the
difference between the two dates. The duration is B<relative> to the object
from which C<$datetime> is subtracted. For example:

    2003-03-15 00:00:00.00000000
 -  2003-02-15 00:00:00.00000000
 -------------------------------
 = 1 month

Note that this duration is not an absolute measure of the amount of time
between the two datetimes, because the length of a month varies, as well as due
to the presence of leap seconds.

The returned duration may have deltas for months, days, minutes, seconds, and
nanoseconds.

=head3 $dt->delta_md($datetime), $dt->delta_days($datetime)

Each of these methods returns a new L<DateTime::Duration> object representing
some portion of the difference between two datetimes.  The C<< $dt->delta_md >>
method returns a duration which contains only the month and day portions of the
duration is represented. The C<< $dt->delta_days >> method returns a duration
which contains only days.

The C<< $dt->delta_md >> and C<< $dt->delta_days >> methods truncate the
duration so that any fractional portion of a day is ignored. Both of these
methods operate on the date portion of a datetime only, and so effectively
ignore the time zone.

Unlike the subtraction methods, B<these methods always return a positive (or
zero) duration>.

=head3 $dt->delta_ms($datetime)

Returns a duration which contains only minutes and seconds. Any day and month
differences are converted to minutes and seconds. This method B<always returns
a positive (or zero) duration>.

=head3 $dt->subtract_datetime_absolute($datetime)

This method returns a new L<DateTime::Duration> object representing the
difference between the two dates in seconds and nanoseconds. This is the only
way to accurately measure the absolute amount of time between two datetimes,
since units larger than a second do not represent a fixed number of seconds.

Note that because of leap seconds, this may not return the same result as doing
this math based on the value returned by C<< $dt->epoch >>.

=head3 $dt->is_between( $lower, $upper )

Checks whether C<$dt> is strictly between two other DateTime objects.

"Strictly" means that C<$dt> must be greater than C<$lower> and less than
C<$upper>. If it is I<equal> to either object then this method returns false.

=head2 Class Methods

=head3 DateTime->DefaultLocale($locale)

This can be used to specify the default locale to be used when creating
DateTime objects. If unset, then C<"en-US"> is used.

This exists for backwards compatibility, but is probably best avoided. This
will change the default locale for every C<DateTime> object created in your
application, even those created by third party libraries which also use
C<DateTime>.

=head3 DateTime->compare( $dt1, $dt2 ), DateTime->compare_ignore_floating( $dt1, $dt2 )

    $cmp = DateTime->compare( $dt1, $dt2 );

    $cmp = DateTime->compare_ignore_floating( $dt1, $dt2 );

This method compare two DateTime objects. The semantics are compatible with
Perl's C<sort> function; it returns C<-1> if C<< $dt1 < $dt2 >>, C<0> if C<$dt1
== $dt2>, C<1> if C<< $dt1 > $dt2 >>.

If one of the two DateTime objects has a floating time zone, it will first be
converted to the time zone of the other object. This is what you want most of
the time, but it can lead to inconsistent results when you compare a number of
DateTime objects, some of which are floating, and some of which are in other
time zones.

If you want to have consistent results (because you want to sort an array of
objects, for example), you can use the C<compare_ignore_floating> method:

    @dates = sort { DateTime->compare_ignore_floating( $a, $b ) } @dates;

In this case, objects with a floating time zone will be sorted as if they were
UTC times.

Since DateTime objects overload comparison operators, this:

    @dates = sort @dates;

is equivalent to this:

    @dates = sort { DateTime->compare( $a, $b ) } @dates;

DateTime objects can be compared to any other calendar class that implements
the C<utc_rd_values> method.

=head2 Testing Code That Uses DateTime

If you are trying to test code that calls uses DateTime, you may want to be to
explicitly set the value returned by Perl's C<time> builtin. This builtin is
called by C<< DateTime->now >> and C<< DateTime->today >>.

You can override C<CORE::GLOBAL::time>, but this will only work if you do this
B<before> loading DateTime. If doing this is inconvenient, you can also
override C<DateTime::_core_time>:

    no warnings 'redefine';
    local *DateTime::_core_time = sub { return 42 };

DateTime is guaranteed to call this subroutine to get the current C<time>
value. You can also override the C<_core_time> sub in a subclass of DateTime
and use that.

=head2 How DateTime Math Works

It's important to have some understanding of how datetime math is implemented
in order to effectively use this module and L<DateTime::Duration>.

=head3 Making Things Simple

If you want to simplify your life and not have to think too hard about the
nitty-gritty of datetime math, I have several recommendations:

=over 4

=item * use the floating time zone

If you do not care about time zones or leap seconds, use the "floating"
timezone:

    my $dt = DateTime->now( time_zone => 'floating' );

Math done on two objects in the floating time zone produces very predictable
results.

Note that in most cases you will want to start by creating an object in a
specific zone and I<then> convert it to the floating time zone. When an object
goes from a real zone to the floating zone, the time for the object remains the
same.

This means that passing the floating zone to a constructor may not do what you
want.

    my $dt = DateTime->now( time_zone => 'floating' );

is equivalent to

    my $dt = DateTime->now( time_zone => 'UTC' )->set_time_zone('floating');

This might not be what you wanted. Instead, you may prefer to do this:

    my $dt = DateTime->now( time_zone => 'local' )->set_time_zone('floating');

=item * use UTC for all calculations

If you do care about time zones (particularly DST) or leap seconds, try to use
non-UTC time zones for presentation and user input only. Convert to UTC
immediately and convert back to the local time zone for presentation:

    my $dt = DateTime->new( %user_input, time_zone => $user_tz );
    $dt->set_time_zone('UTC');

    # do various operations - store it, retrieve it, add, subtract, etc.

    $dt->set_time_zone($user_tz);
    print $dt->datetime;

=item * math on non-UTC time zones

If you need to do date math on objects with non-UTC time zones, please read the
caveats below carefully. The results C<DateTime> produces are predictable,
correct, and mostly intuitive, but datetime math gets very ugly when time zones
are involved, and there are a few strange corner cases involving subtraction of
two datetimes across a DST change.

If you can always use the floating or UTC time zones, you can skip ahead to
L<Leap Seconds and Date Math>

=item * date vs datetime math

If you only care about the date (calendar) portion of a datetime, you should
use either C<< $dt->delta_md >> or C<< $dt->delta_days >>, not C<<
$dt->subtract_datetime >>. This will give predictable, unsurprising results,
free from DST-related complications.

=item * $dt->subtract_datetime and $dt->add_duration

You must convert your datetime objects to the UTC time zone before doing date
math if you want to make sure that the following formulas are always true:

    $dt2 - $dt1 = $dur
    $dt1 + $dur = $dt2
    $dt2 - $dur = $dt1

Note that using C<< $dt->delta_days >> ensures that this formula always works,
regardless of the time zones of the objects involved, as does using C<<
$dt->subtract_datetime_absolute >>. Other methods of subtraction are not always
reversible.

=item * never do math on two objects where only one is in the floating time zone

The date math code accounts for leap seconds whenever the C<DateTime> object is
not in the floating time zone. If you try to do math where one object is in the
floating zone and the other isn't, the results will be confusing and wrong.

=back

=head3 Adding a Duration to a DateTime

The parts of a duration can be broken down into five parts. These are months,
days, minutes, seconds, and nanoseconds. Adding one month to a date is
different than adding 4 weeks or 28, 29, 30, or 31 days.  Similarly, due to DST
and leap seconds, adding a day can be different than adding 86,400 seconds, and
adding a minute is not exactly the same as 60 seconds.

We cannot convert between these units, except for seconds and nanoseconds,
because there is no fixed conversion between most pairs of units. That is
because of things like leap seconds, DST changes, etc.

C<DateTime> always adds (or subtracts) days, then months, minutes, and then
seconds and nanoseconds. If there are any boundary overflows, these are
normalized at each step. For the days and months the local (not UTC) values are
used. For minutes and seconds, the local values are used. This generally just
works.

This means that adding one month and one day to February 28, 2003 will produce
the date April 1, 2003, not March 29, 2003.

    my $dt = DateTime->new( year => 2003, month => 2, day => 28 );

    $dt->add( months => 1, days => 1 );

    # 2003-04-01 - the result

On the other hand, if we add months first, and then separately add days, we end
up with March 29, 2003:

    $dt->add( months => 1 )->add( days => 1 );

    # 2003-03-29

We see similar strangeness when math crosses a DST boundary:

    my $dt = DateTime->new(
        year      => 2003,
        month     => 4,
        day       => 5,
        hour      => 1,
        minute    => 58,
        time_zone => "America/Chicago",
    );

    $dt->add( days => 1, minutes => 3 );
    # 2003-04-06 02:01:00

    $dt->add( minutes => 3 )->add( days => 1 );
    # 2003-04-06 03:01:00

Note that if you converted the datetime object to UTC first you would get
predictable results.

If you want to know how many seconds a L<DateTime::Duration> object represents,
you have to add it to a datetime to find out, so you could do:

    my $now   = DateTime->now( time_zone => 'UTC' );
    my $later = $now->clone->add_duration($duration);

    my $seconds_dur = $later->subtract_datetime_absolute($now);

This returns a L<DateTime::Duration> which only contains seconds and
nanoseconds.

If we were add the duration to a different C<DateTime> object we might get a
different number of seconds.

L<DateTime::Duration> supports three different end-of-month algorithms for
adding months. This comes into play when an addition results in a day past the
end of the following month (for example, adding one month to January 30).

    # 2010-08-31 + 1 month = 2010-10-01
    $dt->add( months => 1, end_of_month => 'wrap' );

    # 2010-01-30 + 1 month = 2010-02-28
    $dt->add( months => 1, end_of_month => 'limit' );

    # 2010-04-30 + 1 month = 2010-05-31
    $dt->add( months => 1, end_of_month => 'preserve' );

By default, it uses C<"wrap"> for positive durations and C<"preserve"> for
negative durations. See L<DateTime::Duration> for a detailed explanation of
these algorithms.

If you need to do lots of work with durations, take a look at the
L<DateTime::Format::Duration> module, which lets you present information from
durations in many useful ways.

There are other subtract/delta methods in C<DateTime> to generate different
types of durations. These methods are C<< $dt->subtract_datetime >>, C<<
$dt->subtract_datetime_absolute >>, C<< $dt->delta_md >>, C<< $dt->delta_days
>>, and C<< $dt->delta_ms >>.

=head3 DateTime Subtraction

Date subtraction is done based solely on the two object's local datetimes, with
one exception to handle DST changes. Also, if the two datetime objects are in
different time zones, one of them is converted to the other's time zone first
before subtraction. This is best explained through examples:

The first of these probably makes the most sense:

    # not DST
    my $dt1 = DateTime->new(
        year      => 2003,
        month     => 5,
        day       => 6,
        time_zone => 'America/Chicago',
    );

    # is DST
    my $dt2 = DateTime->new(
        year      => 2003,
        month     => 11,
        day       => 6,
        time_zone => 'America/Chicago',
    );

    # 6 months
    my $dur = $dt2->subtract_datetime($dt1);

Nice and simple.

This one is a little trickier, but still fairly logical:

    # is DST
    my $dt1 = DateTime->new(
        year      => 2003,
        month     => 4,
        day       => 5,
        hour      => 1,
        minute    => 58,
        time_zone => "America/Chicago",
    );

    # not DST
    my $dt2 = DateTime->new(
        year      => 2003,
        month     => 4,
        day       => 7,
        hour      => 2,
        minute    => 1,
        time_zone => "America/Chicago",
    );

    # 2 days and 3 minutes
    my $dur = $dt2->subtract_datetime($dt1);

Which contradicts the result this one gives, even though they both make sense:

    # is DST
    my $dt1 = DateTime->new(
        year      => 2003,
        month     => 4,
        day       => 5,
        hour      => 1,
        minute    => 58,
        time_zone => "America/Chicago",
    );

    # not DST
    my $dt2 = DateTime->new(
        year      => 2003,
        month     => 4,
        day       => 6,
        hour      => 3,
        minute    => 1,
        time_zone => "America/Chicago",
    );

    # 1 day and 3 minutes
    my $dur = $dt2->subtract_datetime($dt1);

This last example illustrates the "DST" exception mentioned earlier. The
exception accounts for the fact 2003-04-06 only lasts 23 hours.

And finally:

    my $dt2 = DateTime->new(
        year      => 2003,
        month     => 10,
        day       => 26,
        hour      => 1,
        time_zone => 'America/Chicago',
    );

    my $dt1 = $dt2->clone->subtract( hours => 1 );

    # 60 minutes
    my $dur = $dt2->subtract_datetime($dt1);

This seems obvious until you realize that subtracting 60 minutes from C<$dt2>
in the above example still leaves the clock time at "01:00:00". This time we
are accounting for a 25 hour day.

=head3 Reversibility

Date math operations are not always reversible. This is because of the way that
addition operations are ordered. As was discussed earlier, adding 1 day and 3
minutes in one call to C<< $dt->add >> is not the same as first adding 3
minutes and 1 day in two separate calls.

If we take a duration returned from C<< $dt->subtract_datetime >> and then try
to add or subtract that duration from one of the datetimes we just used, we
sometimes get interesting results:

    my $dt1 = DateTime->new(
        year      => 2003,
        month     => 4,
        day       => 5,
        hour      => 1,
        minute    => 58,
        time_zone => "America/Chicago",
    );

    my $dt2 = DateTime->new(
        year      => 2003,
        month     => 4,
        day       => 6,
        hour      => 3,
        minute    => 1,
        time_zone => "America/Chicago",
    );

    # 1 day and 3 minutes
    my $dur = $dt2->subtract_datetime($dt1);

    # gives us $dt2
    $dt1->add_duration($dur);

    # gives us 2003-04-05 02:58:00 - 1 hour later than $dt1
    $dt2->subtract_duration($dur);

The C<< $dt->subtract_duration >> operation gives us a (perhaps) unexpected
answer because it first subtracts one day to get 2003-04-05T03:01:00 and then
subtracts 3 minutes to get the final result.

If we explicitly reverse the order we can get the original value of C<$dt1>.
This can be facilitated by the L<DateTime::Duration> class's C<<
$dur->calendar_duration >> and C<< $dur->clock_duration >> methods:

    $dt2->subtract_duration( $dur->clock_duration )
        ->subtract_duration( $dur->calendar_duration );

=head3 Leap Seconds and Date Math

The presence of leap seconds can cause even more anomalies in date math. For
example, the following is a legal datetime:

    my $dt = DateTime->new(
        year      => 1972,
        month     => 12,
        day       => 31,
        hour      => 23,
        minute    => 59,
        second    => 60,
        time_zone => 'UTC'
    );

If we add one month ...

    $dt->add( months => 1 );

... the datetime is now "1973-02-01 00:00:00", because there is no 23:59:60 on
1973-01-31.

Leap seconds also force us to distinguish between minutes and seconds during
date math. Given the following datetime ...

    my $dt = DateTime->new(
        year      => 1972,
        month     => 12,
        day       => 31,
        hour      => 23,
        minute    => 59,
        second    => 30,
        time_zone => 'UTC'
    );

... we will get different results when adding 1 minute than we get if we add 60
seconds. This is because in this case, the last minute of the day, beginning at
23:59:00, actually contains 61 seconds.

Here are the results we get:

    # 1972-12-31 23:59:30 - our starting datetime
    my $dt = DateTime->new(
        year      => 1972,
        month     => 12,
        day       => 31,
        hour      => 23,
        minute    => 59,
        second    => 30,
        time_zone => 'UTC'
    );

    # 1973-01-01 00:00:30 - one minute later
    $dt->clone->add( minutes => 1 );

    # 1973-01-01 00:00:29 - 60 seconds later
    $dt->clone->add( seconds => 60 );

    # 1973-01-01 00:00:30 - 61 seconds later
    $dt->clone->add( seconds => 61 );

=head3 Local vs. UTC and 24 hours vs. 1 day

When math crosses a daylight saving boundary, a single day may have more or
less than 24 hours.

For example, if you do this ...

    my $dt = DateTime->new(
        year      => 2003,
        month     => 4,
        day       => 5,
        hour      => 2,
        time_zone => 'America/Chicago',
    );

    $dt->add( days => 1 );

... then you will produce an I<invalid> local time, and therefore an exception
will be thrown.

However, this works ...

    my $dt = DateTime->new(
        year      => 2003,
        month     => 4,
        day       => 5,
        hour      => 2,
        time_zone => 'America/Chicago',
    );

    $dt->add( hours => 24 );

... and produces a datetime with the local time of "03:00".

If all this makes your head hurt, there is a simple alternative. Just convert
your datetime object to the "UTC" time zone before doing date math on it, and
switch it back to the local time zone afterwards. This avoids the possibility
of having date math throw an exception, and makes sure that 1 day equals 24
hours. Of course, this may not always be desirable, so caveat user!

=head2 Overloading

This module explicitly overloads the addition (+), subtraction (-), string and
numeric comparison operators. This means that the following all do sensible
things:

    my $new_dt = $dt + $duration_obj;

    my $new_dt = $dt - $duration_obj;

    my $duration_obj = $dt - $new_dt;

    for my $dt ( sort @dts ) {...}

Additionally, the fallback parameter is set to true, so other derivable
operators (+=, -=, etc.) will work properly. Do not expect increment (++) or
decrement (--) to do anything useful.

The string comparison operators, C<eq> or C<ne>, will use the string value to
compare with non-DateTime objects.

DateTime objects do not have a numeric value, using C<==> or C<< <=> >> to
compare a DateTime object with a non-DateTime object will result in an
exception. To safely sort mixed DateTime and non-DateTime objects, use C<sort {
$a cmp $b } @dates>.

The module also overloads stringification using the object's formatter,
defaulting to C<iso8601> method. See L<Formatters And Stringification> for
details.

=head2 Formatters And Stringification

You can optionally specify a C<formatter>, which is usually a
C<DateTime::Format::*> object or class, to control the stringification of the
DateTime object.

Any of the constructor methods can accept a formatter argument:

    my $formatter = DateTime::Format::Strptime->new(...);
    my $dt        = DateTime->new( year => 2004, formatter => $formatter );

Or, you can set it afterwards:

    $dt->set_formatter($formatter);
    $formatter = $dt->formatter;

Once you set the formatter, the overloaded stringification method will use the
formatter. If unspecified, the C<iso8601> method is used.

A formatter can be handy when you know that in your application you want to
stringify your DateTime objects into a special format all the time, for example
in Postgres format.

If you provide a formatter class name or object, it must implement a
C<format_datetime> method. This method will be called with just the C<DateTime>
object as its argument.

=head2 CLDR Patterns

The CLDR pattern language is both more powerful and more complex than strftime.
Unlike strftime patterns, you often have to explicitly escape text that you do
not want formatted, as the patterns are simply letters without any prefix.

For example, C<"yyyy-MM-dd"> is a valid CLDR pattern. If you want to include
any lower or upper case ASCII characters as-is, you can surround them with
single quotes ('). If you want to include a single quote, you must escape it as
two single quotes ('').

    my $pattern1 = q{'Today is ' EEEE};
    my $pattern2 = q{'It is now' h 'o''clock' a};

Spaces and any non-letter text will always be passed through as-is.

Many CLDR patterns which produce numbers will pad the number with leading
zeroes depending on the length of the format specifier. For example, C<"h">
represents the current hour from 1-12. If you specify C<"hh"> then hours 1-9
will have a leading zero prepended.

However, CLDR often uses five of a letter to represent the narrow form of a
pattern. This inconsistency is necessary for backwards compatibility.

There are many cases where CLDR patterns distinguish between the "format" and
"stand-alone" forms of a pattern. The format pattern is used when the thing in
question is being placed into a larger string. The stand-alone form is used
when displaying that item by itself, for example in a calendar.

There are also many cases where CLDR provides three sizes for each item, wide
(the full name), abbreviated, and narrow. The narrow form is often just a
single character, for example "T" for "Tuesday", and may not be unique.

CLDR provides a fairly complex system for localizing time zones that we ignore
entirely. The time zone patterns just use the information provided by
C<DateTime::TimeZone>, and I<do not follow the CLDR spec>.

The output of a CLDR pattern is always localized, when applicable.

CLDR provides the following patterns:

=over 4

=item * G{1,3}

The abbreviated era (BC, AD).

=item * GGGG

The wide era (Before Christ, Anno Domini).

=item * GGGGG

The narrow era, if it exists (but it mostly doesn't).

=item * y and y{3,}

The year, zero-prefixed as needed. Negative years will start with a "-", and
this will be included in the length calculation.

In other, words the "yyyyy" pattern will format year -1234 as "-1234", not
"-01234".

=item * yy

This is a special case. It always produces a two-digit year, so "1976" becomes
"76". Negative years will start with a "-", making them one character longer.

=item * Y{1,}

The year in "week of the year" calendars, from C<< $dt->week_year >>.

=item * u{1,}

Same as "y" except that "uu" is not a special case.

=item * Q{1,2}

The quarter as a number (1..4).

=item * QQQ

The abbreviated format form for the quarter.

=item * QQQQ

The wide format form for the quarter.

=item * q{1,2}

The quarter as a number (1..4).

=item * qqq

The abbreviated stand-alone form for the quarter.

=item * qqqq

The wide stand-alone form for the quarter.

=item * M{1,2}

The numerical month.

=item * MMM

The abbreviated format form for the month.

=item * MMMM

The wide format form for the month.

=item * MMMMM

The narrow format form for the month.

=item * L{1,2}

The numerical month.

=item * LLL

The abbreviated stand-alone form for the month.

=item * LLLL

The wide stand-alone form for the month.

=item * LLLLL

The narrow stand-alone form for the month.

=item * w{1,2}

The week of the year, from C<< $dt->week_number >>.

=item * W

The week of the month, from C<< $dt->week_of_month >>.

=item * d{1,2}

The numeric day of the month.

=item * D{1,3}

The numeric day of the year.

=item * F

The day of the week in the month, from C<< $dt->weekday_of_month >>.

=item * g{1,}

The modified Julian day, from C<< $dt->mjd >>.

=item * E{1,3} and eee

The abbreviated format form for the day of the week.

=item * EEEE and eeee

The wide format form for the day of the week.

=item * EEEEE and eeeee

The narrow format form for the day of the week.

=item * e{1,2}

The I<local> numeric day of the week, from 1 to 7. This number depends on what
day is considered the first day of the week, which varies by locale. For
example, in the US, Sunday is the first day of the week, so this returns 2 for
Monday.

=item * c

The numeric day of the week from 1 to 7, treating Monday as the first of the
week, regardless of locale.

=item * ccc

The abbreviated stand-alone form for the day of the week.

=item * cccc

The wide stand-alone form for the day of the week.

=item * ccccc

The narrow format form for the day of the week.

=item * a

The localized form of AM or PM for the time.

=item * h{1,2}

The hour from 1-12.

=item * H{1,2}

The hour from 0-23.

=item * K{1,2}

The hour from 0-11.

=item * k{1,2}

The hour from 1-24.

=item * j{1,2}

The hour, in 12 or 24 hour form, based on the preferred form for the locale. In
other words, this is equivalent to either "h{1,2}" or "H{1,2}".

=item * m{1,2}

The minute.

=item * s{1,2}

The second.

=item * S{1,}

The fractional portion of the seconds, rounded based on the length of the
specifier. This returned I<without> a leading decimal point, but may have
leading or trailing zeroes.

=item * A{1,}

The millisecond of the day, based on the current time. In other words, if it is
12:00:00.00, this returns 43200000.

=item * z{1,3}

The time zone short name.

=item * zzzz

The time zone long name.

=item * Z{1,3}

The time zone offset.

=item * ZZZZ

The time zone short name and the offset as one string, so something like
"CDT-0500".

=item * ZZZZZ

The time zone offset as a sexagesimal number, so something like "-05:00". (This
is useful for W3C format.)

=item * v{1,3}

The time zone short name.

=item * vvvv

The time zone long name.

=item * V{1,3}

The time zone short name.

=item * VVVV

The time zone long name.

=back

=head3 CLDR "Available Formats"

The CLDR data includes pre-defined formats for various patterns such as "month
and day" or "time of day". Using these formats lets you render information
about a datetime in the most natural way for users from a given locale.

These formats are indexed by a key that is itself a CLDR pattern. When you look
these up, you get back a different CLDR pattern suitable for the locale.

Let's look at some example We'll use C<2008-02-05T18:30:30> as our example
datetime value, and see how this is rendered for the C<"en-US"> and C<"fr-FR">
locales.

=over 4

=item * C<MMMd>

The abbreviated month and day as number. For C<en-US>, we get the pattern C<MMM
d>, which renders as C<Feb 5>. For C<fr-FR>, we get the pattern C<d MMM>, which
renders as C<5 févr.>.

=item * C<yQQQ>

The year and abbreviated quarter of year. For C<en-US>, we get the pattern
C<QQQ y>, which renders as C<Q1 2008>. For C<fr-FR>, we get the same pattern,
C<QQQ y>, which renders as C<T1 2008>.

=item * C<hm>

The 12-hour time of day without seconds. For C<en-US>, we get the pattern
C<h:mm a>, which renders as C<6:30 PM>. For C<fr-FR>, we get the exact same
pattern and rendering.

=back

The available formats for each locale are documented in the POD for that
locale. To get back the format, you use the C<< $locale->format_for >> method.
For example:

    say $dt->format_cldr( $dt->locale->format_for('MMMd') );

=head2 strftime Patterns

The following patterns are allowed in the format string given to the C<<
$dt->strftime >> method:

=over 4

=item * %a

The abbreviated weekday name.

=item * %A

The full weekday name.

=item * %b

The abbreviated month name.

=item * %B

The full month name.

=item * %c

The default datetime format for the object's locale.

=item * %C

The century number (year/100) as a 2-digit integer.

=item * %d

The day of the month as a decimal number (range 01 to 31).

=item * %D

Equivalent to %m/%d/%y. This is not a good standard format if you want folks
from both the United States and the rest of the world to understand the date!

=item * %e

Like %d, the day of the month as a decimal number, but a leading zero is
replaced by a space.

=item * %F

Equivalent to %Y-%m-%d (the ISO 8601 date format)

=item * %G

The ISO 8601 year with century as a decimal number. The 4-digit year
corresponding to the ISO week number (see %V). This has the same format and
value as %Y, except that if the ISO week number belongs to the previous or next
year, that year is used instead. (TZ)

=item * %g

Like %G, but without century, i.e., with a 2-digit year (00-99).

=item * %h

Equivalent to %b.

=item * %H

The hour as a decimal number using a 24-hour clock (range 00 to 23).

=item * %I

The hour as a decimal number using a 12-hour clock (range 01 to 12).

=item * %j

The day of the year as a decimal number (range 001 to 366).

=item * %k

The hour (24-hour clock) as a decimal number (range 0 to 23); single digits are
preceded by a blank. (See also %H.)

=item * %l

The hour (12-hour clock) as a decimal number (range 1 to 12); single digits are
preceded by a blank. (See also %I.)

=item * %m

The month as a decimal number (range 01 to 12).

=item * %M

The minute as a decimal number (range 00 to 59).

=item * %n

A newline character.

=item * %N

The fractional seconds digits. Default is 9 digits (nanoseconds).

    %3N   milliseconds (3 digits)
    %6N   microseconds (6 digits)
    %9N   nanoseconds  (9 digits)

This value will always be rounded down to the nearest integer.

=item * %p

Either `AM' or `PM' according to the given time value, or the corresponding
strings for the current locale. Noon is treated as `pm' and midnight as `am'.

=item * %P

Like %p but in lowercase: `am' or `pm' or a corresponding string for the
current locale.

=item * %r

The time in a.m. or p.m. notation. In the POSIX locale this is equivalent to
`%I:%M:%S %p'.

=item * %R

The time in 24-hour notation (%H:%M). (SU) For a version including the seconds,
see %T below.

=item * %s

The number of seconds since the epoch.

=item * %S

The second as a decimal number (range 00 to 61).

=item * %t

A tab character.

=item * %T

The time in 24-hour notation (%H:%M:%S).

=item * %u

The day of the week as a decimal, range 1 to 7, Monday being 1. See also %w.

=item * %U

The week number of the current year as a decimal number, range 00 to 53,
starting with the first Sunday as the first day of week 01. See also %V and %W.

=item * %V

The ISO 8601:1988 week number of the current year as a decimal number, range 01
to 53, where week 1 is the first week that has at least 4 days in the current
year, and with Monday as the first day of the week. See also %U and %W.

=item * %w

The day of the week as a decimal, range 0 to 6, Sunday being 0. See also %u.

=item * %W

The week number of the current year as a decimal number, range 00 to 53,
starting with the first Monday as the first day of week 01.

=item * %x

The default date format for the object's locale.

=item * %X

The default time format for the object's locale.

=item * %y

The year as a decimal number without a century (range 00 to 99).

=item * %Y

The year as a decimal number including the century.

=item * %z

The time-zone as hour offset from UTC. Required to emit RFC822-conformant dates
(using "%a, %d %b %Y %H:%M:%S %z").

=item * %Z

The short name for the time zone, typically an abbreviation like "EST" or
"AEST".

=item * %%

A literal `%' character.

=item * %{method}

Any method name may be specified using the format C<%{method}> name where
"method" is a valid C<DateTime> object method.

=back

=head2 DateTime and Storable

C<DateTime> implements L<Storable> hooks in order to reduce the size of a
serialized C<DateTime> object.

=head1 DEVELOPMENT TOOLS

If you're working on the C<DateTIme> code base, there are a few extra non-Perl
tools that you may find useful, notably
L<precious|https://github.com/houseabsolute/precious>, a meta-linter/tidier.
You can install all the necessary tools in C<$HOME/bin> by running
F<./dev-bin/install-dev-tools.sh>.

Try running C<precious tidy -a> to tidy all the tidyable files in the repo, and
C<precious lint -a> to run all the lint checks.

You can enable a git pre-commit hook for linting by running F<./git/setup.pl>.

Note that linting will be checked in CI, and it's okay to submit a PR which
fails the linting check, but it's extra nice to fix these yourself.

=head1 THE DATETIME PROJECT ECOSYSTEM

This module is part of a larger ecosystem of modules in the DateTime family.

=head2 L<DateTime::Set>

The L<DateTime::Set> module represents sets (including recurrences) of
datetimes. Many modules return sets or recurrences.

=head2 Format Modules

The various format modules exist to parse and format datetimes. For example,
L<DateTime::Format::HTTP> parses dates according to the RFC 1123 format:

    my $datetime
        = DateTime::Format::HTTP->parse_datetime(
        'Thu Feb  3 17:03:55 GMT 1994');

    print DateTime::Format::HTTP->format_datetime($datetime);

Most format modules are suitable for use as a C<formatter> with a DateTime
object.

All format modules start with
L<DateTime::Format::|https://metacpan.org/search?q=datetime%3A%3Aformat>.

=head2 Calendar Modules

There are a number of modules on CPAN that implement non-Gregorian calendars,
such as the Chinese, Mayan, and Julian calendars.

All calendar modules start with
L<DateTime::Calendar::|https://metacpan.org/search?q=datetime%3A%3Acalendar>.

=head2 Event Modules

There are a number of modules that calculate the dates for events, such as
Easter, Sunrise, etc.

All event modules start with
L<DateTime::Event::|https://metacpan.org/search?q=datetime%3A%3Aevent>.

=head2 Others

There are many other modules that work with DateTime, including modules in the
L<DateTimeX namespace|https://metacpan.org/search?q=datetimex> namespace, as
well as others.

See L<MetaCPAN|https://metacpan.org/search?q=datetime> for more modules.

=head1 KNOWN BUGS

The tests in F<20infinite.t> seem to fail on some machines, particularly on
Win32. This appears to be related to Perl's internal handling of IEEE infinity
and NaN, and seems to be highly platform/compiler/phase of moon dependent.

If you don't plan to use infinite datetimes you can probably ignore this. This
will be fixed (perhaps) in future versions.

=head1 SEE ALSO

L<A Date with Perl|http://presentations.houseabsolute.com/a-date-with-perl/> -
a talk I've given at a few YAPCs.

L<datetime@perl.org mailing list|http://lists.perl.org/list/datetime.html>

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/DateTime.pm/issues>.

There is a mailing list available for users of this distribution,
L<mailto:datetime@perl.org>.

=head1 SOURCE

The source code repository for DateTime can be found at L<https://github.com/houseabsolute/DateTime.pm>.

=head1 DONATIONS

If you'd like to thank me for the work I've done on this module, please
consider making a "donation" to me via PayPal. I spend a lot of free time
creating free software, and would appreciate any support you'd care to offer.

Please note that B<I am not suggesting that you must do this> in order for me
to continue working on this particular software. I will continue to do so,
inasmuch as I have in the past, for as long as it interests me.

Similarly, a donation made in this way will probably not make me work on this
software much more, unless I get so many donations that I can consider working
on free software full time (let's all have a chuckle at that together).

To donate, log into PayPal and send money to autarch@urth.org, or use the
button at L<https://houseabsolute.com/foss-donations/>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 CONTRIBUTORS

=for stopwords Ben Bennett Christian Hansen Daisuke Maki Dan Book Stewart David Dyck E. Wheeler Precious Doug Bell Flávio Soibelmann Glock Gianni Ceccarelli Gregory Oschwald Hauke D Iain Truskett James Raspass Jason McIntosh Joshua Hoblitt Karen Etheridge Mark Overmeer Michael Conrad R. Davis Mohammad S Anwar M Somerville Nick Tonkin Olaf Alders Ovid Paul Howarth Philippe Bruhat (BooK) philip r brenan Ricardo Signes Richard Bowen Ron Hill Sam Kington viviparous

=over 4

=item *

Ben Bennett <fiji@limey.net>

=item *

Christian Hansen <chansen@cpan.org>

=item *

Daisuke Maki <dmaki@cpan.org>

=item *

Dan Book <grinnz@gmail.com>

=item *

Dan Stewart <danielandrewstewart@gmail.com>

=item *

David Dyck <david.dyck@checksum.com>

=item *

David E. Wheeler <david@justatheory.com>

=item *

David Precious <davidp@preshweb.co.uk>

=item *

Doug Bell <madcityzen@gmail.com>

=item *

Flávio Soibelmann Glock <fglock@gmail.com>

=item *

Gianni Ceccarelli <gianni.ceccarelli@broadbean.com>

=item *

Gregory Oschwald <oschwald@gmail.com>

=item *

Hauke D <haukex@zero-g.net>

=item *

Iain Truskett <deceased>

=item *

James Raspass <jraspass@gmail.com>

=item *

Jason McIntosh <jmac@jmac.org>

=item *

Joshua Hoblitt <jhoblitt@cpan.org>

=item *

Karen Etheridge <ether@cpan.org>

=item *

Mark Overmeer <mark@overmeer.net>

=item *

Michael Conrad <mike@nrdvana.net>

=item *

Michael R. Davis <mrdvt92@users.noreply.github.com>

=item *

Mohammad S Anwar <mohammad.anwar@yahoo.com>

=item *

M Somerville <dracos@users.noreply.github.com>

=item *

Nick Tonkin <1nickt@users.noreply.github.com>

=item *

Olaf Alders <olaf@wundersolutions.com>

=item *

Ovid <curtis_ovid_poe@yahoo.com>

=item *

Paul Howarth <paul@city-fan.org>

=item *

Philippe Bruhat (BooK) <book@cpan.org>

=item *

philip r brenan <philiprbrenan@gmail.com>

=item *

Ricardo Signes <rjbs@cpan.org>

=item *

Richard Bowen <bowen@cpan.org>

=item *

Ron Hill <rkhill@cpan.org>

=item *

Sam Kington <github@illuminated.co.uk>

=item *

viviparous <viviparous@prc>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2003 - 2025 by Dave Rolsky.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
