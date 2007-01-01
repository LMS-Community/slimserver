package Slim::Buttons::Favorites;

# $Id$
#
# Copyright (C) 2005-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.


=head1 NAME

Slim::Buttons::Favorites

=head1 DESCRIPTION

L<Slim::Buttons::Favorites> is a SlimServer module which defines
both a mode for listing all favorites, and a mode for displaying the
details of a station or track.

Other modes are encouraged to use the details mode, called
'Favorites.details'.  To use it, setup a hash of params, and
push into the mode.  The params hash must contain strings for
'title' and 'url'.  You may also include an array of strings called
'details'.  If included, each string in the details will be
displayed as well.  The mode also adds a line allowing the user to
add the url to his/her favorites.

=cut

use strict;
use File::Spec::Functions qw(:ALL);
use Scalar::Util qw(blessed);

use Slim::Buttons::Common;
use Slim::Utils::Favorites;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $log = logger('favorites');

my %context = ();

my %mapping = (
	'play'        => 'dead',
	'play.hold'   => 'play',
	'play.single' => 'play',
);

my %mainModeFunctions = (

	'play' => sub {
		my $client    = shift;
		
		my $listIndex = $client->modeParam('listIndex');
		my $urls      = $client->modeParam('urls');
		my $titles    = $client->modeParam('listRef');

		_addOrPlayFavoriteUrl($client, $urls->[$listIndex], $titles->[$listIndex], $listIndex);
	},

	'add' => sub {
		my $client    = shift;

		my $listIndex = $client->modeParam('listIndex');
		my $urls      = $client->modeParam('urls');
		my $titles    = $client->modeParam('listRef');

		_addOrPlayFavoriteUrl($client, $urls->[$listIndex], $titles->[$listIndex], $listIndex, 'add');
	},
);

sub getDisplayName {
	return 'FAVORITES';
}

