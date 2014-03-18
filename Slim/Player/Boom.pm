package Slim::Player::Boom;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use vars qw(@ISA);

BEGIN {
	require Slim::Player::Squeezebox2;
	push @ISA, qw(Slim::Player::Squeezebox2);
}

use Slim::Hardware::BacklightLED;
use Slim::Networking::Slimproto;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::DateTime;

my $prefs = preferences('server');

my $handlersAdded = 0;

my $LED_ALL = 0xFFFF;
my $LED_POWER = 0x0200;

our $defaultPrefs = {
	'analogOutMode'        => -1,      # flag as not set - let the user decide when he first connects
	'bass'                 => 0,
	'treble'               => 0,
	'stereoxl'             => minXL(),
	'menuItem'             => [qw(
		NOW_PLAYING
		BROWSE_MUSIC
		RADIO
		PLUGIN_MY_APPS_MODULE_NAME
		PLUGIN_APP_GALLERY_MODULE_NAME
		FAVORITES
		GLOBAL_SEARCH
		PLUGIN_LINE_IN
		PLUGINS
		ALARM
		SETTINGS
		SQUEEZENETWORK_CONNECT
	)],
	'lineInAlwaysOn'       => 0, 
	'lineInLevel'          => 50, 
	'minAutoBrightness'    => 2,	# Minimal brightness (automatic brightness mode)
	'sensAutoBrightness'    => 10,	# Sensitivity (automatic brightness mode)
};

$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 0, 'high' => 100 }, 'lineInLevel');
$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 1, 'high' => 7 }, 'minAutoBrightness');
$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 1, 'high' => 20 }, 'sensAutoBrightness');
$prefs->setChange(\&setLineInLevel, 'lineInLevel');
$prefs->setChange( sub { $_[2]->stereoxl($_[1]); }, 'stereoxl');

$prefs->setChange(sub {
	my ($name, $enabled, $client) = @_;
	
	if ($enabled) { $client->setLineIn(1); }
	
	# turn off if line is not playing
	elsif (!Slim::Music::Info::isLineIn(Slim::Player::Playlist::url($client))) {
		$client->setLineIn(0);
	}
	
}, 'lineInAlwaysOn');

$prefs->setChange(sub {
	my ($name, $enabled, $client) = @_;

	my $b = $client->display->brightness();
	# Setting the brightness again loads the brightnessMap with
	#  the correct minimal automatic brightness (offset)
	$client->display->brightness( $b);
}, 'minAutoBrightness');

$prefs->setChange(sub {
	my ($name, $enabled, $client) = @_;

	my $b = $client->display->brightness();
	# Setting the brightness again loads the brightnessMap with
	#  the correct automatic brightness sensitivity (divisor)
	$client->display->brightness( $b);
}, 'sensAutoBrightness');

sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);

	return $client;
}

sub welcomeScreen {
	my $client = shift;

	$client->showBriefly( {
		'center' => [ '', '0' ],
		'fonts' => {
				'graphic-160x32' => { 'center' => [ 'standard_n.1', 'logoSB2.2' ] },
			},
		'jive' => undef,
	}, undef, undef, 1);
}

##
# Special Volume control for Boom.  
# 
# Boom is an oddball because it requires extremes in volume adjustment, from
# dead-of-night-time listening to shower time.  
# Additionally, we want 50% volume to be reasonable
#
# So....  A total dynamic range of 74dB over 100 steps is okay, the problem is how to 
# distribute those steps.  When distributed evenly, center volume is way too quiet.
# So, This algorithm moves what would be 50% (i.e. -76*.5=38dB) and moves it to the 25%
# position.
# 
# This is simply a mapping function from 0-100, with 2 straight lines with different slopes.
#
sub getVolumeParameters
{
	my $params = 
	{
		totalVolumeRange => -74,       # dB
		stepPoint        => 25,        # Number of steps, up from the bottom, where a 2nd volume ramp kicks in.
		stepFraction     => .5,        # fraction of totalVolumeRange where alternate volume ramp kicks in.
	};
	return $params;
}

