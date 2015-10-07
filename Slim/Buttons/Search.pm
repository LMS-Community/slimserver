package Slim::Buttons::Search;

# XXX - this package is obsolete. It's no longer being loaded, as its functionality has been re-implemented in Slim::Menu::BrowseLibrary. - mh

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Search

=head1 DESCRIPTION

L<Slim::Buttons::Search> is a Logitech Media Server module to create a UI for searching
the user track database.  Seach by ARTIST, ALBUM and SONGS is added to the home 
menu structure as well as options for adding to the top level.  Search input uses the 
INPUT.Text mode.

=cut

use strict;
use Slim::Buttons::Common;
use Slim::Utils::Prefs;

# button functions for search directory
my @defaultSearchChoices = qw(ARTISTS ALBUMS SONGS);

our %context    = ();
our %menuParams = ();
	
sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	#grab the top level search parameters
	my %params = %{$menuParams{'SEARCH'}};
	
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
	$client->update();
} 

sub init {
	Slim::Buttons::Common::addMode('search',{}, \&Slim::Buttons::Search::setMode);

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
			'overlayRef' => sub { return (undef, shift->symbols('rightarrow')) },
			'overlayRefArgs' => 'C',
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
		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $name, $menuParams{$name});
		Slim::Buttons::Home::addMenuOption($name,$menuParams{$name});
	}	

	for my $name (sort keys %subs) {
		Slim::Buttons::Home::addMenuOption($name,$subs{$name});
	}
}

=head2 forgetClient ( $client )

Clean up global hash when a client is gone

=cut

sub forgetClient {
	my $client = shift;
	
	delete $context{ $client };
}

sub searchExitHandler {
	my ($client,$exitType) = @_;
	
	$exitType = uc($exitType);

	if ($exitType eq 'LEFT') {
	
		Slim::Buttons::Common::popModeRight($client);
	
	} elsif ($exitType eq 'RIGHT') {

		my $current = $client->modeParam('valueRef');

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
		startSearch($client);
	}
}

sub startSearch {
	my $client = shift;
	my $mode = shift;
	my $oldlines = $client->curLines();

	my $term = searchTerm($client);
	$client->showBriefly( {
		'line' => [ $client->string('SEARCHING'), undef ]
	});

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

	$client->pushLeft($oldlines, $client->curLines());
}

sub searchTerm {
	my $client = shift;
	my $search = shift;
	
	$search = $context{$client} if !defined $search;

	# do the search!
	@{$client->searchTerm} = split(//, Slim::Utils::Text::ignoreCase($search));

	my $term = '';

	my $prefs = preferences('server');

	# Bug #738
	# Which should be the default? Old - which is substring always?
	if ($prefs->get('searchSubString')) {
		$term = '%';
	}

	for my $a (@{$client->searchTerm}) {

		if (defined($a)) {
			$term .= $a;
		}
	}

	$term .= '%';

	# If we're searching in substrings, return - otherwise append another
	# search which is effectively \b for the query. We might (should?)
	# deal with alternate separator characters other than space.
	if ($prefs->get('searchSubString')) {
		return [ $term ];
	}

	return [ $term, "% $term" ];
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Buttons::Input::Text>

L<Slim::Player::Client>

=cut

1;

__END__
