package Slim::Utils::OS::SlimService;

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

1;