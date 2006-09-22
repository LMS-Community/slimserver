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
	'BASIC_PLAYER_SETTINGS' => {
		'title' => string('BASIC_PLAYER_SETTINGS') #may be modified in postChange to reflect player name
		,'children' => []
		,'GroupOrder' => []
		,'isClient' => 1
		,'preEval' => sub {
					my ($client,$paramref,$pageref) = @_;
					return if (!defined($client));
					playerChildren($client, $pageref);

					if ($client->isPlayer()) {
						$pageref->{'GroupOrder'} = ['Default','TitleFormats','Display'];
						if ($client->display->isa('Slim::Display::Transporter')) {
							push @{$pageref->{'GroupOrder'}}, 'Visual';
						}
						if (scalar(keys %{Slim::Buttons::Common::hash_of_savers()}) > 0) {
							push @{$pageref->{'GroupOrder'}}, 'ScreenSaver';
						}
					} else {
						$pageref->{'GroupOrder'} = ['Default','TitleFormats'];
					}
					
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
					$paramref->{'voltage'} = $client->voltage();

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
					,'GroupHead' => 'SETUP_TITLEFORMAT'
					,'GroupDesc' => 'SETUP_TITLEFORMAT_DESC'
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
					,'GroupHead' => 'SETUP_PLAYINGDISPLAYMODE'
					,'GroupDesc' => 'SETUP_PLAYINGDISPLAYMODE_DESC'
					,'GroupPrefHead' => '<tr><th>' . string('SETUP_CURRENT') . 
										'</th><th></th><th>' . string('DISPLAY_SETTINGS') . '</th><th></th></tr>'
					,'GroupLine' => 1
					,'GroupSub'  => 1
				}
			,'Visual' => {
					'PrefOrder' => ['visualModes']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub'  => 1
					,'GroupHead' => 'SETUP_VISUALIZERMODE'
					,'GroupDesc' => 'SETUP_VISUALIZERMODE_DESC'
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
				,'GroupHead' => 'SCREENSAVERS'
				,'GroupDesc' => 'SETUP_SCREENSAVER_DESC'
				,'GroupLine' => 1
				,'GroupSub' => 1
			}
		}
		,'Prefs' => {
			'playername' => {
							'validate' => \&Slim::Utils::Validate::hasText
							,'validateArgs' => sub {my $client = shift || return (); return ($client->defaultName());}
							,'PrefSize' => 'medium'
						}
			,'titleFormatCurr'	=> {
							'validate' => \&Slim::Utils::Validate::isInt
						}
			,'playingDisplayMode'	=> {
							'validate' => \&Slim::Utils::Validate::isInt
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
							,'validateArgs' => [\&getPlayingDisplayModes,1]
							,'validateAddClient' => 1
							,'options' => \&getPlayingDisplayModes
							,'optionSort' => 'NK'
						}
			,'visualMode'	=> {
							'validate' => \&Slim::Utils::Validate::isInt
							,'onChange' => \&Slim::Buttons::Common::updateScreen2Mode
						}
			,'visualModes' 	=> {
							'isArray' => 1
							,'arrayAddExtra' => 1
							,'arrayDeleteNull' => 1
							,'arrayDeleteValue' => -1
							,'arrayBasicValue' => 0
							,'arrayCurrentPref' => 'visualMode'
							,'inputTemplate' => 'setup_input_array_sel.html'
							,'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [\&getVisualModes,1]
							,'validateAddClient' => 1
							,'options' => \&getVisualModes
							,'optionSort' => 'NK'
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
							,'validateArgs' => [sub {return hash_of_prefs('titleFormat');}]
							,'options' => sub {return {hash_of_prefs('titleFormat')};}
							,'optionSort' => 'NK'
						}
			,'screensaver'	=> {
							'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [\&Slim::Buttons::Common::hash_of_savers,1]
							,'optionSort' => 'V'
							,'options' => \&Slim::Buttons::Common::hash_of_savers
						}
			,'idlesaver'	=> {
							'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [\&Slim::Buttons::Common::hash_of_savers,1]
							,'optionSort' => 'V'
							,'options' => \&Slim::Buttons::Common::hash_of_savers
						}
			,'offsaver'	=> {
							'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [\&Slim::Buttons::Common::hash_of_savers,1]
							,'optionSort' => 'V'
							,'options' => \&Slim::Buttons::Common::hash_of_savers
						}
			,'screensavertimeout' => {
							'validate' => \&Slim::Utils::Validate::number
							,'validateArgs' => [0,undef,1]
						}
			}
		} #end of setup{'player'} hash

	,'DISPLAY_SETTINGS' => {
		'title' => string('DISPLAY_SETTINGS')
		,'parent' => 'BASIC_PLAYER_SETTINGS'
		,'isClient' => 1
		,'GroupOrder' => [undef,undef,undef,'ScrollMode','ScrollPause','ScrollRate', undef]
		,'preEval' => sub {
					my ($client,$paramref,$pageref) = @_;
					return if (!defined($client));
					playerChildren($client, $pageref);

					if ($client->isPlayer()) {
						$pageref->{'GroupOrder'}[0] = 'Brightness';
						if ($client->display->isa("Slim::Display::Graphics")) {
							$pageref->{'GroupOrder'}[1] = 'activeFont'; 
							$pageref->{'GroupOrder'}[2] = 'idleFont';
							$pageref->{'GroupOrder'}[6] = 'ScrollPixels';
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
					
					if (!$paramref->{'playername'}) {
						$paramref->{'playername'} = $client->name();
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
					,'GroupHead' => 'SETUP_GROUP_BRIGHTNESS'
					,'GroupDesc' => 'SETUP_GROUP_BRIGHTNESS_DESC'
					,'GroupLine' => 1
				}
			,'TextSize' => {
					'PrefOrder' => ['doublesize','offDisplaySize']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'GroupHead' => 'SETUP_DOUBLESIZE'
					,'GroupDesc' => 'SETUP_DOUBLESIZE_DESC'
					,'GroupLine' => 1
				}
			,'LargeFont' => {
					'PrefOrder' => ['largeTextFont']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'GroupHead' => 'SETUP_LARGETEXTFONT'
					,'GroupDesc' => 'SETUP_LARGETEXTFONT_DESC'
					,'GroupLine' => 1
				}
			,'activeFont' => {
					'PrefOrder' => ['activeFont']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'GroupHead' => 'SETUP_ACTIVEFONT'
					,'GroupDesc' => 'SETUP_ACTIVEFONT_DESC'
					,'GroupPrefHead' => ''
					,'GroupLine' => 1
				}
			,'idleFont' => {
					'PrefOrder' => ['idleFont']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'GroupHead' => 'SETUP_IDLEFONT'
					,'GroupDesc' => 'SETUP_IDLEFONT_DESC'
					,'GroupPrefHead' => ''
					,'GroupLine' => 1
				}
			,'ScrollMode' => {
				'PrefOrder' => ['scrollMode']
				,'PrefsInTable' => 1
				,'Suppress_PrefHead' => 1
				,'Suppress_PrefDesc' => 1
				,'Suppress_PrefLine' => 1
				,'GroupHead' => 'SETUP_SCROLLMODE'
				,'GroupDesc' => 'SETUP_SCROLLMODE_DESC'
				,'GroupLine' => 1
			}
			,'ScrollRate' => {
				'PrefOrder' => ['scrollRate','scrollRateDouble']
				,'PrefsInTable' => 1
				,'Suppress_PrefHead' => 1
				,'Suppress_PrefDesc' => 1
				,'Suppress_PrefLine' => 1
				,'GroupHead' => 'SETUP_SCROLLRATE'
				,'GroupDesc' => 'SETUP_SCROLLRATE_DESC'
				,'GroupLine' => 1
			}
			,'ScrollPause' => {
				'PrefOrder' => ['scrollPause','scrollPauseDouble']
				,'PrefsInTable' => 1
				,'Suppress_PrefHead' => 1
				,'Suppress_PrefDesc' => 1
				,'Suppress_PrefLine' => 1
				,'GroupHead' => 'SETUP_SCROLLPAUSE'
				,'GroupDesc' => 'SETUP_SCROLLPAUSE_DESC'
				,'GroupLine' => 1
			}
			,'ScrollPixels' => {
				'PrefOrder' => ['scrollPixels','scrollPixelsDouble']
				,'PrefsInTable' => 1
				,'Suppress_PrefHead' => 1
				,'Suppress_PrefDesc' => 1
				,'Suppress_PrefLine' => 1
				,'GroupHead' => 'SETUP_SCROLLPIXELS'
				,'GroupDesc' => 'SETUP_SCROLLPIXELS_DESC'
				,'GroupLine' => 1
			}
			
			}
		,'Prefs' => {
			'powerOnBrightness' => {
							'validate'     => \&Slim::Utils::Validate::isInt,
							'validateArgs' => \&getBrightnessArgs,
							'optionSort'   => 'NK',
							'options'      => \&getBrightnessOptions,
							'onChange'     => sub {
									my ($client, $changeref) = @_;
									if (defined $client && defined $client->maxBrightness && $client->power()) {
										$client->brightness($changeref->{'powerOnBrightness'}{'new'});
									}
								},
							
						}
			,'powerOffBrightness' => {
							'validate'     => \&Slim::Utils::Validate::isInt,
							'validateArgs' => \&getBrightnessArgs,
							'optionSort'   => 'NK',
							'options'      => \&getBrightnessOptions,
							'onChange'     => sub {
									my ($client, $changeref) = @_;
									if (defined $client && defined $client->maxBrightness && !$client->power()) {
										$client->brightness($changeref->{'powerOffBrightness'}{'new'});
									}
								},
						}
			,'idleBrightness' => {
							'validate'     => \&Slim::Utils::Validate::isInt,
							'validateArgs' => \&getBrightnessArgs,
							'optionSort'   => 'NK',
							'options'      => \&getBrightnessOptions,
						}
			,'doublesize' => {
							'validate' => \&Slim::Utils::Validate::inList
							,'validateArgs' => [0,1]
							,'options' => {
								'0' => 'SMALL',
								'1' => 'LARGE'
							}
							,'PrefChoose' => 'SETUP_DOUBLESIZE'
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
								'0' => 'SMALL',
								'1' => 'LARGE'
							}
							,'PrefChoose' => 'SETUP_OFFDISPLAYSIZE'
						}
			,'largeTextFont' => {
							'validate' => \&Slim::Utils::Validate::inList
							,'validateArgs' => [0,1]
							,'options' => {
								'0' => 'SETUP_LARGETEXTFONT_0',
								'1' => 'SETUP_LARGETEXTFONT_1'
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
							,'validateArgs' => [\&getFontOptions,1]
							,'validateAddClient' => 1
							,'options' => \&getFontOptions
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
							,'validateArgs' => [\&getFontOptions,1]
							,'validateAddClient' => 1
							,'options' => \&getFontOptions
						}
			,'activeFont_curr' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => sub {
									my $client = shift || return ();
									return (0,($client->prefGetArrayMax('activeFont') + 1),1,1);
								}
							,'changeIntro' => 'SETUP_ACTIVEFONT'
						}
			,'idleFont_curr' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => sub {
									my $client = shift || return ();
									return (0,($client->prefGetArrayMax('idleFont') + 1),1,1);
								}
							,'changeIntro' => 'SETUP_IDLEFONT'
						}
			,'autobrightness' => {
						'validate' => \&Slim::Utils::Validate::trueFalse
						,'options' => {
								'1' => 'SETUP_AUTOBRIGHTNESS_ON'
								,'0' => 'SETUP_AUTOBRIGHTNESS_OFF'
							}
						,'changeIntro' => 'SETUP_AUTOBRIGHTNESS_CHOOSE'
					}
			,'scrollMode' => {
				'validate' => \&Slim::Utils::Validate::inList
				,'validateArgs' => [0,1,2]
				,'options' => {
					 '0' => 'SETUP_SCROLLMODE_DEFAULT'
					,'1' => 'SETUP_SCROLLMODE_SCROLLONCE'
					,'2' => 'SETUP_SCROLLMODE_NOSCROLL'
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
				,'validateArgs' => [1,20,1,1]
				,'PrefChoose' => string('SINGLE-LINE').' '.string('SETUP_SCROLLPIXELS').string('COLON')
			},
			'scrollPixelsDouble' => {
				'validate' => \&Slim::Utils::Validate::isInt
				,'validateArgs' => [1,20,1,1]
				,'changeIntro' => string('DOUBLE-LINE').' '.string('SETUP_SCROLLPIXELS').string('COLON')
				,'PrefChoose' => string('DOUBLE-LINE').' '.string('SETUP_SCROLLPIXELS').string('COLON')
			},
		}
	}
	,'MENU_SETTINGS' => {
		'title' => string('MENU_SETTINGS')
		,'parent' => 'BASIC_PLAYER_SETTINGS'
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
					$i = 0;
					foreach my $pluginItem (Slim::Utils::PluginManager::unusedPluginOptions($client)) {
						$paramref->{'pluginItem' . $i++} = $pluginItem;
					}
					$pageref->{'Prefs'}{'pluginItem'}{'arrayMax'} = $i - 1;
					$pageref->{'Prefs'}{'pluginItemAction'}{'arrayMax'} = $i - 1;
					
					if (!$paramref->{'playername'}) {
						$paramref->{'playername'} = $client->name();
					}
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
					,'GroupHead' => 'SETUP_GROUP_MENUITEMS'
					,'GroupDesc' => 'SETUP_GROUP_MENUITEMS_DESC'
				}
			,'NonMenuItems' => {
					'PrefOrder' => ['nonMenuItem']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => ''
					,'GroupDesc' => 'SETUP_GROUP_NONMENUITEMS_INTRO'
				}
			,'Plugins' => {
					'PrefOrder' => ['pluginItem']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => ''
					,'GroupDesc' => 'SETUP_GROUP_PLUGINITEMS_INTRO'
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
						,'validate' => \&Slim::Utils::Validate::inHash
						,'validateArgs' => [\&Slim::Buttons::Home::menuOptions]
						,'externalValue' => \&menuItemName
						,'onChange' => \&Slim::Buttons::Home::updateMenu
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
		,'parent' => 'BASIC_PLAYER_SETTINGS'
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
				,'GroupHead' => 'SETUP_GROUP_ALARM'
				,'GroupDesc' => 'SETUP_GROUP_ALARM_DESC'
				,'GroupLine' => 1
				,'Suppress_PrefLine' => 1
				,'Suppress_PrefHead' => 1
			}
		}
		,'Prefs' => {
			'alarmfadeseconds' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'PrefChoose' => 'ALARM_FADE',
				'changeIntro' => 'ALARM_FADE',
				'inputTemplate' => 'setup_input_chk.html',
			}
		},
	}
	,'AUDIO_SETTINGS' => {
		'title' => string('AUDIO_SETTINGS')
		,'parent' => 'BASIC_PLAYER_SETTINGS'
		,'isClient' => 1
		,'preEval' => sub {

					my ($client,$paramref,$pageref) = @_;
					return if (!defined($client));
					playerChildren($client, $pageref);
					if (Slim::Player::Sync::isSynced($client) || (scalar(Slim::Player::Sync::canSyncWith($client)) > 0))  {
						$pageref->{'GroupOrder'}[0] = 'Synchronize';
					} else {
						$pageref->{'GroupOrder'}[0] = undef;
					}
					
					if ($client && $client->hasPowerControl()) {
						$pageref->{'Groups'}{'PowerOn'}{'PrefOrder'}[1] = 'powerOffDac';
					}
					else {
						$pageref->{'Groups'}{'PowerOn'}{'PrefOrder'}[1] = undef;
					}										

					if ($client && $client->hasDisableDac()) {
						$pageref->{'Groups'}{'PowerOn'}{'PrefOrder'}[2] = 'disableDac';
					}
					else {
						$pageref->{'Groups'}{'PowerOn'}{'PrefOrder'}[2] = undef;
					}										

					if ($client && $client->hasPreAmp()) {
						$pageref->{'Groups'}{'Digital'}{'PrefOrder'}[1] = 'preampVolumeControl';
					} else {
						$pageref->{'Groups'}{'Digital'}{'PrefOrder'}[1] = undef;
					}
					
					if ($client->maxTransitionDuration()) {
						$pageref->{'GroupOrder'}[2] = 'Transition';
					} else {
						$pageref->{'GroupOrder'}[2] = undef;
					}
					
					if ($client && $client->hasDigitalOut()) {
						$pageref->{'GroupOrder'}[3] = 'Digital';
					} else {
						$pageref->{'GroupOrder'}[3] = undef;
					}
					
					if ($client && $client->hasDigitalIn()) {
						$pageref->{'GroupOrder'}[4] = 'Input';
					} else {
						$pageref->{'GroupOrder'}[4] = undef;
					}

					if ($client && $client->hasAesbeu()) {
						$pageref->{'Groups'}{'Digital'}{'PrefOrder'}[3] = 'digitalOutputEncoding';
					}
					else {
						$pageref->{'Groups'}{'Digital'}{'PrefOrder'}[3] = undef;
					}					

					if ($client && $client->hasExternalClock()) {
						$pageref->{'Groups'}{'Digital'}{'PrefOrder'}[4] = 'clockSource';
					}
					else {
						$pageref->{'Groups'}{'Digital'}{'PrefOrder'}[4] = undef;
					}
										
					if ($client && $client->hasPolarityInversion()) {
						$pageref->{'Groups'}{'Digital'}{'PrefOrder'}[5] = 'polarityInversion';
					}
					else {
						$pageref->{'Groups'}{'Digital'}{'PrefOrder'}[5] = undef;
					}
										
					if (Slim::Utils::Misc::findbin('lame')) {
						$pageref->{'Prefs'}{'lame'}{'PrefDesc'} = 'SETUP_LAME_FOUND';
						$pageref->{'GroupOrder'}[5] = 'Quality';
					} else {
						$pageref->{'Prefs'}{'lame'}{'PrefDesc'} = 'SETUP_LAME_NOT_FOUND';
						$pageref->{'GroupOrder'}[5] = undef;
					}
					
					$pageref->{'GroupOrder'}[6] ='Format';
					my @formats = $client->formats();
					if ($formats[0] ne 'mp3') {
						$pageref->{'Groups'}{'Format'}{'GroupDesc'} = 'SETUP_MAXBITRATE_DESC';
						$pageref->{'Prefs'}{'maxBitrate'}{'options'}{'0'} = 'NO_LIMIT';
					} else {
						delete $pageref->{'Prefs'}{'maxBitrate'}{'options'}{'0'};
						$pageref->{'Groups'}{'Format'}{'GroupDesc'} = 'SETUP_MP3BITRATE_DESC';
					}

					if ($client->canDoReplayGain(0)) {
						$pageref->{'GroupOrder'}[7] = 'ReplayGain';
					} else {
						$pageref->{'GroupOrder'}[7] = undef;
					}

					if (!$paramref->{'playername'}) {
						$paramref->{'playername'} = $client->name();
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
							} elsif ( my $syncgroupid = $client->prefGet('syncgroupid') ) {
								# Bug 3284, we want to show powered off players that will resync when turned on
								my @players = Slim::Player::Client::clients();
								foreach my $other (@players) {
									next if $other eq $client;
									my $othersyncgroupid = Slim::Utils::Prefs::clientGet($other,'syncgroupid');
									if ( $syncgroupid == $othersyncgroupid ) {
										$paramref->{'synchronize'} = $other->id;
										last;
									}
								}
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
					'PrefOrder' => ['powerOnResume','powerOffDac','disableDac']
				}
			,'Format' => {
					'PrefOrder' => ['lame','maxBitrate']
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => 'SETUP_MAXBITRATE'
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
					'PrefOrder' => ['digitalVolumeControl','preampVolumeControl','mp3SilencePrelude','digitalOutputEncoding','clockSource','polarityInversion']
				}
			,'Input' => {
					'PrefOrder' => ['wordClockOutput']
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
					'validate' => \&Slim::Utils::Validate::inHash,
					'validateArgs' => [sub{return getSetupOptions('AUDIO_SETTINGS','powerOnResume');},1],
					'options' => {
							'PauseOff-NoneOn'      => 'SETUP_POWERONRESUME_PAUSEOFF_NONEON'
							,'PauseOff-PlayOn'     => 'SETUP_POWERONRESUME_PAUSEOFF_PLAYON'
							,'StopOff-PlayOn'      => 'SETUP_POWERONRESUME_STOPOFF_PLAYON'
							,'StopOff-NoneOn'      => 'SETUP_POWERONRESUME_STOPOFF_NONEON'
							,'StopOff-ResetPlayOn' => 'SETUP_POWERONRESUME_STOPOFF_RESETPLAYON'
							,'StopOff-ResetOn'     => 'SETUP_POWERONRESUME_STOPOFF_RESETON'
						},
					'currentValue' => sub {
							my ($client,$key,$ind) = @_;
							return if (!defined($client));
							return Slim::Player::Sync::syncGroupPref($client,'powerOnResume') ||
								   $client->prefGet('powerOnResume');
					},
					'onChange' => sub {
							my ($client,$changeref,$paramref,$pageref) = @_;
							return if (!defined($client));

							my $newresume = $changeref->{'powerOnResume'}{'new'};
							if (Slim::Player::Sync::syncGroupPref($client,'powerOnResume')) {
								Slim::Player::Sync::syncGroupPref($client,'powerOnResume',$newresume);
							}
						},
					}
							
			,'maxBitrate' => {
							'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [sub{return getSetupOptions('AUDIO_SETTINGS','maxBitrate');},1]
							,'optionSort' => 'NK'
							,'currentValue' => sub { return Slim::Utils::Prefs::maxRate(shift, 1); }
							,'options' => {
									'0' => 'NO_LIMIT'
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
							,'options' => \&syncGroups
							,'validate' => \&Slim::Utils::Validate::inHash
							,'validateArgs' => [\&syncGroups,1]
							,'validateAddClient' => 1
							,'currentValue' => sub {
									my ($client,$key,$ind) = @_;
									return if (!defined($client));
									if (Slim::Player::Sync::isSynced($client)) {
										return $client->id();
									} elsif ( my $syncgroupid = $client->prefGet('syncgroupid') ) {
										# Bug 3284, we want to show powered off players that will resync when turned on
										my @players = Slim::Player::Client::clients();
										foreach my $other (@players) {
											next if $other eq $client;
											my $othersyncgroupid = Slim::Utils::Prefs::clientGet($other,'syncgroupid');
											if ( $syncgroupid == $othersyncgroupid ) {
												return $other->id;
											}
										}
									}
									return -1;
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
									'1' => 'SETUP_SYNCVOLUME_ON'
									,'0' => 'SETUP_SYNCVOLUME_OFF'
								}
						}			
			,'syncPower' => {
							'validate' => \&Slim::Utils::Validate::trueFalse  
							,'options' => {
									'1' => 'SETUP_SYNCPOWER_ON'
									,'0' => 'SETUP_SYNCPOWER_OFF'
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
									'1' => 'SETUP_DIGITALVOLUMECONTROL_ON',
									'0' => 'SETUP_DIGITALVOLUMECONTROL_OFF'
								}
							,'onChange' => sub {
								my $client = shift;
								$client->volume($client->volume());
							}
						}
			,'preampVolumeControl' => {
							'validate' => \&Slim::Utils::Validate::number
							,'validateArgs' => [0, 63]
						}
			,'mp3SilencePrelude' => {
							'validate' => \&Slim::Utils::Validate::number  
							,'validateArgs' => [0, 5]
						}
			,'clockSource' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => [0,5,0,0]
							,'optionSort' => 'NK'
							,'options' => {
									'0' => 'CLOCKSOURCE_INTERNAL',
									'1' => 'CLOCKSOURCE_WORD_CLOCK',
									'2' => 'AUDIO_SOURCE_BALANCED_AES',
									'3' => 'AUDIO_SOURCE_BNC_SPDIF',
									'4' => 'AUDIO_SOURCE_RCA_SPDIF',
									'5' => 'AUDIO_SOURCE_OPTICAL_SPDIF',
								}
							,'onChange' => sub {
								my $client = shift;
								$client->updateClockSource();
							}
						}
			,'transitionType' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => [0,4,1,1]
							,'optionSort' => 'NK'
							,'options' => {
									'0' => 'TRANSITION_NONE',
									'1' => 'TRANSITION_CROSSFADE',
									'2' => 'TRANSITION_FADE_IN',
									'3' => 'TRANSITION_FADE_OUT',
									'4' => 'TRANSITION_FADE_IN_OUT',
								}
						}
			,'transitionDuration' => {
							'validate' => \&Slim::Utils::Validate::isInt,
							'validateArgs' => sub {
									my $client = shift || return ();
									return (0, $client->maxTransitionDuration(),1,1);
								},
						}
			,'replayGainMode' => {
							'validate' => \&Slim::Utils::Validate::inHash,
							'validateArgs' => [sub{return getSetupOptions('AUDIO_SETTINGS','replayGainMode');},1],
							'optionSort' => 'NK',
							'options' => {
									'0' => 'REPLAYGAIN_DISABLED',
									'1' => 'REPLAYGAIN_TRACK_GAIN',
									'2' => 'REPLAYGAIN_ALBUM_GAIN',
									'3' => 'REPLAYGAIN_SMART_GAIN',
								},
						}
			,'digitalOutputEncoding' => {
							'validate' => \&Slim::Utils::Validate::trueFalse
							,'options' => {
									'0' => 'DIGITALOUTPUTENCODING_SPDIF',
									'1' => 'DIGITALOUTPUTENCODING_AESEBU',
							}
			}
			,'wordClockOutput' => {
							'validate' => \&Slim::Utils::Validate::trueFalse
							,'options' => {
									'1' => 'WORDCLOCKOUTPUT_GENERATECLOCK',
									'0' => 'WORDCLOCKOUTPUT_PASSTHROUGH',
							}
			}
			,'powerOffDac' => {
							'validate' => \&Slim::Utils::Validate::trueFalse
							,'options' => {
									'0' => 'POWEROFFDAC_ALWAYSON',
									'1' => 'POWEROFFDAC_WHENOFF',
							}
			}
			,'disableDac' => {
							'validate' => \&Slim::Utils::Validate::trueFalse
							,'options' => {
									'0' => 'DISABLEDAC_ALWAYSON',
									'1' => 'DISABLEDAC_WHENOFF',
							}
			}
			,'polarityInversion' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => [0,3,0,3]
							,'options' => {
									'0' => 'POLARITYINVERSION_NORMAL',
									'3' => 'POLARITYINVERSION_INVERTED',
							}
							,'onChange' => sub {
								my $client = shift;
								$client->volume($client->volume());
							}
			}
		}
	}
	,'REMOTE_SETTINGS' => {
		'title' => string('REMOTE_SETTINGS')
		,'parent' => 'BASIC_PLAYER_SETTINGS'
		,'isClient' => 1
		,'preEval' => sub {
				my ($client,$paramref,$pageref) = @_;
				return if (!defined($client));
				playerChildren($client, $pageref);
				if (scalar(keys %{Slim::Hardware::IR::mapfiles()}) > 1) {  
					$pageref->{'GroupOrder'}[1] = 'IRMap';  
				} else {  
					$pageref->{'GroupOrder'}[1] = undef;
				}
				my $i = 0;
				my %irsets = map {$_ => 1} $client->prefGetArray('disabledirsets');
				foreach my $irset (sort(keys %{Slim::Hardware::IR::irfiles($client)})) {
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
				foreach my $irset (sort(keys %{Slim::Hardware::IR::irfiles($client)})) {
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
				,'GroupHead' => 'SETUP_GROUP_IRSETS'
				,'GroupDesc' => 'SETUP_GROUP_IRSETS_DESC'
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
				,'options' => \&Slim::Hardware::IR::mapfiles
			},
			'irsetlist' => {
				'isArray' => 1
				,'dontSet' => 1
				,'validate' => \&Slim::Utils::Validate::trueFalse
				,'inputTemplate' => 'setup_input_array_chk.html'
				,'arrayMax' => undef #set in preEval
				,'changeMsg' => 'SETUP_IRSETLIST_CHANGE'
				,'externalValue' => sub {
							my ($client,$value,$key) = @_;
							return if (!defined($client));
							if ($key =~ /\D+(\d+)$/) {
								return Slim::Hardware::IR::irfileName((sort(keys %{Slim::Hardware::IR::irfiles($client)}))[$1]);
							} else {
								return $value;
							}
						}
			},
		}
	}
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

	,'BASIC_SERVER_SETTINGS' => {

		'children' => [qw(BASIC_SERVER_SETTINGS INTERFACE_SETTINGS BEHAVIOR_SETTINGS FORMATS_SETTINGS FORMATTING_SETTINGS SECURITY_SETTINGS PERFORMANCE_SETTINGS NETWORK_SETTINGS DEBUGGING_SETTINGS)],
		'title'    => string('BASIC_SERVER_SETTINGS'),
		'singleChildLinkText' => string('ADDITIONAL_SERVER_SETTINGS'),

		'preEval'  => sub {
			my ($client, $paramref, $pageref) = @_;

			my @versions = Slim::Utils::Misc::settingsDiagString();
			$paramref->{'versionInfo'} = join( "<br />\n", @versions ) . "\n<p>";
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
				'GroupHead' => 'SETUP_RESCAN',
				'GroupDesc' => 'SETUP_RESCAN_DESC',
				'GroupLine' => 1,
			},
		},

		'Prefs' => {

			'language' => {

				'validate'     => \&Slim::Utils::Validate::inHash,
				'validateArgs' => [\&Slim::Utils::Strings::hash_of_languages],
				'options'      => sub {return {Slim::Utils::Strings::hash_of_languages()};},
				'onChange'     => sub {
					Slim::Utils::PluginManager::clearPlugins();
					Slim::Utils::Strings::init();
					Slim::Web::Setup::initSetup();
					Slim::Utils::PluginManager::initPlugins();
					Slim::Music::Import->resetSetupGroups;
				},
			},

			'audiodir' => {
				'validate'     => \&Slim::Utils::Validate::isDir,
				'validateArgs' => [1],
				'changeIntro'  => 'SETUP_OK_USING',
				'rejectMsg'    => 'SETUP_BAD_DIRECTORY',
				'PrefSize'     => 'large',
			},

			'playlistdir' => {
				'validate'     => \&Slim::Utils::Validate::isDir,
				'validateArgs' => [1],
				'changeIntro'  => 'SETUP_PLAYLISTDIR_OK',
				'rejectMsg'    => 'SETUP_BAD_DIRECTORY',
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

					$::d_scan && msgf("Setup::rescan - initiating scan of type: [%s]\n", $rescanType->[0]);

					Slim::Control::Request::executeRequest($client, $rescanType);
				},
				'inputTemplate' => 'setup_input_submit.html',
				'ChangeButton'  => 'SETUP_RESCAN_BUTTON',
				'changeIntro'   => 'RESCANNING',
				'dontSet'       => 1,
				'changeMsg'     => '',
			},
			'rescantype' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'optionSort' => 'K',
				'options' => {
					'1rescan'   => 'SETUP_STANDARDRESCAN',
					'2wipedb'   => 'SETUP_WIPEDB',
					'3playlist' => 'SETUP_PLAYLISTRESCAN',
				},
				'dontSet'       => 1,
				'changeMsg'     => '',
				'changeIntro'     => '',
			},
		},

	} #end of setup{'server'} hash

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
		} #end of setup{'RADIO'}
	,'INTERFACE_SETTINGS' => {
		'title' => string('INTERFACE_SETTINGS')
		,'parent' => 'BASIC_SERVER_SETTINGS'
		,'GroupOrder' => ['Default']
		,'Groups' => {
			'Default' => {
				'PrefOrder' => ['skin','itemsPerPage','refreshRate','coverArt','coverThumb','artfolder','thumbSize']
			}
		}
		,'Prefs' => {
			'skin'		=> {
						'validate' => \&Slim::Utils::Validate::inHash
						,'validateArgs' => [\&skins]
						,'options' => sub {return {skins(1)};}
						,'changeIntro' => 'SETUP_SKIN_OK'
						,'changeAddlText' => 'HIT_RELOAD'
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
					,'changeIntro' => 'SETUP_ARTFOLDER'
					,'rejectMsg' => 'SETUP_BAD_DIRECTORY'
					,'PrefSize' => 'large'
				}
			,'thumbSize' => {
					'validate' => \&Slim::Utils::Validate::isInt
					,'validateArgs' => [25,250,1,1]
				}
		}
	}# end of setup{'INTERFACE_SETTINGS'} hash

	,'FORMATS_SETTINGS' => {
		'title' => string('FORMATS_SETTINGS')
		,'parent' => 'BASIC_SERVER_SETTINGS'
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
				if (!$paramref->{"formatslist$i"} && ($binAvailable || exists $formats{$formats})) {

					Slim::Utils::Prefs::push('disabledformats',$formats);
				}

				$i++;
			}

			foreach my $group (Slim::Utils::Prefs::getArray('disabledformats')) {
				delGroup('formats',$group,1);
			}
		}

		,'GroupOrder' => [qw(Default FormatsList)]
		,'Groups' => {

			'Default' => {
				'PrefOrder' => [qw(disabledextensionsaudio disabledextensionsplaylist)],
				'GroupHead' => 'SETUP_GROUP_FORMATS_EXTENSIONS',
			},

			'FormatsList' => {
				'PrefOrder' => ['formatslist'],
				'PrefsInTable' => 1,
				'Suppress_PrefHead' => 1,
				'Suppress_PrefDesc' => 1,
				'Suppress_PrefLine' => 1,
				'Suppress_PrefSub' => 1,
				'GroupLine' => 1,
				'GroupSub' => 1,
				'GroupHead' => 'SETUP_GROUP_FORMATS_CONVERSION',
				'GroupDesc' => 'SETUP_GROUP_FORMATS_CONVERSION_DESC',
				'GroupPrefHead' => '<tr><th>&nbsp;' .
					'</th><th>' . string('FILE_FORMAT') .
					'</th><th>' . string('STREAM_FORMAT') .
					'</th><th>' . string('DECODER') .
					'</th></tr>',
			}
		},

		'Prefs' => {
			'disabledextensionsaudio' => {

				'validate'      => \&Slim::Utils::Validate::acceptAll,
				'inputTemplate' => 'setup_input_txt.html',
				'PrefSize'      => 'large',
			},

			'disabledextensionsplaylist' => {

				'validate'      => \&Slim::Utils::Validate::acceptAll,
				'inputTemplate' => 'setup_input_txt.html',
				'PrefSize'      => 'large',
			},

			'formatslist' => {
				'isArray' => 1
				,'dontSet' => 1
				,'validate' => \&Slim::Utils::Validate::trueFalse
				,'inputTemplate' => 'setup_input_array_chk.html'
				,'arrayMax' => undef #set in preEval
				,'changeMsg' => 'SETUP_FORMATSLIST_CHANGE'
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
		'parent' => 'BASIC_SERVER_SETTINGS',
		'GroupOrder' => [qw(DisplayInArtists VariousArtists Default)],
		'Groups' => {
	
			'Default' => {

				'PrefOrder' => [qw(displaytexttimeout checkVersion noGenreFilter
						playtrackalbum searchSubString ignoredarticles splitList browseagelimit
						groupdiscs persistPlaylists reshuffleOnRepeat saveShuffled)],
			},

			'DisplayInArtists' => {
				'PrefOrder' => [qw(composerInArtists conductorInArtists bandInArtists)],
				'GroupHead' => 'SETUP_COMPOSERINARTISTS',
				'Suppress_PrefHead' => 1,
				'Suppress_PrefSub' => 1,
				'GroupSub' => 1,
				'GroupLine' => 1,
				'Suppress_PrefLine' => 1,
			},

			'VariousArtists' => {
				'PrefOrder' => [qw(variousArtistAutoIdentification useBandAsAlbumArtist variousArtistsString)],
				'GroupHead' => 'SETUP_VARIOUSARTISTS',
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

					$::d_scan && msgf("Setup::ignoredarticles changed - initiating scan of type: [wipecache]\n");

					Slim::Control::Request::executeRequest($client, ['wipecache']);
				},
			},

			'splitList' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large',
				'onChange' => sub {
					my $client = shift;

					$::d_scan && msgf("Setup::splitList changed - initiating scan of type: [wipecache]\n");

					Slim::Control::Request::executeRequest($client, ['wipecache']);
				},
			},

			'variousArtistAutoIdentification' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'1' => 'SETUP_VARIOUSARTISTAUTOIDENTIFICATION_1',
					'0' => 'SETUP_VARIOUSARTISTAUTOIDENTIFICATION_0',
				},
			},

			'useBandAsAlbumArtist' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'1' => 'SETUP_USEBANDASALBUMARTIST_1',
					'0' => 'SETUP_USEBANDASALBUMARTIST_0',
				},
			},

			'variousArtistsString' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large',
			},

			'playtrackalbum' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => {
					'1' => 'SETUP_PLAYTRACKALBUM_1',
					'0' => 'SETUP_PLAYTRACKALBUM_0',
				},
			},

			'composerInArtists' => { 	 

				'inputTemplate' => 'setup_input_chk.html',
				'PrefChoose'    => 'COMPOSER',
				'validate'      => \&Slim::Utils::Validate::trueFalse,
			},

			'conductorInArtists' => { 	 

				'inputTemplate' => 'setup_input_chk.html',
				'PrefChoose'    => 'CONDUCTOR',
				'validate'      => \&Slim::Utils::Validate::trueFalse,
			},

			'bandInArtists' => { 	 

				'inputTemplate' => 'setup_input_chk.html',
				'PrefChoose'    => 'BAND',
				'validate'      => \&Slim::Utils::Validate::trueFalse,
			},

			'noGenreFilter' => { 	 
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => { 	 
					'1' => 'SETUP_NOGENREFILTER_1',
					'0' => 'SETUP_NOGENREFILTER_0',
				},
			},

			'searchSubString' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => {
					'1' => 'SETUP_SEARCHSUBSTRING_1',
					'0' => 'SETUP_SEARCHSUBSTRING_0',
				},
			},

			'persistPlaylists' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => {
					'1' => 'SETUP_PERSISTPLAYLISTS_1',
					'0' => 'SETUP_PERSISTPLAYLISTS_0',
				},
			},

			'reshuffleOnRepeat' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => {
					'1' => 'SETUP_RESHUFFLEONREPEAT_1',
					'0' => 'SETUP_RESHUFFLEONREPEAT_0',
				},
			},

			'saveShuffled' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'1' => 'SETUP_SAVESHUFFLED_1',
					'0' => 'SETUP_SAVESHUFFLED_0',
				},
			},

			'checkVersion' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'1' => 'SETUP_CHECKVERSION_1',
					'0' => 'SETUP_CHECKVERSION_0',
				},
			},

			'groupdiscs' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'onChange' => sub {
					my $client = shift;

					$::d_scan && msgf("Setup::groupdiscs changed - initiating scan of type: [wipecache]\n");

					Slim::Control::Request::executeRequest($client, ['wipecache']);
				},

				'options' => {
					'1' => 'SETUP_GROUPDISCS_1',
					'0' => 'SETUP_GROUPDISCS_0',
				},
			 },
		}
	} #end of setup{'behavior'} hash

	,'FORMATTING_SETTINGS' => {
		'title' => string('FORMATTING_SETTINGS')
		,'parent' => 'BASIC_SERVER_SETTINGS'
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
					,'GroupHead' => 'SETUP_TITLEFORMAT'
					,'GroupDesc' => 'SETUP_GROUP_TITLEFORMATS_DESC'
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
					,'GroupHead' => 'SETUP_GUESSFILEFORMATS'
					,'GroupDesc' => 'SETUP_GROUP_GUESSFILEFORMATS_DESC'
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
						,'validate' => \&Slim::Utils::Validate::isFormat
						,'changeAddlText' => 'SETUP_TITLEFORMAT_CHANGED'
							}
			,'showArtist' => {
						'validate' => \&Slim::Utils::Validate::trueFalse
						,'options' => {
									'0' => 'DISABLED',
									'1' => 'ENABLED'
								}
							}
			,'showYear' => {
						'validate' => \&Slim::Utils::Validate::trueFalse
						,'options' => {
									'0' => 'DISABLED',
									'1' => 'ENABLED'
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
						,'validate' => \&Slim::Utils::Validate::isFormat
						,'changeAddlText' => 'SETUP_GUESSFILEFORMATS_CHANGED'
					}
			,"longdateFormat" => {
						'validate' => \&Slim::Utils::Validate::inHash
						,'validateArgs' => [\&Slim::Utils::DateTime::longDateFormats,1]
						,'options' => \&Slim::Utils::DateTime::longDateFormats
					}
			,"shortdateFormat" => {
						'validate' => \&Slim::Utils::Validate::inHash
						,'validateArgs' => [\&Slim::Utils::DateTime::shortDateFormats,1]
						,'options' => \&Slim::Utils::DateTime::shortDateFormats
					}
			,"timeFormat" => {
						'validate' => \&Slim::Utils::Validate::inHash
						,'validateArgs' => [\&Slim::Utils::DateTime::timeFormats,1]
						,'options' => \&Slim::Utils::DateTime::timeFormats
					}
			}
		} #end of setup{'FORMATTING_SETTINGS'} hash
	,'SECURITY_SETTINGS' => {
		'title' => string('SECURITY_SETTINGS')
		,'parent' => 'BASIC_SERVER_SETTINGS'
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
								'0' => 'SETUP_NO_AUTHORIZE',
								'1' => 'SETUP_AUTHORIZE',
								}
					}
			,'username' => {
						'validate' => \&Slim::Utils::Validate::acceptAll
						,'PrefSize' => 'large'
					}
			,'password' => {
						'validate' => \&Slim::Utils::Validate::password
						,'inputTemplate' => 'setup_input_passwd.html'
						,'changeMsg' => 'SETUP_PASSWORD_CHANGED'
						,'PrefSize' => 'large'
					}
			,'filterHosts' => {
						
						'validate' => \&Slim::Utils::Validate::trueFalse
						,'PrefHead' => 'SETUP_IPFILTER_HEAD'
						,'PrefDesc' => 'SETUP_IPFILTER_DESC'
						,'options' => {
								'0' => 'SETUP_NO_IPFILTER',
								'1' => 'SETUP_IPFILTER',
							}
					}
			,'csrfProtectionLevel' => {
							'validate' => \&Slim::Utils::Validate::isInt
							,'validateArgs' => [0,2,1,1]
							,'optionSort' => 'V'
							,'options' => {
									'0' => 'NONE',
									'1' => 'MEDIUM',
									'2' => 'HIGH',

								}
						}
			,'allowedHosts' => {
						'validate' => \&Slim::Utils::Validate::allowedHosts
						,'PrefHead' => 'SETUP_FILTERRULE_HEAD'
						,'PrefDesc' => 'SETUP_FILTERRULE_DESC'
						,'PrefSize' => 'large'
					}

			}
		} #end of setup{'security'} hash
	,'PERFORMANCE_SETTINGS' => {
		'title' => string('PERFORMANCE_SETTINGS'),
		'parent' => 'BASIC_SERVER_SETTINGS',
		'GroupOrder' => ['Default'],
		'Groups' => {

			'Default' => {
				'PrefOrder' => [qw(
					disableStatistics
					itemsPerPass
					prefsWriteDelay
					serverPriority
					scannerPriority
				)],
			},
		},

		'Prefs' => {
			'disableStatistics' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'1' => 'SETUP_DISABLE_STATISTICS',
					'0' => 'SETUP_ENABLE_STATISTICS',
				},
			},

			'itemsPerPass' => {
				'validate' => \&Slim::Utils::Validate::isInt,
			},

			'prefsWriteDelay' => {
				'validate' => \&Slim::Utils::Validate::isInt,
				'validateArgs' => [0,undef,1],
			},
			
			'forkedWeb' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => {
					'1' => 'SETUP_FORKEDWEB_ENABLE',
					'0' => 'SETUP_FORKEDWEB_DISABLE',
				},
			},
			
			'forkedStreaming' => {
				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options'  => {
					'1' => 'SETUP_FORKEDSTREAMING_ENABLE',
					'0' => 'SETUP_FORKEDSTREAMING_DISABLE',
				},
			},

			'serverPriority' => {
				'validate' => \&Slim::Utils::Validate::inList,
				'validateArgs' => ['', -20 .. 20],
				'onChange' => sub { Slim::Utils::Misc::setPriority( Slim::Utils::Prefs::get("serverPriority") ); },
				'optionSort' => sub {$a eq "" ? -1 : ($b eq "" ? 1 : $a <=> $b)},
				'options' => {
					''   => 'SETUP_PRIORITY_DEFAULT',
					map {$_ => $_ . " " . Slim::Utils::Strings::getString({
						-16 => 'SETUP_PRIORITY_HIGH',
						-6 => 'SETUP_PRIORITY_ABOVE_NORMAL',
						0 => 'SETUP_PRIORITY_NORMAL',
						5 => 'SETUP_PRIORITY_BELOW_NORMAL',
						15 => 'SETUP_PRIORITY_LOW'
						}->{$_} || "") } (-20 .. 20)
				}
			},

			'scannerPriority' => {
				'validate' => \&Slim::Utils::Validate::inList,
				'validateArgs' => ['', -20 .. 20],
				'optionSort' => sub {$a eq "" ? -1 : ($b eq "" ? 1 : $a <=> $b)},
				'options' => {
					''   => 'SETUP_PRIORITY_CURRENT',
					map {$_ => $_ . " " . Slim::Utils::Strings::getString({
						-16 => 'SETUP_PRIORITY_HIGH',
						-6 => 'SETUP_PRIORITY_ABOVE_NORMAL',
						0 => 'SETUP_PRIORITY_NORMAL',
						5 => 'SETUP_PRIORITY_BELOW_NORMAL',
						15 => 'SETUP_PRIORITY_LOW'
						}->{$_} || "") } (-20 .. 20)
				}
			},

		},
	} #end of setup{'performance'} hash
	,'NETWORK_SETTINGS' => {
		'title' => string('NETWORK_SETTINGS')
		,'parent' => 'BASIC_SERVER_SETTINGS'
		,'GroupOrder' => ['Default','TCP_Params']
		,'Groups' => {
			'Default' => {
					'PrefOrder' => ['webproxy','httpport','bufferSecs','remotestreamtimeout', 'maxWMArate']
				}
			,'TCP_Params' => {
					'PrefOrder' => ['tcpReadMaximum','tcpWriteMaximum','udpChunkSize']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => 'SETUP_GROUP_TCP_PARAMS'
					,'GroupDesc' => 'SETUP_GROUP_TCP_PARAMS_DESC'
					,'GroupLine' => 1
					,'GroupSub' => 1
				}
			}
		,'Prefs' => {
			'httpport'	=> {
						'validate' => \&Slim::Utils::Validate::isInt
						,'validateArgs' => [1025,65535,undef,1]
						,'changeAddlText' => string('SETUP_NEW_VALUE')
									. '<blockquote><a target="_top" href="[EVAL]Slim::Utils::Prefs::homeURL()[/EVAL]">'
									. '[EVAL]Slim::Utils::Prefs::homeURL()[/EVAL]</a></blockquote>'
						,'onChange' => sub {
									my ($client,$changeref,$paramref,$pageref) = @_;
									$paramref->{'HomeURL'} = Slim::Utils::Prefs::homeURL();
								}
					}
			,'webproxy'	=> {
						'validate' => \&Slim::Utils::Validate::hostNameOrIPAndPort,
						'PrefSize' => 'large'
					}
			,'mDNSname'	=> {
							'PrefSize' => 'medium'
					}
			,'bufferSecs' => {
						'validate'   => \&Slim::Utils::Validate::isInt,
						'validateArgs' => [1,30,1,30],
					}							
			,'remotestreamtimeout' => {
						'validate' => \&Slim::Utils::Validate::isInt
						,'validateArgs' => [1,undef,1]
					}
			,'maxWMArate' => {
							'validate' => \&Slim::Utils::Validate::isInt,
							'optionSort' => 'NKR',
							'options' => {
								'9999' => string('NO_LIMIT'),
								'320'  => '320 ' . string('KBPS'),
								'256'  => '256 ' . string('KBPS'),
								'192'  => '192 ' . string('KBPS'),
								'160'  => '160 ' . string('KBPS'),
								'128'  => '128 ' . string('KBPS'),
								'96'   => '96 ' . string('KBPS'),
								'64'   => '64 ' . string('KBPS'),
								'32'   => '32 ' . string('KBPS'),
							}
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
		,'parent' => 'BASIC_SERVER_SETTINGS'
		,'postChange' => sub {
					my ($client,$paramref,$pageref) = @_;
					no strict 'refs';
					foreach my $debugItem (@{$pageref->{'Groups'}{'Default'}{'PrefOrder'}}) {
						my $debugSet = "::" . $debugItem;

						# Lame. Our debugging sucks.
						if ($debugItem eq 'd_sql') {
							Slim::Schema->toggleDebug($$debugSet);
						}

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
					,'GroupDesc' => 'SETUP_GROUP_DEBUG_DESC'
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

	# Bug 2724 - only show the mDNS settings if we have a binary for it.
	if (Slim::Utils::Misc::findbin('mDNSResponderPosix')) {

		push @{$setup{'NETWORK_SETTINGS'}{'Groups'}{'Default'}{'PrefOrder'}}, 'mDNSname';
	}
	
	# Add forking performance options for non-Windows
	if ( $^O !~ /Win32/ ) {
		push @{ $setup{'PERFORMANCE_SETTINGS'}->{'Groups'}->{'Default'}->{'PrefOrder'} },
			'forkedWeb',
			'forkedStreaming';
	}

	# This hack pulls the --d_* debug keys from the main package and sets
	# their current value.
	foreach my $key (sort keys %main:: ) {
		next unless $key =~ /^d_/;
		my %debugTemp = %{$setup{'DEBUGGING_SETTINGS'}{'Prefs'}{'d_'}};
		push @{$setup{'DEBUGGING_SETTINGS'}{'Groups'}{'Default'}{'PrefOrder'}},$key;
		$setup{'DEBUGGING_SETTINGS'}{'Prefs'}{$key} = \%debugTemp;
		$setup{'DEBUGGING_SETTINGS'}{'Prefs'}{$key}{'PrefChoose'} = $key;
		$setup{'DEBUGGING_SETTINGS'}{'Prefs'}{$key}{'changeIntro'} = $key;
	}

	if (scalar(keys %{Slim::Utils::PluginManager::installedPlugins()})) {
		
		Slim::Web::Setup::addChildren('BASIC_SERVER_SETTINGS','PLUGINS');

		# XXX This should be added conditionally based on whether there
		# are any radio plugins. We need to find a place to make that
		# check *after* plugins have been correctly initialized.
		Slim::Web::Setup::addChildren('BASIC_SERVER_SETTINGS','RADIO');
	}
}

sub initSetup {
	initSetupConfig();
	fillAlarmOptions();
}

sub getSetupOptions {
	my ($category, $pref) = @_;
	return $setup{$category}{'Prefs'}{$pref}{'options'};
}

sub getPlayingDisplayModes {
	my $client = shift || return {};
	
	my $displayHash = {	'-1' => ' '	};
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
	
	return {} unless (defined $client && $client->display->isa('Slim::Display::Transporter'));
	
	my $displayHash = {	'-1' => ' '	};
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

	return {} if (!$client || !exists &Slim::Display::Lib::Fonts::fontnames);

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
	my %brightnesses = (
						'0' => '0 ('.string('BRIGHTNESS_DARK').')',
						'1' => '1',
						'2' => '2',
						'3' => '3',
						'4' => '4 ('.string('BRIGHTNESS_BRIGHTEST').')',
						);
	my $client = shift || return \%brightnesses;
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
	my ($set,$pref,$hash) = @_;
	$setup{$set}{'Prefs'}{$pref}{'options'} = {hash_of_prefs($hash)};
	$setup{$set}{'Prefs'}{$pref}{'validateArgs'} = [$setup{$set}{'Prefs'}{$pref}{'options'}];
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
	my ($paramref,@pages) = @_;
	
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
		
		# global setup pages, need to do this at startup too
		} else {
			Slim::Web::Pages->addPageLinks("setup",{"$page"  => "setup.html?page=$page"});
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
		#use external value from 'options' hash
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
	while (my ($key, $value) = each %{$optionref}) {
		$optionref->{$key} = Slim::Utils::Strings::getString($value);
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

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
