package Slim::Utils::OS::SqueezeOS;

use strict;
use base qw(Slim::Utils::OS::Linux);

use constant SQUEEZEPLAY_PREFS => '/etc/squeezeplay/userpath/settings/';
use constant SP_PREFS_JSON     => '/etc/squeezecenter/prefs.json';
use constant SP_SCAN_JSON      => '/etc/squeezecenter/scan.json';

# Cannot use Slim::Utils::Prefs here because too early in bootstrap process.

sub dontSetUserAndGroup { 1 }

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();

	# package specific addition to @INC to cater for plugin locations
	$class->{osDetails}->{isSqueezeOS} = 1;
	
	if ( !main::SCANNER && -r '/proc/cpuinfo' ) {
		# Read UUID from cpuinfo
		open my $fh, '<', '/proc/cpuinfo' or die "Unable to read /proc/cpuinfo: $!";
		while ( <$fh> ) {
			if ( /^UUID\s+:\s+([0-9a-f-]+)/ ) {
				my $uuid = $1;
				$uuid =~ s/-//g;
				$class->{osDetails}->{uuid} = $uuid;
			}
		}
		close $fh;
	}
	
	if ( !main::SCANNER && -r '/sys/class/net/eth0/address' ) {
		# Read MAC
		open my $fh, '<', '/sys/class/net/eth0/address' or die "Unable to read /sys/class/net/eth0/address: $!";
		while ( <$fh> ) {
			if ( /^([0-9a-f]{2}([:]|$)){6}$/i ) {
				$class->{osDetails}->{mac} = $_;
				chomp $class->{osDetails}->{mac};
				last;
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
	$ignoredItems{'$RECYCLE.BIN'} = 1;
	$ignoredItems{'log'} = 1;

	return %ignoredItems;
}

sub initPrefs {
	my ($class, $defaults) = @_;
	
	$defaults->{maxPlaylistLength} = 100;
	$defaults->{libraryname} = "Squeezebox Touch";
	$defaults->{autorescan} = 1;
	$defaults->{disabledextensionsvideo}  = 'VIDEO';		# don't scan videos on SqueezeOS
	$defaults->{disabledextensionsimages} = 'bmp, gif, png' # scaling down non-jpg might use too much memory
}

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

			# Squeezeplay only knows 12 vs. 24h time, but no fancy formats as Logitech Media Server
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
				my $prefs = Slim::Utils::Prefs::preferences('server');
				$prefs->set('libraryname', $1);
				
				# can't handle this change using a changehandler,
				# as this in turn updates the pref again 
				_updateLibraryname($prefs);
			}
		}
	},
) unless main::SCANNER;

my ($i, $w);
sub postInitPrefs {
	my ( $class, $prefs ) = @_;
	
	_checkMediaAtStartup($prefs);
	
	$prefs->setChange( \&_onAudiodirChange, 'mediadirs', 'FIRST' );
	$prefs->setChange( sub {
		_updateLibraryname($prefs);
	}, 'language', 'mediadirs' );
	$prefs->setChange( \&_onSNTimediffChange, 'sn_timediff');

	if ( !main::SCANNER ) {

		# sync up prefs in case they were changed while the server wasn't running
		foreach (keys %prefSyncHandlers) {
			_syncPrefs($_);
		}

		# initialize prefs syncing between Squeezeplay and the server
		eval {
			require Linux::Inotify2;
			import Linux::Inotify2;

			$i = Linux::Inotify2->new() or die "Unable to start Inotify watcher: $!";

			$i->watch(SQUEEZEPLAY_PREFS, Linux::Inotify2::IN_MOVE() | Linux::Inotify2::IN_MODIFY(), sub {
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

		Slim::Utils::Log::logError("Squeezeplay <-> Server prefs syncing failed to initialize: $@") if ($@);
	}
}

# add media name to the libraryname
sub _updateLibraryname {
	require Slim::Utils::Strings;
	
	my $prefs = $_[0];
	my $libraryname = $prefs->get('libraryname');
	
	# remove media name
	$libraryname =~ s/ \(.*?(?:USB|SD).*?\)$//i;

	# XXX - for the time being we're going to assume that the embedded server will only handle one folder
	my $audiodir = Slim::Utils::Misc::getAudioDirs()->[0];
	if ( $audiodir && $audiodir =~ m{/(mmcblk|sd[a-z]\d)}i ) {
		$libraryname = sprintf( "%s (%s)", $libraryname, Slim::Utils::Strings::getString($1 =~ /mmc/ ? 'SD' : 'USB') );
	}
	
	$prefs->set('libraryname', $libraryname);
}

sub _syncPrefs {
	my $file = shift;

	if ($file && $prefSyncHandlers{$file} && -r $file ) {

		require File::Slurp;

		my $data = File::Slurp::read_file($file);
		
		# bug 15882 - SP writes files with UTF-8 encoding
		utf8::decode($data);
		
		&{ $prefSyncHandlers{$file} }(\$data);
	}
}


sub sqlHelperClass { 'Slim::Utils::SQLiteHelper' }

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the server directories we
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
			RSSNews Podcast InfoBrowser
			RS232 Visualizer SlimTris Snow NetTest

			Extensions JiveExtras
			
			iTunes MusicMagic PreventStandby Rescan TT xPL
			
			UPnP ImageBrowser
		),
		$class->SUPER::skipPlugins(),
	);
}

