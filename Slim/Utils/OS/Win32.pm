package Slim::Utils::OS::Win32;

use strict;
use File::Path;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use Scalar::Util qw(blessed);
use Win32;
use Win32::OLE::NLS;
use POSIX qw(LC_CTYPE LC_TIME);

use base qw(Slim::Utils::OS);

my $driveList  = {};
my $driveState = {};
my $writablePath;

sub name {
	return 'win';
}

sub initDetails {
	my $class = shift;
	
	$class->{osDetails} = {
		'os'     => 'Windows',

		'osName' => (Win32::GetOSName())[0],

		'osArch' => Win32::GetChipName(),

		'uid'    => Win32::LoginName(),

		'fsType' => (Win32::FsType())[0],
	};

	# Do a little munging for pretty names.
	$class->{osDetails}->{'osName'} =~ s/Win/Windows /;
	$class->{osDetails}->{'osName'} =~ s/\/.Net//;
	$class->{osDetails}->{'osName'} =~ s/2003/Server 2003/;
	
	# TODO: remove this code as soon as Win32::GetOSName supports Windows 2008 Server
	if ($class->{osDetails}->{'osName'} =~ /Vista/i && (Win32::GetOSVersion())[8] > 1) {
		$class->{osDetails}->{'osName'} = 'Windows 2008 Server';
	}
	
	$class->{osDetails}->{isVista} = 1 if $class->{osDetails}->{'osName'} =~ /Vista/;

	return $class->{osDetails};
}

sub initSearchPath {
	my $class = shift;

	$class->SUPER::initSearchPath();
	
	# TODO: we might want to make this a bit more intelligent
	# as Perl is not always in that folder (eg. German Windows)
	
	Slim::Utils::Misc::addFindBinPaths('C:\Perl\bin');
}

sub dirsFor {
	my ($class, $dir) = @_;
	
	my @dirs = $class->SUPER::dirsFor($dir);
	
	if ($dir =~ /^(?:strings|revision|convert|types)$/) {

		push @dirs, $Bin;

	} elsif ($dir eq 'log') {

		push @dirs, $::logdir || $class->writablePath('Logs');

	} elsif ($dir eq 'cache') {

		push @dirs, $::cachedir || $class->writablePath('Cache');

	} elsif ($dir eq 'oldprefs') {

		if ($::prefsfile && -r $::prefsfile) {

			push @dirs, $::prefsfile;
		} 
		
		else {

			if ($class->{osDetails}->{isVista} && -r catdir($class->writablePath(), 'slimserver.pref')) {

				push @dirs, catdir($class->writablePath(''), 'slimserver.pref');
			}
			
			elsif (-r catdir($Bin, 'slimserver.pref'))  {

				push @dirs, catdir($Bin, 'slimserver.pref');
			}
		}

	} elsif ($dir eq 'prefs') {

		push @dirs, $::prefsdir || $class->writablePath('prefs');

	} elsif ($dir =~ /^(?:music|playlists)$/) {

		my $path = Win32::GetFolderPath(Win32::CSIDL_MYMUSIC);
		
		# fall back if no path or invalid path is returned
		if (!$path || $path eq Win32::GetFolderPath(0)) {
	
			my $swKey = $Win32::TieRegistry::Registry->Open(
				'CUser/Software/Microsoft/Windows/CurrentVersion/Explorer/Shell Folders/', 
				{ 
					Access => Win32::TieRegistry::KEY_READ(), 
					Delimiter =>'/' 
				}
			);
	
			if (defined $swKey) {
				if (!($path = $swKey->{'My Music'})) {
					if ($path = $swKey->{'Personal'}) {
						$path = $path . '/My Music';
					}
				}
			}
		}

		if ($path && $dir eq 'playlists') {
			$path .= '/Playlists';
		}

		push @dirs, $path;

	# we don't want these values to return a value
	} elsif ($dir =~ /^(?:libpath|mysql-language)$/) {

	} else {

		push @dirs, catdir($Bin, $dir);
	}

	return wantarray() ? @dirs : $dirs[0];
}

sub decodeExternalHelperPath {
	return Win32::GetShortPathName($_[1]);
}

sub scanner {
	return -x "$Bin/scanner.exe" ? "$Bin/scanner.exe" : $_[0]->SUPER::scanner();
}

sub localeDetails {
	require Win32::Locale;

	my $langid = Win32::OLE::NLS::GetSystemDefaultLCID();
	my $lcid   = Win32::OLE::NLS::MAKELCID($langid);
	my $linfo  = Win32::OLE::NLS::GetLocaleInfo($lcid, Win32::OLE::NLS::LOCALE_IDEFAULTANSICODEPAGE());

	my $lc_ctype = "cp$linfo";
	my $locale   = Win32::Locale::get_locale($langid);
	my $lc_time  = POSIX::setlocale(LC_TIME, $locale);
	
	return ($lc_ctype, $lc_time);
}

