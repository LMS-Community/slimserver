package Slim::Web::Setup;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use HTTP::Status;
use Module::Pluggable require => '1', search_path => ['Slim::Web::Settings'], except => qr/::\._.*$/;

use Slim::Player::TranscodingHelper;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Validate;

our %setup = ();
our @newPlayerChildren;

my $log = logger('prefs');

# XXXXXX This code is brain damaged. It needs to be gutted and rewritten.

# Setup uses strings extensively, for many values it defaults to a certain combination of the
# preference name with other characters.  For this reason it is important to follow the naming
# convention when adding strings for preferences into strings.txt.
# In the following $groupname is replaced by the actual key used in the Groups hash and $prefname
# by the key from the Prefs hash.
# SETUP_GROUP_$groupname => the name of the group, such as would be used in a menu to select the group
#				or in the heading of the group in the web page.  Should be < 40 chars
# SETUP_GROUP_$groupname_DESC => the long description of the group, used in the web page, so length unimportant
# SETUP_$prefname => the friendly name of the preference, such as would be used in a menu to select the preference
#				or in the heading of the preference in the web page.  Should be < 40 chars.  Also
#				used when the preference changes and no change intro message was specified.
# SETUP_$prefname_DESC => the long description of the preference, used in the web page, so length unimportant
# SETUP_$prefname_CHOOSE => the label used for presentation of the input for the preference
# SETUP_$prefname_OK => the change intro message to use when the preference changes

# setup hash's keys:
# 'player' => hash of per player settings
# 'server' => hash of main server settings on the setup server web page

# page hash's keys:
# 'preEval' => sub ref taking $client,$paramref,$pageref as parameters used to refresh a setup entry on each page load
# 'postChange' => sub ref taking $client,$paramref,$pageref as parameters
# 'isClient' => set to 1 for pages relating to a player (client)
# 'template' => template to use to build page
# 'GroupOrder' => array of preference groups to appear on page, in order
# 'Groups' => hash of preference groups on page
# 'Prefs' => hash of preferences on page
# 'parent' => parent category of current category
# 'children' => array of child categories of current category
# 'title' => friendly name to use in web page
# 'singleChildLinkText' => Text to use for a single link to the first child


# Groups hash's keys:
# 'PrefOrder' => list of prefs to appear in group, in order
# 'PrefsInTable' => set if prefs should appear in a table
# 'GroupHead' => Name of the group, usually set to string('SETUP_GROUP+$groupname'), not defaulted to anything
# 'GroupDesc' => Description of the group, usually set to string('SETUP_GROUP_$groupname_DESC'), not defaulted to anything
# 'GroupLine' => set if an <hr> should appear after the group
# 'GroupSub' => set if a submit button should appear after the group
# 'Suppress_PrefHead' => set to prevent the heading of preferences in the group from showing
# 'Suppress_PrefDesc' => set to prevent the descriptions of preferences in the group from showing
# 'Suppress_PrefLine' => set to prevent <hr>'s from appearing after preferences in the group
# 'Suppress_PrefSub' => set to prevent submit buttons from appearing after preferences in the group

# Prefs hash's' keys:
# 'onChange' => sub ref taking $client,$changeref,$paramref,$pageref,$key,$ind as parameters, fired when a preference changes
# 'isArray' => exists if setting is an array type preference
# 'arrayAddExtra' => number of extra null entries to append to end of array
# 'arrayDeleteNull' => indicates whether to delete undef and '' from array
# 'arrayDeleteValue' => value signifying a null entry in the array
# 'arrayCurrentPref' => name of preference denoting current of array
# 'arrayBasicValue' => value to add to array if all entries are removed
# 'arrayMax' => largest index in array (only needed for items which are not actually prefs)
# 'validate' => reference to validation function (will be passed value to validate) (default validateAcceptAll)
# 'validateArgs' => array of arguments to be passed to validation function (in addition to value) (no default)
# 'options' => hash of value => text pairs to be used in building a list (no default)
# 'optionSort' => controls sort order of the options, one of K (key), KR (key reversed), V (value), VR (value reversed),
#	 NK (numeric key), NKR (numeric key reversed), NV (numeric value), NVR (numeric value reversed) - (default K)
#	 S - no string subsitution.
# 'dontSet' => flag to suppress actually changing the preference
# 'currentValue' => sub ref taking $client,$key,$ind as parameters, returns current value of preference.  Only needed for preferences which don't use Slim::Utils::Prefs
# 'noWarning' => flag to suppress change information
# 'externalValue' => sub ref taking $client,$value, $key as parameters, used to map an internal value to an external one
# 'PrefHead' => friendly name of the preference (defaults to 'SETUP_$prefname')
# 'PrefDesc' => long description of the preference (defaults to 'SETUP_$prefname_DESC')
# 'PrefChoose' => label to use for input of the preference (defaults to 'SETUP_$prefname_CHOOSE')
# 'PrefSize' => size to use for text box of input (choices are 'small','medium', and 'large', default 'small')
#	Actual size to use is determined by the setup_input_txt.html template (in EN skin values are 10,20,40)
# 'ChangeButton' => Text to display on the submit button within the input for this preference
#	Defaults to 'CHANGE'
# 'inputTemplate' => template to use for the input of the preference (defaults to setup_input_sel.html
#	for preferences with 'options', setup_input_txt.html otherwise)
# 'changeIntro' => template for the change introductory text (defaults to 'string('SETUP_NEW_VALUE') string('SETUP_prefname'):')
#	for array prefs the default is 'string('SETUP_NEW_VALUE') string('SETUP_prefname') %s:' sprintf'd with array index
# 'changeMsg' => template for change value (defaults to %s), this will be sprintf'd to stick in the value
# 'changeAddlText => template for any additional text to display after a change (default '')
# 'rejectIntro' => template for the rejection introductory text (defaults to 'string('SETUP_NEW_VALUE') string('SETUP_prefname') string('SETUP_REJECTED'):')(sprintf'd with array index for array settings)
	#for array prefs the default is 'string('SETUP_NEW_VALUE') string('SETUP_prefname') %s string('SETUP_REJECTED'):' sprintf'd with array index
# 'rejectMsg' => template for rejected value message (defaults to 'string('SETUP_BAD_VALUE')%s'), this will be sprintf'd to stick in the value
# 'rejectAddlText => template for any additional text to display after a rejection (default '')
# 'showTextExtValue' => indicates whether to display the external value as a label for an array of text input prefs
# 'PrefInTable' => set if only this pref should appear in a table. not compatible with group parameter 'PrefsInTable'

# the default values are used for keys which do not exist() for a particular preference
# for most preferences the only values to set will be 'validate', 'validateArgs', and 'options'

