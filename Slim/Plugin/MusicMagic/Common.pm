package Slim::Plugin::MusicMagic::Common;

# $Id$

# Copyright 2001-2011 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use URI::Escape;

use Slim::Utils::Log;
use Slim::Utils::Strings;
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;

*escape = main::ISWINDOWS ? \&URI::Escape::uri_escape : \&URI::Escape::uri_escape_utf8;

my $log = logger('plugin.musicip');

my $prefs = preferences('plugin.musicip');

my $defaults = {
	musicip         => 0,
	mix_filter      => '',
	mix_genre       => '',
	mix_type        => 0,
	mix_style       => 0,
	mix_variety     => 0,
	mix_size        => 50,
	playlist_prefix => '',
	playlist_suffix => '',
	reject_type     => 0,
	reject_size     => 50,
	scan_interval   => 3600,
	port            => 10002,
};

$prefs->init($defaults);

$prefs->migrate(1, sub {
	$prefs->set('musicmagic',      Slim::Utils::Prefs::OldPrefs->get('musicmagic'));
	$prefs->set('scan_interval',   Slim::Utils::Prefs::OldPrefs->get('musicmagicscaninterval') || $defaults->{scan_interval});
	$prefs->set('port',            Slim::Utils::Prefs::OldPrefs->get('MMSport') || $defaults->{port});
	$prefs->set('mix_filter',      Slim::Utils::Prefs::OldPrefs->get('MMMFilter') || $defaults->{mix_filter});
	$prefs->set('reject_size',     Slim::Utils::Prefs::OldPrefs->get('MMMRejectSize') || $defaults->{reject_size});
	$prefs->set('reject_type',     Slim::Utils::Prefs::OldPrefs->get('MMMRejectType') || $defaults->{reject_type});
	$prefs->set('mix_genre',       Slim::Utils::Prefs::OldPrefs->get('MMMMixGenre') || $defaults->{mix_genre});
	$prefs->set('mix_variety',     Slim::Utils::Prefs::OldPrefs->get('MMMVariety') || $defaults->{mix_variety});
	$prefs->set('mix_style',       Slim::Utils::Prefs::OldPrefs->get('MMMStyle') || $defaults->{mix_style});
	$prefs->set('mix_type',        Slim::Utils::Prefs::OldPrefs->get('MMMMixType') || $defaults->{mix_type});
	$prefs->set('mix_size',        Slim::Utils::Prefs::OldPrefs->get('MMMSize') ||$defaults->{mix_size});
	$prefs->set('playlist_prefix', Slim::Utils::Prefs::OldPrefs->get('MusicMagicplaylistprefix') || '');
	$prefs->set('playlist_suffix', Slim::Utils::Prefs::OldPrefs->get('MusicMagicplaylistsuffix') || '');

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
	$prefs->set('scan_interval',   $oldPrefs->get('scan_interval') || $defaults->{scan_interval});
	$prefs->set('port',            $oldPrefs->get('port') || $defaults->{port});
	$prefs->set('mix_filter',      $oldPrefs->get('mix_filter') || $defaults->{mix_filter});
	$prefs->set('reject_size',     $oldPrefs->get('reject_size') || $defaults->{reject_size});
	$prefs->set('reject_type',     $oldPrefs->get('reject_type') || $defaults->{reject_type});
	$prefs->set('mix_genre',       $oldPrefs->get('mix_genre') || $defaults->{mix_genre});
	$prefs->set('mix_variety',     $oldPrefs->get('mix_variety') || $defaults->{mix_variety});
	$prefs->set('mix_style',       $oldPrefs->get('mix_style') || $defaults->{mix_style});
	$prefs->set('mix_type',        $oldPrefs->get('mix_type') || $defaults->{mix_type});
	$prefs->set('mix_size',        $oldPrefs->get('mix_size') ||$defaults->{mix_size});
	$prefs->set('playlist_prefix', $oldPrefs->get('playlist_prefix') || '');
	$prefs->set('playlist_suffix', $oldPrefs->get('playlist_suffix') || '');

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

		if ( main::IP3K ) {
			for my $c (Slim::Player::Client::clients()) {
				Slim::Buttons::Home::updateMenu($c);
			}
		}
	},
	'musicip',
);

$prefs->setChange(
	sub {
			Slim::Utils::Timers::killTimers(undef, \&Slim::Plugin::MusicMagic::Plugin::checker);
			
			my $interval = $prefs->get('scan_interval') || 3600;
			
			main::INFOLOG && $log->info("re-setting scaninterval to $interval seconds.");
			
			Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 120, \&Slim::Plugin::MusicMagic::Plugin::checker);
	},
'scan_interval');

$prefs->migrateClient(1, sub {
	my ($clientprefs, $client) = @_;
	
	$clientprefs->set('mix_filter',  Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMFilter') || $defaults->{mix_filter});
	$clientprefs->set('reject_size', Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMRejectSize') || $defaults->{reject_size});
	$clientprefs->set('reject_type', Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMRejectType') || $defaults->{reject_type});
	$clientprefs->set('mix_genre',   Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMMixGenre') || $defaults->{mix_genre});
	$clientprefs->set('mix_variety', Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMVariety') || $defaults->{mix_variety});
	$clientprefs->set('mix_style',   Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMStyle') || $defaults->{mix_style});
	$clientprefs->set('mix_type',    Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMMixType') || $defaults->{mix_type});
	$clientprefs->set('mix_size',    Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMSize') || $defaults->{mix_size});
	1;
});

$prefs->migrateClient(2, sub {
	my ($clientprefs, $client) = @_;
	
	my $oldPrefs = preferences('plugin.musicmagic');
	$clientprefs->set('mix_filter',  $oldPrefs->client($client)->get($client, 'mix_filter') || $defaults->{mix_filter});
	$clientprefs->set('reject_size', $oldPrefs->client($client)->get($client, 'reject_size') || $defaults->{reject_size});
	$clientprefs->set('reject_type', $oldPrefs->client($client)->get($client, 'reject_type') || $defaults->{reject_type});
	$clientprefs->set('mix_genre',   $oldPrefs->client($client)->get($client, 'mix_genre') || $defaults->{mix_genre});
	$clientprefs->set('mix_variety', $oldPrefs->client($client)->get($client, 'mix_variety') || $defaults->{mix_variety});
	$clientprefs->set('mix_style',   $oldPrefs->client($client)->get($client, 'mix_style') || $defaults->{mix_style});
	$clientprefs->set('mix_type',    $oldPrefs->client($client)->get($client, 'mix_type') || $defaults->{mix_type});
	$clientprefs->set('mix_size',    $oldPrefs->client($client)->get($client, 'mix_size') || $defaults->{mix_size});
	1;
});

my %filterHash = ();

sub grabFilters {
	my ($class, $client, $params, $callback, @args) = @_;
	
	my $MMSport = $prefs->get('port');

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

	$http->get( "http://localhost:$MMSport/api/filters" );
}

sub getFilterList {
	return \%filterHash;
}

sub _gotFilters {
	my $http = shift;

	my @filters = ();

	if ($http) {

		@filters = split(/\n/, decode($http->content));

		if ($log->is_debug && scalar @filters) {

			main::DEBUGLOG && $log->debug("Found filters:");

			for my $filter (@filters) {

				main::DEBUGLOG && $log->debug("\t$filter");
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
		my $body = $class->handler($client, $params);
		$callback->( $client, $params, $body, @args );	
	}
}

sub decode {
	my $data = shift;
	
	my $enc = Slim::Utils::Unicode::encodingFromString($data);
	return Slim::Utils::Unicode::utf8decode_guess($data, $enc);
}

1;

__END__
