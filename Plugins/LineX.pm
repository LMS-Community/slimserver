package Plugins::LineX;

# LineX.pm
# by Felix Mueller, June 2004
# Based on Phil Barrett's Snow.pm and the new screensaver
#  framework by Kevin Deane-Freeman

# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Only works on Squeezebox with Graphics display

# History:
#
# 03/02/05 - Check for display size and make clients independent
# 07/10/04 - Check for Graphics display
#          - Added rectangle drawing function
# 06/02/04 - Initial version


use strict;

###########################################
### Section 1. Change these as required ###
###########################################

use Slim::Control::Command;
use Slim::Utils::Timers;
use Slim::Hardware::VFD;
use File::Spec::Functions qw(:ALL);
use Slim::Utils::Misc;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.3 $,10);

# ----------------------------------------------------------------------------
sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_LINEX';
}

# ----------------------------------------------------------------------------
sub strings { return '
PLUGIN_SCREENSAVER_LINEX
	DE	LineX Bildschirmschoner
	EN	LineX Screensaver
	ES	Salvapantallas LineX

PLUGIN_SCREENSAVER_LINEX_SETTINGS
	DE	LineX Bildschirmschoner Einstellungen
	EN	LineX Screensaver settings
	ES	Configuración de Salvapantallas LineX

PLUGIN_SCREENSAVER_LINEX_ACTIVATE
	DE	Diesen Bildschirmschoner wählen
	EN	Select Current Screensaver
	ES	Elegir Salvapantallas Actual

PLUGIN_SCREENSAVER_LINEX_ACTIVATE_TITLE
	DE	Aktuellen Bildschirmschoner
	EN	Current Screensaver
	ES	Salvapantallas Actual

PLUGIN_SCREENSAVER_LINEX_ACTIVATED
	DE	LineX als Bildschirmschoner verwenden
	EN	Use LineX as current screensaver
	ES	Utilizar LineX com salvapantallas actual

PLUGIN_SCREENSAVER_LINEX_DEFAULT
	DE	Standard Bildschirmschoner verwenden (nicht LineX)
	EN	Use default screensaver (not LineX)
	ES	Utilizar salvapantallas por defecto (No LineX)

PLUGIN_SCREENSAVER_LINEX_NUMBER
	DE	Anzahl Objekte wählen
	EN	Select number of objects
	ES	Elegir número de objetos

PLUGIN_SCREENSAVER_LINEX_NUMBER_TITLE
	DE	LineX Bildschirmschoner: Anzahl wählen
	EN	LineX Screensaver: Select number
	ES	Salvapantallas LineX: elegir número

PLUGIN_SCREENSAVER_LINEX_OBJECT
	DE	Objekttyp wählen
	EN	Select type of object
	ES	Elegir tipo de objeto

PLUGIN_SCREENSAVER_LINEX_OBJECT_TITLE
	DE	LineX Bildschirmschoner: Objekttyp wählen
	EN	LineX Screensaver: Select type
	ES	Salvapantallas LineX: elegir tipo

PLUGIN_SCREENSAVER_LINEX_OBJECT_LINE
	DE	Linie
	EN	Line
	ES	Línea

PLUGIN_SCREENSAVER_LINEX_OBJECT_RECTANGLE
	DE	Rechteck
	EN	Rectangle
	ES	Rectángulo

PLUGIN_SCREENSAVER_LINEX_OBJECT_RANDOM
	DE	Zufällig
	EN	Random
	ES	Al azar

PLUGIN_SCREENSAVER_LINEX_NEEDS_GRAPHICS_DISPLAY
	DE	Benötigt graphisches Display
	EN	Needs graphics display
	ES	Hace falta un display gráfico

'};

##################################################
### Section 2. Your variables and code go here ###
##################################################

# button functions for browse directory
my @linexSettingsChoices = ('PLUGIN_SCREENSAVER_LINEX_ACTIVATE','PLUGIN_SCREENSAVER_LINEX_OBJECT','PLUGIN_SCREENSAVER_LINEX_NUMBER');

our %current;
our %menuParams = (
  'linex' => {
    'listRef' => \@linexSettingsChoices
    ,'stringExternRef' => 1
    ,'header' => 'PLUGIN_SCREENSAVER_LINEX_SETTINGS'
    ,'stringHeader' => 1
    ,'headerAddCount' => 1
    ,'callback' => \&linexExitHandler
    ,'overlayRef' => sub {return (undef,Slim::Display::Display::symbol('rightarrow'));}
    ,'overlayRefArgs' => ''
  }
  ,catdir('linex','PLUGIN_SCREENSAVER_LINEX_ACTIVATE') => {
    'useMode' => 'INPUT.List'
    ,'listRef' => [0,1]
    ,'externRef' => ['PLUGIN_SCREENSAVER_LINEX_DEFAULT', 'PLUGIN_SCREENSAVER_LINEX_ACTIVATED']
    ,'stringExternRef' => 1
    ,'header' => 'PLUGIN_SCREENSAVER_LINEX_ACTIVATE_TITLE'
    ,'stringHeader' => 1
    ,'onChange' => sub { Slim::Utils::Prefs::clientSet($_[0],'screensaver',$_[1]?'SCREENSAVER.linex':'screensaver'); }
    ,'onChangeArgs' => 'CV'
    ,'initialValue' => sub { (Slim::Utils::Prefs::clientGet($_[0],'screensaver') eq 'SCREENSAVER.linex' ? 1 : 0); }
  }
  ,catdir('linex','PLUGIN_SCREENSAVER_LINEX_OBJECT') => {
    'useMode' => 'INPUT.List'
    ,'listRef' => [0,1,2]
    ,'externRef' => ['PLUGIN_SCREENSAVER_LINEX_OBJECT_LINE','PLUGIN_SCREENSAVER_LINEX_OBJECT_RECTANGLE','PLUGIN_SCREENSAVER_LINEX_OBJECT_RANDOM']
    ,'stringExternRef' => 1
    ,'header' => 'PLUGIN_SCREENSAVER_LINEX_OBJECT_TITLE'
    ,'stringHeader' => 1
    ,'onChange' => sub { Slim::Utils::Prefs::clientSet($_[0],'linexObject',$_[1]); }
    ,'onChangeArgs' => 'CV'
    ,'initialValue' => sub { Slim::Utils::Prefs::clientGet($_[0],'linexObject'); }
  }
  ,catdir('linex','PLUGIN_SCREENSAVER_LINEX_NUMBER') => {
    'useMode' => 'INPUT.List'
    ,'listRef' => [0,1,2,3,4,5,6]
    ,'externRef' => ['3','4','5','6','7','8','9']
    ,'stringExternRef' => 1
    ,'header' => 'PLUGIN_SCREENSAVER_LINEX_NUMBER_TITLE'
    ,'stringHeader' => 1
    ,'onChange' => sub { Slim::Utils::Prefs::clientSet($_[0],'linexNumber',$_[1]); }
    ,'onChangeArgs' => 'CV'
    ,'initialValue' => sub { Slim::Utils::Prefs::clientGet($_[0],'linexNumber'); }
  }
);

# ----------------------------------------------------------------------------
sub linexExitHandler {
  my ( $client,$exittype) = @_;
  $exittype = uc( $exittype);
  if( $exittype eq 'LEFT') {
    Slim::Buttons::Common::popModeRight($client);
  } elsif ( $exittype eq 'RIGHT') {
    my $nextmenu = catdir( 'linex', $current{$client});
    if( exists( $menuParams{$nextmenu})) {
      my %nextParams = %{$menuParams{$nextmenu}};
      if( $nextParams{'useMode'} eq 'INPUT.List' && exists( $nextParams{'initialValue'})) {
      #set up valueRef for current pref
      my $value;
        if (ref($nextParams{'initialValue'}) eq 'CODE') {
          $value = $nextParams{'initialValue'}->($client);
        } else {
          $value = Slim::Utils::Prefs::clientGet($client,$nextParams{'initialValue'});
        }
        $nextParams{'valueRef'} = \$value;
      }
      Slim::Buttons::Common::pushModeLeft($client, $nextParams{'useMode'}, \%nextParams);
    } else {
      $client->bumpRight();
    }
  } else {
    return;
  }
}

# ----------------------------------------------------------------------------
our %functions = (
  'right' => sub  {
    my ( $client, $funct, $functarg) = @_;
    if( defined( $client->param('useMode'))) {
      #in a submenu of settings, which is passing back a button press
      $client->bumpRight();
    } else {
      #handle passback of button presses
      linexExitHandler( $client, 'RIGHT');
    }
  }
);

# ----------------------------------------------------------------------------
sub getFunctions {
  return \%functions;
}

# ----------------------------------------------------------------------------
sub setMode {
  my $client = shift;
  my $method = shift;
  if( $method eq 'pop') {
    Slim::Buttons::Common::popModeRight( $client);
    return;
  }

  # install prefs
  my $linexObject = Slim::Utils::Prefs::clientGet( $client, 'linexObject') || 0;
  Slim::Utils::Prefs::clientSet( $client, 'linexObject', $linexObject);

  my $linexNumber = Slim::Utils::Prefs::clientGet( $client, 'linexNumber') || 0;
  Slim::Utils::Prefs::clientSet( $client, 'linexNumber', $linexNumber);

  $current{$client} = $linexSettingsChoices[0] unless exists( $current{$client});
  my %params = %{$menuParams{'linex'}};
  $params{'valueRef'} = \$current{$client};
  Slim::Buttons::Common::pushMode( $client, 'INPUT.List', \%params);
  $client->update();
}

###################################################################
### Section 3. Your variables for your screensaver mode go here ###
###################################################################

# ----------------------------------------------------------------------------
# First, Register the screensaver mode here.  Must make the call to addStrings in order to have plugin
# localization available at this point.
sub screenSaver {
	Slim::Buttons::Common::addSaver('SCREENSAVER.linex',
		getScreensaverLineXFunctions(),
		\&setScreensaverLineXMode,
		\&leaveScreensaverLineXMode,
		'PLUGIN_SCREENSAVER_LINEX',
	);
}

# ----------------------------------------------------------------------------
our %screensaverLineXFunctions = (
  'done' => sub  {
    my ( $client, $funct, $functarg) = @_;
    Slim::Buttons::Common::popMode( $client);
    $client->update();
    #pass along ir code to new mode if requested
    if( defined $functarg && $functarg eq 'passback') {
	Slim::Hardware::IR::resendButton($client);
    }
  }
);

# ----------------------------------------------------------------------------
sub getScreensaverLineXFunctions {
  return \%screensaverLineXFunctions;
}

my %linexObject;
my %linexNumber;
# Display size (bottom left is 0,0 / top right is $xmax-1,$ymax-1)
my %xmax;
my %ymax;
my %lastX;
my %lastY;
my %hashDisp;
my %step;
my %mode;
my %lastTime;

# ----------------------------------------------------------------------------
sub setScreensaverLineXMode() {
  my $client = shift;

  $client->lines( \&screensaverLineXlines);

  # save time on later lookups - we know these can't change while we're active
  $linexObject{$client} = Slim::Utils::Prefs::clientGet( $client, 'linexObject') || 0;
  $linexNumber{$client} = Slim::Utils::Prefs::clientGet( $client, 'linexNumber') || 0;
  
  # Get display size from player
  if( $client && $client->isa( "Slim::Player::SqueezeboxG")) {
    $xmax{$client} = $client->displayWidth();
    $ymax{$client} = $client->bytesPerColumn() * 8;
  } else {
    $xmax{$client} = 0;
    $ymax{$client} = 0;
  }
    
  clearDisp( $client);
  $step{$client} = 0;
  $mode{$client} = 0;
  $lastX{$client} = 0;
  $lastY{$client} = 0;
  $lastTime{$client} = Time::HiRes::time();
}

# ----------------------------------------------------------------------------
sub leaveScreensaverLineXMode {
  my $client = shift;
}

# ----------------------------------------------------------------------------
sub screensaverLineXlines {
  my $client = shift;
  my $line1 = Slim::Display::Display::symbol("framebuf");
  my $line2;

  if( $client && $client->isa( "Slim::Player::SqueezeboxG")) {
    if( Time::HiRes::time() - $lastTime{$client} > 0.4) {
      $lastTime{$client} = Time::HiRes::time();
      $step{$client}++;
      if( $step{$client} > ( $linexNumber{$client} + 2)) {
        $step{$client} = 0;
        clearDisp( $client);
        if( $linexObject{$client} == 0) {
          $mode{$client} = 0;
        } elsif( $linexObject{$client} == 1) {
          $mode{$client} = 1;
        } else {
          $mode{$client} = int( rand( 100)) % 2;
        }
      }
      if( $mode{$client} == 0) {
        # Random lines
        randomLine( $client);
      } else {
        # Random rectangles
        randomRectangle( $client);
      }
    }
    # Prepare line1
    for( my $x = 0; $x < $xmax{$client}; $x++) {
      my $byte = 0;
      for( my $y = $ymax{$client} / 8; $y > 0; $y--) {
        $byte = $hashDisp{$client}[$x][$y*8-1] * 0x080;
        $byte += $hashDisp{$client}[$x][$y*8-2] * 0x040;
        $byte += $hashDisp{$client}[$x][$y*8-3] * 0x020;
        $byte += $hashDisp{$client}[$x][$y*8-4] * 0x010;
        $byte += $hashDisp{$client}[$x][$y*8-5] * 0x08;
        $byte += $hashDisp{$client}[$x][$y*8-6] * 0x04;
        $byte += $hashDisp{$client}[$x][$y*8-7] * 0x02;
        $byte += $hashDisp{$client}[$x][$y*8-8] * 0x01;
        $line1 .= pack( "C", $byte);
      }
    }
    $line1 .= Slim::Display::Display::symbol("/framebuf");
    Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 0.2, \&tick);
  } else {
    $line1 = $client->string('PLUGIN_SCREENSAVER_LINEX');
    $line2 = $client->string('PLUGIN_SCREENSAVER_LINEX_NEEDS_GRAPHICS_DISPLAY');
  }

  return( $line1, $line2);
}