sub initSetupConfig {
	%setup = (
	'BASIC_PLAYER_SETTINGS' => { } #end of setup{'player'} hash
	,'DISPLAY_SETTINGS' => { }
	,'MENU_SETTINGS' => { }
	,'ALARM_SETTINGS' => { }
	,'AUDIO_SETTINGS' => { }
	,'REMOTE_SETTINGS' => { }
	,'PLAYER_PLUGINS' => {
		'title' => string('PLUGINS')
		,'parent' => 'BASIC_PLAYER_SETTINGS'
		,'isClient' => 1
		,'preEval' => sub {
				my ($client,$paramref,$pageref) = @_;
				return if (!defined($client));
				playerChildren($client, $pageref);
			}
	} # end of setup{'ADDITIONAL_PLAYER'} hash

	,'BASIC_SERVER_SETTINGS' => { } #end of setup{'server'} hash

	,'PLUGINS' => {
		'title' => string('PLUGINS')
		,'parent' => 'BASIC_SERVER_SETTINGS'
		,'preEval' => sub {
				my ($client,$paramref,$pageref) = @_;
				$pageref->{'Prefs'}{'pluginlist'}{'arrayMax'} = fillPluginsList($client, $paramref);
			}
		,'postChange' => sub {
				my ($client,$paramref,$pageref) = @_;
				processPluginsList($client, $paramref);
			}
		,'GroupOrder' => ['Default']
		# if more than one ir map exists the undef will be replaced by 'Default'
		,'Groups' => {
				'Default' => {
					'PrefOrder' => ['plugins-onthefly', 'pluginlist']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => 'SETUP_GROUP_PLUGINS'
					,'GroupDesc' => 'SETUP_GROUP_PLUGINS_DESC'
					,'GroupLine' => 1
					,'GroupSub' => 1
				}
			}
		,'Prefs' => {
			'pluginlist' => {
				'isArray' => 1
				,'dontSet' => 1
				,'validate' => \&Slim::Utils::Validate::trueFalse
				,'inputTemplate' => 'setup_input_array_chk.html'
				,'arrayMax' => undef #set in preEval
				,'changeMsg' => 'SETUP_PLUGINLIST_CHANGE'
				,'onChange' => \&Slim::Utils::PluginManager::clearGroups
				,'externalValue' => sub {
						my ($client, $value, $key) = @_;
						return getPluginState($client, $value, $key);
					}
				}
			,'plugins-onthefly' => {
				'validate' => \&Slim::Utils::Validate::trueFalse
				,'options' => {
						'1' => 'SETUP_PLUGINS-ONTHEFLY_1'
						,'0' => 'SETUP_PLUGINS-ONTHEFLY_0'
					}
				}
			}
		} #end of setup{'PLUGINS'}
	,'RADIO' => {
		'title' => string('RADIO')
		,'parent' => 'BASIC_SERVER_SETTINGS'
		,'preEval' => sub {
				my ($client,$paramref,$pageref) = @_;
				$pageref->{'Prefs'}{'pluginlist'}{'arrayMax'} = fillPluginsList($client, $paramref, 'RADIO');
			}
		,'postChange' => sub {
				my ($client,$paramref,$pageref) = @_;
				processPluginsList($client, $paramref, 'RADIO');
			}
		,'GroupOrder' => ['Default']
		,'Groups' => {
				'Default' => {
					'PrefOrder' => [ 'pluginlist' ]
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => 'RADIO'
					,'GroupDesc' => 'SETUP_GROUP_RADIO_DESC'
					,'GroupLine' => 1
					,'GroupSub' => 1
				}
			}
		,'Prefs' => {
			'pluginlist' => {
				'isArray' => 1
				,'dontSet' => 1
				,'validate' => \&Slim::Utils::Validate::trueFalse
				,'inputTemplate' => 'setup_input_array_chk.html'
				,'arrayMax' => undef #set in preEval
				,'changeMsg' => 'SETUP_PLUGINLIST_CHANGE'
				,'onChange' => \&Slim::Utils::PluginManager::clearGroups
				,'externalValue' => sub {
						my ($client,$value,$key) = @_;
						return getPluginState($client, $value, $key, 'RADIO');
					}
				}
			}
		}, #end of setup{'RADIO'}
	); #end of setup hash
	
	if (scalar(keys %{Slim::Utils::PluginManager::installedPlugins()})) {
		
		addChildren('BASIC_SERVER_SETTINGS', 'PLUGINS');

		# XXX This should be added conditionally based on whether there
		# are any radio plugins. We need to find a place to make that
		# check *after* plugins have been correctly initialized.
		addChildren('BASIC_SERVER_SETTINGS', 'RADIO');
	}
}

sub initSetup {

	initSetupConfig();
	fillAlarmOptions();

	for my $plugin (Slim::Web::Setup->plugins) {

		$plugin->new;
	}
	
	# init radio and plugin settings on startup
	# TODO: make these loadable from plugin API
	my @pages = @{$setup{'BASIC_SERVER_SETTINGS'}{'children'}};
	buildLinks(undef,@pages);
}

sub getSetupOptions {
	my ($category, $pref) = @_;

	return $setup{$category}{'Prefs'}{$pref}{'options'};
}

sub getPlayingDisplayModes {
	my $client = shift || return {};
	
	my $displayHash = { '-1' => ' ' };
	my $modes = $client->display->modes();

	foreach my $i (0..$client->display->nmodes()) {

		my $desc = $modes->[$i]{'desc'};

		foreach my $j (0..$#{$desc}){
			$displayHash->{"$i"} .= ' ' if ($j > 0);
			$displayHash->{"$i"} .= string(@{$desc}[$j]);
		}
	}

	return $displayHash;
}

sub getVisualModes {
	my $client = shift;
	
	if (!defined $client || !$client->display->isa('Slim::Display::Transporter')) {

		return {};
	}

	my $displayHash = { '-1' => ' ' };

	my $modes = $client->display->visualizerModes();

	foreach my $i (0..$client->display->visualizerNModes()) {

		my $desc = $modes->[$i]{'desc'};

		foreach my $j (0..$#{$desc}){

			$displayHash->{"$i"} .= ' ' if ($j > 0);
			$displayHash->{"$i"} .= string(@{$desc}[$j]);
		}
	}

	return $displayHash;
}

sub getFontOptions {
	my $client = shift;

	if (!$client || !exists &Slim::Display::Lib::Fonts::fontnames) {

		return {};
	}

	my $fonts = Slim::Display::Lib::Fonts::fontnames();
	my %allowedfonts;
	my $displayHeight = $client->displayHeight();

	foreach my $f (@$fonts) {

		if ($displayHeight == Slim::Display::Lib::Fonts::fontheight($f . '.2') && 
			Slim::Display::Lib::Fonts::fontchars($f . '.2') > 255 ) {

			$allowedfonts{$f} = $f;
		}
	}

	$allowedfonts{'-1'} = ' ';

	return \%allowedfonts;
}

sub getBrightnessOptions {
	my $client = shift;

	my %brightnesses = (
		'0' => '0 ('.string('BRIGHTNESS_DARK').')',
		'1' => '1',
		'2' => '2',
		'3' => '3',
		'4' => '4 ('.string('BRIGHTNESS_BRIGHTEST').')',
	);

	if (!defined $client) {

		return \%brightnesses;
	}

	if (defined $client->maxBrightness) {
		$brightnesses{'4'} = '4';
		$brightnesses{$client->maxBrightness} = $client->maxBrightness . ' (' . string('BRIGHTNESS_BRIGHTEST').')';
	}

	return \%brightnesses;
}

sub getBrightnessArgs {
	my @args = (0,4,1,1);
	my $client = shift || return @args;
	if (defined $client->maxBrightness) {
		$args[1] = $client->maxBrightness;
	}
	return @args;
}

