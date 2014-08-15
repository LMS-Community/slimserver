package Slim::Web::Settings::Server::Basic;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('BASIC_SERVER_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/server/basic.html');
}

sub prefs {
	return ($prefs, qw(language playlistdir libraryname) );
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	
	# tell the server not to trigger a rescan immediately, but let it queue up requests
	# this is neede to prevent multiple scans to be triggered by change handlers for paths etc.
	Slim::Music::Import->doQueueScanTasks(1);
	my $runScan;

	if ($paramRef->{'pref_rescan'}) {

		my $rescanType = ['rescan'];

		if ($paramRef->{'pref_rescantype'} eq '2wipedb') {

			$rescanType = ['wipecache'];

		} elsif ($paramRef->{'pref_rescantype'} eq '3playlist') {

			$rescanType = [qw(rescan playlists)];
		}

		for my $pref (qw(playlistdir)) {

			my (undef, $ok) = $prefs->set($pref, $paramRef->{"pref_$pref"});

			if ($ok) {
				$paramRef->{'validated'}->{$pref} = 1; 
			}
			else { 
				$paramRef->{'warning'} .= sprintf(Slim::Utils::Strings::string('SETTINGS_INVALIDVALUE'), $paramRef->{"pref_$pref"}, $pref) . '<br/>';
				$paramRef->{'validated'}->{$pref} = 0;
			}
		}

		if ( main::INFOLOG && logger('scan.scanner')->is_info ) {
			logger('scan.scanner')->info(sprintf("Initiating scan of type: %s",join (" ",@{$rescanType})));
		}

		Slim::Control::Request::executeRequest(undef, $rescanType);
		$runScan = 1;
	}
	
	if ( $paramRef->{'saveSettings'} ) {
		my $curLang = $prefs->get('language');
		my $lang    = $paramRef->{'pref_language'};

		if ( $lang && $lang ne $curLang ) {
			# use Classic instead of Default skin if the server's language is set to Hebrew
			if ($lang eq 'HE' && $prefs->get('skin') eq 'Default') {
				$prefs->set('skin', 'Classic');
				$paramRef->{'warning'} .= '<span id="popupWarning">' . Slim::Utils::Strings::string("SETUP_SKIN_OK") . '</span>';
			}	

			# Bug 5740, flush the playlist cache
			for my $client (Slim::Player::Client::clients()) {
				$client->currentPlaylistChangeTime(Time::HiRes::time());
			}
		}
		
		# handle paths
		my @paths;
		my %oldPaths = map { $_ => 1 } @{ $prefs->get('mediadirs') || [] };

		my $ignoreFolders = {
			audio => [],
			video => [],
			image => [],
		};

		my $singleDirScan;
		for (my $i = 0; defined $paramRef->{"pref_mediadirs$i"}; $i++) {
			if (my $path = $paramRef->{"pref_mediadirs$i"}) {
				delete $oldPaths{$path};
				push @paths, $path;

				if ($paramRef->{"pref_rescan_mediadir$i"}) {
					$singleDirScan = Slim::Utils::Misc::fileURLFromPath($path);
				}
				
				push @{ $ignoreFolders->{audio} }, $path if !$paramRef->{"pref_ignoreInAudioScan$i"};
				push @{ $ignoreFolders->{video} }, $path if !$paramRef->{"pref_ignoreInVideoScan$i"};
				push @{ $ignoreFolders->{image} }, $path if !$paramRef->{"pref_ignoreInImageScan$i"};
			}
		}
		
		$prefs->set('ignoreInAudioScan', $ignoreFolders->{audio});
		$prefs->set('ignoreInVideoScan', $ignoreFolders->{video});
		$prefs->set('ignoreInImageScan', $ignoreFolders->{image});

		my $oldCount = scalar @{ $prefs->get('mediadirs') || [] };
		
		if ( keys %oldPaths || !$oldCount || scalar @paths != $oldCount ) {
			$prefs->set('mediadirs', \@paths);
		}
		# only run single folder scan if the paths haven't changed (which would trigger a rescan anyway)
		elsif ( $singleDirScan ) {
			Slim::Control::Request::executeRequest( undef, [ 'rescan', 'full', $singleDirScan ] );
			$runScan = 1;
		}
	}

	$paramRef->{'newVersion'}  = $::newVersion;
	$paramRef->{'languageoptions'} = Slim::Utils::Strings::languageOptions();
	
	my $ignoreFolders = {
		audio => { map { $_, 1 } @{ Slim::Utils::Misc::getDirsPref('ignoreInAudioScan') } },
		video => { map { $_, 1 } @{ Slim::Utils::Misc::getDirsPref('ignoreInVideoScan') } },
		image => { map { $_, 1 } @{ Slim::Utils::Misc::getDirsPref('ignoreInImageScan') } },
	};
	
	$paramRef->{mediadirs} = [];
	foreach ( @{ Slim::Utils::Misc::getMediaDirs() } ) {
		push @{ $paramRef->{mediadirs} }, {
			path  => $_,
			audio => $ignoreFolders->{audio}->{$_},
			video => $ignoreFolders->{video}->{$_},
			image => $ignoreFolders->{image}->{$_},
		}
	}

	# add an empty input field for an additional mediadir input field
	push @{$paramRef->{mediadirs}}, {
		path  => '',
	};

	$paramRef->{'noimage'} = 1 if !(main::IMAGE && main::MEDIASUPPORT);
	$paramRef->{'novideo'} = 1 if !(main::VIDEO && main::MEDIASUPPORT);

	Slim::Music::Import->doQueueScanTasks(0);
	Slim::Music::Import->nextScanTask() if $runScan || !$prefs->get('dontTriggerScanOnPrefChange');

	return $class->SUPER::handler($client, $paramRef);
}

sub beforeRender {
	my ($class, $paramRef) = @_;
	$paramRef->{'scanning'} = Slim::Music::Import->stillScanning;
}

1;

__END__
