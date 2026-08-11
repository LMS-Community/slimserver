package Slim::Plugin::MusicMagic::Common;


# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024-2026 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(catfile);
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
		mix_genre_filter => [],
		mix_size        => 12,
		reject_size     => 12,
		reject_type     => 0,
		playlist_prefix => '',
		playlist_suffix => '',
		scan_interval   => 3600,
		port            => 10002,
		path_conversion_enabled => 0,
		path_conversion_source  => '',
		path_conversion_dest    => '',
	}, 'Slim::Plugin::MusicMagic::Prefs');
}

# Path Conversion - similar to the SugarCube LMS plugin's own feature of
# the same kind. Lets the user configure a source (MusicIP-side) path
# prefix and a destination (Lyrion-side) path prefix, for cases where
# MusicIP reports paths that don't match what Lyrion expects - e.g. when
# MusicIP itself runs under Wine (in which case it reports paths in
# Windows drive-letter form, since Wine maps the Linux filesystem root
# to a drive, typically Z:\), or when running MusicIP on a different
# host/container than Lyrion Music Server with a different mount layout.
#
# Disabled by default, and a no-op unless both the source and
# destination are configured, so this never affects a standard
# native-platform MusicIP install.
sub translatePath {
	my $path = shift;

	return $path unless $prefs->get('path_conversion_enabled');

	my $source = $prefs->get('path_conversion_source');
	my $dest   = $prefs->get('path_conversion_dest');

	return $path unless defined $source && length($source) && defined $dest;

	if ($path =~ s|^\Q$source\E||i) {
		# re-join whatever's left of the path using the destination's
		# own (OS-native) separator, so this works symmetrically in
		# either direction - e.g. a Windows-style source converted to
		# a Unix-style dest (MusicIP under Wine), or the other way
		# around - rather than just blindly flipping backslashes.
		my @parts = grep { length } split m|[\\/]|, $path;
		$path = @parts ? catfile($dest, @parts) : $dest;
	}

	return $path;
}

sub getGenreList {
	my @genres = map { $_->name } Slim::Schema->rs('Genre')->search(undef, { order_by => 'me.namesort' })->all;

	return \@genres;
}

sub getBaseUrl {
	my $host = $prefs->get('host') || 'localhost';
	my $port = $prefs->get('port');
	return "http://$host:$port/api";
}

sub grabFilters {
	my ($class, $client, $params, $callback, @args) = @_;

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

	$http->get( getBaseUrl() . '/filters' );
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
