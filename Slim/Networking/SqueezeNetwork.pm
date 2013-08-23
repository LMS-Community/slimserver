package Slim::Networking::SqueezeNetwork;

# $Id: SqueezeNetwork.pm 11768 2007-04-16 18:14:55Z andy $

# Async interface to mysqueezebox.com API

use strict;
use base qw(Slim::Networking::SimpleAsyncHTTP);

use Digest::SHA1 qw(sha1_base64);
use JSON::XS::VersionOneAndTwo;
use MIME::Base64 qw(encode_base64);
use URI::Escape qw(uri_escape);

if ( !main::SLIM_SERVICE && !main::SCANNER ) {
	# init() is never called on SN so these aren't used
	require Slim::Networking::SqueezeNetwork::Players;
}

use Slim::Utils::IPDetect;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use constant SNTIME_POLL_INTERVAL => 3600;

my $log   = logger('network.squeezenetwork');

my $prefs = preferences('server');

# This is a hashref of mysqueezebox.com server types
#   and names.

my $_Servers = {
	sn      => 'www.mysqueezebox.com',
	update  => 'update.mysqueezebox.com',
	test    => 'www.test.mysqueezebox.com',
};

# Used only on SN
my $internal_http_host;
my $_sn_hosts;
my $_sn_hosts_re;

if ( main::SLIM_SERVICE ) {
	$internal_http_host = SDI::Util::SNConfig::get_config_value('internal_http_host');
	
	my $sn_server = __PACKAGE__->get_server('sn');
	
	my $mysb_host = SDI::Util::SNConfig::get_config_value('use_test_sn')
		? 'www.test.mysqueezebox.com'
		: 'www.mysqueezebox.com';
	my $sn_host = SDI::Util::SNConfig::get_config_value('use_test_sn')
		? 'www.test.squeezenetwork.com'
		: 'www.squeezenetwork.com';
	
	$_sn_hosts = join(q{|},
	        map { qr/\Q$_\E/ } (
			$sn_server,
			$mysb_host,
			$sn_host,
			$internal_http_host,
			($ENV{SN_DEV} ? '127.0.0.1' : ())
		)
	);
	$_sn_hosts_re = qr{
		^http://
		(?:$_sn_hosts)  # literally: (?:\Qsome.host\E|\Qother.host\E)
		(?::\d+)?	# optional port specification
		(?:/|$)		# /|$ prevents matching www.squeezenetwork.com.foo.com,
	}x;
}

