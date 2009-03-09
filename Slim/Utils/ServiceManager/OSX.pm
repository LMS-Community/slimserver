package Slim::Utils::ServiceManager::OSX;

use base qw(Slim::Utils::ServiceManager);

use FindBin qw($Bin);
use File::Spec::Functions qw(catdir);
use Slim::Utils::ServiceManager;

# re-use the startup-script we already have in place for the PreferencePane
sub start {
	foreach my $path (
		catdir($Bin, '..', 'platforms', 'osx', 'Preference Pane'),
		catdir($Bin, '..', 'Resources'),
		catdir($ENV{HOME}, '/Library/PreferencePanes/SqueezeCenter.prefPane/Contents/Resources'),
		'/Library/PreferencePanes/SqueezeCenter.prefPane/Contents/Resources',
	) {
		my $startScript = catdir($path, 'start-server.sh');
		
		if (-f $startScript) {

			$startScript =~ s/ /\\ /g;
			system($startScript);

			last;
		}
	}
	
}

# simple check so far - only check http availability (no starting/stopping states)
sub checkServiceState {
	my ($class) = @_;

	$class->{status} = $class->checkForHTTP() ? SC_STATE_RUNNING : SC_STATE_STOPPED;

	return $class->{status};
}

1;