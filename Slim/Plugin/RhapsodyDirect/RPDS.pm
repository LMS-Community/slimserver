package Slim::Plugin::RhapsodyDirect::RPDS;

# $Id$

# Rhapsody Direct RPDS firmware handler

use strict;

use Exporter::Lite;
use HTML::Entities qw(encode_entities);
use MIME::Base64 qw(decode_base64);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Timers;

our @EXPORT = qw(rpds cancel_rpds);

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.rhapsodydirect',
	'defaultLevel' => $ENV{RHAPSODY_DEV} ? 'DEBUG' : 'WARN',
	'description'  => 'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME',
});

# Can't use pluginData with coderefs because it's serialized
my $rpds_args = {};

sub handleError {
    return Slim::Plugin::RhapsodyDirect::Plugin::handleError(@_);
}

# Send an rpds command
sub rpds {
	my ( $client, $args ) = @_;
	
	Slim::Utils::Timers::killTimers( $client, \&rpds_timeout );
	Slim::Utils::Timers::killTimers( $client, \&rpds_resend );
	
	# Save callback info for rpds_handler
	$rpds_args->{$client} = $args;
	
	my $data = $args->{data};
	
	if ( !$data ) {
		# XXX: This should never happen...
		$log->warn( $client->id . ' No RPDS data found to send, args: ' . Data::Dump::dump($args) );
		bt();
		return;
	}

	$client->sendFrame( 'rpds', \$data );
	
	# Log all RPDS sends for debugging
	my $sent  = unpack('cC/a*', $data);

	if ( $ENV{SLIM_SERVICE} ) {
		# Log full RPDS unless it's RPDS 2 (contains passwords)
		if ( $sent != 2 ) {
			$sent = Data::Dump::dump($data);
		}
		
		SDI::Service::EventLog::logEvent( 
			$client->id, 'rpds', $sent,
		);
	}
	
	$log->warn( $client->id . " RPDS packet sent: $sent" );

	# Timeout in case the player is not responding
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + ( $args->{timeout} || 30 ), # Rhap can be slow
		\&rpds_timeout,
		$args
	);
}

sub rpds_timeout {
	my ( $client, $args ) = @_;
	
	my $sent_cmd = unpack 'c', $args->{data};
	
	$log->warn( $client->id . " RPDS request timed out, command: $sent_cmd");
	
	my $sent  = unpack('cC/a*', $args->{data});

	if ( $ENV{SLIM_SERVICE} ) {
		# Log full RPDS unless it's RPDS 2 (contains passwords)
		if ( $sent != 2 ) {
			$sent = Data::Dump::dump( $args->{data} );
		}
		
		logError( $client, 'RPDS_TIMEOUT', "$sent_cmd / $sent" );
	}
	
	delete $rpds_args->{$client};
	
	my $cb = $args->{onError} || sub {};
	my $pt = $args->{passthrough} || [];
	my $string = $client->string('PLUGIN_RHAPSODY_DIRECT_RPDS_TIMEOUT');
	$cb->( $string, $client, @{$pt} );
	return;
}

sub cancel_rpds {
	my $client = shift;
	
	Slim::Utils::Timers::killTimers( $client, \&rpds_timeout );
	Slim::Utils::Timers::killTimers( $client, \&rpds_resend );
	
	delete $rpds_args->{$client};
}
	
