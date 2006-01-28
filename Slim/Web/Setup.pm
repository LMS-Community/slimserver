package Slim::Web::Setup;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use HTTP::Status;

use Slim::Player::TranscodingHelper;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Validate;

our %setup = ();
our @newPlayerChildren;
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
# 'dontSet' => flag to suppress actually changing the preference
# 'currentValue' => sub ref taking $client,$key,$ind as parameters, returns current value of preference.  Only needed for preferences which don't use Slim::Utils::Prefs
# 'noWarning' => flag to suppress change information
# 'externalValue' => sub ref taking $client,$value, $key as parameters, used to map an internal value to an external one
# 'PrefHead' => friendly name of the preference (defaults to string('SETUP_$prefname')
# 'PrefDesc' => long description of the preference (defaults to string('SETUP_$prefname_DESC')
# 'PrefChoose' => label to use for input of the preference (defaults to string('SETUP_$prefname_CHOOSE')
# 'PrefSize' => size to use for text box of input (choices are 'small','medium', and 'large', default 'small')
#	Actual size to use is determined by the setup_input_txt.html template (in EN skin values are 10,20,40)
# 'ChangeButton' => Text to display on the submit button within the input for this preference
#	Defaults to string('CHANGE')
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
	'PLAYER_SETTINGS' => {
		'title' => string('PLAYER_SETTINGS') #may be modified in postChange to reflect player name
		,'children' => []
		,'GroupOrder' => []
		,'isClient' => 1
		,'preEval' => sub {
					my ($client,$paramref,$pageref) = @_;
					return if (!defined($client));
					playerChildren($client, $pageref);

					if ($client->isPlayer()) {
						$pageref->{'GroupOrder'} = ['Default','TitleFormats','Display'];
						fillSetupOptions('PLAYER_SETTINGS','titleFormat','titleFormat');
						if (scalar(keys %{Slim::Buttons::Common::hash_of_savers()}) > 0) {
							push @{$pageref->{'GroupOrder'}}, 'ScreenSaver';
							$pageref->{'Prefs'}{'screensaver'}{'options'} = Slim::Buttons::Common::hash_of_savers();
							$pageref->{'Prefs'}{'idlesaver'}{'options'} = Slim::Buttons::Common::hash_of_savers();
							$pageref->{'Prefs'}{'offsaver'}{'options'} = Slim::Buttons::Common::hash_of_savers();
						}
						
						my $displayHash = $client->playingModeOptions();
						$displayHash->{-1} = ' ' ;
						$pageref->{'Prefs'}{'playingDisplayModes'}{'options'} = $displayHash;
						$pageref->{'Prefs'}{'playingDisplayModes'}{'validateArgs'} = [$pageref->{'Prefs'}{'playingDisplayModes'}{'options'}];					} else {
						$pageref->{'GroupOrder'} = ['Default','TitleFormats'];
					}
					
					$pageref->{'Prefs'}{'playername'}{'validateArgs'} = [$client->defaultName()];

				}
		,'postChange' => sub {
					my ($client,$paramref,$pageref) = @_;
					
					return if (!defined($client));
					
					if ($paramref->{'playername'}) {
						$pageref->{'title'} = string('PLAYER_SETTINGS') . ' ' . string('FOR') . ' ' . $paramref->{'playername'};
					}
					if (defined($client->revision)) {
						$paramref->{'versionInfo'} = string("PLAYER_VERSION") . string("COLON") . $client->revision;
					}
					
					$paramref->{'ipaddress'} = $client->ipport();
					$paramref->{'macaddress'} = $client->macaddress;
					$paramref->{'signalstrength'} = $client->signalStrength;

					$client->update();
				}
		#,'template' => 'setup_player.html'
		,'Groups' => {
			'Default' => {
					'PrefOrder' => ['playername',]
				}
			,'TitleFormats' => {
					'PrefOrder' => ['titleFormat']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'GroupHead' => string('SETUP_TITLEFORMAT')
					,'GroupDesc' => string('SETUP_TITLEFORMAT_DESC')
					,'GroupPrefHead' => '<tr><th>' . string('SETUP_CURRENT') . 
										'</th><th></th><th>' . string('SETUP_FORMATS') . '</th><th></th></tr>'
					,'GroupLine' => 1
				}
			,'Display' => {
					'PrefOrder' => ['playingDisplayModes']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub'  => 1
					,'GroupHead' => string('SETUP_PLAYINGDISPLAYMODE')
					,'GroupDesc' => string('SETUP_PLAYINGDISPLAYMODE_DESC')
					,'GroupPrefHead' => '<tr><th>' . string('SETUP_CURRENT') . 
										'</th><th></th><th>' . string('DISPLAY_SETTINGS') . '</th><th></th></tr>'
					,'GroupLine' => 1
					,'GroupSub'  => 1
				}
			,'ScreenSaver' => {
				'PrefOrder' => ['screensaver','idlesaver','offsaver','screensavertimeout']
				,'Suppress_PrefHead' => 1
				,'Suppress_PrefDesc' => 1
				,'Suppress_PrefLine' => 1
				,'Suppress_PrefSub' => 1
				,'PrefsInTable' => 1
				,'GroupHead' => string('SCREENSAVERS')
				,'GroupDesc' => string('SETUP_SCREENSAVER_DESC')
				,'GroupLine' => 1
				,'GroupSub' => 1
			}
		}
		,'Prefs' => {
			'playername' => {
							'validate' => \&Slim::Utils::Validate::hasText
							,'validateArgs' => [] #will be set by preEval
							,'PrefSize' => 'medium'
						}
			,'titleFormatCurr'	=> {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => [] #will be set by preEval
						}
			,'playingDisplayMode'	=> {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => [] # will be set by preEval
						}
			,'playingDisplayModes' 	=> {
							'isArray' => 1
							,'arrayAddExtra' => 1
							,'arrayDeleteNull' => 1
							,'arrayDeleteValue' => -1
							,'arrayBasicValue' => 0
							,'arrayCurrentPref' => 'playingDisplayMode'
							,'inputTemplate' => 'setup_input_array_sel.html'
							,'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [] #filled by initSetup
							,'options' => {} #filled by initSetup using hash_of_prefs('titleFormat')
							,'optionSort' => 'NK'
							,'onChange' => sub {
										my ($client,$changeref,$paramref,$pageref) = @_;
										if (exists($changeref->{'playingDisplayModes'}{'Processed'})) {
											return;
										}
										processArrayChange($client,'playingDisplayModes',$paramref,$pageref);
										$changeref->{'playingDisplayModes'}{'Processed'} = 1;
									}
						}
			,'titleFormat'		=> {
							'isArray' => 1
							,'arrayAddExtra' => 1
							,'arrayDeleteNull' => 1
							,'arrayDeleteValue' => -1
							,'arrayBasicValue' => 0
							,'arrayCurrentPref' => 'titleFormatCurr'
							,'inputTemplate' => 'setup_input_array_sel.html'
							,'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [] #filled by initSetup
							,'options' => {} #filled by initSetup using hash_of_prefs('titleFormat')
							,'optionSort' => 'NK'
							,'onChange' => sub {
										my ($client,$changeref,$paramref,$pageref) = @_;
										if (exists($changeref->{'titleFormat'}{'Processed'})) {
											return;
										}
										processArrayChange($client,'titleFormat',$paramref,$pageref);
										$changeref->{'titleFormat'}{'Processed'} = 1;
									}
						}
			,'screensaver'	=> {
							'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [\&Slim::Buttons::Common::hash_of_savers,1]
							,'options' => undef #will be set by preEval  
						}
			,'idlesaver'	=> {
							'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [\&Slim::Buttons::Common::hash_of_savers,1]
							,'options' => undef #will be set by preEval  
						}
			,'offsaver'	=> {
							'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [\&Slim::Buttons::Common::hash_of_savers,1]
							,'options' => undef #will be set by preEval  
						}
			,'screensavertimeout' => {
							'validate' => \&Slim::Utils::Validate::number
							,'validateArgs' => [0,undef,1]
						}
			}
		} #end of setup{'player'} hash

	,'DISPLAY_SETTINGS' => {
		'title' => string('DISPLAY_SETTINGS')
		,'parent' => 'PLAYER_SETTINGS'
		,'isClient' => 1
		,'GroupOrder' => [undef,undef,undef,'ScrollMode','ScrollPause','ScrollRate', undef]
		,'preEval' => sub {
					my ($client,$paramref,$pageref) = @_;
					return if (!defined($client));
					playerChildren($client, $pageref);

					if ($client->isPlayer()) {
						$pageref->{'GroupOrder'}[0] = 'Brightness';
						if ($client->isa("Slim::Player::SqueezeboxG")) {
							$pageref->{'GroupOrder'}[1] = 'activeFont'; 
							$pageref->{'GroupOrder'}[2] = 'idleFont';
							$pageref->{'GroupOrder'}[6] = 'ScrollPixels';

							my $activeFontMax = $client->prefGetArrayMax('activeFont') + 1;
							my $idleFontMax = $client->prefGetArrayMax('idleFont') + 1;
							$pageref->{'Prefs'}{'activeFont_curr'}{'validateArgs'} = [0,$activeFontMax,1,1];
							$pageref->{'Prefs'}{'idleFont_curr'}{'validateArgs'} = [0,$idleFontMax,1,1];
		
							fillFontOptions($client,'DISPLAY_SETTINGS','idleFont');
							fillFontOptions($client,'DISPLAY_SETTINGS','activeFont');
							removeExtraArrayEntries($client,'activeFont',$paramref,$pageref);
							removeExtraArrayEntries($client,'idleFont',$paramref,$pageref);
						} else {
							$pageref->{'GroupOrder'}[1] = 'TextSize';
							$pageref->{'GroupOrder'}[2] = 'LargeFont';
							$pageref->{'GroupOrder'}[6] = undef;
						}

					} else {
						$pageref->{'GroupOrder'}[0] = undef;
						$pageref->{'GroupOrder'}[1] = undef;
						$pageref->{'GroupOrder'}[2] = undef;
						$pageref->{'GroupOrder'}[6] = undef;
					}

					$pageref->{'Prefs'}{'playername'}{'validateArgs'} = [$client->defaultName()];

					if (defined $client->maxBrightness) {
						$pageref->{'Prefs'}{'powerOnBrightness'}{'validateArgs'} = [0,$client->maxBrightness,1,1];
						$pageref->{'Prefs'}{'powerOffBrightness'}{'validateArgs'} = [0,$client->maxBrightness,1,1];
						$pageref->{'Prefs'}{'idleBrightness'}{'validateArgs'} = [0,$client->maxBrightness,1,1];
						
						$pageref->{'Prefs'}{'powerOnBrightness'}{'options'}{$client->maxBrightness} =  $client->maxBrightness.' ('.string('BRIGHTNESS_BRIGHTEST').')';
						$pageref->{'Prefs'}{'powerOffBrightness'}{'options'}{$client->maxBrightness} =  $client->maxBrightness.' ('.string('BRIGHTNESS_BRIGHTEST').')';
						$pageref->{'Prefs'}{'idleBrightness'}{'options'}{$client->maxBrightness} =  $client->maxBrightness.' ('.string('BRIGHTNESS_BRIGHTEST').')';
						$pageref->{'Prefs'}{'powerOnBrightness'}{'onChange'} = sub {
							my ($client, $changeref) = @_;
							if ($client->power()) { $client->brightness($changeref->{'powerOnBrightness'}{'new'}); }
						};
						$pageref->{'Prefs'}{'powerOffBrightness'}{'onChange'} = sub {
							my ($client, $changeref) = @_;
							if (!$client->power()) { $client->brightness($changeref->{'powerOffBrightness'}{'new'}); }
						};
						# Leave Slim::Buttons::Screensaver::screenSaver to change idle brightness
					} else {
						$pageref->{'Prefs'}{'powerOnBrightness'}{'validateArgs'} = [0,4,1,1];
						$pageref->{'Prefs'}{'powerOffBrightness'}{'validateArgs'} = [0,4,1,1];
						$pageref->{'Prefs'}{'idleBrightness'}{'validateArgs'} = [0,4,1,1];
						$pageref->{'Prefs'}{'idleBrightness'}{'options'}{'4'} =  '4 ('.string('BRIGHTNESS_BRIGHTEST').')';
					}

				}
		,'postChange' => sub {
					my ($client,$paramref,$pageref) = @_;
					$client->update();
				}
		#,'template' => 'setup_player.html'
		,'Groups' => {
			'Brightness' => {
					'PrefOrder' => ['powerOnBrightness','powerOffBrightness','idleBrightness','autobrightness']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'GroupHead' => string('SETUP_GROUP_BRIGHTNESS')
					,'GroupDesc' => string('SETUP_GROUP_BRIGHTNESS_DESC')
					,'GroupLine' => 1
				}
			,'TextSize' => {
					'PrefOrder' => ['doublesize','offDisplaySize']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'GroupHead' => string('SETUP_DOUBLESIZE')
					,'GroupDesc' => string('SETUP_DOUBLESIZE_DESC')
					,'GroupLine' => 1
				}
			,'LargeFont' => {
					'PrefOrder' => ['largeTextFont']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'GroupHead' => string('SETUP_LARGETEXTFONT')
					,'GroupDesc' => string('SETUP_LARGETEXTFONT_DESC')
					,'GroupLine' => 1
				}
			,'activeFont' => {
					'PrefOrder' => ['activeFont']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'GroupHead' => string('SETUP_ACTIVEFONT')
					,'GroupDesc' => string('SETUP_ACTIVEFONT_DESC')
					,'GroupPrefHead' => ''
					,'GroupLine' => 1
				}
			,'idleFont' => {
					'PrefOrder' => ['idleFont']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'GroupHead' => string('SETUP_IDLEFONT')
					,'GroupDesc' => string('SETUP_IDLEFONT_DESC')
					,'GroupPrefHead' => ''
					,'GroupLine' => 1
				}
			,'ScrollMode' => {
				'PrefOrder' => ['scrollMode']
				,'PrefsInTable' => 1
				,'Suppress_PrefHead' => 1
				,'Suppress_PrefDesc' => 1
				,'Suppress_PrefLine' => 1
				,'GroupHead' => string('SETUP_SCROLLMODE')
				,'GroupDesc' => string('SETUP_SCROLLMODE_DESC')
				,'GroupLine' => 1
			}
			,'ScrollRate' => {
				'PrefOrder' => ['scrollRate','scrollRateDouble']
				,'PrefsInTable' => 1
				,'Suppress_PrefHead' => 1
				,'Suppress_PrefDesc' => 1
				,'Suppress_PrefLine' => 1
				,'GroupHead' => string('SETUP_SCROLLRATE')
				,'GroupDesc' => string('SETUP_SCROLLRATE_DESC')
				,'GroupLine' => 1
			}
			,'ScrollPause' => {
				'PrefOrder' => ['scrollPause','scrollPauseDouble']
				,'PrefsInTable' => 1
				,'Suppress_PrefHead' => 1
				,'Suppress_PrefDesc' => 1
				,'Suppress_PrefLine' => 1
				,'GroupHead' => string('SETUP_SCROLLPAUSE')
				,'GroupDesc' => string('SETUP_SCROLLPAUSE_DESC')
				,'GroupLine' => 1
			}
			,'ScrollPixels' => {
				'PrefOrder' => ['scrollPixels','scrollPixelsDouble']
				,'PrefsInTable' => 1
				,'Suppress_PrefHead' => 1
				,'Suppress_PrefDesc' => 1
				,'Suppress_PrefLine' => 1
				,'GroupHead' => string('SETUP_SCROLLPIXELS')
				,'GroupDesc' => string('SETUP_SCROLLPIXELS_DESC')
				,'GroupLine' => 1
			}
			
			}
		,'Prefs' => {
			'powerOnBrightness' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => undef
							,'optionSort' => 'NK'
							,'options' => {
									'0' => '0 ('.string('BRIGHTNESS_DARK').')'
									,'1' => '1'
									,'2' => '2'
									,'3' => '3'
									,'4' => '4'
									}
						}
			,'powerOffBrightness' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => undef
							,'optionSort' => 'NK'
							,'options' => {
									'0' => '0 ('.string('BRIGHTNESS_DARK').')'
									,'1' => '1'
									,'2' => '2'
									,'3' => '3'
									,'4' => '4'
									}
						}
			,'idleBrightness' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => undef
							,'optionSort' => 'NK'
							,'options' => {
									'0' => '0 ('.string('BRIGHTNESS_DARK').')'
									,'1' => '1'
									,'2' => '2'
									,'3' => '3'
									,'4' => '4'
									}
						}
			,'doublesize' => {
							'validate' => \&Slim::Utils::Validate::IinList
							,'validateArgs' => [0,1]
							,'options' => {
								'0' => string('SMALL'),
								'1' => string('LARGE')
							}
							,'PrefChoose' => string('SETUP_DOUBLESIZE').string('COLON')
							,'currentValue' => sub { shift->textSize();}
							,'onChange' => sub { 
												my ($client,$changeref,$paramref,$pageref) = @_;
												return if (!defined($client));
												$client->textSize($changeref->{'textsize'}{'new'});
									}
						}
			,'offDisplaySize' => {
							'validate' => \&Slim::Utils::Validate::inList
							,'validateArgs' => [0,1]
							,'options' => {
								'0' => string('SMALL'),
								'1' => string('LARGE')
							}
							,'PrefChoose' => string('SETUP_OFFDISPLAYSIZE').string('COLON')
						}
			,'largeTextFont' => {
							'validate' => \&Slim::Utils::Validate::inList
							,'validateArgs' => [0,1]
							,'options' => {
								'0' => string('SETUP_LARGETEXTFONT_0'),
								'1' => string('SETUP_LARGETEXTFONT_1')
							}
						}
			,'activeFont'		=> {
							'isArray' => 1
							,'arrayAddExtra' => 1
							,'arrayDeleteNull' => 1
							,'arrayDeleteValue' => -1
							,'arrayBasicValue' => 0
							,'arrayCurrentPref' => 'activeFont_curr'
							,'inputTemplate' => 'setup_input_array_sel.html'
							,'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [] #filled by initSetup
							,'options' => {} #filled by initSetup using hash_of_prefs('activeFont')
							,'onChange' => sub {
										my ($client,$changeref,$paramref,$pageref) = @_;
										if (exists($changeref->{'activeFont'}{'Processed'})) {
											return;
										}
										processArrayChange($client,'activeFont',$paramref,$pageref);
										$changeref->{'activeFont'}{'Processed'} = 1;
									}
						}
			,'idleFont'		=> {
							'isArray' => 1
							,'arrayAddExtra' => 1
							,'arrayDeleteNull' => 1
							,'arrayDeleteValue' => -1
							,'arrayBasicValue' => 0
							,'arrayCurrentPref' => 'idleFont_curr'
							,'inputTemplate' => 'setup_input_array_sel.html'
							,'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [] #filled by initSetup
							,'options' => {} #filled by initSetup using hash_of_prefs('activeFont')
							,'onChange' => sub {
										my ($client,$changeref,$paramref,$pageref) = @_;
										if (exists($changeref->{'idleFont'}{'Processed'})) {
											return;
										}
										processArrayChange($client,'idleFont',$paramref,$pageref);
										$changeref->{'idleFont'}{'Processed'} = 1;
									}
						}
			,'activeFont_curr' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => undef
							,'changeIntro' => string('SETUP_ACTIVEFONT')
						}
			,'idleFont_curr' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => undef
							,'changeIntro' => string('SETUP_IDLEFONT')
						}
			,'autobrightness' => {
						'validate' => \&Slim::Utils::Validate::trueFalse
						,'options' => {
								'1' => string('SETUP_AUTOBRIGHTNESS_ON')
								,'0' => string('SETUP_AUTOBRIGHTNESS_OFF')
							}
						,'changeIntro' => string ('SETUP_AUTOBRIGHTNESS_CHOOSE')
					}
			,'scrollMode' => {
				'validate' => \&Slim::Utils::Validate::number
				,'validateArgs' => [0,undef,2]
				,'options' => {
					 '0' => string('SETUP_SCROLLMODE_DEFAULT')
					,'1' => string('SETUP_SCROLLMODE_SCROLLONCE')
					,'2' => string('SETUP_SCROLLMODE_NOSCROLL')
				},
			},
			,'scrollPause' => {
				'validate' => \&Slim::Utils::Validate::number
				,'validateArgs' => [0,undef,1]
				,'PrefChoose' => string('SINGLE-LINE').' '.string('SETUP_SCROLLPAUSE').string('COLON')
			},
			'scrollPauseDouble' => {
				'validate' => \&Slim::Utils::Validate::number
				,'validateArgs' => [0,undef,1]
				,'changeIntro' => string('DOUBLE-LINE').' '.string('SETUP_SCROLLPAUSE').string('COLON')
				,'PrefChoose' => string('DOUBLE-LINE').' '.string('SETUP_SCROLLPAUSE').string('COLON')
			},
			'scrollRate' => {
				'validate' => \&Slim::Utils::Validate::number
				,'validateArgs' => [0,undef,1]
				,'PrefChoose' => string('SINGLE-LINE').' '.string('SETUP_SCROLLRATE').string('COLON')
			},
			'scrollRateDouble' => {
				'validate' => \&Slim::Utils::Validate::number
				,'validateArgs' => [0,undef,1]
				,'changeIntro' => string('DOUBLE-LINE').' '.string('SETUP_SCROLLRATE').string('COLON')
				,'PrefChoose' => string('DOUBLE-LINE').' '.string('SETUP_SCROLLRATE').string('COLON')
			},
			'scrollPixels' => {
				'validate' => \&Slim::Utils::Validate::isInt
				,'validateArgs' => [1,20,1,20]
				,'PrefChoose' => string('SINGLE-LINE').' '.string('SETUP_SCROLLPIXELS').string('COLON')
			},
			'scrollPixelsDouble' => {
				'validate' => \&Slim::Utils::Validate::isInt
				,'validateArgs' => [1,20,1,20]
				,'changeIntro' => string('DOUBLE-LINE').' '.string('SETUP_SCROLLPIXELS').string('COLON')
				,'PrefChoose' => string('DOUBLE-LINE').' '.string('SETUP_SCROLLPIXELS').string('COLON')
			},
		}
	}
	,'MENU_SETTINGS' => {
		'title' => string('MENU_SETTINGS')
		,'parent' => 'PLAYER_SETTINGS'
		,'isClient' => 1
		,'GroupOrder' => ['MenuItems','NonMenuItems','Plugins']
		,'preEval' => sub {
					my ($client,$paramref,$pageref) = @_;
					return if (!defined($client));
					playerChildren($client, $pageref);
					$pageref->{'Prefs'}{'menuItemAction'}{'arrayMax'} = $client->prefGetArrayMax('menuItem');
					my $i = 0;
					foreach my $nonItem (Slim::Buttons::Home::unusedMenuOptions($client)) {
						$paramref->{'nonMenuItem' . $i++} = $nonItem;
					}
					$pageref->{'Prefs'}{'nonMenuItem'}{'arrayMax'} = $i - 1;
					$pageref->{'Prefs'}{'nonMenuItemAction'}{'arrayMax'} = $i - 1;
					removeExtraArrayEntries($client,'menuItem',$paramref,$pageref);
					$i = 0;
					foreach my $pluginItem (Slim::Utils::PluginManager::unusedPluginOptions($client)) {
						$paramref->{'pluginItem' . $i++} = $pluginItem;
					}
					$pageref->{'Prefs'}{'pluginItem'}{'arrayMax'} = $i - 1;
					$pageref->{'Prefs'}{'pluginItemAction'}{'arrayMax'} = $i - 1;
					removeExtraArrayEntries($client,'menuItem',$paramref,$pageref);
				}
		,'postChange' => sub {
					my ($client,$paramref,$pageref) = @_;
					my $i = 0;
					return if (!defined($client));
					#refresh paramref for menuItem array
					foreach my $menuitem ($client->prefGetArray('menuItem')) {
						$paramref->{'menuItem' . $i++} = $menuitem;
					}
					$pageref->{'Prefs'}{'menuItemAction'}{'arrayMax'} = $i - 1;
					while (exists $paramref->{'menuItem' . $i}) {
						delete $paramref->{'menuItem' . $i++};
					}
					#refresh paramref for nonMenuItem array
					$i = 0;
					foreach my $nonItem (Slim::Buttons::Home::unusedMenuOptions($client)) {
						$paramref->{'nonMenuItem' . $i++} = $nonItem;
					}
					$pageref->{'Prefs'}{'nonMenuItem'}{'arrayMax'} = $i - 1;
					$pageref->{'Prefs'}{'nonMenuItemAction'}{'arrayMax'} = $i - 1;
					while (exists $paramref->{'nonMenuItem' . $i}) {
						delete $paramref->{'nonMenuItem' . $i++};
					}
					$i = 0;
					foreach my $pluginItem (Slim::Utils::PluginManager::unusedPluginOptions($client)) {
						$paramref->{'pluginItem' . $i++} = $pluginItem;
					}
					$pageref->{'Prefs'}{'pluginItem'}{'arrayMax'} = $i - 1;
					$pageref->{'Prefs'}{'pluginItemAction'}{'arrayMax'} = $i - 1;
					while (exists $paramref->{'pluginItem' . $i}) {
						delete $paramref->{'pluginItem' . $i++};
					}
				}
		,'Groups' => {
			'MenuItems' => {
					'PrefOrder' => ['menuItem']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => string('SETUP_GROUP_MENUITEMS')
					,'GroupDesc' => string('SETUP_GROUP_MENUITEMS_DESC')
				}
			,'NonMenuItems' => {
					'PrefOrder' => ['nonMenuItem']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => ''
					,'GroupDesc' => string('SETUP_GROUP_NONMENUITEMS_INTRO')
				}
			,'Plugins' => {
					'PrefOrder' => ['pluginItem']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => ''
					,'GroupDesc' => string('SETUP_GROUP_PLUGINITEMS_INTRO')
					,'GroupLine' => 1
				}
		}
		,'Prefs' => {
			'menuItem'	=> {
						'isArray' => 1
						,'arrayDeleteNull' => 1
						,'arrayDeleteValue' => ''
						,'arrayBasicValue' => 'NOW_PLAYING'
						,'inputTemplate' => 'setup_input_array_udr.html'
						,'validate' => \&Slim::Utils::Validate::IinHash
						,'validateArgs' => [\&Slim::Buttons::Home::menuOptions]
						,'externalValue' => \&menuItemName
						,'onChange' => sub {
									my ($client,$changeref,$paramref,$pageref) = @_;
									#Handle all changed items whenever the first one is encountered
									#then set 'Processed' so that the changes aren't repeated
									if (exists($changeref->{'menuItem'}{'Processed'})) {
										return;
									}
									processArrayChange($client,'menuItem',$paramref,$pageref);
									Slim::Buttons::Home::updateMenu($client);
									$changeref->{'menuItem'}{'Processed'} = 1;
								}
					}
			,'menuItemAction' => {
						'isArray' => 1
						,'dontSet' => 1
						,'arrayMax' => undef #set in preEval
						,'noWarning' => 1
						,'onChange' => sub {
									my ($client,$changeref,$paramref,$pageref) = @_;
									#Handle all changed items whenever the first one is encountered
									#then set 'Processed' so that the changes aren't repeated
									if (exists($changeref->{'menuItemAction'}{'Processed'})) {
										return;
									}
									my $i;
									for ($i = $client->prefGetArrayMax('menuItem'); $i >= 0; $i--) {
										if (exists $changeref->{'menuItemAction' . $i}) {
											my $newval = $changeref->{'menuItemAction' . $i}{'new'};
											my $tempItem = $client->prefGet('menuItem',$i);
											if (defined $newval) {
												if ($newval eq 'Remove') {
													$client->prefDelete('menuItem',$i);
												} elsif ($newval eq 'Up' && $i > 0) {
													$client->prefSet('menuItem',$client->prefGet('menuItem',$i - 1),$i);
													$client->prefSet('menuItem',$tempItem,$i - 1);
												} elsif ($newval eq 'Down' && $i < $client->prefGetArrayMax('menuItem')) {
													$client->prefSet('menuItem',$client->prefGet('menuItem',$i + 1),$i);
													$client->prefSet('menuItem',$tempItem,$i + 1);
												}
											}
										}
									}
									if ($client->prefGetArrayMax('menuItem') < 0) {
										$client->prefSet('menuItem',$pageref->{'Prefs'}{'menuItem'}{'arrayBasicValue'},0);
									}
									Slim::Buttons::Home::updateMenu($client);
									$changeref->{'menuItemAction'}{'Processed'} = 1;
								}
					}
			,'nonMenuItem'	=> {
						'isArray' => 1
						,'dontSet' => 1
						,'arrayMax' => undef #set in preEval
						,'noWarning' => 1
						,'inputTemplate' => 'setup_input_array_add.html'
						,'externalValue' => \&menuItemName
					}
			,'nonMenuItemAction' => {
						'isArray' => 1
						,'dontSet' => 1
						,'arrayMax' => undef #set in preEval
						,'noWarning' => 1
						,'onChange' => sub {
									my ($client,$changeref,$paramref,$pageref) = @_;
									return if (!defined($client));
									#Handle all changed items whenever the first one is encountered
									#then set 'Processed' so that the changes aren't repeated
									if (exists($changeref->{'menuItemAction'}{'Processed'})) {
										return;
									}
									my $i;
									for ($i = $pageref->{'Prefs'}{'nonMenuItemAction'}{'arrayMax'}; $i >= 0; $i--) {
										if (exists $changeref->{'nonMenuItemAction' . $i}) {
											if ($changeref->{'nonMenuItemAction' . $i}{'new'} eq 'Add') {
												$client->prefPush('menuItem',$paramref->{'nonMenuItem' . $i});
											}
										}
									}
									Slim::Buttons::Home::updateMenu($client);
									$changeref->{'nonMenuItemAction'}{'Processed'} = 1;
								}
					}
			,'pluginItem'	=> {
						'isArray' => 1
						,'dontSet' => 1
						,'arrayMax' => undef #set in preEval
						,'noWarning' => 1
						,'inputTemplate' => 'setup_input_array_add.html'
						,'externalValue' => \&menuItemName
					}
			,'pluginItemAction' => {
						'isArray' => 1
						,'dontSet' => 1
						,'arrayMax' => undef #set in preEval
						,'noWarning' => 1
						,'onChange' => sub {
									my ($client,$changeref,$paramref,$pageref) = @_;
									return if (!defined($client));
									#Handle all changed items whenever the first one is encountered
									#then set 'Processed' so that the changes aren't repeated
									if (exists($changeref->{'menuItemAction'}{'Processed'})) {
										return;
									}
									my $i;
									for ($i = $pageref->{'Prefs'}{'pluginItemAction'}{'arrayMax'}; $i >= 0; $i--) {
										if (exists $changeref->{'pluginItemAction' . $i}) {
											if ($changeref->{'pluginItemAction' . $i}{'new'} eq 'Add') {
												$client->prefPush('menuItem',$paramref->{'pluginItem' . $i});
											}
										}
									}
									Slim::Buttons::Home::updateMenu($client);
									$changeref->{'pluginItemAction'}{'Processed'} = 1;
								}
					}
			}
	}
	,'ALARM_SETTINGS' => {
		'title' => string('ALARM_SETTINGS')
		,'parent' => 'PLAYER_SETTINGS'
		,'isClient' => 1
		,'preEval' => sub {
				my ($client,$paramref,$pageref) = @_;
				return if (!defined($client));
				playerChildren($client, $pageref);
				my $playlistRef = playlists();
				$playlistRef->{''} = undef;
				my $specialPlaylists = Slim::Buttons::AlarmClock::getSpecialPlaylists;
				for my $key (keys %{$specialPlaylists}) {
					$playlistRef->{$key} = $key;
				}
				for my $i (0..7) {
					$pageref->{'Prefs'}{'alarmplaylist'.$i}{'options'} = $playlistRef;
					$pageref->{'Prefs'}{'alarmplaylist'.$i}{'validateArgs'} = [$playlistRef];
				}
				if (!$paramref->{'playername'}) {
					$paramref->{'playername'} = $client->name();
				}
			}
		,'GroupOrder' => ['AlarmClock','AlarmDay0','AlarmDay1','AlarmDay2','AlarmDay3','AlarmDay4','AlarmDay5','AlarmDay6','AlarmDay7']
		,'Groups' => {
			'AlarmClock' => {
				'PrefOrder' => ['alarmfadeseconds']
				,'GroupHead' => string('SETUP_GROUP_ALARM')
				,'GroupDesc' => string('SETUP_GROUP_ALARM_DESC')
				,'GroupLine' => 1
				,'Suppress_PrefLine' => 1
				,'Suppress_PrefHead' => 1
			}
		}
		,'Prefs' => {
			'alarmfadeseconds' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'PrefChoose' => string('ALARM_FADE'),
				'changeIntro' => string('ALARM_FADE').string('COLON'),
				'inputTemplate' => 'setup_input_chk.html',
			}
		},
	}
	,'AUDIO_SETTINGS' => {
		'title' => string('AUDIO_SETTINGS')
		,'parent' => 'PLAYER_SETTINGS'
		,'isClient' => 1
		,'preEval' => sub {

					my ($client,$paramref,$pageref) = @_;
					return if (!defined($client));
					playerChildren($client, $pageref);
					if (Slim::Player::Sync::isSynced($client) || (scalar(Slim::Player::Sync::canSyncWith($client)) > 0))  {
						$pageref->{'GroupOrder'}[0] = 'Synchronize';
						my $syncGroupsRef = syncGroups($client);
						$pageref->{'Prefs'}{'synchronize'}{'options'} = $syncGroupsRef;
						$pageref->{'Prefs'}{'synchronize'}{'validateArgs'} = [$syncGroupsRef];
					} else {
						$pageref->{'GroupOrder'}[0] = undef;
					}
					
					if ($client && $client->hasPreAmp()) {
						$pageref->{'Groups'}{'Digital'}{'PrefOrder'}[1] = 'preampVolumeControl';
					} else {
						$pageref->{'Groups'}{'Digital'}{'PrefOrder'}[1] = undef;
					}
					
					if ($client->maxTransitionDuration()) {
						$pageref->{'GroupOrder'}[2] = 'Transition';
						$pageref->{'Prefs'}{'transitionDuration'}{'validateArgs'} = [0, $client->maxTransitionDuration(),1,1];
					} else {
						$pageref->{'GroupOrder'}[2] = undef;
					}
					
					if ($client && $client->hasDigitalOut()) {
						$pageref->{'GroupOrder'}[3] = 'Digital';
					} else {
						$pageref->{'GroupOrder'}[3] = undef;
					}
					
					if (Slim::Utils::Misc::findbin('lame')) {
						$pageref->{'Prefs'}{'lame'}{'PrefDesc'} = string('SETUP_LAME_FOUND');
						$pageref->{'GroupOrder'}[4] = 'Quality';
					} else {
						$pageref->{'Prefs'}{'lame'}{'PrefDesc'} = string('SETUP_LAME_NOT_FOUND');
						$pageref->{'GroupOrder'}[4] = undef;
					}
					
					$pageref->{'GroupOrder'}[5] ='Format';
					my @formats = $client->formats();
					if ($formats[0] ne 'mp3') {
						$pageref->{'Groups'}{'Format'}{'GroupDesc'} = string('SETUP_MAXBITRATE_DESC');
						$pageref->{'Prefs'}{'maxBitrate'}{'options'}{'0'} = '  '.string('NO_LIMIT');
					} else {
						delete $pageref->{'Prefs'}{'maxBitrate'}{'options'}{'0'};
						$pageref->{'Groups'}{'Format'}{'GroupDesc'} = string('SETUP_MP3BITRATE_DESC');
					}

					if ($client->canDoReplayGain(0)) {
						$pageref->{'GroupOrder'}[6] = 'ReplayGain';
					} else {
						$pageref->{'GroupOrder'}[6] = undef;
					}

		}
		,'postChange' => sub {
					my ($client,$paramref,$pageref) = @_;
					return if (!defined($client));
					if (Slim::Player::Client::clientCount() > 1 ) {
						$pageref->{'Prefs'}{'synchronize'}{'options'} = syncGroups($client);
						if (!exists($paramref->{'synchronize'})) {
							if (Slim::Player::Sync::isSynced($client)) {
								my $master = Slim::Player::Sync::master($client);
								$paramref->{'synchronize'} = $master->id();
							} else {
								$paramref->{'synchronize'} = -1;
							}
						}
					}
					$client->update();
				}
		,'GroupOrder' => [undef,'PowerOn',undef,undef,undef,undef]
		,'Groups' => {
			'PowerOn' => {
					'PrefOrder' => ['powerOnResume']
				}
			,'Format' => {
					'PrefOrder' => ['lame','maxBitrate']
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => string('SETUP_MAXBITRATE')
					,'GroupLine' => 1
					,'GroupSub' => 1
				}
			,'Quality' => {
					'PrefOrder' => ['lameQuality']
				}
			,'Synchronize' => {
					'PrefOrder' => ['synchronize','syncVolume','syncPower']
				}
			,'Digital' => {
					'PrefOrder' => ['digitalVolumeControl','preampVolumeControl','mp3SilencePrelude']
				}
			,'Transition' => {
					'PrefOrder' => ['transitionType', 'transitionDuration']
				}
			,'ReplayGain' => {
					'PrefOrder' => ['replayGainMode']
				}
		}
		,'Prefs' => {
			'powerOnResume' => {
					'options' => {
							'PauseOff-NoneOn' => string('SETUP_POWERONRESUME_PAUSEOFF_NONEON')
							,'PauseOff-PlayOn' => string('SETUP_POWERONRESUME_PAUSEOFF_PLAYON')
							,'StopOff-PlayOn' => string('SETUP_POWERONRESUME_STOPOFF_PLAYON')
							,'StopOff-NoneOn' => string('SETUP_POWERONRESUME_STOPOFF_NONEON')
							,'StopOff-ResetPlayOn' => string('SETUP_POWERONRESUME_STOPOFF_RESETPLAYON')
							,'StopOff-ResetOn' => string('SETUP_POWERONRESUME_STOPOFF_RESETON')
						}
					,'currentValue' => sub {
							my ($client,$key,$ind) = @_;
							return if (!defined($client));
							return Slim::Player::Sync::syncGroupPref($client,'powerOnResume') ||
								   $client->prefGet('powerOnResume');
					}
					,'onChange' => sub {
							my ($client,$changeref,$paramref,$pageref) = @_;
							return if (!defined($client));

							my $newresume = $changeref->{'powerOnResume'}{'new'};
							if (Slim::Player::Sync::syncGroupPref($client,'powerOnResume')) {
								Slim::Player::Sync::syncGroupPref($client,'powerOnResume',$newresume);
							}
						}
					}
							
			,'maxBitrate' => {
							'validate' => \&Slim::Utils::Validate::inList
							,'validateArgs' => [0, 64, 96, 128, 160, 192, 256, 320]
							,'optionSort' => 'NK'
							,'currentValue' => sub { return Slim::Utils::Prefs::maxRate(shift, 1); }
							,'options' => {
									'0' => string('NO_LIMIT')
									,'64' => '64 '.string('KBPS')
									,'96' => '96 '.string('KBPS')
									,'128' => '128 '.string('KBPS')
									,'160' => '160 '.string('KBPS')
									,'192' => '192 '.string('KBPS')
									,'256' => '256 '.string('KBPS')
									,'320' => '320 '.string('KBPS')
								}
							,'PrefDesc' => undef
						}
			,'lame' => {
						'validate' => \&Slim::Utils::Validate::acceptAll
						,'validateArgs' => [] #filled by preEval
						,'noWarning' => 1
						,'dontSet' => 1
						,'inputTemplate' => undef
						}
			,'lameQuality' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => [0,9,1,1]
							,'optionSort' => 'NK'
							,'options' => {
									'0' => '0 '.string('LAME0')
									,'1' => '1'
									,'2' => '2'
									,'3' => '3'
									,'4' => '4'
									,'5' => '5'
									,'6' => '6'
									,'7' => '7'
									,'8' => '8'
									,'9' => '9 '.string('LAME9')
								}
						}
			,'synchronize' => {
							'dontSet' => 1
							,'options' => {} #filled by preEval
							,'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [] #filled by initSetup
							,'currentValue' => sub {
									my ($client,$key,$ind) = @_;
									return if (!defined($client));
									if (Slim::Player::Sync::isSynced($client)) {
										return $client->id();
									} else {
										return -1;
									}
								}
							,'onChange' => sub {
									my ($client,$changeref,$paramref,$pageref) = @_;
									return if (!defined($client));
									if ($changeref->{'synchronize'}{'new'} eq -1) {
										Slim::Player::Sync::unsync($client);
									} else {
										Slim::Player::Sync::sync($client,Slim::Player::Client::getClient($changeref->{'synchronize'}{'new'}));
									}
								}
						}
			,'syncVolume' => {
							'validate' => \&Slim::Utils::Validate::trueFalse  
							,'options' => {
									'1' => string('SETUP_SYNCVOLUME_ON')
									,'0' => string('SETUP_SYNCVOLUME_OFF')
								}
						}			
			,'syncPower' => {
							'validate' => \&Slim::Utils::Validate::trueFalse  
							,'options' => {
									'1' => string('SETUP_SYNCPOWER_ON')
									,'0' => string('SETUP_SYNCPOWER_OFF')
								}
							,'onChange' => sub {
								my ($client,$changeref,$paramref,$pageref) = @_;
								return if (!defined($client));
								my $value = $changeref->{'syncPower'}{'new'};
								my @buddies = Slim::Player::Sync::syncedWith($client);
								if (scalar(@buddies) > 0) {
									foreach my $eachclient (@buddies) {
										if (!$value && !$eachclient->power()) {
											#temporarily unsync off players if on/off set to separate
											Slim::Player::Sync::unsync($client,1);
										} 
										$eachclient->prefSet('syncPower',$value);
									}
								}
							}
						}
			,'digitalVolumeControl' => {
							'validate' => \&Slim::Utils::Validate::trueFalse  
							,'options' => {
									'1' => string('SETUP_DIGITALVOLUMECONTROL_ON')
									,'0' => string('SETUP_DIGITALVOLUMECONTROL_OFF')
								}
							,'onChange' => sub {
								my $client = shift;
								$client->volume($client->volume());
							}
						}
			,'preampVolumeControl' => {
							'validate' => \&Slim::Utils::Validate::number
							,'validateArgs' => [0, undef, 63]
						}
			,'mp3SilencePrelude' => {
							'validate' => \&Slim::Utils::Validate::number  
							,'validateArgs' => [0,undef,5]
						}
			,'transitionType' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => [0,4,1,1]
							,'optionSort' => 'K'
							,'options' => {
									'0' => string('TRANSITION_NONE')
									,'1' => string('TRANSITION_CROSSFADE')
									,'2' => string('TRANSITION_FADE_IN')
									,'3' => string('TRANSITION_FADE_OUT')
									,'4' => string('TRANSITION_FADE_IN_OUT')
								}
						}
			,'transitionDuration' => {
							'validate' => \&Slim::Utils::Validate::isInt  
						}
			,'replayGainMode' => {
							'optionSort' => 'K',
							'options' => {
									'0' => string('REPLAYGAIN_DISABLED'),
									'1' => string('REPLAYGAIN_TRACK_GAIN'),
									'2' => string('REPLAYGAIN_ALBUM_GAIN'),
									'3' => string('REPLAYGAIN_SMART_GAIN'),
								},
						}
		}
	}
	,'REMOTE_SETTINGS' => {
		'title' => string('REMOTE_SETTINGS')
		,'parent' => 'PLAYER_SETTINGS'
		,'isClient' => 1
		,'preEval' => sub {
				my ($client,$paramref,$pageref) = @_;
				return if (!defined($client));
				playerChildren($client, $pageref);
				if (scalar(keys %{Slim::Hardware::IR::mapfiles()}) > 1) {  
					$pageref->{'GroupOrder'}[1] = 'IRMap';  
					$pageref->{'Prefs'}{'irmap'}{'options'} = Slim::Hardware::IR::mapfiles();  
				} else {  
					$pageref->{'GroupOrder'}[1] = undef;
				}
				my $i = 0;
				my %irsets = map {$_ => 1} $client->prefGetArray('disabledirsets');
				foreach my $irset (sort(keys %{Slim::Hardware::IR::irfiles()})) {
					if (exists $paramref->{"irsetlist$i"} && $paramref->{"irsetlist$i"} == (exists $irsets{$irset} ? 0 : 1)) {
						delete $paramref->{"irsetlist$i"};
					}
					$i++;
				}
				$pageref->{'Prefs'}{'irsetlist'}{'arrayMax'} = $i - 1;
				if (!$paramref->{'playername'}) {
					$paramref->{'playername'} = $client->name();
				}
			}
		,'postChange' => sub {
				my ($client,$paramref,$pageref) = @_;
				return if (!defined($client));
				my $i = 0;
				my %irsets = map {$_ => 1} $client->prefGetArray('disabledirsets');
				$client->prefDelete('disabledirsets');
				foreach my $irset (sort(keys %{Slim::Hardware::IR::irfiles()})) {
					if (!exists $paramref->{"irsetlist$i"}) {
						$paramref->{"irsetlist$i"} = exists $irsets{$irset} ? 0 : 1;
					}
					unless ($paramref->{"irsetlist$i"}) {
						$client->prefPush('disabledirsets',$irset);
					}
					Slim::Hardware::IR::loadIRFile($irset);
					$i++;
				}
			}
		,'GroupOrder' => ['IRSets']
		# if more than one ir map exists the undef will be replaced by 'Default'
		,'Groups' => {
			'IRSets' => {
				'PrefOrder' => ['irsetlist']
				,'PrefsInTable' => 1
				,'Suppress_PrefHead' => 1
				,'Suppress_PrefDesc' => 1
				,'Suppress_PrefLine' => 1
				,'Suppress_PrefSub' => 1
				,'GroupHead' => string('SETUP_GROUP_IRSETS')
				,'GroupDesc' => string('SETUP_GROUP_IRSETS_DESC')
				,'GroupLine' => 1
				,'GroupSub' => 1
			}
			,'IRMap' => {
				'PrefOrder' => ['irmap']
			}
		}
		,'Prefs' => {
			'irmap' => {
				'validate' => \&Slim::Utils::Validate::inHash  
				,'validateArgs' => [\&Slim::Hardware::IR::mapfiles,1]  
				,'options' => undef #will be set by preEval  
			},
			'irsetlist' => {
				'isArray' => 1
				,'dontSet' => 1
				,'validate' => \&Slim::Utils::Validate::trueFalse
				,'inputTemplate' => 'setup_input_array_chk.html'
				,'arrayMax' => undef #set in preEval
				,'changeMsg' => string('SETUP_IRSETLIST_CHANGE')
				,'externalValue' => sub {
							my ($client,$value,$key) = @_;
							return if (!defined($client));
							if ($key =~ /\D+(\d+)$/) {
								return Slim::Hardware::IR::irfileName((sort(keys %{Slim::Hardware::IR::irfiles()}))[$1]);
							} else {
								return $value;
							}
						}
			},
		}
	}
	,'PLAYER_PLUGINS' => {
		'title' => string('PLUGINS')
		,'parent' => 'PLAYER_SETTINGS'
		,'isClient' => 1
		,'preEval' => sub {
				my ($client,$paramref,$pageref) = @_;
				return if (!defined($client));
				playerChildren($client, $pageref);
			}
	} # end of setup{'ADDITIONAL_PLAYER'} hash

	,'SERVER_SETTINGS' => {

		'children' => [qw(SERVER_SETTINGS INTERFACE_SETTINGS BEHAVIOR_SETTINGS FORMATS_SETTINGS FORMATTING_SETTINGS SECURITY_SETTINGS PERFORMANCE_SETTINGS NETWORK_SETTINGS DEBUGGING_SETTINGS)],
		'title'    => string('SERVER_SETTINGS'),
		'singleChildLinkText' => string('ADDITIONAL_SERVER_SETTINGS'),

		'preEval'  => sub {
			my ($client, $paramref, $pageref) = @_;

			$paramref->{'versionInfo'} = Slim::Utils::Misc::settingsDiagString() . "\n<p>";
			$paramref->{'newVersion'}  = $::newVersion;
		},

		'GroupOrder' => [qw(language Default Rescan)],

		'Groups' => {

			'language' => {
				'PrefOrder' => ['language'],
			},

			'Default' => {
				'PrefOrder' => ['audiodir', 'playlistdir', undef],
			},

			'Rescan' => {
				'PrefOrder' => [qw(rescantype rescan)],
				'Suppress_PrefHead' => 1,
				'Suppress_PrefDesc' => 1,
				'Suppress_PrefLine' => 1,
				'Suppress_PrefSub' => 1,
				'GroupHead' => string('SETUP_RESCAN'),
				'GroupDesc' => string('SETUP_RESCAN_DESC'),
				'GroupLine' => 1,
			},
		},

		'Prefs' => {

			'language' => {

				'validate'     => \&Slim::Utils::Validate::inHash,
				'validateArgs' => [\&Slim::Utils::Strings::hash_of_languages],
				'options'      => undef,  # filled by initSetup using Slim::Utils::Strings::hash_of_languages()
				'onChange'     => sub {
					Slim::Utils::PluginManager::clearPlugins();
					Slim::Utils::Strings::init();
					Slim::Web::Setup::initSetup();
					Slim::Utils::PluginManager::initPlugins();
					Slim::Music::Import::resetSetupGroups();
				},
			},

			'audiodir' => {
				'validate'     => \&Slim::Utils::Validate::isDir,
				'validateArgs' => [1],
				'changeIntro'  => string('SETUP_OK_USING'),
				'rejectMsg'    => string('SETUP_BAD_DIRECTORY'),
				'PrefSize'     => 'large',
			},

			'playlistdir' => {
				'validate'     => \&Slim::Utils::Validate::isDir,
				'validateArgs' => [1],
				'changeIntro'  => string('SETUP_PLAYLISTDIR_OK'),
				'rejectMsg'    => string('SETUP_BAD_DIRECTORY'),
				'PrefSize'     => 'large',
			},

			'rescan' => {

				'validate' => \&Slim::Utils::Validate::acceptAll,

				'onChange' => sub {
					my ($client, $changeref) = @_;

					my $rescanType = ['rescan'];

					if ($changeref->{'rescantype'}{'new'} eq '2wipedb') {

						$rescanType = ['wipecache'];

					} elsif ($changeref->{'rescantype'}{'new'} eq '3playlist') {

						$rescanType = [qw(rescan playlists)];
					}

					Slim::Control::Request::executeRequest($client, $rescanType);
				},
				'inputTemplate' => 'setup_input_submit.html',
				'ChangeButton'  => string('SETUP_RESCAN_BUTTON'),
				'changeIntro'   => string('RESCANNING'),
				'dontSet'       => 1,
				'changeMsg'     => '',
			},
			'rescantype' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'optionSort' => 'K',
				'options' => {
					'1rescan'   => string('SETUP_STANDARDRESCAN'),
					'2wipedb'   => string('SETUP_WIPEDB'),
					'3playlist' => string('SETUP_PLAYLISTRESCAN'),
				},
				'dontSet'       => 1,
				'changeMsg'     => '',
				'changeIntro'     => '',
			}
		},

	} #end of setup{'server'} hash

	,'PLUGINS' => {
		'title' => string('PLUGINS')
		,'parent' => 'SERVER_SETTINGS'
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
					,'GroupHead' => string('SETUP_GROUP_PLUGINS')
					,'GroupDesc' => string('SETUP_GROUP_PLUGINS_DESC')
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
				,'changeMsg' => string('SETUP_PLUGINLIST_CHANGE')
				,'onChange' => \&Slim::Utils::PluginManager::clearGroups
				,'externalValue' => sub {
						my ($client, $value, $key) = @_;
						return getPluginState($client, $value, $key);
					}
				}
			,'plugins-onthefly' => {
				'validate' => \&Slim::Utils::Validate::trueFalse
				,'options' => {
						'1' => string('SETUP_PLUGINS-ONTHEFLY_1')
						,'0' => string('SETUP_PLUGINS-ONTHEFLY_0')
					}
				}
			}
		} #end of setup{'PLUGINS'}
	,'RADIO' => {
		'title' => string('RADIO')
		,'parent' => 'SERVER_SETTINGS'
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
					,'GroupHead' => string('RADIO')
					,'GroupDesc' => string('SETUP_GROUP_RADIO_DESC')
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
				,'changeMsg' => string('SETUP_PLUGINLIST_CHANGE')
				,'onChange' => \&Slim::Utils::PluginManager::clearGroups
				,'externalValue' => sub {
						my ($client,$value,$key) = @_;
						return getPluginState($client, $value, $key, 'RADIO');
					}
				}
			}
		} #end of setup{'RADIO'}
	,'INTERFACE_SETTINGS' => {
		'title' => string('INTERFACE_SETTINGS')
		,'parent' => 'SERVER_SETTINGS'
		,'preEval' => sub {
					my ($client,$paramref,$pageref) = @_;
					$pageref->{'Prefs'}{'skin'}{'options'} = {skins(1)};
				}
		,'GroupOrder' => ['Default']
		,'Groups' => {
			'Default' => {
					'PrefOrder' => ['skin','itemsPerPage','refreshRate','coverArt','coverThumb',
					'artfolder','thumbSize','includeNoArt','sortBrowseArt']
				}
			}
		,'Prefs' => {
			'skin'		=> {
						'validate' => \&Slim::Utils::Validate::inHash
						,'validateArgs' => [\&skins]
						,'options' => undef #filled by initSetup using skins()
						,'changeIntro' => string('SETUP_SKIN_OK')
						,'changeAddlText' => string('HIT_RELOAD')
						,'onChange' => sub {
							for my $client (Slim::Player::Client::clients()) {
								$client->currentPlaylistChangeTime(time());
							}
						}
					}
			,'itemsPerPage'	=> {
						'validate' => \&Slim::Utils::Validate::isInt
						,'validateArgs' => [1,undef,1]
					}
			,'refreshRate'	=> {
						'validate' => \&Slim::Utils::Validate::isInt
						,'validateArgs' => [2,undef,1]
					}
			,'coverArt' => {
						'validate' => \&Slim::Utils::Validate::acceptAll
						,'PrefSize' => 'large'
					}
			,'coverThumb' => {
						'validate' => \&Slim::Utils::Validate::acceptAll
						,'PrefSize' => 'large'
					}
			,'artfolder' => {
					'validate' => \&Slim::Utils::Validate::isDir
					,'validateArgs' => [1]
					,'changeIntro' => string('SETUP_ARTFOLDER')
					,'rejectMsg' => string('SETUP_BAD_DIRECTORY')
					,'PrefSize' => 'large'
				}
			,'thumbSize' => {
					'validate' => \&Slim::Utils::Validate::isInt
					,'validateArgs' => [25,250,1,1]
				}
			,'includeNoArt' => {
						'validate' => \&Slim::Utils::Validate::trueFalse
						,'options' => {
								'1' => string('SETUP_INCLUDENOART_1')
								,'0' => string('SETUP_INCLUDENOART_0')
							}
					}
			,'sortBrowseArt' => {
						'validate' => \&validateAcceptAll
						,'options' => {
								'album' => string('SETUP_SORTBROWSEART_ALBUM')
								,'artist,album' => string('SETUP_SORTBROWSEART_ARTISTALBUM')
								,'artist,year,album' => string('SETUP_SORTBROWSEART_ARTISTYEARALBUM')
								,'year,album' => string('SETUP_SORTBROWSEART_YEARALBUM')
								,'year,artist,album' => string('SETUP_SORTBROWSEART_YEARARTISTALBUM')
								,'genre,album' => string('SETUP_SORTBROWSEART_GENREALBUM')
								,'genre,artist,album' => string('SETUP_SORTBROWSEART_GENREARTISTALBUM')
							}
					}
			}
		}# end of setup{'INTERFACE_SETTINGS'} hash

	,'FORMATS_SETTINGS' => {
		'title' => string('FORMATS_SETTINGS')
		,'parent' => 'SERVER_SETTINGS'
		,'preEval' => sub {
				my ($client,$paramref,$pageref) = @_;
				my $i = 0;
				my %formats = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledformats');
				my $formatslistref = Slim::Player::TranscodingHelper::Conversions();

				foreach my $formats (sort {$a cmp $b}(keys %{$formatslistref})) {
					next if $formats =~ /\-transcode\-/;
					my $oldVal = exists $formats{$formats} ? 0 : (Slim::Player::TranscodingHelper::checkBin($formats) ? 1 : 0);
					if (exists $paramref->{"formatslist$i"} && $paramref->{"formatslist$i"} == $oldVal) {
						delete $paramref->{"formatslist$i"};
					}
					$i++;
				}
				$pageref->{'Prefs'}{'formatslist'}{'arrayMax'} = $i - 1;
			}
		,'postChange' => sub {
				my ($client,$paramref,$pageref) = @_;
				my $i = 0;
				my %formats = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledformats');

				Slim::Utils::Prefs::delete('disabledformats');

				my $formatslistref = Slim::Player::TranscodingHelper::Conversions();

				foreach my $formats (sort {$a cmp $b}(keys %{$formatslistref})) {
					next if $formats =~ /\-transcode\-/;
					my $binAvailable = Slim::Player::TranscodingHelper::checkBin($formats);

					# First time through, set the value of the checkbox
					# based on whether the conversion was explicitly 
					# disabled or implicitly disallowed because the 
					# corresponding binary does not exist.
					if (!exists $paramref->{"formatslist$i"}) {
						$paramref->{"formatslist$i"} = exists $formats{$formats} ? 0 : ($binAvailable ? 1 : 0);					
					} 
					# If the conversion pref is checked confirm that 
					# it's allowed to be checked.
					elsif ($paramref->{"formatslist$i"} && !$binAvailable) {
						$paramref->{'warning'} .= 
							string('SETUP_FORMATSLIST_MISSING_BINARY') .
								" " . $formatslistref->{$formats}."<br>";
						$paramref->{"formatslist$i"} = $binAvailable;
					} 

					# If the conversion pref is not checked, persist
					# the pref only in the explicit change case: if
					# the binary is available or if it previously was
					# explicitly disabled.  This way we don't persist
					# the pref if it wasn't explicitly changed.
					if (!$paramref->{"formatslist$i"} &&
						($binAvailable || exists $formats{$formats})) {
						Slim::Utils::Prefs::push('disabledformats',$formats);
					}
					$i++;
				}
				foreach my $group (Slim::Utils::Prefs::getArray('disabledformats')) {
					delGroup('formats',$group,1);
				}
			}
		,'GroupOrder' => ['Default']
		# if more than one ir map exists the undef will be replaced by 'Default'
		,'Groups' => {
				'Default' => {
					'PrefOrder' => ['formatslist']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => string('SETUP_GROUP_FORMATS')
					,'GroupDesc' => string('SETUP_GROUP_FORMATS_DESC')
					,'GroupLine' => 1
					,'GroupSub' => 1
					,'GroupPrefHead' => '<tr><th>&nbsp;' .
										'</th><th>' . string('FILE_FORMAT') .
										'</th><th>' . string('STREAM_FORMAT') .
										'</th><th>' . string('DECODER') .
										'</th></tr>'
				}
			}
		,'Prefs' => {
				'formatslist' => {
					'isArray' => 1
					,'dontSet' => 1
					,'validate' => \&Slim::Utils::Validate::trueFalse
					,'inputTemplate' => 'setup_input_array_chk.html'
					,'arrayMax' => undef #set in preEval
					,'changeMsg' => string('SETUP_FORMATSLIST_CHANGE')
					,'externalValue' => sub {
								my ($client,$value,$key) = @_;
									
								if ($key =~ /\D+(\d+)$/) {
									my $formatslistref = Slim::Player::TranscodingHelper::Conversions();
									my $profile = (sort {$a cmp $b} (grep {$_ !~ /transcode/} (keys %{$formatslistref})))[$1];
									my @profileitems = split('-', $profile);
									pop @profileitems; # drop ID
									$profileitems[0] = string($profileitems[0]);
									$profileitems[1] = string($profileitems[1]);
									$profileitems[2] = $formatslistref->{$profile}; #replace model with binary string
									my $dec = $formatslistref->{$profile};
									$dec =~ s{
											^\[(.*?)\](.*?\|?\[(.*?)\].*?)?
										}{
											$profileitems[2] = $1;
											if (defined $3) {$profileitems[2] .= "/".$3;}
										}iegsx;
									$profileitems[2] = '(built-in)' unless defined $profileitems[2] && $profileitems[2] ne '-';
									
									return join('</td><td>', @profileitems);
								} else {
									return $value;
								}
							}
					}
			}
		} #end of setup{'formats'}


	,'BEHAVIOR_SETTINGS' => {
		'title' => string('BEHAVIOR_SETTINGS'),
		'parent' => 'SERVER_SETTINGS',
		'GroupOrder' => [qw(DisplayInArtists VariousArtists Default CommonAlbumTitles)],
		'Groups' => {
	
			'Default' => {

				'PrefOrder' => [qw(displaytexttimeout checkVersion noGenreFilter
						playtrackalbum searchSubString ignoredarticles splitList browseagelimit
						groupdiscs persistPlaylists reshuffleOnRepeat saveShuffled)],
			},

			'DisplayInArtists' => {
				'PrefOrder' => [qw(composerInArtists conductorInArtists bandInArtists)],
				'GroupHead' => string('SETUP_COMPOSERINARTISTS'),
				'Suppress_PrefHead' => 1,
				'Suppress_PrefSub' => 1,
				'GroupSub' => 1,
				'GroupLine' => 1,
				'Suppress_PrefLine' => 1,
			},

			'CommonAlbumTitles' => {
				'PrefOrder' => [qw(commonAlbumTitlesToggle commonAlbumTitles)],
				'GroupHead' => string('SETUP_COMMONALBUMTITLES'),
				'Suppress_PrefHead' => 1,
				'Suppress_PrefSub' => 1,
				'GroupSub' => 1,
				'GroupLine' => 1,
				'Suppress_PrefLine' => 1,
			},

			'VariousArtists' => {
				'PrefOrder' => [qw(variousArtistAutoIdentification useBandAsAlbumArtist variousArtistsString)],
				'GroupHead' => string('SETUP_VARIOUSARTISTS'),
				'Suppress_PrefHead' => 1,
				'Suppress_PrefSub' => 1,
				'GroupSub' => 1,
				'GroupLine' => 1,
				'Suppress_PrefLine' => 1,
			},
		},

		'Prefs' => {

			'displaytexttimeout' => {
				'validate'     => \&Slim::Utils::Validate::number,
				'validateArgs' => [0.1,undef,1],
			},

			'browseagelimit' => {
				'validate'     	=> \&Slim::Utils::Validate::number,
				'validateArgs' => [0,undef,1,undef],
			},

			'ignoredarticles' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large',
				'onChange' => sub {
					my $client = shift;

					Slim::Control::Request::executeRequest($client, ['wipecache']);
				},
			},

			'splitList' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large',
				'onChange' => sub {
					my $client = shift;

					Slim::Control::Command::execute($client, ['wipecache']);
				},
			},

			'variousArtistAutoIdentification' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'1' => string('SETUP_VARIOUSARTISTAUTOIDENTIFICATION_1'),
					'0' => string('SETUP_VARIOUSARTISTAUTOIDENTIFICATION_0'),
				},
			},

			'useBandAsAlbumArtist' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'1' => string('SETUP_USEBANDASALBUMARTIST_1'),
					'0' => string('SETUP_USEBANDASALBUMARTIST_0'),
				},
			},

			'variousArtistsString' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large',
			},

			'playtrackalbum' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => {
					'1' => string('SETUP_PLAYTRACKALBUM_1'),
					'0' => string('SETUP_PLAYTRACKALBUM_0'),
				},
			},

			'composerInArtists' => { 	 

				'inputTemplate' => 'setup_input_chk.html',
				'PrefChoose'    => string('COMPOSER'),
				'validate'      => \&Slim::Utils::Validate::trueFalse,
			},

			'conductorInArtists' => { 	 

				'inputTemplate' => 'setup_input_chk.html',
				'PrefChoose'    => string('CONDUCTOR'),
				'validate'      => \&Slim::Utils::Validate::trueFalse,
			},

			'bandInArtists' => { 	 

				'inputTemplate' => 'setup_input_chk.html',
				'PrefChoose'    => string('BAND'),
				'validate'      => \&Slim::Utils::Validate::trueFalse,
			},

			'noGenreFilter' => { 	 
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => { 	 
					'1' => string('SETUP_NOGENREFILTER_1'),
					'0' => string('SETUP_NOGENREFILTER_0'),
				},
			},

			'searchSubString' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => {
					'1' => string('SETUP_SEARCHSUBSTRING_1'),
					'0' => string('SETUP_SEARCHSUBSTRING_0'),
				},
			},

			'persistPlaylists' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => {
					'1' => string('SETUP_PERSISTPLAYLISTS_1'),
					'0' => string('SETUP_PERSISTPLAYLISTS_0'),
				},
			},

			'reshuffleOnRepeat' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => {
					'1' => string('SETUP_RESHUFFLEONREPEAT_1'),
					'0' => string('SETUP_RESHUFFLEONREPEAT_0'),
				},
			},

			'saveShuffled' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'1' => string('SETUP_SAVESHUFFLED_1'),
					'0' => string('SETUP_SAVESHUFFLED_0'),
				},
			},

			'checkVersion' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'1' => string('SETUP_CHECKVERSION_1'),
					'0' => string('SETUP_CHECKVERSION_0'),
				},
			},

			'groupdiscs' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'onChange' => sub {
					my $client = shift;

					Slim::Control::Request::executeRequest($client, ['wipecache']);
				},

				'options' => {
					'1' => string ('SETUP_GROUPDISCS_1'),
					'0' => string ('SETUP_GROUPDISCS_0'),
				},
			 },

			'commonAlbumTitlesToggle' => {
				'validate'      => \&Slim::Utils::Validate::acceptAll,
				'inputTemplate' => 'setup_input_chk.html',
				'PrefChoose'    => string('SETUP_COMMONALBUMTITLES_TOGGLE'),
			},

			'commonAlbumTitles'	=> {
				'isArray'          => 1,
				'arrayAddExtra'    => 1,
				'arrayDeleteNull'  => 1,
				'arrayDeleteValue' => '',
				'arrayBasicValue'  => 0,
				'PrefSize'         => 'large',
				'inputTemplate'    => 'setup_input_array_txt.html',
				'onChange'         => sub {

					my ($client,$changeref,$paramref,$pageref) = @_;

					if (exists($changeref->{'commonAlbumTitles'}{'Processed'})) {
						return;
					}

					processArrayChange($client,'commonAlbumTitles',$paramref,$pageref);
					$changeref->{'commonAlbumTitles'}{'Processed'} = 1;
				}
			}
		}
	} #end of setup{'behavior'} hash

	,'FORMATTING_SETTINGS' => {
		'title' => string('FORMATTING_SETTINGS')
		,'parent' => 'SERVER_SETTINGS'
		,'preEval' => sub {
					my ($client,$paramref,$pageref) = @_;
					removeExtraArrayEntries($client,'titleFormat',$paramref,$pageref);
				}
		,'GroupOrder' => ['Default','TitleFormats','GuessFileFormats']
		,'Groups' => {
			'Default' => {
					'PrefOrder' => ['longdateFormat','shortdateFormat','timeFormat','showArtist','showYear']
				}
			,'TitleFormats' => {
					'PrefOrder' => ['titleFormat']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => string('SETUP_TITLEFORMAT')
					,'GroupDesc' => string('SETUP_GROUP_TITLEFORMATS_DESC')
					,'GroupPrefHead' => '<tr><th>' . string('SETUP_CURRENT') .
										'</th><th></th><th>' . string('SETUP_FORMATS') .
										'</th><th></th></tr>'
					,'GroupLine' => 1
					,'GroupSub' => 1
				}
			,'GuessFileFormats' => {
					'PrefOrder' => ['guessFileFormats']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => string('SETUP_GUESSFILEFORMATS')
					,'GroupDesc' => string('SETUP_GROUP_GUESSFILEFORMATS_DESC')
					,'GroupPrefHead' => '<tr><th>' .
										'</th><th></th><th>' . string('SETUP_FORMATS') .
										'</th><th></th></tr>'
					,'GroupLine' => 1
					,'GroupSub' => 1
				}
			}
		,'Prefs' => {
			'titleFormatWeb' => {
						'validate' => \&Slim::Utils::Validate::isInt
						,'validateArgs' => [0,undef,1]
						,'onChange' => sub {
								if (Slim::Utils::Prefs::get('titleFormatWeb') > Slim::Utils::Prefs::getArrayMax('titleFormat')) {
									Slim::Utils::Prefs::set('titleFormatWeb', Slim::Utils::Prefs::getArrayMax('titleFormat'));
								}
								for my $client (Slim::Player::Client::clients()) {
									$client->currentPlaylistChangeTime(time());
								}
							}
					}
			,'titleFormat'	=> {
						'isArray' => 1
						,'arrayAddExtra' => 1
						,'arrayDeleteNull' => 1
						,'arrayDeleteValue' => ''
						,'arrayBasicValue' => 0
						,'arrayCurrentPref' => 'titleFormatWeb'
						,'PrefSize' => 'large'
						,'inputTemplate' => 'setup_input_array_txt.html'
						,'validate' => \&Slim::Utils::Validate::format
						,'changeAddlText' => 'Format will be changed for any clients using this setting'
						,'onChange' => sub {
									my ($client,$changeref,$paramref,$pageref) = @_;
									if (exists($changeref->{'titleFormat'}{'Processed'})) {
										return;
									}
									processArrayChange($client,'titleFormat',$paramref,$pageref);
									fillFormatOptions();
									$changeref->{'titleFormat'}{'Processed'} = 1;
								}
							}
			,'showArtist' => {
						'validate' => \&Slim::Utils::Validate::trueFalse
						,'options' => {
									'0' => string('DISABLED')
									,'1' => string('ENABLED')
								}
							}
			,'showYear' => {
						'validate' => \&Slim::Utils::Validate::trueFalse
						,'options' => {
									'0' => string('DISABLED')
									,'1' => string('ENABLED')
								}
							}
			,'guessFileFormats'	=> {
						'isArray' => 1
						,'arrayAddExtra' => 1
						,'arrayDeleteNull' => 1
						,'arrayDeleteValue' => ''
						,'arrayBasicValue' => 0
						,'PrefSize' => 'large'
						,'inputTemplate' => 'setup_input_array_txt.html'
						,'validate' => \&Slim::Utils::Validate::format
						,'changeAddlText' => 'All files without tags will be processed this way'
						,'onChange' => sub {
									my ($client,$changeref,$paramref,$pageref) = @_;
									if (exists($changeref->{'guessFileFormats'}{'Processed'})) {
										return;
									}
									processArrayChange($client,'guessFileFormats',$paramref,$pageref);
									$setup{'FORMATTING_SETTINGS'}{'Prefs'}{'guessFileFormats'}{'options'} = {hash_of_prefs('guessFileFormats')};
									$changeref->{'guessFileFormats'}{'Processed'} = 1;
								}
					}
			,"longdateFormat" => {
						'validate' => \&Slim::Utils::Validate::inHash
						,'validateArgs' => [] # set in initSetup
						,'options' => { # WWWW is the name of the day of the week
								# WWW is the abbreviation of the name of the day of the week
								# MMMM is the full month name
								# MMM is the abbreviated month name
								# DD is the day of the month
								# YYYY is the 4 digit year
								# YY is the 2 digit year
								q(%A, %B |%d, %Y)	=> "WWWW, MMMM DD, YYYY"
								,q(%a, %b |%d, %Y)	=> "WWW, MMM DD, YYYY"
								,q(%a, %b |%d, '%y)	=> "WWW, MMM DD, 'YY" # '" 
									# The previous comment fixes syntax highlighting thrown off by the embedded single quote
								,q(%A, |%d %B %Y)	=> "WWWW, DD MMMM YYYY"
								,q(%A, |%d. %B %Y)	=> "WWWW, DD. MMMM YYYY"
								,q(%a, |%d %b %Y)	=> "WWW, DD MMM YYYY"
								,q(%a, |%d. %b %Y)	=> "WWW, DD. MMM YYYY"
								,q(%A |%d %B %Y)		=> "WWWW DD MMMM YYYY"
								,q(%A |%d. %B %Y)	=> "WWWW DD. MMMM YYYY"
								,q(%a |%d %b %Y)		=> "WWW DD MMM YYYY"
								,q(%a |%d. %b %Y)	=> "WWW DD. MMM YYYY"
								# Japanese styles
								,q(%Y/%m/%d\(%a\))	=> "YYYY/MM/DD(WWW)"
								,q(%Y-%m-%d\(%a\))	=> "YYYY-MM-DD(WWW)"
								,q(%Y/%m/%d %A)	=> "YYYY/MM/DD WWWW"
								,q(%Y-%m-%d %A)	=> "YYYY-MM-DD WWWW"
								}
					}
			,"shortdateFormat" => {
						'validate' => \&Slim::Utils::Validate::inHash
						,'validateArgs' => [] # set in initSetup
						,'options' => { # MM is the month of the year
								# DD is the day of the year
								# YYYY is the 4 digit year
								# YY is the 2 digit year
								q(%m/%d/%Y)	=> "MM/DD/YYYY"
								,q(%m/%d/%y)	=> "MM/DD/YY"
								,q(%m-%d-%Y)	=> "MM-DD-YYYY"
								,q(%m-%d-%y)	=> "MM-DD-YY"
								,q(%m.%d.%Y)	=> "MM.DD.YYYY"
								,q(%m.%d.%y)	=> "MM.DD.YY"
								,q(%d/%m/%Y)	=> "DD/MM/YYYY"
								,q(%d/%m/%y)	=> "DD/MM/YY"
								,q(%d-%m-%Y)	=> "DD-MM-YYYY"
								,q(%d-%m-%y)	=> "DD-MM-YY"
								,q(%d.%m.%Y)	=> "DD.MM.YYYY"
								,q(%d.%m.%y)	=> "DD.MM.YY"
								,q(%Y-%m-%d)	=> "YYYY-MM-DD (ISO)"
								# Japanese style
								,q(%Y/%m/%d)	=> "YYYY/MM/DD"
								}
					}
			,"timeFormat" => {
						'validate' => \&Slim::Utils::Validate::inHash
						,'validateArgs' => [] # set in initSetup
						,'options' => { # hh is hours
								# h is hours (leading zero removed)
								# mm is minutes
								# ss is seconds
								# pm is either AM or PM
								# anything at the end in parentheses is just a comment
								q(%I:%M:%S %p)	=> "hh:mm:ss pm (12h)"
								,q(%I:%M %p)	=> "hh:mm pm (12h)"
								,q(%H:%M:%S)	=> "hh:mm:ss (24h)"
								,q(%H:%M)	=> "hh:mm (24h)"
								,q(%H.%M.%S)	=> "hh.mm.ss (24h)"
								,q(%H.%M)	=> "hh.mm (24h)"
								,q(%H,%M,%S)	=> "hh,mm,ss (24h)"
								,q(%H,%M)	=> "hh,mm (24h)"
								# no idea what the separator between minutes and seconds should be here
								,q(%Hh%M:%S)	=> "hh'h'mm:ss (24h 03h00:00 15h00:00)"
								,q(%Hh%M)	=> "hh'h'mm (24h 03h00 15h00)"
								,q(|%I:%M:%S %p)	=> "h:mm:ss pm (12h)"
								,q(|%I:%M %p)		=> "h:mm pm (12h)"
								,q(|%H:%M:%S)		=> "h:mm:ss (24h)"
								,q(|%H:%M)		=> "h:mm (24h)"
								,q(|%H.%M.%S)		=> "h.mm.ss (24h)"
								,q(|%H.%M)		=> "h.mm (24h)"
								,q(|%H,%M,%S)		=> "h,mm,ss (24h)"
								,q(|%H,%M)		=> "h,mm (24h)"
								# no idea what the separator between minutes and seconds should be here
								,q(|%Hh%M:%S)		=> "h'h'mm:ss (24h 03h00:00 15h00:00)"
								,q(|%Hh%M)		=> "h'h'mm (24h 03h00 15h00)"
								}
					}
			}
		} #end of setup{'FORMATTING_SETTINGS'} hash
	,'SECURITY_SETTINGS' => {
		'title' => string('SECURITY_SETTINGS')
		,'parent' => 'SERVER_SETTINGS'
		,'GroupOrder' => ['BasicAuth','Default']
		,'Groups' => {
			'Default' => {
					'PrefOrder' => ['filterHosts', 'allowedHosts','csrfProtectionLevel']
				}
			,'BasicAuth' => {
					'PrefOrder' => ['authorize','username','password']
					,'Suppress_PrefSub' => 1
					,'GroupSub' => 1
					,'GroupLine' => 1
					,'Suppress_PrefLine' => 1
				}
			}
		,'Prefs' => {
			'authorize' => {
						'validate' => \&Slim::Utils::Validate::trueFalse
						,'options' => {
								'0' => string('SETUP_NO_AUTHORIZE')
								,'1' => string('SETUP_AUTHORIZE')
								}
					}
			,'username' => {
						'validate' => \&Slim::Utils::Validate::acceptAll
						,'PrefSize' => 'large'
					}
			,'password' => {
						'validate' => \&Slim::Utils::Validate::password
						,'inputTemplate' => 'setup_input_passwd.html'
						,'changeMsg' => string('SETUP_PASSWORD_CHANGED')
						,'PrefSize' => 'large'
					}
			,'filterHosts' => {
						
						'validate' => \&Slim::Utils::Validate::trueFalse
						,'PrefHead' => string('SETUP_IPFILTER_HEAD')
						,'PrefDesc' => string('SETUP_IPFILTER_DESC')
						,'options' => {
								'0' => string('SETUP_NO_IPFILTER')
								,'1' => string('SETUP_IPFILTER')
							}
					}
			,'csrfProtectionLevel' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => [0,2,1,1]
							,'optionSort' => 'V'
							,'options' => {
									'0' => string('NONE')
									,'1' => string('MEDIUM')
									,'2' => string('HIGH')

								}
						}
			,'allowedHosts' => {
						'validate' => \&Slim::Utils::Validate::allowedHosts
						,'PrefHead' => string('SETUP_FILTERRULE_HEAD')
						,'PrefDesc' => string('SETUP_FILTERRULE_DESC')
						,'PrefSize' => 'large'
					}

			}
		} #end of setup{'security'} hash
	,'PERFORMANCE_SETTINGS' => {
		'title' => string('PERFORMANCE_SETTINGS'),
		'parent' => 'SERVER_SETTINGS',
		'GroupOrder' => ['Default'],

		'Groups' => {

			'Default' => {
				'PrefOrder' => [qw(
					lookForArtwork
					itemsPerPass
					prefsWriteDelay
					keepUnswappedInterval
					databaseTempStorage
					databaseCacheSize
				)],
			},
		},

		'Prefs' => {
			'lookForArtwork' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'0' => string('SETUP_NO_ARTWORK'),
					'1' => string('SETUP_LOOKFORARTWORK'),
				},
			},

			'itemsPerPass' => {
				'validate' => \&Slim::Utils::Validate::isInt,
			},

			'prefsWriteDelay' => {
				'validate' => \&Slim::Utils::Validate::isInt,
				'validateArgs' => [0,undef,1],
			},

			'keepUnswappedInterval' => {
				'validate' => \&Slim::Utils::Validate::isInt,
			},

			'databaseCacheSize' => {
				'PrefHead' => string('SETUP_DATBASE_TUNE_CACHE_SIZE_HEAD'),
				'PrefDesc' => string('SETUP_DATBASE_TUNE_CACHE_SIZE_DESC'),

				'validate' => \&Slim::Utils::Validate::isInt,

				'onChange' => sub {
					my ($client, $changeref) = @_;

					my $ds = Slim::Music::Info->getCurrentDataStore;

					$ds->modifyDatabaseCacheSize($changeref->{'databaseCacheSize'}{'new'});
				},
			},

			'databaseTempStorage' => {
				'PrefHead' => string('SETUP_DATBASE_TUNE_TEMP_STORAGE_HEAD'),
				'PrefDesc' => string('SETUP_DATBASE_TUNE_TEMP_STORAGE_DESC'),

				'options' => {
					'MEMORY' => string('SETUP_DATBASE_TUNE_TEMP_STORAGE_MEMORY'),
					'FILE'   => string('SETUP_DATBASE_TUNE_TEMP_STORAGE_FILE'),
				},

				'onChange' => sub {
					my ($client, $changeref) = @_;

					my $ds  = Slim::Music::Info->getCurrentDataStore;
					my $val = $changeref->{'databaseTempStorage'}{'new'};

					if ($val eq 'MEMORY' || $val eq 'FILE') {

						$ds->modifyDatabaseTempStorage($val);
					}
				},
			},
		},
	} #end of setup{'performance'} hash
	,'NETWORK_SETTINGS' => {
		'title' => string('NETWORK_SETTINGS')
		,'parent' => 'SERVER_SETTINGS'
		,'GroupOrder' => ['Default','TCP_Params']
		,'Groups' => {
			'Default' => {
					'PrefOrder' => ['webproxy','httpport','mDNSname','remotestreamtimeout']
				}
			,'TCP_Params' => {
					'PrefOrder' => ['tcpReadMaximum','tcpWriteMaximum','udpChunkSize']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => string('SETUP_GROUP_TCP_PARAMS')
					,'GroupDesc' => string('SETUP_GROUP_TCP_PARAMS_DESC')
					,'GroupLine' => 1
					,'GroupSub' => 1
				}
			}
		,'Prefs' => {
			'httpport'	=> {
						'validate' => \&Slim::Utils::Validate::isInt
						,'validateArgs' => [1025,65535,undef,1]
						,'changeAddlText' => string('SETUP_NEW_VALUE')
									. '<blockquote><a target="_top" href="[EVAL]Slim::Web::HTTP::HomeURL()[/EVAL]">'
									. '[EVAL]Slim::Web::HTTP::HomeURL()[/EVAL]</a></blockquote>'
						,'onChange' => sub {
									my ($client,$changeref,$paramref,$pageref) = @_;
									$paramref->{'HomeURL'} = Slim::Web::HTTP::HomeURL();
								}
					}
			,'webproxy'	=> {
						'validate' => \&Slim::Utils::Validate::hostNameOrIPAndPort,
						'PrefSize' => 'large'
					}
			,'mDNSname'	=> {
							'validateArgs' => [] #will be set by preEval
							,'PrefSize' => 'medium'
					}
			,'remotestreamtimeout' => {
						'validate' => \&Slim::Utils::Validate::isInt
						,'validateArgs' => [1,undef,1]
					}
			,'tcpReadMaximum' => {
						'validate' => \&Slim::Utils::Validate::isInt
						,'validateArgs' => [1,undef,1]
					}
			,"tcpWriteMaximum" => {
						'validate' => \&Slim::Utils::Validate::isInt
						,'validateArgs' => [1,undef,1]
					}
			,"udpChunkSize" => {
						'validate' => \&Slim::Utils::Validate::isInt
						,'validateArgs' => [1,4096,1,1] #limit to 4096
					}
			}
		} #end of setup{'network'} hash
	,'DEBUGGING_SETTINGS' => {
		'title' => string('DEBUGGING_SETTINGS')
		,'parent' => 'SERVER_SETTINGS'
		,'postChange' => sub {
					my ($client,$paramref,$pageref) = @_;
					no strict 'refs';
					foreach my $debugItem (@{$pageref->{'Groups'}{'Default'}{'PrefOrder'}}) {
						my $debugSet = "::" . $debugItem;
						if (!exists $paramref->{$debugItem}) {
							$paramref->{$debugItem} = $$debugSet;
						}
					}
				}
		,'GroupOrder' => ['Default']
		,'Groups' => {
			'Default' => {
					'PrefOrder' => [] # will be filled after hash is set up
					,'Suppress_PrefHead' => 1
#					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'PrefsInTable' => 1
					,'GroupDesc' => string('SETUP_GROUP_DEBUG_DESC')
				}
			}
		,'Prefs' => {
			'd_' => { #template for the debug settings
					'validate' => \&Slim::Utils::Validate::trueFalse
					,'inputTemplate' => 'setup_input_chk.html'
					,'dontSet' => 1
					,'currentValue' => sub {
								my ($client,$key,$ind) = @_;
								no strict 'refs';
								$key = '::' . $key;
								return $$key || 0;
							}
					,'onChange' => sub {
								my ($client,$changeref,$paramref,$pageref,$key,$ind) = @_;
								no strict 'refs';
								my $key2 = '::' . $key;
								$$key2 = $changeref->{$key}{'new'};
							}
				}
			}
		} #end of setup{'debug'} hash
	); #end of setup hash
	foreach my $key (sort keys %main:: ) {
		next unless $key =~ /^d_/;
		my %debugTemp = %{$setup{'DEBUGGING_SETTINGS'}{'Prefs'}{'d_'}};
		push @{$setup{'DEBUGGING_SETTINGS'}{'Groups'}{'Default'}{'PrefOrder'}},$key;
		$setup{'DEBUGGING_SETTINGS'}{'Prefs'}{$key} = \%debugTemp;
		$setup{'DEBUGGING_SETTINGS'}{'Prefs'}{$key}{'PrefChoose'} = $key;
		$setup{'DEBUGGING_SETTINGS'}{'Prefs'}{$key}{'changeIntro'} = $key;
	}
	if (scalar(keys %{Slim::Utils::PluginManager::installedPlugins()})) {
		
		Slim::Web::Setup::addChildren('SERVER_SETTINGS','PLUGINS');

		# XXX This should be added conditionally based on whether there
		# are any radio plugins. We need to find a place to make that
		# check *after* plugins have been correctly initialized.
		Slim::Web::Setup::addChildren('SERVER_SETTINGS','RADIO');
	}
}