sub fillAlarmOptions {
	$setup{'ALARM_SETTINGS'}{'Prefs'}{'alarmtime'} = {
		'onChange' => sub {
			my ($client,$changeref,$paramref,$pageref,$key,$index) = @_;
			
			return if (!defined($client));
			my $time = $changeref->{'alarmtime'.$index}{'new'};
			my $newtime = 0;
			$time =~ s{
				^(0?[0-9]|1[0-9]|2[0-4]):([0-5][0-9])\s*(P|PM|A|AM)?$
			}{
				if (defined $3) {
					$newtime = ($1 == 12?0:$1 * 60 * 60) + ($2 * 60) + ($3 =~ /P/?12 * 60 * 60:0);
				} else {
					$newtime = ($1 * 60 * 60) + ($2 * 60);
				}
			}iegsx;

			$client->prefSet('alarmtime',$newtime,$index);
		}
	};

	for my $i (0..7) {
		$setup{'ALARM_SETTINGS'}{'Prefs'}{'alarmvolume'.$i} = {
			'validate' => \&Slim::Utils::Validate::number
			,'PrefChoose' => 'SETUP_ALARMVOLUME'
			,'validateArgs' => [0,$Slim::Player::Client::maxVolume,1,1]
			,'changeIntro' => string('SETUP_ALARMVOLUME').' '.string('ALARM_DAY'.$i).string('COLON')
			,'currentValue' => sub {
				my $client = shift;
				return if (!defined($client));
				return $client->prefGet( "alarmvolume",$i);
			}
		};

		$setup{'ALARM_SETTINGS'}{'Prefs'}{'alarmtime'.$i} = {
			'validate' => \&Slim::Utils::Validate::isTime
			,'validateArgs' => [0,undef],
			,'PrefChoose' => 'ALARM_SET'
			,'changeIntro' => string('ALARM_SET').' '.string('ALARM_DAY'.$i).string('COLON')
			,'rejectIntro' => 'ALARM_SET'
			,'currentValue' => sub {
				my $client = shift;
				return if (!defined($client));
				
				my $time = $client->prefGet( "alarmtime",$i);
				
				my ($h0, $h1, $m0, $m1, $p) = Slim::Buttons::Input::Time::timeDigits($client,$time);
				my $timestring = ((defined($p) && $h0 == 0) ? ' ' : $h0) . $h1 . ":" . $m0 . $m1 . " " . (defined($p) ? $p : '');
				
				return $timestring;
			}
		};
		$setup{'ALARM_SETTINGS'}{'Prefs'}{'alarm'.$i} = {
			'validate' => \&Slim::Utils::Validate::trueFalse
			,'PrefHead' => ' '
			,'PrefChoose' => 'SETUP_ALARM'
			,'options' => {
					'1' => 'ON',
					'0' => 'OFF',
				}
			,'changeIntro' => string('SETUP_ALARM').' '.string('ALARM_DAY'.$i).string('COLON')
			,'currentValue' => sub {
					my $client = shift;
					return if (!defined($client));
					return $client->prefGet( "alarm",$i);
				}
		};
		$setup{'ALARM_SETTINGS'}{'Prefs'}{'alarmplaylist'.$i} = {
			'validate' => \&Slim::Utils::Validate::inHash
			,'PrefChoose' => 'ALARM_SELECT_PLAYLIST'
			,'validateArgs' => undef
			,'options' => undef
			,'changeIntro' => string('ALARM_SELECT_PLAYLIST').' '.string('ALARM_DAY'.$i).string('COLON')
			,'currentValue' => sub {
					my $client = shift;
					return if (!defined($client));
					return $client->prefGet( "alarmplaylist",$i);
				}
		};
		$setup{'ALARM_SETTINGS'}{'Groups'}{'AlarmDay'.$i} = {
			'PrefOrder' => ['alarm'.$i,'alarmtime'.$i,'alarmvolume'.$i,'alarmplaylist'.$i]
			,'PrefsInTable' => 1
			,'Suppress_PrefHead' => 1
			,'Suppress_PrefDesc' => 1
			,'Suppress_PrefLine' => 1
			,'Suppress_PrefSub' => 1
			,'GroupHead' => "ALARM_DAY$i"
			,'GroupLine' => 1
			,'GroupSub' => 1
		};
	};
}

sub fillSetupOptions {
	my ($set, $pref, $hash) = @_;

	$setup{$set}{'Prefs'}{$pref}{'options'}      = { hash_of_prefs($hash) };
	$setup{$set}{'Prefs'}{$pref}{'validateArgs'} = [ $setup{$set}{'Prefs'}{$pref}{'options'} ];
}

sub playerChildren {
	my $client = shift;
	my $pageref = shift;
	return if (!$client);

	if ($client->isPlayer()) {

		$pageref->{'children'} = ['BASIC_PLAYER_SETTINGS','MENU_SETTINGS','DISPLAY_SETTINGS','ALARM_SETTINGS','AUDIO_SETTINGS','REMOTE_SETTINGS'];
		push @{$pageref->{'children'}},@newPlayerChildren;
		if (scalar(keys %{Slim::Utils::PluginManager::playerPlugins()})) {
			push @{$pageref->{'children'}}, 'PLAYER_PLUGINS';
		}
	} else {
		$pageref->{'children'} = ['BASIC_PLAYER_SETTINGS','ALARM_SETTINGS','AUDIO_SETTINGS'];
	}
	
}

# TODO: get rid of this after ALL new pages are working
sub getPlayerPages {
	my $client = shift;

	return if (!$client);

	my @pages;
	if ($client->isPlayer()) {

		@pages = ();
		push @pages,@newPlayerChildren;
		if (scalar(keys %{Slim::Utils::PluginManager::playerPlugins()})) {
			push @pages, 'PLAYER_PLUGINS';
		}
	} else {
		@pages = ();
	}
	
	return @pages;
}

sub addPlayerChild {
	my $child = shift;

	push @newPlayerChildren, $child;
}

sub menuItemName {
	my ($client,$value) = @_;

	my $pluginsRef = Slim::Utils::PluginManager::installedPlugins();

	if (Slim::Utils::Strings::stringExists($value)) {

		my $string = $client->string($value);

		if (Slim::Utils::Strings::stringExists($string)) {
			return $client->string($string);
		}

		return $string;

	} elsif (exists $pluginsRef->{$value}) {

		return $client->string($pluginsRef->{$value});
	}

	return $value;
}

#returns a hash of title formats with the key being their array index and the value being the
#format string
sub hash_of_prefs {
	my $pref = shift;
	my %prefsHash;
	
	$prefsHash{'-1'} = ' '; #used to delete a title format from the list
	my $i = 0;
	foreach my $item (Slim::Utils::Prefs::getArray($pref)) {
		$prefsHash{$i++} = Slim::Utils::Strings::stringExists($item) ? Slim::Utils::Strings::string($item) : $item;
	}
	
	return %prefsHash;
}

#returns a hash reference to syncGroups available for a client
sub syncGroups {
	my $client = shift;
	my %clientlist = ();
	foreach my $eachclient (Slim::Player::Sync::canSyncWith($client)) {
		$clientlist{$eachclient->id()} =
		Slim::Player::Sync::syncname($eachclient, $client);
	}
	if (Slim::Player::Sync::isMaster($client)) {
		$clientlist{$client->id()} =
		Slim::Player::Sync::syncname($client, $client);
	}
	$clientlist{-1} = string('SETUP_NO_SYNCHRONIZATION');
	return \%clientlist;
}

sub setup_HTTP {
	my ($client, $paramref, $callback, $httpclientsock, $response) = @_;
	my $changed;
	my $rejected;
	
	if ($::nosetup || ($::noserver && $paramref->{'page'} eq 'BASIC_SERVER_SETTINGS')) {
		$response->code(RC_FORBIDDEN);
		return Slim::Web::HTTP::filltemplatefile('html/errors/403.html',$paramref);
	}

	if (!defined($paramref->{'page'}) || !exists($setup{$paramref->{'page'}})) {
		$response->code(RC_NOT_FOUND);
		$paramref->{'suggestion'} = string('SETUP_BAD_PAGE_SUGGEST');
		return Slim::Web::HTTP::filltemplatefile('html/errors/404.html',$paramref);
	}

	my %pagesetup = %{$setup{$paramref->{'page'}}};

	if (exists $pagesetup{'isClient'}) {
		$client = Slim::Player::Client::getClient($paramref->{'playerid'});
	} else {
		$client = undef;
	}

	# XXXX - ugly hack. The debug settings page needs a more flexible
	# layout than the current Setup code can give us. So call a different handler.
	if (defined $pagesetup{'handler'}) {

		return &{$pagesetup{'handler'}}($client, $paramref, \%pagesetup);
	}

	if (defined $pagesetup{'preEval'}) {
		&{$pagesetup{'preEval'}}($client,$paramref,\%pagesetup);
	}

	($changed,$rejected) = setup_evaluation($client,$paramref,$pagesetup{'Prefs'});

	setup_changes_HTTP($changed,$paramref,$pagesetup{'Prefs'});
	setup_rejects_HTTP($rejected,$paramref,$pagesetup{'Prefs'});

	# accept any changes that were posted
	processChanges($client,$changed,$paramref,\%pagesetup);

	if (defined $pagesetup{'postChange'}) {
		&{$pagesetup{'postChange'}}($client,$paramref,\%pagesetup);
	}

	#fill the option lists
	#puts the list of options in the param 'preference_options'
	options_HTTP($client,$paramref,$pagesetup{'Prefs'});
	buildHTTP($client,$paramref,\%pagesetup);
	
	$paramref->{'additionalLinks'} = \%Slim::Web::Pages::additionalLinks;

	return Slim::Web::HTTP::filltemplatefile('setup.html', $paramref);
}

