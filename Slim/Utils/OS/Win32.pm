package Slim::Utils::OS::Win32;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(catdir);
use FindBin qw($Bin);
use Sys::Hostname qw(hostname);
use Win32;
use Win32::OLE;
use Win32::OLE::NLS;
use Win32::TieRegistry ('Delimiter' => '/');

use base qw(Slim::Utils::OS);

my $driveList  = {};
my $driveState = {};
my $writablePath;

sub name {
	return 'win';
}

sub initDetails {
	my $class = shift;

	# better version detection than relying on Win32::GetOSName()
	# http://msdn.microsoft.com/en-us/library/ms724429(VS.85).aspx
	my ($string, $major, $minor, $build, $id, $spmajor, $spminor, $suitemask, $producttype) = Win32::GetOSVersion();
	
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
	if ($major == 6 && $minor == 0 && $producttype > 1) {
		$class->{osDetails}->{'osName'} = 'Windows 2008 Server';
	}

	# Windows 2003 && suitemask 0x00008000 -> WHS
	# http://msdn.microsoft.com/en-us/library/ms724833(VS.85).aspx
	elsif ($major == 5 && $minor == 2
			&& $suitemask && $suitemask >= 0x00008000 && $suitemask < 0x00009000) {
		$class->{osDetails}->{'osName'} = 'Windows Home Server';
		$class->{osDetails}->{'isWHS'} = 1;
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

sub initMySQL {}

sub initPrefs {
	my ($class, $prefs) = @_;

	# try to find the user's real name instead of the username
	$prefs->{libraryname} = sub {

		# WHS is always running SC as the SYSTEM user - return immediately
		return '' if $class->{osDetails}->{isWHS};

		my $username = $ENV{'USERNAME'} || $ENV{'USER'} || $ENV{'LOGNAME'};

		my %userinfo;

		if ($username) {
			require Win32API::Net;
			Win32API::Net::UserGetInfo($ENV{'LOGONSERVER'}, $username, 10, \%userinfo);
		}
		
		return $userinfo{fullName} || $username;
	};
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

	} elsif ($dir eq 'base') {

		push @dirs, $class->installPath();

	} elsif ($dir eq 'prefs') {

		push @dirs, $::prefsdir || $class->writablePath('prefs');

	} elsif ($dir =~ /^(?:music|playlists)$/) {

		my $path;

		# Windows Home Server offers a Music share which is more likely to be used 
		# than the administrator's My Music folder
		if ($class->{osDetails}->{isWHS}) {
			my $objWMI = Win32::OLE->GetObject('winmgmts://./root/cimv2');
			
			if ( $objWMI && (my $shares = $objWMI->InstancesOf('Win32_Share')) ) {
				
				my $path2;
				foreach my $objShare (in $shares) {

					# let's be a bit more open for localized versions: musica, Musik, musique...
					if ($objShare->Name =~ /^musi(?:c|k|que|ca)$/i) {
						$path = '\\\\' . hostname() . '\\' . $objShare->Name;
						last;
					}
					elsif ($objShare->Path =~ /shares.*?musi[ckq]/i) {
						$path = $objShare->Path;
						last;
					}
					elsif ($objShare->path =~ /musi[ckq]/i) {
						$path2 = $objShare->Path;
					}
				}
				
				undef $shares;
				
				# we didn't find x:\shares\music, but some other share with music in the path
				if ($path2 && !$path) {
					$path = $path2;
				}
			}
			
			undef $objWMI;
		}

		$path = Win32::GetFolderPath(Win32::CSIDL_MYMUSIC) unless $path;
		
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
						$path = catdir($path, 'My Music');
					}
				}
			}
		}

		if ($path && $dir eq 'playlists') {
			$path = catdir($path, 'Playlists');
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
	eval { use POSIX qw(LC_TIME); };
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

	require Win32::Locale;

	$class->_parseLanguage(Win32::Locale::get_language()); 
}

sub dontSetUserAndGroup { 1 }