# ----------------------------------------------------------------------------
sub clearDisp {
  my $client = shift;
  for( my $xi = 0; $xi < $xmax{$client}; $xi++) {
    for( my $yi = 0; $yi < $ymax{$client}; $yi++) {
      $hashDisp{$client}[$xi][$yi] = 0;
    }
  }
}

# ----------------------------------------------------------------------------
sub tick {
  my $client = shift;
  Slim::Utils::Timers::killTimers( $client, \&tick);
  $client->update();
}

# ----------------------------------------------------------------------------
sub randomRectangle {
  my $client = shift;
  drawRectangle( $client, int( rand( $xmax{$client}-1)), int( rand( $ymax{$client}-1)), int( rand( $xmax{$client}-1)), int( rand( $ymax{$client}-1)), 1);
}

# ----------------------------------------------------------------------------
sub randomLine {
  my $client = shift;
  my $newX = int( rand( $xmax{$client}-1));
  my $newY = int( rand( $ymax{$client}-1));
  drawLine( $client, $lastX{$client}, $lastY{$client}, $newX, $newY, 1);
  $lastX{$client} = $newX;
  $lastY{$client} = $newY;
}

# ----------------------------------------------------------------------------
sub drawRectangle {
  my $client = shift;
  my $x1 = shift;
  my $y1 = shift;
  my $x2 = shift;
  my $y2 = shift;
  my $color = shift; # currently 1 or O

  drawLine( $client, $x1, $y1, $x2, $y1, $color);
  drawLine( $client, $x2, $y1, $x2, $y2, $color);
  drawLine( $client, $x1, $y2, $x2, $y2, $color);
  drawLine( $client, $x1, $y1, $x1, $y2, $color);
}

