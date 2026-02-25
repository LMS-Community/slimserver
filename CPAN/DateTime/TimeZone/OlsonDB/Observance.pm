package DateTime::TimeZone::OlsonDB::Observance;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '2.66';

use DateTime::Duration;
use DateTime::TimeZone::OlsonDB;
use DateTime::TimeZone::OlsonDB::Change;
use List::Util 1.33 qw( any first );

sub new {
    my $class = shift;
    my %p     = @_;

    $p{until} ||= q{};
    $p{$_} ||= 0
        for qw( offset_from_std last_offset_from_std last_offset_from_utc );

    my $offset_from_utc
        = $p{gmtoff} =~ m/^[+-]?\d?\d$/ # only hours? need to handle specially
        ? 3600 * $p{gmtoff}
        : DateTime::TimeZone::offset_as_seconds( $p{gmtoff} );

    my $offset_from_std
        = DateTime::TimeZone::offset_as_seconds( $p{offset_from_std} );

    my $last_offset_from_utc = delete $p{last_offset_from_utc};
    my $last_offset_from_std = delete $p{last_offset_from_std};

    my $self = bless {
        %p,
        offset_from_utc => $offset_from_utc,
        offset_from_std => $offset_from_std,
        until           => [ split /\s+/, $p{until} ],
    }, $class;

    $self->{first_rule}
        = $self->_first_rule( $last_offset_from_utc, $last_offset_from_std );

    if ( $p{utc_start_datetime} ) {
        $offset_from_std += $self->{first_rule}->offset_from_std
            if $self->{first_rule};

        my $local_start_datetime = $p{utc_start_datetime}->clone;

        $local_start_datetime += DateTime::Duration->new(
            seconds => $offset_from_utc + $offset_from_std );

        $self->{local_start_datetime} = $local_start_datetime;
    }

    return $self;
}

sub offset_from_utc { $_[0]->{offset_from_utc} || 0 }
sub offset_from_std { $_[0]->{offset_from_std} || 0 }
sub total_offset    { $_[0]->offset_from_utc + $_[0]->offset_from_std }

sub offset_from_utc_as_hm {
    my $offset = $_[0]->offset_from_utc;
    my $h      = int( $offset / 3600 );
    my $m      = ( $offset % 3600 ) / 60;
    return sprintf( '%02d:%02d', $h, $m );
}

sub offset_from_std_as_hm {
    my $offset = $_[0]->offset_from_std;
    my $h      = int( $offset / 3600 );
    my $m      = ( $offset % 3600 ) / 60;
    return sprintf( '%02d:%02d', $h, $m );
}

sub rules      { @{ $_[0]->{rules} } }
sub first_rule { $_[0]->{first_rule} }

## no critic (Subroutines::ProhibitBuiltinHomonyms)
sub format { $_[0]->{format} }
## use critic

sub utc_start_datetime   { $_[0]->{utc_start_datetime} }
sub local_start_datetime { $_[0]->{local_start_datetime} }

sub formatted_short_name {
    my $self   = shift;
    my $letter = shift;
    my $rule   = shift;

    my $format = $self->format;
    return $format unless $format =~ /%/;

    if ( $format eq '%z' ) {
        return $self->offset_as_z_format($rule);
    }

    return sprintf( $format, $letter );
}

sub offset_as_z_format {
    my $self = shift;
    my $rule = shift;

    my $offset = $self->total_offset;
    $offset += $rule->offset_from_std if $rule;
    my $sign = $offset < 0 ? '-' : '+';
    $offset = abs($offset);
    my $h = int( $offset / 3600 );
    my $m = ( $offset % 3600 ) / 60;
    if ( $m == 0 ) {
        return sprintf( '%s%02d', $sign, $h );
    }
    return sprintf( '%s%02d%02d', $sign, $h, $m );
}

