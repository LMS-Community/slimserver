package Slim::Player::Player;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# $Id$
#

use strict;
use Slim::Player::Client;
use Slim::Utils::Misc;
use Slim::Hardware::IR;
use Slim::Buttons::SqueezeNetwork;

use base qw(Slim::Player::Client);

our $defaultPrefs = {
		'autobrightness'		=> 1
		,'bass'					=> 50
		,'digitalVolumeControl'	=> 1
		,'preampVolumeControl'	=> 0
		,'disabledirsets'		=> []
		,'doublesize'			=> 0
		,'idleBrightness'		=> 1
		,'irmap'				=> Slim::Hardware::IR::defaultMapFile()
		,'menuItem'				=> [qw( NOW_PLAYING
										BROWSE_MUSIC
										SEARCH
										RandomPlay::Plugin
										SAVED_PLAYLISTS
										RADIO
										SETTINGS
										PLUGINS
							   )]
		,'mp3SilencePrelude' 	=> 0
		,'offDisplaySize'		=> 0
		,'pitch'				=> 100
		,'playingDisplayMode'	=> 0
		,'playingDisplayModes'	=> [0..5]
		,'power'				=> 1
		,'powerOffBrightness'	=> 1
		,'powerOnBrightness'	=> 4
		,'screensaver'			=> 'playlist'
		,'idlesaver'			=> 'nosaver'
		,'offsaver'				=> 'SCREENSAVER.datetime'
		,'screensavertimeout'	=> 30
		,'scrollMode'           => 0
		,'scrollPause'			=> 3.6
		,'scrollPauseDouble'	=> 3.6
		,'scrollRate'			=> 0.15
		,'scrollRateDouble'		=> 0.1
		,'scrollPixels'			=> 7
		,'scrollPixelsDouble'   => 7
		,'silent'				=> 0
		,'syncPower'			=> 0
		,'syncVolume'			=> 0
		,'treble'				=> 50
		,'upgrade-5.4b1-script'		=> 1
		,'upgrade-5.4b2-script'		=> 1
		,'upgrade-6.1b1-script'		=> 1
		,'upgrade-6.2-script'		=> 1
		,'upgrade-R4627-script'		=> 1
		,'volume'				=> 50
		,'syncBufferThreshold'		=> 128
		,'bufferThreshold'		=> 255
		,'powerOnResume'        => 'PauseOff-NoneOn'
		,'largeTextFont'        => 1
	};

my $scroll_pad_scroll = 6; # chars of padding between scrolling text
my $scroll_pad_ticker = 8; # chars of padding in ticker mode

my %Symbols = (
	'notesymbol' => "\x1Fnotesymbol\x1F",
	'rightarrow' => "\x1Frightarrow\x1F",
	'progressEnd'=> "\x1FprogressEnd\x1F",
	'progress1e' => "\x1Fprogress1e\x1F",
	'progress2e' => "\x1Fprogress2e\x1F",
	'progress3e' => "\x1Fprogress3e\x1F",
	'progress1'  => "\x1Fprogress1\x1F",
	'progress2'  => "\x1Fprogress2\x1F",
	'progress3'  => "\x1Fprogress3\x1F",
	'cursor'	 => "\x1Fcursor\x1F",
	'mixable'    => "\x1Fmixable\x1F",
	'bell'	     => "\x1Fbell\x1F",
	'hardspace'  => "\x1Fhardspace\x1F"
);

our %upgradeScripts = (

	# Allow the "upgrading" of old menu items to new ones.
	'5.4b1' => sub {

		my $client = shift;
		my $index  = 0;

		foreach my $menuItem ($client->prefGetArray('menuItem')) {

			if ($menuItem eq 'ShoutcastBrowser') {
				$client->prefSet('menuItem', 'RADIO', $index);
				last;
			}

			$index++;
		}
	},

	'5.4b2' => sub {
		my $client = shift;

		my $addedBrowse = 0;
		my @newitems = ();

		foreach my $menuItem ($client->prefGetArray('menuItem')) {

			if ($menuItem =~ 'BROWSE_') {

				if (!$addedBrowse) {
					push @newitems, 'BROWSE_MUSIC';
					$addedBrowse = 1;
				}

			} else {

				push @newitems, $menuItem;
			}
		}

		$client->prefSet('menuItem', \@newitems);
	},

	'6.1b1' => sub {
		my $client = shift;

		if (Slim::Buttons::SqueezeNetwork::clientIsCapable($client)) {
			# append a menu item to connect to squeezenetwork to the home menu
			$client->prefPush('menuItem', 'SQUEEZENETWORK_CONNECT');
		}
	},
	'6.2' => sub {
		my $client = shift;
		#kill all alarm settings
		my $alarm = $client->prefGet('alarm') || 0;
		
		if (ref $alarm ne 'ARRAY') {
			my $alarmTime = $client->prefGet('alarmtime') || 0;
			my $alarmplaylist = $client->prefGet('alarmplaylist') || '';
			my $alarmvolume = $client->prefGet('alarmvolume') || 50;
			$client->prefDelete('alarm');
			$client->prefDelete('alarmtime');
			$client->prefDelete('alarmplaylist');
			$client->prefDelete('alarmvolume');
			$client->prefSet('alarm',[$alarm,0,0,0,0,0,0,0]);
			$client->prefSet('alarmtime',[$alarmTime,0,0,0,0,0,0,0]);
			$client->prefSet('alarmplaylist',[$alarmplaylist,'','','','','','','']);
			$client->prefSet('alarmvolume',[$alarmvolume,50,50,50,50,50,50,50]);
		}
	},
	'R4627' => sub {
		my $client = shift;
		# Add RandomMix to home and clear unused prefs
		my $menuItem = $client->prefGet('menuItem') || 0;
		
		if (ref $menuItem eq 'ARRAY') {
			my $insertPos = undef;
			my $randomMixFound = 0;
			for (my $i = 0; $i < @$menuItem; $i++) {
				if (@$menuItem[$i] eq 'RandomPlay::Plugin') {
					$randomMixFound = 1;
					last;
				} elsif (@$menuItem[$i] eq 'SEARCH') {
					$insertPos = $i + 1;
				}
			}

			if (! $randomMixFound) {
				if ($insertPos != undef) {
					# Insert random mix after SEARCH
					$menuItem = [(@$menuItem[0 .. $insertPos - 1],
								  'RandomPlay::Plugin',
								  @$menuItem[$insertPos .. scalar @$menuItem - 1]
								)];
				} else {
					push (@$menuItem, 'RandomPlay::Plugin');
				}
				$client->prefSet('menuItem', $menuItem);
			}

			# Clear old prefs
			$client->prefDelete('plugin_random_exclude_genres');
			Slim::Utils::Prefs::delete('plugin_random_remove_old_tracks');
		}
	},
);

sub new {
	my $class    = shift;
	my $id       = shift;
	my $paddr    = shift;
	my $revision = shift;

	my $client = $class->SUPER::new($id, $paddr);

	# initialize model-specific features:
	$client->revision($revision);

	return $client;
}

sub init {
	my $client = shift;

	# make sure any preferences this client may not have set are set to the default
	# This should be a method on client!
	Slim::Utils::Prefs::initClientPrefs($client, $defaultPrefs);

	# init renderCache for client
	my $cache = {
		'screensize'   => 0,        # screensize for last render [0 forces init of cache on first render]
		'fonts'        => {},       # graphics mode only - font used
		'double'       => 0,        # text mode only - double text
	};
	$client->renderCache($cache);

	$client->SUPER::init();

	for my $version (sort keys %upgradeScripts) {
		if ($client->prefGet("upgrade-$version-script")) {
			&{$upgradeScripts{$version}}($client);
			$client->prefSet( "upgrade-$version-script", 0);
		}
	}

	Slim::Buttons::Home::updateMenu($client);

	# fire it up!
	$client->power($client->prefGet('power'));
	$client->startup();

	# start the screen saver
	Slim::Buttons::ScreenSaver::screenSaver($client);
	$client->brightness($client->prefGet($client->power() ? 'powerOnBrightness' : 'powerOffBrightness'));
}

# usage							float		buffer fullness as a percentage
sub usage {
	my $client = shift;
	return $client->bufferSize() ? $client->bufferFullness() / $client->bufferSize() : 0;
}

