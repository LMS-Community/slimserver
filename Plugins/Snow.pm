package Plugins::Snow;

# $Id$
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
use Slim::Utils::Timers;
use Slim::Hardware::VFD;
use File::Spec::Functions qw(:ALL);

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.16 $,10);

sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_SNOW';
}

sub strings { return '
PLUGIN_SCREENSAVER_SNOW
	DE	Schnee Bildschirmschoner
	EN	Snow Screensaver
	FR	Ecran de veille Neige

PLUGIN_SCREENSAVER_SNOW_SETTINGS
	DE	Schnee Einstellungen
	EN	Snow Screensaver settings
	FR	Réglages Ecran de veille Neige

PLUGIN_SCREENSAVER_SNOW_ACTIVATE
	DE	Diesen Bildschirmschoner aktivieren
	EN	Select Current Screensaver
	FR	Choisir écran de veille courant

PLUGIN_SCREENSAVER_SNOW_ACTIVATE_TITLE
	DE	Aktueller Bildschirmschoner
	EN	Current Screensaver
	FR	Ecran de veille courant

PLUGIN_SCREENSAVER_SNOW_ACTIVATED
	DE	Schnee Bildschirmschoner aktivieren
	EN	Use Snow as current screensaver
	FR	Utiliser Neige comme écran de veille

PLUGIN_SCREENSAVER_SNOW_DEFAULT
	DE	Standard-Bildschirmschoner aktivieren
	EN	Use default screensaver (not Snow)
	FR	Utiliser écran de veille par défaut (hors Neige)

PLUGIN_SCREENSAVER_SNOW_QUANTITY
	DE	Schneemenge
	EN	Quantity of snow
	FR	Intensité neige

PLUGIN_SCREENSAVER_SNOW_QUANTITY_TITLE
	DE	Schnee Bildschirmschoner: Schneemenge
	EN	Snow Screensaver: Quantity of snow
	FR	Ecran de veille neige: Intensité

PLUGIN_SCREENSAVER_SNOW_QUANTITY_0
	DE	Ein paar Schneeflocken
	EN	Light flurries
	FR	Quelques flocons

PLUGIN_SCREENSAVER_SNOW_QUANTITY_1
	DE	Weihnächtlich weiss
	EN	Christmassy
	FR	C\'est Noël !

PLUGIN_SCREENSAVER_SNOW_QUANTITY_2
	DE	Heftiges Schneegestöber
	EN	Blizzard
	FR	Tempête

PLUGIN_SCREENSAVER_SNOW_STYLE
	DE	Schneetyp
	EN	Style of snow
	FR	Type neige

PLUGIN_SCREENSAVER_SNOW_STYLE_TITLE
	DE	Schnee Bildschirmschoner: Schneetyp
	EN	Snow Screensaver: Style of snow
	FR	Ecran de veille Neige: Type

PLUGIN_SCREENSAVER_SNOW_STYLE_1
	DE	Es läuft gerade... mit Schnee im Hintergrund
	EN	Now Playing, snow falling behind
	FR	Lecture + neige en arrière-plan

PLUGIN_SCREENSAVER_SNOW_STYLE_2
	DE	Es läuft gerade... mit Schnee im Vordergrund
	EN	Now Playing, snow falling in front
	FR	Lecture +  neige en avant-plan

PLUGIN_SCREENSAVER_SNOW_STYLE_3
	DE	Datum/Zeit
	EN	Date/Time
	FR	Date/Heure

PLUGIN_SCREENSAVER_SNOW_STYLE_4
	DE	Nur Schnee
	EN	Just snow
	FR	Neige seule

PLUGIN_SCREENSAVER_SNOW_STYLE_5
	DE	Automatisch
	EN	Automatic
	FR	Automatique

PLUGIN_SCREENSAVER_SNOW_STYLE_6
	DE	Frohe Feiertage!
	EN	Season\'s Greetings

PLUGIN_SCREENSAVER_SNOW_NUMBER_OF_WORDS
	DE	4
	EN	5
	FR	2

PLUGIN_SCREENSAVER_SNOW_WORD_0
	DE	FROHE
	EN	MERRY
	FR	JOYEUX

PLUGIN_SCREENSAVER_SNOW_WORD_1
	DE	WEIHNACHTEN
	EN	CHRISTMAS
	FR	NOEL

PLUGIN_SCREENSAVER_SNOW_WORD_2
	DE	UND EIN GUTES
	EN	AND A VERY

PLUGIN_SCREENSAVER_SNOW_WORD_3
	DE	GLÜCKLICHES
	EN	HAPPY

PLUGIN_SCREENSAVER_SNOW_WORD_4
	de	NEUES JAHR!
	EN	NEW YEAR !

PLUGIN_SCREENSAVER_SNOW_SORRY
	DE	Sorry, Schnee funktioniert auf diesem Gerät nicht.
	EN	Sorry, Snow doesn\'t work with this player.
'};

##################################################
### Section 2. Your variables and code go here ###
##################################################

# button functions for browse directory
my @snowSettingsChoices = ('PLUGIN_SCREENSAVER_SNOW_ACTIVATE','PLUGIN_SCREENSAVER_SNOW_QUANTITY', 'PLUGIN_SCREENSAVER_SNOW_STYLE');

our %current;
our %menuParams = (
	'snow' => {
		'listRef' => \@snowSettingsChoices
		,'stringExternRef' => 1
		,'header' => 'PLUGIN_SCREENSAVER_SNOW_SETTINGS'
		,'stringHeader' => 1
		,'headerAddCount' => 1
		,'callback' => \&snowExitHandler
		,'overlayRef' => sub {return (undef,Slim::Display::Display::symbol('rightarrow'));}
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
		,'listRef' => [1,2,3,4,5,6]
		,'externRef' => [ 'PLUGIN_SCREENSAVER_SNOW_STYLE_1','PLUGIN_SCREENSAVER_SNOW_STYLE_2','PLUGIN_SCREENSAVER_SNOW_STYLE_3','PLUGIN_SCREENSAVER_SNOW_STYLE_4','PLUGIN_SCREENSAVER_SNOW_STYLE_5','PLUGIN_SCREENSAVER_SNOW_STYLE_6']
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
			$client->bumpRight();
		}
	} else {
		return;
	}
}

