package Slim::Plugin::Orange::Metadata;

# $Id: Metadata.pm 10553 2011-05-06 15:29:58Z mherger $

use strict;

use URI::Escape qw(uri_escape_utf8);
use URI::Split qw(uri_split);

use Slim::Formats::RemoteMetadata;
use JSON::XS::VersionOneAndTwo;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;

my $ICON = Slim::Plugin::Orange::Plugin->_pluginDataFor('icon');

my $log  = logger('plugin.orange');

sub init {
	my $class = shift;
	
	Slim::Formats::RemoteMetadata->registerParser(
		match => qr/api\/orange\/v1/,
		func  => \&parser,
	);
	
	Slim::Formats::RemoteMetadata->registerProvider(
		match => qr/api\/orange\/v1/,
		func  => \&provider,
	);
}

sub defaultMeta {
	my ( $client, $url ) = @_;
	
	return {
		title => Slim::Music::Info::getCurrentTitle($url),
		icon  => $ICON,
		type  => $client->string('RADIO'),
		ttl   => time() + 30,
	};
}

sub provider {
	my ( $client, $url ) = @_;

	if ( !$client->isPlaying && !$client->isPaused ) {
		return defaultMeta( $client, $url );
	}

	if ( my $meta = $client->master->pluginData('metadata') ) {

		if ( $meta->{_url} eq $url ) {
			$meta->{title} ||= Slim::Music::Info::getCurrentTitle($url);
			
			# need to refresh meta data
			if ($meta->{ttl} < time()) {
				fetchMetadata( $client, $url );
			}
			
			return $meta;
		}

	}
	
	if ( !$client->master->pluginData('fetchingMeta') ) {
		fetchMetadata( $client, $url );
	}

	return defaultMeta( $client, $url );	
}

sub fetchMetadata {
	my ( $client, $url ) = @_;
	
	return unless $client;

	Slim::Utils::Timers::killTimers( $client, \&fetchMetadata );
	
	# Make sure client is still playing this station
	if ( Slim::Player::Playlist::url($client) ne $url ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( $client->id . " no longer playing $url, stopping metadata fetch" );
		return;
	}

	$client->master->pluginData( fetchingMeta => 1 );
	
	my ($scheme, $auth, $path, $query, $frag) = uri_split($url);

	# SN URL to fetch track info menu
	my $metaUrl = Slim::Networking::SqueezeNetwork->url(
		'/api/orange/v1/playback/getMetadata?' . $query
	);
	
	main::DEBUGLOG && $log->is_debug && $log->debug( "Fetching Orange metadata from $metaUrl" );
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_gotMetadata,
		\&_gotMetadataError,
		{
			client     => $client,
			url        => $url,
			timeout    => 30,
		},
	);
	
	$http->get( $metaUrl );
}

sub _gotMetadata {
	my $http   = shift;
	my $client = $http->params('client');
	my $url    = $http->params('url');

	my $feed = eval { from_json( $http->content ) };
	
	if ( $@ ) {
		$http->error( $@ );
		_gotMetadataError( $http );
		return;
	}

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Raw Orange metadata: " . Data::Dump::dump($feed) );
	}

	my $meta = defaultMeta( $client, $url );
	$meta->{_url} = $url;

	while (my ($k, $v) = each %{$feed}) {
		if ($v) {
			$meta->{$k} = $v;
		}
	}
	
	if ($meta->{ttl} < time()) {
		$meta->{ttl} = time() + ($meta->{ttl} || 60); 
	}

	$client->master->pluginData( fetchingMeta => 0 );
	$client->master->pluginData( metadata => $meta );

	Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );

	Slim::Utils::Timers::setTimer(
		$client,
		$meta->{ttl},
		\&fetchMetadata,
		$url,
	);
}

sub _gotMetadataError {
	my $http   = shift;
	my $client = $http->params('client');
	my $url    = $http->params('url');
	my $error  = $http->error;
	
	main::DEBUGLOG && $log->is_debug && $log->debug( "Error fetching Orange metadata: $error" );
	
	$client->master->pluginData( fetchingMeta => 0 );
	
	# To avoid flooding the RT servers in the case of errors, we just ignore further
	# metadata for this station if we get an error
	my $meta = defaultMeta( $client, $url );
	$meta->{_url} = $url;
	
	$client->master->pluginData( metadata => $meta );

	Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );
	
	Slim::Utils::Timers::setTimer(
		$client,
		$meta->{ttl},
		\&fetchMetadata,
		$url,
	);
}

sub parser {
	my ( $client, $url, $metadata ) = @_;
	
	# If a station is providing Icy metadata, disable metadata
	# provided by Orange
	if ( $metadata =~ /StreamTitle=\'([^']+)\'/ ) {
		if ( $1 ) {
			if ( $client->master->pluginData('metadata' ) ) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Disabling Orange metadata, stream has Icy metadata');
				
				Slim::Utils::Timers::killTimers( $client, \&fetchMetadata );
				#$client->master->pluginData( metadata => undef );
			}
			
			# Let the default metadata handler process the Icy metadata
			$client->master->pluginData( hasIcy => $url );
			return;
		}
	}
	
	# If a station is providing WMA metadata, disable metadata
	# provided by Orange
	elsif ( $metadata =~ /(?:CAPTION|artist|type=SONG)/ ) {
		if ( $client->master->pluginData('metadata' ) ) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Disabling Orange metadata, stream has WMA metadata');
			
			Slim::Utils::Timers::killTimers( $client, \&fetchMetadata );
			#$client->master->pluginData( metadata => undef );
		}
		
		# Let the default metadata handler process the WMA metadata
		$client->master->pluginData( hasIcy => $url );
		return;
	}
	
	return 1;
}

1;
