package Slim::Plugin::CLI::Settings;

# SlimServer Copyright (c) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('cli');

$prefs->migrate(1, sub {
	$prefs->set('cliport', Slim::Utils::Prefs::OldPrefs->get('cliport') || 9090); 1;
});

$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 1024, 'high' => 65535 }, 'cliport');
$prefs->setChange(\&Slim::Plugin::CLI::Plugin::cli_socket_change, 'cliport');

sub name {
	return 'PLUGIN_CLI';
}

sub page {
	return 'plugins/CLI/settings/basic.html';
}

sub prefs {
	return ($prefs, 'cliport');
}

1;

__END__
