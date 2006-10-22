package Slim::Utils::Firmware;

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
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
use Slim::Utils::OSDetect;
use Slim::Utils::Timers;

# Models to download firmware for
our @models = qw( squeezebox squeezebox2 transporter );

# File location
our $dir = Slim::Utils::OSDetect::dirsFor('Firmware');

# Download location
our $base = 'http://update.slimdevices.com/update/firmware';

# Check interval when firmware can't be downloaded
our $CHECK_TIME = 600;

=head2 init()

Scans firmware version files and tries to download each missing firmware file using
download().

=cut

sub init {
	# the files we need to download
	my $files = {};
	
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

					logger('player.firmware')->info("Need to download $file\n");

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
	
	logError("Unable to download firmware from $url: $error");

	return 0;
}

=head2 downloadAsync($file)

This timer tries to download any missing firmware in the background every 10 minutes.

=cut

sub downloadAsync {
	my $file = shift;
	
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
		},
	);
	
	$http->get( $url );
}

=head2 downloadAsyncDone($http)

Callback after our firmware file has been downloaded.

=cut

sub downloadAsyncDone {
	my $http = shift;
	my $file = $http->params('file');
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
			file   => $file,
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
