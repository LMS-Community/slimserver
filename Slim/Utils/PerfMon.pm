package Slim::Utils::PerfMon;


# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Slim::Utils::Log;
use Slim::Utils::PerlRunTime;

my $log = logger('perfmon');

my $monitors = {
	timer    => 'Timer',
	io       => 'IO',
	anyevent => 'AnyEvent CB',
	request  => 'Request',
	notify   => 'Notify',
	scheduler=> 'Scheduler',
	async    => 'Async HTTP',
	template => 'Template',
	dbaccess => 'DB Access',
	web      => 'Page Build',
	ir       => 'IR Delay',
};

my $thresh = {}; # thresholds per enabled monitor

sub init {
	my $class   = shift;
	my $cmdline = shift;

	if ($cmdline && $cmdline =~ /^\d+$|^\d+\.\d+$/) {

		for my $mon (keys %$monitors) {
			$thresh->{$mon} = $cmdline;
		}

	} elsif ($cmdline && $cmdline =~ /=/) {

		for my $statement (split /\s*,\s*/, $cmdline) {
			my ($name, $val) = split /=/, $statement;
			if (exists $monitors->{$name}) {
				$thresh->{$name} = $val;
			} else {
				$log->warn("unknown monitor: $name");
			}
		}

	} else {

		$log->warn("Valid perfwarn options: [--perfwarn=<threshold secs>] | [--perfwarn <monitor1>=<threshold1>,<monitor2>=<threshold2>,...]");
		$log->warn(" Monitors: ", join(", ", sort keys %$monitors));
	}

	for my $mon (keys %$thresh) {
		$log->warn(sprintf("Logging %-12s > %8.5fs", $monitors->{$mon}, $thresh->{$mon}));
	}
}

sub check {
	return unless defined $thresh->{$_[1]} && $_[2] > $thresh->{$_[1]};

	my ($class, $mon, $val, $stringref, $coderef) = @_;

	my $string = sprintf("%-12s%8.5f : ", $monitors->{$mon}, $val);
	
	if ($stringref) {
		$string .= ref $stringref ? $stringref->() : $stringref;
	}
	
	if (main::INFOLOG && $coderef) {
		$string .= Slim::Utils::PerlRunTime::realNameForCodeRef($coderef);
	}
	
	$log->warn($string);
}


1;
