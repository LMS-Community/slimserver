package Slim::Buttons::Search;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Utils::Strings qw (string);

Slim::Buttons::Common::addMode('search',getFunctions(),\&setMode);

# button functions for search directory
my @defaultSearchChoices = ('ARTISTS','ALBUMS','SONGS');
my $rightarrow = Slim::Display::Display::symbol('rightarrow');

my %current;
my %context;

my %menuParams = (
	'search' => {
		'listRef' => \@defaultSearchChoices
		,'stringExternRef' => 1
		,'header' => 'SEARCH'
		,'stringHeader' => 1
		,'headerAddCount' => 1
		,'callback' => \&searchExitHandler
		,'overlayRef' => sub {return (undef,Slim::Display::Display::symbol('rightarrow'));}
		,'overlayRefArgs' => ''
	}
	,'search/ARTISTS' => {
		'useMode' => 'INPUT.Text'
		,'header' => 'SEARCHFOR_ARTISTS'
		,'stringHeader' => 1
		,'cursorPos' => 0
		,'charsRef' => 'BOTH'
		,'callback' => \&searchHandler
	}
	,'search/ALBUMS' => {
		'useMode' => 'INPUT.Text'
		,'header' => 'SEARCHFOR_ALBUMS'
		,'stringHeader' => 1
		,'cursorPos' => 0
		,'charsRef' => 'BOTH'
		,'callback' => \&searchHandler
	}
	,'search/SONGS' => {
		'useMode' => 'INPUT.Text'
		,'header' => 'SEARCHFOR_SONGS'
		,'stringHeader' => 1
		,'cursorPos' => 0
		,'charsRef' => 'BOTH'
		,'callback' => \&searchHandler
	}
);

sub searchExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} elsif ($exittype eq 'RIGHT') {
		my %nextParams = searchFor($client,$current{$client});
		Slim::Buttons::Common::pushModeLeft(
			$client
			,$nextParams{'useMode'}
			,\%nextParams
		);
	} else {
		return;
	}
}

sub searchFor {
	my $client = shift;
	my $search = shift;
	my $nextmenu = 'search'.'/'.$search;
	$context{$client} = ('A');
	my %nextParams = %{$menuParams{$nextmenu}};
	$nextParams{'valueRef'} = \$context{$client};
	$client->searchFor($search);
	return %nextParams;
}

sub searchHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'BACKSPACE') {
		Slim::Buttons::Common::popModeRight($client);
	} else {
		$context{$client} =~ s/$rightarrow//;
		startSearch($client);
	}
}


sub startSearch {
	my $client = shift;
	my $mode = shift;
	my @oldlines = Slim::Display::Display::curLines($client);

	my $term = searchTerm($client);
	$client->showBriefly(string('SEARCHING'));
	if ($client->searchFor eq 'ARTISTS') {
		Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist' => $term } );
	} elsif ($client->searchFor eq 'ALBUMS') {
		Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist' => '*', 'album' =>$term });
	} else {
		Slim::Buttons::Common::pushMode($client, 'browseid3', {'genre'=>'*', 'artist' => '*', 'album' => '*', 'song' => $term } );
	}
	$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
}

sub searchTerm {
	my $client = shift;

	# do the search!
	@{$client->searchTerm} = split(//,$context{$client});
	my $term = "*";
	foreach my $a (@{$client->searchTerm}) {
		if (defined($a) && ($a ne $rightarrow)) {
			$term .= $a;
		}
	}
	$term .= "*";
	return $term;
}

my %functions = (
	'right' => sub  {
		my ($client,$funct,$functarg) = @_;
		if (defined(Slim::Buttons::Common::param($client,'useMode'))) {
			#in a submenu of settings, which is passing back a button press
			$client->bumpRight();
		} else {
			#handle passback of button presses
			settingsExitHandler($client,'RIGHT');
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
	$current{$client} = $defaultSearchChoices[0] unless exists($current{$client});
	my %params = %{$menuParams{'search'}};
	$params{'valueRef'} = \$current{$client};
	
	my @searchChoices = @defaultSearchChoices;
	
	$params{'listRef'} = \@searchChoices;
	
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
	$client->update();
}

1;

__END__
