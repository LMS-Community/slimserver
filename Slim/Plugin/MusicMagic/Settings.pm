package Slim::Plugin::MusicMagic::Settings;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.musicip',
	'defaultLevel' => 'ERROR',
});

my %filterHash = ();

my $prefs = preferences('plugin.musicip');

$prefs->migrate(1, sub {
	$prefs->set('musicmagic',      Slim::Utils::Prefs::OldPrefs->get('musicmagic'));
	$prefs->set('scan_interval',   Slim::Utils::Prefs::OldPrefs->get('musicmagicscaninterval') || 3600            );
	$prefs->set('player_settings', Slim::Utils::Prefs::OldPrefs->get('MMMPlayerSettings') || 0                    );
	$prefs->set('port',            Slim::Utils::Prefs::OldPrefs->get('MMSport') || 10002                          );
	$prefs->set('mix_filter',      Slim::Utils::Prefs::OldPrefs->get('MMMFilter')                                 );
	$prefs->set('reject_size',     Slim::Utils::Prefs::OldPrefs->get('MMMRejectSize') || 0                        );
	$prefs->set('reject_type',     Slim::Utils::Prefs::OldPrefs->get('MMMRejectType')                             );
	$prefs->set('mix_genre',       Slim::Utils::Prefs::OldPrefs->get('MMMMixGenre')                               );
	$prefs->set('mix_variety',     Slim::Utils::Prefs::OldPrefs->get('MMMVariety') || 0                           );
	$prefs->set('mix_style',       Slim::Utils::Prefs::OldPrefs->get('MMMStyle') || 0                             );
	$prefs->set('mix_type',        Slim::Utils::Prefs::OldPrefs->get('MMMMixType')                                );
	$prefs->set('mix_size',        Slim::Utils::Prefs::OldPrefs->get('MMMSize') || 12                             );
	$prefs->set('playlist_prefix', Slim::Utils::Prefs::OldPrefs->get('MusicMagicplaylistprefix') || ''   );
	$prefs->set('playlist_suffix', Slim::Utils::Prefs::OldPrefs->get('MusicMagicplaylistsuffix') || ''            );

	$prefs->set('musicmagic', 0) unless defined $prefs->get('musicmagic'); # default to on if not previously set
	
	# use new naming of the old default wasn't changed
	if ($prefs->get('playlist_prefix') eq 'MusicMagic: ') {
		$prefs->set('playlist_prefix', 'MusicIP: ');
	}
	1;
});

$prefs->migrate(2, sub {
	my $oldPrefs = preferences('plugin.musicmagic'); 

	$prefs->set('musicip',         $oldPrefs->get('musicmagic'));
	$prefs->set('scan_interval',   $oldPrefs->get('scan_interval') || 3600          );
	$prefs->set('player_settings', $oldPrefs->get('player_settings') || 0           );
	$prefs->set('port',            $oldPrefs->get('port') || 10002                  );
	$prefs->set('mix_filter',      $oldPrefs->get('mix_filter')                     );
	$prefs->set('reject_size',     $oldPrefs->get('reject_size') || 0               );
	$prefs->set('reject_type',     $oldPrefs->get('reject_type')                    );
	$prefs->set('mix_genre',       $oldPrefs->get('mix_genre')                      );
	$prefs->set('mix_variety',     $oldPrefs->get('mix_variety') || 0               );
	$prefs->set('mix_style',       $oldPrefs->get('mix_style') || 0                 );
	$prefs->set('mix_type',        $oldPrefs->get('mix_type')                       );
	$prefs->set('mix_size',        $oldPrefs->get('mix_size') || 12                 );
	$prefs->set('playlist_prefix', $oldPrefs->get('playlist_prefix') || '' );
	$prefs->set('playlist_suffix', $oldPrefs->get('playlist_suffix') || ''          );

	my $prefix = $prefs->get('playlist_prefix');
	if ($prefix =~ /MusicMagic/) {
		$prefix =~ s/MusicMagic/MusicIP/g;
		$prefs->set('playlist_prefix', $prefix);
	}

	$prefs->remove('musicmagic');
	1;
});