sub getLineInVolumeParameters
{
	my $params = 
	{
		totalVolumeRange => -74,       # dB
		stepPoint        => 25,        # Number of steps, up from the bottom, where a 2nd volume ramp kicks in.
		stepFraction     => .5,        # fraction of totalVolumeRange where alternate volume ramp kicks in.
		maximumVolume    => 24         # + 24 dB
	};
	return $params;
}

sub init {
	my $client = shift;

	if (!$handlersAdded) {

		# Add a handler for line-in/out status changes
		Slim::Networking::Slimproto::addHandler( LIOS => \&lineInOutStatus );
	
		# Create a new event for sending LIOS updates
		Slim::Control::Request::addDispatch(
			['lios', '_state'],
			[1, 0, 0, undef],
		   );
		
		Slim::Control::Request::addDispatch(
			['lios', 'linein', '_state'],
			[1, 0, 0, undef],
		   );
		
		Slim::Control::Request::addDispatch(
			['lios', 'lineout', '_state'],
			[1, 0, 0, undef],
		   );
		
		Slim::Control::Request::addDispatch(
			['boomdac', '_command'],
			[1, 0, 0, \&Slim::Player::Boom::boomI2C]
		   );

		Slim::Control::Request::addDispatch(
			['boombright', '_bkk', '_gcp1', '_gcp2', '_bk2', '_filament_v', '_filament_p', '_annode_v', '_anode_p' ],
			[1, 0, 0, \&Slim::Player::Boom::boomBright]
		   );
		
		$handlersAdded = 1;

	}

	$client->SUPER::init(@_);
}

sub initPrefs {
	my $client = shift;

	# make sure any preferences unique to this client may not have set are set to the default
	$prefs->client($client)->init($defaultPrefs);

	$client->SUPER::initPrefs();
}

sub model {
	return 'boom';
}

sub modelName {
	return 'Squeezebox Boom';
}

sub hasFrontPanel {
	return 1;
}

sub hasDisableDac {
	return 0;
}

sub hasDigitalOut {
	return 0;
}

sub hasHeadSubOut() {
	return 1;
}

sub hasPowerControl {
	return 0;
}

sub hasRTCAlarm {
	return 1;
}

sub hasLineIn {
	return 1;
}

# SN only, this checks that the player's firmware version supports compression
sub hasCompression { 1 }

# Do we have support for client-side scrolling?
sub hasScrolling {
	return shift->revision >= 55;
}


sub maxTreble {	return 23; }
sub minTreble {	return -23; }

sub maxBass {	return 23; }
sub minBass {	return -23; }

sub toneI2CAddress { return 55; }

sub maxXL {	return 3; }
sub minXL {	return 0; }

sub stereoxl {
	my $client = shift;
	my $newvalue = shift;

	my $StereoXL = $client->_mixerPrefs('stereoxl', 'maxXL', 'minXL', $newvalue);
	my $depth_db;
	if ($StereoXL == 0) {
		$depth_db = 'off';
	} elsif ($StereoXL == 1) {
		$depth_db = -6;
	} elsif ($StereoXL == 2) {
		$depth_db = 0; 
	} elsif ($StereoXL == 3) {
		$depth_db = 6; 
	} else {
		$depth_db = 'off';
		logger('player.streaming.direct')->warn("Invalid stereoXL setting ($StereoXL)");
	}
	if (defined($newvalue)) {
		my $depth = 0;
		if ($depth_db eq 'off') {
			$depth = 0;
		} else {
			$depth = 10.0**($depth_db/20.0);
		}
		my $depth_int  = (int(($depth  * 0x00800000)+0.5)) & 0xFFFFFFFF ;
		my $depth_int_ = (-int(($depth * 0x00800000)+0.5)) & 0xFFFFFFFF ;
		my $stereoxl_i2c_address = 41;
		my $i2cData = pack("CNNNN", $stereoxl_i2c_address, $depth_int, $depth_int_, 0, 0);
		# print "len = " . length ($i2cData) . "\n";
		# printf ("$stereoxl_i2c_address, %08x, %08x \n", $depth_int, $depth_int_);
		sendBDACFrame($client, 'DACI2CGEN', $i2cData);
	}

	return $StereoXL;
}