sub initSetup {
	initSetupConfig();
	$setup{'SERVER_SETTINGS'}{'Prefs'}{'language'}{'options'} = {Slim::Utils::Strings::hash_of_languages()};
	$setup{'INTERFACE_SETTINGS'}{'Prefs'}{'skin'}{'options'} = {skins(1)};
	$setup{'FORMATTING_SETTINGS'}{'Prefs'}{'longdateFormat'}{'validateArgs'} = [$setup{'FORMATTING_SETTINGS'}{'Prefs'}{'longdateFormat'}{'options'}];
	$setup{'FORMATTING_SETTINGS'}{'Prefs'}{'shortdateFormat'}{'validateArgs'} = [$setup{'FORMATTING_SETTINGS'}{'Prefs'}{'shortdateFormat'}{'options'}];
	$setup{'FORMATTING_SETTINGS'}{'Prefs'}{'timeFormat'}{'validateArgs'} = [$setup{'FORMATTING_SETTINGS'}{'Prefs'}{'timeFormat'}{'options'}];
	fillFormatOptions();
	fillSetupOptions('PLAYER_SETTINGS','titleFormat','titleFormat');
	fillAlarmOptions();
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
			,'PrefChoose' => string('SETUP_ALARMVOLUME').string('COLON')
			,'validateArgs' => [0,$Slim::Player::Client::maxVolume,1,1]
			,'currentValue' => sub {
				my $client = shift;
				return if (!defined($client));
				return $client->prefGet( "alarmvolume",$i);
			}
		};

		$setup{'ALARM_SETTINGS'}{'Prefs'}{'alarmtime'.$i} = {
			'validate' => \&Slim::Utils::Validate::isTime
			,'validateArgs' => [0,undef],
			,'PrefChoose' => string('ALARM_SET').string('COLON')
			,'changeIntro' => string('ALARM_SET')
			,'rejectIntro' => string('ALARM_SET')
			,'currentValue' => sub {
				my $client = shift;
				return if (!defined($client));
				
				my $time = $client->prefGet( "alarmtime",$i);
				
				my ($h0, $h1, $m0, $m1, $p) = Slim::Buttons::Common::timeDigits($client,$time);
				my $timestring = ((defined($p) && $h0 == 0) ? ' ' : $h0) . $h1 . ":" . $m0 . $m1 . " " . (defined($p) ? $p : '');
				
				return $timestring;
			}
		};
		$setup{'ALARM_SETTINGS'}{'Prefs'}{'alarm'.$i} = {
			'validate' => \&Slim::Utils::Validate::trueFalse
			,'PrefHead' => ' '
			,'PrefChoose' => string('SETUP_ALARM').string('COLON')
			,'options' => {
					'1' => string('ON')
					,'0' => string('OFF')
				}
			,'currentValue' => sub {
					my $client = shift;
					return if (!defined($client));
					return $client->prefGet( "alarm",$i);
				}
		};
		$setup{'ALARM_SETTINGS'}{'Prefs'}{'alarmplaylist'.$i} = {
			'validate' => \&Slim::Utils::Validate::inHash
			,'PrefChoose' => string('ALARM_SELECT_PLAYLIST').string('COLON')
			,'validateArgs' => undef
			,'options' => undef
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
			,'GroupHead' => string('ALARM_DAY'.$i)
			,'GroupLine' => 1
			,'GroupSub' => 1
		};
	};
}

