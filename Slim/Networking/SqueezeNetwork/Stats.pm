package Slim::Networking::SqueezeNetwork::Stats;

# $Id$

# Report radio stats to SN if enabled.

use strict;

use JSON::XS::VersionOneAndTwo;

use Slim::Control::Request;
use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $log   = logger('network.squeezenetwork');
my $prefs = preferences('server');

# Regex for which URLs we want to report stats for
my $REPORT_RE = qr{^(?:http|mms|live365|loop)://};

# Report stats to SN at this interval
my $REPORT_INTERVAL = 1200;

# Granularity for radio logging
my $REPORT_GRANULARITY = 300;

# Max number of items to upload at a time
# 8K events = ~1M of JSON data, no one should ever hit this unless there's a bug
my $MAX_ITEMS_PER_UPLOAD = 8 * 1024;

sub init {
	my ( $class, $json ) = @_;
	
	# Check if stats are disabled
	return if $prefs->get('sn_disable_stats');
	
	main::INFOLOG && $log->info( "SqueezeNetwork stats init" );
	
	# Override defaults if SN has provided them
	if ( $json->{stats_interval} ) {
		$REPORT_INTERVAL = $json->{stats_interval};
	}
	
	if ( my $regex = $json->{stats_regex} ) {
		$REPORT_RE = qr{^(?:$regex)://};
	}
	
	if ( $json->{stats_granularity} ) {
		$REPORT_GRANULARITY = $json->{stats_granularity};
	}
	
	# Subscribe to new song events
	Slim::Control::Request::subscribe(
		\&newsongCallback, 
		[['playlist'], ['newsong']],
	);
	
	# Report stats now and then once an hour
	Slim::Utils::Timers::setTimer(
		undef,
		time() + 15,
		\&reportStats,
	);
}

sub shutdown {
	main::INFOLOG && $log->info( "SqueezeNetwork stats shutdown" );
	
	# Unsubscribe
	Slim::Control::Request::unsubscribe( \&newsongCallback );
}

sub newsongCallback {
	my $request = shift;
	my $client  = $request->client() || return;
	
	# Check if stats are disabled
	return if $prefs->get('sn_disable_stats');
	
	# If synced, only listen to the master
	if ( $client->isSynced() ) {
		return unless Slim::Player::Sync::isMaster($client);
	}
	
	my $url = Slim::Player::Playlist::url($client);
	
	my $track = Slim::Schema->objectForUrl( { url => $url } );
	
	my $secs = $track->secs || 0;
	
	# If this is a radio track (no track length) and doesn't contain a playlist index value
	# it is the newsong notification from a metadata change, which we want to ignore
	if ( !$secs && !defined $request->getParam('_p3') ) {
		main::DEBUGLOG && $log->debug( 'Ignoring radio station newsong metadata notification' );
		return;
	}
	
	if (!Slim::Music::Info::isRemoteURL($url)) {
		my $id = $track->id;
		
		if ($id > 0) {
			# Make sure the URL matches what we want to report
			$url = 'local://trackId=' . $id;
		} else {
			return;
		}
	} else {
		return unless $url =~ $REPORT_RE;
	}
		
	if ( $secs > 0 ) {
		# A track with known duration, log one event for it
		my $queue = $prefs->get('sn_stats_queue') || [];
	
		push @{$queue}, {
			player  => $client->id,
			ts      => time() + $prefs->get('sn_timediff'),
			url     => $url,
			secs    => $secs,
		};
	
		$prefs->set( sn_stats_queue => $queue );
		
		main::DEBUGLOG && $log->debug( "Reporting play of remote URL to SN: $url, duration: $secs" );
	}
	else {
		# A radio track, log events at 5-minute intervals
		logRadio( $client, $url );
	}
}

sub logRadio {
	my ( $client, $url ) = @_;
	
	# If player is stopped, stop logging
	if ( !$client || $client->isStopped() ) {
		main::DEBUGLOG && $log->debug( "Player no longer playing, finished logging for $url" );
		return;
	}
	
	my $cururl = Slim::Player::Playlist::url($client);
	
	if ( $cururl ne $url ) {
		main::DEBUGLOG && $log->debug( "Currently playing radio URL has changed, finished logging for $url" );
		return;
	}
	
	my $queue = $prefs->get('sn_stats_queue') || [];

	push @{$queue}, {
		player  => $client->id,
		ts      => time() + $prefs->get('sn_timediff'),
		url     => $url,
		secs    => $REPORT_GRANULARITY,
	};

	$prefs->set( sn_stats_queue => $queue );
	
	main::DEBUGLOG && $log->debug( "Reporting play of radio URL to SN: $url, duration: $REPORT_GRANULARITY" );
	
	Slim::Utils::Timers::setTimer(
		$client,
		time() + $REPORT_GRANULARITY,
		\&logRadio,
		$url,
	);
}

sub reportStats {
	my $queue = $prefs->get('sn_stats_queue') || [];

	if ( scalar @{$queue} ) {		
		my $client = Slim::Player::Client::clientRandom();
		
		if ( defined $client ) {
			# Copy no more than max items into tmp array
			my @tmp = splice @{$queue}, 0, $MAX_ITEMS_PER_UPLOAD;			
			$prefs->set( sn_stats_queue => $queue );
			
			if ( main::DEBUGLOG && $log->is_debug ) {
				$log->debug( 'Reporting stats queue to SN: ' . Data::Dump::dump(\@tmp) );
			}
		
			my $http = Slim::Networking::SqueezeNetwork->new(
				\&_reportStats_done,
				\&_reportStats_error,
				{
					client => $client,
					queue  => \@tmp,
				},
			);
			
			my $json = eval { to_json(\@tmp) };
			if ( $@ ) {
				$log->error( "Unable to render stats queue as JSON: $@" );
			}
			else {
				$http->post( $http->url( '/api/v1/stats/submit' ), $json );
			}
		}
		else {
			main::DEBUGLOG && $log->debug( 'Skipping stats reporting, no client connected' );
		}
	}
	
	Slim::Utils::Timers::setTimer(
		undef,
		time() + $REPORT_INTERVAL,
		\&reportStats,
	);
}

sub _reportStats_done {
	my $http = shift;
	
	my $content = eval { from_json( $http->content ) };
	
	if ( $@ || $content->{error} ) {
		$http->error( $@ || $content->{error} );
		return _reportStats_error( $http );
	}
	
	main::DEBUGLOG && $log->debug( 'Stats reported OK' );
}

sub _reportStats_error {
	my $http     = shift;
	my $error    = $http->error;
	my $tmpqueue = $http->params('queue');
	
	$prefs->remove('sn_session');

	$log->error( "Stats reporting failed: $error" );
	
	# Add the queue back so it will retry later
	my $queue = $prefs->get('sn_stats_queue') || [];
	
	unshift @{$queue}, @{$tmpqueue};
	
	$prefs->set( sn_stats_queue => $queue );
}

1;