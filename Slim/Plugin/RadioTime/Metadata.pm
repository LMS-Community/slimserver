package Slim::Plugin::RadioTime::Metadata;

# $Id$

use strict;

use Slim::Formats::RemoteMetadata;
use Slim::Formats::XML;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use URI::Escape qw(uri_escape_utf8);

my $log   = logger('formats.metadata');
my $prefs = preferences('plugin.radiotime');

use constant META_URL => 'http://opml.radiotime.com/NowPlaying.aspx?partnerId=16';

my $ICON = Slim::Plugin::RadioTime::Plugin->_pluginDataFor('icon');

sub init {
	my $class = shift;
	
	Slim::Formats::RemoteMetadata->registerParser(
		match => qr/radiotime\.com/,
		func  => \&parser,
	);
	
	Slim::Formats::RemoteMetadata->registerProvider(
		match => qr/radiotime\.com/,
		func  => \&provider,
	);
}

sub defaultMeta {
	my ( $client, $url ) = @_;
	
	return {
		title => Slim::Music::Info::getCurrentTitle($url),
		icon  => $ICON,
		type  => $client->string('RADIO'),
	};
}

sub parser {
	my ( $client, $url, $metadata ) = @_;
	
	# If a station is providing Icy metadata, disable metadata
	# provided by RadioTime
	if ( $metadata =~ /StreamTitle=\'([^']+)\'/ ) {
		if ( $1 ) {
			if ( $client->pluginData('metadata' ) ) {
				$log->is_debug && $log->debug('Disabling RadioTime metadata, stream has Icy metadata');
				
				Slim::Utils::Timers::killTimers( $client, \&fetchMetadata );
				$client->pluginData( hasIcy => $url );
				$client->pluginData( metadata => undef );
			}
			
			# Let the default metadata handler process the Icy metadata
			return;
		}
	}
	
	return 1;
}

sub provider {
	my ( $client, $url ) = @_;
	
	my $hasIcy = $client->pluginData('hasIcy');
	
	if ( $hasIcy && $hasIcy ne $url ) {
		$client->pluginData( hasIcy => 0 );
		$hasIcy = undef;
	}
	
	return {} if $hasIcy;
	
	if ( !$client->isPlaying && !$client->isPaused ) {
		return defaultMeta( $client, $url );
	}
	
	if ( my $meta = $client->pluginData('metadata') ) {
		if ( $meta->{_url} eq $url ) {
			if ( !$meta->{title} ) {
				$meta->{title} = Slim::Music::Info::getCurrentTitle($url);
			}
			
			return $meta;
		}
	}
	
	if ( !$client->pluginData('fetchingMeta') ) {
		# Fetch metadata in the background
		Slim::Utils::Timers::killTimers( $client, \&fetchMetadata );
		fetchMetadata( $client, $url );
	}
	
	return defaultMeta( $client, $url );
}

sub fetchMetadata {
	my ( $client, $url ) = @_;
	
	return unless $client;
	
	# Make sure client is still playing this station
	if ( Slim::Player::Playlist::url($client) ne $url ) {
		$log->is_debug && $log->debug( $client->id . " no longer playing $url, stopping metadata fetch" );
		return;
	}
	
	my ($stationId) = $url =~ m/stationId=(\d+)/;
	return unless $stationId;
	
	my $username;
	if ( main::SLIM_SERVICE ) {
		$username = preferences('server')->client($client)->get('plugin_radiotime_username', 'force');
	}
	else {
		$username = $prefs->get('username');
	}
	
	my $metaUrl = META_URL . '&stationId=' . $stationId;
	
	if ( $username ) {
		$metaUrl .= '&username=' . uri_escape_utf8($username);
	}
	
	$log->is_debug && $log->debug( "Fetching RadioTime metadata from $metaUrl" );
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_gotMetadata,
		\&_gotMetadataError,
		{
			client     => $client,
			url        => $url,
			timeout    => 30,
		},
	);
	
	$client->pluginData( fetchingMeta => 1 );
	
	my %headers;
	if ( main::SLIM_SERVICE ) {
		# Add real client IP for Radiotime so they can do proper geo-location
		$headers{'X-Forwarded-For'} = $client->ip;
	}
	
	$http->get( $metaUrl, %headers );
}

sub _gotMetadata {
	my $http   = shift;
	my $client = $http->params('client');
	my $url    = $http->params('url');
	
	my $feed = eval { Slim::Formats::XML::parseXMLIntoFeed( $http->contentRef ) };
	
	if ( $@ ) {
		$http->error( $@ );
		_gotMetadataError( $http );
		return;
	}
	
	$client->pluginData( fetchingMeta => 0 );
	
	if ( $log->is_debug ) {
		$log->debug( "Raw RadioTime metadata: " . Data::Dump::dump($feed) );
	}
	
	my $ttl = 300;
	
	if ( my $cc = $http->headers->header('Cache-Control') ) {
		if ( $cc =~ m/max-age=(\d+)/i ) {
			$ttl = $1;
		}
	}
	
	my $meta = defaultMeta( $client, $url );
	$meta->{_url} = $url;
	
	my $i = 0;
	for my $item ( @{ $feed->{items} } ) {
		if ( $item->{image} ) {
			$meta->{cover} = $item->{image};
		}
		
		if ( $i == 0 ) {
			$meta->{artist} = $item->{name};
		}
		elsif ( $i == 1 ) {
			$meta->{title} = $item->{name};
		}
		
		$i++;
	}
	
	if ( $log->is_debug ) {
		$log->debug( "Saved RadioTime metadata: " . Data::Dump::dump($meta) );
	}
	
	$client->pluginData( metadata => $meta );
	
	$log->is_debug && $log->debug( "Will check metadata again in $ttl seconds" );
	
	Slim::Utils::Timers::setTimer(
		$client,
		time() + $ttl,
		\&fetchMetadata,
		$url,
	);
}

sub _gotMetadataError {
	my $http   = shift;
	my $client = $http->params('client');
	my $url    = $http->params('url');
	my $error  = $http->error;
	
	$log->is_debug && $log->debug( "Error fetching RadioTime metadata: $error" );
	
	$client->pluginData( fetchingMeta => 0 );
	
	# To avoid flooding the RT servers in the case of errors, we just ignore further
	# metadata for this station if we get an error
	my $meta = defaultMeta( $client, $url );
	$meta->{_url} = $url;
	
	$client->pluginData( metadata => $meta );
}

1;