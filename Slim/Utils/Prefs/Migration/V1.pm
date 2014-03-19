package Slim::Utils::Prefs::Migration::V1;

use strict;

use Slim::Utils::Prefs::OldPrefs;

sub init {
	my ($class, $prefs, $defaults, $path) = @_;
	
	$prefs->migrate(1, sub {
		unless (-d $path) { mkdir $path; }
		unless (-d $path) { logError("can't create new preferences directory at $path"); }
	
		for my $pref (keys %$defaults) {
			my $old = Slim::Utils::Prefs::OldPrefs->get($pref);
	
			# bug 7237: don't migrate dbsource if we're upgrading from SS6.3
			next if $pref eq 'dbsource' && $old && $old =~ /SQLite/i;
	
			$prefs->set($pref, $old) if !$prefs->exists($pref) && defined $old;
		}

		1;
	});
}

1;