sub reconnect {
	my $client = shift;

	$client->SUPER::reconnect(@_);

	my $on = $prefs->client( $client)->get( 'power') || 0;
	if( $on == 1) {
		Slim::Hardware::BacklightLED::setBacklightLED( $client, $LED_ALL);
	} else {
		Slim::Hardware::BacklightLED::setBacklightLED( $client, $LED_POWER);
	}

	setRTCTime( $client );
	# Uncommenting the following will modify the woofer bass extension table.  This is a map that maps 
	# volume (in 16.16 format) to a biquad index. Index 0 provides the most bass extension, index 9 
	# provides the least.
	# sendBDACFrame($client, 'DACWOOFERBQ',[   658,   980, 1729, 2816, 5120, 8960, 14848, 26368, 0x8fffffff]);  # <--default built into firmware.
	# sendBDACFrame($client, 'DACWOOFERBQ',[   658*2,   980*2, 1729*2, 2816*2, 5120*2, 8960*2, 14848*2, 26368*2, 0x8fffffff]);
	# sendBDACFrame($client, 'DACWOOFERBQ',  [    0,     0,     0,     0,     0,     0,     0,     0,     0]);
	# sendBDACFrame($client, 'DACWOOFERBQ',  [2264,   3526,  5200,  5800, 10200, 15889, 27031,  45000,     0x8FFFFFFF]);
	sendBDACFrame($client, 'DACWOOFERBQ',   [   658,   980, 1729, 2816, 5120, 8960, 0x8fffffff, 0x8fffffff, 0x8fffffff]);
	sendBDACFrame($client, 'DACWOOFERBQSUB',[    0 ,     0,    0,    0,    0,    0,          0, 0x8fffffff, 0x8fffffff]);
	
	# re-initialise some prefs which aren't stored on the player
	sendTone($client, $client->SUPER::bass(), $client->SUPER::treble());
	stereoxl($client, $prefs->client($client)->get('stereoxl'));
	setLineInLevel(undef, $prefs->client($client)->get('lineInLevel'), $client);
}

sub play {
	my ($client, $params) = @_;

	# If the url to play is a source: value, that means the Line In
	# are being used. The LineIn plugin handles setting the audp
	# value for those. If the user then goes and pressed play on a
	# standard file:// or http:// URL, we need to set the value back to 0,
	# IE: input from the network.
	my $url = $params->{'url'};

	if ($url) {
		if (Slim::Music::Info::isLineIn($url)) {
			# The LineIn plugin will handle this, so just return
			return 1;
		}
		else {
			main::INFOLOG && logger('player.source')->info("Setting LineIn to 0 for [$url]");
			$client->setLineIn(0);
		}
	}
	return $client->SUPER::play($params);
}

sub pause {
	my $client = shift;

	$client->SUPER::pause(@_);
	if (Slim::Music::Info::isLineIn(Slim::Player::Playlist::url($client))) {
		$client->setLineIn(0);
	}
}

sub stop {
	my $client = shift;

	$client->SUPER::stop(@_);
	if (Slim::Music::Info::isLineIn(Slim::Player::Playlist::url($client))) {
		$client->setLineIn(0);
	}
}

sub resume {
	my $client = shift;

	$client->SUPER::resume(@_);
	if (Slim::Music::Info::isLineIn(Slim::Player::Playlist::url($client))) {
		$client->setLineIn(Slim::Player::Playlist::url($client));
	}
}

sub power {
	my $client = shift;
	my $on = $_[0];
	my $currOn = $prefs->client( $client)->get( 'power') || 0;

	# Turn led backlight on and off
	if( defined( $on) && (!defined(Slim::Buttons::Common::mode($client)) || ($currOn != $on))) {
		if( $on == 1) {
			Slim::Hardware::BacklightLED::setBacklightLED( $client, $LED_ALL);
		} else {
			Slim::Hardware::BacklightLED::setBacklightLED( $client, $LED_POWER);
		}
	}

	my $result = $client->SUPER::power($on);

	# Start playing line in on power on, if line in was selected before
	if( defined( $on) && (!defined(Slim::Buttons::Common::mode($client)) || ($currOn != $on))) {
		if( $on == 1) {
			if (Slim::Music::Info::isLineIn(Slim::Player::Playlist::url($client))) {
				$client->execute(["play"]);
			}
		}
	}

	return $result;
}

