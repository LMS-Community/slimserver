package Slim::Networking::SqueezeNetwork::PrefSync;

# $Id: SqueezeNetwork.pm 11768 2007-04-16 18:14:55Z andy $

# Sync prefs from SS <-> SN

use strict;

use File::Basename qw(basename dirname);
use File::Spec::Functions qw(catfile);
use JSON::XS::VersionOneAndTwo;

use Slim::Control::Request;
use Slim::Hardware::IR;
use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $log   = logger('network.squeezenetwork.prefsync');

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
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug("Got list of SN prefs to sync: " . scalar(@{$res}) . " prefs");
	}
	
	# Sync all connected clients with SN
	# New clients will be handled by clientEvent
	for my $client ( Slim::Player::Client::clients() ) {
		next unless $client->isa('Slim::Player::Squeezebox2') && $client->deviceid !~ /^(?:3|6|8|11|12)/;
		
		Slim::Utils::Timers::setTimer(
			$client,
			time() + int( rand(10) ),
			\&syncDown,
		);
	}
	
	# Sync global prefs
	Slim::Utils::Timers::setTimer(
		undef,
		time() + int( rand(10) ),
		\&syncDownGlobal,
	);
	
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
	
	if ( !defined $client || !$client->isa('Slim::Player::Squeezebox2') || $client->deviceid =~ /^(?:3|6|8|11|12)/ ) {
		return;
	}
	
	Slim::Utils::Timers::killTimers( $client, \&syncDown );
	
	# If the event was for a new client, sync down now
	my $event = $request->getRequest(1);
	if ( $event =~ /(?:new|reconnect)/ ) {
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( $client->id . ": Got client $event event, syncing prefs from SN" );
		}
		
		syncDown($client);
	}
	elsif ( $event eq 'disconnect' ) {
		# Client is gone, kill any pending syncUp event (syncDown killed above)
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( $client->id . ': Got client disconnect event, disabling sync' );
		}
		
		Slim::Utils::Timers::killTimers( $client, \&syncUp );
	}
}

sub _init_error {
	my $http  = shift;
	my $error = $http->error;
	
	$log->warn( "Unable to get list of prefs to sync with mysqueezebox.com, sync is disabled: $error" );
	
	$prefs->remove('sn_session');
	
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
	
	Slim::Utils::Timers::killTimers( undef, \&syncUpGlobal );
	Slim::Utils::Timers::killTimers( undef, \&syncDownGlobal );
	
	main::INFOLOG && $log->info( "SqueezeNetwork pref sync shutdown" );
}

sub syncDown {
	my $client = shift || return;
	
	Slim::Utils::Timers::killTimers( $client, \&syncDown );
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_syncDown_done,
		\&_syncDown_error,
		{
			client => $client,
		},
	);
	
	my $sync = {
		client   => $client->id,
		uuid     => $client->uuid,
		deviceid => $client->deviceid,
		model    => $client->model,
		rev      => $client->revision,
		name     => $client->name,
		since    => $prefs->client($client)->get('snLastSyncDown'),
	};
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Requesting sync down from SN: " . Data::Dump::dump($sync) );
	}
	
	my $json = eval { to_json($sync) };
	if ( $@ ) {
		$http->error( $@ );
		return _syncDown_error( $http );
	}
	
	$http->post( $http->url( '/api/v1/prefs/sync_down' ), $json );
}