sub buildHTTP {
	my ($client,$paramref,$pageref) = @_;

	my ($page,@pages) = ();

	for my $group (@{$pageref->{'GroupOrder'}}) {

		next if !$group || !defined($pageref->{'Groups'}{$group});

		my %groupparams = %{$pageref->{'Groups'}{$group}};

		$groupparams{'skinOverride'} = $$paramref{'skinOverride'};

		for my $pref (@{$pageref->{'Groups'}{$group}{'PrefOrder'}}) {

			next if !defined($pref) || !defined($pageref->{'Prefs'}{$pref});

			my %prefparams = (%{$paramref}, %{$pageref->{'Prefs'}{$pref}});

			$prefparams{'Suppress_PrefHead'} = $groupparams{'Suppress_PrefHead'};
			$prefparams{'Suppress_PrefDesc'} = $groupparams{'Suppress_PrefDesc'};
			$prefparams{'Suppress_PrefSub'}  = $groupparams{'Suppress_PrefSub'};
			$prefparams{'Suppress_PrefLine'} = $groupparams{'Suppress_PrefLine'};
			$prefparams{'PrefsInTable'}      = $groupparams{'PrefsInTable'} || $prefparams{'PrefInTable'};
			$prefparams{'skinOverride'}      = $groupparams{'skinOverride'};
			
			my $token  = 'SETUP_' . uc($pref);
			my $tokenDesc   = $token . '_DESC';
			my $tokenChoose = $token . '_CHOOSE';

			if (!exists $prefparams{'PrefHead'}) {
				$prefparams{'PrefHead'} = (Slim::Utils::Strings::resolveString($token) || $pref);
			}

			if (!exists $prefparams{'PrefDesc'} && Slim::Utils::Strings::stringExists($tokenDesc)) {
				$prefparams{'PrefDesc'} = $tokenDesc;
			}

			if (!exists $prefparams{'PrefChoose'} && Slim::Utils::Strings::stringExists($tokenChoose)) {
				$prefparams{'PrefChoose'} = $tokenChoose;
			}

			if (!exists $prefparams{'inputTemplate'}) {
				$prefparams{'inputTemplate'} = (exists $prefparams{'options'}) ? 'setup_input_sel.html' : 'setup_input_txt.html';
			}

			if (!exists $prefparams{'ChangeButton'}) {
				$prefparams{'ChangeButton'} = 'CHANGE';
			}

			$prefparams{'page'} = $paramref->{'page'};

			my $arrayMax = 0;
			my $arrayCurrent;

			if (exists($pageref->{'Prefs'}{$pref}{'isArray'})) {

				if (defined($pageref->{'Prefs'}{$pref}{'arrayMax'})) {
					$arrayMax = $pageref->{'Prefs'}{$pref}{'arrayMax'};
				} else {
					$arrayMax = ($client) ? $client->prefGetArrayMax($pref) : 
						Slim::Utils::Prefs::getArrayMax($pref);
				}

				if (defined($pageref->{'Prefs'}{$pref}{'arrayCurrentPref'})) {

					$prefparams{'PrefArrayCurrName'} = $pageref->{'Prefs'}{$pref}{'arrayCurrentPref'};

					$arrayCurrent = ($client) ? $client->prefGet($pageref->{'Prefs'}{$pref}{'arrayCurrentPref'})
								: Slim::Utils::Prefs::get($pageref->{'Prefs'}{$pref}{'arrayCurrentPref'});
				}

				if (defined($pageref->{'Prefs'}{$pref}{'arrayAddExtra'})) {

					my $adval = defined($pageref->{'Prefs'}{$pref}{'arrayDeleteValue'}) ? 
						$pageref->{'Prefs'}{$pref}{'arrayDeleteValue'} : '';

					for (my $i = $arrayMax + 1; $i <= $arrayMax + $pageref->{'Prefs'}{$pref}{'arrayAddExtra'}; $i++) {

						$paramref->{$pref . $i} = $adval;
					}

					$arrayMax += $pageref->{'Prefs'}{$pref}{'arrayAddExtra'};
				}
			}

			$prefparams{'PrefInput'} = '';

			for (my $i = 0; $i <= $arrayMax; $i++) {

				my $pref2 = $pref . (exists($pageref->{'Prefs'}{$pref}{'isArray'}) ? $i : '');

				$prefparams{'PrefName'} = $pref2;
				$prefparams{'PrefNameRoot'} = $pref;
				$prefparams{'PrefIndex'} = $i;

				if (!exists($paramref->{$pref2}) && !exists($pageref->{'Prefs'}{$pref}{'dontSet'})) {

					if (!exists($pageref->{'Prefs'}{$pref}{'isArray'})) {

						$paramref->{$pref2} = ($client) ? $client->prefGet($pref2) : 
							Slim::Utils::Prefs::get($pref2);

					} else {

						$paramref->{$pref2} = ($client) ? $client->prefGet($pref,$i) : 
							Slim::Utils::Prefs::getInd($pref,$i);
					}
				}

				$prefparams{'PrefValue'} = $paramref->{$pref2};

				if (exists $pageref->{'Prefs'}{$pref}{'externalValue'}) {

					if (exists $pageref->{'Prefs'}{$pref}{'isClient'}) {
						$client = Slim::Player::Client::getClient($paramref->{'playerid'});
					}

					$prefparams{'PrefExtValue'} = &{$pageref->{'Prefs'}{$pref}{'externalValue'}}($client,$paramref->{$pref2},$pref2);

				} else {

					$prefparams{'PrefExtValue'} = $paramref->{$pref2};
				}

				$prefparams{'PrefOptions'} = $paramref->{$pref2 . '_options'};

				if (exists($pageref->{'Prefs'}{$pref}{'isArray'})) {

					$prefparams{'PrefSelected'} = (defined($arrayCurrent) && ($arrayCurrent eq $i)) ? 'checked' : undef;

				} else {

					$prefparams{'PrefSelected'} = $paramref->{$pref2} ? 'checked' : undef;
				}

				if (defined $prefparams{'inputTemplate'}) {
					$prefparams{'PrefInput'} .= ${Slim::Web::HTTP::filltemplatefile($prefparams{'inputTemplate'},\%prefparams)};
				}
			}

			$groupparams{'PrefList'} .= ${Slim::Web::HTTP::filltemplatefile('setup_pref.html',\%prefparams)};
		}

		if (!exists $groupparams{'ChangeButton'}) {
			$groupparams{'ChangeButton'} = 'CHANGE';
		}

		$paramref->{'GroupList'} .= ${Slim::Web::HTTP::filltemplatefile('setup_group.html',\%groupparams)};
	}

	# set up pagetitle
	$paramref->{'pagetitle'} = $pageref->{'title'};

	# let the skin know if this is a client-specific page
	$paramref->{'isClient'} = $pageref->{'isClient'};

	# set up link tree
	$page = $paramref->{'page'};

	@pages = ();

	while (defined $page) {
		unshift @pages,$page;
		$page = $setup{$page}{'parent'};
	}

	@{$paramref->{'linklist'}} = ({
		'hreftype'  => 'setup',
		'title'     => string($paramref->{'page'}),
		'page'      => $paramref->{'page'},
	});

	# set up sibling bar
	if (defined $pageref->{'parent'} && defined $setup{$pageref->{'parent'}}{'children'}) {
		@pages = @{$setup{$pageref->{'parent'}}{'children'}};

		@{$paramref->{'linklist'}} = ({
			'hreftype'  => 'setup',
			'title'     => string($pageref->{'parent'}),
			'page'      => $pageref->{'parent'},
		});

		if (scalar(@pages) > 1) {

			buildLinks($paramref, @pages);
		}
	}

	# set up children bar and single child link
	if (defined $pageref->{'children'} && defined $pageref->{'children'}[0]) {

		@pages = @{$pageref->{'children'}};

		buildLinks($paramref, @pages);
	}
}

