package Slim::Utils::Prefs::Migration::V1;

use strict;

use base qw(Slim::Utils::Prefs::Migration);

use Slim::Utils::Prefs::OldPrefs;

sub migrate {
	my ($class, $prefs, $defaults) = @_;
	
	$prefs->migrate(1, sub {
	
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