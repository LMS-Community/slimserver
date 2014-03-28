package Slim::Plugin::MusicMagic::Common;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use URI::Escape;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings;
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;

*escape = main::ISWINDOWS ? \&URI::Escape::uri_escape : \&URI::Escape::uri_escape_utf8;

my $log = logger('plugin.musicip');

my %filterHash = ();

my $prefs = preferences('plugin.musicip');

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
		
		main::INFOLOG && $log->info("re-setting scaninterval to $interval seconds.");
		
		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 120, \&Slim::Plugin::MusicMagic::Plugin::checker);
	},
'scan_interval');

sub checkDefaults {

	$prefs->init({
		musicip         => 0,
		mix_type        => 0,
		mix_style       => 20,
		mix_variety     => 0,
		mix_genre       => 0,
		mix_size        => 12,
		reject_size     => 12,
		reject_type     => 0,
		playlist_prefix => '',
		playlist_suffix => '',
		scan_interval   => 3600,
		port            => 10002,
	}, 'Slim::Plugin::MusicMagic::Prefs');
}

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
