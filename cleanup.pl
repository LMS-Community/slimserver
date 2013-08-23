#!/usr/bin/perl -ICPAN

# Logitech Media Server Copyright 2001-2009 Logitech.
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

use constant SPLASH_LOGO => 'lms_splash.png';
use constant ISWINDOWS    => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant ISMAC        => ( $^O =~ /darwin/i ) ? 1 : 0;

# don't use Wx, if script is run using perl on OSX, it needs to be run using wxperl
my $splash;
my $useWx = (!ISMAC || $^X =~ /wxPerl/i) && eval {
	require Wx;
	
	showSplashScreen();
	
	require Wx::Event;
	require Slim::GUI::ControlPanel;

	return 1;
};

print "$@\n" if $@ && ISWINDOWS;

use strict;
use Socket;
use utf8;

use constant SLIM_SERVICE => 0;
use constant SCANNER      => 0;
use constant RESIZER      => 0;
use constant DEBUG        => 1;
use constant TRANSCODING  => 0;
use constant PERFMON      => 0;
use constant DEBUGLOG     => 0;
use constant INFOLOG      => 0;
use constant STATISTICS   => 0;
use constant SB1SLIMP3SYNC=> 0;
use constant WEBUI        => 0;
use constant LOCALFILE    => 0;

# load these later, don't need them right now
require File::Path;
require File::Spec::Functions;
require Getopt::Long;

require Slim::Utils::OSDetect;
require Slim::Utils::Light;

