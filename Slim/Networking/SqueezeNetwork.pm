package Slim::Networking::SqueezeNetwork;

# $Id: SqueezeNetwork.pm 11768 2007-04-16 18:14:55Z andy $

# Async interface to SqueezeNetwork API

use strict;
use warnings;
use base qw(Slim::Networking::SimpleAsyncHTTP);

use Digest::SHA1 qw(sha1_base64);
#use JSON::XS qw(from_json);
use JSON::Syck;
use MIME::Base64 qw(decode_base64);
use URI::Escape qw(uri_escape);

use Slim::Utils::IPDetect;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'network.squeezenetwork',
	'defaultLevel' => 'DEBUG',
	'description'  => 'SQUEEZENETWORK_LOGGING',
});

my $prefs = preferences('server');

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
	
	my $client = $params{client};
	
	my ($username, $password);
	
	# Get these directly if running on SN
	if ( $ENV{SLIM_SERVICE} ) {
		my $user  = $client->playerData->userid;
		$username = $user->email;
		$password = $user->password;
	}
	else {
		$username = $prefs->get('sn_email');
		$password = $prefs->get('sn_password');
		
		if ( $password ) {
			$password = sha1_base64( decode_base64( $password ) );
		}
	}
	
	# Return if we don't have any SN login information
	if ( !$username || !$password ) {
		$log->info("No SN login info found for " . $client->id . ", $username, $password");
		return $params{callback}->();
	}
	
	$log->info("Logging in to SN as $username");
	
	my $self = $class->new(
		\&_login_done,
		\&_error,
		{
			params => \%params,
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

# Override GET to add session cookie header
sub get {
	my ( $self, $url, %headers ) = @_;
	
	# Add session cookie if we have it
	if ( my $client = $self->params('client') ) {

		if ( my $sid = $client->snSession ) {
			$headers{Cookie} = 'sdi_squeezenetwork_session=' . uri_escape($sid);
			$headers{'X-Player-MAC'} = $client->id;
		}
		else {
			$log->info("Logging in to SqueezeNetwork to obtain session ID");
	
			# Login and get a session ID
			$self->login(
				client   => $client,
				callback => sub {
					if ( my $sid = $client->snSession ) {
						$headers{Cookie} = 'sdi_squeezenetwork_session=' . uri_escape($sid);
						$headers{'X-Player-MAC'} = $client->id;
			
						$log->info("Got SqueezeNetwork session ID: $sid");
					}
			
					$self->SUPER::get( $url, %headers );
				},
			);
	
			return;
		}
	}
	
	$self->SUPER::get( $url, %headers );
}	

sub _login_done {
	my $self   = shift;
	my $params = $self->params('params');
	
	#my $json = eval { from_json( $self->content ) };
	my $json = eval { JSON::Syck::Load( $self->content ) };
	
	if ( $@ ) {
		return $self->_error( $@ );
	}
	
	if ( $json->{error} ) {
		return $self->_error( $json->{error} );
	}
	
	if ( my $sid = $json->{sid}	) {
		$params->{client}->snSession( $sid );
	}
	
	$params->{callback}->();
}

sub _error {
	my ( $self, $error ) = @_;
	my $params = $self->params('params');
	
	# XXX: Error handling
	
	$params->{callback}->();
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
	
	
	