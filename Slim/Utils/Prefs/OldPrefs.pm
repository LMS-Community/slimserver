package Slim::Utils::Prefs::OldPrefs;

=head1 NAME

Slim::Utils::Prefs::OldPrefs

=head1 DESCRIPTION

Class to allow loading of the old 6.0/6.1/6.2/6.3/6.5 YAML based server preferences so they can be migrated to new preferences.

=head1 METHODS

=cut

use strict;

use YAML::XS;
use FindBin qw($Bin);
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

	if ( my $path = Slim::Utils::OSDetect::dirsFor('oldprefs') ) {

		main::INFOLOG && $log->is_info && $log->info("using old preference file $oldprefs for conversion") if $oldprefs;

		$oldprefs = eval { YAML::XS::LoadFile($path) };

		if (!$@ && ref $oldprefs eq 'HASH') {

			main::INFOLOG && $log->info("loaded $path");

			return $oldprefs;

		} else {

			$log->warn("failed to load $path [$@]");
		}
	}

	else {

		$log->warn("no old preference file found - using default preferences");
	}

	return $oldprefs = {};
}

=head2 SEE ALSO

L<Slim::Utils::Prefs::Base>
L<Slim::Utils::Prefs::Namespace>
L<Slim::Utils::Prefs::Client>
L<Slim::Utils::Preds::OldPrefs>

=cut

1;
