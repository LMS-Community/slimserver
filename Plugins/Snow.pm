package Plugins::Snow;

# Snow.pm
# by Phil Barrett, December 2003
# screensaver conversion by Kevin Deane-Freeman Dec 2003

# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
use strict;

###########################################
### Section 1. Change these as required ###
###########################################

use Slim::Control::Command;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Timers;
use Slim::Hardware::VFD;
use File::Spec::Functions qw(:ALL);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.5 $,10);

sub getDisplayName() {return string('PLUGIN_SCREENSAVER_SNOW');}

sub strings() { return '
PLUGIN_SCREENSAVER_SNOW
	EN	Snow Screensaver

PLUGIN_SCREENSAVER_SNOW_SETTINGS
	EN	Snow Screensaver settings

PLUGIN_SCREENSAVER_SNOW_ACTIVATE
	EN	Select Current Screensaver

PLUGIN_SCREENSAVER_SNOW_ACTIVATE_TITLE
	EN	Current Screensaver

PLUGIN_SCREENSAVER_SNOW_ACTIVATED
	EN	Use Snow as current screensaver

PLUGIN_SCREENSAVER_SNOW_DEFAULT
	EN	Use default screensaver (not Snow)

PLUGIN_SCREENSAVER_SNOW_QUANTITY
	EN	Quantity of snow

PLUGIN_SCREENSAVER_SNOW_QUANTITY_TITLE
	EN	Snow Screensaver: Quantity of snow

PLUGIN_SCREENSAVER_SNOW_QUANTITY_0
	EN	Light flurries

PLUGIN_SCREENSAVER_SNOW_QUANTITY_1
	EN	Christmassy

PLUGIN_SCREENSAVER_SNOW_QUANTITY_2
	EN	Blizzard

PLUGIN_SCREENSAVER_SNOW_STYLE
	EN	Style of snow

PLUGIN_SCREENSAVER_SNOW_STYLE_TITLE
	EN	Snow Screensaver: Style of snow

PLUGIN_SCREENSAVER_SNOW_STYLE_0
	EN	Now Playing, snow falling behind

PLUGIN_SCREENSAVER_SNOW_STYLE_1
	EN	Now Playing, snow falling in front

PLUGIN_SCREENSAVER_SNOW_STYLE_2
	EN	Date/Time

PLUGIN_SCREENSAVER_SNOW_STYLE_3
	EN	Just snow

'};

##################################################
### Section 2. Your variables and code go here ###
##################################################

# button functions for browse directory
my @snowSettingsChoices = ('PLUGIN_SCREENSAVER_SNOW_ACTIVATE','PLUGIN_SCREENSAVER_SNOW_QUANTITY', 'PLUGIN_SCREENSAVER_SNOW_STYLE');

my %current;
my %menuParams = (
	'snow' => {
		'listRef' => \@snowSettingsChoices
		,'stringExternRef' => 1
		,'header' => 'PLUGIN_SCREENSAVER_SNOW_SETTINGS'
		,'stringHeader' => 1
		,'headerAddCount' => 1
		,'callback' => \&snowExitHandler
		,'overlayRef' => sub {return (undef,Slim::Hardware::VFD::symbol('rightarrow'));}
		,'overlayRefArgs' => ''
	}
	,catdir('snow','PLUGIN_SCREENSAVER_SNOW_ACTIVATE') => {
		'useMode' => 'INPUT.List'
		,'listRef' => [0,1]
		,'externRef' => ['PLUGIN_SCREENSAVER_SNOW_DEFAULT', 'PLUGIN_SCREENSAVER_SNOW_ACTIVATED']
		,'stringExternRef' => 1
		,'header' => 'PLUGIN_SCREENSAVER_SNOW_ACTIVATE_TITLE'
		,'stringHeader' => 1
		,'onChange' => sub { Slim::Utils::Prefs::clientSet($_[0],'screensaver',$_[1]?'SCREENSAVER.snow':'screensaver'); }
		,'onChangeArgs' => 'CV'
		,'initialValue' => sub { (Slim::Utils::Prefs::clientGet($_[0],'screensaver') eq 'SCREENSAVER.snow' ? 1 : 0); }
	}
	,catdir('snow','PLUGIN_SCREENSAVER_SNOW_QUANTITY') => {
		'useMode' => 'INPUT.List'
		,'listRef' => [0,1,2]
		,'externRef' => ['PLUGIN_SCREENSAVER_SNOW_QUANTITY_0', 'PLUGIN_SCREENSAVER_SNOW_QUANTITY_1', 'PLUGIN_SCREENSAVER_SNOW_QUANTITY_2']
		,'stringExternRef' => 1
		,'header' => 'PLUGIN_SCREENSAVER_SNOW_QUANTITY_TITLE'
		,'stringHeader' => 1
		,'onChange' => sub { Slim::Utils::Prefs::clientSet($_[0],'snowQuantity',$_[1]); }
		,'onChangeArgs' => 'CV'
		,'initialValue' => sub { Slim::Utils::Prefs::clientGet($_[0],'snowQuantity'); }
	}
	,catdir('snow','PLUGIN_SCREENSAVER_SNOW_STYLE') => {
		'useMode' => 'INPUT.List'
		,'listRef' => [0,1,2,3]
		,'externRef' => [ 'PLUGIN_SCREENSAVER_SNOW_STYLE_0','PLUGIN_SCREENSAVER_SNOW_STYLE_1','PLUGIN_SCREENSAVER_SNOW_STYLE_2','PLUGIN_SCREENSAVER_SNOW_STYLE_3']
		,'stringExternRef' => 1
		,'header' => 'PLUGIN_SCREENSAVER_SNOW_STYLE_TITLE'
		,'stringHeader' => 1
		,'onChange' => sub { Slim::Utils::Prefs::clientSet($_[0],'snowStyle',$_[1]); }
		,'onChangeArgs' => 'CV'
		,'initialValue' => sub { Slim::Utils::Prefs::clientGet($_[0],'snowStyle'); }
	}
);

sub snowExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} elsif ($exittype eq 'RIGHT') {
		my $nextmenu = catdir('snow',$current{$client});
		if (exists($menuParams{$nextmenu})) {
			my %nextParams = %{$menuParams{$nextmenu}};
			if ($nextParams{'useMode'} eq 'INPUT.List' && exists($nextParams{'initialValue'})) {
				#set up valueRef for current pref
				my $value;
				if (ref($nextParams{'initialValue'}) eq 'CODE') {
					$value = $nextParams{'initialValue'}->($client);
				} else {
					$value = Slim::Utils::Prefs::clientGet($client,$nextParams{'initialValue'});
				}
				$nextParams{'valueRef'} = \$value;
			}
			Slim::Buttons::Common::pushModeLeft(
				$client
				,$nextParams{'useMode'}
				,\%nextParams
			);
		} else {
			Slim::Display::Animation::bumpRight($client);
		}
	} else {
		return;
	}
}

