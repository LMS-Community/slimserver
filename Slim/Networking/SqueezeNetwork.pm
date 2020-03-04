package Slim::Networking::SqueezeNetwork;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# Async interface to mysqueezebox.com API

use strict;
use base qw(Slim::Networking::SimpleAsyncHTTP Slim::Networking::SqueezeNetwork::Base);

use Digest::SHA1 qw(sha1_base64);
use JSON::XS::VersionOneAndTwo;
use MIME::Base64 qw(encode_base64);
use List::Util qw(max);
use URI::Escape qw(uri_escape);

if ( !main::SCANNER ) {
	require Slim::Networking::SqueezeNetwork::Players;
}

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Timers;

my $log   = logger('network.squeezenetwork');

my $prefs = preferences('server');

my $loginErrors = 0;
my $nextLoginAttempt = 0;

# Initialize by logging into SN server time and storing our time difference
sub init {
	my $class = shift;

	main::INFOLOG && $log->info('SqueezeNetwork Init');

	# Convert old non-hashed password
	if ( my $password = $prefs->get('sn_password') ) {
		$password = sha1_base64( $password );
		$prefs->set( sn_password_sha => $password );
		$prefs->remove('sn_password');

		main::DEBUGLOG && $log->debug('Converted SN password to hashed version');
	}

	Slim::Utils::Timers::setTimer(
		undef,
		time(),
		sub {
			if ( $prefs->get('sn_email') && $prefs->get('sn_password_sha') ) {
				# Login to SN
				$class->login(
					cb  => \&_init_done,
					ecb => \&_init_error,
				);
			} else {
				# Not logging in to SN, add local apps to web interface
				_init_add_non_sn_apps(),
			}
		},
	);
}

sub _init_done {
	my ( $http, $json ) = @_;

	my $snTime = $json->{time};

	if ( $snTime !~ /^\d+$/ ) {
		$http->error( sprintf("Invalid mysqueezebox.com server timestamp (%s)", $http->url) );
		return _init_error( $http );
	}

	my $diff = $snTime - time();

	main::INFOLOG && $log->info("Got SqueezeNetwork server time: $snTime, diff: $diff");

	$prefs->set( sn_timediff => $diff );

	# Clear error counter
	$prefs->remove( 'snInitErrors' );
	$loginErrors = $nextLoginAttempt = 0;

	# Store disabled plugins, if any
	if ( $json->{disabled_plugins} ) {
		if ( ref $json->{disabled_plugins} eq 'ARRAY' ) {
			$prefs->set( sn_disabled_plugins => $json->{disabled_plugins} );

			# Remove disabled plugins from player UI and web UI
			for my $plugin ( @{ $json->{disabled_plugins} } ) {
				my $pclass = "Slim::Plugin::${plugin}::Plugin";
				if ( $pclass->can('setMode') && $pclass->playerMenu) {
					Slim::Buttons::Home::delSubMenu( $pclass->playerMenu, $pclass->getDisplayName );
					main::DEBUGLOG && $log->debug( "Removing $plugin from player UI, service not allowed in country" );
				}

				if ( $pclass->can('webPages') && $pclass->can('menu') ) {
					Slim::Web::Pages->delPageLinks( $pclass->menu, $pclass->getDisplayName );
					main::DEBUGLOG && $log->debug( "Removing $plugin from web UI, service not allowed in country" );
				}
			}
		}

		$prefs->set( sn_disabled_plugins => $json->{disabled_plugins} || [] );
	}

	# Init the Internet Radio menu
	if ( $json->{radio_menu} ) {
		if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::InternetRadio::Plugin') ) {
			Slim::Plugin::InternetRadio::Plugin->buildMenus( $json->{radio_menu} );
		}
	}

	# Stash the supported protocols
	if ( $json->{protocolhandlers}  && ref $json->{protocolhandlers} eq 'ARRAY') {
		$prefs->set( sn_protocolhandlers => $json->{protocolhandlers} );
	}

	# Init pref syncing
	if ( $prefs->get('sn_sync') ) {
		require Slim::Networking::SqueezeNetwork::PrefSync;
		Slim::Networking::SqueezeNetwork::PrefSync->init();
	}

	# Init polling for list of SN-connected players
	Slim::Networking::SqueezeNetwork::Players->init();

	# Init stats - don't even load the module unless stats are enabled
	# let's not bother about re-initialising if pref is changed - there's no user-noticeable effect anyway
