package Plugins::Shooter;

# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Display::Animation;
use Slim::Buttons::Home;
use Slim::Display::Display;
use Slim::Buttons::Common;
use Slim::Utils::Misc;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.6 $,10);

my @topchars = ("placeholder!", " ", " ",    "^", "v");
my @btmchars = ("placeholder!", "_", "^", "*", " ");
my $player = "<";

my $framerate = .1; # 10 FPS
my $maxobs = 8;

sub addMenu {
	my $menu = "GAMES";
	return $menu;
}

sub getDisplayName { 'Shooter' }

my %functions = (
	'play' => sub  {
		my $client = shift;
		if ($client->gplay) {
			my $mostrec = 0;
			my $mrpos = 0;
			for (my $i = 0; $i < $maxobs; $i++) {
				if ((defined $client->otype($i))&&($client->opos($i)>$mrpos)) {
					$mostrec = $i;
					$mrpos = $client->opos($i);
				}
			}
			if ($client->otype($mostrec) == 3) {
				$client->otype($mostrec, 2);
				$client->update();
			}
		}
	},
	'stop' => sub  {
		my $client = shift;
		$client->gplay(0);
	},
	'up' => sub  {
	        my $client = shift;
	        $client->cpos(1);
	        $client->update();
	},
	'down' => sub  {
	        my $client = shift;
	        $client->cpos(2);
	        $client->update();
	},
	'left' => sub  {
	        my $client = shift;
		    Slim::Buttons::Common::popMode($client);
	},
	'right' => sub {
			my $client = shift;
			$client->gplay(1);
	}
);

sub lines {
    my $client = shift;
    my $line1 = '';
    my $line2 = '';
    my $ok = 0;

    if ($client->gplay) {
        for (my $i = 0; $i < 39; $i++) {
            $ok = 0;
            for (my $j = 0; $j < $maxobs; $j++) {
                if ((defined $client->otype($j)) && ($client->opos($j) == $i)) {
                    $ok = 1;
                    $line1 .= $topchars[$client->otype($j)];
                    $line2 .= $btmchars[$client->otype($j)];
                }
            }
            $line1 .= ' ' unless $ok;
            $line2 .= ' ' unless $ok;
        }
        $line1 .= ($client->cpos == 1) ? $player : " ";
        $line2 .= ($client->cpos == 2) ? $player : " ";
    } else {
        $line1 = "Welcome to Shooter!";
        $line2 = "Press RIGHT to begin, PLAY to shoot.";
    }
    return ($line1, $line2);
}

sub setMode {
    my $client = shift;
    $client->lines(\&lines);
    $client->cpos(1);
    @{$client->otype} = (2, 4, 3,  4,  3);
    @{$client->opos} =  (1, 7, 13, 20, 26);
    $client->gplay(0);
    Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $framerate, \&g_advance, ($client, Time::HiRes::time()));
}

sub g_replace {
	my $client = shift;
	my $i = shift;


	$client->otype($i, int((rand 3) + 2));
	$client->opos($i, 0);
}

sub g_return {
	my $client = shift;
	$client->gplay(0);
	$client->update();
}

sub g_advance {
   my $client = shift;
   my $ot = shift;
   my $i;

   if ($client->gplay) {
      for ($i=0; $i < $maxobs; $i++) {
         if (defined $client->otype($i)) {
            $client->opos($i, $client->opos($i)+1);
            if ($client->opos($i) == 39) {
               g_return($client) if($client->otype($i)==2)&&($client->cpos==2);
               g_return($client) if($client->otype($i)==3);
               g_return($client) if($client->otype($i)==4)&&($client->cpos==1);
               g_replace $client, $i;
            }
         }
      }
      $client->update();
   }
   my $nextrun = Time::HiRes::time() + $framerate;

   if (Slim::Buttons::Common::mode($client) eq 'PLUGIN.Shooter') {
      Slim::Utils::Timers::setTimer($client, $nextrun, \&g_advance, ($nextrun));
   }
}

sub getFunctions {
    \%functions;
}


1;
