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
	
	if ( !main::SCANNER && -r '/proc/cpuinfo' ) {
		# Read MAC/UUID from cpuinfo
		open my $fh, '<', '/proc/cpuinfo' or die "Unable to read /proc/cpuinfo: $!";
		while ( <$fh> ) {
			if ( /^Serial\s+:\s+([0-9a-f]+)/ ) {
				my $serial = $1;
				my $mac = '000420' . substr( $serial, -6, 6 );
				$mac =~ s/(.{2})/$1:/g;
				$mac =~ s/:$//;
				$class->{osDetails}->{mac} = $mac;
			}
			elsif ( /^UUID\s+:\s+([0-9a-f-]+)/ ) {
				my $uuid = $1;
				$uuid =~ s/-//g;
				$class->{osDetails}->{uuid} = $uuid;
			}
		}
		close $fh;
	}

	return $class->{osDetails};
}

sub ignoredItems {
	my $class = shift;
	
	my %ignoredItems = $class->SUPER::ignoredItems();

	# ignore some Windows special folders which exist on external disks too
	# can't ignore Recycler though... http://www.lastfm.de/music/Recycler
	$ignoredItems{'System Volume Information'} = 1;
	$ignoredItems{'RECYCLER'} = 1;
	$ignoredItems{'$Recycle.Bin'} = 1;

	return %ignoredItems;
}

sub initPrefs {
	my ($class, $defaults) = @_;
	
	$defaults->{maxPlaylistLength} = 100;
	
	# XXX use SN test for now
	$defaults->{use_sn_test} = 1;
}


use constant SQUEEZEPLAY_PREFS => '/etc/squeezeplay/userpath/settings/';

my %prefSyncHandlers = (
	SQUEEZEPLAY_PREFS . 'SetupLanguage.lua' => sub {
		my $data = shift;

		if ($$data && $$data =~ /locale="([A-Z][A-Z])"/) {
			Slim::Utils::Prefs::preferences('server')->set('language', uc($1));
		}
	},

	SQUEEZEPLAY_PREFS . 'SetupDateTime.lua' => sub {
		my $data = shift;

		if ($$data) {
			my $prefs = Slim::Utils::Prefs::preferences('server');
		
			if ($$data =~ /dateformat="(.*?)"/) {
				$prefs->set('longdateFormat', $1);
			}

			if ($$data =~ /shortdateformat="(.*?)"/) {
				$prefs->set('shortdateFormat', $1);
			}

			# Squeezeplay only knows 12 vs. 24h time, but no fancy formats as Squeezebox Server
			$prefs->set('timeFormat', $$data =~ /hours="24"/ ? '%H:%M' : '|%I:%M %p');

			$prefs = Slim::Utils::Prefs::preferences('plugin.datetime');
			foreach ( Slim::Player::Client::clients() ) {
				$prefs->client($_)->set('dateFormat', '');
				$prefs->client($_)->set('timeFormat', '');
			}
		}
	},
	
	SQUEEZEPLAY_PREFS . 'Playback.lua' => sub {
		my $data = shift;
		
		if ($$data && $$data =~ /playerInit={([^}]+)}/i) {
			my $playerInit = $1;
			
			if ($playerInit =~ /name="(.*?)"/i) {
				Slim::Utils::Prefs::preferences('server')->set('libraryname', $1);
			}
		}
	},
) unless main::SCANNER;

my ($i, $w);
sub postInitPrefs {
	my ( $class, $prefs ) = @_;
	
	_checkMediaAtStartup($prefs);
	
	$prefs->setChange( \&_onAudiodirChange, 'audiodir', 'FIRST' );

	if (!main::SCANNER) {

		# sync up prefs in case they were changed while Squeezebox Server wasn't running
		foreach (keys %prefSyncHandlers) {
			_syncPrefs($_);
		}

		# initialize prefs syncing between Squeezeplay and Squeezebox Server
		eval {
			require Linux::Inotify2;
			import Linux::Inotify2;

			$i = Linux::Inotify2->new() or die "Unable to start Inotify watcher: $!";

			$i->watch(SQUEEZEPLAY_PREFS, IN_MOVE() | IN_MODIFY(), sub {
				my $ev = shift;
				my $file = $ev->fullname || '';
				
				# $ev->fullname sometimes adds duplicate slashes
				$file =~ s|//|/|g;

				_syncPrefs($file);
				
			}) or die "Unable to add Inotify watcher: $!";

			$w = AnyEvent->io(
				fh => $i->fileno,
				poll => 'r',
				cb => sub { $i->poll },
			);
		};

		Slim::Utils::Log::logError("Squeezeplay <-> Squeezebox Server prefs syncing failed to initialize: $@") if ($@);
	}
}

sub _syncPrefs {
	my $file = shift;

	if ($file && $prefSyncHandlers{$file} && -r $file ) {

		require File::Slurp;

		my $data = File::Slurp::read_file($file);

		&{ $prefSyncHandlers{$file} }(\$data);
	}
}


sub sqlHelperClass { 'Slim::Utils::SQLiteHelper' }

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the Squeezebox Server directories we
need information for.

=cut

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = ();
	
	if ($dir =~ /^(?:scprefs|oldprefs|updates)$/) {

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

sub gdresize {
	return '/usr/squeezecenter/gdresize.pl';
}

sub gdresized {
	return '/usr/squeezecenter/gdresized.pl';
}

# See corresponding list in SqueezeOS SbS build file: squeezecenter_svn.bb
# Only file listed there in INCLUDED_PLUGINS are actually installed 
sub skipPlugins {
	my $class = shift;
	
	return (
		qw(
			Amazon
			Classical Deezer LMA Mediafly MP3tunes Napster Pandora Slacker Sounds
			Queen
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
	my ( $path, $prefs ) = @_;
	
	# Is audiodir defined, mounted and writable?
	if ($path && $path =~ m{^/media/[^/]+} && -w $path) {

		my $mounts = `/bin/mount | grep "$path"`;
		chomp $mounts;

		if ( !$mounts ) {
			warn "$path: mount point is not mounted, let's ignore it\n";
			return 0;
		}

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
		
		$prefs->set( librarycachedir => "$path/.Squeezebox/cache");
		
		return 1;
	}
	
	return 0;
}

sub _onAudiodirChange {
	require Slim::Utils::Prefs;
	my $prefs = Slim::Utils::Prefs::preferences('server');
    
	my $audiodir = $prefs->get('audiodir');
	
	if ($audiodir) {
		if (_setupMediaDir($audiodir, $prefs)) {
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
	my $prefs = shift;
	
	my $audiodir = $prefs->get('audiodir');
	
	if (_setupMediaDir($audiodir, $prefs)) {
		# hunky dory
		return;
	}
	
	my $mounts = `/bin/mount | grep /media/`;
	chomp $mounts;
	
	for my $line ( split /\n/, $mounts ) {
		my ($path, $rw) = $line =~ /on ([^ ]+) type [^ ]+ \((\w{2})/;
		next if $rw ne 'rw';
		
		if (_setupMediaDir($path, $prefs)) {
			$prefs->set('audiodir', $path);
			return;
		}
	}
	
	if ($audiodir) {
		# it is defined but not valid
		$prefs->set('audiodir', undef);
	}
}

# don't download/cache firmware for other players, but have them download directly
sub directFirmwareDownload { 1 };

# Path to progress JSON file
sub progressJSON { '/etc/squeezecenter/scan.json' }

1;
