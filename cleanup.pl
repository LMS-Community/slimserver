#!/usr/bin/perl -w -ICPAN

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

require 5.008_001;

use constant SPLASH_LOGO => 'logitech-squeezebox.png';

# don't use Wx, if script is run using perl on OSX, it needs to be run using wxperl
my $splash;
my $useWx = ($^O !~ /darwin/ || $^X =~ /wxPerl/i) && eval {
	require Wx;
	
	showSplashScreen();
	
	require Wx::Event;
	require Slim::GUI::ControlPanel;

	return 1;
};

print "$@\n" if $@;

use strict;
use Socket;
use utf8;

use constant SLIM_SERVICE => 0;
use constant SCANNER      => 0;
use constant RESIZER      => 0;
use constant DEBUG        => 1;
use constant ISWINDOWS    => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant ISMAC        => ( $^O =~ /darwin/i ) ? 1 : 0;

# load these later, don't need them right now
require File::Path;
require File::Spec::Functions;
require Getopt::Long;

require Slim::Utils::OSDetect;
require Slim::Utils::Light;

our $VERSION = '7.4';

BEGIN {
	if (ISWINDOWS) {
		eval { require Wx::Perl::Packager; }
	}
}


if (DEBUG && $@) {
	print "GUI can't be loaded: $@\n";
}

my ($os);

sub main {
	Slim::Utils::OSDetect::init();
	$os = Slim::Utils::OSDetect->getOS();
	
	if (checkForSC() && !$useWx) {
		print sprintf("\n%s\n\n", Slim::Utils::Light::string('CLEANUP_PLEASE_STOP_SC'));
		exit;
	}

	my ($all, $cache, $filecache, $mysql, $prefs, $logs);
	
	Getopt::Long::GetOptions(
		'all'       => \$all,
		'cache'     => \$cache,
		'filecache' => \$filecache,
		'prefs'     => \$prefs,
		'logs'      => \$logs,
		'mysql'     => \$mysql,
	);
	
	my $folders = getFolderList({
		'all'       => $all,
		'cache'     => $cache,
		'filecache' => $filecache,
		'prefs'     => $prefs,
		'logs'      => $logs,
		'mysql'     => $mysql,
	});
		
	unless (scalar @$folders) {

		# show simple GUI if possible
		if ($useWx) {
			
			my $app = Slim::GUI::ControlPanel->new({
				folderCB => \&getFolderList,
				cleanCB  => \&cleanup,
				options  => options(),
			});
	
			$splash->Destroy();
	
			$app->MainLoop;
			exit;
		}

		else {		
			usage();
			exit;
		}
	}

	cleanup($folders);
	
	print sprintf("\n%s\n\n", Slim::Utils::Light::string('CLEANUP_PLEASE_RESTART_SC'));
}

sub usage {
	my $usage = <<EOF;
%s: $0 [--all] [--cache] [--mysql] [--filecache] [--prefs] [--logs]

%s

	--mysql        %s
	--filecache    %s
	--prefs        %s
	--logs         %s

	--cache   (!)  %s

	--all     (!!) %s
	
EOF
	print sprintf($usage, 
		Slim::Utils::Light::string('CLEANUP_USAGE'), 
		Slim::Utils::Light::string('CLEANUP_COMMAND_LINE'),
		Slim::Utils::Light::string('CLEANUP_MYSQL'),
		Slim::Utils::Light::string('CLEANUP_FILECACHE'),
		Slim::Utils::Light::string('CLEANUP_PREFS'),
		Slim::Utils::Light::string('CLEANUP_LOGS'),
		Slim::Utils::Light::string('CLEANUP_CACHE'),
		Slim::Utils::Light::string('CLEANUP_ALL'),
	);
}

