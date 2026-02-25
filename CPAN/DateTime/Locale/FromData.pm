package DateTime::Locale::FromData;

use strict;
use warnings;
use namespace::autoclean;

use DateTime::Locale::Util qw( parse_locale_code );
use Params::ValidationCompiler 0.13 qw( validation_for );
use Specio::Declare;
use Storable qw( dclone );

our $VERSION = '1.45';

my @FormatLengths;

BEGIN {
    my @methods = qw(
        code
        name
        language
        script
        territory
        variant
        native_name
        native_language
        native_script
        native_territory
        native_variant
        am_pm_abbreviated
        date_format_full
        date_format_long
        date_format_medium
        date_format_short
        time_format_full
        time_format_long
        time_format_medium
        time_format_short
        day_format_abbreviated
        day_format_narrow
        day_format_wide
        day_stand_alone_abbreviated
        day_stand_alone_narrow
        day_stand_alone_wide
        month_format_abbreviated
        month_format_narrow
        month_format_wide
        month_stand_alone_abbreviated
        month_stand_alone_narrow
        month_stand_alone_wide
        quarter_format_abbreviated
        quarter_format_narrow
        quarter_format_wide
        quarter_stand_alone_abbreviated
        quarter_stand_alone_narrow
        quarter_stand_alone_wide
        era_abbreviated
        era_narrow
        era_wide
        default_date_format_length
        default_time_format_length
        first_day_of_week
        version
        glibc_datetime_format
        glibc_date_format
        glibc_date_1_format
        glibc_time_format
        glibc_time_12_format
    );

    for my $meth (@methods) {
        my $sub = sub { $_[0]->{$meth} };
        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict 'refs';
        *{$meth} = $sub;
    }

    @FormatLengths = qw( short medium long full );

    for my $length (@FormatLengths) {
        my $meth = 'datetime_format_' . $length;
        my $key  = 'computed_' . $meth;

        my $sub = sub {
            my $self = shift;

            return $self->{$key} if exists $self->{$key};

            return $self->{$key} = $self->_make_datetime_format($length);
        };

        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict 'refs';
        *{$meth} = $sub;
    }
}

sub new {
    my $class = shift;
    my $data  = shift;

    return bless {
        %{$data},
        default_date_format_length => 'medium',
        default_time_format_length => 'medium',
        locale_data                => $data
    }, $class;
}

sub date_format_default {
    return $_[0]->date_format_medium;
}

sub time_format_default {
    return $_[0]->time_format_medium;
}

sub datetime_format {
    return $_[0]->{datetime_format_medium};
}

sub datetime_format_default {
    return $_[0]->datetime_format_medium;
}

sub _make_datetime_format {
    my $self   = shift;
    my $length = shift;

    my $dt_key    = 'datetime_format_' . $length;
    my $date_meth = 'date_format_' . $length;
    my $time_meth = 'time_format_' . $length;

    my $dt_format = $self->{$dt_key};
    $dt_format =~ s/\{0\}/$self->$time_meth/eg;
    $dt_format =~ s/\{1\}/$self->$date_meth/eg;

    return $dt_format;
}

my $length    = enum( values => [qw( full long medium short )] );
my $validator = validation_for(
    name             => '_check_length_parameter',
    name_is_optional => 1,
    params           => [ { type => $length } ],
);

sub set_default_date_format_length {
    my $self = shift;
    my ($l) = $validator->(@_);

    $self->{default_date_format_length} = lc $l;
}

sub set_default_time_format_length {
    my $self = shift;
    my ($l) = $validator->(@_);

    $self->{default_time_format_length} = lc $l;
}

sub date_formats {
    my %formats;
    for my $length (@FormatLengths) {
        my $meth = 'date_format_' . $length;
        $formats{$length} = $_[0]->$meth;
    }
    return \%formats;
}

sub time_formats {
    my %formats;
    for my $length (@FormatLengths) {
        my $meth = 'time_format_' . $length;
        $formats{$length} = $_[0]->$meth;
    }
    return \%formats;
}