our %functions = (
	'right' => sub  {
		my ($client,$funct,$functarg) = @_;
		if (defined($client->param('useMode'))) {
			#in a submenu of settings, which is passing back a button press
			$client->bumpRight();
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
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# install prefs
	Slim::Utils::Prefs::clientSet($client,'snowStyle',6)
	    unless defined Slim::Utils::Prefs::clientGet($client,'snowStyle');
	Slim::Utils::Prefs::clientSet($client,'snowQuantity',1)
	    unless defined Slim::Utils::Prefs::clientGet($client,'snowQuantity');

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
sub screenSaver {
	Slim::Buttons::Common::addSaver('SCREENSAVER.snow', 
		getScreensaverSnowFunctions(),
		\&setScreensaverSnowMode, 
		\&leaveScreensaverSnowMode,
		'PLUGIN_SCREENSAVER_SNOW',
	);
}

our %wasDoubleSize;

our %screensaverSnowFunctions = (
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

our %snowStyle;
our %snowQuantity;
our %lastTime;
our %flakes;

sub setScreensaverSnowMode() {
	my $client = shift;
	$client->lines(\&screensaverSnowlines);
	$wasDoubleSize{$client} = $client->textSize;
	$client->textSize(0);
	# save time on later lookups - we know these can't change while we're active
	$snowStyle{$client} = Slim::Utils::Prefs::clientGet($client,'snowStyle') || 6;
	$snowQuantity{$client} = Slim::Utils::Prefs::clientGet($client,'snowQuantity') || 1;
}

sub leaveScreensaverSnowMode {
	my $client = shift;
	$client->textSize($wasDoubleSize{$client});
	$lastTime{$client} = Time::HiRes::time();
}

sub screensaverSnowlines {
	my $client = shift;
	my ($line1, $line2) = ('','');
	my $onlyInSpaces = 0;
	my $simple = 0;
	my $words = 0;
	my $style = $snowStyle{$client};

	if( $client && $client->isa( "Slim::Player::SqueezeboxG")) {
		$line1 = $client->string('PLUGIN_SCREENSAVER_SNOW');
		$line2 = $client->string('PLUGIN_SCREENSAVER_SNOW_SORRY');
		return ($line1, $line2);
	} 	 

	if($style == 5) {
		# automatic
		if (Slim::Player::Source::playmode($client) eq "pause") {
		$style = 4; # Just snow when paused
		} elsif (Slim::Player::Source::playmode($client) eq "stop") {
		$style = 4; # Just snow when stopped
		} else {
		$style = 1; # Now Playing when playing
		}
	}

	if($style == 6) {
		$style = 4; # Just snow
		$words = 2; # With words
	}

	if($style == 1 || $style == 2) {
		# Now Playing
		($line1, $line2) = $client->renderOverlay($client->currentSongLines());
		$onlyInSpaces = ($style == 1);
	} elsif($style == 3) {
		# Date/Time
		($line1, $line2) = $client->renderOverlay(&Slim::Buttons::Common::dateTime($client));
		$onlyInSpaces = 1;
	} else {
		# Just snow
		$simple = 1;
	}
	($line1, $line2) = letItSnow($client, $line1, $line2, $onlyInSpaces, $simple, $words);
	return ($line1, $line2);
}

Slim::Hardware::VFD::setCustomChar('snow01',
                                 ( 0b00000010,
                                   0b00000111,
                                   0b00000010,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('snow00',
                                 ( 0b00001000,
                                   0b00011100,
                                   0b00001000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('snow11',
                                 ( 0b00000000,
                                   0b00000000,
                                   0b00000010,
                                   0b00000111,
                                   0b00000010,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('snow10',
                                 ( 0b00000000,
                                   0b00000000,
                                   0b00001000,
                                   0b00011100,
                                   0b00001000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('snow21',
                                 ( 0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000010,
                                   0b00000111,
                                   0b00000010,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('snow20',
                                 ( 0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00000000,
                                   0b00001000,
                                   0b00011100,
                                   0b00001000,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('snow7',
                                 ( 0b00001000,
                                   0b00011100,
                                   0b00001000,
                                   0b00000000,
                                   0b00001000,
                                   0b00011100,
                                   0b00001000,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('snow8',
                                 ( 0b00000000,
                                   0b00000000,
                                   0b00001000,
                                   0b00011100,
                                   0b00001010,
                                   0b00000111,
                                   0b00000010,
                                   0b00000000 ));
Slim::Hardware::VFD::setCustomChar('snow9',
                                 ( 0b00001000,
                                   0b00011100,
                                   0b00001000,
                                   0b00000000,
                                   0b00000010,
                                   0b00000111,
                                   0b00000010,
                                   0b00000000 ));

sub tick {
	my $client = shift;
	Slim::Utils::Timers::killTimers($client, \&tick);
	$client->update();
}

sub insertChar {
    my $line = shift;
    my $sym = shift;
    my $col = shift;
    my $len = shift;
    return ($col > 0 ? Slim::Display::Display::subString($line, 0, $col) : '') . 
	$sym .
	($col < (40-$len) ? Slim::Display::Display::subString($line, $col+$len, 40 - $len - $col) : '');
}

sub drawFlake {
    my $bigrow = shift;
    my $bigcol = shift;
    my $onlyInSpaces = shift;
    my $lines = shift;

    my $row = int($bigrow / 3);
    my $col = int($bigcol / 2);
    my $sym = Slim::Display::Display::symbol('snow' . ($bigrow - $row * 3) . ($bigcol - $col * 2));
    
    if(! $onlyInSpaces
       ||
       Slim::Display::Display::subString($lines->[$row], $col, 1) eq ' ') {
	$lines->[$row] = insertChar($lines->[$row], $sym, $col, 1);
    }
}

our %flakeMap = (0 => ' ',
		1 => Slim::Display::Display::symbol('snow00'),
		2 => Slim::Display::Display::symbol('snow10'),
		4 => Slim::Display::Display::symbol('snow20'),
		8 => Slim::Display::Display::symbol('snow01'),
		16 => Slim::Display::Display::symbol('snow11'),
		32 => Slim::Display::Display::symbol('snow21'),
		5 => Slim::Display::Display::symbol('snow7'),
		34 => Slim::Display::Display::symbol('snow8'),
		33 => Slim::Display::Display::symbol('snow9'),
		);

our %letters = (A => [3, [2], [], [0,4], [0,2,4], [], [0,4] ],
	       B => [3, [0,2], [4], [0,2], [0], [4], [0,2] ],
	       C => [3, [2,4], [1], [], [1], [], [2,4] ],
	       D => [3, [0,2], [4], [0], [0,4], [], [0,2] ],
	       E => [3, [0,2,4], [], [0,2], [0], [], [0,2,4] ],
	       F => [3, [0,2,4], [], [0], [0,2], [], [0] ],
	       G => [3, [2,4], [1], [], [1,4], [], [2,4] ],
	       H => [3, [0,4], [], [0,2,4], [0,4], [], [0,4] ],
	       I => [1, [0], [], [0], [0], [], [0] ],
	       J => [3, [0,2,4], [], [2], [2], [0], [1,2] ],
	       K => [3, [0,4], [], [0,2], [0,3], [], [0,4] ],
	       L => [3, [0], [], [0], [0], [], [0,2,4] ],
	       M => [4, [0,6], [2,4], [0,3,6], [0,6], [], [0,6] ],
	       N => [3, [0,4], [], [0,2,4], [0,3,4], [], [0,4] ],
	       O => [3, [2], [], [0,4], [0,4], [], [2] ],
	       P => [3, [0,2], [], [0,4], [0,2], [], [0] ],
	       Q => [3, [2], [], [0,4], [0,4], [], [2,5] ],
	       R => [3, [0,2], [], [0,4], [0,2], [], [0,4] ],
	       S => [3, [2,4], [1], [2], [4], [], [1,3] ],
	       T => [3, [0,2,4], [], [2], [2], [], [2] ],
	       U => [3, [0,4], [], [0,4], [0,4], [], [1,3] ],
	       V => [4, [0,6], [], [1,5], [2,4], [], [3] ],
	       W => [3, [0,4], [], [0,2,4], [0,2,4], [], [1,3] ],
	       X => [3, [0,4], [], [1,3], [2,4], [], [0,5] ],
	       Y => [3, [0,4], [], [1,3], [2], [], [2] ],
	       Z => [3, [0,2,4], [], [3], [2], [], [0,2,4] ],
	       ' ' => [0, [], [], [], [], [], [] ],
	       '!' => [1, [0], [], [0], [], [], [0] ],
	       );

sub paintFlake {
    my $bigrow = shift;
    my $bigcol = shift;
    my $torender = shift;
    my $onlyIfCanRender = shift;
    my $onlyInSpaces = shift;
    my $lines = shift;

    my $row = int($bigrow / 3);
    my $col = int($bigcol / 2);
    my $bit = (1 << (($bigrow - $row * 3) + 3 * ($bigcol - $col * 2)));
    
    if(! $onlyInSpaces
       ||
       Slim::Display::Display::subString($lines->[$row], $col, 1) eq ' ') {
	if($torender->[$row][$col] != -1) {
	    return 0 if($onlyIfCanRender && !exists($flakeMap{($torender->[$row][$col]) | $bit}));
	    $torender->[$row][$col] |= $bit;
	} else {
	    $torender->[$row][$col] = $bit;
	}
	return 1;
    } 
    return 0;
}

sub renderFlakes {
    my $torender = shift;
    my $lines = shift;
    my $row;
    my $col;
    my @newlines = ('', '');;

    foreach $row (0,1) {
	foreach $col (0..39) {
	    my $bits = $torender->[$row][$col];
	    if($bits == -1) {
		$newlines[$row] .= Slim::Display::Display::subString($lines->[$row], $col, 1);
	    } elsif(exists $flakeMap{$bits}) {
		$newlines[$row] .= $flakeMap{$bits};
	    } else {
		print "No symbol for $bits\n";
		$newlines[$row] .= '*';
	    }
	}
    }
    return @newlines;
}

my $holdTime = 70;

sub paintWord {
    my $word = shift;
    my $state = shift;
    my $offsets = shift;
    my $torender = shift;
    my $lines = shift;
    my @text;
    my $letter;
    my $row;
    my $col;
	
    my $totallen = -1;
    map {$totallen += @{$letters{$_}}[0] + 1} (split //, $word);
    
    my $startcol = 2 * int((40 - $totallen) / 2);
    
    # Wipe out any falling snow under the letters
    foreach $row (0..1) {
	foreach $col (0..($totallen-1)) {
	    $torender->[$row][$startcol/2+$col] = 0;
	}
    }
    
    my $exiting = 0;
    if($state > $holdTime) {
	$state -= $holdTime;
	$exiting = 1;
    }

    my $paintedSomething = 0;

    foreach $letter (split //, $word) {
	my $charwidth = @{$letters{$letter}}[0];
	foreach $row (0..5) {
	    foreach $col (@{$letters{$letter}[$row+1]}) {
		my $outrow = 3 * $row - 15 + $state - $offsets->[int($col/2)];
		if(!$exiting) {
		    $outrow = $row if($outrow > $row); # stop at correct row
		} else {
		    $outrow = $row if($outrow < $row); # start at correct row
		}

		if($outrow >= 0 && $outrow < 6) {
		    paintFlake($outrow, $startcol + $col, $torender, 0, 0, $lines);
		    $paintedSomething = 1;
		}
	    }
	}
	$startcol += $charwidth * 2 + 2;
    }

    return $paintedSomething;
}

our %wordState;
our %word;
our %offsets;
our %wordIndex;

sub letItSnow {
	my $client = shift;
	my @lines = (shift, shift);
	my $onlyInSpaces = shift;
	my $simple = shift;
	my $showWords = shift;

	$lastTime{$client} = defined($lastTime{$client}) ? $lastTime{$client} : 0;
	my $animate = (Time::HiRes::time() - $lastTime{$client} > 0.25);
	if($animate) {
		$lastTime{$client} = Time::HiRes::time();
		my $flake;
		foreach $flake (@{$flakes{$client}}) {
			$flake->[0] ++;
			$flake->[1] += (int(rand(3)) - 1);
		}
		
		# cull flakes which have left the screen
		@{$flakes{$client}} = grep { $_->[0] < 6 && $_->[1] >= 0 && $_->[1] < 80} @{$flakes{$client}};
		
		my $i;
		foreach $i (0..5) {
			if(rand(100) < (5,10,30)[$snowQuantity{$client}]) {
				push @{$flakes{$client}}, [0, int rand(80)];
			}
		}
	}

	my $i;
	foreach $i (0,1) {
		if(!$simple) {
			if (index($lines[$i], Slim::Display::Display::symbol('center') ) == 0)  {
				$lines[$i] = substr($lines[$i], length(Slim::Display::Display::symbol('center')));
				s/\s*$//;
				my $centerspaces = int((40-Slim::Display::Display::lineLength($lines[$i]))/2);
				$lines[$i] = (" " x $centerspaces).$lines[$i];
			}
		}
		$lines[$i] = Slim::Display::Display::subString($lines[$i] . (' ' x 40), 0, 40);
	}

	my $torender = [[-1,-1], [-1,-1]];
	my $row;
	my $col;
	foreach $row (0..1) {
	    foreach $col (0..39) {
		$torender->[$row][$col] = -1;
	    }
	}

	foreach my $flake (@{$flakes{$client}}) {
	    if($showWords) {
		paintFlake(@{$flake}[0], @{$flake}[1], $torender, 1, $onlyInSpaces, \@lines);
	    } else {
		# Use older, but faster, code
		drawFlake(@{$flake}[0], @{$flake}[1], $onlyInSpaces, \@lines);
	    }
	}
	    
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 0.25, \&tick);

	if($showWords) {
	    if(!exists $wordState{$client}) {
		$wordState{$client} = -1; 
		$wordIndex{$client} = 0;
	    }
	    
	    if($wordState{$client} == -1) {
		# Not showing a word right now. Should we start next time?
		$word{$client} = $client->string('PLUGIN_SCREENSAVER_SNOW_WORD_' . $wordIndex{$client});
		$wordIndex{$client}++;
		$wordIndex{$client} = 0 if($wordIndex{$client} == $client->string('PLUGIN_SCREENSAVER_SNOW_NUMBER_OF_WORDS'));
		$wordState{$client} = 0;
		foreach $col (0..39) {
		    $offsets{$client}->[$col] = int(rand(24));
		}
	    } else {
		my $paintedSomething = paintWord($word{$client}, $wordState{$client}, $offsets{$client}, $torender, \@lines);
		$wordState{$client} ++ if($animate);
		
		if($wordState{$client} > $holdTime && !$paintedSomething) {
		    # finished with this word. Resume normal snowing
		    $wordState{$client} = -1;
		}
	    }

	    @lines = renderFlakes($torender, \@lines);
	}

	return @lines;
}

1;

__END__
