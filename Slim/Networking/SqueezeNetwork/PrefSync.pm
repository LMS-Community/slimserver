package Slim::Networking::SqueezeNetwork::PrefSync;

# $Id: SqueezeNetwork.pm 11768 2007-04-16 18:14:55Z andy $

# Sync prefs from SS <-> SN

use strict;

use File::Basename qw(basename dirname);
use File::Spec::Functions qw(catfile);
use JSON::XS qw(to_json from_json);

use Slim::Control::Request;
use Slim::Hardware::IR;
use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $log   = logger('network.squeezenetwork');

my $prefs = preferences('server');

# List of prefs we want to sync to SN
our $can_sync = {};

sub init {
	my $class = shift;
	
	# Get the list of prefs SN will sync with us
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_init_done,
		\&_init_error,
	);
	
	$http->get( $http->url( '/api/v1/prefs/can_sync' ) );
}

sub _init_done {
	my $http = shift;
	
	my $res = eval { from_json( $http->content ) };
	if ( $@ || ref $res ne 'ARRAY' ) {
		$http->error( $@ || 'Invalid JSON response' );
		return _init_error( $http );
	}
	
	$can_sync = {
		map { $_ => 1 }
		@{ $res }
	};
	
	if ( $log->is_debug ) {
		$log->debug("Got list of SN prefs to sync: " . scalar(@{$res}) . " prefs");
	}
	
	# Sync all connected clients with SN
	# New clients will be handled by clientEvent
	for my $client ( Slim::Player::Client::clients() ) {
		next unless $client->isa('Slim::Player::Squeezebox2');
		
		Slim::Utils::Timers::setTimer(
			$client,
			time() + 10,
			\&syncDown,
		);
	}
	
	# Subscribe to pref changes
	Slim::Control::Request::subscribe( 
		\&prefEvent, 
		[['prefset']]
	);
	
	# Subscribe to player connect/disconnect messages
	Slim::Control::Request::subscribe(
		\&clientEvent,
		[['client'],['new','reconnect','disconnect']]
	);
}

sub clientEvent {
	my $request = shift;
	my $client  = $request->client;
	
	if ( !$client->isa('Slim::Player::Squeezebox2') ) {
		return;
	}
	
	Slim::Utils::Timers::killTimers( $client, \&syncDown );
	
	# If the event was for a new client, sync down now
	my $event = $request->getRequest(1);
	if ( $event =~ /(?:new|reconnect)/ ) {
		if ( $log->is_debug ) {
			$log->debug( $client->id . ": Got client $event event, syncing prefs from SN" );
		}
		
		syncDown($client);
	}
	elsif ( $event eq 'disconnect' ) {
		# Client is gone, kill any pending syncUp event (syncDown killed above)
		if ( $log->is_debug ) {
			$log->debug( $client->id . ': Got client disconnect event, disabling sync' );
		}
		
		Slim::Utils::Timers::killTimers( $client, \&syncUp );
	}
}

sub _init_error {
	my $http  = shift;
	my $error = $http->error;
	
	$log->error( "Unable to get list of prefs to sync with SqueezeNetwork, sync is disabled: $error" );
	
	$can_sync = {};
}

# Shut down
sub shutdown {
	my $class = shift;
	
	$can_sync = {};
	
	Slim::Control::Request::unsubscribe( \&prefEvent );
	
	Slim::Control::Request::unsubscribe( \&clientEvent );
	
	for my $client ( Slim::Player::Client::clients() ) {
		Slim::Utils::Timers::killTimers( $client, \&syncUp );
		Slim::Utils::Timers::killTimers( $client, \&syncDown );
	}
	
	$log->info( "SqueezeNetwork pref sync shutdown" );
}

sub syncDown {
	my $client = shift || return;
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_syncDown_done,
		\&_syncDown_error,
		{
			client => $client,
		},
	);
	
	my $sync = {
		client => $client->id,
		since  => $prefs->client($client)->get('snLastSyncDown'),
	};
	
	if ( $log->is_debug ) {
		$log->debug( "Syncing down from SN: " . Data::Dump::dump($sync) );
	}
	
	my $json = eval { to_json($sync) };
	if ( $@ ) {
		$http->error( $@ );
		return _syncDown_error( $http );
	}
	
	$http->post( $http->url( '/api/v1/prefs/sync_down' ), $json );
}

