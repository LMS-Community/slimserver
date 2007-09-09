package Slim::Utils::Firmware;

# SlimServer Copyright (c) 2001-2007 Logitech.
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
our @models = qw( squeezebox squeezebox2 transporter );

# File location
our $dir = Slim::Utils::OSDetect::dirsFor('Firmware');

# Download location
our $base = 'http://update.slimdevices.com/update/firmware';

# Check interval when firmware can't be downloaded
our $CHECK_TIME = 600;

# Current Jive firmware file
my $JIVE_FW;

my $log = logger('player.firmware');

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

				if ($files->{$file}) {
					next;
				}
				
				if ( !-r $path ) {

					$log->info("Need to download $file\n");

					$files->{$file} = 1;
				}
			}
		}
		
		close $fh;
	}
	
	my $ok = 1;

	for my $file ( keys %{$files} ) {
		my $url = $base . '/' . $::VERSION . '/' . $file;
		
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

=cut

sub init_jive {
	my $url = $base . '/' . $::VERSION . '/jive.version';
	
	my $version_file = catdir( $dir, 'jive.version' );
	
	if ( !-e $version_file ) {
		$log->info('Downloading new jive.version file...');
		
		if ( !download( $url, 'jive.version' ) ) {
			logError('Unable to download jive.version file, to retry please restart SlimServer.');
			return;
		}
	}
	else {
		# Check for a newer jive.version, only for svn users
		if ( $::REVISION eq 'TRUNK' ) {		
			$log->info('Checking for a newer jive.version file...');
			
			if ( !download( $url, 'jive.version' ) ) {
				# not modified
				$log->info("Jive version file is up to date");
			}
		}
	}
		
	my $version = read_file($version_file);
	
	# jive.version format:
	# 1 r457
	# sdi@padbuild #24 Sat Sep 8 01:26:46 PDT 2007
	my ($jive_version, $jive_rev) = $version =~ m/^(\d+)\s(r\d+\w*)/;
	
	my $jive_file = "jive_${jive_version}_${jive_rev}.bin";
	
	if ( !-e catdir( $dir, $jive_file ) ) {		
		$log->info("Downloading in the background: $jive_file");
		
		downloadAsync( $jive_file, \&init_jive_done, $jive_file );
	}
	else {
		$log->info("Jive firmware is up to date: $jive_file");
		$JIVE_FW = $jive_file;
	}
}

=head2 init_jive_done($jive_file)

Callback after Jive firmware has been downloaded.  Receives the filename
of the newly downloaded firmware.  Removes old Jive firmware file if one exists.

=cut

sub init_jive_done {
	my $jive_file = shift;
	
	opendir my ($dirh), $dir;
	
	my @files = grep { /^jive.*\.bin$/ } readdir $dirh;
	
	closedir $dirh;
	
	for my $file ( @files ) {
		next if $file eq $jive_file;
		$log->info("Removing old Jive firmware file: $file");
		unlink catdir( $dir, $file ) or logError("Unable to remove old Jive firmware file: $file: $!");
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
		. "/firmware/$JIVE_FW";
}

=head2 jive_needs_upgrade( $current_version )

Returns 1 if Jive needs an upgrade.  Returns undef if not, or
if there is no firmware downloaded.

=cut

sub jive_needs_upgrade {
	my ( $class, $current ) = @_;
	
	return unless $JIVE_FW;
	
	my ($cur_version, $cur_rev) = $current =~ m/^(\d+)\s(r\d+\w*)/;
	
	if ( !$cur_version || !$cur_rev ) {
		logError("Jive sent invalid current version: $current");
		return;
	}
	
	my ($server_version, $server_rev) = $JIVE_FW =~ m/^jive_(\d+)_(r\d+\w*)\.bin$/;
	
	if ( 
		( $server_version != $cur_version )
		||
		( $server_rev ne $cur_rev )
	) {
		$log->debug("Jive needs upgrade! (has: $current, needs: $server_version $server_rev)");
		return 1;
	}
	
	$log->debug("Jive doesn't need an upgrade (has: $current, server has: $server_version $server_rev)");
	
	return;
}

=head2 download( $url, $file )

Performs a synchronous file download at startup for all firmware files.
If these fail, will set a timer for async downloads in the background in
10 minutes or so.

=cut

sub download {
	my ( $url, $file ) = @_;
	
	my $ua = LWP::UserAgent->new(
		env_proxy => 1,
	);
	
	my $error;
	
	msg("Downloading firmware from $url, please wait...\n");
	
	my $path = catdir( $dir, $file );
	
	my $res = $ua->mirror( $url, $path );
	if ( $res->is_success ) {
		
		# Download the SHA1sum file to verify our download
		my $res2 = $ua->mirror( "$url.sha", "$path.sha" );
		if ( $res2->is_success ) {
			
			my $sumfile = read_file( "$path.sha" ) or fatal("Unable to read $file.sha to verify firmware\n");
			my ($sum) = $sumfile =~ m/([a-f0-9]{40})/;
			unlink "$path.sha";
			
			open my $fh, '<', $path or fatal("Unable to read $path to verify firmware\n");
			binmode $fh;
			
			my $sha1 = Digest::SHA1->new;
			$sha1->addfile($fh);
			close $fh;
			
			if ( $sha1->hexdigest eq $sum ) {
				logWarning("Successfully downloaded and verified $file.");
				return 1;
			}
			
			unlink $path;
			
			logError("Validation of firmware $file failed, SHA1 checksum did not match");
		}
		else {
			unlink $path;
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
	my $url = $base . '/' . $::VERSION . '/' . $file;
	
	# File to save it in, we use a tmp file so we can check SHA
	my $path = catdir( $dir, $file ) . '.tmp';
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&downloadAsyncDone,
		\&downloadAsyncError,
		{
			saveAs => $path,
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
	my $path = catdir( $dir, $file ) . '.tmp';
	if ( !-e $path ) {
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
	my $path = catdir( $dir, $file ) . '.tmp';
	open my $fh, '<', $path or return downloadAsyncError( $http, "Unable to read $path to verify firmware" );
	binmode $fh;
	
	my $sha1 = Digest::SHA1->new;
	$sha1->addfile($fh);
	close $fh;
	
	if ( $sha1->hexdigest eq $sum ) {
				
		# rename the tmp file
		my $real = catdir( $dir, $file );
		rename $path, $real or return downloadAsyncError( $http, "Unable to rename temporary $path file" );
		
		logWarning("Successfully downloaded and verified $file.");
		
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
	my $path = catdir( $dir, $file ) . '.tmp';
	unlink $path if -e $path;
	
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
