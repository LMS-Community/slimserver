# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
use Slim::Player::Client;
package Slim::Player::Player;

@ISA = ("Slim::Player::Client");

sub new {
	my $class = shift;
	my $id = shift;
	my $paddr = shift;
	my $revision = shift;
	my $client = Slim::Player::Client->new($id, $paddr);
	bless $client, $class;

	# initialize model-specific features:
	$client->revision($revision);

	return $client;
}

sub init {
	my $client = shift;
	# fire it up!
	$client->power(Slim::Utils::Prefs::clientGet($client,'power'));
	$client->startup();
                
	# start the screen saver
	Slim::Buttons::ScreenSaver::screenSaver($client);
}

sub update {
	my $client = shift;
	Slim::Display::Animation::killAnimation($client);
	Slim::Hardware::VFD::vfdUpdate($client, Slim::Display::Display::curLines($client));
}	

sub isPlayer {
	return 1;
}

sub power {
	my $client = shift;
	my $on = shift;
	
	my $mode = Slim::Buttons::Common::mode($client);
	my $currOn;
	if (defined($mode)) {
		$currOn = $mode ne "off" ? 1 : 0;
	}
	
	if (!defined $on) {
		return ($currOn);
	} else {
		if (!defined($currOn) || ($currOn != $on)) {
			if ($on) {
				Slim::Buttons::Common::setMode($client, 'home');
				
				
				my $welcome =  Slim::Display::Display::center(Slim::Utils::Strings::string(Slim::Utils::Prefs::clientGet($client, "doublesize") ? 'SQUEEZEBOX' : 'WELCOME_TO_SQUEEZEBOX'));
				my $welcome2 = Slim::Utils::Prefs::clientGet($client, "doublesize") ? '' : Slim::Display::Display::center(Slim::Utils::Strings::string('FREE_YOUR_MUSIC'));
				Slim::Display::Animation::showBriefly($client, $welcome, $welcome2);
				
				# restore the saved brightness, unless its completely dark...
				my $powerOnBrightness = Slim::Utils::Prefs::clientGet($client, "powerOnBrightness");
				if ($powerOnBrightness < 1) { 
					$powerOnBrightness = 1;
				}
				Slim::Utils::Prefs::clientSet($client, "powerOnBrightness", $powerOnBrightness);
				#check if there is a sync group to restore
				Slim::Player::Sync::restoreSync($client);
				# restore volume (un-mute if necessary)
				my $vol = Slim::Utils::Prefs::clientGet($client,"volume");
				if($vol < 0) { 
					# un-mute volume
					$vol *= -1;
					Slim::Utils::Prefs::clientSet($client, "volume", $vol);
				}
				Slim::Control::Command::execute($client, ["mixer", "volume", $vol]);
			
			} else {
				Slim::Buttons::Common::setMode($client, 'off');
			}
			# remember that we were on if we restart the server
			Slim::Utils::Prefs::clientSet($client, 'power', $on ? 1 : 0);
		}
	}
}			



1;