# ----------------------------------------------------------------------------
# Every line can be described as: y = ax + b
# There is one exception: vertical lines
sub drawLine {
  my $client = shift;
  my $x1 = shift;
  my $y1 = shift;
  my $x2 = shift;
  my $y2 = shift;
  my $color = shift; # currently 1 or O

  my $dx = $x2 - $x1;
  my $dy = $y2 - $y1;

  # Check for vertical line
  if( abs( $dx) > 0) {
    if( abs( $dx) >= abs( $dy)) {
      if( $x1 > $x2) {
        my $s = $x1;
        $x1 = $x2;
        $x2 = $s;
        $s = $y1;
        $y1 = $y2;
        $y2 = $s;
      }
      my $a = $dy / $dx;
      my $b = $y1 - $a * $x1;
      my $x = $x1;
      while( $x <= $x2) {
        my $y = $a * $x + $b;
        $y = sprintf( "%.0f", $y);
        $hashDisp{$client}[$x][$y] = $color;
        $x++;
      }
    } else {
      if( $y1 > $y2) {
        my $s = $x1;
        $x1 = $x2;
        $x2 = $s;
        $s = $y1;
        $y1 = $y2;
        $y2 = $s;
      }
      my $a = $dy / $dx;
      my $b = $y1 - $a * $x1;
      my $y = $y1;
      while( $y <= $y2) {
        my $x = ( $y - $b) / $a;
        $x = sprintf( "%.0f", $x);
        $hashDisp{$client}[$x][$y] = $color;
        $y++;
      }
    }
  # Special case for vertical lines
  } else {
    if( $y1 > $y2) {
      my $s = $x1;
      $x1 = $x2;
      $x2 = $s;
      $s = $y1;
      $y1 = $y2;
      $y2 = $s;
    }
    my $y = $y1;
    while( $y <= $y2) {
      my $x = $x1;
      $hashDisp{$client}[$x][$y] = $color;
      $y++;
    }
  }
}


1;

__END__
