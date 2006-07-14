package Slim::Buttons::Search;

# $Id$

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

our %current    = ();
our %context    = ();
our %menuParams = ();

sub init {
	my %subs = (

		'SEARCH_FOR_ARTISTS' => sub {
			return Slim::Buttons::Search::searchFor(shift, 'ARTISTS');
		},

		'SEARCH_FOR_ALBUMS' => sub {
			return Slim::Buttons::Search::searchFor(shift, 'ALBUMS');
		},

		'SEARCH_FOR_SONGS' => sub {
			return Slim::Buttons::Search::searchFor(shift, 'SONGS');
		}
	);

	#
	%menuParams = (
		'SEARCH' => {
			'listRef' => \@defaultSearchChoices,
			'stringExternRef' => 1,
			'header' => 'SEARCH',
			'stringHeader' => 1,
			'headerAddCount' => 1,
			'callback' => \&searchExitHandler,
			'overlayRef' => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
			'overlayRefArgs' => '',
			'submenus' => {

				'ARTISTS' => {
					'useMode' => 'INPUT.Text',
					'header' => 'SEARCHFOR_ARTISTS',
					'stringHeader' => 1,
					'cursorPos' => 0,
					'charsRef' => 'UPPER',
					'numberLetterRef' => 'UPPER',
					'callback' => \&searchHandler,
				},

				'ALBUMS' => {
					'useMode' => 'INPUT.Text',
					'header' => 'SEARCHFOR_ALBUMS',
					'stringHeader' => 1,
					'cursorPos' => 0,
					'charsRef' => 'UPPER',
					'numberLetterRef' => 'UPPER',
					'callback' => \&searchHandler,
				},

				'SONGS' => {
					'useMode' => 'INPUT.Text',
					'header' => 'SEARCHFOR_SONGS',
					'stringHeader' => 1,
					'cursorPos' => 0,
					'charsRef' => 'UPPER',
					'numberLetterRef' => 'UPPER',
					'callback' => \&searchHandler,
				}
			}
		}
	);

	for my $name (sort keys %menuParams) {
		Slim::Buttons::Home::addMenuOption($name,$menuParams{$name});
	}	

	for my $name (sort keys %subs) {
		Slim::Buttons::Home::addMenuOption($name,$subs{$name});
	}
}

sub searchExitHandler {
	my ($client,$exitType) = @_;
	
	$exitType = uc($exitType);

	if ($exitType eq 'LEFT') {
		my @oldlines = Slim::Display::Display::curLines($client);

		Slim::Buttons::Home::jump($client, 'SEARCH');
		Slim::Buttons::Common::setMode($client, 'home');
		$client->pushRight(\@oldlines, [Slim::Display::Display::curLines($client)]);

	} elsif ($exitType eq 'RIGHT') {

		my $current = $client->param('valueRef');

		my %nextParams = searchFor($client, $$current) ;

		Slim::Buttons::Common::pushModeLeft($client, $nextParams{'useMode'}, \%nextParams);
	}
}

sub searchFor {
	my $client = shift;
	my $search = shift;
	my $value  = shift;
 
	$context{$client} = (defined($value) && length($value)) ? ($value) : ('A');

	my %nextParams = %{$menuParams{'SEARCH'}{'submenus'}{$search}};

	$nextParams{'valueRef'} = \$context{$client};

	$client->searchFor($search);

	return %nextParams;
}

sub searchHandler {
	my ($client,$exitType) = @_;

	$exitType = uc($exitType);

	if ($exitType eq 'BACKSPACE') {
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

		Slim::Buttons::Common::pushMode($client, 'browsedb', {
			'search'    => $term,
			'hierarchy' => 'contributor,album,track',
			'level'     => 0,
		});

	} elsif ($client->searchFor eq 'ALBUMS') {

		Slim::Buttons::Common::pushMode($client, 'browsedb', {
			'search'    => $term,
			'hierarchy' => 'album,track',
			'level'     => 0,
		});

	} else {

		Slim::Buttons::Common::pushMode($client, 'browsedb', {
			'search'    => $term,
			'hierarchy' => 'track',
			'level'     => 0,
		});
	}

	$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
}

sub searchTerm {
	my $client = shift;

	# do the search!
	@{$client->searchTerm} = split(//, Slim::Utils::Text::ignoreCaseArticles($context{$client}));

	my $term = '';

	# Bug #738
	# Which should be the default? Old - which is substring always?
	if (Slim::Utils::Prefs::get('searchSubString')) {
		$term = '%';
	}

	for my $a (@{$client->searchTerm}) {

		if (defined($a) && ($a ne $rightarrow)) {
			$term .= $a;
		}
	}

	$term .= '%';

	# If we're searching in substrings, return - otherwise append another
	# search which is effectively \b for the query. We might (should?)
	# deal with alternate separator characters other than space.
	if (Slim::Utils::Prefs::get('searchSubString')) {
		return [ $term ];
	}

	return [ $term, "% $term" ];
}

1;

__END__