sub render {
	my $client = shift;
	my $lines = shift;
	my $scroll = shift || 0; # 0 = no scroll, 1 = normal horiz scroll mode if line 2 too long, 
	                         # 2 = scrollonce with no wrapped text, 3 = ticker scroll
	my $parts;
	my $double;
	my $displayoverlays;

	if ((ref($lines) eq 'HASH')) {
		$parts = $lines;
	} else {
		$parts = $client->parseLines($lines);
	}

	my $cache = $client->renderCache();
	$cache->{changed} = 0;
	$cache->{newscroll} = 0;
	$cache->{restartticker} = 0;
	$cache->{scrollmode} = $parts->{scrollmode};

	if ($cache->{screensize} != 40) {
	    $cache->{screensize} = 40;
		$cache->{changed} = 1;
		$cache->{restartticker} = 1;
	}

	if (defined($parts->{double})) {
		$double = $parts->{double};
	}
	if (defined($parts->{fonts}) && defined($parts->{fonts}->{text})) {
		my $text = $parts->{fonts}->{text};
		if (ref($text) eq 'HASH') {
			if (defined($text->{lines})) {
				if     ($text->{lines} == 1) { $double = 1; }
				elsif ($text->{lines} == 2) { $double = 0; }
			}
			$displayoverlays = $text->{displayoverlays} if exists $text->{displayoverlays};
		} else {
			if    ($text == 1) { $double = 1; } 
			elsif ($text == 2) { $double = 0; }
		}
	} 
	if (!defined($double)) { $double = $client->textSize() ? 1 : 0; }

	if ($double != $cache->{double}) {
		$cache->{double} = $double;
		$cache->{changed} = 1;
		$cache->{restartticker} = 1;
	}

	if ($cache->{changed}) {
		# force full rerender
		$cache->{scrolling} = 0;
		$cache->{line1} = undef;
		$cache->{line1text} = '';
		$cache->{line1finish} = 0;
		$cache->{line2} = undef;
		$cache->{line2text} = '';
		$cache->{line2finish} = 0;
		$cache->{scrollline1ref} = undef;
		$cache->{scrollline2ref} = undef;
		$cache->{overlay1} = undef;
		$cache->{overlay1text} = '';
		$cache->{overlay1start} = 40;
		$cache->{overlay2} = undef;
		$cache->{overlay2text} = '';
		$cache->{overlay2start} = 40;
		$cache->{center1} = undef;
		$cache->{center1text} = undef;
   		$cache->{center2} = undef;
		$cache->{center2text} = undef;
		$cache->{ticker} = 0;
	}

	# if we're only displaying the second line (i.e. single line mode) and the second line is blank,
	# copy the first to the second.  Don't do for ticker mode.
	if ($double && (!$parts->{line2} || $parts->{line2} eq '') && $scroll != 3) {
		$parts->{line2} = $parts->{line1};
	}

	# line 1 - render if changed
	if (defined($parts->{line1}) && 
		(!defined($cache->{line1}) || ($parts->{line1} ne $cache->{line1}) || (!$scroll && $cache->{scrolling}) ||
		 ($scroll == 3) || (($scroll == 1 || $scroll == 2) && $cache->{ticker}) )) {
		$cache->{line1} = $parts->{line1};
		if (!$double) {
			$cache->{line1text} = $parts->{line1};
			$cache->{line1finish} = Slim::Display::Display::lineLength($cache->{line1text});
			$cache->{changed} = 1;
		}
	} elsif (!defined($parts->{line1}) && defined($cache->{line1})) {
		$cache->{line1} = undef;
		if (!$double) {
			$cache->{line1text} = '';
			$cache->{line1finish} = 0;
			$cache->{changed} = 1;
		}
	}

	# line 2 - render if changed
	if (defined($parts->{line2}) && 
		(!defined($cache->{line2}) || ($parts->{line2} ne $cache->{line2}) || (!$scroll && $cache->{scrolling}) ||
		 ($scroll == 3) || (($scroll == 1 || $scroll == 2) && $cache->{ticker}) )) {
		$cache->{line2} = $parts->{line2};
		if (!$double) {
			if (Slim::Utils::Unicode::encodingFromString($parts->{line2}) eq 'raw') {
				# SliMP3 / Pre-G can't handle wide characters outside the latin1 range - turn off the utf8 flag.
				$cache->{line2text} = Slim::Utils::Unicode::utf8off($parts->{line2});
			} else {
				$cache->{line2text} = $parts->{line2};
			}
			$cache->{line2finish} = Slim::Display::Display::lineLength($cache->{line2text});
		} else {
			($cache->{line1text}, $cache->{line2text}) = Slim::Hardware::VFD::doubleSize($client,$parts->{line2});
			$cache->{line1finish} = Slim::Display::Display::lineLength($cache->{line1text});
			$cache->{line2finish} = Slim::Display::Display::lineLength($cache->{line2text});
		}
		$cache->{scrollline1ref} = undef;
		$cache->{scrollline2ref} = undef;
		$cache->{scrolling} = 0;
		$cache->{ticker} = 0 if ($scroll != 3);
		$cache->{changed} = 1;
	} elsif (!defined($parts->{line2}) && (defined($cache->{line2})) || $cache->{restartticker}) {
		$cache->{line2} = undef;
		if ($double) {
			$cache->{line1text} = '';
			$cache->{line1finish} = 0;
		}
		$cache->{line2text} = '';
		$cache->{line2finish} = 0;
		$cache->{changed} = 1;
		$cache->{scrolling} = 0;
		$cache->{ticker} = 0 if ($scroll != 3);
		$cache->{scrollline1ref} = undef;
		$cache->{scrollline2ref} = undef;
	}

	# overlay 1 - render if changed
	if (defined($parts->{overlay1}) && (!defined($cache->{overlay1}) || ($parts->{overlay1} ne $cache->{overlay1}))) {
		$cache->{overlay1} = $parts->{overlay1};
		if (!$double || $displayoverlays) {
			$cache->{overlay1text} = $parts->{overlay1};
		} else {
			$cache->{overlay1text} = '';
		}
		if (Slim::Display::Display::lineLength($cache->{overlay1text}) > 40 ) {
			$cache->{overlay1text} = Slim::Display::Display::subString($cache->{overlay1text}, 0, 40);
		}
		$cache->{overlay1start} = 40 - Slim::Display::Display::lineLength($cache->{overlay1text});
		$cache->{changed} = 1;
	} elsif (!defined($parts->{overlay1}) && defined($cache->{overlay1})) {
		$cache->{overlay1} = undef;
		$cache->{overlay1text} = '';
		$cache->{overlay1start} = 40;
		$cache->{changed} = 1;
	}

	# overlay 2 - render if changed
	if (defined($parts->{overlay2}) && (!defined($cache->{overlay2}) || ($parts->{overlay2} ne $cache->{overlay2}))) {
		$cache->{overlay2} = $parts->{overlay2};
		if (!$double || $displayoverlays) {
			$cache->{overlay2text} = $parts->{overlay2};
		} else {
			$cache->{overlay2text} = '';
		}
		if (Slim::Display::Display::lineLength($cache->{overlay2text}) > 40 ) {
			$cache->{overlay2text} = Slim::Display::Display::subString($cache->{overlay2text}, 0, 40);
		}
		$cache->{overlay2start} = 40 - Slim::Display::Display::lineLength($cache->{overlay2text});
		$cache->{changed} = 1;
	} elsif (!defined($parts->{overlay2}) && defined($cache->{overlay2})) {
		$cache->{overlay2} = undef;
		$cache->{overlay2text} = '';
		$cache->{overlay2start} = 40;
		$cache->{changed} = 1;
	}

	# center 1 - render if changed
	if (defined($parts->{center1}) && (!defined($cache->{center1}) || ($parts->{center1} ne $cache->{center1}))) {
		$cache->{center1} = $parts->{center1};
		if (!$double) {
			my $len = Slim::Display::Display::lineLength($cache->{center1}); 
			if ($len < 39) {
				$cache->{center1text} = ' ' x ((40 - $len)/2) . $cache->{center1} . ' ' x (40 - $len - int((40 - $len)/2));
			} else {
				$cache->{center1text} = Slim::Display::Display::subString($cache->{center1} . ' ', 0 ,40);
			}
		}
		$cache->{changed} = 1;		
	} elsif (!defined($parts->{center1}) && defined($cache->{center1})) {
		if (!$double) {
			$cache->{center1} = undef;
			$cache->{center1text} = undef;
			$cache->{changed} = 1;
		}
	}

	# center 2 - render if changed
	if (defined($parts->{center2}) && (!defined($cache->{center2}) || ($parts->{center2} ne $cache->{center2}))) {
		$cache->{center2} = $parts->{center2};
		if (!$double) {
			my $len = Slim::Display::Display::lineLength($cache->{center2}); 
			if ($len < 39) {
				$cache->{center2text} = ' ' x ((40 - $len)/2) . $cache->{center2} . ' ' x (40 - $len - int((40 - $len)/2));
			} else {
				$cache->{center2text} = Slim::Display::Display::subString($cache->{center2} . ' ', 0 ,40);
			}
		} else {
			my ($center1, $center2) = Slim::Hardware::VFD::doubleSize($client,$parts->{center2});
			my $len = Slim::Display::Display::lineLength($center1);
			if ($len < 39) {
				$cache->{center1text} = ' ' x ((40 - $len)/2) . $center1 . ' ' x (40 - $len - int((40 - $len)/2));
				$cache->{center2text} = ' ' x ((40 - $len)/2) . $center2 . ' ' x (40 - $len - int((40 - $len)/2));
			} else {
				$cache->{center1text} = Slim::Display::Display::subString($center1 . ' ', 0 ,40);
				$cache->{center2text} = Slim::Display::Display::subString($center2 . ' ', 0 ,40);
			}
		}
		$cache->{changed} = 1;
	} elsif (!defined($parts->{center2}) && defined($cache->{center2})) {
		$cache->{center2} = undef;
		$cache->{center1text} = undef if $double;
		$cache->{center2text} = undef;
		$cache->{changed} = 1;
	}
			
	# Assemble components

	my ($line1, $line2);

	# 1st line
	if (defined($cache->{center1text})) { 
		$line1 = Slim::Display::Display::subString($cache->{center1text}, 0, $cache->{overlay1start}). 
				$cache->{overlay1text};

	} else {

		if ($cache->{line1finish} <= $cache->{overlay1start}) {
			$line1 = $cache->{line1text} . ' ' x ($cache->{overlay1start} - $cache->{line1finish}) . 
				$cache->{overlay1text};
		} else {
			$line1 = Slim::Display::Display::subString($cache->{line1text}, 0, $cache->{overlay1start}). 
				$cache->{overlay1text};
		}
	}

	# Add 2nd line
	if (defined($cache->{center2text})) { 
		$line2 = Slim::Display::Display::subString($cache->{center2text}, 0, $cache->{overlay2start}). 
				$cache->{overlay2text};

	} else {

		if ( ($cache->{line2finish} <= $cache->{overlay2start}) && ($scroll != 3) ) {
			$line2 = $cache->{line2text} . ' ' x ($cache->{overlay2start} - $cache->{line2finish}) . 
				$cache->{overlay2text};
		} else {
			if ($scroll) {
				my $scroll1text = $cache->{line1text} if $double;
				my $scroll2text = $cache->{line2text};

				if ($scroll == 1) {
					# enable line 2 scrolling, remove line2text from base display and move to scrolltext
					my $padlen = $scroll_pad_scroll;
					my $pad = ' ' x $padlen;
					$scroll1text .= $pad . Slim::Display::Display::subString($cache->{line1text}, 0, 40) if $double;
					$scroll2text .= $pad . Slim::Display::Display::subString($cache->{line2text}, 0, 40);
					$cache->{endscroll} = $cache->{line2finish} + $padlen;
					$cache->{newscroll} = 1;
				
				} elsif ($scroll == 2) {
					# scrolling without wrapped text - scroll to end only
					$cache->{endscroll} = $cache->{line2finish} - 40;
					$cache->{newscroll} = 1;

				} else {
					# ticker mode
					my $padlen = $scroll_pad_ticker;
					my $pad = ' ' x $padlen;
					if ($cache->{line2finish} > 0 || !$cache->{ticker}) {
						$scroll1text .= $pad if $double;
						$scroll2text .= $pad;
						$cache->{endscroll} = $cache->{line2finish};
						$cache->{newscroll} = 1;
					} else {
						$cache->{endscroll} = 0;
					}
					$cache->{ticker} = 1;
				}
				$cache->{scrolling} = 1;					
				if ($double) {
					$cache->{scrollline1ref} = \$scroll1text;
					$cache->{line1text} = '';
					$cache->{line1finish} = 0;
				}
				$cache->{scrollline2ref} = \$scroll2text;
				$cache->{line2text} = '';
				$cache->{line2finish} = 0;
				$cache->{scrolling} = 1;					

				$line2 = ' ' x $cache->{overlay2start} . $cache->{overlay2text};

			} else {
				# scrolling not enabled - truncate line2
				$line2 = Slim::Display::Display::subString($cache->{line2text}, 0, $cache->{overlay2start}). $cache->{overlay2text};
			}
		}
	}

	$cache->{line1ref} = \$line1;
	$cache->{line2ref} = \$line2;

	return $cache;
}

