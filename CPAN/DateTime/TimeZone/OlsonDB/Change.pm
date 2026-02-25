package DateTime::TimeZone::OlsonDB::Change;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '2.66';

sub new {
    my $class = shift;
    my %p     = @_;

    # These are almost always mutually exclusive, except when adding
    # an observance change and the last rule has no offset, but the
    # new observance has an anonymous rule.  In that case, prefer the
    # offset from std defined in the observance to that in the
    # previous rule (what a mess!).
    if ( $p{type} eq 'observance' ) {
        $p{offset_from_std} = $p{rule}->offset_from_std if defined $p{rule};
        $p{offset_from_std} = $p{observance}->offset_from_std
            if $p{observance}->offset_from_std;
        $p{offset_from_std} ||= 0;
    }
    else {
        $p{offset_from_std} = $p{observance}->offset_from_std;
        $p{offset_from_std} = $p{rule}->offset_from_std if defined $p{rule};
    }

    $p{offset_from_utc} = $p{observance}->offset_from_utc;

    $p{is_dst} = 0;
    $p{is_dst} = 1 if $p{rule} && $p{rule}->offset_from_std;
    $p{is_dst} = 1 if $p{observance}->offset_from_std;

    if ( $p{short_name} =~ m{([\-\+\w]+)/([\-\+\w]+)} ) {
        $p{short_name} = $p{is_dst} ? $2 : $1;
    }

    return bless \%p, $class;
}

sub utc_start_datetime   { $_[0]->{utc_start_datetime} }
sub local_start_datetime { $_[0]->{local_start_datetime} }
sub short_name           { $_[0]->{short_name} }
sub is_dst               { $_[0]->{is_dst} }
sub observance           { $_[0]->{observance} }
sub rule                 { $_[0]->{rule} }
sub offset_from_utc      { $_[0]->{offset_from_utc} }
sub offset_from_std      { $_[0]->{offset_from_std} }
sub total_offset         { $_[0]->offset_from_utc + $_[0]->offset_from_std }

sub two_changes_as_span {
    my ( $c1, $c2 ) = @_;

    my ( $utc_start, $local_start );

    if ( defined $c1->utc_start_datetime ) {
        $utc_start   = $c1->utc_start_datetime->utc_rd_as_seconds;
        $local_start = $c1->local_start_datetime->utc_rd_as_seconds;
    }
    else {
        $utc_start = $local_start = '-inf';
    }

    my $utc_end   = $c2->utc_start_datetime->utc_rd_as_seconds;
    my $local_end = $utc_end + $c1->total_offset;

    return {
        utc_start   => $utc_start,
        utc_end     => $utc_end,
        local_start => $local_start,
        local_end   => $local_end,
        short_name  => $c1->short_name,
        offset      => $c1->total_offset,
        is_dst      => $c1->is_dst,
    };
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines, InputOutput::RequireCheckedSyscalls)
sub _debug_output {
    my $self = shift;

    my $obs = $self->observance;

    if ( $self->utc_start_datetime ) {
        print ' UTC:        ', $self->utc_start_datetime->datetime,   "\n";
        print ' Local:      ', $self->local_start_datetime->datetime, "\n";
    }
    else {
        print " First change (starts at -inf)\n";
    }

    print ' Short name: ', $self->short_name, "\n";
    printf " UTC offset: %s (%s)\n", $obs->offset_from_utc,
        $obs->offset_from_utc_as_hm;

    if ( $obs->offset_from_std || $self->rule ) {
        if ( $obs->offset_from_std ) {
            printf " Std offset: %s (%s)\n", $obs->offset_from_std,
                $obs->offset_from_std_as_hm;
        }

        if ( $self->rule ) {
            printf " Std offset: %s (%s) - %s rule\n",
                $self->rule->offset_from_std,
                $self->rule->offset_from_std_as_hm,
                $self->rule->name;
        }
    }
    else {
        print " Std offset: 0 - no rule\n";
    }

    print "\n";
}
## use critic

1;
