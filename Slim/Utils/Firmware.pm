package Slim::Utils::Firmware;

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# $Id$

=head1 NAME

Slim::Utils::Firmware

=head1 SYNOPSIS

This class downloads firmware during startup if it was
not included with the distribution.  It uses synchronous
download via LWP so that all firmware will be downloaded
before any players connect.  If this initial download fails
it will switch to async mode and try to download missing
firmware every 10 minutes in the background.

All downloaded firmware is verified using an SHA1 checksum
file before being saved.

=head1 METHODS

=cut

use strict;

use Digest::SHA1;
use File::Basename;
use File::Slurp qw(read_file);
use File::Spec::Functions qw(:ALL);
use LWP::UserAgent;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

# Models to download firmware for
my @models = qw( squeezebox squeezebox2 transporter );

# Firmware location
my $dir = Slim::Utils::OSDetect::dirsFor('Firmware');

# Download location
my $base = 'http://update.slimdevices.com/update/firmware';

# Check interval when firmware can't be downloaded
my $CHECK_TIME = 600;

# Current Jive firmware file and version/revision
my $JIVE_FW;
my $JIVE_VER;
my $JIVE_REV;

my $log = logger('player.firmware');

my $prefs = preferences('server');

=head2 init()

Scans firmware version files and tries to download each missing firmware file using
download().

=cut

sub init {
	# the files we need to download
	my $files = {};
	
	# Special handling is needed for Jive firmware
	init_jive();
	
	for my $model ( @models ) {

		# read each model's version file
		open my $fh, '<', catdir( $dir, "$model.version" );

		if ( !$fh ) {

			# It's a fatal error if we can't read our version files
			fatal("Unable to initialize firmware, missing $model.version file\n");
		}
		
		while ( <$fh> ) {
			chomp;
			
			my ($version) = $_ =~ m/(?:\d+|\*)(?:\.\.\d+)?\s+(\d+)/;
			
			if ( $version ) {

				my $file = "${model}_${version}.bin";
				my $path = catdir( $dir, $file );

				if ($files->{$path}) {
					next;
				}
				
				if ( !-r $path ) {

					$log->info("Need to download $file\n");

					$files->{$path} = 1;
				}
			}
		}
		
		close $fh;
	}
	
	my $ok = 1;

	for my $file ( keys %{$files} ) {
		my $url = $base . '/' . $::VERSION . '/' . basename($file);
		
		$ok = download( $url, $file );
		
		if ( !$ok ) {
			# set a timer that will check again later on, and download this firmware in 
			# the background.  Any player that needs an upgrade will then be prompted by
			# Slim::Player::Squeezebox::checkFirmwareUpgrade
			Slim::Utils::Timers::setTimer( $file, time() + $CHECK_TIME + int(rand(60)), \&downloadAsync );
		}
	}
	
	if ( !$ok ) {
		logError("Some firmware failed to download, will try again in 10 minutes.  Please check your Internet connection.");
	}
}

=head2 init_jive()

Looks for a jive.version file and downloads firmware if missing.  If jive.version
is missing, downloads that too.	 If we are not a released build, also checks for
updated jive.version file.

To allow for locally built jive images, first looks for the files: custom.jive.version
and custom.jive.bin in the cachedir.  If these exist then these are used in preference.

=cut

sub init_jive {

	my $url = $base . '/' . $::VERSION . '/jive.version';
		
	my $version_file   = catdir( $prefs->get('cachedir'), 'jive.version' );

	my $custom_version = catdir( $prefs->get('cachedir'), 'custom.jive.version' );
	my $custom_image   = catdir( $prefs->get('cachedir'), 'custom.jive.bin' );
	
	if ( -r $custom_version && -r $custom_image ) {
		$log->info("Using custom jive firmware $custom_version $custom_image");

		$version_file = $custom_version;
		$JIVE_FW = $custom_image;

		my $version = read_file($version_file);
		($JIVE_VER, $JIVE_REV) = $version =~ m/^(\d+)\s(r.*)/;

		Slim::Web::HTTP::addRawDownload('^firmware/.*\.bin', $custom_image, 'binary');
		
		return;
	}

	# Don't check for Jive firmware if the 'check for updated versions' pref is disabled
	return unless $prefs->get('checkVersion');
	
	$log->info('Downloading jive.version file...');
	
	# Any async downloads in init must be started on a timer so they don't
	# time out from other slow init things
	Slim::Utils::Timers::setTimer(
		undef,
		time(),
		sub {
			downloadAsync( $version_file, \&init_jive_version_done, $version_file );
		},
	);
}

