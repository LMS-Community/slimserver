package Slim::Player::Boom;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Player::Squeezebox2);

use Slim::Player::ProtocolHandlers;
use Slim::Player::Transporter;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

our $defaultPrefs = {
	'analogOutMode'        => 1,      # default sub-out
	'menuItem'             => [qw(
		NOW_PLAYING
		BROWSE_MUSIC
		RADIO
		MUSIC_SERVICES
		FAVORITES
		PLUGINS
		ALARM
		SETTINGS
		SQUEEZENETWORK_CONNECT
	)],
};


sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);

	return $client;
}

sub init {
	my $client = shift;

	# make sure any preferences unique to this client may not have set are set to the default
	$prefs->client($client)->init($defaultPrefs);

	$client->SUPER::init();
}


sub model {
	return 'boom';
}

sub hasFrontPanel {
	return 1;
}

sub hasDigitalOut {
	return 0;
}

sub hasPowerControl {
	return 0;
}

sub reconnect {
	my $client = shift;

	$client->SUPER::reconnect(@_);

	setRTCTime( $client);
}

sub setRTCTime {
	my $client = shift;
	my $data;

	# Set 12h / 24h display mode according to SC setting
	# Internal IC format must always be set to 24h mode (bit 1)
	# Display format is stored in SC0 (bit 2) (meaning: 0 = 12h mode, 1 = 24h mode)
	$data = pack( 'C', 0x00); 	# Status register 1
	# 12h mode
	if( $prefs->get('timeFormat') =~ /%p/) {
		$data .= pack( 'C', 0b00000010);	# Reset SC0 (=display format 12h), keep internal format at 24h mode
	# 24h mode
	} else {
		$data .= pack( 'C', 0b00000110);	# Set SC0 (=display format 24h), keep internal format at 24h mode
	}
	$client->sendFrame( 'rtcs', \$data);

	# Sync actual time in RTC
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	my $h_10 = int( $hour / 10);
	my $h_1 = $hour % 10;
	my $m_10 = int( $min / 10);
	my $m_1 = $min % 10;
	my $s_10 = int( $sec / 10);
	my $s_1 = $sec % 10;
	my $hhh = $h_10 * 16 + $h_1;
	my $mmm = $m_10 * 16 + $m_1;
	my $sss = $s_10 * 16 + $s_1;

	$data = pack( 'C', 0x03);	# Time register 2
	$data .= pack( 'C', $hhh);
	$data .= pack( 'C', $mmm);
	$data .= pack( 'C', $sss);
	$client->sendFrame( 'rtcs', \$data);
}

sub setAnalogOutMode {
	my $client = shift;
	
	my $data = pack('C', $prefs->client($client)->get('analogOutMode'));	# 0 = headphone (i.e. internal speakers off), 1 = sub out
	$client->sendFrame('audo', \$data);
}

1;

__END__
