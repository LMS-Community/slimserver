package Slim::Web::Settings::Server::Basic;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');
my $log = logger('scan.scanner');

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

		my $rescanType = Slim::Music::Import->getScanCommand($paramRef->{'pref_rescantype'});

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

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("Initiating scan of type: %s", join(' ', @$rescanType)));
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

		my $ignoreFolders = [];

		my $singleDirScan;
		for (my $i = 0; defined $paramRef->{"pref_mediadirs$i"}; $i++) {
			if (my $path = $paramRef->{"pref_mediadirs$i"}) {
				main::INFOLOG && $log->is_info && $log->info('Path information for single dir scan: ' . Data::Dump::dump({
					oldPath => $oldPaths{$path},
					path => $path
				}));

				delete $oldPaths{$path};
				push @paths, $path;

				if ($paramRef->{"pref_rescan_mediadir$i"}) {
					$singleDirScan = Slim::Utils::Misc::fileURLFromPath($path);
				}

				push @{ $ignoreFolders }, $path if !$paramRef->{"pref_ignoreInAudioScan$i"};
			}
		}

		$prefs->set('ignoreInAudioScan', $ignoreFolders);

		my $oldCount = scalar @{ $prefs->get('mediadirs') || [] };

		if ( main::INFOLOG && $log->is_info ) {
			$log->info('Path information for single dir scan: ' . Data::Dump::dump({
				oldPaths => \%oldPaths,
				paths => \@paths,
				singleDirScan => $singleDirScan
			}));
		}

		if ( keys %oldPaths || !$oldCount || scalar @paths != $oldCount ) {
			main::INFOLOG && $log->is_info && $log->info("Triggering scan...");
			$prefs->set('mediadirs', \@paths);
		}
		# only run single folder scan if the paths haven't changed (which would trigger a rescan anyway)
		elsif ( $singleDirScan ) {
			main::INFOLOG && $log->is_info && $log->info("Triggering singleDirScan ($singleDirScan)");
			Slim::Control::Request::executeRequest( undef, [ 'rescan', 'full', $singleDirScan ] );
			$runScan = 1;
		}
	}

	$paramRef->{'newVersion'}  = $::newVersion;
	$paramRef->{'languageoptions'} = Slim::Utils::Strings::languageOptions();

	my $ignoreFolders = {
		map { $_, 1 } @{ $prefs->get('ignoreInAudioScan') || [''] },
	};

	$paramRef->{mediadirs} = [];
	foreach ( @{  $prefs->get('mediadirs') || [''] } ) {
		push @{ $paramRef->{mediadirs} }, {
			path  => $_,
			audio => $ignoreFolders->{$_},
		}
	}

	# add an empty input field for an additional mediadir input field
	push @{$paramRef->{mediadirs}}, {
		path  => '',
	};

	my $scanTypes = Slim::Music::Import->getScanTypes();
	$paramRef->{'scanTypes'} = { map { $_ => $scanTypes->{$_}->{name} } grep /\d.+/, keys %$scanTypes };

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