$prefs->setValidate('num', qw(scan_interval port mix_variety mix_style reject_size));

$prefs->setChange(
	sub {
		my $newval = $_[1];
		
		if ($newval) {
			Slim::Plugin::MusicMagic::Plugin->initPlugin();
		}
		
		Slim::Music::Import->useImporter('Slim::Plugin::MusicMagic::Plugin', $_[1]);

		for my $c (Slim::Player::Client::clients()) {
			Slim::Buttons::Home::updateMenu($c);
		}
	},
	'musicip',
);

$prefs->setChange(
	sub {
			Slim::Utils::Timers::killTimers(undef, \&Slim::Plugin::MusicMagic::Plugin::checker);
			
			my $interval = $prefs->get('scan_interval') || 3600;
			
			$log->info("re-setting checker for $interval seconds from now.");
			
			Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + $interval, \&Slim::Plugin::MusicMagic::Plugin::checker);
	},
'scan_interval');


sub name {
	return Slim::Web::HTTP::protectName('MUSICMAGIC');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/MusicMagic/settings/musicmagic.html');
}

sub prefs {
	return ($prefs, qw(musicip scan_interval player_settings port mix_filter reject_size reject_type 
			   mix_genre mix_variety mix_style mix_type mix_size playlist_prefix playlist_suffix));
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ( !$params->{'saveSettings'} ) {

		$class->grabFilters($client, $params, $callback, @args);
		
		return undef;
	}
	
	$params->{'filters'} = getFilterList();

	return $class->SUPER::handler($client, $params);
}

sub grabFilters {
	my ($class, $client, $params, $callback, @args) = @_;
	
	my $MMSport = $prefs->get('port');
	my $MMSHost = $prefs->get('host');

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_gotFilters,
		sub {
			$log->error('Failed fetching filters from MusicIP');
			_fetchingFiltersDone(shift);
		},
		{
			client   => $client,
			params   => $params,
			callback => $callback,
			class    => $class,
			args     => \@args,
			timeout  => 5,
#			cacheTime => 0
		}
	);

	$http->get( "http://$MMSHost:$MMSport/api/filters" );
}

sub getFilterList {
	return \%filterHash;
}

sub _gotFilters {
	my $http = shift;

	my @filters = ();

	if ($http) {

		@filters = split(/\n/, $http->content);

		if ($log->is_debug && scalar @filters) {

			$log->debug("Found filters:");

			for my $filter (@filters) {

				$log->debug("\t$filter");
			}
		}
	}

	my $none = sprintf('(%s)', Slim::Utils::Strings::string('NONE'));

	push @filters, $none;
	%filterHash = ();

	foreach my $filter ( @filters ) {

		if ($filter eq $none) {

			$filterHash{0} = $filter;
			next
		}

		$filterHash{$filter} = $filter;
	}

	# remove filter from client settings if it doesn't exist any more
	foreach my $client (Slim::Player::Client::clients()) {

		unless ( $filterHash{ $prefs->client($client)->get('mix_filter') } ) {

			$log->warn('Filter "' . $prefs->client($client)->get('mix_filter') . '" does no longer exist - resetting');
			$prefs->client($client)->set('mix_filter', 0);

		}

	}

	unless ( $filterHash{ $prefs->get('mix_filter') } ) {

		$log->warn('Filter "' . $prefs->get('mix_filter') . '" does no longer exist - resetting');
		$prefs->set('mix_filter', 0);

	}
	
	_fetchingFiltersDone($http);
}

sub _fetchingFiltersDone {
	my $http = shift;

	my $client   = $http->params('client');
	my $params   = $http->params('params');
	my $callback = $http->params('callback');
	my $class    = $http->params('class');
	my @args     = @{$http->params('args')};

	$params->{'filters'} = \%filterHash;

	if ($callback && $class) {		
		my $body = $class->SUPER::handler($client, $params);
		$callback->( $client, $params, $body, @args );	
	}
}

1;

__END__