sub expand_from_rules {
    my $self = shift;
    my $zone = shift;

    # real max is year + 1 so we include max year
    my $max_year = (shift) + 1;

    my $min_year;

    if ( $self->utc_start_datetime ) {
        $min_year = $self->utc_start_datetime->year;
    }
    else {

        # There is at least one time zone that has an infinite
        # observance, but that observance has rules that only start at
        # a certain point - Pacific/Chatham

        # In this case we just find the earliest rule and start there

        $min_year
            = ( sort { $a <=> $b } map { $_->min_year } $self->rules )[0];
    }

    my $until = $self->until( $zone->last_change->offset_from_std );
    if ($until) {
        $max_year = $until->year;
    }
    else {

        # Some zones, like Asia/Tehran, have a predefined fixed set of
        # rules that go well into the future (2037 for Asia/Tehran)
        my $max_rule_year = 0;
        foreach my $rule ( $self->rules ) {
            $max_rule_year = $rule->max_year
                if $rule->max_year && $rule->max_year > $max_rule_year;
        }

        $max_year = $max_rule_year if $max_rule_year > $max_year;
    }

    foreach my $year ( $min_year .. $max_year ) {
        my @rules = $self->_sorted_rules_for_year($year);

        for my $rule (@rules) {
            my $dt = $rule->utc_start_datetime_for_year(
                $year,
                $self->offset_from_utc, $zone->last_change->offset_from_std
            );

            next
                if $self->utc_start_datetime
                && $dt <= $self->utc_start_datetime;

            ## no critic (Variables::ProhibitReusedNames)
            my $until = $self->until( $zone->last_change->offset_from_std );

            next if $until && $dt >= $until;

            my $change = DateTime::TimeZone::OlsonDB::Change->new(
                type                 => 'rule',
                utc_start_datetime   => $dt,
                local_start_datetime => $dt + DateTime::Duration->new(
                    seconds => $self->total_offset + $rule->offset_from_std
                ),
                short_name =>
                    $self->formatted_short_name( $rule->letter, $rule ),
                observance => $self,
                rule       => $rule,
            );

            if ($DateTime::TimeZone::OlsonDB::DEBUG) {
                ## no critic (InputOutput::RequireCheckedSyscalls)
                print "Adding rule change ...\n";

                $change->_debug_output;
            }

            $zone->add_change($change);
        }
    }
}

sub _sorted_rules_for_year {
    my $self = shift;
    my $year = shift;

    ## no critic (BuiltinFunctions::ProhibitComplexMappings)
    my @rules = (
        map  { $_->[0] }
        sort { $a->[1] <=> $b->[1] }
        map {
            my $dt = $_->utc_start_datetime_for_year(
                $year,
                $self->offset_from_utc, 0
            );
            [ $_, $dt ]
        }
        grep {
            $_->min_year <= $year
                && ( ( !$_->max_year ) || $_->max_year >= $year )
        } $self->rules
    );

    my %rules_by_month;
    for my $rule (@rules) {
        push @{ $rules_by_month{ $rule->month() } }, $rule;
    }

    # In some cases we have both a "max year" rule and a "this year" rule for
    # a given month's change. In that case, we want to pick the more specific
    # ("this year") rule, not apply both. This only matters for zones that
    # have a winter transition that follows the Islamic calendar to deal with
    # Ramadan. So far this has happened with Cairo, El_Aaiun, and other zones
    # in northern Africa.
    my @final_rules;
    for my $month ( sort { $a <=> $b } keys %rules_by_month ) {
        push @final_rules, @{ $rules_by_month{$month} };
    }

    return @final_rules;
}

## no critic (Subroutines::ProhibitBuiltinHomonyms)
sub until {
    my $self            = shift;
    my $offset_from_std = shift || $self->offset_from_std;

    return unless defined $self->until_year;

    my $utc = DateTime::TimeZone::OlsonDB::utc_datetime_for_time_spec(
        spec            => $self->until_time_spec,
        year            => $self->until_year,
        month           => $self->until_month,
        day             => $self->until_day,
        offset_from_utc => $self->offset_from_utc,
        offset_from_std => $offset_from_std,
    );

    return $utc;
}
## use critic

sub until_year { $_[0]->{until}[0] }

sub until_month {
    return 1 unless defined $_[0]->{until}[1];
    return $DateTime::TimeZone::OlsonDB::MONTHS{ $_[0]->{until}[1] };
}

sub until_day {
    return 1 unless defined $_[0]->{until}[2];
    my ( undef, $day ) = DateTime::TimeZone::OlsonDB::parse_day_spec(
        $_[0]->{until}[2],
        $_[0]->until_month,
        $_[0]->until_year,
    );
    return $day;
}

sub until_time_spec {
    defined $_[0]->{until}[3] ? $_[0]->{until}[3] : '00:00:00';
}

