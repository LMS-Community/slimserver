package Slim::Buttons::Search;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Display::Display;

# button functions for search directory
my @defaultSearchChoices = qw(ARTISTS ALBUMS SONGS);
my $rightarrow = Slim::Display::Display::symbol('rightarrow');

my %current;
my %context;

my %menuParams = (
	'SEARCH' => {
		'listRef' => \@defaultSearchChoices
		,'stringExternRef' => 1
		,'header' => 'SEARCH'
		,'stringHeader' => 1
		,'headerAddCount' => 1
		,'callback' => \&searchExitHandler
		,'overlayRef' => sub {return (undef,Slim::Display::Display::symbol('rightarrow'));}
		,'overlayRefArgs' => ''
		,'submenus' => {
				'ARTISTS' => {
				'useMode' => 'INPUT.Text'
				,'header' => 'SEARCHFOR_ARTISTS'
				,'stringHeader' => 1
				,'cursorPos' => 0
				,'charsRef' => 'UPPER'
				,'numberLetterRef' => 'UPPER'
				,'callback' => \&searchHandler
				}
				,'ALBUMS' => {
					'useMode' => 'INPUT.Text'
					,'header' => 'SEARCHFOR_ALBUMS'
					,'stringHeader' => 1
					,'cursorPos' => 0
					,'charsRef' => 'UPPER'
					,'numberLetterRef' => 'UPPER'
					,'callback' => \&searchHandler
				}
				,'SONGS' => {
					'useMode' => 'INPUT.Text'
					,'header' => 'SEARCHFOR_SONGS'
					,'stringHeader' => 1
					,'cursorPos' => 0
					,'charsRef' => 'UPPER'
					,'numberLetterRef' => 'UPPER'
					,'callback' => \&searchHandler
				}
		}
	}

);

sub searchExitHandler {
	my ($client,$exittype) = @_;
	
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} elsif ($exittype eq 'RIGHT') {
		my $current = Slim::Buttons::Common::param($client,'valueRef');
		my %nextParams = searchFor($client,$$current);
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
	
	$context{$client} = ('A');
	my %nextParams = %{$menuParams{'SEARCH'}{'submenus'}{$search}};
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
	$client->showBriefly($client->string('SEARCHING'));

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

sub init {
	my %subs = (
		'SEARCH_FOR_ARTISTS' => sub {
			return Slim::Buttons::Search::searchFor(shift, 'ARTISTS');
		}
		,'SEARCH_FOR_ALBUMS' => sub {
			return Slim::Buttons::Search::searchFor(shift, 'ALBUMS');
		}
		,'SEARCH_FOR_SONGS' => sub {
			return Slim::Buttons::Search::searchFor(shift, 'SONGS');
		}
	);
	foreach my $name (sort keys %menuParams) {
		Slim::Buttons::Home::addMenuOption($name,$menuParams{$name});
	}	
	foreach my $name (sort keys %subs) {
		Slim::Buttons::Home::addMenuOption($name,$subs{$name});
	}

}

1;

__END__