sub available_formats {
    my $self = shift;

    $self->{computed_available_formats}
        ||= [ sort keys %{ $self->_available_formats } ];

    return @{ $self->{computed_available_formats} };
}

sub format_for {
    my $self = shift;
    my $for  = shift;

    return $self->_available_formats->{$for};
}

sub _available_formats { $_[0]->{available_formats} }

sub prefers_24_hour_time {
    my $self = shift;

    return $self->{prefers_24_hour_time}
        if exists $self->{prefers_24_hour_time};

    # This regex splits the pattern into parts, but only keeps the parts that aren't quoted. This
    # lets us ignore literal strings in the pattern when looking for `h|K`. Without this we could
    # match on a literal `'h'` in the pattern (which fr-CA has at the time of this writing), giving
    # us a false positive.
    my @parts = split /(?:'(?:(?:[^']|'')*)')/, $self->time_format_short;
    return $self->{prefers_24_hour_time} = !( grep {/h|K/} @parts );
}

sub language_code {
    my $self = shift;
    return ( $self->{parsed_code} ||= { parse_locale_code( $self->code ) } )
        ->{language};
}

sub script_code {
    my $self = shift;
    return ( $self->{parsed_code} ||= { parse_locale_code( $self->code ) } )
        ->{script};
}

sub territory_code {
    my $self = shift;
    return ( $self->{parsed_code} ||= { parse_locale_code( $self->code ) } )
        ->{territory};
}

sub variant_code {
    my $self = shift;
    return ( $self->{parsed_code} ||= { parse_locale_code( $self->code ) } )
        ->{variant};
}

sub id {
    $_[0]->code;
}

sub language_id {
    $_[0]->language_code;
}

sub script_id {
    $_[0]->script_code;
}

sub territory_id {
    $_[0]->territory_code;
}

sub variant_id {
    $_[0]->variant_code;
}

sub locale_data {
    return %{ dclone( $_[0]->{locale_data} ) };
}

sub STORABLE_freeze {
    my $self    = shift;
    my $cloning = shift;

    return if $cloning;

    return $self->code;
}

sub STORABLE_thaw {
    my $self = shift;
    shift;
    my $serialized = shift;

    require DateTime::Locale;
    my $obj = DateTime::Locale->load($serialized);

    %{$self} = %{$obj};

    return $self;
}

1;

# ABSTRACT: Class for locale objects instantiated from pre-defined data

__END__

=pod

=encoding UTF-8

=head1 NAME

DateTime::Locale::FromData - Class for locale objects instantiated from pre-defined data

=head1 VERSION

version 1.45

=head1 SYNOPSIS

  my $locale = DateTime::Locale::FromData->new(%lots_of_data)

=head1 DESCRIPTION

This class is used to represent locales instantiated from the data in the
DateTime::Locale::Data module.

=head1 METHODS

This class provides the following methods:

=head2 $locale->code

The complete locale id, something like "en-US".

=head2 $locale->language_code

The language portion of the code, like "en".

=head2 $locale->script_code

The script portion of the code, like "Hant".

=head2 $locale->territory_code

The territory portion of the code, like "US".

=head2 $locale->variant_code

The variant portion of the code, like "POSIX".

=head2 $locale->name

The locale's complete name, which always includes at least a language
component, plus optional territory and variant components. Something like
"English United States". The value returned will always be in English.

=head2 $locale->language

=head2 $locale->script

=head2 $locale->territory

=head2 $locale->variant

The relevant component from the locale's complete name, like "English" or
"United States".

=head2 $locale->native_name

The locale's complete name in localized form as a UTF-8 string.

=head2 $locale->native_language

=head2 $locale->native_script

=head2 $locale->native_territory

=head2 $locale->native_variant

The relevant component from the locale's complete native name as a UTF-8
string.

=head2 $locale->month_format_wide

=head2 $locale->month_format_abbreviated

=head2 $locale->month_format_narrow

=head2 $locale->month_stand_alone_wide