#	if (!$prefs->get('sn_disable_stats')) {
#		require Slim::Networking::SqueezeNetwork::Stats;
#		Slim::Networking::SqueezeNetwork::Stats->init( $json );
#	}

	# add link to mysb.com favorites to our local favorites list
	if ( $json->{favorites_url} ) {

		my $favs = Slim::Utils::Favorites->new();

		if ( !defined $favs->findUrl($json->{favorites_url}) ) {

			$favs->add( $json->{favorites_url}, Slim::Utils::Strings::string('ON_MYSB'), undef, undef, undef, 'html/images/favorites.png' );

		}
	}
}

sub _init_error {
	my $http  = shift;
	my $error = $http->error;

	$log->error( sprintf("Unable to login to mysqueezebox.com, sync is disabled: $error (%s)", $http->url) );

	if ( my $proxy = $prefs->get('webproxy') ) {
		$log->error( sprintf("Please check your proxy configuration (%s)", $proxy) );
	} 

	$prefs->remove('sn_timediff');

	# back off if we keep getting errors
	my $count = $prefs->get('snInitErrors') || 0;
	$prefs->set( snInitErrors => $count + 1 );
	$loginErrors = $count + 1;

	my $retry = 300 * ( $count + 1 );
	$nextLoginAttempt = time() + $retry;

	$log->error( sprintf("mysqueezebox.com sync init failed: $error, will retry in $retry (%s)", $http->url) );

	Slim::Utils::Timers::setTimer(
		undef,
		$nextLoginAttempt + 10,
		sub { 
			__PACKAGE__->init();
		}
	);
}

# add non SN apps to Web interface if we are not logging into SN
# normally this is done when SN provides an updated list of apps on a per player basis in S:N:SqueezeNetwork:Player
sub _init_add_non_sn_apps {
	if (my $nonSNApps = Slim::Plugin::Base->nonSNApps) {
		for my $app (@$nonSNApps) {
			if (my $plugin = Slim::Utils::PluginManager->isEnabled($app) ) {
				my $url = Slim::Web::Pages->getPageLink( 'apps', $plugin->{'name'} );
				Slim::Web::Pages->addPageLinks( 'my_apps', { $plugin->{'name'} => $url } );
			}
		}
	}
}

# Stop all communication with SN, if the user removed their login info for example
sub shutdown {
	my $class = shift;

	$prefs->remove('sn_timediff');

	# Remove SN session
	$prefs->remove('sn_session');

	# Shutdown pref syncing
	if ( UNIVERSAL::can('Slim::Networking::SqueezeNetwork::PrefSync', 'shutdown') ) {
		Slim::Networking::SqueezeNetwork::PrefSync->shutdown();
	}

	# Shutdown player list fetch
	Slim::Networking::SqueezeNetwork::Players->shutdown();

	# Shutdown stats
#	if ( UNIVERSAL::can('Slim::Networking::SqueezeNetwork::Stats', 'shutdown') ) {
#		Slim::Networking::SqueezeNetwork::Stats->shutdown();
#	}
}

# both classes from which we inherit implement a sub url() - therefore we have to implement this little wrapper here
sub url { shift->_url(@_); }

# Is a URL on SN?
sub isSNURL {
	my ( $class, $url ) = @_;

	my $snBase = $class->url();

	# Allow old SN hostname to be seen as SN
	my $oldBase = $snBase;
	$oldBase =~ s/mysqueezebox/squeezenetwork/;

	return $url =~ /^$snBase/ || $url =~ /^$oldBase/;
}

# Login to SN and obtain a session ID
sub login {
	my ( $class, %params ) = @_;

	$class = ref $class || $class;

	my $client = $params{client};

	my $time = time();
	my $login_params;

	# don't run the query if we've failed recently
	if ( $time < $nextLoginAttempt && !$params{interactive} ) {
		$log->warn("We've failed to log in a few moments ago, or are still waiting for a response. Let's not try again just yet, we don't want to hammer mysqueezebox.com.");
		return $params{ecb}->(undef, cstring($client, 'SETUP_SN_VALIDATION_FAILED'));
	}

	# avoid parallel login attempts
	$nextLoginAttempt = max($time + 30, $nextLoginAttempt);

	my $username = $params{username};
	my $password = $params{password};

	if ( !$username || !$password ) {
		$username = $prefs->get('sn_email');
		$password = $prefs->get('sn_password_sha');
	}

	# Return if we don't have any SN login information
	if ( !$username || !$password ) {
		my $error = cstring($client, 'SQUEEZENETWORK_NO_LOGIN');

		main::INFOLOG && $log->info( $error );
		return $params{ecb}->( undef, $error );
	}

	main::INFOLOG && $log->is_info && $log->info("Logging in to " . $class->get_server('sn') . " as $username");

	$login_params = {
		v => 'sc' . $::VERSION,
		u => $username,
		t => $time,
		a => sha1_base64( $password . $time ),
	};

	my $self = $class->new(
		\&_login_done,
		\&_error,
		{
			params  => \%params,
			Timeout => 30,
		},
	);

	my $url = $self->_construct_url(
		'login',
		$login_params,
	);

	$self->get( $url );
}


