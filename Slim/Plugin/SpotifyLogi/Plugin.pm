package Slim::Plugin::SpotifyLogi::Plugin;

# $Id$

use strict;
use base 'Slim::Plugin::OPMLBased';

use Slim::Networking::SqueezeNetwork;
use Slim::Plugin::SpotifyLogi::ProtocolHandler;

use URI::Escape qw(uri_escape_utf8);

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.spotifylogi',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_SPOTIFYLOGI_MODULE_NAME',
} );

=pod
typedef enum sp_error {
	SP_ERROR_OK                        = 0,  ///< No errors encountered
	SP_ERROR_BAD_API_VERSION           = 1,  ///< The library version targeted does not match the one you claim you support
	SP_ERROR_API_INITIALIZATION_FAILED = 2,  ///< Initialization of library failed - are cache locations etc. valid?
	SP_ERROR_TRACK_NOT_PLAYABLE        = 3,  ///< The track specified for playing cannot be played
	SP_ERROR_RESOURCE_NOT_LOADED       = 4,  ///< One or several of the supplied resources is not yet loaded
	SP_ERROR_BAD_APPLICATION_KEY       = 5,  ///< The application key is invalid
	SP_ERROR_BAD_USERNAME_OR_PASSWORD  = 6,  ///< Login failed because of bad username and/or password
	SP_ERROR_USER_BANNED               = 7,  ///< The specified username is banned
	SP_ERROR_UNABLE_TO_CONTACT_SERVER  = 8,  ///< Cannot connect to the Spotify backend system
	SP_ERROR_CLIENT_TOO_OLD            = 9,  ///< Client is too old, library will need to be updated
	SP_ERROR_OTHER_PERMANENT           = 10, ///< Some other error occured, and it is permanent (e.g. trying to relogin will not help)
	SP_ERROR_BAD_USER_AGENT            = 11, ///< The user agent string is invalid or too long
	SP_ERROR_MISSING_CALLBACK          = 12, ///< No valid callback registered to handle events
	SP_ERROR_INVALID_INDATA            = 13, ///< Input data was either missing or invalid
	SP_ERROR_INDEX_OUT_OF_RANGE        = 14, ///< Index out of range
	SP_ERROR_USER_NEEDS_PREMIUM        = 15, ///< The specified user needs a premium account
	SP_ERROR_OTHER_TRANSIENT           = 16, ///< A transient error occured.
	SP_ERROR_IS_LOADING                = 17, ///< The resource is currently loading
	SP_ERROR_NO_STREAM_AVAILABLE       = 18, ///< Could not find any suitable stream to play
	SP_ERROR_PERMISSION_DENIED         = 19, ///< Requested operation is not allowed
	SP_ERROR_INBOX_IS_FULL             = 20, ///< Target inbox is full
} sp_error;

100+ are internal errors:

100 - No Spotify URI found for playback
101 - Not a Spotify track URI
102 - Spotify play token lost, account in use elsewhere
103 - Track is not available for playback (sp_track_is_available returns false)
=cut

# Stop playback on these errors.  Other errors will skip
# to the next track.
my @stop_errors = (
	4, # SP_ERROR_RESOURCE_NOT_LOADED
	5, # SP_ERROR_BAD_APPLICATION_KEY
	6, # SP_ERROR_BAD_USERNAME_OR_PASSWORD
	7, # SP_ERROR_USER_BANNED
	8, # SP_ERROR_UNABLE_TO_CONTACT_SERVER
	9, # SP_ERROR_CLIENT_TOO_OLD,
	10, # SP_ERROR_OTHER_PERMANENT
	15, # SP_ERROR_USER_NEEDS_PREMIUM
	19, # SP_ERROR_PERMISSION_DENIED,
	102, # Spotify play token lost, account in use elsewhere
);

