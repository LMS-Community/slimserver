package Slim::Plugin::Favorites::Plugin;

# $Id$

# A Favorites implementation which stores favorites as opml files and allows
# the favorites list to be edited from the web interface

# Includes code from the MyPicks plugin by Adrian Smith and Bryan Alton

# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Buttons::Common;
use Slim::Web::XMLBrowser;
use Slim::Utils::Favorites;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use File::Spec::Functions qw(:ALL);

use Slim::Plugin::Favorites::Opml;
use Slim::Plugin::Favorites::OpmlFavorites;

my $log = logger('favorites');

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(@_);

	# register ourselves as the opml editor for xmlbrowser
	Slim::Web::XMLBrowser::registerEditor( qr/^file:\/\/.*\.opml$/, 'plugins/Favorites/edit.html' );

	# register opml based favorites handler
	Slim::Utils::Favorites::registerFavoritesClassName('Slim::Plugin::Favorites::OpmlFavorites');

	# register handler for playing favorites by remote hot button
	Slim::Buttons::Common::setFunction('playFavorite', \&playFavorite);
}

sub setMode {
	my $class = shift;
    my $client = shift;
    my $method = shift;

    if ( $method eq 'pop' ) {
        Slim::Buttons::Common::popMode($client);
        return;
    }

	my $file = Slim::Plugin::Favorites::OpmlFavorites->new->filename;

	if (-r $file) {

		# use INPUT.Choice to display the list of feeds
		my %params = (
			header   => 'PLUGIN_FAVORITES_LOADING',
			modeName => 'Favorites.Browser',
			url      => Slim::Utils::Misc::fileURLFromPath($file),
			title    => $client->string('FAVORITES'),
		   );

		Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

		# we'll handle the push in a callback
		$client->modeParam('handledTransition',1)

	} else {

		$client->lines(\&errorLines);
	}
}

sub errorLines {
	return { 'line' => [string('FAVORITES'), string('PLUGIN_FAVORITES_NOFILE')] };
}

sub playFavorite {
	my $client = shift;
	my $button = shift;
	my $digit  = shift;

	if ($digit == 0) {
		$digit = 10;
	}

	my ($url, $title) = Slim::Plugin::Favorites::OpmlFavorites->new->findByClientAndId($client, $digit);

	if (!$url) {

		$client->showBriefly({
			 'line' => [ sprintf($client->string('FAVORITES_NOT_DEFINED'), $digit) ],
		});

		return;

	} else {

		$log->info("Playing favorite number $digit $title $url");

		Slim::Music::Info::setTitle($url, $title);

		$client->execute(['playlist', 'play', $url]);
	}
}

sub webPages {
	my $class = shift;

	Slim::Web::Pages->addPageLinks('browse', { 'FAVORITES' => 'plugins/Favorites/index.html' });
#	Slim::Web::Pages->addPageLinks('plugins', { 'PLUGIN_FAVORITES_EDITOR' => 'plugins/Favorites/edit.html' });

	Slim::Web::HTTP::addPageFunction('plugins/Favorites/index.html', \&indexHandler);
	Slim::Web::HTTP::addPageFunction('plugins/Favorites/edit.html', \&editHandler);
}

sub indexHandler {
	my $file = Slim::Plugin::Favorites::OpmlFavorites->new->filename;

	if (-r $file) {

		Slim::Web::XMLBrowser->handleWebIndex( {
			feed   => Slim::Utils::Misc::fileURLFromPath($file),
			title  => 'FAVORITES',
			args   => \@_
		} );
	}
}

my $opml;
my $level = 0;
my $currentLevel;
my @prevLevels;
my $deleted;
my $filename;
my $changed;