sub getSystemLanguage {
	my $class = shift;
	$class->_parseLanguage(Win32::Locale::get_language()); 
}

sub dontSetUserAndGroup { 1 }

sub getProxy {
	my $class = shift;
	my $proxy = '';

	require Win32::TieRegistry;

	# on Windows read Internet Explorer's proxy setting
	my $ieSettings = $Win32::TieRegistry::Registry->Open(
		'CUser/Software/Microsoft/Windows/CurrentVersion/Internet Settings',
		{ 
			Access => Win32::TieRegistry::KEY_READ(), 
			Delimiter =>'/' 
		}
	);

	if (defined $ieSettings && hex($ieSettings->{'ProxyEnable'})) {
		$proxy = $ieSettings->{'ProxyServer'};
	}

	return $proxy || $class->SUPER::getProxy();
}

sub ignoredItems {
	return (
		# Items we should ignore  on a Windows volume
		'System Volume Information' => '/',
		'RECYCLER' => '/',
		'Recycled' => '/',	
	);
}


=head2 getDrives()

Returns a list of drives available to SqueezeCenter, filtering out floppy drives etc.

=cut

sub getDrives {

	if (!defined $driveList->{ttl} || !$driveList->{drives} || $driveList->{ttl} < time) {
		require Win32API::File;;
	
		my @drives = grep {
			s/\\//;
	
			my $driveType = Win32API::File::GetDriveType($_);
			Slim::Utils::Log::logger('os.paths')->debug("Drive of type '$driveType' found: $_");
	
			# what USB drive is considered REMOVABLE, what's FIXED?
			# have an external HDD -> FIXED, USB stick -> REMOVABLE
			# would love to filter out REMOVABLEs, but I'm not sure it's save
			#($driveType != DRIVE_UNKNOWN && $driveType != DRIVE_REMOVABLE);
			($driveType != Win32API::File->DRIVE_UNKNOWN && /[^AB]:/i);
		} Win32API::File::getLogicalDrives();
		
		$driveList = {
			ttl    => time() + 60,
			drives => \@drives
		}
	}

	return @{ $driveList->{drives} };
}

=head2 isDriveReady()

Verifies whether a drive can be accessed or not

=cut

sub isDriveReady {
	my ($class, $drive) = @_;

	# shortcut - we've already tested this drive	
	if (!defined $driveState->{$drive} || $driveState->{$drive}->{ttl} < time) {

		$driveState->{$drive} = {
			state => 0,
			ttl   => time() + 60	# cache state for a minute
		};

		# don't check inexisting drives
		if (scalar(grep /$drive/, $class->getDrives()) && -r $drive) {
			$driveState->{$drive}->{state} = 1;
		}

		Slim::Utils::Log::logger('os.paths')->debug("Checking drive state for $drive");
		Slim::Utils::Log::logger('os.paths')->debug('      --> ' . ($driveState->{$drive}->{state} ? 'ok' : 'nok'));
	}
	
	return $driveState->{$drive}->{state};
}

=head2 writablePath()

Returns a path which is expected to be writable by all users on Windows without virtualisation on Vista.
This should mean that the server always sees consistent versions of files under this path.

TODO: this needs to be rewritten to use the proper API calls instead of poking around the registry and environment!

=cut

sub writablePath {
	my ($class, $folder) = @_;
	my $path;

	unless ($writablePath) {
		require Win32::TieRegistry;

		# use the "Common Application Data" folder to store SqueezeCenter configuration etc.
		# c:\documents and settings\all users\application data - on Windows 2000/XP
		# c:\ProgramData - on Vista
		my $swKey = $Win32::TieRegistry::Registry->Open(
			'LMachine/Software/Microsoft/Windows/CurrentVersion/Explorer/Shell Folders/', 
			{ 
				Access => Win32::TieRegistry::KEY_READ(), 
				Delimiter =>'/' 
			}
		);
	
		if (defined $swKey && $swKey->{'Common AppData'}) {
			$writablePath = catdir($swKey->{'Common AppData'}, 'SqueezeCenter');
		}
		elsif ($ENV{'ProgramData'}) {
			$writablePath = catdir($ENV{'ProgramData'}, 'SqueezeCenter');
		}
		else {
			$writablePath = $Bin;
		}

		if (! -d $writablePath) {
			mkdir $writablePath;
		}
	}

	$path = catdir($writablePath, $folder);

	mkdir $path unless -d $path;

	return $path;
}

=head2 pathFromWinShortcut( $path )

Return the filepath for a given Windows Shortcut

=cut

