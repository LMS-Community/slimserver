package Slim::Utils::OS::SlimService;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

use base qw(Slim::Utils::OS::Unix);

sub dirsFor {
	my ($class, $dir) = @_;

	$dir ||= '';
	
	my @dirs   = ();
	my $prefix = $^O eq 'linux' ? '/home/svcprod/ss' : $Bin;
	
	if ($dir eq "Plugins") {
		push @dirs, catdir($Bin, 'Slim', 'Plugin');
		
		# load SN-only plugins
		push @dirs, catdir( $main::SN_PATH, 'lib', 'Slim', 'Plugin' );
	}

	# slimservice on squeezenetwork
	if ( $dir =~ /^(?:strings|revision|convert|types)$/ ) {
		push @dirs, $Bin;
	}
	
	elsif ( $dir eq 'log' ) {
		if ( $::logdir ) {
			push @dirs, $::logdir;
		}
		elsif ( $^O eq 'linux' ) {
			push @dirs, '/home/svcprod/ss/logs';
		}
		else {
			push @dirs, catdir( $prefix, $dir );
		}
	}
	
	elsif ( $dir =~ /^(cache|prefs)$/ ) {
		push @dirs, catdir( $prefix, $1 );
	}
	
	elsif ( $dir =~ /^(?:music|playlists)$/ ) {
		push @dirs, '';
	}
	
	# we don't want these values to return a value
	elsif ($dir =~ /^(?:libpath|mysql-language)$/) {
	
	}
	
	else {
		push @dirs, catdir( $Bin, $dir );
	}

	return wantarray() ? @dirs : $dirs[0];
}

sub getSystemLanguage { 'EN' }

sub migratePrefsFolder {};

sub skipPlugins {
	my $class = shift;
	
	return (
		qw(Podcast JiveExtras MusicMagic MyRadio PreventStandby RS232 RandomPlay Rescan SavePlaylist SlimTris Snow SN iTunes xPL NetTest UPnP ImageBrowser),
		$class->SUPER::skipPlugins(),
	);
}

# XXX: I don't think we even need this anymore
sub sqlHelperClass { 'Slim::Utils::SQLiteHelper' }

1;