# This function builds the list of settings page links. 
# in future this will be done at startup and by plugins where needed
sub buildLinks {
	my ($paramref, @pages) = @_;
	
	for my $page (@pages) {
		
		# Don't include in the sorted list, let skins include or not and where they want.
		next if $page eq "BASIC_SERVER_SETTINGS";
		next if $page eq "BASIC_PLAYER_SETTINGS";
		
		# Grab player tabs.  
		# TODO do this on startup only and allow plugins to add themselves
		if (defined $paramref->{'playerid'}) {

			Slim::Web::Pages->addPageLinks("playersetup",{"$page"  => "setup.html?page=$page"});

			for my $playerplugin (@newPlayerChildren) {

				#Slim::Web::Pages->addPageLinks("playerplugin",{"$playerplugin"  => "setup.html?page=$playerplugin"});
			}
		
		} else {

				Slim::Web::Pages->addPageLinks('setup', { $page => "setup.html?page=$page" });
		}
	}
}

sub processChanges {
	my ($client,$changeref,$paramref,$pageref) = @_;
	
	foreach my $key (keys %{$changeref}) {
		my ($keyA, $keyI) = $key =~ /(.+?)(\d*)$/;

		if (exists($pageref->{'Prefs'}{$keyA}{'isArray'}) && !exists($pageref->{'Prefs'}{$keyA}{'dontSet'})) {
			if (!exists($changeref->{$keyA}{'Processed'})) {
				processArrayChange($client, $keyA, $paramref, $pageref);
				if (exists $pageref->{'Prefs'}{$keyA}{'onChange'}) {
					&{$pageref->{'Prefs'}{$keyA}{'onChange'}}($client,$changeref,$paramref,$pageref,$keyA,$keyI);
				}
				$changeref->{$keyA}{'Processed'} = 1;
			}
		} elsif (exists $pageref->{'Prefs'}{$keyA}{'onChange'}) {
			&{$pageref->{'Prefs'}{$keyA}{'onChange'}}($client,$changeref,$paramref,$pageref,$keyA,$keyI);
		}
	}
}

sub processArrayChange {
	my ($client,$array,$paramref,$pageref) = @_;
	my $arrayMax = ($client) ? $client->prefGetArrayMax($array) : Slim::Utils::Prefs::getArrayMax($array);
	if ($pageref->{'Prefs'}{$array}{'arrayDeleteNull'}) {
		my $acval;
		if (defined($pageref->{'Prefs'}{$array}{'arrayCurrentPref'})) {
			$acval = ($client) ? $client->prefGet($pageref->{'Prefs'}{$array}{'arrayCurrentPref'})
						: Slim::Utils::Prefs::get($pageref->{'Prefs'}{$array}{'arrayCurrentPref'});
		}
		my $adval = defined($pageref->{'Prefs'}{$array}{'arrayDeleteValue'}) ? $pageref->{'Prefs'}{$array}{'arrayDeleteValue'} : '';
		for (my $i = $arrayMax;$i >= 0;$i--) {
			my $aval = ($client) ? $client->prefGet($array,$i) : Slim::Utils::Prefs::getInd($array,$i);
			if (!defined $aval || $aval eq '' || $aval eq $adval) {
				if ($client) {
					$client->prefDelete($array,$i);
				} else {
					Slim::Utils::Prefs::delete($array,$i);
				}
				if (defined $acval && $acval >= $i) {
					$acval--;
				}
			}
		}
		if (defined($pageref->{'Prefs'}{$array}{'arrayCurrentPref'})) {
			if ($client) {
				$client->prefSet($pageref->{'Prefs'}{$array}{'arrayCurrentPref'},$acval);
			} else {
				Slim::Utils::Prefs::set($pageref->{'Prefs'}{$array}{'arrayCurrentPref'},$acval);
			}
		}
		$arrayMax = ($client) ? $client->prefGetArrayMax($array) : Slim::Utils::Prefs::getArrayMax($array);
		if ($arrayMax < 0 && defined($pageref->{'Prefs'}{$array}{'arrayBasicValue'})) {
			#all the array entries were deleted, so set one up
			if ($client) {
				$client->prefSet($array,$pageref->{'Prefs'}{$array}{'arrayBasicValue'},0);
			} else {
				Slim::Utils::Prefs::set($array,$pageref->{'Prefs'}{$array}{'arrayBasicValue'},0);
			}
			if (defined($pageref->{'Prefs'}{$array}{'arrayCurrentPref'})) {
				if ($client) {
					$client->prefSet($pageref->{'Prefs'}{$array}{'arrayCurrentPref'},0);
				} else {
					Slim::Utils::Prefs::set($pageref->{'Prefs'}{$array}{'arrayCurrentPref'},0);
				}
			}
			$arrayMax = 0;
		}
		#update the params hash, since the array entries may have shifted around some
		for (my $i = 0;$i <= $arrayMax;$i++) {
			$paramref->{$array . $i} = ($client) ? $client->prefGet($array,$i) : Slim::Utils::Prefs::getInd($array,$i);
		}
		#further update params hash to clear shifted values
		my $i = $arrayMax + 1;
		while (exists $paramref->{$array . $i}) {
			$paramref->{$array . $i} = $adval;
			$i++;
		}
	}
}

sub removeExtraArrayEntries {
	my ($client,$array,$paramref,$pageref) = @_;

	if (!defined($pageref->{'Prefs'}{$array}{'arrayAddExtra'})) {
		return;
	}

	my $arrayMax;
	if (defined($pageref->{'Prefs'}{$array}{'arrayMax'})) {
		$arrayMax = $pageref->{'Prefs'}{$array}{'arrayMax'};
	} else {
		$arrayMax = ($client) ? $client->prefGetArrayMax($array) : Slim::Utils::Prefs::getArrayMax($array);
	}

	my $adval = defined($pageref->{'Prefs'}{$array}{'arrayDeleteValue'}) ? $pageref->{'Prefs'}{$array}{'arrayDeleteValue'} : '';

	for (my $i = $arrayMax + $pageref->{'Prefs'}{$array}{'arrayAddExtra'};$i > $arrayMax;$i--) {
		if (exists $paramref->{$array . $i} && (!defined($paramref->{$array . $i}) || $paramref->{$array . $i} eq '' || $paramref->{$array . $i} eq $adval)) {
			delete $paramref->{$array . $i};
		}
	}
}