=head2 init_jive_version_done($version_file)

Callback after the jive.version file has been downloaded.  Checks if we need
to download a new bin file, and schedules another check for the version file
in 1 day.

=cut

sub init_jive_version_done {
	my $version_file = shift;
			
	my $version = read_file($version_file);
	
	# jive.version format:
	# 1 r457
	# sdi@padbuild #24 Sat Sep 8 01:26:46 PDT 2007
	($JIVE_VER, $JIVE_REV) = $version =~ m/^(\d+)\s(r.*)/;

	my $jive_file = catdir( $prefs->get('cachedir'), "jive_${JIVE_VER}_${JIVE_REV}.bin" );

	if ( !-e $jive_file ) {		
		$log->info("Downloading Jive firmware to: $jive_file");
	
		downloadAsync( $jive_file, \&init_jive_done, $jive_file );
	}
	else {
		$log->info("Jive firmware is up to date: $jive_file");
		$JIVE_FW = $jive_file;
	}

	Slim::Web::HTTP::addRawDownload('^firmware/.*\.bin', $jive_file, 'binary');
	
	# Check again for an updated jive.version in 24 hours
	$log->debug('Scheduling next jive.version check in 24 hours');
	Slim::Utils::Timers::setTimer(
		undef,
		time() + 86400,
		\&init_jive,
	);
}

=head2 init_jive_done($jive_file)

Callback after Jive firmware has been downloaded.  Receives the filename
of the newly downloaded firmware.  Removes old Jive firmware file if one exists.

=cut

sub init_jive_done {
	my $jive_file = shift;
	
	opendir my ($dirh), $prefs->get('cachedir');
	
	my @files = grep { /^jive.*\.bin(\.tmp)?$/ } readdir $dirh;
	
	closedir $dirh;
	
	for my $file ( @files ) {
		next if $file eq basename($jive_file);
		$log->info("Removing old Jive firmware file: $file");
		unlink catdir( $prefs->get('cachedir'), $file ) or logError("Unable to remove old Jive firmware file: $file: $!");
	}
	
	$JIVE_FW = $jive_file;
}

=head2 jive_url()

Returns a URL for downloading the current Jive firmware.  Returns
undef if firmware has not been downloaded.

=cut

sub jive_url {
	my $class = shift;

	return unless $JIVE_FW;
	
	return 'http://'
		. Slim::Utils::Network::serverAddr() . ':'
		. preferences('server')->get('httpport')
		. '/firmware/' . basename($JIVE_FW);
}

=head2 jive_needs_upgrade( $current_version )

Returns 1 if Jive needs an upgrade.  Returns undef if not, or
if there is no firmware downloaded.

=cut

sub jive_needs_upgrade {
	my ( $class, $current ) = @_;
	
	return unless $JIVE_FW;
	
	my ($cur_version, $cur_rev) = $current =~ m/^(\d+)\s(r.*)/;
	
	if ( !$cur_version || !$cur_rev ) {
		logError("Jive sent invalid current version: $current");
		return;
	}
	
	if ( 
		( $JIVE_VER != $cur_version )
		||
		( $JIVE_REV ne $cur_rev )
	) {
		$log->debug("Jive needs upgrade! (has: $current, needs: $JIVE_VER $JIVE_REV)");
		return 1;
	}
	
	$log->debug("Jive doesn't need an upgrade (has: $current, server has: $JIVE_VER $JIVE_REV)");
	
	return;
}

=head2 download( $url, $file )

Performs a synchronous file download at startup for all firmware files.
If these fail, will set a timer for async downloads in the background in
10 minutes or so.

$file must be an absolute path.

=cut

