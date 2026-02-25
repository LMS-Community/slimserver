package DateTime::Types;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '1.66';

use parent 'Specio::Exporter';

use Specio 0.50;
use Specio::Declare;
use Specio::Library::Builtins -reexport;
use Specio::Library::Numeric -reexport;
use Specio::Library::String;

any_can_type(
    'ConvertibleObject',
    methods => ['utc_rd_values'],
);

declare(
    'DayOfMonth',
    parent => t('Int'),
    inline => sub {
        $_[0]->parent->inline_check( $_[1] )
            . " && $_[1] >= 1 && $_[1] <= 31";
    },
);

declare(
    'DayOfYear',
    parent => t('Int'),
    inline => sub {
        $_[0]->parent->inline_check( $_[1] )
            . " && $_[1] >= 1 && $_[1] <= 366";
    },
);

object_isa_type(
    'Duration',
    class => 'DateTime::Duration',
);

enum(
    'EndOfMonthMode',
    values => [qw( wrap limit preserve )],
);

any_can_type(
    'Formatter',
    methods => ['format_datetime'],
);

my $locale_object = declare(
    'LocaleObject',
    parent => t('Object'),
    inline => sub {

        # Can't use $_[1] directly because 5.8 gives very weird errors
        my $var = $_[1];
        <<"EOF";
(
    $var->isa('DateTime::Locale::FromData')
    || $var->isa('DateTime::Locale::Base')
)
EOF
    },
);

union(
    'Locale',
    of => [ t('NonEmptySimpleStr'), $locale_object ],
);

my $time_zone_object = object_can_type(
    'TZObject',
    methods => [
        qw(
            is_floating
            is_utc
            name
            offset_for_datetime
            short_name_for_datetime
        )
    ],
);

declare(
    'TimeZone',
    of => [ t('NonEmptySimpleStr'), $time_zone_object ],
);

declare(
    'Hour',
    parent => t('PositiveOrZeroInt'),
    inline => sub {
        $_[0]->parent->inline_check( $_[1] )
            . " && $_[1] >= 0 && $_[1] <= 23";
    },
);

declare(
    'Minute',
    parent => t('PositiveOrZeroInt'),
    inline => sub {
        $_[0]->parent->inline_check( $_[1] )
            . " && $_[1] >= 0 && $_[1] <= 59";
    },
);

declare(
    'Month',
    parent => t('PositiveInt'),
    inline => sub {
        $_[0]->parent->inline_check( $_[1] )
            . " && $_[1] >= 1 && $_[1] <= 12";
    },
);

declare(
    'Nanosecond',
    parent => t('PositiveOrZeroInt'),
);

declare(
    'Second',
    parent => t('PositiveOrZeroInt'),
    inline => sub {
        $_[0]->parent->inline_check( $_[1] )
            . " && $_[1] >= 0 && $_[1] <= 61";
    },
);

enum(
    'TruncationLevel',
    values => [
        qw(
            year
            quarter
            month
            day hour
            minute
            second
            nanosecond
            week
            local_week
        )
    ],
);

declare(
    'Year',
    parent => t('Int'),
);

1;

# ABSTRACT: Types used for parameter checking in DateTime

__END__

=pod

=encoding UTF-8

=head1 NAME

DateTime::Types - Types used for parameter checking in DateTime

=head1 VERSION

version 1.66

=head1 DESCRIPTION

This module has no user-facing parts.

=for Pod::Coverage .*

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