sub get_server {
	my ($class, $stype) = @_;
	
	# Use SN test server if hidden test pref is set
	if ( $stype eq 'sn' && $prefs->get('use_sn_test') ) {
		$stype = 'test';
	}
	
	return $_Servers->{$stype}
		|| die "No hostname known for server type '$stype'";
}

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
			if (
				( $prefs->get('sn_email') && $prefs->get('sn_password_sha') )
				||
				Slim::Utils::OSDetect::isSqueezeOS()
			) {
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
	
	_syncSNTime_done($http, $snTime);
	
	# Clear error counter
	$prefs->remove( 'snInitErrors' );
	
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
	if (!$prefs->get('sn_disable_stats')) {
		require Slim::Networking::SqueezeNetwork::Stats;
		Slim::Networking::SqueezeNetwork::Stats->init( $json );
	}

	
	# add link to mysb.com favorites to our local favorites list
	if ( !main::SLIM_SERVICE && $json->{favorites_url} ) {

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
	
	my $retry = 300 * ( $count + 1 );
	
	$log->error( sprintf("mysqueezebox.com sync init failed: $error, will retry in $retry (%s)", $http->url) );
	
	Slim::Utils::Timers::setTimer(
		undef,
		time() + $retry,
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
	if ( UNIVERSAL::can('Slim::Networking::SqueezeNetwork::Stats', 'shutdown') ) {
		Slim::Networking::SqueezeNetwork::Stats->shutdown();
	}
}

# Return a correct URL for mysqueezebox.com
sub url {
	my ( $class, $path, $external ) = @_;
	
	# There are 3 scenarios:
	# 1. Local dev, running SN on localhost:3000
	# 2. An SN instance, needs to access using an internal IP
	# 3. Public user
	my $base;
	
	$path ||= '';
	
	if ( !$external ) {
		if ( main::SLIM_SERVICE ) {
			$base = 'http://' . $internal_http_host;
        }
        elsif ( $ENV{SN_DEV} ) {
			$base = 'http://127.0.0.1:3000';  # Local dev
		}
	}
	
	$base ||= 'http://' . $class->get_server('sn');
	
	return $base . $path;
}

# Is a URL on SN?
sub isSNURL {
	my ( $class, $url ) = @_;
	
	if ( main::SLIM_SERVICE ) {
		return $url =~ /$_sn_hosts_re/o;
	}
	
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
	
	if ( Slim::Utils::OSDetect::isSqueezeOS() ) {
		# login using MAC/UUID on TinySBS
		my $osDetails = Slim::Utils::OSDetect::details();
		
		main::INFOLOG && $log->is_info && $log->info("Logging in to " . $_Servers->{sn} . " as " . $osDetails->{mac});
		
		$login_params = {
			v => 'sc' . $::VERSION,
			m => $osDetails->{mac},
			t => $time,
			a => sha1_base64( $osDetails->{uuid} . $time ),
		};
	}
	else {		
		my $username = $params{username};
		my $password = $params{password};
	
		if ( !$username || !$password ) {
			$username = $prefs->get('sn_email');
			$password = $prefs->get('sn_password_sha');
		}
	
		# Return if we don't have any SN login information
		if ( !$username || !$password ) {
			my $error = $client 
				? $client->string('SQUEEZENETWORK_NO_LOGIN')
				: Slim::Utils::Strings::string('SQUEEZENETWORK_NO_LOGIN');
			
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
	}
	
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


sub syncSNTime {
	# we only want this to run on SqueezeOS/SB Touch
	return unless Slim::Utils::OSDetect::isSqueezeOS();
	
	my $http = __PACKAGE__->new(
		\&_syncSNTime_done,
		\&_syncSNTime_done,
	);
	
	$http->get( $http->url( '/api/v1/time' ) );
}

sub _syncSNTime_done {
	my ($http, $snTime) = @_;

	# we only want this to run on SqueezeOS/SB Touch
	return unless Slim::Utils::OSDetect::isSqueezeOS();

	if (!$snTime && $http && $http->content) {
		$snTime = $http->content;
	}

	if ( $snTime && $snTime =~ /^\d+$/ && $snTime > 1262887372 ) {
		main::INFOLOG && $log->info("Got SqueezeNetwork server time - set local time to $snTime");
		
		# update offset to SN time
		$prefs->set( sn_timediff => $snTime - time() );
		
		# set local time to mysqueezebox.com's epochtime 
		Slim::Control::Request::executeRequest(undef, ['date', "set:$snTime"]);	
	}
	else {
		$log->error("Invalid or no mysqueezebox.com server timestamp - ignoring");
	}

	Slim::Utils::Timers::killTimers( undef, \&syncSNTime );
	Slim::Utils::Timers::setTimer(
		undef,
		time() + SNTIME_POLL_INTERVAL,
		\&syncSNTime,
	);
		
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
			
		if ( main::SLIM_SERVICE ) {
			$lang ||= $prefs->client($client)->get('language');
		}
	
		$lang ||= $prefs->get('language') || 'en';
			
		push @headers, 'Accept-Language', lc($lang);
		
		# Request JSON instead of XML, it is much faster to parse
		push @headers, 'Accept', 'text/x-json, text/xml';
		
		if ( main::SLIM_SERVICE ) {
			# Indicate player is on SN and provide real client IP
			push @headers, 'X-Player-SN', 1;
			push @headers, 'X-Player-IP', $client->ip;
		}
	}
	
	return @headers;
}

sub getAuthHeaders {
	my ( $self ) = @_;
	
	if ( Slim::Utils::OSDetect::isSqueezeOS() ) {
		
		# login using MAC/UUID on TinySBS
		my $osDetails = Slim::Utils::OSDetect::details();
		my $time = time();
		
		return [
			sn_auth_u => $osDetails->{mac} . '|' . $time . '|' . sha1_base64( $osDetails->{uuid} . $time ),
		];
	}
	
	my $email = $prefs->get('sn_email') || '';
	my $pass  = $prefs->get('sn_password_sha') || '';

	return [
		sn_auth => $email . ':' . sha1_base64( $email . $pass )
	];
}

sub getCookie {
	my ( $self, $client ) = @_;
	
	# Add session cookie if we have it
	if ( main::SLIM_SERVICE ) {
		# Get sid directly if running on SN
		if ( $client ) {
			my $user = $client->playerData->userid;
			my $sid  = $user->id . ':' . $user->password;
			return 'sdi_squeezenetwork_session=' . uri_escape($sid);
		}
		else {
			bt();
			$log->error( "SN request without a client" );
		}
	}
	elsif ( my $sid = $prefs->get('sn_session') ) {
		return 'sdi_squeezenetwork_session=' . uri_escape($sid);
	}
	
	return;
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
	
	main::DEBUGLOG && $log->debug("Logged into SN OK");
	
	$params->{cb}->( $self, $json );
}

sub _error {
	my ( $self, $error ) = @_;
	my $params = $self->params('params');
	
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
	
	
	