sub rpds_handler {
	my ( $client, $data_ref ) = @_;
	
	if ( $log->is_warn ) {
		$log->warn( $client->id . " Got RPDS packet: " . Data::Dump::dump($data_ref) );
	}
	
	my $got_cmd = unpack 'c', $$data_ref;
	
	# Check for -5 getEA failures here, so we don't screw up any other rpds commands
	if ( $got_cmd eq '-5' ) {
		if ( $ENV{SLIM_SERVICE} ) {
			logError( $client, 'RPDS_EA_FAILED' );
		}
		return;
	}
	
	Slim::Utils::Timers::killTimers( $client, \&rpds_timeout );

	my $rpds     = delete $rpds_args->{$client} || {};
	my $sent_cmd = $rpds->{data} ? unpack( 'c', $rpds->{data} ) : 'N/A';
	
	# Check for errors sent by the player
	if ( $got_cmd eq '-1' ) {
		# SOAP Fault
		my (undef, $faultCode, $faultString ) = unpack 'cn/a*n/a*', $$data_ref;
		
		$log->warn( $client->id . " Received RPDS fault: $faultCode - $faultString");
		
		if ( $ENV{SLIM_SERVICE} ) {
			logError( $client, 'RPDS_FAULT', "$sent_cmd / $faultString" );
		}
		
		# If a user's session becomes invalid, the firmware will keep retrying getEA
		# and report a fault of 'Playback Session id $foo is not a valid session id'
		# and so we need to stop the player and get a new session
		if ( $faultString =~ /not a valid session id/ ) {
			
			my $error = $client->string('PLUGIN_RHAPSODY_DIRECT_INVALID_SESSION');
			
			# Stop the player
			Slim::Player::Source::playmode( $client, 'stop' );
			
			# Track session errors so we don't get in a loop
			my $sessionErrors = $client->pluginData('sessionErrors') || 0;
			$sessionErrors++;
			
			$log->debug("Got invalid session error # $sessionErrors");
			
			if ( $sessionErrors > 1 ) {
				# On the second error, give up
				$log->debug("Giving up after multiple invalid session errors");
				
				handleError( $error, $client );
				
				return;
			}
			
			$client->pluginData( sessionErrors => $sessionErrors );
			
			my $restart = sub {
				# Clear radio data if any, so we always get a new radio track
				$client->pluginData( radioTrack => 0 );
				
				Slim::Plugin::RhapsodyDirect::ProtocolHandler::gotTrackError(
					$error, $client
				);
			};
			
			# call endPlaybackSession and then restart playback, which
			# will get a new session
			rpds( $client, {
				data        => pack( 'c', 6 ),
				callback    => $restart,
				onError     => $restart,
				passthrough => [],
			} );
			
			return;
		}
		
		my $cb = $rpds->{onError} || sub {};
		my $pt = $rpds->{passthrough} || [];
		my $string = sprintf( $client->string('PLUGIN_RHAPSODY_DIRECT_RPDS_FAULT'), $faultString );
		$cb->( $string, $client, @{$pt} );
		return;
	}
	elsif ( $got_cmd eq '-2' ) {
		# Player indicates it needs a new session
		
		$log->warn( $client->id . " Received RPDS -2, player needs a new session");
		
		if ( $ENV{SLIM_SERVICE} ) {
			logError( $client, 'RPDS_NO_SESSION' );
		}
		
		# XXX: What if this isn't available in pluginData?
		my $account = $client->pluginData('account');
		
		if ( !$account ) {
			bt();
			die "No Rhapsody account info available";
		}

		my $packet = pack 'cC/a*C/a*C/a*C/a*', 
			2,
			encode_entities( $account->{username}->[0] ),
			$account->{cobrandId}, 
			encode_entities( decode_base64( $account->{password}->[0] ) ), 
			$account->{clientType};
		
		rpds( $client, {
			data        => $packet,
			callback    => \&rpds_resend,
			onError     => \&handleError,
			passthrough => [ $rpds ],
		} );
		
		return;
	}
	elsif ( $got_cmd eq '-3' ) {
		# SSL connection error
		$log->warn( $client->id . " Received RPDS -3, SSL connection error");
		
		if ( $ENV{SLIM_SERVICE} ) {
			logError( $client, 'RPDS_SSL_ERROR' );
		}
		
		my $cb = $rpds->{onError} || sub {};
		my $pt = $rpds->{passthrough} || [];
		my $string = $client->string('PLUGIN_RHAPSODY_DIRECT_RPDS_SSL_ERROR');
		$cb->( $string, $client, @{$pt} );
		
		return;
	}
	elsif ( $got_cmd eq '-4' ) {
		# Another SSL connection is still in progress, we need to wait and try
		# sending the request again
		
		$log->warn( $client->id . " Received RPDS -4, SSL connection already in use, retrying later");
		
		if ( $ENV{SLIM_SERVICE} ) {
			logError( $client, 'RPDS_SSL_IN_USE' );
		}
		
		# Try to resend in a bit
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + 2,
			\&rpds_resend,
			undef,
			$rpds,
		);
		
		return;
	}	
	
	if ( !$rpds || $got_cmd ne $sent_cmd ) {
		$log->warn( $client->id . ' Received unrequested or old RPDS packet, ignoring' );
		
		if ( $ENV{SLIM_SERVICE} ) {
			logError( $client, 'RPDS_OLD', "got $got_cmd, ignoring" );
		}
		
		return;
	}
	
	# On an rpds 2 response, we have a new session so reset sessionErrors
	if ( $got_cmd eq '2' ) {
		$log->debug("New playback session obtained, resetting sessionErrors count to 0");
		$client->pluginData( sessionErrors => 0 );
	}
	
	my $cb = $rpds->{callback};
	my $pt = $rpds->{passthrough} || [];
	
	$cb->( $client, $$data_ref, @{$pt} );
}

# Resend an RPDS request that failed due to an invalid session
sub rpds_resend {
	my ( $client, undef, $rpds ) = @_;
	
	$log->warn( $client->id . ' Re-sending RPDS packet');
	
	rpds( $client, {
		data        => $rpds->{data},
		callback    => $rpds->{callback},
		onError     => $rpds->{onError},
		passthrough => $rpds->{passthrough},
	} );
}

1;

