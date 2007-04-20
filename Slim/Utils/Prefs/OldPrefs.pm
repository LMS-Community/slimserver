package Slim::Utils::Prefs::OldPrefs;

=head1 NAME

Slim::Utils::Prefs::OldPrefs

=head1 DESCRIPTION

Class to allow loading of the old 6.0/6.1/6.2/6.3/6.5 YAML based server preferences so they can be migrated to new preferences.

=head1 METHODS

=cut

use strict;

use YAML::Syck;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
use Slim::Utils::Log;

my $log = logger('prefs');

my $oldprefs;

=head2 get( $prefname )

Returns the value for old preference $prefname.

=cut

sub get {
	my $class = shift;
	my $pref  = shift;

	$class->_oldPrefs->{ $pref };
}

=head2 clientGet( $client, $prefname )

Returns the value for old client preference $prefname.

=cut

sub clientGet {
	my $class = shift;
	my $client = shift;
	my $pref  = shift;

	my $prefs = $class->_oldPrefs;

	if ($prefs->{'clients'} && $prefs->{'clients'}->{ $client->id } ) {

		return $prefs->{'clients'}->{ $client->id }->{ $pref };
	}

	return undef;
}

sub _oldPrefs {
	my $class = shift;

	return $oldprefs if $oldprefs;

	if ( my $path = _oldPath() ) {

		$oldprefs = eval { LoadFile($path) };

		if (!$@ && ref $oldprefs eq 'HASH') {

			$log->info("loaded $path");

			return $oldprefs;

		} else {

			$log->warn("failed to load $path [$@]");
		}
	}

	return $oldprefs = {};
}

sub _oldPath {

	my $oldPrefs;

	if ($::prefsfile && -r $::prefsfile) {

		$oldPrefs = $::prefsfile;

	} elsif (Slim::Utils::OSDetect::OS() eq 'mac' && -r catdir($ENV{'HOME'}, 'Library', 'SlimDevices', 'slimserver.pref')) {

		$oldPrefs = catdir($ENV{'HOME'}, 'Library', 'SlimDevices', 'slimserver.pref');

	} elsif (Slim::Utils::OSDetect::OS() eq 'win' && -r catdir($Bin, 'slimserver.pref'))  {

		$oldPrefs = catdir($Bin, 'slimserver.pref');

	} elsif (-r '/etc/slimserver.conf') {

		$oldPrefs = '/etc/slimserver.conf';

	} elsif (-r catdir(Slim::Utils::OSDetect::dirsFor('prefs'), 'slimserver.pref')) {

		$oldPrefs = catdir(Slim::Utils::OSDetect::dirsFor('prefs'), 'slimserver.pref');

	} elsif (-r catdir($ENV{'HOME'}, 'slimserver.pref')) {

		$oldPrefs = catdir($ENV{'HOME'}, 'slimserver.pref');

	} else {

		$log->warn("no old preference file found - using default preferences");

		return undef;
	}

	$log->info("using old preference file $oldPrefs for conversion");

	return $oldPrefs;
}

=head2 SEE ALSO

L<Slim::Utils::Prefs::Base>
L<Slim::Utils::Prefs::Namespace>
L<Slim::Utils::Prefs::Client>
L<Slim::Utils::Preds::OldPrefs>

=cut

1;
