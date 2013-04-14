package Slim::Plugin::RadioTime::Metadata;

# $Id$

use strict;

use Slim::Formats::RemoteMetadata;
use Slim::Formats::XML;
use Slim::Music::Info;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Plugin::RadioTime::Plugin;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use URI::Escape qw(uri_escape_utf8);

my $log   = logger('plugin.radio');
my $prefs = preferences('plugin.radiotime');

use constant PARTNER_ID => 16;
use constant META_URL   => 'http://opml.radiotime.com/NowPlaying.aspx?partnerId=' . PARTNER_ID;
use constant CONFIG_URL => 'http://opml.radiotime.com/Config.ashx?c=api&partnerId=' . PARTNER_ID . '&serial=';

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
	
	# match one of the following types of artwork:
	# http://xxx.cloudfront.net/293541660g.jpg
	# http://xxx.cloudfront.net/gn/6LN8BZKP0Mg.jpg
	Slim::Web::ImageProxy->registerHandler(
		match => qr/cloudfront\.net\/(?:[ps]?\d+|gn\/[A-Z0-9]+)[tqgd]?\.(?:jpe?g|png|gif)$/,
		func  => \&artworkUrl,
	);
}

sub getConfig {
	my $client = shift;
	
	Slim::Utils::Timers::killTimers( $client, \&getConfig );
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_gotConfig,
		\&_gotConfig, # TODO - error handler
		{
			client  => $client,
			timeout => 30,
		},
	);
	
	Slim::Utils::Timers::setTimer(
		$client,
		time() + 60*60*23,	# repeat at least every 24h
		\&getConfig,
	);

	$http->get( CONFIG_URL . Slim::Plugin::RadioTime::Plugin->getSerial($client) );
}

sub _gotConfig {
	my $http   = shift;
	my $client = $http->params('client');
	
	my $feed = eval { Slim::Formats::XML::parseXMLIntoFeed( $http->contentRef ) };

	if ( $@ ) {
		main::DEBUGLOG && $log->debug( "Error fetching TuneIn artwork configuration: $@" );
	}
	elsif ( $feed && $feed->{items} && (my $config = $feed->{items}->[0]) ) {
		if ( (my $lookup = $config->{'albumart.lookupurl'}) && (my $url = $config->{'albumart.url'}) ) {
			$client->pluginData( artworkConfig => {
				lookupurl   => $lookup,
				albumarturl => $url,
			} );
		}
	}
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
	
	if ( $client && !$client->pluginData('artworkConfig') ) {
		getConfig($client);
	}

	# If a station is providing Icy metadata, disable metadata
	# provided by RadioTime
	if ( $metadata =~ /StreamTitle=\'([^']+)\'/ ) {
		if ( $1 ) {
			if ( $client->master->pluginData('metadata' ) ) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Disabling RadioTime metadata, stream has Icy metadata');
				
				Slim::Utils::Timers::killTimers( $client, \&fetchMetadata );
				$client->master->pluginData( metadata => undef );
			}

			# Check for an image URL in the metadata.
			my $artworkUrl;
			if ( $metadata =~ /StreamUrl=\'([^']+)\'/ ) {
				$artworkUrl = $1;
				if ( $artworkUrl !~ /\.(?:jpe?g|gif|png)$/i ) {
					$artworkUrl = undef;
				}
			}

			# lookup artwork unless it's been defined in the metadata (eg. Radio Paradise)
			fetchArtwork($client, $url, 'delayed') unless $artworkUrl;
			
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

		fetchArtwork($client, $url, 'delayed');
		
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
	
	my $username = Slim::Plugin::RadioTime::Plugin->getUsername($client);
	
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
		setArtwork($client, $url, $meta->{cover});
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Saved RadioTime metadata: " . Data::Dump::dump($meta) );
	}
	
	$client->master->pluginData( metadata => $meta );
	
	fetchArtwork($client, $url);
	
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


sub fetchArtwork {
	my ($client, $url, $delayed) = @_;
	
	main::DEBUGLOG && $log->debug( "Getting artwork for $url" );
	
	Slim::Utils::Timers::killTimers( $client, \&_fetchArtwork );

	if ($delayed) {
		$delayed = Slim::Music::Info::getStreamDelay($client);

		# if the stream has ICY metadata, give it a moment to parse it
		Slim::Utils::Timers::setTimer(
			$client,
			time() + $delayed + 1,
			\&_fetchArtwork,
			$url
		);
	}
	else {
		_fetchArtwork($client, $url);
	}
}

