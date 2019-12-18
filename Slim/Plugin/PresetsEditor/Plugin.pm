package Slim::Plugin::PresetsEditor::Plugin;

# Logitech Media Server Copyright 2001-2019 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Log;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.presetseditor',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_PRESETS_EDITOR',
});

sub initPlugin {
	if (main::WEBUI) {
		require Slim::Plugin::PresetsEditor::Settings;
		Slim::Plugin::PresetsEditor::Settings->new();
	}
	else {
		$log->warn(Slim::Utils::Strings::string('PLUGIN_PRESETS_EDITOR_NEED_WEBUI'));
	}
}

1;