sub preprocessArray {
	my ($client,$array,$paramref,$settingsref) = @_;

	my $arrayMax;
	if (defined($settingsref->{$array}{'arrayMax'})) {
		$arrayMax = $settingsref->{$array}{'arrayMax'};
	} else {
		$arrayMax = ($client) ? $client->prefGetArrayMax($array) : Slim::Utils::Prefs::getArrayMax($array);
	}

	my $arrayAddExtra = $settingsref->{$array}{'arrayAddExtra'};
	if (!defined $arrayAddExtra) {
		return $arrayMax;
	}

	my $adval = defined($settingsref->{$array}{'arrayDeleteValue'}) ? $settingsref->{$array}{'arrayDeleteValue'} : '';

	for (my $i=$arrayMax + $arrayAddExtra; $i > $arrayMax; $i--) {
		if (exists $paramref->{$array . $i}) {
			if (defined($paramref->{$array . $i}) && $paramref->{$array . $i} ne '' && $paramref->{$array . $i} ne $adval) {
				$arrayMax = $i;
				last;
			} else {
				delete $paramref->{$array . $i};
			}
		}
	}

	return $arrayMax;
}

sub playlists {
	my %lists = ();

	for my $playlist (Slim::Schema->rs('Playlist')->getPlaylists) {

		$lists{$playlist->url} = Slim::Music::Info::standardTitle(undef, $playlist);
	}

	return \%lists;
}

sub skins {
	my $forUI = shift;
	
	my %skinlist = ();

	foreach my $templatedir (Slim::Web::HTTP::HTMLTemplateDirs()) {

		foreach my $dir (Slim::Utils::Misc::readDirectory($templatedir)) {

			# reject CVS, html, and .svn directories as skins
			next if $dir =~ /^(?:cvs|html|\.svn)$/i;
			next if $forUI && $dir =~ /^x/;
			next if !-d catdir($templatedir, $dir);

			# BUG 4171: Disable dead Default2 skin, in case it was left lying around
			next if $dir =~ /^(?:Default2)$/i;

			logger('network.http')->info("skin entry: $dir");

			if ($dir eq Slim::Web::HTTP::defaultSkin()) {
				$skinlist{$dir} = string('DEFAULT_SKIN');
			} elsif ($dir eq Slim::Web::HTTP::baseSkin()) {
				$skinlist{$dir} = string('BASE_SKIN');
			} else {
				$skinlist{$dir} = Slim::Utils::Misc::unescape($dir);
			}
		}
	}
	return %skinlist;
}

sub setup_evaluation {
	my ($client, $paramref, $settingsref) = @_;
	my %changes = ();
	my %rejects = ();

	foreach my $key (keys %$settingsref) {
		my $arrayMax = 0;

		if (exists($settingsref->{$key}{'isArray'})) {
			$arrayMax = preprocessArray($client, $key, $paramref, $settingsref);
		}

		if (defined($arrayMax)) {
			for (my $i=0; $i <= $arrayMax; $i++) {
				my ($key2,$currVal);
				if (exists($settingsref->{$key}{'isArray'})) {
					$key2 = $key . $i;
					if (exists($settingsref->{$key}{'currentValue'})) {
						$currVal = &{$settingsref->{$key}{'currentValue'}}($client,$key,$i);
					} else {
						$currVal = ($client) ? $client->prefGet($key,$i) : Slim::Utils::Prefs::getInd($key,$i);
					}
				} else {
					$key2 = $key;
					if (exists($settingsref->{$key}{'currentValue'})) {
						$currVal = &{$settingsref->{$key}{'currentValue'}}($client,$key);
					} else {
						$currVal = ($client) ? $client->prefGet($key) : Slim::Utils::Prefs::get($key);
					}
				}
				if (defined($paramref->{$key2})) {
					my ($pvalue, $errmsg);
					if (exists $settingsref->{$key}{'validate'}) {
						my @args = ($paramref->{$key2});

						if (exists $settingsref->{$key}{'validateArgs'}) {
							if (ref $settingsref->{$key}{'validateArgs'} eq 'CODE') {
								my @valargs = &{$settingsref->{$key}{'validateArgs'}}($client);
								push @args, @valargs;
							} else {
								push @args, @{$settingsref->{$key}{'validateArgs'}};
							}
						}

						if (exists $settingsref->{$key}{'validateAddClient'}) {
							push @args, $client;
						}

						($pvalue, $errmsg) = &{$settingsref->{$key}{'validate'}}(@args);
					} else { # accept everything
						$pvalue = $paramref->{$key2};
					}
					if (defined($pvalue)) {
						# the following if is true if the current setting is different
						# from the setting in the param hash
						if (!(defined($currVal) && $currVal eq $pvalue)) {
							if ($client) {
								$changes{$key2}{'old'} = $currVal;
								if (!exists $settingsref->{$key}{'dontSet'}) {
									$client->prefSet($key2,$pvalue);
								}
							} else {
								$changes{$key2}{'old'} = $currVal;
								if (!exists $settingsref->{$key}{'dontSet'}) {
									Slim::Utils::Prefs::set($key2,$pvalue);
								}
							}
							$changes{$key2}{'new'} = $pvalue;
							$currVal = $pvalue;
						}
					} else {
						$rejects{$key2} = $paramref->{$key2};
					}
				}
				if (!exists $settingsref->{$key}{'dontSet'}) {
					$paramref->{$key2} = $currVal;
				}
			}
		}
	}
	return \%changes,\%rejects;
}

sub setup_changes_HTTP {
	my $changeref = shift;
	my $paramref = shift;
	my $settingsref = shift;

	my $client;
	if (exists $paramref->{'playerid'}) {
		$client = Slim::Player::Client::getClient($paramref->{'playerid'});
	}

	foreach my $key (keys %{$changeref}) {

		my ($keyA,$keyI);

		# split up array preferences into the base + index
		# debug variables start with d_ and should not be split
		if ($key =~ /^(?!d_)(.+?)(\d*)$/) {
			$keyA = $1;
			$keyI = $2;
		} else {
			$keyA = $key;
			$keyI = '';
		}

		my $changemsg  = undef;
		my $changedval = undef;
		my $changebase = undef;

		if (exists $settingsref->{$keyA}{'noWarning'}) {
			next;
		}
		
		if (exists $settingsref->{$keyA}{'changeIntro'}) {

			$changebase = Slim::Utils::Strings::getString($settingsref->{$keyA}{'changeIntro'});

		} elsif (Slim::Utils::Strings::stringExists('SETUP_' . uc($keyA) . '_OK')) {

			$changebase = string('SETUP_' . uc($keyA) . '_OK');

		} elsif (Slim::Utils::Strings::stringExists('SETUP_' . uc($keyA))) {

			$changebase = string('SETUP_' . uc($keyA)) . ($keyI ne '' ? " $keyI" : '') . string('COLON');

		} else {

			$changebase = $keyA . ($keyI ne '' ? " $keyI" : '') . string('COLON');
		}

		$changemsg = sprintf($changebase,$keyI);
		$changemsg .= '<p>';

		# use external value from 'options' hash

		if (exists $settingsref->{$keyA}{'changeoptions'}) {

			if ($settingsref->{$keyA}{'changeoptions'}) {

				$changedval = $settingsref->{$keyA}{'changeoptions'}{$changeref->{$key}{'new'}};
			}

		} elsif (exists $settingsref->{$keyA}{'options'}) {

			if (ref $settingsref->{$keyA}{'options'} eq 'CODE') {

				$changedval = &{$settingsref->{$keyA}{'options'}}($client)->{$changeref->{$key}{'new'}};

			} else {

				$changedval = $settingsref->{$keyA}{'options'}{$changeref->{$key}{'new'}};
			}

		} elsif (exists $settingsref->{$keyA}{'externalValue'}) {

			$changedval = &{$settingsref->{$keyA}{'externalValue'}}($client,$changeref->{$key},$key);

		} else {

			$changedval = $changeref->{$key}{'new'};
		}

		if (exists $settingsref->{$keyA}{'changeMsg'}) {

			$changemsg .= Slim::Utils::Strings::getString($settingsref->{$keyA}{'changeMsg'});

		} else {

			$changemsg .= '%s';
		}

		$changemsg .= '</p>';

		if (exists $settingsref->{$keyA}{'changeAddlText'}) {

			$changemsg .= Slim::Utils::Strings::getString($settingsref->{$keyA}{'changeAddlText'});
		}

		if (defined($changedval) && $changemsg) {

			$paramref->{'warning'} .= sprintf($changemsg, $changedval);
		}
	}
}

