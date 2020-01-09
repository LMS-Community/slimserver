package Slim::Plugin::LineOut::Plugin;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use Scalar::Util qw(blessed);
use HTTP::Status qw(RC_MOVED_TEMPORARILY);

use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $prefs = preferences("server");

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.lineout',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();
	
	Slim::Web::Pages->addPageLinks("icons", { $class->getDisplayName() => $class->_pluginDataFor('icon') });
}

sub getDisplayName {
	return 'PLUGIN_LINE_OUT'
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	Slim::Buttons::Common::pushModeLeft(
		$client,
		'INPUT.Choice',
		Slim::Buttons::Settings::analogOutMenu()
	);
}

# This plugin leaks into the main server, Slim::Web::Pages::Home() needs to
# call this function to decide to show the Line In menu or not.
sub webPages {
	my $class  = shift;
	my $client = shift || return;

	if ($client->hasHeadSubOut) {
		Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_LINE_OUT' => 'settings/player/audio.html' });
	} else {
		Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_LINE_OUT' => undef });
	}
}

1;

__END__