# Update and animation routines use $client->updateMode() and $client->animateState(), $client->scrollState()
#
# updateMode: 
#   0 = normal
#   1 = periodic updates are blocked
#   2 = all updates are blocked
#
# animateState: 
#   0 = no animation
#   1 = client side push/bump animations
#   2 = update scheduled (timer set to callback update)
#   3 = server side push & bumpLeft/Right
#   4 = server side bumpUp/Down
#   5 = server side showBriefly
#   6 = clear scrolling (used for scrollonce and end scrolling mode)
#
# scrollState:
#   0 = no scrolling
#   1 = server side normal scrolling
#   2 = server side ticker mode
#  3+ = <reserved for client side scrolling>

sub update {
	my $client = shift;
	my $lines = shift;
	my $scrollMode = shift; # 0 = normal scroll, 1 = scroll once only, 2 = no scroll, 3 = ticker scroll, 
                            # 4 = scroll once and end (used for showBriefly mode which clears once scroll is completed)

	# return if updates are blocked
	return if ($client->updateMode() == 2);

	# clear any server side animations or pending updates, don't kill scrolling
	$client->killAnimation(1) if ($client->animateState() > 0);

	my $parts;
	if (defined($lines)) {
		$parts = $client->parseLines($lines);
	} else {
		my $linefunc  = $client->lines();
		$parts = $client->parseLines(&$linefunc($client));
	}

	if (defined($parts->{scrollmode})) {
		$scrollMode = 1 if ($parts->{scrollmode} eq 'scrollonce');
		$scrollMode = 2 if ($parts->{scrollmode} eq 'noscroll');
		$scrollMode = 3 if ($parts->{scrollmode} eq 'ticker');
		$scrollMode = 4 if ($parts->{scrollmode} eq 'scrollonceend');
	}

	if (!defined($scrollMode)) {
		$scrollMode = $client->paramOrPref('scrollMode') || 0;
	}

	my ($scroll, $scrollonce, $ticker);
	if    ($scrollMode == 0) { $scroll = 1; $scrollonce = 0; $ticker = 0; }
	elsif ($scrollMode == 1) { $scroll = 1; $scrollonce = 1; $ticker = 0; }
	elsif ($scrollMode == 2) { $scroll = 0; $scrollonce = 0; $ticker = 0; }
	elsif ($scrollMode == 3) { $scroll = 3; $scrollonce = 1; $ticker = 1; }
	elsif ($scrollMode == 4) { $scroll = 2; $scrollonce = 2; $ticker = 0; }

	my $render = $client->render($parts, $scroll);

	my $state = $client->scrollState();

	if (!$render->{scrolling}) {
		# lines don't require scrolling
		if ($state > 0) {
			$client->scrollStop();
		}
		$client->updateScreen($render);
	} else {
		if ($state == 0) {
			# not scrolling - start scrolling
			$client->scrollInit($render, $scrollonce, $ticker);
		} elsif (($state == 1 && $render->{newscroll}) || 
				 ($state == 2 && (!$ticker || $render->{restartticker})) ) {
			# currently scrolling and new text, or in ticker mode need to exit or new font
			$client->scrollStop();
			$client->scrollInit($render, $scrollonce, $ticker);
		} elsif (($state == 2) && $ticker && $render->{newscroll}) {
			# staying in ticker mode - add to ticker queue & update background
			$client->scrollUpdateTicker($render);
			$client->scrollUpdateBackground($render);
		} else {
			# same scrolling text, possibly new background
			$client->scrollUpdateBackground($render);
		}			  
	}
}

