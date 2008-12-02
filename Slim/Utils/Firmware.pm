package Slim::Utils::Firmware;

# SqueezeCenter Copyright 2001-2007 Logitech.
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

use Slim::Networking::SqueezeNetwork;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use constant INITIAL_RETRY_TIME => 600;
use constant MAX_RETRY_TIME     => 86400;

# Models to download firmware for
my @models = qw( squeezebox squeezebox2 transporter boom receiver );

# Firmware location
my $dir = Slim::Utils::OSDetect::dirsFor('Firmware');

# Download location
sub BASE {
	'http://'
	. Slim::Networking::SqueezeNetwork->get_server("update")
	. '/update/firmware';
}

# Check interval when firmware can't be downloaded
my $CHECK_TIME = INITIAL_RETRY_TIME;

# Available firmware files and versions/revisions
my $firmwares = {};

my $log = logger('player.firmware');

my $prefs = preferences('server');

=head2 init()

Scans firmware version files and tries to download each missing firmware file using
download().

=cut

sub init {
	# the files we need to download
	my $files = {};
	
	my $cachedir = $prefs->get('cachedir');
	
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

				my $file  = "${model}_${version}.bin";
				my $path  = catdir( $dir, $file );
				my $path2 = catdir( $cachedir, $file );

				if ($files->{$path} || $files->{$path2}) {
					next;
				}

				if ( !-r $path && !-r $path2 ) {

					$log->info("Need to download $file\n");

					$files->{$path2} = 1;
				}
			}
		}
		
		close $fh;
	}
	
	my $ok = 1;

	for my $file ( keys %{$files} ) {
		my $url = BASE() . '/' . $::VERSION . '/' . basename($file);
		
		$ok = download( $url, $file );
		
		if ( !$ok ) {
			# set a timer that will check again later on, and download this firmware in 
			# the background.  Any player that needs an upgrade will then be prompted by
			# Slim::Player::Squeezebox::checkFirmwareUpgrade
			Slim::Utils::Timers::setTimer( $file, time() + $CHECK_TIME + int(rand(60)), \&downloadAsync );
		}
	}
	
	if ( !$ok ) {
		logError("Some firmware failed to download, will try again in " . int( $CHECK_TIME / 60 ) . " minutes.  Please check your Internet connection.");
	}
}

=head2 init_firmware_download()

Looks for a $model.version file and downloads firmware if missing.  If $model.version
is missing, downloads that too.	 If we are not a released build, also checks for
updated $model.version file.

To allow for locally built firmware images, first looks for the files: custom.$model.version
and custom.$model.bin in the cachedir.  If these exist then these are used in preference.

=cut

sub init_firmware_download {
	my $model = shift;

	my $version_file   = catdir( $prefs->get('cachedir'), "$model.version" );

	my $custom_version = catdir( $prefs->get('cachedir'), "custom.$model.version" );
	my $custom_image   = catdir( $prefs->get('cachedir'), "custom.$model.bin" );
	
	if ( -r $custom_version && -r $custom_image ) {
		$log->info("Using custom $model firmware $custom_version $custom_image");

		$version_file = $custom_version;
		$firmwares->{$model}->{file} = $custom_image;

		my $version = read_file($version_file);
		($firmwares->{$model}->{version}, $firmwares->{$model}->{revision}) = $version =~ m/^([^ ]+)\sr(\d+)/;

		Slim::Web::HTTP::addRawDownload('^firmware/.*\.bin', $custom_image, 'binary');
		
		return;
	}

	# Don't check for Jive firmware if the 'check for updated versions' pref is disabled
	return unless $prefs->get('checkVersion');
	
	$log->is_info && $log->info("Downloading $model.version file...");
	
	# Any async downloads in init must be started on a timer so they don't
	# time out from other slow init things
	Slim::Utils::Timers::setTimer(
		undef,
		time(),
		sub {
			downloadAsync( $version_file, \&init_version_done, $version_file, $model );
		},
	);
}

=head2 init_version_done($version_file, $model)

Callback after the jive.version file has been downloaded.  Checks if we need
to download a new bin file, and schedules another check for the version file
in 1 day.

=cut

sub init_version_done {
	my $version_file = shift;
	my $model        = shift || 'jive';
			
	my $version = read_file($version_file);
	
	# jive.version format:
	# 7.0 rNNNN
	# sdi@padbuild #24 Sat Sep 8 01:26:46 PDT 2007
	my ($ver, $rev) = $version =~ m/^([^ ]+)\sr(\d+)/;

	my $fw_file = catdir( $prefs->get('cachedir'), "${model}_${ver}_r${rev}.bin" );

	if ( !-e $fw_file ) {		
		$log->info("Downloading $model firmware to: $fw_file");
	
		downloadAsync( $fw_file, \&init_fw_done, $fw_file, $model );
	}
	else {
		$log->info("$model firmware is up to date: $fw_file");
		$firmwares->{$model} = {
			version  => $ver,
			revision => $rev,
			file     => $fw_file,
		}
	}

	Slim::Web::HTTP::addRawDownload('^firmware/.*\.bin', $fw_file, 'binary');
	
	# Check again for an updated $model.version in 12 hours
	$log->debug('Scheduling next $model.version check in 12 hours');
	Slim::Utils::Timers::setTimer(
		undef,
		time() + 43200,
		sub {
			init_fw_download($model);
		},
	);
}

