package Slim::Utils::OS::Debian;

use strict;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

use base qw(Slim::Utils::OS::Linux);

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();

	$class->{osDetails}->{osName} = 'Debian';

	# package specific addition to @INC to cater for plugin locations
	if ($0 =~ m{^/usr/sbin/squeezecenter}) {
		$class->{osDetails}->{isDebian} = 1 ;

		unshift @INC, '/usr/share/squeezecenter';
		unshift @INC, '/usr/share/squeezecenter/CPAN';
	}
	
	# Bug 2659 - maybe. Remove old versions of modules that are now in the $Bin/lib/ tree.
	if (!Slim::Utils::OSDetect::isDebian()) {

		unlink("$Bin/CPAN/MP3/Info.pm");
		unlink("$Bin/CPAN/DBIx/ContextualFetch.pm");
	}

	return $class->{osDetails};
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the SqueezeCenter directories we
need information for.

=cut

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = ();
	
	if ($dir eq "Plugins") {
		push @dirs, catdir($Bin, 'Slim', 'Plugin');
	}

	if ($dir eq 'oldprefs') {

		push @dirs, $class->SUPER::dirsFor($dir);

	} elsif ($dir =~ /^(?:Firmware|Graphics|HTML|IR|MySQL|SQL|lib|Bin)$/) {

		push @dirs, "/usr/share/squeezecenter/$dir";

	} elsif ($dir eq 'Plugins') {
			
		push @dirs, "/usr/share/perl5/Slim/Plugin", "/usr/share/squeezecenter/Plugins";
		
	} elsif ($dir =~ /^(?:strings|revision)$/) {

		push @dirs, "/usr/share/squeezecenter";

	} elsif ($dir eq 'libpath') {

		push @dirs, "/usr/share/squeezecenter" if $class->{osDetails}->{isDebian};

	# Because we use the system MySQL, we need to point to the right
	# directory for the errmsg. files. Default to english.
	} elsif ($dir eq 'mysql-language') {

		push @dirs, "/usr/share/mysql/english" if $class->{osDetails}->{isDebian};

	} elsif ($dir =~ /^(?:types|convert)$/) {

		push @dirs, "/etc/squeezecenter";

	} elsif ($dir =~ /^(?:prefs)$/) {

		push @dirs, $::prefsdir || "/var/lib/squeezecenter/prefs";

	} elsif ($dir eq 'log') {

		push @dirs, $::logdir || "/var/log/squeezecenter";

	} elsif ($dir eq 'cache') {

		push @dirs, $::cachedir || "/var/lib/squeezecenter/cache";

	} elsif ($dir =~ /^(?:music|playlists)$/) {

		push @dirs, '';

	} else {

		warn "dirsFor: Didn't find a match request: [$dir]\n";
	}

	return wantarray() ? @dirs : $dirs[0];
}

sub scanner {
	return '/usr/sbin/squeezecenter-scanner';
}


1;