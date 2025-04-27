package Slim::Utils::Update;

use strict;
use File::Slurp qw(write_file);
use Time::HiRes;
use Digest::MD5;
use File::Spec::Functions qw(splitpath catdir);
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;
use Slim::Utils::Unicode;

use constant REPOSITORY_URL => 'https://lms-community.github.io/lms-server-repository/servers.json';

my $prefs = preferences('server');

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'server.update',
	'defaultLevel' => 'ERROR',
});

my $os = Slim::Utils::OSDetect->getOS();

my $versionFile;

sub checkVersion {
	my $cb = shift;

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

	Slim::Networking::SimpleAsyncHTTP->new(
		\&checkVersionCB,
		\&checkVersionError,
		{
			cb => $cb
		}
	)->get(REPOSITORY_URL);

	$prefs->set('checkVersionLastTime', Time::HiRes::time());
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $prefs->get('checkVersionInterval'), \&checkVersion);
}

# called when check version request is complete
sub checkVersionCB {
	my $http = shift;
	my $cb = $http->params('cb');

	my ($version, $md5);

	# store result in global variable, to be displayed by browser
	if ($http->code =~ /^2\d\d/) {

		my $content = Slim::Utils::Unicode::utf8decode( $http->content() );

		my $versions = from_json($content);

		my $osID = $os->installerOS() || 'default';
		$versions = $versions->{$::VERSION} || $versions->{latest};

		main::DEBUGLOG && $log->is_debug && $log->debug("Got list of installers:\n" . Data::Dump::dump($versions));

		if ( my $update = $versions->{ $osID } ) {
			if ( $update->{version} && $update->{revision} ) {
				if ( Slim::Utils::Versions->compareVersions($update->{version}, $::VERSION) > 0 || $update->{revision} > $::REVISION ) {
					if ( $osID ne 'default' && $prefs->get('autoDownloadUpdate') ) {
						$version = $update->{url};
						$md5 = $update->{md5};
					}
					else {
						$version = Slim::Utils::Strings::string('SERVER_UPDATE_AVAILABLE', $update->{version}, $update->{url});
					}
				}
			}
		}

		$version ||= 0;

		main::DEBUGLOG && $log->debug($version || 'No new Lyrion Music Server version available');

		# reset the update flag
		setUpdateInstaller();

		# trigger download of the installer if available
		if ($version && $prefs->get('autoDownloadUpdate')) {

			main::INFOLOG && $log->info('Triggering automatic Lyrion Music Server update download...');
			getUpdate($version, $md5);
		}

		# if we got an update with download URL, display it in the web UI et al.
		elsif ($version && $version =~ /a href="(http.*\bdownloads\.[^"]+)/i) {
			$prefs->set('serverUpdateAvailable', $1);
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
	my ($url, $md5) = @_;

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
				md5    => $md5,
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
	my $md5     = $http->params('md5');

	my $path    = $params->{'path'};

	# make sure we got the file
	if (!-e $tmpFile) {
		$log->warn("Installer download failed: file '$tmpFile' not stored on disk?!?");
		return;
	}

	if (-s _ != $http->headers->content_length()) {
		$log->warn( sprintf("Installer file size mismatch: expected size %s bytes, actual size %s bytes", $http->headers->content_length(), -s _) );
		unlink $tmpFile;
		return;
	}

	if ($md5) {
		my $digest;
		eval {
			# "With OO style, you can break the message arbitrarily. This means that we are no longer limited
			#  to have space for the whole message in memory, i.e. we can handle messages of any size."
			# https://metacpan.org/pod/Digest::MD5#EXAMPLES
			my $md5 = Digest::MD5->new;
			open my $fh, '<:raw', $tmpFile;
			while (<$fh>) {
				$md5->add($_);
			}
			close $fh;
			$digest = $md5->hexdigest;
		};

		if ($@) {
			$log->error("Error calculating MD5 checksum: $@");
		}
		elsif (main::DEBUGLOG && $log->is_debug) {
			$log->debug("Verified expected MD5 checksum: $digest");
		}

		if ($digest ne $md5) {
			$log->warn("Installer file checksum mismatch: expected $md5, got $digest");
			unlink $tmpFile;
			return;
		}
	}

	cleanup($path);

	if (main::INFOLOG && $log->is_info) {
		$log->info("Successfully downloaded update installer file '$tmpFile'.");
		$log->info("Saving as $file");
	}

	unlink $file;
	my $success = rename $tmpFile, $file;
	if ($md5) {
		my ($a, $b, $filename) = splitpath($file);
		write_file($file . '.md5.txt', "$md5  $filename");
	}

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
	$versionFile ||= catdir( scalar $os->dirsFor('updates'), 'server.version' );
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

		if (/LyrionMusicServer.*/i) {
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

	Slim::Utils::Misc::deleteFiles($path, qr/^LyrionMusicServer.*\.$ext(\.md5\.txt)?$/i);
}

1;