sub setup_rejects_HTTP {
	my $rejectref = shift;
	my $paramref = shift;
	my $settingsref = shift;
	foreach my $key (keys %{$rejectref}) {
		$key =~ /(.+?)(\d*)$/;
		my $keyA = $1;
		my $keyI = $2;
		my $rejectmsg;
		if (exists $settingsref->{$keyA}{'rejectIntro'}) {
			my $rejectbase = Slim::Utils::Strings::getString($settingsref->{$keyA}{'rejectIntro'});
			$rejectmsg = sprintf($rejectbase,$keyI);
		} else {
			$rejectmsg = string('SETUP_NEW_VALUE') . ' ' . 
						(string('SETUP_' . uc($keyA)) || $keyA) . ' ' . 
						$keyI . string("SETUP_REJECTED") . ':';
		}
		$rejectmsg .= ' <blockquote> ';
		if (exists $settingsref->{$keyA}{'rejectMsg'}) {
			$rejectmsg .= Slim::Utils::Strings::getString($settingsref->{$keyA}{'rejectMsg'});
		} else {
			$rejectmsg .= string('SETUP_BAD_VALUE');
		}
		$rejectmsg .= '</blockquote><p>';
		if (exists $settingsref->{$keyA}{'rejectAddlText'}) {
			$rejectmsg .= Slim::Utils::Strings::getString($settingsref->{$keyA}{'rejectAddlText'});
		}
		$paramref->{'warning'} .= sprintf($rejectmsg, $rejectref->{$key});
	}
}

sub options_HTTP {
	my ($client, $paramref, $settingsref) = @_;

	foreach my $key (keys %$settingsref) {
		my $arrayMax = 0;
		my $keyOptions = undef;

		if (exists($settingsref->{$key}{'isArray'})) {
			$arrayMax = ($client) ? $client->prefGetArrayMax($key) : Slim::Utils::Prefs::getArrayMax($key);
			if (!defined $arrayMax) { $arrayMax = 0; }
			if (exists($settingsref->{$key}{'arrayAddExtra'})) {
				$arrayMax += $settingsref->{$key}{'arrayAddExtra'};
			}
		}

		if (exists $settingsref->{$key}{'options'}) {
			if (ref $settingsref->{$key}{'options'} eq 'CODE') {
				$keyOptions = \%{&{$settingsref->{$key}{'options'}}($client)};
			} elsif (ref $settingsref->{$key}{'options'} eq 'HASH') {
				$keyOptions = \%{$settingsref->{$key}{'options'}};
			}
		}

		for (my $i=0; $i <= $arrayMax; $i++) {
			my $key2 = $key . (exists($settingsref->{$key}{'isArray'}) ? $i : '');
			if (defined $keyOptions) {
				$paramref->{$key2 . '_options'}{'order'} = _sortOptionArray($keyOptions,$settingsref->{$key}{'optionSort'});
				$paramref->{$key2 . '_options'}{'map'} = $keyOptions;
			}
		}
	}
}

# Utility used to sort and translate options hash
sub _sortOptionArray {
	my ($optionref, $sort) = @_;

	# default $sort to K
	$sort = 'K' unless defined $sort;

	# First - resolve any string pointers
	if ($sort !~ /S/) {

		while (my ($key, $value) = each %{$optionref}) {

			$optionref->{$key} = Slim::Utils::Strings::getString($value);
		}
	}

	# Now sort
	my @options = keys %$optionref;
	
	if (ref $sort eq 'CODE') {
		@options = sort { &{$sort} } @options;
	}elsif ($sort =~ /N/i) {
		# N - numeric sort
		if($sort =~ /K/i) {
			# K - by key
			@options = sort {$a <=> $b} @options;
		} else {
			# V - by value
			@options = sort {$optionref->{$a} <=> $optionref->{$b}} @options;
		}
	} else {
		# regular sort
		if($sort =~ /K/i) {
			# K - by key
			@options = sort @options;
		} else {
			# V - by value
			@options = sort {$optionref->{$a} cmp $optionref->{$b}} @options;
		}
	}

	if ($sort =~ /R/i) {
		@options = reverse @options;
	}

	return \@options;
}

######################################################################
# Setup Hash Manipulation Functions
######################################################################
# Adds the preference to the PrefOrder array of the supplied group at the
# supplied position (or at the end if no position supplied)

sub addPrefToGroup {
	my ($category, $groupname, $prefname, $position) = @_;

	unless (exists $setup{$category} && exists $setup{$category}{'Groups'}{$groupname}) {

		# either the category or the group within the category is invalid
		$log->warn("Group $groupname in category $category does not exist!");

		return;
	}

	if (!defined $position || $position > scalar(@{$setup{$category}{'Groups'}{$groupname}{'PrefOrder'}})) {

		$position = scalar(@{$setup{$category}{'Groups'}{$groupname}{'PrefOrder'}});
	}

	splice(@{$setup{$category}{'Groups'}{$groupname}{'PrefOrder'}},$position,0,$prefname);
}

# Removes the preference from the PrefOrder array of the supplied group
# in the supplied category
sub removePrefFromGroup {
	my ($category, $groupname, $prefname, $noWarn) = @_;

	# Find $prefname in $setup{$category}{'Groups'}{$groupname}{'PrefOrder'} array
	unless (exists $setup{$category} && exists $setup{$category}{'Groups'}{$groupname}) {

		# either the category or the group within the category is invalid
		$log->warn("Group $groupname in category $category does not exist!");

		return;
	}

	my $i = 0;

	for my $currpref (@{$setup{$category}{'Groups'}{$groupname}{'PrefOrder'}}) {

		if ($currpref eq $prefname) {

			splice (@{$setup{$category}{'Groups'}{$groupname}{'PrefOrder'}},$i,1);
			$i = -1; # indicates that a preference was removed
			last;
		}

		$i++;
	}

	if ($i > 0 && !$noWarn) {

		$log->warn("Preference $prefname not found in group $groupname in category $category");
	}
}

# Adds the preference to the category.  A reference to a hash containing the
# preference data must be supplied.
sub addPref {
	my ($category, $prefname, $prefref, $groupname, $position) = @_;

	if (!exists $setup{$category}) {

		$log->warn("Category $category does not exist");

		return;
	}

	$setup{$category}{'Prefs'}{$prefname} = $prefref;

	if (defined $groupname) {

		addPrefToGroup($category,$groupname,$prefname,$position);
	}
}

# Removes the preference from the supplied category, optionally removes
# all references to the preference from the PrefOrder arrays of the groups
# within the category
sub delPref {
	my ($category, $prefname, $andGroupRefs) = @_;
	
	if (!exists $setup{$category}) {

		$log->warn("Category $category does not exist");

		return;
	}

	delete $setup{$category}{'Prefs'}{$prefname};

	if ($andGroupRefs) {

		for my $group (@{$setup{$category}{'GroupOrder'}}) {

			removePrefFromGroup($category, $group, $prefname, 1);
		}
	}
}