## no critic (Subroutines::ProhibitExcessComplexity)
sub _first_rule {
    my $self                 = shift;
    my $last_offset_from_utc = shift;
    my $last_offset_from_std = shift;

    return unless $self->rules;

    my $date = $self->utc_start_datetime
        or return $self->_first_no_dst_rule;

    my @rules = $self->rules;

    my %possible_rules;

    my $year = $date->year;
    foreach my $rule (@rules) {

        # We need to look at what the year _would_ be if we added the
        # rule's offset to the UTC date.  Otherwise we can end up with
        # a UTC date in year X, and a rule that starts in _local_ year
        # X + 1, where that rule really does apply to that UTC date.
        my $temp_year
            = $date->clone->add(
            seconds => $self->offset_from_utc + $rule->offset_from_std )
            ->year;

        # Save the highest value
        $year = $temp_year if $temp_year > $year;

        next if $rule->min_year > $temp_year;

        $possible_rules{$rule} = $rule;
    }

    my $earliest_year = $year - 1;
    foreach my $rule (@rules) {
        $earliest_year = $rule->min_year
            if $rule->min_year < $earliest_year;
    }

    # figure out what date each rule would start on _if_ that rule
    # were applied to this current observance.  this could be a rule
    # that started much earlier, but is only now active because of an
    # observance switch.  An obnoxious example of this is
    # America/Phoenix in 1944, which applies the US rule in April,
    # thus (re-)instating the "war time" rule from 1942.  Can you say
    # ridiculous crack-smoking stupidity?
    my @rule_dates;
    foreach my $y ( $earliest_year .. $year ) {
    RULE:
        foreach my $rule ( values %possible_rules ) {

            # skip rules that can't have applied the year before the
            # observance started.
            if ( $rule->min_year > $y ) {
                ## no critic (InputOutput::RequireCheckedSyscalls)
                print 'Skipping rule beginning in ', $rule->min_year,
                    ".  Year is $y.\n"
                    if $DateTime::TimeZone::OlsonDB::DEBUG;

                next RULE;
            }

            if ( $rule->max_year && $rule->max_year < $y ) {
                ## no critic (InputOutput::RequireCheckedSyscalls)
                print 'Skipping rule ending in ', $rule->max_year,
                    ".     Year is $y.\n"
                    if $DateTime::TimeZone::OlsonDB::DEBUG;

                next RULE;
            }

            my $rule_start = $rule->utc_start_datetime_for_year(
                $y,
                $last_offset_from_utc, $last_offset_from_std
            );

            push @rule_dates, [ $rule_start, $rule ];
        }
    }

    @rule_dates = sort { $a->[0] <=> $b->[0] } @rule_dates;

    ## no critic (InputOutput::RequireCheckedSyscalls)
    print "Looking for first rule ...\n"
        if $DateTime::TimeZone::OlsonDB::DEBUG;
    print ' Observance starts: ', $date->datetime, "\n\n"
        if $DateTime::TimeZone::OlsonDB::DEBUG;
    ## use critic

    # ... look through the rules to see if any are still in
    # effect at the beginning of the observance

    ## no critic (ControlStructures::ProhibitCStyleForLoops)
    for ( my $x = 0; $x < @rule_dates; $x++ ) {
        my ( $dt, $rule ) = @{ $rule_dates[$x] };
        my ( $next_dt, $next_rule )
            = $x < @rule_dates - 1 ? @{ $rule_dates[ $x + 1 ] } : undef;

        next if $next_dt && $next_dt < $date;

        ## no critic (InputOutput::RequireCheckedSyscalls)
        print ' This rule starts:  ', $dt->datetime, "\n"
            if $DateTime::TimeZone::OlsonDB::DEBUG;

        print ' Next rule starts:  ', $next_dt->datetime, "\n"
            if $next_dt && $DateTime::TimeZone::OlsonDB::DEBUG;

        print " No next rule\n\n"
            if !$next_dt && $DateTime::TimeZone::OlsonDB::DEBUG;
        ## use critic

        if ( $dt <= $date ) {
            if ($next_dt) {
                return $rule      if $date < $next_dt;
                return $next_rule if $date == $next_dt;
            }
            else {
                return $rule;
            }
        }
    }

    # If this observance has rules, but the rules don't have any
    # defined changes until after the observance starts, we get the
    # earliest standard time rule and use it. If there is none, shit
    # blows up (but this is not the case for any time zones as of
    # 2009a). I really, really hate the Olson database a lot of the
    # time! Could this be more arbitrary?
    my $std_time_rule = $self->_first_no_dst_rule;

    die
        q{Cannot find a rule that applies to the observance's date range and cannot find a rule without DST to apply}
        unless $std_time_rule;

    return $std_time_rule;
}
## use critic

sub _first_no_dst_rule {
    my $self = shift;

    return first { !$_->offset_from_std }
        sort { $a->min_year <=> $b->min_year } $self->rules;
}

1;