sub setLineIn {
	my $client = shift;
	my $input  = shift;

	my $log    = logger('player.source');

	# convert a source: url to a number, otherwise, just use the number
	if (Slim::Music::Info::isLineIn($input)) {
	
		main::INFOLOG && $log->info("Got source: url: [$input]");

		if ($INC{'Slim/Plugin/LineIn/Plugin.pm'}) {

			$input = Slim::Plugin::LineIn::Plugin::valueForSourceName($input);

			# make sure volume is set, without changing temp setting
			$client->volume( abs($prefs->client($client)->get("volume")), defined($client->tempVolume()));
		}
	}

	# turn off linein if nothing's plugged in
	if (!$client->lineInConnected()) {
		$input = 0;
	}

	# override the input value if the alwaysOn option is set
	elsif ($prefs->client($client)->get('lineInAlwaysOn')) {
		$input = 1;
	}

	main::INFOLOG && $log->info("Switching to line in $input");

	$prefs->client($client)->set('lineIn', $input);
	$client->sendFrame('audp', \pack('C', $input));
}

sub setLineInLevel {
	my $level = $_[1];
	my $client = $_[2];
	
	main::INFOLOG && logger('player.source')->info("Setting line in level to $level");
	
	# map level to volume:
	my $newGain = 0;
	if ($level != 0) {
		my $db = $client->getVolume($level, $client->getLineInVolumeParameters());
		$newGain = $client->dBToFixed($db);
	}
	
	sendBDACFrame($client, 'DACLINEINGAIN', $newGain);
}

sub setRTCTime {
	my $client = shift;
	my $data;

	my $dateTimeFormat = preferences('plugin.datetime')->client($client)->get('timeFormat') || $prefs->get('timeFormat');

	# Set 12h / 24h display mode accordingly; mark time as being valid (i.e. set)
	#
	# Bit 1: Internal RTC format must always be set to 24h mode (0 = 12h mode, 1 = 24h mode)
	# Bit 2: Display format is stored in SC0 (0 = 12h mode, 1 = 24h mode)
	# Bit 3: Set SC1 (bit 3) to mark the time as being valid (i.e. set)
	$data = pack( 'C', 0x00); 	# Status register 1

	# 12h mode
	if( $dateTimeFormat =~ /%p/) {
		# Bit 1: always set (internal RTC format is always 24h)
		# Bit 2: clear for 12h display format
		# Bit 3: set to mark time as being valid (i.e. set)
		$data .= pack( 'C', 0b00001010);
	# 24h mode
	} else {
		# Bit 1: always set (internal RTC format is always 24h)
		# Bit 2: set for 24h display format
		# Bit 3: set to mark time as being valid (i.e. set)
		$data .= pack( 'C', 0b00001110);
	}
	$client->sendFrame( 'rtcs', \$data);

	# Sync actual time in RTC
	my ($sec, $min, $hour) = (localtime())[0..2];
	
	my ($sssBCD, $mmmBCD, $hhhBCD) = Slim::Utils::DateTime::bcdTime($sec, $min, $hour);

	$data = pack( 'C', 0x03);	# Set time (hours, minutes and seconds)
	$data .= pack( 'C', $hhhBCD);
	$data .= pack( 'C', $mmmBCD);
	$data .= pack( 'C', $sssBCD);
	$client->sendFrame( 'rtcs', \$data);
}