# Adds a group to the supplied category.  A reference to a hash containing the
# group data must be supplied.  If a reference to a hash of preferences is supplied,
# they will also be added to the category.
sub addGroup {
	my ($category,$groupname,$groupref,$position,$prefsref,$categoryKey) = @_;

	unless (exists $setup{$category}) {

		$log->warn("Category $category does not exist");

		return;
	}

	unless (defined $groupname && (defined $groupref || defined $categoryKey)) {

		$log->warn("No group information supplied!");

		return;
	}
	
	$categoryKey = 'GroupOrder' unless defined $categoryKey;
	
	if (defined $prefsref) {
		$setup{$category}{'Groups'}{$groupname} = $groupref;
	}

	my $found = 0;

	for (@{$setup{$category}{$categoryKey}}) {

		next if !defined $_;

		$found = 1, last if $_ eq $groupname;
	}

	if (!$found) {

		if (!defined $position || $position > scalar(@{$setup{$category}{$categoryKey}})) {

			$position = scalar(@{$setup{$category}{$categoryKey}});
		}

		$log->info("Adding $groupname to position $position in $categoryKey");

		splice(@{$setup{$category}{$categoryKey}}, $position, 0, $groupname);
	}

	if ($category eq 'PLUGINS') {

		my $first = shift @{$setup{$category}{$categoryKey}};

		my $pluginlistref = getCategoryPlugins(undef, $category);

		@{$setup{$category}{$categoryKey}} = ($first, sort {

			uc($pluginlistref->{$a}) cmp uc($pluginlistref->{$b})

		} (@{$setup{$category}{$categoryKey}}));
	}
	
	if (defined $prefsref) {

		my ($pref,$prefref);

		while (($pref,$prefref) = each %{$prefsref}) {

			$setup{$category}{'Prefs'}{$pref} = $prefref;

			$log->info("Adding $pref to setup hash");
		}
	}
}

# Deletes a group from a category and optionally the associated preferences
sub delGroup {
	my ($category,$groupname,$andPrefs) = @_;

	if (!exists $setup{$category}) {

		$log->warn("Category $category does not exist");

		return;
	}
	
	my @preflist = ();

	if (exists $setup{$category}{'Groups'}{$groupname} && $andPrefs) {

		#hold on to preferences for later deletion
		@preflist = @{$setup{$category}{'Groups'}{$groupname}{'PrefOrder'}};
	}
	
	if ($setup{$category}{'children'}) {

		# remove ghost children
		my @children = ();

		foreach (@{$setup{$category}{'children'}}) {

			next if !defined $_;
			next if $_ eq $groupname;
			push @children,$_;
		}

		@{$setup{$category}{'children'}} = @children;
	}

	# remove from Groups hash
	delete $setup{$category}{'Groups'}{$groupname};
	
	# remove from GroupOrder array
	my $i = 0;
	
	for my $currgroup (@{$setup{$category}{'GroupOrder'}}) {

		if ($currgroup eq $groupname) {

			splice (@{$setup{$category}{'GroupOrder'}}, $i, 1);
			last;
		}

		$i++;
	}

	# delete associated preferences if requested
	if ($andPrefs) {

		for my $pref (@preflist) {
			delPref($category, $pref);
		}
	}
}

sub addChildren {
	my ($category, $child, $position) = @_;

	my $categoryKey = 'children';
	
	addGroup($category, $child, undef, $position, undef, $categoryKey);
}

sub addCategory {
	my ($category, $categoryref) = @_;

	if (!defined $category || !defined $categoryref) {

		$log->warn("No category information supplied!");

		return;
	}
	
	$setup{$category} = $categoryref;
}

sub delCategory {
	my $category = shift;

	if (!defined $category) {

		$log->warn("No category information supplied!");

		return;
	}

	delete $setup{$category};
}

sub existsCategory {
	my $category = shift;

	return exists $setup{$category};
}

sub getCategoryPlugins {
	my $client        = shift;
	my $category      = shift || 'PLUGINS';
	my $pluginlistref = Slim::Utils::PluginManager::installedPlugins();

	no strict 'refs';

	for my $plugin (keys %{$pluginlistref}) {

		# get plugin's displayName if it's not available, yet
		if (!Slim::Utils::Strings::stringExists($pluginlistref->{$plugin})) {

			$pluginlistref->{$plugin} = Slim::Utils::PluginManager::canPlugin($plugin);
		}
		
		if (Slim::Utils::Strings::stringExists($pluginlistref->{$plugin})) {

			my $menu = 'PLUGINS';

			if (UNIVERSAL::can("Plugins::${plugin}", "addMenu")) {

				$menu = eval { &{"Plugins::${plugin}::addMenu"}() };

				# if there's a problem or a category does not exist, reset $menu
				$menu = 'PLUGINS' if ($@ || not existsCategory($menu));
			}

			# only return the current category's plugins
			if ($menu eq $category) {

				$pluginlistref->{$plugin} = Slim::Utils::Strings::string($pluginlistref->{$plugin});

				next;
			}
		}

		delete $pluginlistref->{$plugin};
	}
	
	return $pluginlistref;
}

sub fillPluginsList {
	my ($client, $paramref, $category) = @_;

	my %plugins = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledplugins');
	my $pluginlistref = getCategoryPlugins($client, $category);
	my $i = 0;

	for my $plugin (sort {uc($pluginlistref->{$a}) cmp uc($pluginlistref->{$b})} (keys %{$pluginlistref})) {	

		if ((exists $paramref->{"pluginlist$i"} && $paramref->{"pluginlist$i"} == (exists $plugins{$plugin} ? 0 : 1))) {

			delete $paramref->{"pluginlist$i"};
		}

		$i++;
	}

	return $i - 1;
}

sub processPluginsList {
	my ($client, $paramref, $category) = @_;
	my %plugins = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledplugins');
	my $i = 0;

	Slim::Utils::Prefs::delete('disabledplugins');

	my $pluginlistref = getCategoryPlugins($client, $category);

	my @sorted = (sort {uc($pluginlistref->{$a}) cmp uc($pluginlistref->{$b})} (keys %{$pluginlistref}));

	no strict 'refs';

	for my $plugin (@sorted) {

		if (defined $paramref->{"pluginlist$i"} && not $paramref->{"pluginlist$i"}) {

			Slim::Utils::PluginManager::shutdownPlugin($plugin);
		}

		if (!exists $paramref->{"pluginlist$i"}) {

			$paramref->{"pluginlist$i"} = exists $plugins{$plugin} ? 0 : 1;
		}

		if (!$paramref->{"pluginlist$i"}) {

			Slim::Utils::Prefs::push('disabledplugins',$plugin);
		}

		delete $plugins{$plugin};

		$i++;
	}

	# add remaining disabled plugins (other categories)
	foreach (keys %plugins) {

		Slim::Utils::Prefs::push('disabledplugins', $_);
	}

	Slim::Web::HTTP::initSkinTemplateCache();
	Slim::Utils::PluginManager::initPlugins();
	Slim::Utils::PluginManager::addSetupGroups();

	$i = 0;

	# refresh the list of plugins as some of them might have been disable during intialization
	%plugins = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledplugins');

	for my $plugin (@sorted) {	

		if (exists $plugins{$plugin} && $plugins{$plugin}) {

			$paramref->{"pluginlist$i"} = 0;
		}

		$i++;
	}
}

sub getPluginState {
	my ($client, $value, $key, $category) = @_;

	if ($key !~ /\D+(\d+)$/) {
		return $value;

	}

	my $pluginlistref = getCategoryPlugins($client, $category);

	return $pluginlistref->{(sort {uc($pluginlistref->{$a}) cmp uc($pluginlistref->{$b})} (keys %{$pluginlistref}))[$1]};
}

1;

__END__