sub _fetchArtwork {
	my ( $client, $url ) = @_;
	
	my $config  = $client->pluginData('artworkConfig') || return;
	my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);

	if ( $handler && $handler->can('getMetadataFor') ) {
		my $track = $handler->getMetadataFor( $client, $url );

		main::DEBUGLOG && $log->debug( 'Getting TuneIn artwork based on metadata:', Data::Dump::dump($track) );
		
		# keep track of the station logo in case we don't get track artwork
		#                                             [ps] => podcast or station
		#                                                     t => Thumbnail
		#                                                      q => sQuare
		#                                                       g => Giant
		#                                                        d => meDium
		if ( $track->{cover} && $track->{cover} =~ m{/[ps]\d+[tqgd]?\.(?:jpg|jpeg|png|gif)$}i && (my $song = $client->playingSong()) ) {
			if ( !$song->pluginData('stationLogo') ) {
				main::DEBUGLOG && $log->debug( 'Storing default station artwork: ' . $track->{cover} );
				
				$song->pluginData( stationLogo => $track->{cover} );
				$client->pluginData( stationLogo => $track->{cover} );
			}
		}
		
		if ( $track && $track->{title} && $track->{artist} ) {
			
			my $lookupurl = sprintf($config->{lookupurl} . '?partnerId=%s&serial=%s&artist=%s&title=%s',
				PARTNER_ID,
				Slim::Plugin::RadioTime::Plugin->getSerial($client),
				$track->{artist},
				$track->{title},
			);
			
			return if $client->master->pluginData('fetchingArtwork') && $client->master->pluginData('fetchingArtwork') eq $lookupurl;
			
			$client->master->pluginData( fetchingArtwork => $lookupurl );
	
			my $http = Slim::Networking::SimpleAsyncHTTP->new(
				\&_gotArtwork,
				\&_gotArtwork, # we'll happily fall back to the station artwork if we fail
				{
					client     => $client,
					url        => $url,
					timeout    => 30,
				},
			);
			
			$http->get( $lookupurl );
		}
		# fallback to station artwork
		elsif ( my $artworkUrl = $client->pluginData('stationLogo') ) {
			setArtwork($client, $url, $artworkUrl);
		}
	}
}

sub _gotArtwork {
	my $http   = shift;
	my $client = $http->params('client');
	my $url    = $http->params('url');
	
	$client->master->pluginData( fetchingArtwork => 0 );

	my $feed = eval { Slim::Formats::XML::parseXMLIntoFeed( $http->contentRef ) };
	
	if ( $@ || !$feed ) {
		main::DEBUGLOG && $log->debug( "Error fetching TuneIn artwork: $@" );
	}
	else  {
		main::DEBUGLOG && $log->debug( 'Received TuneIn track artwork information: ', Data::Dump::dump($feed) );
	}
	
	if ( $feed && $feed->{items} && $feed->{items}->[0] && (my $key = $feed->{items}->[0]->{album_art} || $feed->{items}->[0]->{artist_art}) ) {
		my $config = $client->pluginData('artworkConfig');
		# grab "g"iant artwork
		my $artworkUrl = $config->{albumarturl} . $key . 'g.jpg';
		
		setArtwork($client, $url, $artworkUrl);
	}
	# fallback to station artwork
	elsif ( my $artworkUrl = $client->pluginData('stationLogo') ) {
		setArtwork($client, $url, $artworkUrl);
	}
}

sub setArtwork {
	my ($client, $url, $artworkUrl) = @_;
			
	my $cache = Slim::Utils::Cache->new();
	$cache->set( "remote_image_$url", $artworkUrl, 3600 );
	
	if ( my $song = $client->playingSong() ) {
		$song->pluginData( httpCover => $artworkUrl );

		main::DEBUGLOG && $log->debug("Updating stream artwork to $artworkUrl");
		Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );
	}
}


# TuneIn image sizes:
# t.jpg = 75x75 Thumbnail
# q.jpg = 145x145 sQuare
# d.jpg = 300x300 meDium
# g.jpg = 600x600 Giant
my $sizeMap = {
	75  => 't',
	145 => 'q',
	300 => 'd',
	600 => 'g',
};

# this method tries to figure out the smallest file to be downloaded to fit the client's needs
# it uses the plugin's knowledge about available file sizes to optimize bandwidth and processing requirements
sub artworkUrl {
	my ($url, $spec) = @_;
	
	main::DEBUGLOG && $log->debug("TuneIn artwork - let's get the smallest version fitting our needs: $url, $spec");
	
	my ($logo, $id, $size) = $url =~ m{/([ps]?)(\d+)([tqgd]?)\.(jpg|jpeg|png|gif)$}i;
	$size = lc($size || '');
		
	# sometimes the sQuare image differs from the others for _logos_
	# don't use the larger, non-square in this case, otherwide default to largest
	$size = 'g' unless $logo && $size; 

	my $ext = (Slim::Web::Graphics->parseSpec($spec))[4];
	
	my $min = Slim::Web::ImageProxy->getRightSize($spec, $sizeMap);

	# we use either the min required, or the maximum as defined above
	foreach (sort keys %$sizeMap) {
		if ($sizeMap->{$_} eq $min) {
			$size = $min;
			last;
		}

		last if $sizeMap->{$_} eq $size;
	}

	$url =~ s/[tqgd]?\.$ext$/$size.$ext/ if $size;
	
	main::DEBUGLOG && $log->debug("Going to get $url");
	
	return $url;
}

1;