sub _setupMediaDir {
	my ( $path, $prefs ) = @_;
	
	# Is audiodir defined, mounted and writable?
	if ($path && $path =~ m{^/media/[^/]+} && -w $path) {

		require File::Slurp;

		my $mounts = grep /$path/, split /\n/, File::Slurp::read_file('/proc/mounts');

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
		
		$prefs->set( mediadirs       => [ $path ] );
		$prefs->set( librarycachedir => "$path/.Squeezebox/cache" );

		# reset dbsource, it needs to be re-configured
		$prefs->set( 'dbsource', '' );
		
		# Create a playlist dir if necessary
		my $playlistdir = "$path/Playlists";
		
		if ( -f $playlistdir ) {
			$playlistdir .= 'Squeezebox';
		}

		if ( !-d $playlistdir ) {
			mkdir $playlistdir or warn "Couldn't create playlist directory: $playlistdir - $!\n";
		}
		
		$prefs->set( playlistdir => $playlistdir );
		
		return 1;
	}
	
	return 0;
}

sub _onAudiodirChange {
	require Slim::Utils::Prefs;
	my $prefs = Slim::Utils::Prefs::preferences('server');

	# XXX - for the time being we're going to assume that the embedded server will only handle one folder
	my $audiodir = Slim::Utils::Misc::getAudioDirs()->[0];
	
	if ($audiodir) {
		if (_setupMediaDir($audiodir, $prefs)) {
			# hunky dory
			return;
		} else {
			# it is defined but not valid
			warn "$audiodir cannot be used";
			$prefs->set('mediadirs', []);
		}
	}
}

sub _checkMediaAtStartup {
	my $prefs = shift;
	
	# Always read audiodir first from /etc/squeezecenter/prefs.json
	my $audiodir = '';
	if ( -e SP_PREFS_JSON ) {
		require File::Slurp;
		require JSON::XS;
		
		my $spPrefs = eval { JSON::XS::decode_json( File::Slurp::read_file(SP_PREFS_JSON) ) };
		if ( $@ ) {
			warn "Unable to read prefs.json: $@\n";
		}
		else {
			$audiodir = $spPrefs->{audiodir};
		}
	}
	
	# XXX SP should store audiodir and mountpath values
	# mediapath is always the root of the drive and where we store the .Squeezebox dir
	# audiodir may be any other dir, but .Squeezebox dir is not put there
	
	if ( _setupMediaDir($audiodir, $prefs) ) {
		# hunky dory
		return;
	}
	
	# Something went wrong, don't use this audiodir
	$prefs->set('mediadirs', []);
}

# Update system time if difference between system and SN time is bigger than 15 seconds
sub _onSNTimediffChange {
	my $pref = shift;
	my $diff = shift;

	if( abs( $diff) > 15) {
		Slim::Utils::OS::SqueezeOS->settimeofday( time() + $diff);
	}
}

# don't download/cache firmware for other players, but have them download directly
sub directFirmwareDownload { 1 };

# Path to progress JSON file
sub progressJSON { SP_SCAN_JSON }

# This is a bit of a hack to call the settimeofday() syscall to set the system time
# without the need to shell out to another process.
sub settimeofday {
	my ( $class, $epoch ) = @_;
	
	eval {
		# int settimeofday(const struct timeval *tv , const struct timezone *tz);
		# struct timeval is long, long
		# struct timezone is int, int, but ignored
		my $ret = syscall( 79, pack('LLLL', $epoch, 0, 0, 0), 0 );
		if ( $ret != 0 ) {
			die $!;
		}
	};
	
	if ( $@ ) {
		Slim::Utils::Log::logWarning("settimeofday($epoch) failed: $@");
	} else {
		Slim::Utils::Timers::timeChanged();
	}
}

sub canAutoRescan { 1 };

1;
