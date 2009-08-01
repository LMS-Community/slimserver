package Slim::Utils::OS::SqueezeOS;

use strict;

use base qw(Slim::Utils::OS::Linux);

# Cannot use Slim::Utils::Prefs here because too early in bootstrap process.

sub dontSetUserAndGroup { 1 }

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();

	# package specific addition to @INC to cater for plugin locations
	$class->{osDetails}->{isSqueezeOS} = 1 ;
	$::noweb = 1;

	return $class->{osDetails};
}


sub initPrefs {
	my ($class, $prefs) = @_;
	
	require Slim::Utils::Prefs;
	
	$prefs->{checkVersion} = 0;
	
	_checkMediaAtStartup();
	Slim::Utils::Prefs::preferences('server')->setChange(\&_onAudiodirChange, 'audiodir');
	
}


=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the Squeezebox Server directories we
need information for.

=cut

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = ();
	
	if ($dir =~ /^(?:oldprefs|updates)$/) {

		push @dirs, $class->SUPER::dirsFor($dir);

	} elsif ($dir =~ /^(?:Firmware|Graphics|HTML|IR|SQLite|SQL|lib|Bin)$/) {

		push @dirs, "/usr/squeezecenter/$dir";

	} elsif ($dir eq 'Plugins') {
			
		push @dirs, $class->SUPER::dirsFor($dir);
		push @dirs, "/usr/squeezecenter/Slim/Plugin", "/usr/share/squeezecenter/Plugins";
		
	} elsif ($dir =~ /^(?:strings|revision)$/) {

		push @dirs, "/usr/squeezecenter";

	} elsif ($dir eq 'libpath') {

		push @dirs, "/usr/squeezecenter";

	} elsif ($dir =~ /^(?:types|convert)$/) {

		push @dirs, "/usr/squeezecenter";

	} elsif ($dir =~ /^(?:prefs)$/) {

		push @dirs, $::prefsdir || "/etc/squeezecenter/prefs";

	} elsif ($dir eq 'log') {

		push @dirs, $::logdir || "/var/log/squeezecenter";

	} elsif ($dir eq 'cache') {

		# XXX: cachedir pref is going to cause a problem here, we need to ignore it
		push @dirs, $::cachedir || "/etc/squeezecenter/cache";

	} elsif ($dir =~ /^(?:music)$/) {

		push @dirs, '';

	} elsif ($dir =~ /^(?:playlists)$/) {

		push @dirs, '';

	} else {

		warn "dirsFor: Didn't find a match request: [$dir]\n";
	}

	return wantarray() ? @dirs : $dirs[0];
}

# Bug 9488, always decode on Ubuntu/Debian
sub decodeExternalHelperPath {
	return Slim::Utils::Unicode::utf8decode_locale($_[1]);
}

sub scanner {
	return '/usr/squeezecenter/scanner.pl';
}

sub skipPlugins {
	my $class = shift;
	
	return (
		qw(
			Amazon
			Classical Deezer LMA Mediafly MP3tunes Napster Pandora Slacker Sounds
			Podcast
			InfoBrowser RSSNews
			
			DigitalInput LineIn	LineOut RS232
			SlimTris Snow Visualizer

			Extensions JiveExtras
			
			iTunes MusicMagic

			PreventStandby Rescan TT

			xPL
		),
		$class->SUPER::skipPlugins(),
	);
}

sub _setupMediaDir {
	my $path = shift;
	
	# Is audiodir defined, mounted and writable?
	if ($path && $path =~ m{^/media/[^/]+} && -w $path) {
		
		# XXX Maybe also check for rw mount-point
		
		# Create a .Squeezebox directory if necessary
		if ( !-e "$path/.Squeezebox" ) {
			mkdir "$path/.Squeezebox" or do {
				warn "Unable to create directory $path/.Squeezebox: $!\n";
				return 0;
			};
		}
		if ( !-e "$path/.Squeezebox/cache" ) {
			mkdir "$path/.Squeezebox/cache" or do {
				warn "Unable to create directory $path/.Squeezebox/cache: $!\n";
				return 0;
			};
		}
		
		Slim::Utils::Prefs::preferences('server')->set('librarycachedir', "$path/.Squeezebox/cache");
		return 1;
	}
	
	return 0;
}

sub _onAudiodirChange {
	my $prefs    = Slim::Utils::Prefs::preferences('server');
	my $audiodir = $prefs->get('audiodir');
	
	if ($audiodir) {
		if (_setupMediaDir($audiodir)) {
			# hunky dory
			return;
		} else {
			# it is defined but not valid
			warn "$audiodir cannot be used";
			$prefs->set('audiodir', undef);
		}
	}
}

sub _checkMediaAtStartup {
	my $prefs    = Slim::Utils::Prefs::preferences('server');
	my $audiodir = $prefs->get('audiodir');
	
	if (_setupMediaDir($audiodir)) {
		# hunky dory
		return;
	}
	
	my $mounts = `/bin/mount | grep /media/`;
	chomp $mounts;
	
	for my $line ( split /\n/, $mounts ) {
		my ($path, $rw) = $line =~ /on ([^ ]+) type [^ ]+ \((\w{2})/;
		next if $rw ne 'rw';
		
		if (_setupMediaDir($path)) {
			$prefs->set('audiodir', $path);
			return;
		}
	}
	
	if ($audiodir) {
		# it is defined but not valid
		$prefs->set('audiodir', undef);
	}
}

1;