sub _syncDown_done {
	my $http   = shift;
	my $client = $http->params('client');
	
	my $content = eval { from_json( $http->content ) };
	if ( $@ || $content->{error} ) {
		$http->error( $@ || $content->{error} );
		return _syncDown_error( $http );
	}
	
	my $cprefs = $prefs->client($client);
	
	if ( $log->is_debug ) {
		$log->debug( 'Sync down data from SN: ' . Data::Dump::dump($content) );
	}
	
	$cprefs->set( snLastSyncDown => $content->{timestamp} );
	$cprefs->set( snSyncInterval => $content->{next_sync} );
	
	$cprefs->remove('snSyncErrors');
		
	while ( my ($pref, $data) = each %{ $content->{prefs} } ) {
			
		# compare timestamps
		if ( $data->{ts} > $cprefs->timestamp($pref) ) {		
			
			# special handling needed to rewrite disabledirsets with full pathname
			if ( $pref eq 'disabledirsets' ) {
				# Force array pref
				if ( !ref $data->{value} ) {
					$data->{value} = [ $data->{value} ];
				}
				
				# XXX: This may break if users have custom IR files in a different directory
				my $irfiles = Slim::Hardware::IR::irfiles();
				my $dir     = dirname( (keys %{$irfiles})[0] );
				$data->{value} = [ map { catfile( $dir, $_ ) } @{ $data->{value} } ];
			}			
		
			if ( $log->is_debug ) {
				$log->debug("Synced $pref to: " . Data::Dump::dump( $data->{value} ) );
			}
		
			$cprefs->set( $pref => $data->{value} );
		
			# Wipe timestamp values so the pref is
			# not immediately synced back up to SN
			$cprefs->timestamp( $pref, 'wipe' );
		}
	}
	
	$client->update;
	
	if ( $log->is_debug ) {
		$log->debug( 'Synced prefs from SN for player ' . $client->id );
	}
	
	# Schedule next sync
	Slim::Utils::Timers::setTimer( 
		$client, 
		time() + $content->{next_sync},
		\&syncDown
	);
}

sub _syncDown_error {
	my $http  = shift;
	my $error = $http->error;
	
	my $client = $http->params('client');
	
	# back off if we keep getting errors
	my $cprefs = $prefs->client($client);
	my $count = $cprefs->get('snSyncErrors') || 0;
	$cprefs->set( snSyncErrors => $count + 1 );
	
	my $retry = $cprefs->get('snSyncInterval') * ( $count + 1 );
	
	$log->error( "Sync Down failed: $error, will retry in $retry" );
	
	Slim::Utils::Timers::setTimer(
		$client,
		time() + $retry,
		\&syncDown,
	);
}

# Callback whenever a pref is changed
# XXX: Support changes to global prefs
sub prefEvent {
	my $request = shift;
	my $client  = $request->client || return;
	
	if ( !$client->isa('Slim::Player::Squeezebox2') ) {
		return;
	}
	
	my $ns    = $request->getParam('_namespace');
	my $pref  = $request->getParam('_prefname');
	my $value = $request->getParam('_newvalue');
	
	# Is the pref one we care about?
	if ( !exists $can_sync->{$pref} ) {
		return;
	}
	
	# Was this pref just synced to us from SN?  If so, ignore it
	if ( $prefs->client($client)->timestamp($pref) == -1 ) {
		return;
	}
	
	if ( $log->is_debug ) {
		$log->debug( "prefEvent to sync: " . $client->id . " / $ns / $pref / " . Data::Dump::dump($value) );
	}
	
	# Kill existing sync timer, if any
	# This way, if someone is changing a lot of prefs, we don't sync until things
	# have settled down for a while
	Slim::Utils::Timers::killTimers( $client, \&syncUp );
	
	# Set a timer to sync the changes
	Slim::Utils::Timers::setTimer( $client, Time::HiRes::time() + 30, \&syncUp );
}

sub syncUp {
	my $client = shift || return;
	
	my $cprefs = $prefs->client($client);
	
	my $sync = {
		client => $client->id,
		prefs  => {},
	};
	
	my $sn_timediff = $prefs->get('sn_timediff');
	
	# Send prefs that have been changed since the last sync
	my $lastSync = $cprefs->get('snLastSyncUp');
	
	for my $pref ( keys %{$can_sync} ) {
		my $ts = $cprefs->timestamp($pref);
		if ( $ts >= $lastSync ) {
			my $value = $cprefs->get($pref);
			if ( !defined $value ) {
				$value = $prefs->get($pref);
			}
			
			# special handling needed to rewrite disabledirsets with no pathname
			if ( $pref eq 'disabledirsets' ) {
				$value = [ map { basename($_) } @{$value} ];
			}
			
			$sync->{prefs}->{$pref} = {
				value => $value,
				ts    => $ts + $sn_timediff,
			};
		}
	}
	
	if ( $log->is_debug ) {
		$log->debug( 'Syncing up to SN: ' . Data::Dump::dump($sync) );
	}
	
	my $json = eval { to_json($sync) };
	if ( $@ ) {
		$log->error( "Unable to sync up: $@" );
		return;
	}
	
	$cprefs->set( snLastSyncUp => time() );
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_syncUp_done,
		\&_syncUp_error,
		{
			client => $client,
		},
	);
	
	$http->post( $http->url( '/api/v1/prefs/sync_up' ), $json );
}

sub _syncUp_done {
	my $http = shift;
	
	my $content = eval { from_json( $http->content ) };
	
	if ( $@ || $content->{error} ) {
		$http->error( $@ || $content->{error} );
		return _syncUp_error( $http );
	}
	
	$log->info( 'Sync OK' );
}

sub _syncUp_error {
	my $http   = shift;
	my $error  = $http->error;
	my $client = $http->params('client');
	
	$prefs->client($client)->set( snLastSyncUp => -1 );
	
	$log->error( "Sync Up failed: $error" );
}

1;
