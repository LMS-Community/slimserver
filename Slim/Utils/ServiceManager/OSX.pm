package Slim::Utils::ServiceManager::OSX;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use base qw(Slim::Utils::ServiceManager);

use FindBin qw($Bin);
use File::Spec::Functions qw(catdir);
use Slim::Utils::ServiceManager;

# re-use the startup-script we already have in place for the PreferencePane
sub canStart { 1 }
sub start {
	my ($class, $params) = @_;
	
	foreach my $path (
		catdir($Bin, '..', 'platforms', 'osx', 'Preference Pane'),
		catdir($Bin, '..', 'Resources'),
		catdir($ENV{HOME}, '/Library/PreferencePanes/SqueezeCenter.prefPane/Contents/Resources'),
		'/Library/PreferencePanes/SqueezeCenter.prefPane/Contents/Resources',
	) {
		my $startScript = catdir($path, 'start-server.sh');
		
		if (-f $startScript) {

			$startScript =~ s/ /\\ /g;
			system( $startScript . ($params ? " $params" : '') );

			last;
		}
	}
	
}

sub getStartupOptions {
	return ("I'm sorry, we're not quite there yet", 'Whatever is defined in the PrefPane');
}

# simple check so far - only check http availability (no starting/stopping states)
sub checkServiceState {
	my ($class) = @_;

	$class->{status} = $class->checkForHTTP() ? SC_STATE_RUNNING : SC_STATE_STOPPED;

	return $class->{status};
}

# use AppleScript to run some script as admin
# ugly but effective
# 	system('osascript -e \'do shell script "/run/something" with administrator privileges\'');

1;