sub getFolderList {
	my $args = shift;
	
	my @folders;
	my $cacheFolder = Slim::Utils::Light::getPref('cachedir') || $os->dirsFor('cache');

	push @folders, _target('cache', 'cache') if ($args->{all} || $args->{cache});
	
	if ($args->{filecache}) {
		push @folders, {
			label   => 'file cache (artwork, templates etc.)',
			folders => [
				File::Spec::Functions::catdir($cacheFolder, 'Artwork'),
				File::Spec::Functions::catdir($cacheFolder, 'iTunesArtwork'),
				File::Spec::Functions::catdir($cacheFolder, 'FileCache'),
				File::Spec::Functions::catdir($cacheFolder, 'fonts.bin'),
				File::Spec::Functions::catdir($cacheFolder, 'strings.bin'),
				File::Spec::Functions::catdir($cacheFolder, 'templates'),
				File::Spec::Functions::catdir($cacheFolder, 'cookies.dat'),
				File::Spec::Functions::catdir($cacheFolder, 'plugin-data.yaml'),
			],
		};
	}
		
	if ($args->{mysql}) {
		push @folders, {
			label   => 'MySQL data',
			folders => [
				File::Spec::Functions::catdir($cacheFolder, 'MySQL'),
				File::Spec::Functions::catdir($cacheFolder, 'my.cnf'),
				File::Spec::Functions::catdir($cacheFolder, 'squeezecenter-mysql.pid'),
				File::Spec::Functions::catdir($cacheFolder, 'squeezecenter-mysql.sock'),
				File::Spec::Functions::catdir($cacheFolder, 'mysql-error-log.txt'),
			],
		};
	}
		
	if ($args->{all} || $args->{prefs}) {
		push @folders, _target('prefs', 'preferences');
		push @folders, _target('oldprefs', 'old preferences (SlimServer <= 6.5)');
	}
	
	push @folders, _target('log', 'logs') if ($args->{all} || $args->{logs});

	return \@folders;
}

sub _target {
	my ($value, $label) = @_;
	
	my $f = $os->dirsFor($value);
	
	return {
		label   => $label,
		folders => [ $f ],
	};
}

sub options {
	
	my $options = [
		{
			name     => 'prefs',
			title    => Slim::Utils::Light::string('CLEANUP_PREFS'),
			position => [30, 20],
		},
	
		{
			name     => 'filecache',
			title    => Slim::Utils::Light::string('CLEANUP_FILECACHE'),
			position => [30, 40],
		},
	
		{
	
			name     => 'mysql',
			title    => Slim::Utils::Light::string('CLEANUP_MYSQL'),
			position => [30, 60],
		},
	
		{
	
			name     => 'logs',
			title    => Slim::Utils::Light::string('CLEANUP_LOGS'),
			position => [30, 80],
		},
	
		{
	
			name     => 'cache',
			title    => Slim::Utils::Light::string('CLEANUP_CACHE'),
			position => [30, 120],
		},
	
		{
	
			name     => 'all',
			title    => '(!) ' . Slim::Utils::Light::string('CLEANUP_ALL'),
			position => [30, 160],
		},
	];

	return $options;
}

sub checkForSC {
	my $iaddr = inet_aton('127.0.0.1');
	my $paddr = sockaddr_in(3483, $iaddr);

	socket(SSERVER, PF_INET, SOCK_STREAM, getprotobyname('tcp'));

	if (connect(SSERVER, $paddr)) {

		close(SSERVER);
		return 1;
	}

	return 0;
}

sub cleanup {
	my $folders = shift;

	my $fallbackFolder = $os->dirsFor('');
		
	for my $item (@$folders) {
		print sprintf("\n%s %s...\n", Slim::Utils::Light::string('CLEANUP_DELETING'), $item->{label}) unless $useWx;
		
		foreach ( @{$item->{folders}} ) {
			next unless $_;
			
			print "-> $_\n" if (-e $_ && !$useWx);

			if (-d $_) {
				File::Path::rmtree($_);
			}
			
			elsif (-f $_) {
				unlink $_;
			}
		}
	}
}

sub showSplashScreen {
	return unless $^O =~ /win/i;
	
	my $file;
	
	if (defined $PerlApp::VERSION) {
		$file = PerlApp::extract_bound_file(SPLASH_LOGO);
	}
	
	if (!$file || !-f $file) {
		$file = '../platforms/win32/res/' . SPLASH_LOGO;
	}

	Wx::Image::AddHandler(Wx::PNGHandler->new());
	
	if (my $bitmap = Wx::Bitmap->new($file, Wx::wxBITMAP_TYPE_PNG())) {

		$splash = Wx::SplashScreen->new(
			$bitmap, 
			Wx::wxSPLASH_CENTRE_ON_SCREEN() | Wx::wxSPLASH_TIMEOUT(),
			10000,
			undef,
			-1, [-1, -1], [-1, -1],
			Wx::wxSIMPLE_BORDER() | Wx::wxSTAY_ON_TOP()
		);

	}
}

main();

__END__