# update screen for character display
sub updateScreen {
	my $client = shift;
	my $render = shift;
	Slim::Hardware::VFD::vfdUpdate($client, ${$render->{line1ref}}, ${$render->{line2ref}});
}

sub prevline1 {
	my $client = shift;
	my $cache = $client->renderCache();
	return $cache->{line1};
}

sub prevline2 {
	my $client = shift;
	my $cache = $client->renderCache();
	return $cache->{line2};
}

sub curDisplay {
	my $client = shift;
	my $cache = $client->renderCache();
	return {
		'line1'    => $cache->{line1},
		'line2'    => $cache->{line2},
		'overlay1' => $cache->{overlay1},
		'overlay2' => $cache->{overlay2},
		'center1'  => $cache->{center1},
		'center2'  => $cache->{center2},
	};
}

sub curLines {
	my $client = shift;

	my $linefunc = $client->lines();

	if (defined $linefunc) {
		return $client->renderOverlay(&$linefunc($client));
	} else {
		return undef;
	}
} 

sub showBriefly {
	my $client = shift;

	# return if update blocked
	return if ($client->updateMode() == 2);

	my ($parsed, $duration, $firstLine, $blockUpdate, $scrollToEnd, $brightness, $callback, $callbackargs);
	my $sbData;

	my $parts = shift;
	if (ref($parts) eq 'HASH') {
		$parsed = $parts;
	} else {
		$parsed = $client->parseLines([$parts, shift]);
	}

	my $args = shift;
	if (ref($args) eq 'HASH') {
		$duration     = $args->{'duration'} || 1; # duration - default to 1 second
		$firstLine    = $args->{'firstline'};     # use 1st line in doubled mode
		$blockUpdate  = $args->{'block'};         # block other updates from cancelling
		$scrollToEnd  = $args->{'scroll'};        # scroll text once before cancelling if scrolling is necessary
		$brightness   = $args->{'brightness'};    # brightness to display at
		$callback     = $args->{'callback'};      # callback when showBriefly completes
		$callbackargs = $args->{'callbackargs'};  # callback arguments
	} else {
		$duration = $args || 1;
		$firstLine    = shift;
		$blockUpdate  = shift;
		$scrollToEnd  = shift;
		$brightness   = shift;
		$callback     = shift;
		$callbackargs = shift;
	}

	if ($firstLine && ($client->linesPerScreen() == 1)) {
		$parsed->{line2} = $parsed->{line1};
	}

	$client->update($parsed, $scrollToEnd ? 4 : undef);
	
	$client->updateMode( $blockUpdate ? 2 : 1 );
	$client->animateState(5);

	if (defined($brightness)) {
		if ($brightness =~ /powerOn|powerOff|idle/) {
			$brightness = $client->prefGet($brightness.'Brightness');
		}
		$sbData->{'oldbrightness'} = $client->brightness();
		$client->brightness($brightness);
	}

	if (defined($callback)) {
		$sbData->{'callback'} = $callback;
		$sbData->{'callbackargs'} = $callbackargs;
	}
	
	$client->showBrieflyData($sbData);

	if (!$scrollToEnd || !$client->scrollData()) {
		Slim::Utils::Timers::setTimer($client,Time::HiRes::time() + $duration, \&endAnimation);
	}
}

sub endShowBriefly {
	my $client = shift;
	my $sbData = $client->showBrieflyData() || return;

	if (defined(my $old = $sbData->{'oldbrightness'})) {
		$client->brightness($old);
	}

	if (defined(my $cb = $sbData->{'callback'})) {
		my $cbargs = $sbData->{'callbackargs'};
		&$cb($cbargs);
	}

	$client->showBrieflyData(undef);
}

sub block {
	Slim::Buttons::Block::block(@_);
}

sub unblock {
	Slim::Buttons::Block::unblock(@_);
}

sub pushUp {
	my $client = shift;
	$client->update();
}

sub pushDown {
	my $client = shift;
	$client->update();
}

sub pushLeft {
	my $client = shift;
	my $start = shift || $client->renderCache();
	my $end = shift || $client->curLines();

	my $renderstart = $client->render($start);
	my ($line1start, $line2start) = ($renderstart->{line1ref}, $renderstart->{line2ref});
	my $renderend = $client->render($end);
	my ($line1end, $line2end) = ($renderend->{line1ref}, $renderend->{line2ref});

	my $line1 = $$line1start . $$line1end;
	my $line2 = $$line2start . $$line2end;

	$client->killAnimation();
	$client->pushUpdate([\$line1, \$line2, 0, 5, 40,  0.02]);
}

sub pushRight {
	my $client = shift;
	my $start = shift || $client->renderCache();
	my $end = shift || $client->curLines();

	my $renderstart = $client->render($start);
	my ($line1start, $line2start) = ($renderstart->{line1ref}, $renderstart->{line2ref});
	my $renderend = $client->render($end);
	my ($line1end, $line2end) = ($renderend->{line1ref}, $renderend->{line2ref});

	my $line1 = $$line1end . $$line1start;
	my $line2 = $$line2end . $$line2start;

	$client->killAnimation();
	$client->pushUpdate([\$line1, \$line2, 40, -5, 0,  0.02]);
}

sub bumpRight {
	my $client = shift;
	my $render = $client->render($client->renderCache());
	my $line1 = ${$render->{line1ref}} . $client->symbols('hardspace');
	my $line2 = ${$render->{line2ref}} . $client->symbols('hardspace');
	$client->killAnimation();
	$client->pushUpdate([\$line1, \$line2, 2, -1, 0, 0.125]);	
}

sub bumpLeft {
	my $client = shift;
	my $render = $client->render($client->renderCache());
	my $line1 = $client->symbols('hardspace') . ${$render->{line1ref}};
	my $line2 = $client->symbols('hardspace') . ${$render->{line2ref}};
	$client->killAnimation();
	$client->pushUpdate([\$line1, \$line2, -1, 1, 1, 0.125]);	
}

sub pushUpdate {
	my $client = shift;
	my $params = shift;
	my ($line1, $line2, $offset, $delta, $end, $deltatime) = @$params;
	
	$offset += $delta;

	my $screenline1 = Slim::Display::Display::subString($$line1, $offset, 40);
	my $screenline2 = Slim::Display::Display::subString($$line2, $offset, 40);

	Slim::Hardware::VFD::vfdUpdate($client, $screenline1, $screenline2);		

	if ($offset != $end) {
		$client->updateMode(1);
		$client->animateState(3);
		Slim::Utils::Timers::setHighTimer($client,Time::HiRes::time() + $deltatime,\&pushUpdate,[$line1,$line2,$offset,$delta,$end,$deltatime]);
	} else {
		$client->endAnimation();
	}
}

sub bumpDown {
	my $client = shift;
	my $render = $client->render($client->renderCache());
	my $line1 = ${$render->{line2ref}};
	my $line2 = ' ' x 40;
	Slim::Hardware::VFD::vfdUpdate($client, $line1, $line2);		
	$client->updateMode(1);
	$client->animateState(4);
	Slim::Utils::Timers::setHighTimer($client,Time::HiRes::time() + 0.125, \&endAnimation);
}

sub bumpUp {
	my $client = shift;
	my $render = $client->render($client->renderCache());
	my $line1 = ' ' x 40;
	my $line2 = ${$render->{line1ref}};
	$client->showBriefly($line1, $line2, 0.125);
	Slim::Hardware::VFD::vfdUpdate($client, $line1, $line2);		
	$client->updateMode(1);
	$client->animateState(4);
	Slim::Utils::Timers::setHighTimer($client,Time::HiRes::time() + 0.125, \&endAnimation);
}

