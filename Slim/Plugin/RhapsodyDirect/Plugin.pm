package Slim::Plugin::RhapsodyDirect::Plugin;

# $Id$

# Browse Rhapsody Direct via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Networking::SqueezeNetwork;
use Slim::Plugin::RhapsodyDirect::ProtocolHandler;
use Slim::Plugin::RhapsodyDirect::RPDS ();

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.rhapsodydirect',
	'defaultLevel' => $ENV{RHAPSODY_DEV} ? 'DEBUG' : 'WARN',
	'description'  => 'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME',
});

my $FEED = Slim::Networking::SqueezeNetwork->url( '/api/rhapsody/opml' );
my $cli_next;

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		rhapd => 'Slim::Plugin::RhapsodyDirect::ProtocolHandler'
	);
	
	Slim::Networking::Slimproto::addHandler( 
		RPDS => \&Slim::Plugin::RhapsodyDirect::RPDS::rpds_handler
	);
	
	# XXX: CLI support

	$class->SUPER::initPlugin();
}

sub getDisplayName () {
	return 'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME';
}

sub setMode {
	my ( $class, $client, $method ) = @_;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header   => 'PLUGIN_RHAPSODY_DIRECT_LOGGING_IN',
		modeName => 'Rhapsody Direect Plugin',
		url      => $FEED,
		title    => $client->string(getDisplayName()),
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam( 'handledTransition', 1 );
}

sub handleError {
	my ( $error, $client ) = @_;
	
	$log->debug("Error during request: $error");
	
	# Strip long number string from front of error
	$error =~ s/\d+( : )?//;
	
	# Allow status updates again
	$client->suppressStatus(0);
	
	# XXX: Need to give error feedback for web requests

	if ( $client ) {
		$client->unblock;
		
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Choice', {
			header  => '{PLUGIN_RHAPSODY_DIRECT_ERROR}',
			listRef => [ $error ],
		} );
		
		if ( $ENV{SLIM_SERVICE} ) {
		    logError( $client, $error );
		}
	}
}

# XXX: CLI/Web support

1;