# Report these errors
my @report_errors = (
	6, # SP_ERROR_BAD_USERNAME_OR_PASSWORD
);

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		spotify => 'Slim::Plugin::SpotifyLogi::ProtocolHandler'
	);

	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr|squeezenetwork\.com.*/api/spotify/|, 
		sub { Slim::Plugin::SpotifyLogi::ProtocolHandler->getIcon(); }
	);
	
	Slim::Networking::Slimproto::addHandler( 
		SPDS => \&spds_handler
	);
	
	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( spotifylogi => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );
	
	# Commands init
	Slim::Control::Request::addDispatch(['spotify', 'star', '_uri'],
		[0, 1, 1, \&star]);

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url('/api/spotify/v1/opml'),
		tag    => 'spotifylogi',
		menu   => 'music_services',
		weight => 20,
		is_app => 1,
	);
	
	if ( main::WEBUI ) {
		# Add a function to view trackinfo in the web
		Slim::Web::Pages->addPageFunction( 
			'plugins/spotifylogi/trackinfo.html',
			sub {
				my $client = $_[0];
				my $params = $_[1];
				
				my $url;
				
				my $id = $params->{sess} || $params->{item};
				
				if ( $id ) {
					# The user clicked on a different URL than is currently playing
					if ( my $track = Slim::Schema->find( Track => $id ) ) {
						$url = $track->url;
					}
					
					# Pass-through track ID as sess param
					$params->{sess} = $id;
				}
				else {
					$url = Slim::Player::Playlist::url($client);
				}
				
				Slim::Web::XMLBrowser->handleWebIndex( {
					client  => $client,
					feed    => Slim::Plugin::SpotifyLogi::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/spotifylogi/trackinfo.html',
					title   => 'Spotify Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub getDisplayName () {
	return 'PLUGIN_SPOTIFYLOGI_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

sub handleError {
	my ( $error, $client ) = @_;
	
	main::DEBUGLOG && $log->debug("Error during request: $error");
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	return unless $client;
	
	# Only show if in the app list
	return unless $client->isAppEnabled('spotify');
	
	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	my $album  = $track->remote ? $remoteMeta->{album}  : ( $track->album ? $track->album->name : undef );
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;
	
	my $snURL = Slim::Networking::SqueezeNetwork->url(
		'/api/spotify/v1/opml/context?artist='
			. uri_escape_utf8($artist)
			. '&album='
			. uri_escape_utf8($album)
			. '&track='
			. uri_escape_utf8($title)
	);
	
	if ( $artist && ( $album || $title ) ) {
		return {
			type      => 'link',
			name      => $client->string('PLUGIN_SPOTIFYLOGI_ON_SPOTIFY'),
			url       => $snURL,
			favorites => 0,
		};
	}
}

sub star {
	my $request = shift;
	my $client  = $request->client();
	my $uri = $request->getParam('_uri');
	
	return unless defined $client && $uri;
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Sending star command to player for $uri");
	
	my $data = pack(
		'cC/a*',
		2,
		$uri,
	);
	
	$client->sendFrame( spds => \$data );
	
	$request->setStatusDone();
}

sub spds_handler {
	my ( $client, $data_ref ) = @_;
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( $client->id . " Got SPDS packet: " . Data::Dump::dump($data_ref) );
	}
	
	my $got_cmd = unpack 'C', $$data_ref;
	
	# Check for specific decoding error codes
	if ( $got_cmd == 255 ) {
		my (undef, $error_code, $message, $spotify_error ) = unpack 'CCC/a*C/a*', $$data_ref;
		
		if ( $spotify_error ) {
			$message .= ': ' . $spotify_error;
		}
		
		$log->error( $client->id . " Spotify error, code $error_code: $message" );
		
		my $string = ($error_code >= 3 && $error_code <= 103) ? $client->string("SPOTIFY_ERROR_${error_code}") : $message;
		$client->controller()->playerStreamingFailed($client, $string, ' '); # empty string to hide track URL
		
		# Report some serious issues to back-end
		if ( grep { $error_code == $_ } @report_errors ) {
			my $auth = $client->pluginData('info') && $client->pluginData('info')->{auth};
			$auth ||= {};
			
			my $http = Slim::Networking::SqueezeNetwork->new(
				sub {},
				sub {},
				{ client => $client }
			)->get(
				Slim::Networking::SqueezeNetwork->url(
					sprintf('/api/spotify/v1/opml/report_error?account=%s&error=%s', uri_escape_utf8($auth->{username}), $error_code),
				)
			);
		}
		
		# Force stop on certain errors
		if ( grep { $error_code == $_ } @stop_errors ) {
			# XXX need a better way to stop playback with an error message, calling
			# this after playerStreamingFailed is wrong because the next
			# track is fetched
			Slim::Player::Source::playmode($client, 'stop');
		}
		
		return;
	}
	else {
		# Older firmware, etc, just fail on any unexpected SPDS
		$client->controller()->playerStreamingFailed($client, "Unexpected Spotify error, please update your firmware.", ' ');
	}

}

1;