our $VERSION = '7.8.0';

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

	my ($all, $cache, $filecache, $database, $prefs, $logs, $dryrun);
	
	Getopt::Long::GetOptions(
		'all'       => \$all,
		'cache'     => \$cache,
		'filecache' => \$filecache,
		'prefs'     => \$prefs,
		'logs'      => \$logs,
		'database'  => \$database,
		'dryrun'    => \$dryrun,
	);
	
	my $folders = getFolderList({
		'all'       => $all,
		'cache'     => $cache,
		'filecache' => $filecache,
		'prefs'     => $prefs,
		'logs'      => $logs,
		'database'  => $database,
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

	cleanup($folders, $dryrun);
	
	print sprintf("\n%s\n\n", Slim::Utils::Light::string('CLEANUP_PLEASE_RESTART_SC'));
}

sub usage {
	my $usage = <<EOF;
%s: $0 [--all] [--cache] [--database] [--filecache] [--prefs] [--logs]

%s

	--database     %s
	--filecache    %s
	--prefs        %s
	--logs         %s

	--cache   (!)  %s

	--all     (!!) %s
	
	--dryrun       %s
	
EOF
	print sprintf($usage, 
		Slim::Utils::Light::string('CLEANUP_USAGE'), 
		Slim::Utils::Light::string('CLEANUP_COMMAND_LINE'),
		Slim::Utils::Light::string('CLEANUP_DB'),
		Slim::Utils::Light::string('CLEANUP_FILECACHE'),
		Slim::Utils::Light::string('CLEANUP_PREFS'),
		Slim::Utils::Light::string('CLEANUP_LOGS'),
		Slim::Utils::Light::string('CLEANUP_CACHE'),
		Slim::Utils::Light::string('CLEANUP_ALL'),
		Slim::Utils::Light::string('CLEANUP_DRYRUN'),
	);
}

sub getFolderList {
	my $args = shift;
	
	my @folders;
	my $cacheFolder = Slim::Utils::Light::getPref('cachedir') || $os->dirsFor('cache');

	push @folders, _target('cache', 'cache') if ($args->{all} || $args->{cache});
	
	if ($args->{all} || $args->{prefs} || $args->{cache} || $args->{filecache} || $args->{logs} || $args->{database}) {
		push @folders, {
			label   => 'some legacy files',
			folders => [
				File::Spec::Functions::catdir($cacheFolder, 'MySQL'),
				File::Spec::Functions::catdir($cacheFolder, 'my.cnf'),
				File::Spec::Functions::catdir($cacheFolder, 'squeezecenter-mysql.pid'),
				File::Spec::Functions::catdir($cacheFolder, 'squeezecenter-mysql.sock'),
				File::Spec::Functions::catdir($cacheFolder, 'mysql-error-log.txt'),
				File::Spec::Functions::catdir($cacheFolder, 'squeezebox.db'),
				File::Spec::Functions::catdir($cacheFolder, 'squeezebox.db-shm'),
				File::Spec::Functions::catdir($cacheFolder, 'squeezebox.db-wal'),
				File::Spec::Functions::catdir($cacheFolder, 'squeezebox-persistent.db'),
				File::Spec::Functions::catdir($cacheFolder, 'squeezebox-persistent.db-shm'),
				File::Spec::Functions::catdir($cacheFolder, 'squeezebox-persistent.db-wal'),
				File::Spec::Functions::catdir($cacheFolder, 'ArtworkCache.db'),
				File::Spec::Functions::catdir($cacheFolder, 'ArtworkCache.db-shm'),
				File::Spec::Functions::catdir($cacheFolder, 'ArtworkCache.db-wal'),
			],
		};
	}
	
	if ($args->{filecache}) {
		push @folders, {
			label   => 'file cache (artwork, templates etc.)',
			folders => [
				File::Spec::Functions::catdir($cacheFolder, 'Artwork'),
				File::Spec::Functions::catdir($cacheFolder, 'ArtworkCache'),
				File::Spec::Functions::catdir($cacheFolder, 'iTunesArtwork'),
				File::Spec::Functions::catdir($cacheFolder, 'FileCache'),
				File::Spec::Functions::catdir($cacheFolder, 'fonts.bin'),
				File::Spec::Functions::catdir($cacheFolder, 'strings.bin'),
				File::Spec::Functions::catdir($cacheFolder, 'templates'),
				File::Spec::Functions::catdir($cacheFolder, 'updates'),
				File::Spec::Functions::catdir($cacheFolder, 'cookies.dat'),
				File::Spec::Functions::catdir($cacheFolder, 'plugin-data.yaml'),

				File::Spec::Functions::catdir($cacheFolder, 'cache.db'),
				File::Spec::Functions::catdir($cacheFolder, 'cache.db-shm'),
				File::Spec::Functions::catdir($cacheFolder, 'cache.db-wal'),

				File::Spec::Functions::catdir($cacheFolder, 'artwork.db'),
				File::Spec::Functions::catdir($cacheFolder, 'artwork.db-shm'),
				File::Spec::Functions::catdir($cacheFolder, 'artwork.db-wal'),
			],
		};
	}
		
	if ($args->{database}) {
		push @folders, {
			label   => 'Musiclibrary data',
			folders => [
				File::Spec::Functions::catdir($cacheFolder, 'libmediascan.db'),
				File::Spec::Functions::catdir($cacheFolder, '__db.001'),
				File::Spec::Functions::catdir($cacheFolder, '__db.002'),
				File::Spec::Functions::catdir($cacheFolder, '__db.003'),
				File::Spec::Functions::catdir($cacheFolder, 'library.db'),
				File::Spec::Functions::catdir($cacheFolder, 'library.db-shm'),
				File::Spec::Functions::catdir($cacheFolder, 'library.db-wal'),
				File::Spec::Functions::catdir($cacheFolder, 'persist.db'),
				File::Spec::Functions::catdir($cacheFolder, 'persist.db-shm'),
				File::Spec::Functions::catdir($cacheFolder, 'persist.db-wal'),
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
	
			name     => 'database',
			title    => Slim::Utils::Light::string('CLEANUP_DB'),
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
	my ($folders, $dryrun) = @_;

	for my $item (@$folders) {
		print sprintf("\n%s %s...\n", Slim::Utils::Light::string('CLEANUP_DELETING'), $item->{label}) unless $useWx;
		
		foreach ( @{$item->{folders}} ) {
			next unless $_;
			
			print "-> $_\n" if (-e $_ && !$useWx);
			
			next if $dryrun;

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
			Wx::wxSPLASH_CENTRE_ON_SCREEN() | Wx::wxSPLASH_NO_TIMEOUT(),
			0,
			undef,
			-1, [-1, -1], [-1, -1],
			Wx::wxSIMPLE_BORDER() | Wx::wxSTAY_ON_TOP()
		);

	}
}

main();

__END__
