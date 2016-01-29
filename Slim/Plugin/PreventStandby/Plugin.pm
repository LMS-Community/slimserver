package Slim::Plugin::PreventStandby::Plugin;

# $Id: Plugin.pm 11021 2006-12-21 22:28:39Z dsully $

# PreventStandby.pm by Julian Neil (julian.neil@internode.on.net)
#
# Prevent the server machine from going into standby when it is streaming
# music to any clients.
#
# Excuse my perl.. first time I've ever used it.
#
# Thanks to the PowerSave plugin by Jason Holtzapplefor some basics,
# to various ppl on the slim forums and to CPAN and the Win32::API module.
#
#-> Changelog
#
# 1.0 - 2006-04-05 - Initial Release
#
# 2.0 - 2009-01-03 - Proposed changes by Gordon Harris to address bug 8520:
#
#                    http://bugs.slimdevices.com/show_bug.cgi?id=8520
#
#                    Added "idletime" feature -- waits at least $idletime number
#                    of idle player intervals before allowing standby.  Also, is
#                    "resume aware" -- resets the idle counter on system resume
#                    from standby or hibernation.
#
#       2009-01-12 - Cleaned up some content in strings.txt, added optional check
#                    power feature to mimic Nigel Burch's proposed patch behavior.
#
# 3.0 - 2012-08-26 - add support for OSX, plus infrastructure to add more

use strict;
use Time::HiRes;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::OSDetect;

if ( main::WEBUI ) {
	require Slim::Plugin::PreventStandby::Settings;
}


# How many seconds between checks for busy clients..
# Reduce this value when testing, unless you are very patient.
use constant INTERVAL => 60;

# time() we last checked for client activity
my $lastchecktime = time;

# Number of intervals that the cliets have been idle.
my $hasbeenidle = 0;
my ($handler, $pollInterval);

my $prefs = preferences('plugin.preventstandby');

$prefs->migrate(1, sub {
	require Slim::Utils::Prefs::OldPrefs;
	$prefs->set('idletime', Slim::Utils::Prefs::OldPrefs->get('idletime') || 20);
	$prefs->set('checkpower', Slim::Utils::Prefs::OldPrefs->get('checkpower') || 0);
	1;
});

$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 0, 'high' => 240 }, 'idletime');
$prefs->setChange(\&idletime_change, 'idletime');
$prefs->setChange(\&checkpower_change, 'checkpower');


my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.preventstandby',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});


sub getDisplayName {
	return 'PLUGIN_PREVENTSTANDBY';
}

sub initPlugin {
	if (main::ISWINDOWS) {
		require Slim::Plugin::PreventStandby::Win32;
		$handler = Slim::Plugin::PreventStandby::Win32->new();
	}
	
	elsif ($^O =~/darwin/i) {
		require Slim::Plugin::PreventStandby::OSX;
		$handler = Slim::Plugin::PreventStandby::OSX->new();
	}
	
	if (!$handler) {
		$log->warn("Failed to initialize plugin - can't prevent standby mode.");
		return;
	}
	
	if ( main::WEBUI ) {
		Slim::Plugin::PreventStandby::Settings->new;
	}

	if ( main::DEBUGLOG ) {
		if (my $idletime = $prefs->get('idletime')) {
			$log->debug("System standby now allowed after $idletime minutes of player idle time.")
		}
		else {
			$log->debug("System standby now prohibited.")
		}
	}
	
	$pollInterval = $handler->pollInterval || INTERVAL;

	checkClientActivity();
}