# Set the RTC alarm clock to a given time or clear it.
# $time must be in seconds past midnight or undef to clear the alarm
# $time should be adjusted as necessary for local time before being passed to this sub.
# $volume is the volume at which the alarm should sound (0-100)
# Generally called by Slim::Utils::Alarm::scheduleNext
sub setRTCAlarm {
	my $client = shift;
	my $time = shift;
	my $volume = shift;
	
	if (defined $time) {
		# - Alarm time needs to be set always in 24h mode
		# - Hours and minutes are in BCD format (see Slim::Utils::DateTime::bcdTime)
		# - Setting the MSB (0x80) makes the hour, minute or both active

		my ($alarmSecBCD, $alarmMinBCD, $alarmHourBCD) = Slim::Utils::DateTime::bcdTime((gmtime($time))[0..2]);
		my $data = pack( 'C', 0x04);	# Set alarm (hours and minutes)
		$data .= pack( 'C', $alarmHourBCD | 0x80);
		$data .= pack( 'C', $alarmMinBCD | 0x80);
		$client->sendFrame( 'rtcs', \$data);

		# Set alarm volume
		$data = pack( 'C', 0x05);	# Set alarm volume (0 - 100)
		$data .= pack( 'C', $volume);
		$client->sendFrame( 'rtcs', \$data);



 	} else {
		# Clear the alarm
		my $data = pack( 'C', 0x04);	# Set alarm (hours and minutes)
		$data .= pack( 'C', 0x00);
		$data .= pack( 'C', 0x00);
		$client->sendFrame( 'rtcs', \$data);
	}
}

# Change the analog output mode between headphone and sub-woofer
# If no mode is specified, the value of the client's analogOutMode preference is used.
# Otherwise the mode is temporarily changed to the given value without altering the preference.
sub setAnalogOutMode {
	my $client = shift;
	# 0 = headphone (internal speakers off), 1 = sub out,
	# 2 = always on (internal speakers on), 3 = always off
	my $mode = shift;

	if (! defined $mode) {
		$mode = $prefs->client($client)->get('analogOutMode');
	}
	
	my $data = pack('C', $mode);
	$client->sendFrame('audo', \$data);
}

sub bass {
	my $client = shift;
	my $newbass = shift;
	my $bass = $client->SUPER::bass($newbass);
	my $treble = $client->SUPER::treble();

	if (defined($newbass)) {
		sendTone($client, $bass, $treble);
	}

	return $bass;
}

sub treble {
	my $client = shift;
	my $newtreble = shift;

	my $bass = $client->SUPER::bass();
	my $treble = $client->SUPER::treble($newtreble);
	if (defined($newtreble)) {
		sendTone($client, $bass, $treble);
	}
	return $treble;
}

# sendTone
# Both bass and treble must be sent at the same time.
sub sendTone
{
	my ($client, $bass, $treble) = @_;
	$bass = -$bass     - minBass();
	$treble = -$treble - minTreble();
	# Do a little safety checking on the parameters.  It can get really ugly otherwise with 
	# loud scary noises coming out of boom.
	# We should probably send the tone settings in a special packet, rather than 
	# raw I2C.  
	$treble = $treble & 0xff;
	$bass   = $bass   & 0xff;
	if ($treble >47) {
		$treble = 47;
	} 
	if ($treble < 0) {
		$treble = 0;
	}
	if ($bass >47) {
		$bass = 47;
	}
	if ($bass < 0) {
		$bass = 0;
	}
	
	
	my $i2cData = pack("CCCCC", toneI2CAddress(),0,0, $treble, $bass);

	sendBDACFrame($client, 'DACI2CGEN', $i2cData);
}
sub sendBDACFrame {
	my ($client, $type, $data) = @_;

	use bytes;

	my $log = logger('player.firmware');

	my $buf = undef; 

	if ($type eq 'DACRESET') {

		main::INFOLOG && $log->info("Sending BDAC DAC RESET");

		$buf = pack('C',0);

	} elsif($type eq 'DACI2CDATA') {
		my $length = length($data)/9;

		main::DEBUGLOG && $log->debug("Sending BDAC DAC I2C DATA $length chunks");

		$buf = pack('C',1).pack('C',$length).$data;

	} elsif($type eq 'DACI2CDATAEND') {

		main::INFOLOG && $log->info("Sending BDAC DAC I2C DATA COMPLETE");

		$buf = pack('C',2);

	} elsif($type eq 'DACDEFAULT') {

		main::INFOLOG && $log->info("Sending BDAC DAC DEFAULT");

		$buf = pack('C',3);

	} elsif($type eq 'DACI2CGEN') {
		my $length = length($data);

		main::INFOLOG && $log->info("Sending BDAC I2C GENERAL DATA $length chunks");

		$buf = pack('C',4).pack('C',$length).$data;
	} elsif($type eq 'DACALSFLOOD') {
		main::INFOLOG && $log->info("Starting Lightsensor flood");
		$buf = pack('C',5);
	} elsif($type eq 'DACWOOFERBQ') {
		main::INFOLOG && $log->info("Updating the BDAC bass_eq volume table");
		my $count = @$data;
		$buf = pack('C',6).pack('C',$count).pack("N$count", @$data);
	} elsif($type eq 'DACWOOFERBQSUB') {
		main::INFOLOG && $log->info("Updating the BDAC bass_eq volume table for the subwoofer");
		my $count = @$data;
		$buf = pack('C',7).pack('C',$count).pack("N$count", @$data);
	} elsif ($type eq 'DACLINEINGAIN') {
		main::INFOLOG && $log->info("Setting line in gain");
		$buf = pack('C',8).pack('N',$data);
	} 
	
	if (defined $buf) {
		$client->sendFrame('bdac', \$buf);
	}
}

