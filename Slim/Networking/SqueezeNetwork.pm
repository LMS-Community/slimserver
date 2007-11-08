package Slim::Networking::SqueezeNetwork;

# $Id: SqueezeNetwork.pm 11768 2007-04-16 18:14:55Z andy $

# Async interface to SqueezeNetwork API

use strict;
use base qw(Slim::Networking::SimpleAsyncHTTP);

use JSON::XS qw(from_json);
use URI::Escape qw(uri_escape);

use Slim::Networking::SqueezeNetwork::Players;
use Slim::Networking::SqueezeNetwork::PrefSync;
use Slim::Networking::SqueezeNetwork::Stats;
use Slim::Utils::IPDetect;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $log   = logger('network.squeezenetwork');

my $prefs = preferences('server');

# Initialize by fetching the SN server time and storing our time difference
sub init {
	my $class = shift;
	
	$log->info('SqueezeNetwork Sync Init');
	
	my $timeURL = $class->url( '/api/v1/time' );
	
	my $http = $class->new(
		\&_init_done,
		\&_init_error,
		{
			Timeout => 30,
		},
	);
	
	# Any async HTTP in init must be done on a timer
	Slim::Utils::Timers::setTimer(
		undef,
		time(),
		sub {
			$http->get( $timeURL );
		},
	);
}

sub _init_done {
	my $http = shift;
	
	my $snTime = $http->content;
	
	if ( $snTime !~ /^\d+$/ ) {
		$http->error( "Invalid SqueezeNetwork server timestamp" );
		return _init_error( $http );
	}
	
	my $diff = $snTime - time();
	
	$log->info("Got SqueezeNetwork server time: $snTime, diff: $diff");
	
	$prefs->set( 'sn_timediff' => $diff );
	
	# Clear error counter
	$prefs->remove( 'snInitErrors' );
	
	# Init pref syncing
	Slim::Networking::SqueezeNetwork::PrefSync->init();
	
	# Init polling for list of SN-connected players
	Slim::Networking::SqueezeNetwork::Players->init();
	
	# Init stats
	Slim::Networking::SqueezeNetwork::Stats->init();
}

sub _init_error {
	my $http  = shift;
	my $error = $http->error;
	
	$log->error( "Unable to get SqueezeNetwork server time, sync is disabled: $error" );
	
	$prefs->remove('sn_timediff');
	
	# back off if we keep getting errors
	my $count = $prefs->get('snInitErrors') || 0;
	$prefs->set( snInitErrors => $count + 1 );
	
	my $retry = 300 * ( $count + 1 );
	
	$log->error( "SqueezeNetwork sync init failed: $error, will retry in $retry" );
	
	Slim::Utils::Timers::setTimer(
		undef,
		time() + $retry,
		sub { 
			__PACKAGE__->init();
		}
	);
}

# Stop all communication with SN, if the user removed their login info for example
sub shutdown {
	my $class = shift;
	
	$prefs->remove('sn_timediff');
	
	# Shutdown pref syncing
	Slim::Networking::SqueezeNetwork::PrefSync->shutdown();
	
	# Shutdown player list fetch
	Slim::Networking::SqueezeNetwork::Players->shutdown();
	
	# Shutdown stats
	Slim::Networking::SqueezeNetwork::Stats->shutdown();
}

# Return a correct URL for SqueezeNetwork
sub url {
	my ( $class, $path ) = @_;
	
	# There are 3 scenarios:
	# 1. Local dev, running SN on localhost:3000
	# 2. An SN instance, needs to access using an internal IP
	# 3. Public user
	my $base;
	
	$path ||= '';
	
	if ( $ENV{SLIM_SERVICE} || $ENV{SN_DEV} ) {
		my $ip = Slim::Utils::IPDetect::IP();
		$base  = ( $ip =~ /^192.168.254/ ) 
			? 'http://192.168.254.200' # Production
			: 'http://127.0.0.1:3000';  # Local dev
	}
	else {
		# XXX: Port 3000 is the SN beta website, this will change back to 
		# port 80 before release.
		$base = 'http://www.squeezenetwork.com:3000';
	}
	
	return $base . $path;
}

# Is a URL on SN?
sub isSNURL {
	my ( $class, $url ) = @_;
	
	my $snBase = $class->url();
	
	return $url =~ /^$snBase/;
}

# Login to SN and obtain a session ID
sub login {
	my ( $class, %params ) = @_;
	
	$class = ref $class || $class;
	
	my $client = $params{client};
	
	my $username = $params{username};
	my $password = $params{password};
	
	if ( !$username || !$password ) {
		# Get these directly if running on SN
		if ( $ENV{SLIM_SERVICE} ) {
			my $user  = $client->playerData->userid;
			$username = $user->email;
			$password = $user->password;
		}
		else {
			$username = $prefs->get('sn_email');
			$password = $prefs->get('sn_password');
		}
	}
	
	# Return if we don't have any SN login information
	if ( !$username || !$password ) {
		my $error = $client->string('SQUEEZENETWORK_NO_LOGIN');
		$log->info( $error );
		return $params{ecb}->( undef, $error );
	}
	
	$log->info("Logging in to SN as $username");
	
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
		{
			username => $username,
			password => $password,
		},
	);
	
	$self->get( $url );
}

# Override to add session cookie header
sub _createHTTPRequest {
	my ( $self, $type, $url, @args ) = @_;
	
	# Indicate our language preference
	unshift @args, 'Accept-Language', lc( $prefs->get('language') ) || 'en';
	
	# Add session cookie if we have it
	if ( my $client = $self->params('client') ) {

		if ( my $sid = $client->snSession ) {
			unshift @args, 'Cookie', 'sdi_squeezenetwork_session=' . uri_escape($sid);
			unshift @args, 'X-Player-MAC', $client->id;	
		}
		else {
			$log->info("Logging in to SqueezeNetwork to obtain session ID");
	
			# Login and get a session ID
			$self->login(
				client => $client,
				cb     => sub {
					if ( my $sid = $client->snSession ) {
						unshift @args, 'Cookie', 'sdi_squeezenetwork_session=' . uri_escape($sid);
						unshift @args, 'X-Player-MAC', $client->id;
			
						$log->info("Got SqueezeNetwork session ID: $sid");
					}
			
					$self->SUPER::_createHTTPRequest( $type, $url, @args );
				},
				ecb    => sub {
					my ( $http, $error ) = @_;
					$self->error( $error ); 
					$self->{ecb}->( $self, $error );
				},
			);
	
			return;
		}
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
		if ( $params->{client} ) {
			$params->{client}->snSession( $sid );
		}
	}
	
	$params->{cb}->();
}

sub _error {
	my ( $self, $error ) = @_;
	my $params = $self->params('params');
	
	$log->error( "Unable to login to SN: $error" );
	
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
	
	
	
