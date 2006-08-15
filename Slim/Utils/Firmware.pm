package Slim::Utils::Firmware;

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This class downloads firmware during startup if it was
# not included with the distribution.  It uses synchronous
# download via LWP so that all firmware will be downloaded
# before any players connect.

use strict;

use Digest::SHA1;
use File::Slurp qw(read_file);
use File::Spec::Functions qw(:ALL);
use LWP::UserAgent;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;

# Models to download firmware for
our @models = qw( squeezebox squeezebox2 transporter );

# File location
our $dir = Slim::Utils::OSDetect::dirsFor('Firmware');

# Download location
our $base = 'http://update.slimdevices.com/update/firmware';

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
				next if $files->{$file};
				
				my $path = catdir( $dir, $file );
				
				if ( !-r $path ) {
					$::d_firmware && msg("Firmware: Need to download $file\n");
					$files->{$file} = 1;
				}
			}
		}
		
		close $fh;
	}
	
	for my $file ( keys %{$files} ) {
		my $url = $base . '/' . $file;
		
		download( $url, $file );
	}
}

# Download the file and verify it
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
				warn "Successfully downloaded and verified $file.\n";
				return 1;
			}
			
			unlink $path;
			
			fatal("Validation of firmware $file failed, SHA1 checksum did not match\n");
		}
		else {
			unlink $path;
			$error = $res2->status_line;
		}
	}
	else {
		$error = $res->status_line;
	}
	
	fatal("Unable to download firmware from $url: $error\n");
}

sub fatal {
	my $msg = shift;
	
	errorMsg($msg);
	
	main::stopServer();
}

1;
		