sub scrollInit {
	my $client = shift;
	my $render = shift;
	my $scrollonce = shift; # 0 = continue scrolling after pause, 1 = scroll to endscroll and then stop, 
	                        # 2 = scroll to endscroll and then end animation (causing new update)
	my $ticker = shift;     # 0 = normal pause-scroll, 1 = ticker mode

	my $refresh = $client->paramOrPref($client->linesPerScreen() == 1 ? 'scrollRateDouble': 'scrollRate');
	my $pause = $client->paramOrPref($client->linesPerScreen() == 1 ? 'scrollPauseDouble': 'scrollPause');	
	my $now = Time::HiRes::time();

	my $start = $now + ($ticker ? 0 : (($pause > 0.5) ? $pause : 0.5));

	my $scroll = {
		'endscroll'       => $render->{endscroll},
		'offset'          => 0,
		'scrollonce'      => $scrollonce ? 1 : 0,
		'scrollonceend'   => ($scrollonce == 2) ? 1 : 0,
		'refreshInt'      => $refresh,
		'pauseInt'        => $pause,
		'pauseUntil'      => $start,
		'refreshTime'     => $start,
		'paused'          => 0,
		'overlay2start'   => $render->{overlay2start},
		'ticker'          => $ticker,
	};

	if (defined($render->{line1ref})) {
		# character display
		my $double = $render->{double};
		$scroll->{line1ref} = $render->{line1ref};
		$scroll->{line2ref} = $render->{line2ref};
		$scroll->{shift} = 1;
		$scroll->{double} = $double;
		$scroll->{overlay2text}= $render->{overlay2text};
		if (!$ticker) {
			$scroll->{scrollline1ref} = $render->{scrollline1ref} if $double;
			$scroll->{scrollline2ref} = $render->{scrollline2ref};
		} else {
			my $line1 = (' ' x $render->{overlay2start}) . ${$render->{scrollline1ref}} if $double;
			my $line2 = (' ' x $render->{overlay2start}) . ${$render->{scrollline2ref}};
			$scroll->{scrollline1ref} = \$line1 if $double;
			$scroll->{scrollline2ref} = \$line2;
			$scroll->{endscroll} += $render->{overlay2start};
		}
	}

	if (defined($render->{bitsref})) {
		# graphics display
		my $pixels = $client->paramOrPref($client->linesPerScreen() == 1 ? 'scrollPixelsDouble': 'scrollPixels');	
		$scroll->{shift} = $pixels * $client->bytesPerColumn();
		$scroll->{scrollHeader} = $client->scrollHeader;
		$scroll->{scrollFrameSize} = length($client->scrollHeader) + $client->screenBytes;
		$scroll->{bitsref} = $render->{bitsref};
		if (!$ticker) {
			$scroll->{scrollbitsref} = $render->{scrollbitsref};
		} else {
			my $tickerbits = (chr(0) x $render->{overlay2start}) . ${$render->{scrollbitsref}};
			$scroll->{scrollbitsref} = \$tickerbits;
			$scroll->{endscroll} += $render->{overlay2start};
		}
	}

	$client->scrollData($scroll);
	
	$client->scrollState($ticker ? 2 : 1);
	$client->scrollUpdate();
}

sub scrollStop {
	my $client = shift;

	Slim::Utils::Timers::killHighTimers($client, \&scrollUpdate);
	$client->scrollState(0);
	$client->scrollData(undef);
}

sub scrollUpdateBackground {
	my $client = shift;
	my $render = shift;

	my $scroll = $client->scrollData();

	if (defined($render->{line1ref})) {
		# character display
		$scroll->{line1ref} = $render->{line1ref};
		$scroll->{line2ref} = $render->{line2ref};
		$scroll->{overlay2text} = $render->{overlay2text};

	} elsif (defined($render->{bitsref})) {
		# graphics display
		$scroll->{bitsref} = $render->{bitsref};
	}

	$scroll->{overlay2start} = $render->{overlay2start};

	# force update of screen for if paused, otherwise rely on scrolling to update
	if ($scroll->{paused}) {
		$client->scrollUpdateDisplay($scroll);
	}
}

# indicate length of queue for ticker mode 
sub scrollTickerTimeLeft {
	# returns: time to complete ticker, time to expose queued up text
	my $client = shift;

	my $scroll = $client->scrollData();

	if (!$scroll) {
		return (0, 0);
	} 

	my $todisplay = $scroll->{endscroll} - $scroll->{offset};
	my $completeTime = $todisplay / ($scroll->{shift} / $scroll->{refreshInt});

	my $notdisplayed = $todisplay - $scroll->{overlay2start};
	my $queueTime = ($notdisplayed > 0) ? $notdisplayed / ($scroll->{shift} / $scroll->{refreshInt}) : 0;

	return ($completeTime, $queueTime);
}

# update scrolling for character display
sub scrollUpdateDisplay {
	my $client = shift;
	my $scroll = shift;

	my ($line1, $line2);
	
	my $padlen = $scroll->{overlay2start} - ($scroll->{endscroll} - $scroll->{offset});
	$padlen = 0 if ($padlen < 0);
	my $pad = ' ' x $padlen;

	if (!($scroll->{double})) {
		$line1 = ${$scroll->{line1ref}};
		if ($padlen) {
			$line2 = Slim::Display::Display::subString(${$scroll->{scrollline2ref}} . $pad, $scroll->{offset}, $scroll->{overlay2start}) . $scroll->{overlay2text};
		} else {
			$line2 = Slim::Display::Display::subString(${$scroll->{scrollline2ref}}, $scroll->{offset}, $scroll->{overlay2start}) . $scroll->{overlay2text};
		}
	} else {
		if ($padlen) {
			$line1 = Slim::Display::Display::subString(${$scroll->{scrollline1ref}} . $pad, $scroll->{offset}, 40);
			$line2 = Slim::Display::Display::subString(${$scroll->{scrollline2ref}} . $pad, $scroll->{offset}, 40);
		} else {
			$line1 = Slim::Display::Display::subString(${$scroll->{scrollline1ref}}, $scroll->{offset}, 40);
			$line2 = Slim::Display::Display::subString(${$scroll->{scrollline2ref}}, $scroll->{offset}, 40);
		}
	}

	Slim::Hardware::VFD::vfdUpdate($client, $line1, $line2);
}

sub scrollUpdateTicker {
	my $client = shift;
	my $render = shift;

	my $scroll = $client->scrollData();
	my $double = $scroll->{double};

	my $line1 = Slim::Display::Display::subString(${$scroll->{scrollline1ref}}, $scroll->{offset}) if $double;
	my $line2 = Slim::Display::Display::subString(${$scroll->{scrollline2ref}}, $scroll->{offset});

	my $len = $scroll->{endscroll} - $scroll->{offset};
	my $padChar = $scroll_pad_ticker;

	my $pad = 0;
	if ($render->{overlay2start} > ($len + $padChar)) {
		$pad = $render->{overlay2start} - $len - $padChar;
		$line1 .= ' ' x $pad if $double;
		$line2 .= ' ' x $pad;
	}

	$line1 .= ${$render->{scrollline1ref}} if $double;
	$line2 .= ${$render->{scrollline2ref}};

	$scroll->{scrollline1ref} = \$line1 if $double;
	$scroll->{scrollline2ref} = \$line2;

	$scroll->{endscroll} = $len + $padChar + $pad + $render->{endscroll};
	$scroll->{offset} = 0;
}

