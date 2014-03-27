package Slim::Utils::Prefs::Migration;

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Utils::Log;

my $log   = logger('prefs');

sub init {
	my ($class, $prefs, $defaults) = @_;
	
	$class->migrate($prefs, $defaults);

	my $version = $prefs->get('_version') || 0;

	$version++;
	
	my $module = $class->getBaseMigrationClass($prefs) . $version;

	eval "use $module";
		
	if ($@) {
		main::DEBUGLOG && $log && $log->debug($@);
	}
	else {
		main::DEBUGLOG && $log && $log->is_debug && $log->debug("Initializing migration code: $module");
		$module->init($prefs, $defaults);
	};
}

sub getBaseMigrationClass {
	return $_[1]->{migrationClass} . '::V';
}

sub migrate {}

1;
