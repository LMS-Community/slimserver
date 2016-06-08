package Slim::Utils::Light;

# $Id:  $

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This module provides some functions compatible with functions
# from the core Logitech Media Server code, without their overhead.
# These functions are called by helper applications like SqueezeTray
# or the control panel. 

use Exporter::Lite;
@ISA = qw(Exporter);

use Config;
use FindBin qw($Bin);
use File::Spec::Functions qw(catfile catdir);

our @EXPORT = qw(string getPref);
my ($os, $language, %strings, $stringsLoaded);

BEGIN {
	my @SlimINC = ();

	# NB: The user may be on a platform who's perl reports a
	# different x86 version than we've supplied - but it may work
	# anyways.
	my $arch = $Config::Config{'archname'};
	   $arch =~ s/^i[3456]86-/i386-/;
	   $arch =~ s/gnu-//;
	
	# Check for use64bitint Perls
	my $is64bitint = $arch =~ /64int/;

	# Some ARM platforms use different arch strings, just assume any arm*linux system
	# can run our binaries, this will fail for some people running invalid versions of Perl
	# but that's OK, they'd be broken anyway.
	if ( $arch =~ /^arm.*linux/ ) {
		$arch = $arch =~ /gnueabihf/ 
			? 'arm-linux-gnueabihf-thread-multi' 
			: 'arm-linux-gnueabi-thread-multi';
		$arch .= '-64int' if $is64bitint;
	}
	
	# Same thing with PPC
	if ( $arch =~ /^(?:ppc|powerpc).*linux/ ) {
		$arch = 'powerpc-linux-thread-multi';
		$arch .= '-64int' if $is64bitint;
	}

	my $perlmajorversion = $Config{'version'};
	   $perlmajorversion =~ s/\.\d+$//;

	my $libPath = $Bin;

	use Slim::Utils::OSDetect;
	Slim::Utils::OSDetect::init();

	if (my $libs = Slim::Utils::OSDetect::dirsFor('libpath')) {
		# On Debian, RH and SUSE, our CPAN directory is located in the same dir as strings.txt
		$libPath = $libs;
	};

	@SlimINC = (
		catdir($libPath,'CPAN','arch',$perlmajorversion, $arch),
		catdir($libPath,'CPAN','arch',$perlmajorversion, $arch, 'auto'),
		catdir($libPath,'CPAN','arch',$Config{'version'}, $Config::Config{'archname'}),
		catdir($libPath,'CPAN','arch',$Config{'version'}, $Config::Config{'archname'}, 'auto'),
		catdir($libPath,'CPAN','arch',$perlmajorversion, $Config::Config{'archname'}),
		catdir($libPath,'CPAN','arch',$perlmajorversion, $Config::Config{'archname'}, 'auto'),
		catdir($libPath,'CPAN','arch',$Config::Config{'archname'}),
		catdir($libPath,'CPAN','arch',$perlmajorversion),
		catdir($libPath,'lib'), 
		catdir($libPath,'CPAN'), 
		$libPath,
	);

	# This works like 'use lib'
	# prepend our directories to @INC so we look there first.
	unshift @INC, @SlimINC;

	$os = Slim::Utils::OSDetect->getOS();
}

my ($serverPrefFile, $versionFile);

# return localised version of string token
sub string {
	my $name = shift;
	
	loadStrings() unless $stringsLoaded;
	
	$language ||= getPref('language') || $os->getSystemLanguage();
		
	my $lang = shift || $language;
	
	my $string = $strings{ $name }->{ $lang } || $strings{ $name }->{ $language } || $strings{ $name }->{'EN'} || $name;
	
	if ( @_ ) {
		$string = sprintf( $string, @_ );
	}	
	
	return $string;
}

sub loadStrings {
	my $string     = '';
	my $language   = '';
	my $stringname = '';

	# server string file
	my $file;

	# let's see whether this is a PerlApp/Tray compiled executable
	if (defined $PerlApp::VERSION) {
		$file = PerlApp::extract_bound_file('strings.txt');
	}
	elsif (defined $PerlTray::VERSION) {
		$file = PerlTray::extract_bound_file('strings.txt');
	}
	
	# try to find the strings.txt file from our installation
	unless ($file && -f $file) {
		my $path = $os->dirsFor('strings');
		$file = catdir($path, 'strings.txt');
	}
	
	open(STRINGS, "<:utf8", $file) || do {
		warn "Couldn't open file [$file]!";
		return;
	};

	foreach my $line (<STRINGS>) {

		chomp($line);
		
		next if $line =~ /^#/;
		next if $line !~ /\S/;

		if ($line =~ /^(\S+)$/) {

			$stringname = $1;
			$string = '';
			next;

		} elsif ($line =~ /^\t(\S*)\t(.+)$/) {

			$language = uc($1);
			$string   = $2;

			$strings{$stringname}->{$language} = $string;
		}
	}

	close STRINGS;
	
	$stringsLoaded = 1;
}

sub setString {
	my ($stringname, $string) = @_;
	
	loadStrings() unless $stringsLoaded;

	$language ||= getPref('language') || $os->getSystemLanguage();

	$strings{$stringname}->{$language} = $string;	
}


# Read pref from the server preference file - lighter weight than loading YAML
# don't call this too often, it's in no way optimized for speed
sub getPref {
	my $pref = shift;
	my $prefFile = shift;

	if ($prefFile) {
		$prefFile = catdir($os->dirsFor('prefs'), 'plugin', $prefFile);
	}
	else {
		$serverPrefFile ||= catfile( scalar($os->dirsFor('prefs')), 'server.prefs' );
		$prefFile = $serverPrefFile;
	}

	require YAML::XS;
	
	my $prefs = eval { YAML::XS::LoadFile($prefFile) };

	my $ret;

	if (!$@) {
		$ret = $prefs->{$pref};
	}

#	if (-r $prefFile) {
#
#		if (open(PREF, $prefFile)) {
#
#			local $_;
#			while (<PREF>) {
#			
#				# read YAML (server) and old style prefs (installer)
#				if (/^$pref(:| \=)? (.+)$/) {
#					$ret = $2;
#					$ret =~ s/^['"]//;
#					$ret =~ s/['"\s]*$//s;
#					last;
#				}
#			}
#
#			close(PREF);
#		}
#	}

	return $ret;
}

sub checkForUpdate {
	
	$versionFile ||= catfile( scalar($os->dirsFor('updates')), 'server.version' );
	
	open(UPDATEFLAG, $versionFile) || return '';
	
	my $installer = '';
	
	local $_;
	while ( <UPDATEFLAG> ) {

		chomp;
		
		if (/(?:LogitechMediaServer|Squeezebox|SqueezeCenter).*/i) {
			$installer = $_;
			last;
		}
	}
		
	close UPDATEFLAG;
	
	return $installer if ($installer && -r $installer);	
}

sub resetUpdateCheck {
	unlink $versionFile if $versionFile && -r $versionFile;
}

1;
