package Slim::Plugin::MusicMagic::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.musicmagic',
	'defaultLevel' => 'WARN',
});

sub name {
	return 'MUSICMAGIC';
}

sub page {
	return 'plugins/MusicMagic/settings/musicmagic.html';
}

sub handler {
	my ($class, $client, $params) = @_;

	# These are lame preference names.
	my @prefs = qw(
		musicmagic
		MMMPlayerSettings
		MMMSize
		MMMMixType
		MMMStyle
		MMMVariety
		MMMMixGenre
		MMMRejectType
		MMMRejectSize
		MMMFilter
		musicmagicscaninterval
		MMSport
		MusicMagicplaylistprefix
		MusicMagicplaylistsuffix
	);

	# Cleanup the checkbox
	$params->{'musicmagic'} = defined $params->{'musicmagic'} ? 1 : 0;

	if ($params->{'saveSettings'}) {

		if ($params->{'musicmagic'} != Slim::Utils::Prefs::get('musicmagic')) {

			for my $c (Slim::Player::Client::clients()) {

				Slim::Buttons::Home::updateMenu($c);
			}

			Slim::Music::Import->useImporter('Plugin::MusicMagic::Plugin', $params->{'musicmagic'});
		}

		for my $pref (@prefs) {

			# XXX - need validation!
			#'itunesscaninterval' => { 'validate' => \&Slim::Utils::Validate::number, },
			#'itunes_library_xml_path' => { 'validate' => \&Slim::Utils::Validate::isFile, },
			#'itunes_library_music_path' => { 'validate' => \&Slim::Utils::Validate::isDir, },

			Slim::Utils::Prefs::set($pref, $params->{$pref});
		}
	}

	for my $pref (@prefs) {

		$params->{'prefs'}->{$pref} = Slim::Utils::Prefs::get($pref);
	}
	$params->{'filters'}        = grabFilters();

	return $class->SUPER::handler($client, $params);
}

sub grabFilters {
	my @filters    = ();
	my %filterHash = ();
	
	my $MMSport = Slim::Utils::Prefs::get('MMSport');
	my $MMSHost = Slim::Utils::Prefs::get('MMSHost');

	$log->debug("Get filters list");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/filters",
		'create' => 0,
	});

	if ($http) {

		@filters = split(/\n/, $http->content);
		$http->close;

		if ($log->is_debug && scalar @filters) {

			$log->debug("Found filters:");

			for my $filter (@filters) {

				$log->debug("\t$filter");
			}
		}
	}

	my $none = sprintf('(%s)', Slim::Utils::Strings::string('NONE'));

	push @filters, $none;

	foreach my $filter ( @filters ) {

		if ($filter eq $none) {

			$filterHash{0} = $filter;
			next
		}

		$filterHash{$filter} = $filter;
	}

	return \%filterHash;
}



1;

__END__