sub pathFromWinShortcut {
	my $class    = shift;
	my $fullpath = Slim::Utils::Misc::pathFromFileURL(shift);

	require Win32::Shortcut;

	my $path     = "";
	my $shortcut = Win32::Shortcut->new($fullpath);

	if (defined($shortcut)) {

		$path = $shortcut->Path();

		# the following pattern match throws out the path returned from the
		# shortcut if the shortcut is contained in a child directory of the path
		# to avoid simple loops, loops involving more than one shortcut are still
		# possible and should be dealt with somewhere, just not here.
		if (defined($path) && !$path eq "" && $fullpath !~ /^\Q$path\E/i) {

			$path = Slim::Utils::Misc::fileURLFromPath($path);

			#collapse shortcuts to shortcuts into a single hop
			if (Slim::Music::Info::isWinShortcut($path)) {
				$path = $class->pathFromWinShortcut($path);
			}

		} else {

			Slim::Utils::Log::logger('os.files')->error("Error: Bad path in $fullpath - path was: [$path]");
		}

	} else {

		Slim::Utils::Log::logger('os.files')->error("Error: Shortcut $fullpath is invalid");
	}

	return $path;
}


=head2 setPriority( $priority )

Set the priority for the server. $priority should be -20 to 20

=cut

sub setPriority {
	my ($class, $priority) = @_;

	return unless defined $priority && $priority =~ /^-?\d+$/;

	Slim::bootstrap::tryModuleLoad('Win32::API', 'Win32::Process', 'nowarn');

	# For win32, translate the priority to a priority class and use that
	my ($priorityClass, $priorityClassName) = _priorityClassFromPriority($priority);

	my $getCurrentProcess = Win32::API->new('kernel32', 'GetCurrentProcess', ['V'], 'N');
	my $setPriorityClass  = Win32::API->new('kernel32', 'SetPriorityClass',  ['N', 'N'], 'N');

	if (blessed($setPriorityClass) && blessed($getCurrentProcess)) {

		my $processHandle = eval { $getCurrentProcess->Call(0) };

		if (!$processHandle || $@) {

			Slim::Utils::Log->logError("Can't get process handle ($^E) [$@]");
			return;
		};

		Slim::Utils::Log::logger('server')->info("SqueezeCenter changing process priority to $priorityClassName");

		eval { $setPriorityClass->Call($processHandle, $priorityClass) };

		if ($@) {
			Slim::Utils::Log->logError("Couldn't set priority to $priorityClassName ($^E) [$@]");
		}
	}
}

=head2 getPriority( )

Get the current priority of the server.

=cut

sub getPriority {

	Slim::bootstrap::tryModuleLoad('Win32::API', 'Win32::Process', 'nowarn');

	my $getCurrentProcess = Win32::API->new('kernel32', 'GetCurrentProcess', ['V'], 'N');
	my $getPriorityClass  = Win32::API->new('kernel32', 'GetPriorityClass',  ['N'], 'N');

	if (blessed($getPriorityClass) && blessed($getCurrentProcess)) {

		my $processHandle = eval { $getCurrentProcess->Call(0) };

		if (!$processHandle || $@) {

			Slim::Utils::Log->logError("Can't get process handle ($^E) [$@]");
			return;
		};

		my $priorityClass = eval { $getPriorityClass->Call($processHandle) };

		if ($@) {
			Slim::Utils::Log->logError("Can't get priority class ($^E) [$@]");
		}

		return _priorityFromPriorityClass($priorityClass);
	}
}

# Translation between win32 and *nix priorities
# is as follows:
# -20  -  -16  HIGH
# -15  -   -6  ABOVE NORMAL
#  -5  -    4  NORMAL
#   5  -   14  BELOW NORMAL
#  15  -   20  LOW

sub _priorityClassFromPriority {
	my $priority = shift;

	# ABOVE_NORMAL_PRIORITY_CLASS and BELOW_NORMAL_PRIORITY_CLASS aren't
	# provided by Win32::Process so their values have been hardcoded.

	if ($priority <= -16 ) {
		return (Win32::Process::HIGH_PRIORITY_CLASS(), "HIGH");
	} elsif ($priority <= -6) {
		return (0x00008000, "ABOVE_NORMAL");
	} elsif ($priority <= 4) {
		return (Win32::Process::NORMAL_PRIORITY_CLASS(), "NORMAL");
	} elsif ($priority <= 14) {
		return (0x00004000, "BELOW_NORMAL");
	} else {
		return (Win32::Process::IDLE_PRIORITY_CLASS(), "LOW");
	}
}

sub _priorityFromPriorityClass {
	my $priorityClass = shift;

	if ($priorityClass == 0x00000100) { # REALTIME
		return -20;
	} elsif ($priorityClass == Win32::Process::HIGH_PRIORITY_CLASS()) {
		return -16;
	} elsif ($priorityClass == 0x00008000) {
		return -6;
	} elsif ($priorityClass == 0x00004000) {
		return 5;
	} elsif ($priorityClass == Win32::Process::IDLE_PRIORITY_CLASS()) {
		return 15;
	} else {
		return 0;
	}
}



1;