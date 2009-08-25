package Slim::Plugin::Sounds::Plugin;

# $Id$

# Browse Sounds & Effects

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Formats::XML;
use Slim::Networking::SqueezeNetwork;
use Slim::Player::ProtocolHandlers;
use Slim::Plugin::Sounds::ProtocolHandler;
use Slim::Utils::Log;

# Flat list of sounds to use for alarms
my $alarmPlaylists;

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		loop => 'Slim::Plugin::Sounds::ProtocolHandler'
	);

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url( '/api/sounds/v1/opml' ),
		tag    => 'sounds',
		menu   => 'plugins',
		is_app => 1,
	);
	
	# Cache list of sounds for alarm
	Slim::Formats::XML->getFeedAsync( 
		\&_gotSounds,
		\&_gotSoundsError,
		{
			url   => $class->feed,
			no_sn => 1, # tell XML code to not bother with an SN session
		},
	);
}

sub getDisplayName {
	return 'PLUGIN_SOUNDS_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

# Called by Slim::Utils::Alarm to get the playlists that should be presented as options
# for an alarm playlist.
sub getAlarmPlaylists {
	return $alarmPlaylists;
}

sub _gotSounds {
	my ( $feed, $params ) = @_;
	
	$alarmPlaylists = [];

	# Flatten the list
	for my $first ( @{ $feed->{items} } ) {
		my $category = {
			type  => $first->{name},
			items => [],
		};
		
		for my $second ( @{ $first->{items} } ) {
			push @{ $category->{items} }, {
				title => $second->{name},
				url   => $second->{url},
			};
		}
		
		push @{$alarmPlaylists}, $category;
	}
}

sub _gotSoundsError {
	my ( $error, $params ) = @_;
	
	logError( 'Unable to cache Sounds & Effects menu from SN: ' . $error );
	
	# Give up, Sounds won't be available in Alarm menu
	$alarmPlaylists = undef;
}

1;