sub scrollUpdate {
	my $client = shift;
	my $scroll = $client->scrollData();

	# update display
	$client->scrollUpdateDisplay($scroll);

	my $timenow = Time::HiRes::time();

	if ($timenow < $scroll->{pauseUntil}) {
		# called during pause phase - don't scroll
		$scroll->{paused} = 1;
		$scroll->{refreshTime} = $scroll->{pauseUntil};
		Slim::Utils::Timers::setHighTimer($client, $scroll->{pauseUntil}, \&scrollUpdate);

	} else {
		# update refresh time and skip frame if running behind actual timenow
		do {
			$scroll->{offset} += $scroll->{shift};
			$scroll->{refreshTime} += $scroll->{refreshInt};
		} while ($scroll->{refreshTime} < $timenow);

		$scroll->{paused} = 0;
		if ($scroll->{offset} >= $scroll->{endscroll}) {
			if ($scroll->{scrollonce}) {
				$scroll->{offset} = $scroll->{endscroll};
				if ($scroll->{ticker}) {
					# keep going to wait for ticker to fill
				} elsif ($scroll->{scrollonce} == 1) {
					# finished scrolling at next scrollUpdate
					$scroll->{scrollonce} = 2;
				} elsif ($scroll->{scrollonce} == 2) {
					# transition to permanent scroll pause state
					$scroll->{offset} = 0;
					$scroll->{paused} = 1;
					if ($scroll->{scrollonceend}) {
						# schedule endAnimaton to kill off scrolling and display new screen
						$client->animateState(6) unless ($client->animateState() == 5);
						my $end = ($scroll->{pauseInt} > 0.5) ? $scroll->{pauseInt} : 0.5;
						Slim::Utils::Timers::setTimer($client, $timenow + $end, \&endAnimation);
					}
					return;
				}
			} elsif ($scroll->{pauseInt} > 0) {
				$scroll->{offset} = 0;
				$scroll->{pauseUntil} = $scroll->{refreshTime} + $scroll->{pauseInt};
			} else {
				$scroll->{offset} = 0;
			}
		}
		# fast timer during scroll
		Slim::Utils::Timers::setHighTimer($client, $scroll->{refreshTime}, \&scrollUpdate);
	}
}

sub killAnimation {
	my $client = shift;
	my $exceptScroll = shift; # all but scrolling to be killed

	my $animate = $client->animateState();
	Slim::Utils::Timers::killTimers($client, \&update) if ($animate == 2);
	Slim::Utils::Timers::killHighTimers($client, \&pushUpdate) if ($animate == 3);	
	Slim::Utils::Timers::killHighTimers($client, \&endAnimation) if ($animate == 4);
	Slim::Utils::Timers::killTimers($client, \&endAnimation) if ($animate == 5 || $animate == 6);	
	$client->scrollStop() if (($client->scrollState() > 0) && !$exceptScroll);
	$client->endShowBriefly() if ($animate == 5);
	$client->animateState(0);
	$client->updateMode(0);
}

sub endAnimation {
	# called after after an animation to display the screen and initiate scrolling
	my $client = shift;
	my $delay = shift;

	if ($delay) {
		# set timer to call update after delay - use lines stored in render cache
		# called when SB2 ends client side animation and sends ANIC frame
		$client->animateState(2);
		$client->updateMode(1);
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $delay, \&update, $client->renderCache());
	} else {
		# call update using lines stored in render cache except for showBriefly and bump Up/Down
		my $screen;
		my $animate = $client->animateState();
		$screen = $client->renderCache() unless ($animate == 4 || $animate == 5 || $animate == 6);
		$client->endShowBriefly() if ($animate == 5);
		$client->animateState(0);
		$client->updateMode(0);
		$client->update($screen);
	}
}	

sub isPlayer {
	return 1;
}

sub symbols {
	my $client = shift;
	my $line = shift || return undef;

	return $Symbols{$line} if exists $Symbols{$line};
	return "\x1F$line\x1F" if Slim::Hardware::VFD::isCustomChar($line);

	return $line;
}
	
# parse the stringified display commands into a hash.  try to extract them if
# they come as a reference to an array, a scalar, a reference to a scalar or
# even a pre-processed hash.
sub parseLines {
	my $client = shift;
	my $lines = shift;
	my %parts;
	my ($line1, $line2, $line3, $line4, $overlay1, $overlay2, $center1, $center2, $bits);
	
	if (ref($lines) eq 'HASH') { 
		return $lines;
	} elsif (ref($lines) eq 'SCALAR') {
		$line1 = $$lines;
	} else {
		if (ref($lines) eq 'ARRAY') {
			$line1= $lines->[0];
			$line2= $lines->[1];
			$line3= $lines->[2];
			$line4= $lines->[3];
		} else {
			$line1 = $lines;
			$line2 = shift;
			$line3 = shift;
			$line4 = shift;
		}
		
		return $line1 if (ref($line1) eq 'HASH');
		
		if (!defined($line1)) { $line1 = ''; }
		if (!defined($line2)) { $line2 = ''; }

		$line1 .= "\x1eright\x1e" . $line3 if (defined($line3));

		$line2 .= "\x1eright\x1e" . $line4 if (defined($line4));

		if (length($line2)) { 
			$line1 .= "\x1elinebreak\x1e" . $line2;
		}
	}

	while ($line1 =~ s/\x1eframebuf\x1e(.*)\x1e\/framebuf\x1e//s) {
		$bits |= $1;
	}

	$line1 = $client->symbols($line1);
	($line1, $line2) = split("\x1elinebreak\x1e", $line1);

	if (!defined($line2)) { $line2 = '';}
	
	($line1, $overlay1) = split("\x1eright\x1e", $line1) if $line1;
	($line2, $overlay2) = split("\x1eright\x1e", $line2) if $line2;

	($line1, $center1) = split("\x1ecenter\x1e", $line1) if $line1;
	($line2, $center2) = split("\x1ecenter\x1e", $line2) if $line2;

	$line1 = '' if (!defined($line1));

	$parts{bits} = $bits;
	$parts{line1} = $line1;
	$parts{line2} = $line2;
	$parts{overlay1} = $overlay1;
	$parts{overlay2} = $overlay2;
	$parts{center1} = $center1;
	$parts{center2} = $center2;

	return \%parts;
}

sub power {
	my $client = shift;
	my $on = shift;
	
	my $currOn = $client->prefGet('power') || 0;
	
	return $currOn unless defined $on;
	return unless (!defined(Slim::Buttons::Common::mode($client)) || ($currOn != $on));

	$client->renderCache()->{defaultfont} = undef;

	$client->prefSet( 'power', $on);

	my $resume = Slim::Player::Sync::syncGroupPref($client, 'powerOnResume') || $client->prefGet('powerOnResume');
	$resume =~ /(.*)Off-(.*)On/;
	my ($resumeOff, $resumeOn) = ($1,$2);

	unless ($on) {
		# turning player off - move to off mode and unsync/pause/stop player
  
		$client->killAnimation();
		$client->brightness($client->prefGet("powerOffBrightness"));
		Slim::Buttons::Common::setMode($client, 'off');
			  
	    my $sync = $client->prefGet('syncPower');
		if (defined $sync && $sync == 0) {
			$::d_sync && msg("Temporary Unsync ".$client->id()."\n");
			Slim::Player::Sync::unsync($client,1);
  		}
  
		if (Slim::Player::Source::playmode($client) eq 'play') {

			if (Slim::Player::Playlist::song($client) && 
				Slim::Music::Info::isRemoteURL(Slim::Player::Playlist::url($client))) {
				# always stop if currently playing remote stream
				$client->execute(["stop"]);
			
			} elsif ($resumeOff eq 'Pause') {
				# Pause client mid track
				$client->execute(["pause", 1]);
  		
			} else {
				# Stop client
				$client->execute(["stop"]);
			}
		}

		# turn off audio outputs
		$client->audio_outputs_enable(0);

	} else {
		# turning player on - reset mode & brightness, display welcome and sync/start playing

		$client->audio_outputs_enable(1);

		$client->update( {} );
		$client->updateMode(2); # block updates to hide mode change

		Slim::Buttons::Common::setMode($client, 'home');

		$client->updateMode(0); # unblock updates
		
		# restore the saved brightness, unless its completely dark...
		my $powerOnBrightness = $client->prefGet("powerOnBrightness");

		if ($powerOnBrightness < 1) { 
			$powerOnBrightness = 1;
			$client->prefSet("powerOnBrightness", $powerOnBrightness);
		}
		$client->brightness($powerOnBrightness);

		my $oneline = ($client->linesPerScreen() == 1);
		
		$client->showBriefly( {
			'center1' => $oneline ? undef : $client->string('WELCOME_TO_' . $client->model),
			'center2' => $oneline ? $client->string($client->model) : $client->string('FREE_YOUR_MUSIC'),
		}, undef, undef, 1);

		# check if there is a sync group to restore
		Slim::Player::Sync::restoreSync($client);

		if (Slim::Player::Source::playmode($client) ne 'play') {
			
			if ($resumeOn =~ /Reset/) {
				# reset playlist to start
				$client->execute(["playlist","jump", 0, 1]);
			}

			if ($resumeOn =~ /Play/ && Slim::Player::Playlist::song($client) &&
				!Slim::Music::Info::isRemoteURL(Slim::Player::Playlist::url($client))) {
				# play if current playlist item is not a remote url
				$client->execute(["play"]);
			}
		}		
	}
}

