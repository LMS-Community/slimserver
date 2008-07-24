package Slim::Plugin::LineIn::Plugin;

# SqueezeCenter Copyright 2001-2008 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use Scalar::Util qw(blessed);

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;

my $line_in = 0;

my @line_ins = ();

my $source_name = 'source';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.linein',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

sub getDisplayName {
	return 'PLUGIN_LINE_IN'
}

sub initPlugin {
	my $class = shift;

	$log->info("Initializing");
	
	$class->SUPER::initPlugin();

	@line_ins = (
		{
			'name'  => '{PLUGIN_LINE_IN_LINE_IN}',
			'value' => 1,
			'url'   => "$source_name:linein",
		},
	);

	Slim::Player::ProtocolHandlers->registerHandler('source', 'Slim::Plugin::LineIn::ProtocolHandler');

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
	Slim::Control::Request::addDispatch(['lineinmenu'],
	[1, 1, 0, \&lineInMenu]);
	Slim::Control::Request::addDispatch(['setlinein', '_which'],
	[1, 0, 0, \&setLineIn]);
}

# Called every time Jive main menu is updated after a player switch
# Adds Line In menu item for Boom
sub lineInItem {
	my $client = shift;

	return [] unless blessed($client)
		&& $client->isPlayer()
		&& Slim::Utils::PluginManager->isEnabled('Slim::Plugin::LineIn::Plugin')
		&& $client->hasLineIn();

	return [{
		stringToken    => getDisplayName(),
		weight         => 45,
		id             => 'linein',
		node           => 'home',
		'icon-id'      => Slim::Plugin::LineIn::Plugin->_pluginDataFor('icon'),
		displayWhenOff => 0,
		window         => { titleStyle => 'album' },
		actions => {
			go =>          {
				player => 0,
				cmd    => [ 'lineinmenu' ],
			},
		},
	}];
}

sub lineInMenu {
	my $request = shift;
	my $client = $request->client();
	my @menu = (
		{
			text  => $client->string('PLUGIN_LINE_IN_LINE_IN'),
			id  => 'linein',
			weight  => 10,
			style   => 'itemplay',
			nextWindow => 'nowPlaying',
			actions => {
				play => {
					player => 0,
					cmd    => [ 'setlinein' , 'linein' ],
				},
				go => {
					player => 0,
					cmd    => [ 'setlinein' , 'linein' ],
				},
			},
		},
	);

	my $numitems = scalar(@menu);
	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachItem (@menu[0..$#menu]) {
		$request->setResultLoopHash('item_loop', $cnt, $eachItem);
		$cnt++;
	}
	$request->setStatusDone();
}

sub setLineIn {
	my $request = shift;
	my $client  = $request->client();
	my $which   = $request->getParam('_which');
	my $functions = getFunctions();

	if (!defined $which || !defined $$functions{$which} || !$client) {
		$request->setStatusBadParams();
		return;
	}

	&{$$functions{$which}}($client);

	$request->setStatusDone()
}

sub enabled {
	my $client = shift;
	
	# make sure this is only validated when the provided client has line in.
	# when the client isn't given, we only need to report that the plugin is alive.
	return $client ? $client->hasLineIn() : 1;
}

sub valueForSourceName {
	my $sourceName = shift || return 0;

	for my $input (@line_ins) {

		if ($input->{'url'} eq $sourceName) {

			return $input->{'value'};
		}
	}

	return 0;
}

sub updateLineIn {
	my $client = shift;
	my $valueRef = shift;

	my $name  = $valueRef->{'name'};
	my $value = $valueRef->{'value'};
	my $url   = $valueRef->{'url'};

	# Strip off INPUT.Choice brackets.
	$name =~ s/[{}]//g;
	$name = $client->string($name);

	$log->info("Calling addtracks on [$name] ($url)");

	# Create an object in the database for this meta source: url.
	my $obj = Slim::Schema->rs('Track')->updateOrCreate({
		'url'        => $url,
		'create'     => 1,
		'readTags'   => 0,
		'attributes' => {
			'TITLE' => $name,
			'CT'    => 'src',
		},
	});

	my $line1;
	my $line2;
	
	if ($client->linesPerScreen == 1) {

		$line2 = $client->doubleString('NOW_PLAYING_FROM');

	} else {

		$line1 = $client->string('NOW_PLAYING_FROM');
		$line2 = $name;
	};

	$client->showBriefly({
		'line'    => [ $line1, $line2 ],
		'overlay' => [ undef, $client->symbols('notesymbol') ],
	});

	if (blessed($obj)) {
		$client->execute([ 'playlist', 'clear' ] );
		$client->execute([ 'playlist', 'playtracks', 'listRef', [ $obj ] ]);
	}
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		'header'       => '{PLUGIN_LINE_IN} {count}',
		'listRef'      => \@line_ins,
		'modeName'     => 'Line In Plugin',
		'onPlay'       => \&updateLineIn,
		'overlayRef'   => sub { return [ undef, shift->symbols('notesymbol') ] },
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub getFunctions {
	return {
		'linein'     => sub { updateLineIn(shift, $line_ins[ 0 ]) },
	};
}

# This plugin leaks into the main server, Slim::Web::Pages::Home() needs to
# call this function to decide to show the Line In menu or not.
sub webPages {
	my $class        = shift;
	my $hasLineIn = shift;

	my $urlBase = 'plugins/LineIn';

	if ($hasLineIn) {
		Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_LINE_IN' => "$urlBase/list.html" });
	} else {
		Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_LINE_IN' => undef });
	}
	Slim::Web::Pages->addPageLinks("icons", { $class->getDisplayName() => $class->_pluginDataFor('icon') });

	Slim::Web::HTTP::addPageFunction("$urlBase/list.html", \&handleWebList);
	Slim::Web::HTTP::addPageFunction("$urlBase/set.html", \&handleSetting);
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;
	my $url;

	if ($client) {

		my $song = Slim::Player::Playlist::song($client);
		
		if ($song) {
			$url = $song->url;

		
			my $name;
			for my $input (@line_ins) {
				if ($url && $url eq $input->{'url'}) {
					$name = $input->{'name'};
					last;
				}
			}
	
			if (defined $name) {
				# pre-localised string served to template
				$params->{'lineInCurrent'} = Slim::Buttons::Input::Choice::formatString(
					$client, $name,
				);
			}
		}
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/LineIn/list.html', $params);
}

# Handles play requests from plugin's web page
sub handleSetting {
	my ($client, $params) = @_;

	if (defined $client) {

		updateLineIn($client, $line_ins[ ($params->{'type'} - 1) ]);
	}

	handleWebList($client, $params);
}

1;

__END__
