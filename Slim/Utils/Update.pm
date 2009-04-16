package Slim::Utils::Update;

use strict;
use Time::HiRes;
use File::Spec::Functions qw(splitpath catdir);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;
use Slim::Utils::Unicode;

my $prefs = preferences('server');

#my $log   = logger('server.update');
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'server.update',
	'defaultLevel' => 'DEBUG',
});

sub checkVersion {
	if (!$prefs->get('checkVersion')) {

		$::newVersion = undef;
		$prefs->set('updateInstaller');
		return;
	}

	my $lastTime = $prefs->get('checkVersionLastTime');

	if ($lastTime) {

		my $delta = Time::HiRes::time() - $lastTime;

		if (($delta > 0) && ($delta < $prefs->get('checkVersionInterval'))) {

			if ( $log->is_info ) {
				$log->info(sprintf("Checking version in %s seconds",
					($lastTime + $prefs->get('checkVersionInterval') + 2 - Time::HiRes::time())
				));
			}

			Slim::Utils::Timers::setTimer(0, $lastTime + $prefs->get('checkVersionInterval') + 2, \&checkVersion);

			return;
		}
	}

	$log->info("Checking version now.");

	my $url  = "http://"
		. Slim::Networking::SqueezeNetwork->get_server("update")
		. "/update/?version=$::VERSION&revision=$::REVISION&lang=" . Slim::Utils::Strings::getLanguage();
	my $http = Slim::Networking::SqueezeNetwork->new(\&checkVersionCB, \&checkVersionError);

	# will call checkVersionCB when complete
	$http->get($url);

	$prefs->set('checkVersionLastTime', Time::HiRes::time());
	Slim::Utils::Timers::setTimer(0, Time::HiRes::time() + $prefs->get('checkVersionInterval'), \&checkVersion);
}

# called when check version request is complete
sub checkVersionCB {
	my $http = shift;

	# store result in global variable, to be displayed by browser
	if ($http->{code} =~ /^2\d\d/) {

		$::newVersion = Slim::Utils::Unicode::utf8decode( $http->content() );
		chomp($::newVersion);
		
		$log->debug($::newVersion || 'No new SqueezeCenter version available');

		# reset the update flag
		$prefs->set('updateInstaller');

		# trigger download of the installer if available
		if ($::newVersion && $prefs->get('autoDownloadUpdate')) {
			$log->info('Triggering automatic SqueezeCenter update download...');
			Slim::Utils::OSDetect->getOS()->initUpdate();
		}
	}
	else {
		$::newVersion = 0;
		$log->warn(sprintf(Slim::Utils::Strings::string('CHECKVERSION_PROBLEM'), $http->{code}));
	}
}

# called only if check version request fails
sub checkVersionError {
	my $http = shift;

	$log->error(Slim::Utils::Strings::string('CHECKVERSION_ERROR') . "\n" . $http->error);
}


# get the latest URL and download the installer

sub getUpdate {
	my $params = shift;
	
	my $url  = "http://"
		. Slim::Networking::SqueezeNetwork->get_server("sn")
		. "/update/?geturl=1&revision=$::REVISION&os=" . $params->{os};
		
	$log->info("Getting url for latest SqueezeCenter download from $url");
	
	my $downloadPath = $params->{path} || scalar ( Slim::Utils::OSDetect::dirsFor('updates') );

	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotUrlCB,
		\&checkVersionError,
		{
			path => $downloadPath,
		}
	);

	$http->get($url);
}

sub gotUrlCB {
	my $http = shift;
	my $path = $http->params('path');
	
	cleanup($path, 'tmp');

	my $url = $http->content();

	if ( $http->{code} =~ /^2\d\d/ && Slim::Music::Info::isURL($url) ) {
		
		$log->info("URL to download update from: $url");

		my ($a, $b, $file) = Slim::Utils::Misc::crackURL($url);
		($a, $b, $file) = splitpath($file);
		$file = catdir($path, $file);

$log->error($file);

		# don't re-download if file exists already
		if ( -e $file ) {
			$prefs->set( 'updateInstaller', $file);
			return;
		}
		
		my $tmpFile = "$file.tmp";

		$prefs->set('updateInstaller');

		# Save to a tmp file so we can check SHA
		my $download = Slim::Networking::SimpleAsyncHTTP->new(
			\&downloadAsyncDone,
			\&checkVersionError,
			{
				saveAs => $tmpFile,
				file   => $file,
				path   => $path,
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
	my $path    = $http->params('path');
	
	# make sure we got the file
	return if !-e $tmpFile;

	if (-s _ != $http->headers->content_length()) {
		$log->warn( sprintf("SqueezeCenter installer file size mismatch: expected size %s bytes, actual size %s bytes", $http->headers->content_length(), -s _) );
		unlink $tmpFile;
		return;
	}

	cleanup($path);

	$log->info("Successfully downloaded update installer file. Saving as $file");
	rename $tmpFile, $file && $prefs->set('updateInstaller', $file);

	cleanup($path, 'tmp');
}

sub cleanup {
	my ($path, $additionalExt) = @_;
	
	opendir my ($dirh), $path;
	
	my $ext = Slim::Utils::OSDetect->getOS()->installerExtension() . ($additionalExt ? "\.$additionalExt" : '');
	my @oldInstallers = grep { /^SqueezeCenter.*\.$ext$/i } readdir $dirh;
	
	closedir $dirh;
	
	for my $file ( @oldInstallers ) {
		$log->info("Removing old installer file: $file");
		unlink catdir($path, $file) or logError("Unable to remove old installer file: $file: $!");
	}
}

1;