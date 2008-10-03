package Slim::Plugin::SubHeadOut::Plugin;

# SqueezeCenter Copyright 2001-2008 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use Scalar::Util qw(blessed);
use HTTP::Status qw(RC_MOVED_TEMPORARILY);

use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $url   = 'plugins/SubHeadOut/set.html';
my $prefs = preferences("server");

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.subheadout',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

sub getDisplayName {
	return 'PLUGIN_SUB_HEAD_OUT'
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


1;

__END__
