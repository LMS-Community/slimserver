package Slim::Utils::Firmware;

# Logitech Media Server Copyright 2001-2011 Logitech.
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

use Slim::Networking::Repositories;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use constant INITIAL_RETRY_TIME => 600;
use constant MAX_RETRY_TIME     => 86400;

# Firmware location - initialize in init() once options have been parsed
my $dir;
my $updatesDir;

# Download location
sub BASE {
	return Slim::Networking::Repositories->getUrlForRepository('firmware');
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
	# Must initialize these here, not in declaration so that options have been parsed.
	$dir        = Slim::Utils::OSDetect::dirsFor('Firmware');
	$updatesDir = Slim::Utils::OSDetect::dirsFor('updates');
	
	# clean up old download location
	Slim::Utils::Misc::deleteFiles($prefs->get('cachedir'), qr/^\w{4}_\d\.\d_.*\.bin(\.tmp)?$/i);
	Slim::Utils::Misc::deleteFiles($prefs->get('cachedir'), qr/^.*version$/i);

	# No longer try downloading all player firmwares at startup - just allow the background
	# download to get what is needed
	
	# Delete old ip3k firmware downloads - we should not normally need them again
	Slim::Utils::Misc::deleteFiles($updatesDir, qr/^(squeezebox|squeezebox2|transporter|boom|receiver)_\d+\.bin$/);
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

	return if $model eq 'squeezeplay'; # there is no firmware for the desktop version of squeezeplay!
	
	my $version_file   = catdir( $updatesDir, "$model.version" );

	my $custom_version = catdir( $updatesDir, "custom.$model.version" );
	my $custom_image   = catdir( $updatesDir, "custom.$model.bin" );
	
	if ( -r $custom_version && -r $custom_image ) {
		main::INFOLOG && $log->info("Using custom $model firmware $custom_version $custom_image");

		$version_file = $custom_version;
		$firmwares->{$model}->{file} = $custom_image;

		my $version = read_file($version_file);
		($firmwares->{$model}->{version}, $firmwares->{$model}->{revision}) = $version =~ m/^([^ ]+)\sr(\d+)/;

		Slim::Web::Pages->addRawDownload("^firmware/custom.$model.bin", $custom_image, 'binary');
		
		return;
	}

	# Don't check for Jive firmware if the 'check for updated versions' pref is disabled
	if ( !$prefs->get('checkVersion') ) {
		main::INFOLOG && $log->info("Not downloading firmware for $model - update check has been disabled in Settings/Advanced/Software Updates");
		get_fw_locally($model);
		return;
	}

	main::INFOLOG && $log->is_info && $log->info("Downloading $model.version file...");

	# Any async downloads in init must be started on a timer so they don't
	# time out from other slow init things
	Slim::Utils::Timers::setTimer(
		undef,
		time(),
		sub {
			downloadAsync( $version_file, {cb => \&init_version_done, pt => [$version_file, $model]} );
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

	# on SqueezeOS we don't download firmware files
	# we'll let the player download them from squeezenetwork directly
	if ( Slim::Utils::OSDetect->getOS()->directFirmwareDownload() ) {

		$firmwares->{$model} = {
			version  => $ver,
			revision => $rev,
			file     => 1		# dummy value or upgrade won't be published
		};

		Slim::Control::Request->new(undef, ['fwdownloaded', $model])->notify('firmwareupgrade');
	}
	
	else {
		
		my $fw_file = catdir( $updatesDir, "${model}_${ver}_r${rev}.bin" );

		if ( !-e $fw_file ) {		
			main::INFOLOG && $log->info("Downloading $model firmware to: $fw_file");
		
			downloadAsync( $fw_file, {cb => \&init_fw_done, pt => [$fw_file, $model]} );
		}
		else {
			main::INFOLOG && $log->info("$model firmware is up to date: $fw_file");
			$firmwares->{$model} = {
				version  => $ver,
				revision => $rev,
				file     => $fw_file,
			};
	
			Slim::Control::Request->new(undef, ['fwdownloaded', $model])->notify('firmwareupgrade');
			
			Slim::Web::Pages->addRawDownload("^firmware/${model}.*\.bin", $fw_file, 'binary');
		}

	}
	
	# Check again for an updated $model.version in 12 hours
	main::DEBUGLOG && $log->debug("Scheduling next $model.version check in " . ($prefs->get('checkVersionInterval') / 3600) . " hours");
	Slim::Utils::Timers::setTimer(
		undef,
		time() + $prefs->get('checkVersionInterval'),
		sub {
			init_firmware_download($model);
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
		
	Slim::Utils::Misc::deleteFiles($updatesDir, qr/^$model.*\.bin(\.tmp)?$/i, $fw_file);
	
	my ($ver, $rev) = $fw_file =~ m/${model}_([^_]+)_r([^\.]+).bin/;
	
	$firmwares->{$model} = {
		version  => $ver,
		revision => $rev,
		file     => $fw_file,
	};

	main::DEBUGLOG && $log->debug("downloaded $ver $rev for $model - $fw_file");
	
	Slim::Web::Pages->addRawDownload("^firmware/${model}.*\.bin", $fw_file, 'binary');

	# send a notification that this firmware is downloaded
	Slim::Control::Request->new(undef, ['fwdownloaded', $model])->notify('firmwareupgrade');
}

=head2 init_fw_error($model)

Called if firmware download failed.  Checks if another firmware exists in cache.

=cut

sub init_fw_error {	
	my $model = shift || 'jive';

	main::INFOLOG && $log->info("$model firmware download had an error");

	get_fw_locally( $model );
	
	# Note: Server will keep trying to download a new one
}

sub get_fw_locally {
	my $model = shift || 'jive';
	
	for my $path ($updatesDir, $dir) {
		# Check if we have a usable Jive firmware
		my $version_file = catdir( $path, "$model.version" );
		
		if ( -e $version_file ) {
			my $version = read_file($version_file);
			my ($ver, $rev) = $version =~ m/^([^ ]+)\sr(\d+)/;
	
			my $fw_file = catdir( $path, "${model}_${ver}_r${rev}.bin" );

			if ( -e $fw_file ) {
				main::INFOLOG && $log->info("Using existing firmware for $model: $fw_file");
				$firmwares->{$model} = {
					version  => $ver,
					revision => $rev,
					file     => $fw_file,
				};
				
				Slim::Web::Pages->addRawDownload("^firmware/${model}.*\.bin", $fw_file, 'binary');
	
				# send a notification that this firmware is downloaded
				Slim::Control::Request->new(undef, ['fwdownloaded', $model])->notify('firmwareupgrade');
				
				last;
			}
		}
	}
}

=head2 url()

Returns an URL for downloading the current player firmware.  Returns
undef if firmware has not been downloaded.

=cut

sub url {
	my $class = shift;
	my $model = shift || 'jive';

	unless ($firmwares->{$model}) {
		# don't trigger download more than once
		$firmwares->{$model} = {};
		init_firmware_download($model);
		return unless ($firmwares->{$model}->{file});	# Will be available immediately if custom f/w 
	}

	# when running on SqueezeOS, return the direct link from SqueezeNetwork
	if ( Slim::Utils::OSDetect->getOS()->directFirmwareDownload() ) {
		return BASE() . $::VERSION . '/' . $model
			. '_' . $firmwares->{$model}->{version} 
			. '_r' . $firmwares->{$model}->{revision} 
			. '.bin';
	}

	return unless $firmwares->{$model}->{file};
	
	return Slim::Utils::Network::serverURL() . '/firmware/' . basename($firmwares->{$model}->{file});
}

=head2 need_upgrade( $current_version, $model )

Returns 1 if $model player needs an upgrade.  Returns undef if not, or
if there is no firmware downloaded.

=cut

sub need_upgrade {
	my ( $class, $current, $model ) = @_;
	
	unless ($firmwares->{$model} && $firmwares->{$model}->{file} && $firmwares->{$model}->{version}) {
		main::DEBUGLOG && $log->debug("no firmware for $model - can't upgrade");
		return;
	}
	
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
		main::DEBUGLOG && $log->debug("$model needs upgrade! (has: $current, needs: $firmwares->{$model}->{version} $firmwares->{$model}->{revision})");
		return 1;
	}
	
	main::DEBUGLOG && $log->debug("$model doesn't need an upgrade (has: $current, server has: $firmwares->{$model}->{version} $firmwares->{$model}->{revision})");
	
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
	
	require LWP::UserAgent;
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
		main::INFOLOG && $log->info("File $file not modified");
		return 0;
	}
	
	logError("Unable to download firmware from $url: $error");

	return 0;
}

=head2 downloadAsync($file)

This timer tries to download any missing firmware in the background every 10 minutes.

=cut

# Keep track of what files are being downloaded and their callbacks
my %filesDownloading;

sub downloadAsync {
	my ($file, $args) = @_;
	$args ||= {};
		
	# Are we already downloading?
	my $callbacks;
	if (!$args->{'retry'} && ($callbacks = $filesDownloading{$file})) {
		# If we we have more than one caller expecting a callback then stash them here
		if ($args->{'cb'}) {
			# XXX maybe check that we do not already have this tuple
			push @$callbacks, $args;
		}
		return;
	}
	
	# Use an empty array ref as the default true value
	$filesDownloading{$file} ||= [];
	
	# URL to download
	my $url = BASE() . $::VERSION . '/' . basename($file);
	
	# Save to a tmp file so we can check SHA
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&downloadAsyncDone,
		\&downloadAsyncError,
		{
			%$args,
			saveAs => "$file.tmp",
			file   => $file,
		},
	);
	
	main::INFOLOG && $log->info("Downloading in the background: $url -> $file");
	
	$http->get( $url );
}

=head2 downloadAsyncDone($http)

Callback after our firmware file has been downloaded.

=cut

sub downloadAsyncDone {
	my $http = shift;
	my $args = $http->params();
	my $file = $args->{'file'};
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
			%$args,
			saveAs => undef,
		}
	);
	
	$http->get( $url . '.sha' );
}

