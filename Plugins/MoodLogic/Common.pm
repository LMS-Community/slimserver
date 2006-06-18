package Plugins::MoodLogic::Common;

# $Id$

use strict;
use Slim::Utils::Misc;

my $last_error = 0;
	
sub OLEError {
	$::d_moodlogic && msg(Win32::OLE->LastError() . "\n");
}

sub DESTROY {
	Win32::OLE->Uninitialize();
}

sub event_hook {
	my ($mixer,$event,@args) = @_;
	return if ($event eq "TaskProgress");
	$last_error = $args[0]->Value();
	print "MoodLogic Error Event triggered: '$event',".join(",", $args[0]->Value())."\n";
	print $mixer->ErrorDescription()."\n";
}

sub checkDefaults {

	if (!Slim::Utils::Prefs::isDefined('moodlogic')) {
		Slim::Utils::Prefs::set('moodlogic',0)
	}
	
	if (!Slim::Utils::Prefs::isDefined('moodlogicscaninterval')) {
		Slim::Utils::Prefs::set('moodlogicscaninterval',60)
	}
	
	if (!Slim::Utils::Prefs::isDefined('MoodLogicplaylistprefix')) {
		Slim::Utils::Prefs::set('MoodLogicplaylistprefix','MoodLogic: ');
	}
	
	if (!Slim::Utils::Prefs::isDefined('MoodLogicplaylistsuffix')) {
		Slim::Utils::Prefs::set('MoodLogicplaylistsuffix','');
	}
	
	if (!Slim::Utils::Prefs::isDefined('instantMixMax')) {
		Slim::Utils::Prefs::set('instantMixMax',12);
	}
	
	if (!Slim::Utils::Prefs::isDefined('varietyCombo')) {
		Slim::Utils::Prefs::set('varietyCombo',50);
	}
}

1;

__END__