sub download {
	my ( $url, $file ) = @_;
	
	my $ua = LWP::UserAgent->new(
		env_proxy => 1,
	);
	
	my $error;
	
	msg("Downloading firmware from $url, please wait...\n");
	
	my $res = $ua->mirror( $url, $file );
	if ( $res->is_success ) {
		
		# Download the SHA1sum file to verify our download
		my $res2 = $ua->mirror( "$url.sha", "$file.sha" );
		if ( $res2->is_success ) {
			
			my $sumfile = read_file( "$file.sha" ) or fatal("Unable to read $file.sha to verify firmware\n");
			my ($sum) = $sumfile =~ m/([a-f0-9]{40})/;
			unlink "$file.sha";
			
			open my $fh, '<', $file or fatal("Unable to read $file to verify firmware\n");
			binmode $fh;
			
			my $sha1 = Digest::SHA1->new;
			$sha1->addfile($fh);
			close $fh;
			
			if ( $sha1->hexdigest eq $sum ) {
				logWarning("Successfully downloaded and verified $file.");
				return 1;
			}
			
			unlink $file;
			
			logError("Validation of firmware $file failed, SHA1 checksum did not match");
		}
		else {
			unlink $file;
			$error = $res2->status_line;
		}
	}
	else {
		$error = $res->status_line;
	}
	
	if ( $res->code == 304 ) {
		$log->info("File $file not modified");
		return 0;
	}
	
	logError("Unable to download firmware from $url: $error");

	return 0;
}

=head2 downloadAsync($file)

This timer tries to download any missing firmware in the background every 10 minutes.

=cut

sub downloadAsync {
	my $file     = shift;
	my ( $cb, @pt ) = @_;
	
	# URL to download
	my $url = $base . '/' . $::VERSION . '/' . basename($file);
	
	# Save to a tmp file so we can check SHA
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&downloadAsyncDone,
		\&downloadAsyncError,
		{
			saveAs => "$file.tmp",
			file   => $file,
			cb     => $cb,
			pt     => \@pt,
		},
	);
	
	$log->info("Downloading in the background: $url");
	
	$http->get( $url );
}

=head2 downloadAsyncDone($http)

Callback after our firmware file has been downloaded.

=cut

sub downloadAsyncDone {
	my $http = shift;
	my $file = $http->params('file');
	my $cb   = $http->params('cb');
	my $pt   = $http->params('pt');
	my $url  = $http->url;
	
	# make sure we got the file
	if ( !-e "$file.tmp" ) {
		return downloadAsyncError( $http, 'File was not saved properly' );
	}
	
	# Grab the SHA file, doesn't need to be saved to the filesystem
	$http = Slim::Networking::SimpleAsyncHTTP->new(
		\&downloadAsyncSHADone,
		\&downloadAsyncError,
		{
			file => $file,
			cb   => $cb,
			pt   => $pt,
		},
	);
	
	$http->get( $url . '.sha' );
}

=head2 downloadAsyncSHADone($http)

Callback after our firmware's SHA checksum file has been downloaded.

=cut

sub downloadAsyncSHADone {
	my $http = shift;
	my $file = $http->params('file');
	my $cb   = $http->params('cb');
	my $pt   = $http->params('pt') || [];
	
	# get checksum
	my ($sum) = $http->content =~ m/([a-f0-9]{40})/;
	
	# open firmware file
	open my $fh, '<', "$file.tmp" or return downloadAsyncError( $http, "Unable to read $file to verify firmware" );
	binmode $fh;
	
	my $sha1 = Digest::SHA1->new;
	$sha1->addfile($fh);
	close $fh;
	
	if ( $sha1->hexdigest eq $sum ) {
				
		# rename the tmp file
		rename "$file.tmp", $file or return downloadAsyncError( $http, "Unable to rename temporary $file file" );
		
		$log->info("Successfully downloaded and verified $file.");
		
		if ( $cb && ref $cb eq 'CODE' ) {
			$cb->( @{$pt} );
		}
	}
	else {
		downloadAsyncError( $http, "Validation of firmware $file failed, SHA1 checksum did not match" );
	}
}

=head2 downloadAsyncError( $http, $error )

Error handler for any download errors, or errors verifying the firmware.  Cleans up temporary
file and resets the check timer.

=cut

sub downloadAsyncError {
	my ( $http, $error ) = @_;
	my $file = $http->params('file');
	
	# Clean up
	unlink "$file.tmp" if -e "$file.tmp";
	
	logWarning(sprintf("Firmware: Failed to download %s (%s), will try again in 10 minutes.",
		$http->url,
		$error,
	));
	
	Slim::Utils::Timers::setTimer( $file, time() + $CHECK_TIME + int(rand(60)), \&downloadAsync );
}

=head2 fatal($msg)

Shuts down with an error message.

=cut

sub fatal {
	my $msg = shift;
	
	logError($msg);
	
	main::stopServer();
}

1;
