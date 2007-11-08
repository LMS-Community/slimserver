package Slim::Networking::SqueezeNetwork::Stats;

# $Id$

# Report radio stats to SN if enabled.

use strict;

use JSON::XS qw(to_json from_json);

use Slim::Control::Request;
use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $log   = logger('network.squeezenetwork');
my $prefs = preferences('server');

# Regex for which URLs we want to report stats for
my $REPORT_RE = qr{^(?:http|mms)://};

# Report stats at this interval
my $REPORT_INTERVAL = 3600;

sub init {
	$log->info( "SqueezeNetwork stats init" );
	
	# Subscribe to new song events
	Slim::Control::Request::subscribe(
		\&newsongCallback, 
		[['playlist'], ['newsong']],
	);
	
	# Report stats once an hour
	Slim::Utils::Timers::setTimer(
		undef,
		time() + $REPORT_INTERVAL,
		\&reportStats,
	);
}

sub shutdown {
	$log->info( "SqueezeNetwork stats shutdown" );
	
	# Unsubscribe
	Slim::Control::Request::unsubscribe( \&newsongCallback );
}

sub newsongCallback {
	my $request = shift;
	my $client  = $request->client() || return;
	my $idx     = $request->getParam('_p3');
	
	# mp3 streams report newsong on every metadata change, so we want to ignore that
	return if !defined $idx;
	
	# Check if stats are disabled
	return if $prefs->get('sn_disable_stats');
	
	# If synced, only listen to the master
	if ( Slim::Player::Sync::isSynced($client) ) {
		return unless Slim::Player::Sync::isMaster($client);
	}
	
	my $url = Slim::Player::Playlist::url( $client, $idx );
	
	# Make sure the URL matches what we want to report
	return unless $url =~ $REPORT_RE;
	
	my $track = Slim::Schema->objectForUrl( { url => $url } );
	
	$log->debug( "Reporting play of radio URL to SN: $url" );
	
	my $queue = $prefs->get('sn_stats_queue') || [];
	
	push @{$queue}, {
		player  => $client->id,
		ts      => time() + $prefs->get('sn_timediff'),
		url     => $url,
		secs    => $track->secs,
	};
	
	$prefs->set( sn_stats_queue => $queue );
}

sub reportStats {
	my $queue = $prefs->get('sn_stats_queue') || [];
	
	if ( scalar @{$queue} ) {
		my $client = Slim::Player::Client::clientRandom();
		
		if ( defined $client ) {
			if ( $log->is_debug ) {
				$log->debug( 'Reporting stats queue to SN: ' . Data::Dump::dump($queue) );
			}
			
			# Clear the stats queue so we don't lose anything during submit
			$prefs->set( sn_stats_queue => [] );
		
			my $http = Slim::Networking::SqueezeNetwork->new(
				\&_reportStats_done,
				\&_reportStats_error,
				{
					client => $client,
					queue  => $queue,
				},
			);
			
			my $json = eval { to_json($queue) };
			if ( $@ ) {
				$log->error( "Unable to render stats queue as JSON: $@" );
			}
			else {
				$http->post( $http->url( '/api/v1/stats/submit' ), $json );
			}
		}
		else {
			$log->debug( 'Skipping stats reporting, no client connected' );
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
	
	$log->debug( 'Stats reported OK' );
}

sub _reportStats_error {
	my $http     = shift;
	my $error    = $http->error;
	my $tmpqueue = $http->params('queue');

	$log->error( "Stats reporting failed: $error" );
	
	# Add the queue back so it will retry later
	my $queue = $prefs->get('sn_stats_queue') || [];
	
	unshift @{$queue}, @{$tmpqueue};
	
	$prefs->set( sn_stats_queue => $queue );
}

1;