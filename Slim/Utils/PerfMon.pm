package Slim::Utils::PerfMon;

# Package to add simple 'bucket' based logging to SlimServer
# Used to store the distibution of values logged plus min/avg/max
# May also set high and low warning levels which trigger a msg() 

# $Id$

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Slim::Utils::Misc;

sub new {
	my $class = shift;

	my $ref = {};
	bless $ref, $class;

	return adjust($ref,@_);
}

sub adjust {
	my ($ref, $name, $buckets, $warnLow, $warnHigh) = @_;

	$ref->{name} = $name;
	$ref->{total} = 0;
	$ref->{over} = 0;
	$ref->{max} = 0;
	$ref->{min} = 0;
	$ref->{sum} = 0;
	$ref->{array} = [];
	$ref->{warnlo} = undef;
	$ref->{warnhi} = undef;

    for my $entry (0..$#{$buckets}) {
		$ref->{array}[$entry]->{val} = 0;
		$ref->{array}[$entry]->{thres} = @$buckets[$entry];
    }

	$ref->{warnlo} = $warnLow if $warnLow;
	$ref->{warnhi} = $warnHigh if $warnHigh;

	return $ref;
}

sub setWarnLow {
	my $ref = shift || return;
	my $val = shift;

	$ref->{warnlo} = $val;
}

sub setWarnHigh {
	my $ref = shift || return;
	my $val = shift;

	$ref->{warnhi} = $val;
}

sub clear {
	my $ref = shift;

	$ref->{total} = 0;
	$ref->{over} = 0; 
	$ref->{max} = 0;
	$ref->{min} = undef;
	$ref->{sum} = 0;

	my @array = @{$ref->{array}};
	for my $entry (0..$#array) {
		$array[$entry]->{val} = 0;
	}
}	
	
sub log {
	my $ref = shift;
	my $val = shift;

	$ref->{total}++;
	$ref->{sum} += $val;
	$ref->{max} = $val if ($val > $ref->{max});
	$ref->{min} = $val if (!defined($ref->{min}) || ($val < $ref->{min}));

	$ref->{warnlo} && ($val < $ref->{warnlo}) && msg($ref->{name}." below threshold: ".$val."\n");
	$ref->{warnhi} && ($val > $ref->{warnhi}) && msg($ref->{name}." above threshold: ".$val."\n");

	my @array = @{$ref->{array}};
	for my $entry (0..$#array) {
		if ($array[$entry]->{thres} > $val) {
			$array[$entry]->{val}++;
			return;
		}
	}
	$ref->{over}++;
}

sub sprint {
	my $ref = shift;
	my $displayTitle = shift;

	my $str = '';

	my $total = $ref->{total} || return $str;

	$str .= $ref->{name}.":\n" if $displayTitle;

	my @array = @{$ref->{array}};
	for my $entry (0..$#array) {
		my $val = $array[$entry]->{val};
		my $percent = $val/$total*100;
		$str .= sprintf "%8s : %8d :%3.0f%% %s\n","< ".$array[$entry]->{thres}, $val, $percent, "#" x ($percent/2);
	}
	$str .= sprintf "%8s : %8d :%3.0f%% %s\n", ">=".$array[$#array]->{thres},$ref->{over}, $ref->{over}/$total*100, "#" x ($ref->{over}/$total*100/2);
	$str .= sprintf "    max  : %8f\n", $ref->{max};
	$str .= sprintf "    min  : %8f\n", $ref->{min};
	$str .= sprintf "    avg  : %8f\n", $ref->{sum}/$ref->{total};

	return $str
}

sub print {
	print sprint(@_);
}

sub above {
	my $ref = shift;
	my $val = shift;

	my $count = $ref->{over};

	my @array = @{$ref->{array}};
	for my $entry (0..$#array) {
		if ($array[$entry]->{thres} > $val) {
			$count += $array[$entry]->{val};
		}
	}
	return $count;
}

sub below {
	my $ref = shift;
	my $val = shift;

	my $count = 0;

	my @array = @{$ref->{array}};
	for my $entry (0..$#array) {
		if ($array[$entry]->{thres} <= $val) {
			$count += $array[$entry]->{val};
		}
	}
	return $count;
}

sub percentAbove {
	my $ref = shift;
	my $val = shift;

	my $total = $ref->{total} || return 0;
	return $ref->above($val)/$total*100;
}

sub percentBelow {
	my $ref = shift;
	my $val = shift;

	my $total = $ref->{total} || return 0;
	return $ref->below($val)/$total*100;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