sub upgradeDAC {
	my ($client, $filename) = @_;

	use bytes;

	my $log = logger('player.firmware');

	my $frame;

	# disable visualizer is this mode
	$client->modeParam('visu', [0]);

	# force brightness to dim if off
	if ($client->display->currBrightness() == 0) { $client->display->brightness(1); }

	open FS, $filename || return("Open failed for: $filename\n");

	binmode FS;
	
	my $size = -s $filename;
	
	# place in block mode so that brightness key is now ignored
	$client->block( {
		'line'  => [ $client->string('UPDATING_DSP') ],
		'fonts' => { 
			'graphic-320x32' => 'light',
			'graphic-160x32' => 'light_n',
			'graphic-280x16' => 'small',
			'text'           => 2,
		},
	}, 'upgrade', 1 );
	
	my $bytesread      = 0;
	my $totalbytesread = 0;
	my $lastFraction   = -1;
	my $byteswritten;
	my $bytesleft;

	$client->sendBDACFrame('DACRESET');

	main::INFOLOG && $log->info("Updating DAC: Sending $size bytes");

	eval {
		while ($bytesread = read(FS, my $buf, 36)) {

			assert(length($buf) == $bytesread);

			$client->sendBDACFrame('DACI2CDATA',$buf);

			$totalbytesread += $bytesread;

			main::DEBUGLOG && $log->debug("Updating DAC: $totalbytesread / $size bytes");
	
			my $fraction = $totalbytesread / $size;

			if (($fraction - $lastFraction) > (1/40)) {
	
				$client->showBriefly( {
	
					'line'  => [ $client->string('UPDATING_DSP'),
					         $client->symbols($client->progressBar($client->displayWidth(), $totalbytesread/$size)) ],
	
					'fonts' => { 
						'graphic-320x32' => 'light',
						'graphic-160x32' => 'light_n',
						'graphic-280x16' => 'small',
						'text'           => 2,
					},
					'jive'  => undef,
					'cli'   => undef,
				} );
	
				$lastFraction = $fraction;
			}
		}
	};
	if ($@) {
		$log->error("Updating DAC: Failure: $@");
		$client->sendBDACFrame('DACDEFAULT');
		$client->unblock();

		main::INFOLOG && $log->info("Updating DAC: Restore default image");

		$client->showBriefly({
			'line'    => [ undef, $client->string("UPDATE_DSP_FAILURE_RESTORE")],
			'overlay' => [ undef, undef ],
		});

		return 0;
	}else {

		$client->sendBDACFrame('DACI2CDATAEND');
		$client->unblock();

		main::INFOLOG && $log->info("Updating DAC: successfully completed");
		return 1;
	}
}

