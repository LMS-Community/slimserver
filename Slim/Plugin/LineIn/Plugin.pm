package Slim::Plugin::LineIn::Plugin;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use Scalar::Util qw(blessed);
use HTTP::Status qw(RC_MOVED_TEMPORARILY);

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $line_in = {
	'name'  => '{PLUGIN_LINE_IN_LINE_IN}',
	'value' => 1,
	'url'   => "linein:1",
};

my $url   = 'plugins/LineIn/set.html';
my $prefs = preferences("server");

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

	main::INFOLOG && $log->info("Initializing");
	
	$class->SUPER::initPlugin();

	Slim::Player::ProtocolHandlers->registerHandler('linein', 'Slim::Plugin::LineIn::ProtocolHandler');

	# Subscribe to line in/out events
	Slim::Control::Request::subscribe(\&_liosCallback, [['lios'], ['linein']]);


#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
	Slim::Control::Request::addDispatch(['lineinalwaysoncommand'],
	[1, 0, 1, \&lineInAlwaysOnCommand]);
	Slim::Control::Request::addDispatch(['lineinlevel'],
	[1, 1, 0, \&lineInLevelMenu]);
	Slim::Control::Request::addDispatch(['lineinlevelcommand'],
	[1, 0, 1, \&lineInLevelCommand]);
	Slim::Control::Request::addDispatch(['setlinein', '_which'],
	[1, 0, 0, \&setLineIn]);

	Slim::Web::Pages->addPageLinks("icons", { $class->getDisplayName() => $class->_pluginDataFor('icon') });
}

# Called every time Jive main menu is updated after a player switch with $notify set to 0
# Adds Line In settings menus when main menu is updated, and Home menu Line In item if something is currently connected

# Called every time with $notify flag when something is connected/disconnected from LineIn jack:
# Adds/Removes Line In Home menu item as applicable

sub lineInItem {
	my $client = shift;
	my $notify = shift;

	return [] unless blessed($client)
		&& $client->isPlayer()
		&& Slim::Utils::PluginManager->isEnabled('Slim::Plugin::LineIn::Plugin')
		&& $client->hasLineIn();

	my $lineInItem = {
		text           => $client->string(getDisplayName()),
		weight         => 45,
		style          => 'itemplay',
		id             => 'linein',
		node           => 'home',
		actions => {
			do =>          {
				player => 0,
				cmd    => [ 'setlinein', 'linein' ],
			},
			play =>          {
				player => 0,
				cmd    => [ 'setlinein', 'linein' ],
			},
		},
	};

	if ($notify) {
		if ($client->lineInConnected) {
			Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', [ $lineInItem ], 'add',    $client->id() ] );
			$client->showBriefly({
				'jive' => {
					type    => 'icon',
					style   => 'lineIn',
				},
			});
		} else {
			Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', [ $lineInItem ], 'remove', $client->id() ] );
		}
	} else {

		my @strings           = qw/ OFF ON /;
	        my @translatedStrings = map { ucfirst($client->string($_)) } @strings;
		my $currentSetting    = $prefs->client($client)->get('lineInAlwaysOn'); 

		my @choiceActions;
		for my $i (0..$#strings) {
			push @choiceActions, 
			{
				player => 0,
				cmd    => [ 'lineinalwaysoncommand' ],
				params => {
					value  => $i,
				},
			},
		}

		my @lineInSettings = (
			{
				text           => $client->string("LINE_IN_LEVEL"),
				id             => 'settingsLineInLevel',
				node           => 'settingsAudio',
				weight         => 83,
				actions        => {
					go => {
						cmd    => ['lineinlevel'],
						player => 0,
					},
				},
				window         => { titleStyle => 'settings' },
			},
			{
				text           => $client->string("LINE_IN_ALWAYS_ON"),
				id             => 'settingsLineInAlwaysOn',
				node           => 'settingsAudio',
				selectedIndex  => $currentSetting + 1,
				weight         => 86,
				choiceStrings  => [ @translatedStrings ],
				actions        => {
					do => {
						choices => [ @choiceActions ],
					},
				},
			},
		);

		if ($client->lineInConnected) {
			return [ $lineInItem, @lineInSettings ];
		} else {
			return [ @lineInSettings ];
		}
	}
}

sub lineInLevelMenu {

	my $request = shift;
	my $client = $request->client();

	my $currentSetting    = $prefs->client($client)->get('lineInLevel'); 

	my $slider = {
		slider      => 1,
		min         => 1,
		max         => 100,
		sliderIcons => 'volume',
		initial     => $currentSetting + 0,
		actions => {
			do => {
				player => 0,
				cmd    => [ 'lineinlevelcommand' ],
				params => {
					valtag => 'value',
				},
			},
		},
	};

	$request->addResult("count", 1);
	$request->addResult("offset", 0);
	$request->setResultLoopHash('item_loop', 0, $slider);

	$request->setStatusDone();
}

sub lineInLevelCommand {
	my $request = shift;
	my $client  = $request->client();
	my $value   = $request->getParam('value');

	$prefs->client($client)->set('lineInLevel', $value);
	$request->setStatusDone();
}

sub lineInAlwaysOnCommand {
	my $request = shift;
	my $client  = $request->client();
	my $value   = $request->getParam('value');

	$prefs->client($client)->set('lineInAlwaysOn', $value);

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

	if ($which eq 'linein') {
		$client->showBriefly(
			{ 'jive' =>
				{
					'type'    => 'popupplay',
					'text'    => [ $client->string('PLUGIN_LINE_IN_IN_USE') ],
				},
			}
		);	
	}

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

	main::INFOLOG && $log->info("Calling addtracks on [$name] ($url)");

	# Create an object in the database for this meta source: url.
	my $obj = Slim::Schema->updateOrCreate({
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
		if ($prefs->client($client)->get('syncgroupid')) {
			$client->controller()->unsync($client);	
		}

		
		# Remove it first if it is already there
		$client->execute([ 'playlist', 'deleteitem', $line_in->{'url'} ] );
		
		# Bug 11809: get the index of the inserted track from the request result, rather than using skip
		my $request = Slim::Control::Request->new($client->id, [ 'playlist', 'inserttracks', 'listRef', [ $obj ] ]);
		$request->execute();
		$client->execute([ 'playlist', 'index', $request->getResult('index') ]);	
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

	Slim::Web::Pages->addPageFunction($url, \&handleSetting);
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
	
	main::DEBUGLOG && $log->debug( 'Line In state changed: ' . $enabled );
	
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