sub fillFormatOptions {
	$setup{'FORMATTING_SETTINGS'}{'Prefs'}{'guessFileFormats'}{'options'} = {hash_of_prefs('guessFileFormats')};
}

sub fillSetupOptions {
	my ($set,$pref,$hash) = @_;
	$setup{$set}{'Prefs'}{$pref}{'options'} = {hash_of_prefs($hash)};
	$setup{$set}{'Prefs'}{$pref}{'validateArgs'} = [$setup{$set}{'Prefs'}{$pref}{'options'}];
}

sub fillFontOptions {
	my ($client,$set,$pref,$hash) = @_;
	my $fonts = Slim::Display::Graphics::fontnames();
	my %allowedfonts;

	my $displayHeight = $client->displayHeight();
	foreach my $f (keys %$fonts) {
		
		if ($displayHeight == Slim::Display::Graphics::fontheight($f . '.2')) {
			$allowedfonts{$f} = $f;
		}
	}
	
	$allowedfonts{'-1'} = ' ';;

	$setup{$set}{'Prefs'}{$pref}{'options'} = \%allowedfonts;
	$setup{$set}{'Prefs'}{$pref}{'validateArgs'} = [\%allowedfonts];
}

sub playerChildren {
	my $client = shift;
	my $pageref = shift;
	return if (!$client);

	if ($client->isPlayer()) {

		$pageref->{'children'} = ['PLAYER_SETTINGS','MENU_SETTINGS','DISPLAY_SETTINGS','ALARM_SETTINGS','AUDIO_SETTINGS','REMOTE_SETTINGS'];
		push @{$pageref->{'children'}},@newPlayerChildren;
		if (scalar(keys %{Slim::Utils::PluginManager::playerPlugins()})) {
			push @{$pageref->{'children'}}, 'PLAYER_PLUGINS';
		}
	} else {
		$pageref->{'children'} = ['PLAYER_SETTINGS','ALARM_SETTINGS','AUDIO_SETTINGS'];
	}
	
}