my %functions = (
	'right' => sub  {
		my ($client,$funct,$functarg) = @_;
		if (defined(Slim::Buttons::Common::param($client,'useMode'))) {
			#in a submenu of settings, which is passing back a button press
			Slim::Display::Animation::bumpRight($client);
		} else {
			#handle passback of button presses
			snowExitHandler($client,'RIGHT');
		}
	}
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $method = shift;
	if ($method eq 'pop') {
		Slim::Buttons::Common::popModeRight($client);
		return;
	}

	# install prefs
	my $snowStyle = Slim::Utils::Prefs::clientGet($client,'snowStyle') || 0;
	Slim::Utils::Prefs::clientSet($client,'snowStyle',$snowStyle);
	my $snowQuantity = Slim::Utils::Prefs::clientGet($client,'snowQuantity') || 1;
	Slim::Utils::Prefs::clientSet($client,'snowQuantity',$snowQuantity);

	$current{$client} = $snowSettingsChoices[0] unless exists($current{$client});
	my %params = %{$menuParams{'snow'}};
	$params{'valueRef'} = \$current{$client};
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
	$client->update();
}

###################################################################
### Section 3. Your variables for your screensaver mode go here ###
###################################################################

# First, Register the screensaver mode here.  Must make the call to addStrings in order to have plugin
# localization available at this point.
sub screenSaver() {
	Slim::Buttons::Common::addSaver('SCREENSAVER.snow', 
				getScreensaverSnowFunctions(),
				\&setScreensaverSnowMode, 
				\&leaveScreensaverSnowMode,
				string('PLUGIN_SCREENSAVER_SNOW'));
}

my %wasDoubleSize;

my %screensaverSnowFunctions = (
	'done' => sub  {
		my ($client, $funct, $functarg) = @_;
		Slim::Buttons::Common::popMode($client);
		$client->update();
		#pass along ir code to new mode if requested
		if (defined $functarg && $functarg eq 'passback') {
			Slim::Hardware::IR::resendButton($client);
		}
	}
	,'textsize' => sub { 
		my $client = shift;
		$wasDoubleSize{$client} = !$wasDoubleSize{$client}; 
	}
);

sub getScreensaverSnowFunctions {
	return \%screensaverSnowFunctions;
}

my %snowStyle;
my %snowQuantity;
my %lastTime;
my %flakes;