# CLI I2C Example:  Set volume
# main volume control is at i2c address 47 (2f)
# Set volume to -20 dB.  0dB == 0x080000
# -20 dB == 0.1 linear.  
# 0x00800000 * 0.1 = 0x000CCCCC
#
# To send this volume command to a player called 'boom' do the following from the CLI:
#     boom boomdac %2f%00%0c%cc%cc    <- -20 dB
#     boom boomdac %2f%00%0c%cc%cc    <- back to 0 dB
sub boomI2C {
	my $request = shift;
	
	my $log = logger('player.firmware');
	
	# get the parameters
	my $client     = $request->client();
	my $i2cbytes   = $request->getParam('_command');

	if (!defined $i2cbytes ) {

		$request->setStatusBadParams();
		return;
	}

	my $data  = pack('C', 0x04);

	$data .= pack('C', length($i2cbytes));
	$data .= $i2cbytes;
	
	my @d = unpack("C*", $data);
	my $msg = "Sending data to i2c bus :[";
	
	foreach my $d (@d) {
		$msg .= sprintf("0x%02x ", ($d & 0xFF));
	}
	
	$msg .= "]";
	
	main::DEBUGLOG && $log->debug($msg);
	
	$client->sendFrame('bdac', \$data);
	
	$request->setStatusDone();
}

#
#  boomBright
#  Control boom brightness.
sub boomBright {
	my $request = shift;

	my $client     = $request->client();
		

	my $log = logger('player.firmware');
	
	# get the parameters

	my $bkk        = $request->getParam('_bkk');
	my $gcp1       = $request->getParam('_gcp1');
	my $gcp2       = $request->getParam('_gcp2');
	my $bk2        = $request->getParam('_bk2');
	my $filament_v = $request->getParam('_filament_v');
	my $filament_p = $request->getParam('_filament_p');
	my $annode_v   = $request->getParam('_annode_v');
	my $anode_p    = $request->getParam('_anode_p');

	if (
		(!defined $bkk) ||
		(!defined $gcp1)   ||
		(!defined $gcp2)||
		(!defined $bk2)||
		(!defined $filament_v)||
		(!defined $filament_p)||
		(!defined $annode_v)||
		(!defined $anode_p))
	    
	{
		$request->setStatusBadParams();
		return;
	}
	

	my $data = pack('CCCCCCCC', $bkk, $gcp1, $gcp2, $bk2, $filament_v, $filament_p, $annode_v, $anode_p);
	
	$client->sendFrame('brir', \$data);
	
	$request->setStatusDone();
}

sub lineInConnected {
	my $state = Slim::Networking::Slimproto::voltage(shift) || return 0;
	return $state & 0x01 || 0;
}

sub lineOutConnected {
	my $state = Slim::Networking::Slimproto::voltage(shift) || return 0;
	return $state & 0x02 || 0;
}

sub lineInOutStatus {
	my ( $client, $data_ref ) = @_;
	
	my $state = unpack 'n', $$data_ref;

	my $oldState = {
		in  => $client->lineInConnected(),
		out => $client->lineOutConnected(),
	};
	
	Slim::Networking::Slimproto::voltage( $client, $state );

	Slim::Control::Request::notifyFromArray( $client, [ 'lios', $state ] );
	
	if ($oldState->{in} != $client->lineInConnected()) {
		Slim::Control::Request::notifyFromArray( $client, [ 'lios', 'linein', $client->lineInConnected() ] );
		if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::LineIn::Plugin')) {
			Slim::Plugin::LineIn::Plugin::lineInItem($client, 1);
		}
	}
	
	if ($oldState->{out} != $client->lineOutConnected()) {

		# ask what out mode to use if user is plugging in for the first time		
		if ($prefs->client( $client)->get( 'analogOutMode' ) == -1) {

			# default to headphone
			$prefs->client( $client)->set( 'analogOutMode', 0 );

			Slim::Buttons::Common::pushModeLeft(
				$client,
				'INPUT.Choice',
				Slim::Buttons::Settings::analogOutMenu()
			);
			
		}
		
		Slim::Control::Request::notifyFromArray( $client, [ 'lios', 'lineout', $client->lineOutConnected() ] );
	}
}

1;

__END__