sub getProxy {
	my $class = shift;
	my $proxy = '';

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

=head2 installPath()

Returns the base installation directory of SqueezeCenter.

=cut

sub installPath {

	# Try and find it in the registry.
	# This is a system-wide registry key.
	my $swKey = $Win32::TieRegistry::Registry->Open(
		'LMachine/Software/Logitech/SqueezeCenter/', 
		{ 
			Access => Win32::TieRegistry::KEY_READ(), 
			Delimiter =>'/' 
		}
	);

	if (defined $swKey && $swKey->{'Path'}) {
		return $swKey->{'Path'} if -d $swKey->{'Path'};
	}

	# Otherwise look in the standard location.
	# search in legacy SlimServer folder, too
	my $installDir;
	PF: foreach my $programFolder ($ENV{ProgramFiles}, 'C:/Program Files') {
		foreach my $ourFolder ('SqueezeCenter', 'SlimServer') {

			$installDir = File::Spec->catdir($programFolder, $ourFolder);
			last PF if (-d $installDir);

		}
	}

	return $installDir if -d $installDir;
}


=head2 writablePath()

Returns a path which is expected to be writable by all users on Windows without virtualisation on Vista.
This should mean that the server always sees consistent versions of files under this path.

=cut

sub writablePath {
	my ($class, $folder) = @_;
	my $path;

	unless ($writablePath) {

		# the installer is writing the data folder to the registry - give this the first try
		my $swKey = $Win32::TieRegistry::Registry->Open(
			'LMachine/Software/Logitech/SqueezeCenter/', 
			{ 
				Access => Win32::TieRegistry::KEY_READ(), 
				Delimiter =>'/' 
			}
		);
	
		if (defined $swKey && $swKey->{'DataPath'}) {
			$writablePath = $swKey->{'DataPath'};
		}

		else {
			# second attempt: use the Windows API (recommended by MS)
			# use the "Common Application Data" folder to store SqueezeCenter configuration etc.
			$writablePath = Win32::GetFolderPath(Win32::CSIDL_COMMON_APPDATA);
			
			# fall back if no path or invalid path is returned
			if (!$writablePath || $writablePath eq Win32::GetFolderPath(0)) {

				# third attempt: read the registry's compatibility value
				# NOTE: this key has proved to be wrong on some Vista systems
				# only here for backwards compatibility
				$swKey = $Win32::TieRegistry::Registry->Open(
					'LMachine/Software/Microsoft/Windows/CurrentVersion/Explorer/Shell Folders/', 
					{ 
						Access => Win32::TieRegistry::KEY_READ(), 
						Delimiter =>'/' 
					}
				);
			
				if (defined $swKey && $swKey->{'Common AppData'}) {
					$writablePath = $swKey->{'Common AppData'};
				}
				
				elsif ($ENV{'ProgramData'}) {
					$writablePath = $ENV{'ProgramData'};
				}

				# this point hopefully is never reached, as on most systems the program folder isn't writable...
				else {
					$writablePath = $Bin;
				}
			}
			
			$writablePath = catdir($writablePath, 'SqueezeCenter') unless $writablePath eq $Bin;
			
			# store the key in the registry for future reference
			$swKey = $Win32::TieRegistry::Registry->Open(
				'LMachine/Software/Logitech/SqueezeCenter/', 
				{ 
					Delimiter =>'/' 
				}
			);
			
			if (defined $swKey && !$swKey->{'DataPath'}) {
				$swKey->{'DataPath'} = $writablePath;
			}
		}

		if (! -d $writablePath) {
			mkdir $writablePath;
		}
	}

	$path = catdir($writablePath, $folder);

	mkdir $path unless -d $path;

	return $path;
}

=head2 pathFromShortcut( $path )

Return the filepath for a given Windows Shortcut

=cut

sub pathFromShortcut {
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
				$path = $class->pathFromShortcut($path);
			}

		} else {

			Slim::Utils::Log::logger('os.files')->error("Error: Bad path in $fullpath - path was: [$path]");
		}

	} else {

		Slim::Utils::Log::logger('os.files')->error("Error: Shortcut $fullpath is invalid");
	}

	return $path;
}

=head2 fileURLFromShortcut( $shortcut )

	Special case to convert a windows shortcut to a normalised file:// url.

=cut

sub fileURLFromShortcut {
	my ($class, $path) = @_;
	return Slim::Utils::Misc::fixPath( $class->pathFromShortcut($path) );
}

=head2 getShortcut( $shortcut )

	Return a shortcut's name and the target URL

=cut

