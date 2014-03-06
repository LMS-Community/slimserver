package Slim::Plugin::RadioIO::Plugin;

use strict;

use JSON::XS::VersionOneAndTwo;

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.radioio',
	'description'  => 'RADIOIO',
});

use constant ARTWORK_URL => Slim::Networking::SqueezeNetwork->url( '/api/radioio/v1/opml/artwork?artist=%s&title=%s&url=%s' );
use constant ICON        => Slim::Networking::SqueezeNetwork->url( '/static/jive/plugins/RadioIO/html/images/icon.png', 1 );

my $urlParseRegex = qr/(?:streamtheworld|radioio)\.com/i;

sub initPlugin {
	my $class = shift;

	Slim::Player::ProtocolHandlers->registerIconHandler(
		$urlParseRegex, 
		sub { ICON }
	);

	Slim::Formats::RemoteMetadata->registerParser(
		match => $urlParseRegex,
		func  => sub {
			my ( $client, $url, $metadata ) = @_;
			
			if ( $client && $url && $metadata =~ (/StreamTitle=\'(.*?)\'(?:;|$)/) ) {

				if ( my ($artist, $title) = split(' - ', $1) ) {
					main::DEBUGLOG && $log->is_debug && $log->debug("Let's get some artwork for $url...");

					Slim::Networking::SqueezeNetwork->new(
						\&_gotArtwork,
						\&_gotArtwork,
						{
							client  => $client,
							url     => $url,
						},
					)->get( sprintf( ARTWORK_URL, URI::Escape::uri_escape_utf8($artist), URI::Escape::uri_escape_utf8($title), $url ) );
				}

			}
		
			# let the main protocol handler the rest of the metadata
			return 0;
		},
	);
}

sub _gotArtwork {
	my $http = shift || return;
	
	my $client = $http->params('client') || return;
	my $url    = $http->params('url') || return;

	my $cover;

	if ( $http->content ) {
		$cover = eval { 
			my $parsed = from_json($http->content);
			$parsed->{cover};
		};
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			 $log->debug( 
			 	( $@ || !$cover )
			 		? ("No cover art found: $@\n" . $http->content)
			 		: ("Found title artwork: " . $cover)
			 );
		}
	};

	$cover ||= ICON;
	
	my $cb = sub {
		Slim::Utils::Cache->new->set( "remote_image_$url", $cover, 3600 );

		if ( my $song = $client->playingSong() ) {
			$song->pluginData( httpCover => $cover );
		}

		Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );
	};

	# Delay metadata according to buffer size if we already have metadata
	if ( $client->metaTitle() ) {
		Slim::Music::Info::setDelayedCallback( $client, $cb );
	}
	else {
		$cb->();
	}
}

1;