=head2 $locale->month_stand_alone_abbreviated

=head2 $locale->month_stand_alone_narrow

=head2 $locale->day_format_wide

=head2 $locale->day_format_abbreviated

=head2 $locale->day_format_narrow

=head2 $locale->day_stand_alone_wide

=head2 $locale->day_stand_alone_abbreviated

=head2 $locale->day_stand_alone_narrow

=head2 $locale->quarter_format_wide

=head2 $locale->quarter_format_abbreviated

=head2 $locale->quarter_format_narrow

=head2 $locale->quarter_stand_alone_wide

=head2 $locale->quarter_stand_alone_abbreviated

=head2 $locale->quarter_stand_alone_narrow

=head2 $locale->am_pm_abbreviated

=head2 $locale->era_wide

=head2 $locale->era_abbreviated

=head2 $locale->era_narrow

These methods all return an array reference containing the specified data.

The methods with "format" in the name should return strings that can be used a
part of a string, like "the month of July". The stand alone values are for use
in things like calendars as opposed to a sentence.

The narrow forms may not be unique (for example, in the day column heading for
a calendar it's okay to have "T" for both Tuesday and Thursday).

The wide name should always be the full name of thing in question. The narrow
name should be just one or two characters.

B<These methods return a reference to the data stored in the locale object. If
you change this reference's contents, this will affect the data in the locale
object! You should clone the data first if you want to modify it.>

=head2 $locale->date_format_full

=head2 $locale->date_format_long

=head2 $locale->date_format_medium

=head2 $locale->date_format_short

=head2 $locale->time_format_full

=head2 $locale->time_format_long

=head2 $locale->time_format_medium

=head2 $locale->time_format_short

=head2 $locale->datetime_format_full

=head2 $locale->datetime_format_long

=head2 $locale->datetime_format_medium

=head2 $locale->datetime_format_short

These methods return strings appropriate for the C<< DateTime->format_cldr >>
method.

=head2 $locale->format_for($name)

These are accessed by passing a name to C<< $locale->format_for(...)  >>, where
the name is a CLDR-style format specifier.

The return value is a string suitable for passing to C<< $dt->format_cldr >>,
so you can do something like this:

  print $dt->format_cldr( $dt->locale->format_for('MMMdd') )

which for the "en" locale would print out something like "08 Jul".

Note that the localization may also include additional text specific to the
locale. For example, the "MMMMd" format for the "zh" locale includes the
Chinese characters for "day" (日) and month (月), so you get something like
"S<8月23日>".

=head2 $locale->available_formats

This should return a list of all the format names that could be passed to C<<
$locale->format_for >>.

See the documentation for individual locales for details and examples of these
formats. The format names that are available vary by locale.

=head2 $locale->glibc_datetime_format

=head2 $locale->glibc_date_format

=head2 $locale->glibc_date_1_format

=head2 $locale->glibc_time_format

=head2 $locale->glibc_time_12_format

These methods return strings appropriate for the C<< DateTime->strftime >>
method. However, you are strongly encouraged to use the other format methods,
which use the CLDR format data. They are primarily included for the benefit for
L<DateTime::Format::Strptime>.

=head2 $locale->version

The CLDR version from which this locale was generated.

=head2 $locale->prefers_24_hour_time

Returns a boolean indicating whether or not the locale prefers 24-hour time.

=head2 $locale->first_day_of_week

Returns a number from 1 to 7 indicating the I<local> first day of the week,
with Monday being 1 and Sunday being 7.

=head2 $locale->locale_data

Returns a clone of the original data used to create this locale as a hash. This
is here to facilitate creating custom locales via
C<DateTime::Locale->register_data_locale>.

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/DateTime-Locale/issues>.

There is a mailing list available for users of this distribution,
L<mailto:datetime@perl.org>.

=head1 SOURCE

The source code repository for DateTime-Locale can be found at L<https://github.com/houseabsolute/DateTime-Locale>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2003 - 2025 by Dave Rolsky.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