sub editHandler {
	my ($client, $params) = @_;

	my $edit;     # index of entry to edit if set
	my $errorMsg; # error message to display at top of page

	# Debug:
	#for my $key (keys %$params) {
	#	print "Key: $key, Val: ".$params->{$key}."\n";
	#}

	# action any params set
	if ($params->{'title'}) {
		$opml->title( $params->{'title'} );
		$changed = 1;
	}

	if ($params->{'save'}) {
		$opml->save;
		$changed = undef;
	}

	if ($params->{'url'}) {

		$opml = Slim::Plugin::Favorites::OpmlFavorites->new;

		if ("file://" . $opml->filename ne $params->{'url'}) {
			# if url is not for favorite file use opml direct
			$opml = Slim::Plugin::Favorites::Opml->new( $params->{'url'} );
		}

		$level = 0;
		$currentLevel = $opml->toplevel;
		@prevLevels = ();
		$deleted = undef;
		$changed = undef;

		if ($params->{'index'}) {
			for my $i (split(/\./, $params->{'index'})) {
				if (defined @$currentLevel[$i]) {
					$prevLevels[ $level++ ] = {
						'ref'   => $currentLevel,
						'title' => @$currentLevel[$i]->{'text'},
					};
					$currentLevel = @$currentLevel[$i]->{'outline'};
				}
			}
		}
	}

	if (my $action = $params->{'action'}) {
		if ($action eq 'descend') {
			$prevLevels[ $level++ ] = {
				'ref'   => $currentLevel,
				'title' => @$currentLevel[$params->{'entry'}]->{'text'},
			};
			$currentLevel = @$currentLevel[$params->{'entry'}]->{'outline'};
		}

		if ($action eq 'ascend') {
			my $pop = defined ($params->{'levels'}) ? $params->{'levels'} : 1;
			while ($pop) {
				$currentLevel = $prevLevels[ --$level ]->{'ref'} if $level > 0;
				--$pop;
			}
		}

		if ($action eq 'edit') {
			$edit = $params->{'entry'};
		}

		if ($action eq 'edittitle') {
			$params->{'edittitle'} = 1;
		}

		if ($action eq 'delete') {
			$deleted = splice @$currentLevel, $params->{'entry'}, 1;
			$changed = 1;
		}

		if ($action eq 'forgetdelete') {
			$deleted = undef;
		}

		if ($action eq 'insert' && $deleted) {
			push @$currentLevel, $deleted;
			$deleted = undef;
			$changed = 1;
		}

		if ($action eq 'movedown') {
			my $entry = splice @$currentLevel, $params->{'entry'}, 1;
			splice @$currentLevel, $params->{'entry'} + 1, 0, $entry;
			$changed = 1;
		}

		if ($action eq 'moveup' && $params->{'entry'} > 0) {
			my $entry = splice @$currentLevel, $params->{'entry'}, 1;
			splice @$currentLevel, $params->{'entry'} - 1, 0, $entry;
			$changed = 1;
		}

		if ($action eq 'newentry') {
			$params->{'newentry'} = 1;
		}

		if ($action =~ /play|add/ && $client) {
			my $stream = @$currentLevel[$params->{'entry'}]->{'URL'};
			my $title  = @$currentLevel[$params->{'entry'}]->{'text'};
			Slim::Music::Info::setTitle($stream, $title);
			$client->execute(['playlist', $action, $stream]);
		}
	}

	if ($params->{'editset'} && defined $params->{'entry'}) {
		my $entry = @$currentLevel[$params->{'entry'}];
		$entry->{'text'} = $params->{'entrytitle'};
		$entry->{'URL'} = $params->{'entryurl'} if defined($params->{'entryurl'});
		$changed = 1;
	}

	if ($params->{'newmenu'}) {
		push @$currentLevel, {
			'text'   => $params->{'menutitle'},
			'outline'=> [],
		};
		$changed = 1;
	}

	if ($params->{'newstream'}) {
		push @$currentLevel,{
			'text' => $params->{'streamtitle'},
			'URL'  => $params->{'streamurl'},
			'type' => 'audio',
		};
		$changed = 1;
	}

	# set params for page build
	$params->{'title'} = $opml->title;
	$params->{'previous'} = ($level > 0);
	$params->{'deleted'} = defined($deleted) ? $deleted->{'text'} : undef;
	$params->{'changed' } = $changed;

	if ($opml->error) {
		$params->{'errormsg'} = string('PLUGIN_FAVORITES_' . $opml->error . " " . $opml->filename);
	}

	my @entries;
	my $index = 0;

	foreach my $opmlEntry (@$currentLevel) {
		push @entries, {
			'title'   => $opmlEntry->{'text'} || '',
			'url'     => $opmlEntry->{'URL'} || '',
			'audio'   => (defined $opmlEntry->{'type'} && $opmlEntry->{'type'} eq 'audio'),
			'outline' => $opmlEntry->{'outline'},
			'edit'    => (defined $edit && $edit == $index),
			'index'   => $index++,
		};
	}

	$params->{'entries'} = \@entries;

	push @{$params->{'pwd_list'}}, {
		'title' => $opml->title || string('PLUGIN_FAVORITES_EDITOR'),
		'href'  => 'href="edit.html?action=ascend&levels=' . $level . '"',
	};

	for (my $i = 1; $i <= $level; $i++) {
		push @{$params->{'pwd_list'}}, {
			'title' => $prevLevels[ $i - 1 ]->{'title'},
			'href'  => 'href="edit.html?action=ascend&levels=' . ($level - $i) . '"',
		};
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/Favorites/edit.html', $params);
}

1;