sub getShortcut {
	my ($class, $path) = @_;
	
	my $name = Slim::Music::Info::fileName($path);
	$name =~ s/\.lnk$//i;
	
	return ( $name, $class->fileURLFromShortcut($path) );
}


=head2 setPriority( $priority )

Set the priority for the server. $priority should be -20 to 20

=cut

sub setPriority {
	my ($class, $priority) = @_;

	return unless defined $priority && $priority =~ /^-?\d+$/;

	Slim::bootstrap::tryModuleLoad('Scalar::Util', 'Win32::API', 'Win32::Process', 'nowarn');

	# For win32, translate the priority to a priority class and use that
	my ($priorityClass, $priorityClassName) = _priorityClassFromPriority($priority);

	my $getCurrentProcess = Win32::API->new('kernel32', 'GetCurrentProcess', ['V'], 'N');
	my $setPriorityClass  = Win32::API->new('kernel32', 'SetPriorityClass',  ['N', 'N'], 'N');

	if (Scalar::Util::blessed($setPriorityClass) && Scalar::Util::blessed($getCurrentProcess)) {

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

	Slim::bootstrap::tryModuleLoad('Scalar::Util', 'Win32::API', 'Win32::Process', 'nowarn');

	my $getCurrentProcess = Win32::API->new('kernel32', 'GetCurrentProcess', ['V'], 'N');
	my $getPriorityClass  = Win32::API->new('kernel32', 'GetPriorityClass',  ['N'], 'N');

	if (Scalar::Util::blessed($getPriorityClass) && Scalar::Util::blessed($getCurrentProcess)) {

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


sub getUpdateParams {
	my ($class, $url) = @_;

	return if main::SLIM_SERVICE || main::SCANNER;
	
	if (!$PerlSvc::VERSION) {
		Slim::Utils::Log::logger('server.update')->error("Running SqueezeCenter from the source - don't download the update.");
		return;
	}
	
	require Win32::NetResource;
	
	my $downloaddir;
	
	if ($class->{osDetails}->{isWHS}) {

		my $share;
		Win32::NetResource::NetShareGetInfo('software', $share);

		# this is ugly... FR uses a localized share name
		if (!$share || !$share->{path}) {
			Win32::NetResource::NetShareGetInfo('logiciel', $share);
		}
		
		if ($share && $share->{path}) {
			$downloaddir = $share->{path};

			if (-e catdir($downloaddir, "Add-Ins")) {
				$downloaddir = catdir($downloaddir, "Add-Ins");
			}
		}
	}
	
	return {
		path => $downloaddir,
	};
}

sub canAutoUpdate { 1 }

# return file extension filter for installer
sub installerExtension { '(?:exe|msi)' }; 
sub installerOS { 
	my $class = shift;
	return $class->{osDetails}->{isWHS} ? 'whs' : 'win';
}

sub restartServer {
	my $class = shift;

	my $log = Slim::Utils::Log::logger('database.mysql');
	

	if (!$class->canRestartServer()) {
		$log->error("On Windows SqueezeCenter can't be restarted when run from the perl source.");
		return;
	}
	
	if ($PerlSvc::VERSION && PerlSvc::RunningAsService()) {

		my $svcHelper = Win32::GetShortPathName( catdir( $class->installPath, 'server', 'squeezesvc.exe' ) );
		my $processObj;

		Slim::bootstrap::tryModuleLoad('Win32::Process');

		if ($@ || !Win32::Process::Create(
			$processObj,
			$svcHelper,
			"$svcHelper --restart",
			0,
			Win32::Process::DETACHED_PROCESS() | Win32::Process::CREATE_NO_WINDOW() | Win32::Process::NORMAL_PRIORITY_CLASS(),
			".")
		) {
			$log->error("Couldn't restart SqueezeCenter service (squeezesvc)");
		}
	}
	
	elsif ($PerlSvc::VERSION) {
	
		my $restartFlag = catdir($class->dirsFor('cache'), 'restart.txt');
		if (open(RESTART, ">$restartFlag")) {
			close RESTART;
			main::stopServer();
		}
		
		else {
			$log->error("Can't write restart flag ($restartFlag) - don't shut down");
		}
	}
};

sub canRestartServer { return $PerlSvc::VERSION ? 1 : 0; }

1;