sub syncDownGlobal {
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_syncDown_done,
		\&_syncDown_error,
	);
	
	my $sync = {
		since => $prefs->get('snLastSyncDown'),
	};
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Requesting global sync down from SN: " . Data::Dump::dump($sync) );
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
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Sync down data from SN: ' . Data::Dump::dump($content) );
	}

	# Client prefs
	if ( $client ) {
		my $cprefs = $prefs->client($client);
		
		if ( ($content->{next_sync} || 0) < 60 ) {
			$content->{next_sync} = 300;
		}
	
		$cprefs->set( snLastSyncDown => $content->{timestamp} );
		$cprefs->set( snSyncInterval => $content->{next_sync} );
	
		$cprefs->remove('snSyncErrors');
		
		while ( my ($pref, $data) = each %{ $content->{prefs} } ) {
			
			if ( $pref =~ /\./ ) {
				# It's a plugin pref
				my ($ns, $prefname) = $pref =~ /(\w+\.\w+)\.(\w+)/;

				my $rprefs = preferences($ns);
				
				# compare timestamps
				if ( $data->{ts} > $rprefs->client($client)->timestamp($prefname) ) {
					if ( main::DEBUGLOG && $log->is_debug ) {
						$log->debug("Synced " . $client->id . " ${ns}.${prefname} to: " . Data::Dump::dump( $data->{value} ) );
					}

					$rprefs->client($client)->set( $prefname => $data->{value} );

					# Wipe timestamp values so the pref is
					# not immediately synced back up to SN
					$rprefs->client($client)->timestamp( $prefname, 'wipe' );
				}
			}
			else {
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

					if ( main::DEBUGLOG && $log->is_debug ) {
						$log->debug("Synced " . $client->id . " $pref to: " . Data::Dump::dump( $data->{value} ) );
					}

					$cprefs->set( $pref => $data->{value} );

					# Wipe timestamp values so the pref is
					# not immediately synced back up to SN
					$cprefs->timestamp( $pref, 'wipe' );
					
					if ( $pref eq 'alarms' ) {
						# Reload any changed alarms
					 	Slim::Utils::Alarm->loadAlarms($client);
					}
				}
			}
		}

		$client->update;

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( 'Synced prefs from SN for player ' . $client->id );
		}

		# Schedule next sync
		Slim::Utils::Timers::setTimer( 
			$client, 
			time() + $content->{next_sync},
			\&syncDown,
		);
	}
	
	# Global prefs
	else {
		$prefs->set( snLastSyncDown => $content->{timestamp} );
	
		$prefs->remove('snSyncErrors');
		
		while ( my ($pref, $data) = each %{ $content->{prefs} } ) {
			my ($ns, $prefname) = $pref =~ /(\w+\.\w+)\.(\w+)/;
			
			my $rprefs = preferences($ns);		

			# compare timestamps
			if ( $data->{ts} > $rprefs->timestamp($prefname) ) {
				
				# If pref value looks like JSON, try to decode it
				# (used for AudioScrobbler accounts)
				if ( $data->{value} =~ /^(?:\[|{)/ ) {
					my $decoded = eval { from_json( $data->{value} ) };
					if ( !$@ ) {
						$data->{value} = $decoded;
					}
				}
				
				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug("Synced ${ns}.${prefname} to: " . Data::Dump::dump( $data->{value} ) );
				}

				$rprefs->set( $prefname => $data->{value} );

				# Wipe timestamp values so the pref is
				# not immediately synced back up to SN
				$rprefs->timestamp( $prefname, 'wipe' );
			}
		}
	}
}

sub _syncDown_error {
	my $http  = shift;
	my $error = $http->error;
	
	my $client = $http->params('client');
	
	if ( $client ) {
		# back off if we keep getting errors
		my $cprefs = $prefs->client($client);
		my $count  = $cprefs->get('snSyncErrors') || 0;
		$cprefs->set( snSyncErrors => $count + 1 );
	
		my $retry = $cprefs->get('snSyncInterval') * ( $count + 1 );
	
		$log->warn( "Sync Down failed: $error, will retry in $retry" );
	
		Slim::Utils::Timers::setTimer(
			$client,
			time() + $retry,
			\&syncDown,
		);
	}
	else {
		$log->warn( "Global Sync Down failed: $error" );
	}
}