sub audio_outputs_enable { }

sub maxVolume { return 100; }
sub minVolume {	return 0; }

sub maxTreble {	return 100; }
sub minTreble {	return 0; }

sub maxBass {	return 100; }
sub minBass {	return 0; }

sub fonts { return undef; }

# fade the volume up or down
# $fade = number of seconds to fade 100% (positive to fade up, negative to fade down) 
# $callback is function reference to be called when the fade is complete
our %fvolume;  # keep temporary fade volume for each client

sub fade_volume {
	my($client, $fade, $callback, $callbackargs) = @_;

	$::d_ui && msg("entering fade_volume:  fade: $fade to $fvolume{$client}\n");
	
	my $faderate = 20;  # how often do we send updated fade volume commands per second
	
	Slim::Utils::Timers::killTimers($client, \&fade_volume);
	
	my $vol = $client->prefGet("volume");
	my $mute = $client->prefGet("mute");
	
	if ($vol < 0) {
		# correct volume if mute volume is stored
		$vol = -$vol;
	}
	
	if (($fade == 0) ||
		($vol < 0 && $fade < 0)) {
		# the volume is muted or fade is instantaneous, don't fade.
		$callback && (&$callback(@$callbackargs));
		return;
	}

	# on the first pass, set temporary fade volume
	if(!$fvolume{$client} && $fade > 0) {
		# fading up, start volume at 0
		$fvolume{$client} = 0;
	} elsif(!$fvolume{$client}) {
		# fading down, start volume at current volume
		$fvolume{$client} = $vol;
	}

	$fvolume{$client} += $client->maxVolume() * (1/$faderate) / $fade; # fade volume

	if ($fvolume{$client} < 0) { $fvolume{$client} = 0; };
	if ($fvolume{$client} > $vol) { $fvolume{$client} = $vol; };

	$client->volume($fvolume{$client},1); # set volume

	if (($fvolume{$client} == 0 && $fade < 0) || ($fvolume{$client} == $vol && $fade > 0)) {	
		# done fading
		$::d_ui && msg("fade_volume done.  fade: $fade to $fvolume{$client} (vol: $vol)\n");
		$fvolume{$client} = 0; # reset temporary fade volume 
		$callback && (&$callback(@$callbackargs));
	} else {
		$::d_ui && msg("fade_volume - setting volume to $fvolume{$client} (originally $vol)\n");
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time()+ (1/$faderate), \&fade_volume, ($fade, $callback, $callbackargs));
	}
}

# mute or un-mute volume as necessary
# A negative volume indicates that the player is muted and should be restored 
# to the absolute value when un-muted.
sub mute {
	my $client = shift;
	
	if (!$client->isPlayer()) {
		return 1;
	}

	my $vol = $client->prefGet("volume");
	my $mute = $client->prefGet("mute");
	
	if (($vol < 0) && ($mute)) {
		# mute volume
		# todo: there is actually a hardware mute feature
		# in both decoders. Need to add Decoder::mute
		$client->volume(0);
	} else {
		# un-mute volume
		$vol *= -1;
		$client->volume($vol);
	}

	$client->prefSet( "volume", $vol);
	Slim::Display::Display::volumeDisplay($client);
}

sub brightness {
	my ($client,$delta, $noupdate) = @_;

	if (defined($delta) ) {
		if ($delta =~ /[\+\-]\d+/) {
			$client->currBrightness( ($client->currBrightness() + $delta) );
		} else {
			$client->currBrightness( $delta );
		}

		$client->currBrightness(0) if ($client->currBrightness() < 0);
		$client->currBrightness($client->maxBrightness()) if ($client->currBrightness() > $client->maxBrightness());
	
		if (!$noupdate && !$client->scrollState()) {
			$client->update($client->renderCache());
		}
	}
	
	my $brightness = $client->currBrightness();

	if (!defined($brightness)) { $brightness = $client->maxBrightness(); }	

	return $brightness;
}

sub maxBrightness {
	return $Slim::Hardware::VFD::MAXBRIGHTNESS;
}

sub textSize {
	my $client = shift;
	my $newsize = shift;
	
	my $prefname = ($client->power()) ? "doublesize" : "offDisplaySize";
	
	if (defined($newsize)) {
		return	$client->prefSet( $prefname, $newsize);
	} else {
		return	$client->prefGet($prefname);
	}
}

# $client->textSize = 1 for LARGE text, 0 for small.
sub linesPerScreen {
	my $client = shift;
	return $client->textSize() ? 1 : 2;	
}

sub maxTextSize {
	return 1;
}

sub hasDigitalOut {
	return 0;
}
	
sub displayWidth {
	return 40;
}

sub sendFrame {};

sub currentSongLines {
	my $client = shift;
	my $parts;
	
	my $playlistlen = Slim::Player::Playlist::count($client);

	if ($playlistlen < 1) {

		$parts->{line1} = $client->string('NOW_PLAYING');
		$parts->{line2} = $client->string('NOTHING');

	} else {

		if (Slim::Player::Source::playmode($client) eq "pause") {

			if ( $playlistlen == 1 ) {
				$parts->{line1} = $client->string('PAUSED');
			}
			else {
				$parts->{line1} = sprintf(
					$client->string('PAUSED')." (%d %s %d) ",
					Slim::Player::Source::playingSongIndex($client) + 1, $client->string('OUT_OF'), $playlistlen
				);
			}

		# for taking photos of the display, comment out the line above, and use this one instead.
		# this will cause the display to show the "Now playing" screen to show when paused.
		# line1 = "Now playing" . sprintf " (%d %s %d) ", Slim::Player::Source::playingSongIndex($client) + 1, string('OUT_OF'), $playlistlen;

		} elsif (Slim::Player::Source::playmode($client) eq "stop") {

			if ( $playlistlen == 1 ) {
				$parts->{line1} = $client->string('STOPPED');
			}
			else {
				$parts->{line1} = sprintf(
					$client->string('STOPPED')." (%d %s %d) ",
					Slim::Player::Source::playingSongIndex($client) + 1, $client->string('OUT_OF'), $playlistlen
				);
			}

		} else {

			if (Slim::Player::Source::rate($client) != 1) {
				$parts->{line1} = $client->string('NOW_SCANNING') . ' ' . Slim::Player::Source::rate($client) . 'x';
			} elsif (Slim::Player::Playlist::shuffle($client)) {
				$parts->{line1} = $client->string('PLAYING_RANDOMLY');
			} else {
				$parts->{line1} = $client->string('PLAYING');
			}
			
			if ($client->volume() < 0) {
				$parts->{line1} .= " ". $client->string('LCMUTED');
			}

			if ( $playlistlen > 1 ) {
				$parts->{line1} = $parts->{line1} . sprintf(
					" (%d %s %d) ",
					Slim::Player::Source::playingSongIndex($client) + 1, $client->string('OUT_OF'), $playlistlen
				);
			}
		} 

		$parts->{line2} = Slim::Music::Info::getCurrentTitle($client, Slim::Player::Playlist::url($client));

		$parts->{overlay2} = $client->symbols(Slim::Display::Display::symbol('notesymbol'));

		# add in the progress bar and time...
		$client->nowPlayingModeLines($parts);
	}
	
	return $parts;
}

sub playingModeOptions { 
	my $client = shift;
	my %options = (
		'0' => $client->string('BLANK'),
		'1' => $client->string('ELAPSED'),
		'2' => $client->string('REMAINING'),
		'3' => $client->string('PROGRESS_BAR'),
		'4' => $client->string('ELAPSED') . ' ' . $client->string('AND') . ' ' . $client->string('PROGRESS_BAR'),
		'5' => $client->string('REMAINING') . ' ' . $client->string('AND') . ' ' . $client->string('PROGRESS_BAR'),
		'6' => $client->string('SETUP_SHOWBUFFERFULLNESS'),
	);
	
	return \%options;
}

