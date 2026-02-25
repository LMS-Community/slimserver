package DateTime::TimeZone::OlsonDB::Zone;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '2.66';

use DateTime::TimeZone;
use DateTime::TimeZone::OlsonDB;
use DateTime::TimeZone::OlsonDB::Change;
use DateTime::TimeZone::OlsonDB::Observance;
use List::Util qw( first max );

sub new {
    my $class = shift;
    my %p     = @_;

    my $self = {
        name           => $p{name},
        observances    => $p{observances},
        changes        => [],
        infinite_rules => {},
    };

    return bless $self, $class;
}

sub name { $_[0]->{name} }

sub last_rules_year {
    my $self = shift;
    my $odb  = shift;

    my $last_rule = $self->{observances}[-1]{rules};

    return unless $last_rule;

    my @rules = $odb->rules_by_name($last_rule);

    return $rules[-1]->min_year();
}

sub expand_observances {
    my $self     = shift;
    my $odb      = shift;
    my $max_year = shift;

    my $prev_until;
    ## no critic (ControlStructures::ProhibitCStyleForLoops)
    for ( my $x = 0; $x < @{ $self->{observances} }; $x++ ) {
        my %p = %{ $self->{observances}[$x] };

        my $rules_name = delete $p{rules};

        my $last_offset_from_std
            = $self->last_change ? $self->last_change->offset_from_std : 0;
        my $last_offset_from_utc
            = $self->last_change ? $self->last_change->offset_from_utc : 0;

        my $obs = DateTime::TimeZone::OlsonDB::Observance->new(
            %p,
            utc_start_datetime   => $prev_until,
            rules                => [ $odb->rules_by_name($rules_name) ],
            last_offset_from_utc => $last_offset_from_utc,
            last_offset_from_std => $last_offset_from_std,
        );

        my $rule   = $obs->first_rule;
        my $letter = $rule ? $rule->letter : q{};

        my $change = DateTime::TimeZone::OlsonDB::Change->new(
            type                 => 'observance',
            utc_start_datetime   => $obs->utc_start_datetime,
            local_start_datetime => $obs->local_start_datetime,
            short_name => $obs->formatted_short_name( $letter, $rule ),
            observance => $obs,
            $rule ? ( rule => $rule ) : (),
        );

        if ($DateTime::TimeZone::OlsonDB::DEBUG) {
            ## no critic (InputOutput::RequireCheckedSyscalls)
            print "Adding observance change ...\n";

            $change->_debug_output;
        }

        $self->add_change($change);

        if ( $obs->rules ) {
            $obs->expand_from_rules( $self, $max_year );
        }

        $prev_until = $obs->until(
            $self->last_change ? $self->last_change->offset_from_std : 0 );

        # last observance
        if ( $x == $#{ $self->{observances} } ) {
            foreach my $rule ( $obs->rules ) {
                if ( $rule->is_infinite ) {
                    $self->add_infinite_rule($rule);
                }
            }
        }
    }
}

sub add_change {
    my $self   = shift;
    my $change = shift;

    if ( defined $change->utc_start_datetime ) {
        if (   @{ $self->{changes} }
            && $self->{changes}[-1]->utc_start_datetime
            && $self->{changes}[-1]->utc_start_datetime
            == $change->utc_start_datetime ) {
            if ( $self->{changes}[-1]->rule && $change->observance ) {
                ## no critic (InputOutput::RequireCheckedSyscalls)
                print
                    " Ignoring previous rule change, that starts the same time as current observance change\n\n"
                    if $DateTime::TimeZone::OlsonDB::DEBUG;

                $self->{changes}[-1] = $change;

                return;
            }

            die
                "Cannot add two different changes that have the same UTC start datetime!\n";
        }

        my $last_change = $self->last_change;

        if (   $last_change->short_name eq $change->short_name
            && $last_change->total_offset == $change->total_offset
            && $last_change->is_dst == $change->is_dst ) {
            my $last_rule = $last_change->rule || q{};
            my $new_rule  = $change->rule      || q{};

            ## no critic (InputOutput::RequireCheckedSyscalls)
            print "Skipping identical change\n"
                if $DateTime::TimeZone::OlsonDB::DEBUG;
            return;
        }

        push @{ $self->{changes} }, $change;
    }
    else {
        if ( $self->{earliest} ) {
            die 'There can only be one earliest time zone change!';
        }
        else {
            $self->{earliest} = $change;
        }
    }
}

sub add_infinite_rule {
    $_[0]->{infinite_rules}{ $_[1] } = $_[1];
}

sub last_change {
    return unless @{ $_[0]->{changes} } || $_[0]->{earliest};
    return (
        @{ $_[0]->{changes} }
        ? $_[0]->{changes}[-1]
        : $_[0]->{earliest}
    );
}

sub sorted_changes {
    (
        ( defined $_[0]->{earliest} ? $_[0]->{earliest} : () ),
        sort { $a->utc_start_datetime <=> $b->utc_start_datetime }
            @{ $_[0]->{changes} }
    );
}

sub infinite_rules {
    my @v = sort { $a->min_year <=> $b->min_year || $a->month cmp $b->month }
        values %{ $_[0]->{infinite_rules} };
    return @v;
}

1;