sub addPlayerChild {
	push @newPlayerChildren,shift;
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
	
	# hack around a race condition at startup
	if (!Slim::Utils::Prefs::getArrayMax($pref)) {
		return;
	};
	
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
	
	if ($::nosetup || ($::noserver && $paramref->{'page'} eq 'SERVER_SETTINGS')) {
		$response->code(RC_FORBIDDEN);
		return Slim::Web::HTTP::filltemplatefile('html/errors/403.html',$paramref);
	}

	if (!defined($paramref->{'page'}) || !exists($setup{$paramref->{'page'}})) {
		$response->code(RC_NOT_FOUND);
		$paramref->{'suggestion'} = "Try adding page=SERVER_SETTINGS.";
		return Slim::Web::HTTP::filltemplatefile('html/errors/404.html',$paramref);
	}

	my %pagesetup = %{$setup{$paramref->{'page'}}};

	if (exists $pagesetup{'isClient'}) {
		$client = Slim::Player::Client::getClient($paramref->{'playerid'});
	} else {
		$client = undef;
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

	foreach my $group (@{$pageref->{'GroupOrder'}}) {

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
			my $tokenDesc   = 'SETUP_' . uc($pref) . '_DESC';
			my $tokenChoose = 'SETUP_' . uc($pref) . '_CHOOSE';

			if (!exists $prefparams{'PrefHead'}) {
				$prefparams{'PrefHead'} = (Slim::Utils::Strings::resolveString($token) || $pref);
			}

			if (!exists $prefparams{'PrefDesc'} && Slim::Utils::Strings::stringExists($tokenDesc)) {
				$prefparams{'PrefDesc'} = string($tokenDesc);
			}

			if (!exists $prefparams{'PrefChoose'} && Slim::Utils::Strings::stringExists($tokenChoose)) {
				$prefparams{'PrefChoose'} = string($tokenChoose);
			}

			if (!exists $prefparams{'inputTemplate'}) {
				$prefparams{'inputTemplate'} = (exists $prefparams{'options'}) ? 'setup_input_sel.html' : 'setup_input_txt.html';
			}

			if (!exists $prefparams{'ChangeButton'}) {
				$prefparams{'ChangeButton'} = string('CHANGE');
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
			$groupparams{'ChangeButton'} = string('CHANGE');
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
	my ($paramref,@pages) = @_;
	
	for my $page (@pages) {
		
		# Don't include in the sorted list, let skins include or not and where they want.
		next if $page eq "SERVER_SETTINGS";
		next if $page eq "PLAYER_SETTINGS";
		
		# Grab player tabs.  
		# TODO do this on startup only and allow plugins to add themselves
		if (defined $paramref->{'playerid'}) {
			Slim::Web::Pages->addPageLinks("playersetup",{"$page"  => "setup.html?page=$page"});
			for my $playerplugin (@newPlayerChildren) {
				#Slim::Web::Pages->addPageLinks("playerplugin",{"$playerplugin"  => "setup.html?page=$playerplugin"});
			}
		
		# global setup pages, need to do this at startup too
		} else {
			Slim::Web::Pages->addPageLinks("setup",{"$page"  => "setup.html?page=$page"});
		}
	}
}

sub processChanges {
	my ($client,$changeref,$paramref,$pageref) = @_;
	
	foreach my $key (keys %{$changeref}) {
		$key =~ /(.+?)(\d*)$/;
		my $keyA = $1;
		my $keyI = $2;
		if (exists $pageref->{'Prefs'}{$keyA}{'onChange'}) {
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
	my $arrayMax = ($client) ? $client->prefGetArrayMax($array) : Slim::Utils::Prefs::getArrayMax($array);
	my $adval = defined($pageref->{'Prefs'}{$array}{'arrayDeleteValue'}) ? $pageref->{'Prefs'}{$array}{'arrayDeleteValue'} : '';
	for (my $i = $arrayMax + $pageref->{'Prefs'}{$array}{'arrayAddExtra'};$i > $arrayMax;$i--) {
		if (exists $paramref->{$array . $i} && (!defined($paramref->{$array . $i}) || $paramref->{$array . $i} eq '' || $paramref->{$array . $i} eq $adval)) {
			delete $paramref->{$array . $i};
		}
	}
}

sub playlists {
	my %lists = ();

	my $ds   = Slim::Music::Info::getCurrentDataStore();

#	for my $playlist (@{Slim::Music::Info::playlists()}) {
	for my $playlist ($ds->getPlaylists()) {

		if (Slim::Music::Info::isURL($playlist)) {

			$lists{$playlist} = Slim::Music::Info::standardTitle(undef, $playlist);
		}
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
			
			#my $path = catdir($templatedir, $dir);
			
			$::d_http && msg(" skin entry: $dir\n");
			
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

			if (defined($settingsref->{$key}{'arrayMax'})) {
				$arrayMax = $settingsref->{$key}{'arrayMax'};
			} else {
				$arrayMax = ($client) ? $client->prefGetArrayMax($key) : Slim::Utils::Prefs::getArrayMax($key);
			}
			if (defined($arrayMax) && exists($settingsref->{$key}{'arrayAddExtra'})) {
				my $adval = defined($settingsref->{$key}{'arrayDeleteValue'}) ? $settingsref->{$key}{'arrayDeleteValue'} : '';
				for (my $i=$arrayMax + $settingsref->{$key}{'arrayAddExtra'}; $i > $arrayMax; $i--) {
					if (exists $paramref->{$key . $i} && (defined($paramref->{$key . $i}) || $paramref->{$key . $i} ne '' || $paramref->{$key . $i} ne $adval)) {
						$arrayMax = $i;
						last;
					}
				}
			}
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
						if (exists $settingsref->{$key}{'validateArgs'}) {
							($pvalue, $errmsg) = &{$settingsref->{$key}{'validate'}}($paramref->{$key2},@{$settingsref->{$key}{'validateArgs'}});
						} else {
							($pvalue, $errmsg) = &{$settingsref->{$key}{'validate'}}($paramref->{$key2});
						}
					} else { #accept everything
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
		my $changemsg = undef;
		my $changedval = undef;
		if (exists $settingsref->{$keyA}{'noWarning'}) {
			next;
		}
		if (exists $settingsref->{$keyA}{'changeIntro'}) {
			$changemsg = sprintf($settingsref->{$keyA}{'changeIntro'},$keyI);
		} elsif (Slim::Utils::Strings::stringExists('SETUP_' . uc($keyA) . '_OK')) {
			$changemsg = string('SETUP_' . uc($keyA) . '_OK');
		} else {
			$changemsg = (Slim::Utils::Strings::stringExists('SETUP_' . uc($keyA)) ?
							string('SETUP_' . uc($keyA)) : $keyA) . ' ' . $keyI . ':';
		}
		$changemsg .= '<p>';
		#use external value from 'options' hash
		if (exists $settingsref->{$keyA}{'changeoptions'}) {
			if ($settingsref->{$keyA}{'changeoptions'}) {
				$changedval = $settingsref->{$keyA}{'changeoptions'}{$changeref->{$key}{'new'}};
			}
		} elsif (exists $settingsref->{$keyA}{'options'}) {
			$changedval = $settingsref->{$keyA}{'options'}{$changeref->{$key}{'new'}};
		} elsif (exists $settingsref->{$keyA}{'externalValue'}) {
			my $client;
			if (exists $paramref->{'playerid'}) {
				$client = Slim::Player::Client::getClient($paramref->{'playerid'});
			}
			$changedval = &{$settingsref->{$keyA}{'externalValue'}}($client,$changeref->{$key},$key);
		} else {
			$changedval = $changeref->{$key}{'new'};
		}
		if (exists $settingsref->{$keyA}{'changeMsg'}) {
			$changemsg .= $settingsref->{$keyA}{'changeMsg'};
		} else {
			$changemsg .= '%s';
		}
		$changemsg .= '</p>';
		if (exists $settingsref->{$keyA}{'changeAddlText'}) {
			$changemsg .= $settingsref->{$keyA}{'changeAddlText'};
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
			$rejectmsg = sprintf($settingsref->{$keyA}{'rejectIntro'},$keyI);
		} else {
			$rejectmsg = string('SETUP_NEW_VALUE') . ' ' . 
						(string('SETUP_' . uc($keyA)) || $keyA) . ' ' . 
						$keyI . string("SETUP_REJECTED") . ':';
		}
		$rejectmsg .= ' <blockquote> ';
		if (exists $settingsref->{$keyA}{'rejectMsg'}) {
			$rejectmsg .= $settingsref->{$keyA}{'rejectMsg'};
		} else {
			$rejectmsg .= string('SETUP_BAD_VALUE');
		}
		$rejectmsg .= '</blockquote><p>';
		if (exists $settingsref->{$keyA}{'rejectAddlText'}) {
			$rejectmsg .= $settingsref->{$keyA}{'rejectAddlText'};
		}
		#force eval on the filltemplate call
		$paramref->{'warning'} .= sprintf($rejectmsg, $rejectref->{$key});
	}
}

sub options_HTTP {
	my ($client, $paramref, $settingsref) = @_;

	foreach my $key (keys %$settingsref) {
		my $arrayMax = 0;
		if (exists($settingsref->{$key}{'isArray'})) {
			$arrayMax = ($client) ? $client->prefGetArrayMax($key) : Slim::Utils::Prefs::getArrayMax($key);
			if (!defined $arrayMax) { $arrayMax = 0; }
			if (exists($settingsref->{$key}{'arrayAddExtra'})) {
				$arrayMax += $settingsref->{$key}{'arrayAddExtra'};
			}
		}
		for (my $i=0; $i <= $arrayMax; $i++) {
			my $key2 = $key . (exists($settingsref->{$key}{'isArray'}) ? $i : '');
			if (exists $settingsref->{$key}{'options'}) {
				if ($settingsref->{$key}{'inputTemplate'} && $settingsref->{$key}{'inputTemplate'} eq 'setup_input_radio.html') {
					$paramref->{$key2 . '_options'} = fillRadioOptions($paramref->{$key2},$settingsref->{$key}{'options'},$key,$settingsref->{$key}{'optionSort'});
				} else {
					$paramref->{$key2 . '_options'} = fillOptions($paramref->{$key2},$settingsref->{$key}{'options'},$settingsref->{$key}{'optionSort'});
				}
			}
		}
	}
}

# pass in the selected value and a hash of value => text pairs to get the option list filled
# with the correct option selected.  Since the text portion can be a template (for stringification)
# perform a filltemplate on the completed list

sub fillOptions {
	my ($selected, $optionref, $sort) = @_;

	my @optionlist = ();
	my $options    = _sortOptionArray($optionref, $sort);

	for my $curOption (@{$options}) {

		push @optionlist, '<option ' .
			((defined $selected && $curOption eq $selected) ? 'selected ' : '') .
			qq(value="$curOption">$optionref->{$curOption}</option>);
	}

	return join("\n", @optionlist);
}

# pass in the selected value and a hash of value => text pairs to get the option list filled
# with the correct option selected.  Since the text portion can be a template (for stringification)
# perform a filltemplate on the completed list

sub fillRadioOptions {
	my ($selected,$optionref,$option,$sort) = @_;

	my @optionlist = ();
	my $options    = _sortOptionArray($optionref, $sort);

	for my $curOption (@{$options}) {

		push @optionlist, '<p><input type="radio" ' . 
			((defined $selected && $curOption eq $selected) ? 'checked ' : '') .
			qq(value="$curOption" name="$option">$optionref->{$curOption}</p>);
	}

	return join("\n", @optionlist);
}

# Utility used by both fill*Options functions
sub _sortOptionArray {
	my ($optionref, $sort) = @_;

	# default $sort to K
	$sort = 'K' unless defined $sort;

	# First - resolve any string pointers
	while (my ($key, $value) = each %{$optionref}) {

		if (Slim::Utils::Strings::stringExists($value)) {
			$optionref->{$key} = string($value);
		}
	}

	# Now sort
	my @options = keys %$optionref;
	
	if ($sort =~ /N/i) {
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
	my ($category,$groupname,$prefname,$position) = @_;
	unless (exists $setup{$category} && exists $setup{$category}{'Groups'}{$groupname}) {
		# either the category or the group within the category is invalid
		$::d_prefs && msg("Group $groupname in category $category does not exist\n");
		return;
	}
	if (!defined $position || $position > scalar(@{$setup{$category}{'Groups'}{$groupname}{'PrefOrder'}})) {
		$position = scalar(@{$setup{$category}{'Groups'}{$groupname}{'PrefOrder'}});
	}
	splice(@{$setup{$category}{'Groups'}{$groupname}{'PrefOrder'}},$position,0,$prefname);
	return;
}

# Removes the preference from the PrefOrder array of the supplied group
# in the supplied category
sub removePrefFromGroup {
	my ($category,$groupname,$prefname,$noWarn) = @_;
	# Find $prefname in $setup{$category}{'Groups'}{$groupname}{'PrefOrder'} array
	unless (exists $setup{$category} && exists $setup{$category}{'Groups'}{$groupname}) {
		# either the category or the group within the category is invalid
		$::d_prefs && msg("Group $groupname in category $category does not exist\n");
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
		$::d_prefs && msg("Preference $prefname not found in group $groupname in category $category\n");
	}
	return;
}

# Adds the preference to the category.  A reference to a hash containing the
# preference data must be supplied.
sub addPref {
	my ($category,$prefname,$prefref,$groupname,$position) = @_;
	unless (exists $setup{$category}) {
		$::d_prefs && msg("Category $category does not exist\n");
		return;
	}
	$setup{$category}{'Prefs'}{$prefname} = $prefref;
	if (defined $groupname) {
		addPrefToGroup($category,$groupname,$prefname,$position);
	}
	return;
}

# Removes the preference from the supplied category, optionally removes
# all references to the preference from the PrefOrder arrays of the groups
# within the category
sub delPref {
	my ($category,$prefname,$andGroupRefs) = @_;
	
	unless (exists $setup{$category}) {
		$::d_prefs && msg("Category $category does not exist\n");
		return;
	}
	delete $setup{$category}{'Prefs'}{$prefname};
	if ($andGroupRefs) {
		for my $group (@{$setup{$category}{'GroupOrder'}}) {
			removePrefFromGroup($category,$group,$prefname,1);
		}
	}
	return;
}

# Adds a group to the supplied category.  A reference to a hash containing the
# group data must be supplied.  If a reference to a hash of preferences is supplied,
# they will also be added to the category.
sub addGroup {
	my ($category,$groupname,$groupref,$position,$prefsref,$categoryKey) = @_;

	unless (exists $setup{$category}) {
		$::d_prefs && msg("Category $category does not exist\n");
		return;
	}
	unless (defined $groupname && (defined $groupref || defined $categoryKey)) {
		warn "No group information supplied!\n";
		return;
	}
	
	$categoryKey = 'GroupOrder' unless defined $categoryKey;
	
	if (defined $prefsref) {
		$setup{$category}{'Groups'}{$groupname} = $groupref;
	}
	
	my $found = 0;
	foreach (@{$setup{$category}{$categoryKey}}) {
		next if !defined $_;
		$found = 1,last if $_ eq $groupname;
	}
	if (!$found) {
		if (!defined $position || $position > scalar(@{$setup{$category}{$categoryKey}})) {
			$position = scalar(@{$setup{$category}{$categoryKey}});
		}
		$::d_prefs && msg("Adding $groupname to position $position in $categoryKey\n");
		splice(@{$setup{$category}{$categoryKey}},$position,0,$groupname);
	}
	
	if ($category eq 'PLUGINS') {
		my $first = shift @{$setup{$category}{$categoryKey}};
		my $pluginlistref = getCategoryPlugins(undef, $category);
		@{$setup{$category}{$categoryKey}} = ($first,sort {uc($pluginlistref->{$a}) cmp uc($pluginlistref->{$b})} (@{$setup{$category}{$categoryKey}}));
	}
	
	if (defined $prefsref) {
		my ($pref,$prefref);
		while (($pref,$prefref) = each %{$prefsref}) {
			$setup{$category}{'Prefs'}{$pref} = $prefref;
			$::d_prefs && msg("Adding $pref to setup hash\n");
		}
	}
	return;
}

# Deletes a group from a category and optionally the associated preferences
sub delGroup {
	my ($category,$groupname,$andPrefs) = @_;
	
	unless (exists $setup{$category}) {
		$::d_prefs && msg("Category $category does not exist\n");
		return;
	}
	
	my @preflist;
	
	if (exists $setup{$category}{'Groups'}{$groupname} && $andPrefs) {
		#hold on to preferences for later deletion
		@preflist = @{$setup{$category}{'Groups'}{$groupname}{'PrefOrder'}};
	}
	

	if ($setup{$category}{'children'}) {
		# remove ghost children
		my @children;
			foreach (@{$setup{$category}{'children'}}) {
			next if !defined $_;
			next if $_ eq $groupname;
			push @children,$_;
		}
		@{$setup{$category}{'children'}} = @children;
	}
	#remove from Groups hash
	delete $setup{$category}{'Groups'}{$groupname};
	
	#remove from GroupOrder array
	my $i=0;
	
	for my $currgroup (@{$setup{$category}{'GroupOrder'}}) {
		if ($currgroup eq $groupname) {
			splice (@{$setup{$category}{'GroupOrder'}},$i,1);
			last;
		}
		$i++;
	}
	
	#delete associated preferences if requested
	if ($andPrefs) {
		for my $pref (@preflist) {
			delPref($category,$pref);
		}
	}
	
	return;
}

sub addChildren {
	my ($category,$child,$position) = @_;
	my $categoryKey = 'children';
	
	addGroup($category,$child,undef,$position,undef,$categoryKey);
	return;
}

sub addCategory {
	my ($category,$categoryref) = @_;
	
	unless (defined $category && defined $categoryref) {
		warn "No category information supplied!\n";
		return;
	}
	
	$setup{$category} = $categoryref;
}

sub delCategory {
	my $category = shift;

	unless (defined $category) {
		warn "No category information supplied!\n";
		return;
	}

	delete $setup{$category};
}

sub existsCategory {
	my $category = shift;
	return exists $setup{$category};
}

sub getCategoryPlugins {
	no strict 'refs';
	my $client = shift;
	my $category = shift || 'PLUGINS';
	my $pluginlistref = Slim::Utils::PluginManager::installedPlugins();

	for my $plugin (keys %{$pluginlistref}) {
		# get plugin's displayName if it's not available, yet
		unless (Slim::Utils::Strings::stringExists($pluginlistref->{$plugin})) {
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

		unless ($paramref->{"pluginlist$i"}) {
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
	my ($client,$value,$key, $category) = @_;

	if ($key !~ /\D+(\d+)$/) {
		return $value;
	}

	my $pluginlistref = getCategoryPlugins($client, $category);
	return $pluginlistref->{(sort {uc($pluginlistref->{$a}) cmp uc($pluginlistref->{$b})} (keys %{$pluginlistref}))[$1]};
}


######################################################################
# Validation Functions
######################################################################
sub validateAcceptAll {
	Slim::Utils::Validate::acceptAll(@_);
}

sub validateTrueFalse {
	Slim::Utils::Validate::trueFalse(@_);
}

sub validateInt {
	Slim::Utils::Validate::isInt(@_);
}

sub validatePort {
	Slim::Utils::Validate::port(@_);
}

sub validateHostNameOrIPAndPort {
	Slim::Utils::Validate::hostNameOrIPAndPort(@_);
}

sub validateIPPort {
	Slim::Utils::Validate::IPPort(@_);
}

sub validateNumber {
	Slim::Utils::Validate::number(@_);
}

sub validateInList {
	Slim::Utils::Validate::inList(@_);
}

sub validateTime {
	Slim::Utils::Validate::isTime(@_);
}

# determines if the value is one of the keys of the supplied hash
# the hash is supplied in the form of a reference either to a hash, or to code which returns a hash
sub validateInHash {
	Slim::Utils::Validate::inHash(@_);
}

sub validateIsFile {
	Slim::Utils::Validate::isFile(@_);
}

sub validateIsDir {
	Slim::Utils::Validate::isDir(@_);
}

sub validateIsAudioDir {
	Slim::Utils::Validate::isDir(@_);
}

sub validateHasText {
	Slim::Utils::Validate::hasText(@_);
}

sub validatePassword {
	Slim::Utils::Validate::password(@_);
}

# TODO make this actually check to see if the format is valid
sub validateFormat {
	Slim::Utils::Validate::format(@_);
}

# Verify allowed hosts is in somewhat proper format, always prepend 127.0.0.1 if not there
sub validateAllowedHosts {
	Slim::Utils::Validate::allowedHosts(@_);
 }

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