sub setScreensaverSnowMode() {
	my $client = shift;
	$client->lines(\&screensaverSnowlines);
	$wasDoubleSize{$client} = Slim::Utils::Prefs::clientGet($client,'doublesize');
	Slim::Utils::Prefs::clientSet($client,'doublesize',0);
	# save time on later lookups - we know these can't change while we're active
	$snowStyle{$client} = Slim::Utils::Prefs::clientGet($client,'snowStyle') || 0;
	$snowQuantity{$client} = Slim::Utils::Prefs::clientGet($client,'snowQuantity') || 1;
}

sub leaveScreensaverSnowMode {
	my $client = shift;
	Slim::Utils::Prefs::clientSet($client,'doublesize',$wasDoubleSize{$client});
	$lastTime{$client} = Time::HiRes::time();
}

sub screensaverSnowlines {
	my $client = shift;
	my ($line1, $line2) = ('','');
	my $onlyInSpaces = 0;
	my $simple = 0;
	if($snowStyle{$client} == 0 || $snowStyle{$client} == 1) {
		# Now Playing
		($line1, $line2) = Slim::Display::Display::renderOverlay(&Slim::Buttons::Playlist::currentSongLines($client));
		$onlyInSpaces = ($snowStyle{$client} == 0);
	} elsif($snowStyle{$client} == 2) {
		# Date/Time
		($line1, $line2) = Slim::Display::Display::renderOverlay(&Slim::Buttons::Common::dateTime($client));
		$onlyInSpaces = 1;
	} else {
		# Just snow
		$simple = 1;
	}
	($line1, $line2) = letItSnow($client, $line1, $line2, $onlyInSpaces, $simple);
	return ($line1, $line2);
}

Slim::Hardware::VFD::setCustomChar('star01',
                                 ( 0b00000010,
                                   0b00000111,
                                   0b00000010,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('star00',
                                 ( 0b00001000,
                                   0b00011100,
                                   0b00001000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('star11',
                                 ( 0b00000000,
                                   0b00000000,
                                   0b00000010,
                                   0b00000111,
                                   0b00000010,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('star10',
                                 ( 0b00000000,
                                   0b00000000,
                                   0b00001000,
                                   0b00011100,
                                   0b00001000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('star21',
                                 ( 0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000010,
                                   0b00000111,
                                   0b00000010,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('star20',
                                 ( 0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00001000,
                                   0b00011100,
                                   0b00001000,
                                   0b00000000 ));

sub tick {
	my $client = shift;
	Slim::Utils::Timers::killTimers($client, \&tick);
	$client->update();
}

sub letItSnow {
	my $client = shift;
	my @lines = (shift, shift);
	my $onlyInSpaces = shift;
	my $simple = shift;
	
	$lastTime{$client} = defined($lastTime{$client}) ? $lastTime{$client} : 0;
	if (Time::HiRes::time() - $lastTime{$client} > 0.25) {
		$lastTime{$client} = Time::HiRes::time();
		my $flake;
		foreach $flake (@{$flakes{$client}}) {
			$flake->{line} ++;
			$flake->{pos} += (int rand(3) - 1);
		}
		
		# cull flakes which have left the screen
		@{$flakes{$client}} = grep { $_->{line} < 6 && $_->{pos} >= 0 && $_->{pos} < 80} @{$flakes{$client}};
		
		my $i;
		foreach $i (0..5) {
			if(rand(100) < (5,10,30)[$snowQuantity{$client}]) {
				my $newflake = {};
				$newflake->{line} = 0;
				$newflake->{pos} = int rand(80);
				push @{$flakes{$client}}, $newflake;
			}
		}
	}

	my $i;
	foreach $i (0,1) {
		if(!$simple) {
			if (index($lines[$i], Slim::Hardware::VFD::symbol('center') ) == 0)  {
				$lines[$i] = substr($lines[$i], length(Slim::Hardware::VFD::symbol('center')));
				s/\s*$//;
				my $centerspaces = int((40-Slim::Hardware::VFD::lineLength($lines[$i]))/2);
				$lines[$i] = (" " x $centerspaces).$lines[$i];
			}
		}
		$lines[$i] = Slim::Hardware::VFD::subString($lines[$i] . (' ' x 40), 0, 40);
	}

	foreach my $flake (@{$flakes{$client}}) {
		my $row = int($flake->{line} / 3);
		my $col = int($flake->{pos} / 2);
		my $sym = 'star' . ($flake->{line} - $row * 3) . ($flake->{pos} - $col * 2);
	
		if(! $onlyInSpaces
			||
			Slim::Hardware::VFD::subString($lines[$row], $col, 1) eq ' ') {
			$lines[$row] =
			($col > 0 ? Slim::Hardware::VFD::subString($lines[$row], 0, $col) : '') . 
			Slim::Hardware::VFD::symbol($sym) .
			($col < 39 ? Slim::Hardware::VFD::subString($lines[$row], $col+1, 39 - $col) : '');
		}
	}

	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 0.25, \&tick);

	return @lines;
}

1;

__END__
