package Slim::Utils::Update;

use strict;
use Time::HiRes;
use File::Spec::Functions qw(splitpath catdir);

use Slim::Utils::Log;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;
use Slim::Utils::Unicode;

if (main::NOMYSB) {
	require Slim::Networking::Repositories;
}

my $prefs = preferences('server');

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'server.update',
	'defaultLevel' => 'ERROR',
});

my $os = Slim::Utils::OSDetect->getOS();

my $versionFile;

sub checkVersion {
	my $cb = shift;
	
	# clean up old download location
	Slim::Utils::Misc::deleteFiles($prefs->get('cachedir'), qr/^(?:Squeezebox|SqueezeCenter|LogitechMediaServer).*\.(pkg|dmg|exe)(\.tmp)?$/i);

	Slim::Utils::Timers::killTimers(0, \&checkVersion);			

	# don't check for updates when running from the source
	if ($os->runningFromSource) {
		main::INFOLOG && $log->is_info && $log->info("We're running from the source - don't check for updates");
		return;
	}
	
	return unless $prefs->get('checkVersion') || $cb;

	my $installer = getUpdateInstaller() || '';
	
	# reset update download status in case our system is up to date
	if ( $installer && installerIsUpToDate($installer) ) {
		
		main::INFOLOG && $log->info("We're up to date (v$::VERSION, $::REVISION). Reset update notifiers.");
		
		$::newVersion = undef;
		setUpdateInstaller();
	}
	
	$os->initUpdate() if $os->canAutoUpdate() && $prefs->get('autoDownloadUpdate');

	my $lastTime = $prefs->get('checkVersionLastTime');

	if ($lastTime && !$cb) {

		my $delta = Time::HiRes::time() - $lastTime;

		if (($delta > 0) && ($delta < $prefs->get('checkVersionInterval'))) {

			if ( main::INFOLOG && $log->is_info ) {
				$log->info(sprintf("Checking version in %s seconds",
					($lastTime + $prefs->get('checkVersionInterval') + 2 - Time::HiRes::time())
				));
			}

			Slim::Utils::Timers::setTimer(0, $lastTime + $prefs->get('checkVersionInterval') + 2, \&checkVersion);

			return;
		}
	}

	main::INFOLOG && $log->info("Checking version now.");

	my $url = main::NOMYSB ? (Slim::Networking::Repositories->getUrlForRepository('servers') . "$::VERSION/servers.xml") : (Slim::Networking::SqueezeNetwork->url('') . '/update/');
	
	$url .= sprintf(
		"?version=%s&revision=%s&lang=%s&geturl=%s&os=%s&uuid=%s&pcount=%d", 
		$::VERSION, 
		$::REVISION, 
		Slim::Utils::Strings::getLanguage(),
		$os->canAutoUpdate() && $prefs->get('autoDownloadUpdate') ? '1' : '0',
		$os->canAutoUpdate() ? $os->installerOS() : '',
		$prefs->get('server_uuid'),
		Slim::Player::Client::clientCount(),
	);
	
	main::DEBUGLOG && $log->debug("Using URL: $url");
	
	my $params = {
		cb => $cb
	};
	
	my $http = main::NOMYSB 
		? Slim::Networking::SimpleAsyncHTTP->new(\&checkVersionCB, \&checkVersionError, $params)
		: Slim::Networking::SqueezeNetwork->new(\&checkVersionCB, \&checkVersionError, $params);
		
	$http->get($url);

	$prefs->set('checkVersionLastTime', Time::HiRes::time());
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $prefs->get('checkVersionInterval'), \&checkVersion);
}

# called when check version request is complete
sub checkVersionCB {
	my $http = shift;
	my $cb = $http->params('cb');

	my $version;

	# store result in global variable, to be displayed by browser
	if ($http->code =~ /^2\d\d/) {

		my $content = Slim::Utils::Unicode::utf8decode( $http->content() );
		
		# Update checker logic is hosted on mysb.com. Once this is gone, we'll have to deal with it on our own.
		if (main::NOMYSB) {
			require XML::Simple;
			my $versions = XML::Simple::XMLin($content);
			
			my $osID = $os->installerOS() || 'default';
			
			main::DEBUGLOG && $log->is_debug && $log->debug("Got list of installers:\n" . Data::Dump::dump($versions));
			
			if ( my $update = $versions->{ $osID } ) {
				if ( $update->{version} && $update->{revision} ) {
					if ( Slim::Utils::Versions->compareVersions($update->{version}, $::VERSION) > 0 || $update->{revision} > $::REVISION ) {
						if ( $osID ne 'default' && $prefs->get('autoDownloadUpdate') ) {
							$version = $update->{url};
							
							# prepend URL with our download host if we didn't get an absolute URL
							$version = Slim::Networking::Repositories->getUrlForRepository('servers') . $version unless $version =~ /^http/;
						}
						else {
							$version = Slim::Utils::Strings::string('SERVER_UPDATE_AVAILABLE', $update->{version}, $update->{url});
						}
					}
				}
			}
		}
		else {
			chomp($content);
			$version = $content;
		}
		
		$version ||= 0;
		
		main::DEBUGLOG && $log->debug($version || 'No new Logitech Media Server version available');

		# reset the update flag
		setUpdateInstaller();

		# trigger download of the installer if available
		if ($version && $prefs->get('autoDownloadUpdate')) {
			
			main::INFOLOG && $log->info('Triggering automatic Logitech Media Server update download...');
			getUpdate($version);
		}
		
		# if we got an update with download URL, display it in the web UI et al.
		elsif ($version && $version =~ /a href="downloads.slimdevices/i) {
			$::newVersion = $version;
		}
	}
	else {
		$::newVersion = 0;
		$log->warn(sprintf(Slim::Utils::Strings::string('CHECKVERSION_PROBLEM'), $http->code));
	}
	
	$cb->($version) if $cb && ref $cb;
}

