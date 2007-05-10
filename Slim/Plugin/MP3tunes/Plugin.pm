package Slim::Plugin::MP3tunes::Plugin;

# $Id$

# Browse MP3tunes via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Networking::SqueezeNetwork;

my $FEED = Slim::Networking::SqueezeNetwork->url( '/api/mp3tunes/opml' );
my $cli_next;

sub initPlugin {
	my $class = shift;

	# XXX: CLI support

	$class->SUPER::initPlugin();
}

sub getDisplayName () {
	return 'PLUGIN_MP3TUNES_MODULE_NAME';
}

sub setMode {
	my ( $class, $client, $method ) = @_;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header   => 'PLUGIN_MP3TUNES_LOADING',
		modeName => 'MP3Tunes Plugin',
		snLogin  => 1, # Needs SN login/session ID
		url      => $FEED,
		title    => $client->string(getDisplayName()),
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam( 'handledTransition', 1 );
}

# XXX: CLI/Web support

1;