sub checkClientActivity {
	my $currenttime = time();

	# Reset the idle countdown counter if 1). scanning, 2). firmware updating or playing, or
	# 3). time-shift (i.e. DST system time change) or we've resumed from standby or hibernation..
	my $idletime = $prefs->get('idletime');
	
	if ($idletime) {
		$idletime *= 60;
		
		if ( Slim::Music::Import->stillScanning() || $handler->isBusy($currenttime) ) {
			
			$hasbeenidle = 0;
			main::DEBUGLOG && $log->is_debug && $log->debug("Resetting idle counter.    " . (($idletime - $hasbeenidle) / 60) . " minutes left in allowed idle period.");
		}
		
		else {
			
			$hasbeenidle += $pollInterval;
			
			if ($hasbeenidle < $idletime) {
				main::DEBUGLOG && $log->is_debug && $log->debug("Incrementing idle counter. " . (($idletime - $hasbeenidle) / 60) . " minutes left in allowed idle period.");
			}
		}
	}
	
	# If idletime is set to zero in settings, ALWAYS prevent standby..
	# Otherwise, only prevent standby if we're still in the idle time-out period..
	if ( (!$idletime) || $hasbeenidle < $idletime) {
		
		main::INFOLOG && $log->is_info && $log->info("Preventing System Standby...");
		$handler->setBusy($currenttime);
	}
	
	else {
		main::INFOLOG && $log->is_info && $log->info("Players have been idle for " . ($hasbeenidle / 60) . " minutes. Allowing System Standby...");
		$handler->setIdle($currenttime);
	}

	$lastchecktime = $currenttime;
	
	Slim::Utils::Timers::killTimers( undef, \&checkClientActivity );
	Slim::Utils::Timers::setTimer(
		undef, 
		time + $pollInterval, 
		\&checkClientActivity
	);

	return 1;
}

sub _playersBusy {
	
	my $checkpower = $prefs->get('checkpower');
	
	for my $client (Slim::Player::Client::clients()) {
		
		if ($checkpower && $client->power()) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Player " . $client->name() . " is powered " . ($client->power() ? "on" : "off") . "...");
			return 1;
		}
		
		if ( $client->isUpgrading() || $client->isPlaying() || (Time::HiRes::time() - $client->lastActivityTime <= INTERVAL) ) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Player " . $client->name() . " is busy...");
			return 1;
		}
	}
	return 0;
}

sub _hasResumed {
	my ($class, $currenttime) = @_;

	# We've resumed if the current time is more than two minutes later than the last check time, or
	# if the current time is earlier than the last check time (system time change)
	
	if ( $currenttime > ($lastchecktime + (INTERVAL * 2)) || $currenttime < $lastchecktime ) {
		
		main::DEBUGLOG && $log->debug("System has resumed...");
		return 1;
	}
	
	return 0;
}


sub idletime_change {
	my ($pref, $value) = @_;
	
	$value ||= 0;

	main::DEBUGLOG && $log->debug("Pref $pref changed to $value. Resetting idle counter.");

	# Reset our counter on prefs change..
	$hasbeenidle = 0;

	if (main::DEBUGLOG) {
		if ($value) {
			$log->debug("System standby now allowed after $value minutes of player idle time.")
		} else {
			$log->debug("System standby now prohibited.")
		}
	}
}

sub checkpower_change {
	my ($pref, $value) = @_;
	
	$value ||= 0;

	main::DEBUGLOG && $log->debug("Pref $pref changed to $value. Resetting idle counter.");

	# Reset our counter on prefs change..
	$hasbeenidle = 0;

	if (main::DEBUGLOG && $value) {
		$log->debug("System standby now prohibited when players are powered on.")
	}
}

sub hasBeenIdle {
	my ($class, $newValue) = @_;
	$hasbeenidle = $newValue*60 if $newValue;
	return $hasbeenidle;
}

sub shutdownPlugin {
	Slim::Utils::Timers::killTimers( undef, \&checkClientActivity );
	$handler->cleanup();
}

1;

# base class for OS dependent implementations
package Slim::Plugin::PreventStandby::OS;

use strict;
use Slim::Plugin::PreventStandby::Plugin;

sub new {}

sub isBusy {
	my ($class, $currenttime) = @_;
	return Slim::Plugin::PreventStandby::Plugin->_hasResumed($currenttime) || Slim::Plugin::PreventStandby::Plugin->_playersBusy();
}

sub setBusy {}
sub setIdle {}
sub cleanup {}
sub pollInterval {}

1;

__END__