=head2 init_fw_done($fw_file, $model)

Callback after firmware has been downloaded.  Receives the filename
of the newly downloaded firmware and the $modelname. 
Removes old firmware file if one exists.

=cut

sub init_fw_done {
	my $fw_file = shift;
	my $model   = shift;
	
	opendir my ($dirh), $prefs->get('cachedir');
	
	my @files = grep { /^$model.*\.bin(\.tmp)?$/ } readdir $dirh;
	
	closedir $dirh;
	
	for my $file ( @files ) {
		next if $file eq basename($fw_file);
		$log->info("Removing old $model firmware file: $file");
		unlink catdir( $prefs->get('cachedir'), $file ) or logError("Unable to remove old $model firmware file: $file: $!");
	}
	
	my ($ver, $rev) = $fw_file =~ m/${model}_([^_]+)_r([^\.]+).bin/;
	
	$firmwares->{$model} = {
		version  => $ver,
		revision => $rev,
		file     => $fw_file,
	}
}

=head2 init_fw_error($model)

Called if firmware download failed.  Checks if another firmware exists in cache.

=cut

sub init_fw_error {	
	my $model = shift || 'jive';
	
	# Check if we have a usable Jive firmware
	my $version_file = catdir( $prefs->get('cachedir'), "$model.version" );
	
	if ( -e $version_file ) {
		my $version = read_file($version_file);

		my ($ver, $rev) = $version =~ m/^([^ ]+)\sr(\d+)/;

		my $fw_file = catdir( $prefs->get('cachedir'), "${model}_${ver}_r${rev}.bin" );

		if ( -e $fw_file ) {
			$log->info("$model firmware download had an error, using existing firmware: $fw_file");
			$firmwares->{$model} = {
				version  => $ver,
				revision => $rev,
				file     => $fw_file,
			}
		}
	}
	
	# Note: Server will keep trying to download a new one
}

=head2 url()

Returns an URL for downloading the current player firmware.  Returns
undef if firmware has not been downloaded.

=cut

sub url {
	my $class = shift;
	my $model = shift || 'jive';

	unless ($firmwares->{$model} && $firmwares->{$model}->{file}) {
		init_firmware_download($model);
		return;
	}
	
	return 'http://'
		. Slim::Utils::Network::serverAddr() . ':'
		. preferences('server')->get('httpport')
		. '/firmware/' . basename($firmwares->{$model}->{file});
}

=head2 need_upgrade( $current_version, $model )

Returns 1 if $model player needs an upgrade.  Returns undef if not, or
if there is no firmware downloaded.

=cut

sub need_upgrade {
	my ( $class, $current, $model ) = @_;
	
	return unless $firmwares->{$model} && $firmwares->{$model}->{file} && $firmwares->{$model}->{version};
	
	my ($cur_version, $cur_rev) = $current =~ m/^([^ ]+)\sr(\d+)/;
	
	if ( !$cur_version || !$cur_rev ) {
		logError("$model sent invalid current version: $current");
		return;
	}
	
	# Force upgrade if the version doesn't match, or if the rev is older
	# Allows newer firmware to work without forcing a downgrade
	if ( 
		( $firmwares->{$model}->{version} ne $cur_version )
		||
		( $firmwares->{$model}->{revision} > $cur_rev )
	) {
		$log->debug("$model needs upgrade! (has: $current, needs: $firmwares->{$model}->{version} $firmwares->{$model}->{revision})");
		return 1;
	}
	
	$log->debug("$model doesn't need an upgrade (has: $current, server has: $firmwares->{$model}->{version} $firmwares->{$model}->{revision})");
	
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
	my $file = shift;
	my ( $cb, @pt ) = @_;
	
	# URL to download
	my $url = BASE() . '/' . $::VERSION . '/' . basename($file);
	
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
	
	$CHECK_TIME = INITIAL_RETRY_TIME;
	
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
	my $cb   = $http->params('cb');
	my $pt   = $http->params('pt');
	
	# Clean up
	unlink "$file.tmp" if -e "$file.tmp"; 
	
	logWarning(sprintf("Firmware: Failed to download %s (%s), will try again in %d minutes.",
		$http->url,
		$error,
		int( $CHECK_TIME / 60 ),
	));
	
	Slim::Utils::Timers::setTimer( $file, time() + $CHECK_TIME, \&downloadAsync,
		{
			file => $file,
			cb   => $cb,
			pt   => $pt,
		},
	 );
	
	# Increase retry time in case of multiple failures, but don't exceed MAX_RETRY_TIME
	$CHECK_TIME *= 2;
	if ( $CHECK_TIME > MAX_RETRY_TIME ) {
		$CHECK_TIME = MAX_RETRY_TIME;
	}
	
	# Bug 9230, if we failed to download a Jive firmware but have a valid one in Cache already,
	# we should still offer it for download
	my $model = scalar @$pt > 1 ? $pt->[1] : 'jive';
	if ( $file =~ /$model/ ) {
		init_fw_error($model);
	}
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
