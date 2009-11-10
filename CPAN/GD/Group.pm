package GD::Group;

# Simple object for recursive grouping. Does absolutely nothing with GD,
# but works nicely with GD::SVG.

use strict;

our $AUTOLOAD;
our $VERSION = 1.00;

sub AUTOLOAD {
    my ($pack,$func_name) = $AUTOLOAD =~ /(.+)::([^:]+)$/;
    my $this = shift;
    $this->{gd}->currentGroup($this->{group});
    $this->{gd}->$func_name(@_);
}

sub new {
    my $this        = shift;
    my ($gd,$group) = @_;
    return bless {gd    => $gd,
		  group => $group},ref $this || $this;
}

sub DESTROY {
    my $this = shift;
    my $gd   = $this->{gd};
    my $grp  = $this->{group};
    $gd->endGroup($grp);
}


1;
