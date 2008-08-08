package Slim::Plugin::LineIn::Plugin;

# SqueezeCenter Copyright 2001-2008 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use Scalar::Util qw(blessed);
use HTTP::Status qw(RC_MOVED_TEMPORARILY);

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;

my $line_in = {
	'name'  => '{PLUGIN_LINE_IN_LINE_IN}',
	'value' => 1,
	'url'   => "linein:1",
};

my $url = 'plugins/LineIn/set.html';

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

	Slim::Player::ProtocolHandlers->registerHandler('linein', 'Slim::Plugin::LineIn::ProtocolHandler');

	# Subscribe to line in/out events
	Slim::Control::Request::subscribe(\&_liosCallback, [['lios'], ['linein']]);


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
		&& $client->hasLineIn()
		&& $client->lineInConnected();

	return [{
		stringToken    => getDisplayName(),
		weight         => 45,
		id             => 'linein',
		node           => 'extras',
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

	if ($sourceName eq $line_in->{'url'}) {

		return $line_in->{'value'};
	}

	return 0;
}

sub updateLineIn {
	my $client = shift;

	my $name  = $line_in->{'name'};
	my $url   = $line_in->{'url'};

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
	
	updateLineIn($client);

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', {
		'stringHeader' => 1,
		'header'       => $class->getDisplayName(),
		'listRef'      => [ $client->string('PLUGIN_LINE_IN_IN_USE') ],
		'modeName'     => 'Line In Plugin',
	});
}

sub getFunctions {
	return {
		'linein' => sub { updateLineIn(shift) },
	};
}

# This plugin leaks into the main server, Slim::Web::Pages::Home() needs to
# call this function to decide to show the Line In menu or not.
sub webPages {
	my $class  = shift;
	my $client = shift || return;

	if ($client->hasLineIn && $client->lineInConnected) {
		Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_LINE_IN' => $url });
	} else {
		Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_LINE_IN' => undef });
	}
	Slim::Web::Pages->addPageLinks("icons", { $class->getDisplayName() => $class->_pluginDataFor('icon') });

	Slim::Web::HTTP::addPageFunction($url, \&handleSetting);
}

sub handleSetting {
	my ($client, $params, $gugus, $httpClient, $response) = @_;

	if (defined $client) {

		updateLineIn($client);
	}

	$response->code(RC_MOVED_TEMPORARILY);
	$response->header('Location' => $params->{webroot} . 'home.html');

	return Slim::Web::HTTP::filltemplatefile($url, $params);
}


# line in/out event handler
sub _liosCallback {
	my $request = shift;
	my $client  = $request->client() || return;
	
	my $enabled = $request->getParam('_state');
	
	$log->debug( 'Line In state changed: ' . $enabled );
	
	if ($enabled) {
		# XXX - not sure it's a good idea to delete current playlist?
		# maybe we should just insert the linein:1 at the current position and play it?
		updateLineIn($client);
	}
	else {
		# remove linein item from current playlist, menus etc.
		$client->execute([ 'playlist', 'deleteitem', $line_in->{'url'} ] );
		$client->setLineIn(0);
	}

	Slim::Buttons::Home::updateMenu($client);
}

1;

__END__