=head2 downloadAsyncSHADone($http)

Callback after our firmware's SHA checksum file has been downloaded.

=cut

sub downloadAsyncSHADone {
	my $http = shift;
	my $args = $http->params();
	my $file = $args->{'file'};
	
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
		
		main::INFOLOG && $log->info("Successfully downloaded and verified $file.");
	
		# reset back off time
		$CHECK_TIME = INITIAL_RETRY_TIME;
		
		my $cb = $args->{'cb'};
		if ( $cb && ref $cb eq 'CODE' ) {
			$cb->( @{$args->{'pt'} || []} );
		}
		
		# Pick up extra callbacks waiting for this file
		foreach $args (@{$filesDownloading{$file}}) {
			my $cb = $args->{'cb'};
			if ( $cb && ref $cb eq 'CODE' ) {
				$cb->( @{$args->{'pt'} || []} );
			}
		}
		
		delete $filesDownloading{$file};
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
	
	# If error was "Unable to open $file for writing", downloading will never succeed so just give up
	# Same for "Unable to write" if we run out of disk space, for example
	if ( $error =~ /Unable to (?:open|write)/ ) {
		logWarning(sprintf("Firmware: Fatal error downloading %s (%s), giving up",
			$http->url,
			$error,
		));
	}
	else {
		logWarning(sprintf("Firmware: Failed to download %s (%s), will try again in %d minutes.",
			$http->url,
			$error,
			int( $CHECK_TIME / 60 ),
		));

		if ( my $proxy = $prefs->get('webproxy') ) {
			$log->error( sprintf("Please check your proxy configuration (%s)", $proxy) );
		} 
	
		Slim::Utils::Timers::killTimers( $file, \&downloadAsync );
		Slim::Utils::Timers::setTimer( $file, time() + $CHECK_TIME, \&downloadAsync,
			{
				file => $file,
				cb   => $cb,
				pt   => $pt,
				retry=> 1,
			},
		 );
	
		# Increase retry time in case of multiple failures, but don't exceed MAX_RETRY_TIME
		$CHECK_TIME *= 2;
		if ( $CHECK_TIME > MAX_RETRY_TIME ) {
			$CHECK_TIME = MAX_RETRY_TIME;
		}
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
