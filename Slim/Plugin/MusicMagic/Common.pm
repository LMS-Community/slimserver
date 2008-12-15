package Slim::Plugin::MusicMagic::Common;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech
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

my $os  = Slim::Utils::OSDetect::OS();
*escape   = Slim::Utils::OSDetect::isWindows() ? \&URI::Escape::uri_escape : \&URI::Escape::uri_escape_utf8;

my $log = logger('plugin.musicip');

my $prefs = preferences('plugin.musicip');

my %filterHash = ();

sub convertPath {
	my $mmsPath = shift;
	
	if ($prefs->get('host') eq 'localhost') {
		return $mmsPath;
	}
	
	my $remoteRoot = $prefs->get('remote_root');
	my $nativeRoot = preferences('server')->get('audiodir');
	my $original   = $mmsPath;
	my $winPath    = $mmsPath =~ m/\\/; # test if this is a windows path

	if ($os eq 'unix') {

		# we are unix
		if ($winPath) {

			# we are running musicip on windows but
			# slim server is running on unix

			# convert any windozes paths to unix style
			$remoteRoot =~ tr/\\/\//;

			$log->debug("$remoteRoot :: $nativeRoot");

			# convert windozes paths to unix style
			$mmsPath =~ tr/\\/\//;
			# convert remote root to native root
			$mmsPath =~ s/$remoteRoot/$nativeRoot/;
		}

	} else {

		# we are windows
		if (!$winPath) {

			# we recieved a unix path from music match
			# convert any unix paths to windows style
			# convert windows native to unix first
			# cuz matching dont work unless we do
			$nativeRoot =~ tr/\\/\//;

			$log->debug("$remoteRoot :: $nativeRoot");

			# convert unix root to windows root
			$mmsPath =~ s/$remoteRoot/$nativeRoot/;
			# convert unix paths to windows
			$mmsPath =~ tr/\//\\/;
		}
	}

	$log->debug("$original is now $mmsPath");

	return $mmsPath
}

sub checkDefaults {

	if (!defined $prefs->get('musicip')) {
		$prefs->set('musicip',0)
	}

	if (!defined $prefs->get('mix_type')) {
		$prefs->set('mix_type',0)
	}

	if (!defined $prefs->get('mix_style')) {
		$prefs->set('mix_style',0);
	}

	if (!defined $prefs->get('mix_variety')) {
		$prefs->set('mix_variety',0);
	}

	if (!defined $prefs->get('mix_size')) {
		$prefs->set('mix_size',12);
	}

	if (!defined $prefs->get('playlist_prefix')) {
		$prefs->set('playlist_prefix','');
	}

	if (!defined $prefs->get('playlist_suffix')) {
		$prefs->set('playlist_suffix','');
	}

	if (!defined $prefs->get('scan_interval')) {
		$prefs->set('scan_interval',3600);
	}

	if (!defined $prefs->get('port')) {
		$prefs->set('port',10002);
	}

	if (!defined $prefs->get('host')) {
		$prefs->set('host','localhost');
	}
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

sub decode {
	my $data = shift;
	
	my $enc = Slim::Utils::Unicode::encodingFromString($data);
	return Slim::Utils::Unicode::utf8decode_guess($data, $enc);
}

1;

__END__