# called only if check version request fails
sub checkVersionError {
	my $http = shift;

	my $proxy = $prefs->get('webproxy');

	$log->error(Slim::Utils::Strings::string('CHECKVERSION_ERROR')
		. "\n" . $http->error
		. ($proxy ? sprintf("\nPlease check your proxy configuration (%s)", $proxy) : '')
	);
}


# download the installer
sub getUpdate {
	my $url = shift;
	
	my $params = $os->getUpdateParams($url);
	
	return unless $params;
	
	$params->{path} ||= scalar ( $os->dirsFor('updates') );
	
	cleanup($params->{path}, 'tmp');

	if ( $url && Slim::Music::Info::isURL($url) ) {
		
		main::INFOLOG && $log->info("URL to download update from: $url");

		my ($a, $b, $file) = Slim::Utils::Misc::crackURL($url);
		($a, $b, $file) = splitpath($file);

		# don't re-download if we're up to date
		if (installerIsUpToDate($file)) {
			main::INFOLOG && $log->info("We're up to date (v$::VERSION, $::REVISION). Reset update notifiers.");
			
			setUpdateInstaller();
			return;
		}

		$file = catdir($params->{path}, $file);

		# don't re-download if file exists already
		if ( -e $file ) {
			main::INFOLOG && $log->info("We already have the latest installer file: $file");
			
			setUpdateInstaller($file, $params->{cb});
			return;
		}
		
		my $tmpFile = "$file.tmp";

		setUpdateInstaller();
		
		main::DEBUGLOG && $log->is_debug && $log->debug("Downloading...\n   URL:      $url\n   Save as:  $tmpFile\n   Filename: $file");

		# Save to a tmp file so we can check SHA
		my $download = Slim::Networking::SimpleAsyncHTTP->new(
			\&downloadAsyncDone,
			\&checkVersionError,
			{
				saveAs => $tmpFile,
				file   => $file,
				params => $params,
			},
		);
		
		$download->get( $url );
	}
	else {
		$log->error("Didn't receive valid update URL: " . substr($url, 0, 50) . (length($url) > 50 ? '...' : ''));
	}
}

sub downloadAsyncDone {
	my $http = shift;
	
	my $file    = $http->params('file');
	my $tmpFile = $http->params('saveAs');
	my $params  = $http->params('params') || {};
	
	my $path    = $params->{'path'};
	
	# make sure we got the file
	if (!-e $tmpFile) {
		$log->warn("Logitech Media Server installer download failed: file '$tmpFile' not stored on disk?!?");
		return;
	}

	if (-s _ != $http->headers->content_length()) {
		$log->warn( sprintf("Logitech Media Server installer file size mismatch: expected size %s bytes, actual size %s bytes", $http->headers->content_length(), -s _) );
		unlink $tmpFile;
		return;
	}

	cleanup($path);

	main::INFOLOG && $log->is_info && $log->info("Successfully downloaded update installer file '$tmpFile'. Saving as $file");
	unlink $file;
	my $success = rename $tmpFile, $file;
	
	if (-e $file) {
		setUpdateInstaller($file, $params->{cb}) ;
	}
	elsif (!$success) {
		$log->warn("Renaming '$tmpFile' to '$file' failed.");
	}
	else {
		$log->warn("There was an unknown error downloading/storing the update installer.");
	}

	cleanup($path, 'tmp');
}

sub setUpdateInstaller {
	my ($file, $cb) = @_;
	
	$versionFile ||= getVersionFile();
	
	if ($file && open(UPDATEFLAG, ">$versionFile")) {
		
		main::DEBUGLOG && $log->debug("Setting update version file to: $file");
		
		print UPDATEFLAG $file;
		close UPDATEFLAG;

		if ($cb && ref($cb) eq 'CODE') {
			$cb->($file);
		}
		
		$::newVersion ||= string('SERVER_UPDATE_AVAILABLE_SHORT');
	}
	
	elsif ($file) {
		
		$log->warn("Unable to update version file: $versionFile");
	}
	
	else {
	
		unlink $versionFile;
	}
}

sub getVersionFile {
	$versionFile ||= catdir( scalar($os->dirsFor('updates')), 'server.version' );
	return $versionFile;
}


sub getUpdateInstaller {
	
	return unless $prefs->get('autoDownloadUpdate');
	
	$versionFile ||= getVersionFile();
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Reading update installer path from $versionFile");
	
	open(UPDATEFLAG, $versionFile) || do {
		main::DEBUGLOG && $log->is_debug && $log->debug("No '$versionFile' available.");
		return '';	
	};
	
	my $updateInstaller = '';
	
	local $_;
	while ( <UPDATEFLAG> ) {

		chomp;
		
		if (/(?:LogitechMediaServer|Squeezebox|SqueezeCenter).*/) {
			$updateInstaller = $_;
			last;
		}
	}
		
	close UPDATEFLAG;
	
	main::DEBUGLOG && $log->debug("Found update installer path: '$updateInstaller'");
	
	return $updateInstaller;
}

sub installerIsUpToDate {
	
	return unless $prefs->get('autoDownloadUpdate');

	my $installer = shift || '';

	return ( $installer =~ /$::REVISION/ && $installer =~ /$::VERSION/ );	# same revision and revision
}

sub cleanup {
	my ($path, $additionalExt) = @_;

	my $ext = $os->installerExtension() . ($additionalExt ? "\.$additionalExt" : '');

	Slim::Utils::Misc::deleteFiles($path, qr/^(?:LogitechMediaServer|Squeezebox|SqueezeCenter).*\.$ext$/i);
}

1;