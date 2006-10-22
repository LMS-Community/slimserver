package Plugins::MoodLogic::Common;

# $Id$

use strict;
use Slim::Utils::Log;

my $last_error = 0;

sub OLEError {

	logError(Win32::OLE->LastError);
}

sub DESTROY {
	Win32::OLE->Uninitialize();
}

sub event_hook {
	my ($mixer, $event, @args) = @_;

	if ($event eq "TaskProgress") {
		return;
	}

	$last_error = $args[0]->Value();

	logError("triggered: '$event', ", join(',', $args[0]->Value));
	logError("", $mixer->ErrorDescription);
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