sub getHeaders {
	my ( $self, $client ) = @_;

	my @headers;

	# Add player ID data
	if ( $client ) {
		push @headers, 'X-Player-MAC', $client->master()->id;
		if ( my $uuid = $client->master()->uuid ) {
			push @headers, 'X-Player-UUID', $uuid;
		}

		# Add device id/firmware info
		if ( $client->deviceid ) {
			push @headers, 'X-Player-DeviceInfo', $client->deviceid . ':' . $client->revision;
		}

		# Add player name
		my $name = $client->name;
		utf8::encode($name);
		push @headers, 'X-Player-Name', encode_base64( $name, '' );

		push @headers, 'X-Player-Model', $client->model;

		# Bug 13963, Add "controlled by" string so SN knows what kind of menu to return
		if ( my $controller = $client->controlledBy ) {
			push @headers, 'X-Controlled-By', $controller;
		}

		if ( my $controllerUA = $client->controllerUA ) {
			push @headers, 'X-Controller-UA', $controllerUA;
		}

		# Add Accept-Language header
		my $lang = $client->languageOverride(); # override from comet request

		$lang ||= $prefs->get('language') || 'en';

		push @headers, 'Accept-Language', lc($lang);

		# Request JSON instead of XML, it is much faster to parse
		push @headers, 'Accept', 'text/x-json, text/xml';
	}

	return @headers;
}

sub getAuthHeaders {
	my ( $self ) = @_;

	my $email = $prefs->get('sn_email') || '';
	my $pass  = $prefs->get('sn_password_sha') || '';

	return [
		sn_auth => $email . ':' . sha1_base64( $email . $pass )
	];
}

# Override to add session cookie header
sub _createHTTPRequest {
	my ( $self, $type, $url, @args ) = @_;

	# Add SN-specific headers
	unshift @args, $self->getHeaders( $self->params('client') );

	my $cookie;
	if ( $cookie = $self->getCookie( $self->params('client') ) ) {
		unshift @args, 'Cookie', $cookie;
	}

	if ( !$cookie && $url !~ m{api/v1/(login|radio)|public|update} ) {
		main::INFOLOG && $log->info("Logging in to SqueezeNetwork to obtain session ID");

		# Login and get a session ID
		$self->login(
			client => $self->params('client'),
			cb     => sub {
				if ( my $cookie = $self->getCookie( $self->params('client') ) ) {
					unshift @args, 'Cookie', $cookie;

					main::INFOLOG && $log->info('Got SqueezeNetwork session ID');
				}

				$self->SUPER::_createHTTPRequest( $type, $url, @args );
			},
			ecb    => sub {
				my ( $http, $error ) = @_;
				$self->error( $error ); 
				$self->ecb->( $self, $error );
			},
		);

		return;
	}

	$self->SUPER::_createHTTPRequest( $type, $url, @args );
}

sub _login_done {
	my $self   = shift;
	my $params = $self->params('params');

	my $json = eval { from_json( $self->content ) };

	if ( $@ ) {
		return $self->_error( $@ );
	}

	if ( $json->{error} ) {
		return $self->_error( $json->{error} );
	}

	if ( my $sid = $json->{sid}	) {
		$prefs->set( sn_session => $sid );
	}

	$nextLoginAttempt = $loginErrors = 0;

	main::DEBUGLOG && $log->debug("Logged into SN OK");

	$params->{cb}->( $self, $json );
}

sub _error {
	my ( $self, $error ) = @_;
	my $params = $self->params('params');

	# tell the login method not to try again
	$loginErrors++;
	$nextLoginAttempt = 60 * $loginErrors;

	my $proxy = $prefs->get('webproxy'); 

	$log->error( "Unable to login to SN: $error" 
		. ($proxy ? sprintf(" - please check your proxy configuration (%s)", $proxy) : '')
	); 

	$prefs->remove('sn_session');

	$self->error( $error );

	$params->{ecb}->( $self, $error );
}

sub _construct_url {
	my ( $self, $method, $params ) = @_;

	my $url = $self->url( '/api/v1/' . $method );

	if ( my @keys = keys %{$params} ) {
		my @params;
		foreach my $key ( @keys ) {
			push @params, uri_escape($key) . '=' . uri_escape( $params->{$key} );
		}
		$url .= '?' . join( '&', @params );
	}

	return $url;
}

1;