sub nowPlayingModes {
	my $client = shift;
	
	return scalar(keys %{$client->playingModeOptions()});
}

sub nowPlayingModeLines {
	my ($client, $parts) = @_;
	my $overlay;
	my $fractioncomplete   = 0;
	my $playingDisplayMode = $client->prefGet('playingDisplayModes',$client->prefGet("playingDisplayMode"));

	$client->param(
		'animateTop',
		(Slim::Player::Source::playmode($client) ne "stop") ? $playingDisplayMode : 0
	);

	unless (defined $playingDisplayMode) {
		$playingDisplayMode = 1;
	};

	# check if we don't know how long the track is...
	if (!Slim::Player::Source::playingSongDuration($client) && ($playingDisplayMode != 6)) {
		# no progress bar, remaining time is meaningless
		$playingDisplayMode = ($playingDisplayMode % 3) ? 1 : 0;

	} else {
		$fractioncomplete = Slim::Player::Source::progress($client);
	}

	my $songtime = " " . Slim::Player::Source::textSongTime($client, $playingDisplayMode);

	if ( $playingDisplayMode == 6) {
		# show both the usage bar and numerical usage
		$fractioncomplete = $client->usage();
		my $usageLine = ' ' . int($fractioncomplete * 100 + 0.5)."%";
		my $usageLineLength = $client->measureText($usageLine,1);

		my $leftLength = $client->measureText($parts->{line1}, 1);
		my $barlen = $client->displayWidth()  - $leftLength - $usageLineLength;
		my $bar    = $client->symbols($client->progressBar($barlen, $fractioncomplete));

		$overlay = $bar . $usageLine;
	}
	
	if ($playingDisplayMode == 1 || $playingDisplayMode == 2) {
		$overlay = $songtime;

	} elsif ($playingDisplayMode == 3) {

		# just show the bar
		my $leftLength = $client->measureText($parts->{line1}, 1);
		my $barlen = $client->displayWidth() - $leftLength;
		my $bar    = $client->symbols($client->progressBar($barlen, $fractioncomplete));

		$overlay = $bar;

	} elsif ($playingDisplayMode == 4 || $playingDisplayMode == 5) {

		# show both the bar and the time
		my $leftLength = $client->measureText($parts->{line1}, 1);
		my $barlen = $client->displayWidth() - $leftLength - $client->measureText($songtime, 1);

		my $bar    = $client->symbols($client->progressBar($barlen, $fractioncomplete));

		$overlay = $bar . $songtime;
	}
	$parts->{overlay1} = $overlay;
	return $parts;
}

sub measureText {
	my $client = shift;
	my $text = shift;
	my $line = shift;
	
	return Slim::Display::Display::lineLength($text);
}


sub renderOverlay {
	my $client = shift;
	my $line1 = shift;
	my $line2 = shift;
	my $overlay1 = shift;
	my $overlay2 = shift;
	my $center1;
	my $center2;
	
	return $line1 if (ref($line1) eq 'HASH');
	return $line1 if $line1 =~ /\x1e(framebuf|linebreak|right)\x1e/s;

	my $parts;

	($line1, $center1) = split("\x1ecenter\x1e", $line1) if $line1;
	($line2, $center2) = split("\x1ecenter\x1e", $line2) if $line2;

	$parts->{line1} = defined($line1) ? $client->symbols($line1) : undef;
	$parts->{line2} = defined($line2) ? $client->symbols($line2) : undef;
	$parts->{overlay1} = defined($overlay1) ? $client->symbols($overlay1) : undef;
	$parts->{overlay2} = defined($overlay2) ? $client->symbols($overlay2) : undef;
	$parts->{center1} = defined($center1) ? $client->symbols($center1) : undef;
	$parts->{center2} = defined($center2) ? $client->symbols($center2) : undef;

	return $parts;
}

# Draws a slider bar, bidirectional or single direction is possible.
# $value should be pre-processed to be from 0-100
# $midpoint specifies the position of the divider from 0-100 (use 0 for progressBar)
# returns a +/- balance/bass/treble bar text AND sets up custom characters if necessary
# range 0 to 100, 50 is middle.
sub sliderBar {
	my ($client,$width,$value,$midpoint,$fullstep) = @_;
	$midpoint = 0 unless defined $midpoint;
	if ($width == 0) {
		return "";
	}
	
	my $charwidth = 5;

	if ($value < 0) {
		$value = 0;
	}
	
	if ($value > 100) {
		$value = 100;
	}
	
	my $chart = "";
	
	my $totaldots = $charwidth + ($width - 2) * $charwidth + $charwidth;

	# felix mueller discovered some rounding errors that were causing the
	# calculations to be off.  Doing it 1000 times up seems to be better.  
	# go figure.
	my $dots = int( ( ( $value * 10 ) * $totaldots) / 1000);
	my $divider = ($midpoint/100) * ($width-2);

	my $val = $value/100 * $width;
	$width = $width - 1 if $midpoint;
	
	if ($dots < 0) { $dots = 0 };
	
	if ($dots < $charwidth) {
		$chart = $midpoint ? Slim::Display::Display::symbol('leftprogress4') : Slim::Display::Display::symbol('leftprogress'.$dots);
	} else {
		$chart = $midpoint ? Slim::Display::Display::symbol('leftprogress0') : Slim::Display::Display::symbol('leftprogress4');
	}
	
	$dots -= $charwidth;
			
	if ($midpoint) {
		for (my $i = 1; $i < $divider; $i++) {
			if ($dots <= 0) {
				$chart .= Slim::Display::Display::symbol('solidblock');
			} else {
				$chart .= Slim::Display::Display::symbol('middleprogress0');
			}
			$dots -= $charwidth;
		}
		if ($value < $midpoint) {
			$chart .= Slim::Display::Display::symbol('solidblock');
			$dots -= $charwidth;
		} else {
			$chart .= Slim::Display::Display::symbol('leftmark');
			$dots -= $charwidth;
		}
	}
	for (my $i = $divider + 1; $i < ($width - 1); $i++) {
		if ($midpoint && $i == $divider + 1) {
			if ($value > $midpoint) {
				$chart .= Slim::Display::Display::symbol('solidblock');
			} else {
				$chart .= Slim::Display::Display::symbol('rightmark');
			}
			$dots -= $charwidth;
		}
		if ($dots <= 0) {
			$chart .= Slim::Display::Display::symbol('middleprogress0');
		} elsif ($dots < $charwidth && !$fullstep) {
			$chart .= Slim::Display::Display::symbol('middleprogress'.$dots);
		} else {
			$chart .= Slim::Display::Display::symbol('solidblock');
		}
		$dots -= $charwidth;
	}
		
	if ($dots <= 0) {
		$chart .= Slim::Display::Display::symbol('rightprogress0');
	} elsif ($dots < $charwidth && !$fullstep) {
		$chart .= Slim::Display::Display::symbol('rightprogress'.$dots);
	} else {
		$chart .= Slim::Display::Display::symbol('rightprogress4');
	}
	
	return $chart;
}

# returns progress bar text
sub progressBar {
	return sliderBar(shift,shift,(shift)*100,0);
}

sub balanceBar {
	return sliderBar(shift,shift,shift,50);
}

sub textSongTime {
	my $client = shift;
	my $remaining = shift;

	my $delta = 0;
	my $sign  = '';

	my $duration = Slim::Player::Source::playingSongDuration($client) || 0;

	if (Slim::Player::Source::playmode($client) eq "stop") {
		$delta = 0;
	} else {	
		$delta = Slim::Player::Source::songTime($client);
		if ($duration && $delta > $duration) {
			$delta = $duration;
		}
	}

	# 2 and 5 display remaining time, not elapsed
	if ($remaining) {
		if ($duration) {
			$delta = $duration - $delta;	
			$sign = '-';
		}
	}
	
	my $hrs = int($delta / (60 * 60));
	my $min = int(($delta - $hrs * 60 * 60) / 60);
	my $sec = $delta - ($hrs * 60 * 60 + $min * 60);
	
	my $time;
	if ($hrs) {
		$time = sprintf("%s%d:%02d:%02d", $sign, $hrs, $min, $sec);
	} else {
		$time = sprintf("%s%02d:%02d", $sign, $min, $sec);
	}
	return $time;
}


1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
