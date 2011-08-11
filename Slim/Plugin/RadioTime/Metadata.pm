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
		match => qr/(?:radiotime|tunein)\.com/,
		func  => \&parser,
	);
	
	Slim::Formats::RemoteMetadata->registerProvider(
		match => qr/(?:radiotime|tunein)\.com/,
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
			if ( $client->master->pluginData('metadata' ) ) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Disabling RadioTime metadata, stream has Icy metadata');
				
				Slim::Utils::Timers::killTimers( $client, \&fetchMetadata );
				$client->master->pluginData( metadata => undef );
			}
			
			# Let the default metadata handler process the Icy metadata
			$client->master->pluginData( hasIcy => $url );
			return;
		}
	}
	
	# If a station is providing WMA metadata, disable metadata
	# provided by RadioTime
	elsif ( $metadata =~ /(?:CAPTION|artist|type=SONG)/ ) {
		if ( $client->master->pluginData('metadata' ) ) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Disabling RadioTime metadata, stream has WMA metadata');
			
			Slim::Utils::Timers::killTimers( $client, \&fetchMetadata );
			$client->master->pluginData( metadata => undef );
		}
		
		# Let the default metadata handler process the WMA metadata
		$client->master->pluginData( hasIcy => $url );
		return;
	}
	
	return 1;
}

sub provider {
	my ( $client, $url ) = @_;
	
	my $hasIcy = $client->master->pluginData('hasIcy');
	
	if ( $hasIcy && $hasIcy ne $url ) {
		$client->master->pluginData( hasIcy => 0 );
		$hasIcy = undef;
	}
	
	return {} if $hasIcy;
	
	if ( !$client->isPlaying && !$client->isPaused ) {
		return defaultMeta( $client, $url );
	}
	
	if ( my $meta = $client->master->pluginData('metadata') ) {
		if ( $meta->{_url} eq $url ) {
			if ( !$meta->{title} ) {
				$meta->{title} = Slim::Music::Info::getCurrentTitle($url);
			}
			
			return $meta;
		}
	}
	
	if ( !$client->master->pluginData('fetchingMeta') ) {
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
		main::DEBUGLOG && $log->is_debug && $log->debug( $client->id . " no longer playing $url, stopping metadata fetch" );
		return;
	}
	
	my ($stationId) = $url =~ m/(?:station)?id=([^&]+)/i; # support old-style stationId= and new id= URLs
	return unless $stationId;
	
	my $username;
	if ( main::SLIM_SERVICE ) {
		$username = preferences('server')->client($client)->get('plugin_radiotime_username', 'force');
	}
	else {
		$username = $prefs->get('username');
	}
	
	my $metaUrl = META_URL . '&id=' . $stationId;
	
	if ( $username ) {
		$metaUrl .= '&username=' . uri_escape_utf8($username);
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug( "Fetching RadioTime metadata from $metaUrl" );
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_gotMetadata,
		\&_gotMetadataError,
		{
			client     => $client,
			url        => $url,
			timeout    => 30,
		},
	);
	
	$client->master->pluginData( fetchingMeta => 1 );
	
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
	
	$client->master->pluginData( fetchingMeta => 0 );
	
	if ( main::DEBUGLOG && $log->is_debug ) {
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
	
	# Also cache the image URL in case the stream has other metadata
	if ( $meta->{cover} ) {
		my $cache = Slim::Utils::Cache->new();
		$cache->set( "remote_image_$url" => $meta->{cover}, 86400 * 7 );

		if ( my $song = $client->playingSong() ) {
			$song->pluginData( httpCover => $meta->{cover} );
		}
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Saved RadioTime metadata: " . Data::Dump::dump($meta) );
	}
	
	$client->master->pluginData( metadata => $meta );
	
	main::DEBUGLOG && $log->is_debug && $log->debug( "Will check metadata again in $ttl seconds" );
	
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
	
	main::DEBUGLOG && $log->is_debug && $log->debug( "Error fetching RadioTime metadata: $error" );
	
	$client->master->pluginData( fetchingMeta => 0 );
	
	# To avoid flooding the RT servers in the case of errors, we just ignore further
	# metadata for this station if we get an error
	my $meta = defaultMeta( $client, $url );
	$meta->{_url} = $url;
	
	$client->master->pluginData( metadata => $meta );
}

1;