# Callback whenever a pref is changed
sub prefEvent {
	my $request = shift;
	my $client  = $request->client;
	
	if ( !defined $client || !$client->isa('Slim::Player::Squeezebox2') || $client->deviceid =~ /^(?:3|6|8|11|12)/ ) {
		return;
	}
	
	my $ns    = $request->getParam('_namespace');
	my $pref  = $request->getParam('_prefname');
	my $value = $request->getParam('_newvalue');
	
	# Client prefs
	if ( $client ) {
		# Is the pref one we care about?
		if ( !exists $can_sync->{$pref} ) {
			return;
		}
		
		# Was this pref just synced to us from SN?  If so, ignore it
		if ( $prefs->client($client)->timestamp($pref) == -1 ) {
			return;
		}
	
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Client prefEvent to sync: " . $client->id . " / $ns / $pref / " . Data::Dump::dump($value) );
		}
	
		# Kill existing sync timer, if any
		# This way, if someone is changing a lot of prefs, we don't sync until things
		# have settled down for a while
		Slim::Utils::Timers::killTimers( $client, \&syncUp );
	
		# Set a timer to sync the changes
		Slim::Utils::Timers::setTimer( $client, Time::HiRes::time() + 30, \&syncUp );
	}
	
	# Global prefs
	else {
		# Is the pref one we care about?
		if ( !exists $can_sync->{ "${ns}.${pref}" } ) {
			return;
		}
		
		my $rprefs = preferences($ns);
		
		# Was this pref just synced to us from SN?  If so, ignore it
		if ( $rprefs->timestamp($pref) == -1 ) {
			return;
		}
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Global prefEvent to sync: $ns / $pref / " . Data::Dump::dump($value) );
		}
		
		# Kill existing sync timer, if any
		# This way, if someone is changing a lot of prefs, we don't sync until things
		# have settled down for a while
		Slim::Utils::Timers::killTimers( undef, \&syncUpGlobal );
	
		# Set a timer to sync the changes
		Slim::Utils::Timers::setTimer( undef, Time::HiRes::time() + 30, \&syncUpGlobal );
	}
}

sub syncUp {
	my $client = shift || return;
	
	Slim::Utils::Timers::killTimers( $client, \&syncUp );
	
	my $cprefs = $prefs->client($client);
	
	my $sync = {
		client   => $client->id,
		uuid     => $client->uuid,
		deviceid => $client->deviceid,
		rev      => $client->revision,
		name     => $client->name,
		prefs    => {},
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
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Syncing client prefs up to SN: ' . Data::Dump::dump($sync) );
	}
	
	my $json = eval { to_json($sync) };
	if ( $@ ) {
		$log->warn( "Unable to sync up: $@" );
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

sub syncUpGlobal {	
	my $sync = {
		prefs => {},
	};
	
	my $sn_timediff = $prefs->get('sn_timediff');
	
	# Send prefs that have been changed since the last sync
	my $lastSync = $prefs->get('snLastSyncUp') || 0;
	
	for my $pref ( keys %{$can_sync} ) {
		next unless $pref =~ /\./;
		
		my ($ns, $prefname) = $pref =~ /(\w+\.\w+)\.(\w+)/;
		
		my $rprefs = preferences($ns);
		
		my $ts = $rprefs->timestamp($prefname);
		
		if ( $ts >= $lastSync ) {
			my $value = $rprefs->get($prefname);
			
			$sync->{prefs}->{$pref} = {
				value => $value,
				ts    => $ts + $sn_timediff,
			};
		}
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Syncing global prefs up to SN: ' . Data::Dump::dump($sync) );
	}
	
	my $json = eval { to_json($sync) };
	if ( $@ ) {
		$log->warn( "Unable to sync up: $@" );
		return;
	}
	
	$prefs->set( snLastSyncUp => time() );
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_syncUp_done,
		\&_syncUp_error,
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
	
	main::INFOLOG && $log->info( 'Sync OK' );
}

sub _syncUp_error {
	my $http   = shift;
	my $error  = $http->error;
	my $client = $http->params('client');
	
	if ( $client ) {
		$prefs->client($client)->set( snLastSyncUp => -1 );
	}
	else {
		$prefs->set( snLastSyncUp => -1 );
	}
	
	$log->warn( "Sync Up failed: $error" );
}

1;