sub init {
	$log->info("Initializing");

	Slim::Buttons::Common::addMode('FAVORITES', \%mainModeFunctions, \&setMode);

	Slim::Buttons::Home::addMenuOption('FAVORITES', { 'useMode' => 'FAVORITES' });

	Slim::Buttons::Common::setFunction('playFavorite', \&playFavorite);

	# register our functions
	
#		  |requires Client
#		  |  |is a Query
#		  |  |  |has Tags
#		  |  |  |  |Function to call
#		  C  Q  T  F
	Slim::Control::Request::addDispatch(['favorites', '_index', '_quantity'],  
		[0, 1, 1, \&listQuery]);
	Slim::Control::Request::addDispatch(['favorites', 'move', '_fromindex', '_toindex'],  
		[0, 0, 0, \&moveCommand]);
	Slim::Control::Request::addDispatch(['favorites', 'delete', '_index'],
		[0, 0, 0, \&deleteCommand]);
	Slim::Control::Request::addDispatch(['favorites', 'add', '_url', '_title'],
		[0, 0, 0, \&addCommand]);
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {

		if (!$context{$client}->{'blocking'}) {
			Slim::Buttons::Common::popMode($client);
		}

		return;
	}

	my $favs   = Slim::Utils::Favorites->new($client);
	my @titles = $favs->titles;
	my @urls   = $favs->urls;

	# don't give list mode an empty list!
	if (!scalar @titles) {
		push @titles, $client->string('EMPTY');
	}

	my %params = (
		'stringHeader'   => 1,
		'header'         => 'FAVORITES',
		'listRef'        => \@titles,
		'callback'       => \&mainModeCallback,
		'valueRef'       => \$context{$client}->{mainModeIndex},
		'externRef'      => sub {return $_[1] || $_[0]->string('EMPTY')},
		'headerAddCount' => scalar (@urls) ? 1 : 0,
		'urls'           => \@urls,
		'parentMode'     => Slim::Buttons::Common::mode($client),
		'overlayRef'     => sub {
			if (scalar @urls) {
				return (undef,shift->symbols('notesymbol'));
			} else {
				return undef;
			}
		},
		'overlayRefArgs' => 'C',
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

sub mainModeCallback {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my $listIndex = $client->modeParam('listIndex');
		my $urls      = $client->modeParam('urls');

		my %params = (
			title => $context{$client}->{'mainModeIndex'},
			url   => $urls->[$listIndex],
		);

 		Slim::Buttons::Common::pushModeLeft($client, 'remotetrackinfo', \%params);

	} else {

		$client->bumpRight;
	}
}

sub defaultMap {
	return \%mapping;
}

sub getFunctions {
	return \%mainModeFunctions;
}

####################################################################
# Adds a mapping for 'playFavorite' function in all modes
####################################################################
sub playFavorite {
	my $client = shift;
	my $button = shift;
	my $digit  = shift;

	if ($digit == 0) {
		$digit = 10;
	}

	my $listIndex = $digit - 1;
	my $favs      = Slim::Utils::Favorites->new($client);
	my @titles    = $favs->titles;
	my @urls      = $favs->urls;

	if (!$urls[$listIndex]) {

		$client->showBriefly({
			 'line' => [ sprintf($client->string('FAVORITES_NOT_DEFINED'), $digit) ],
		});

		return;
	}

	$log->info("Playing favorite number $digit, $titles[$listIndex]");

	_addOrPlayFavoriteUrl($client, $urls[$listIndex], $titles[$listIndex], $listIndex);
}

sub _addOrPlayFavoriteUrl {
	my $client  = shift;
	my $url     = shift;
	my $title   = shift;
	my $index   = shift;
	my $add     = shift || 0;

	my $string  = $add ? 'FAVORITES_ADDING' : 'FAVORITES_PLAYING';
	my $command = $add ? 'inserttracks' : 'loadtracks';

	if (defined $index) {

		$client->showBriefly({
			'line' => [ sprintf($client->string($string), $index+1), $title ],
		});
	}

	if (!$add) {
		$client->execute([ 'playlist', 'clear' ] );
	}

	# remote URLs should go via play/add so they go through Scanner
	# 
	# NB: Transporter digital source: URLs are special. They are
	# implemented as a ProtocolHandler, but are not remote streams.
	if ( Slim::Music::Info::isRemoteURL($url) && $url !~ /^source:/ ) {

		$command = $add ? 'add' : 'play';

		$log->info("Calling $command on favorite [$title] ($url)");

		$client->execute([ 'playlist', $command, $url, $title ]);

	} else {

		$log->info("Calling $command on favorite [$title] ($url)");

		$client->execute([ 'playlist', $command, 'favorite', $url ]);
	}
}

# These are all CLI commands
# move from to command
sub moveCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['favorites'], ['move']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client    = $request->client();
	my $fromindex = $request->getParam('_fromindex');;
	my $toindex   = $request->getParam('_toindex');;

	if (!defined $fromindex || !defined $toindex) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Utils::Favorites->moveItem($client, $fromindex, $toindex);

	$request->setStatusDone();
}

# add to favorites
sub addCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['favorites'], ['add']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $url    = $request->getParam('_url');;
	my $title  = $request->getParam('_title');;

	if (!defined $url || !defined $title) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Utils::Favorites->clientAdd($client, $url, $title);

	$request->setStatusDone();
}

# delete command
sub deleteCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['favorites'], ['delete']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $index  = $request->getParam('_index');;

	if (!defined $index) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Utils::Favorites->deleteByClientAndId($client, $index);

	$request->setStatusDone();
}

# favorites list
sub listQuery {
	my $request = shift;

	if ($request->isNotQuery([['favorites']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client   = $request->client();
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	
	my $favs     = Slim::Utils::Favorites->new($client);
	my @titles   = $favs->titles;
	my @urls     = $favs->urls;
	
	my $count    = scalar(@titles);

	$request->addResult('count', $count);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {
		my $idx = $start;
		my $cnt = 0;

		for my $eachtitle (@titles[$start..$end]) {
			$request->addResultLoop('@favorites', $cnt, 'id', $idx);
			$request->addResultLoop('@favorites', $cnt, 'title', $eachtitle);
			$request->addResultLoop('@favorites', $cnt, 'url', $urls[$idx]);
			$cnt++;
			$idx++;
		}	
	}

	$request->setStatusDone();
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Utils::Favorites>

=cut

1;

__END__
