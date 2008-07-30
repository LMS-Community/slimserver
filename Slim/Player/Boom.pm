package Slim::Player::Boom;

# SqueezeCenter Copyright (c) 2001-2008 Logitech.
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
	if ( main::SLIM_SERVICE ) {
		require SDI::Service::Player::SqueezeNetworkClient;
		push @ISA, qw(SDI::Service::Player::SqueezeNetworkClient);
	}
	else {
		require Slim::Player::Squeezebox2;
		push @ISA, qw(Slim::Player::Squeezebox2);
	}
}

use Slim::Player::ProtocolHandlers;
use Slim::Player::Transporter;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::DateTime;
use Slim::Hardware::BacklightLED;

my $prefs = preferences('server');

my $LED_ALL = 0xFFFF;
my $LED_POWER = 0x0200;

our $defaultPrefs = {
	'analogOutMode'        => 1,      # default sub-out
	'bass'                 => 0,
	'treble'               => 0,
	'stereoxl'             => minXL(),
	'menuItem'             => [qw(
		NOW_PLAYING
		BROWSE_MUSIC
		RADIO
		MUSIC_SERVICES
		FAVORITES
		PLUGIN_LINE_IN
		PLUGINS
		ALARM
		SETTINGS
		SQUEEZENETWORK_CONNECT
	)],
	'titleFormatCurr'      => 4,
};

if ( main::SLIM_SERVICE ) {
	$defaultPrefs->{menuItem} = [ qw(
		NOW_PLAYING
		MY_MUSIC
		RADIO
		MUSIC_SERVICES
		FAVORITES
		PLUGIN_LINE_IN
		PLUGINS
		ALARM
		SETTINGS
		SQUEEZENETWORK_CONNECT
	) ];
}

sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);

	return $client;
}


sub welcomeScreen {
	my $client = shift;

	$client->showBriefly( {
		'line' => [ '', '0' ],
		'fonts' => {
				'graphic-160x32' => { 'line' => [ 'standard_n.1', 'logoSB2.2' ] },
			},
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
		totalVolumeRange => -74,   # dB
		stepPoint        => 25,    # Number of steps, up from the bottom, where a 2nd volume ramp kicks in.
		stepFraction     => .5     # fraction of totalVolumeRange where alternate volume ramp kicks in.
	};
	return $params;
}

sub init {
	my $client = shift;

	Slim::Control::Request::addDispatch(['boomdac', '_command'], [1, 0, 0, \&Slim::Player::Boom::boomI2C]);
	Slim::Control::Request::addDispatch(['boombright', 
					     '_bkk', '_gcp1', '_gcp2', '_bk2',
					     '_filament_v', '_filament_p',
					     '_annode_v',   '_anode_p',
					    ],
					    [1, 0, 0, \&Slim::Player::Boom::boomBright]);

	$client->SUPER::init();
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

sub hasFrontPanel {
	return 1;
}

sub hasDigitalOut {
	return 0;
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

	setRTCTime( $client);
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
			logger('player.source')->info("Setting LineIn to 0 for [$url]");
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
	
		$log->info("Got source: url: [$input]");

		if ($INC{'Slim/Plugin/LineIn/Plugin.pm'}) {

			$input = Slim::Plugin::LineIn::Plugin::valueForSourceName($input);
		}
	}

	$log->info("Switching to line in $input");

	$prefs->client($client)->set('lineIn', $input);
	$client->sendFrame('audp', \pack('C', $input));
}

sub setRTCTime {
	my $client = shift;
	my $data;

	# According to Michael there is a player specific date format, but I was not able
	#  to test this as I don't know where to set it via web interface
	my $dateTimeFormat = preferences('plugin.datetime')->client($client)->get('timeformat');
	if (!defined $dateTimeFormat ||  $dateTimeFormat eq "") {
		# Try the date time screensaver date format, if set differently from system wide setting
		$dateTimeFormat = preferences('plugin.datetime')->get('timeformat');
	}
	if (!defined $dateTimeFormat ||  $dateTimeFormat eq "") {
		# If all else fails, use system wide date format setting
		$dateTimeFormat = $prefs->get('timeFormat');
	}

	# Set 12h / 24h display mode accordingly
	# Internal RTC format must always be set to 24h mode (bit 1)
	# Display format is stored in SC0 (bit 2) (meaning: 0 = 12h mode, 1 = 24h mode)
	$data = pack( 'C', 0x00); 	# Status register 1
	# 12h mode
	if( $dateTimeFormat =~ /%p/) {
		$data .= pack( 'C', 0b00000010);	# Reset SC0 (=display format 12h), keep internal format at 24h mode
	# 24h mode
	} else {
		$data .= pack( 'C', 0b00000110);	# Set SC0 (=display format 24h), keep internal format at 24h mode
	}
	$client->sendFrame( 'rtcs', \$data);

	# Sync actual time in RTC
	my ($sec, $min, $hour);
	
	if ( main::SLIM_SERVICE ) {
		# Adjust for the user's timezone
		my $timezone = $prefs->client($client)->get('timezone') 
			|| $client->playerData->userid->timezone 
			|| 'America/Los_Angeles';

		my $dt = DateTime->now( 
			time_zone => $timezone
		);
		
		$sec  = $dt->sec;
		$min  = $dt->min;
		$hour = $dt->hour;
	}
	else {
		($sec, $min, $hour) = (localtime())[0..2];
	}
	
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
	# 0 = headphone (i.e. internal speakers off), 1 = sub 
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

	print "$treble, $bass\n";
	sendBDACFrame($client, 'DACI2CGEN', $i2cData);
}
sub sendBDACFrame {
	my ($client, $type, $data) = @_;

	use bytes;

	my $log = logger('player.firmware');

	my $buf = undef; 

	if ($type eq 'DACRESET') {

		$log->info("Sending BDAC DAC RESET");

		$buf = pack('C',0);

	} elsif($type eq 'DACI2CDATA') {
		my $length = length($data)/9;

		$log->debug("Sending BDAC DAC I2C DATA $length chunks");

		$buf = pack('C',1).pack('C',$length).$data;

	} elsif($type eq 'DACI2CDATAEND') {

		$log->info("Sending BDAC DAC I2C DATA COMPLETE");

		$buf = pack('C',2);

	} elsif($type eq 'DACDEFAULT') {

		$log->info("Sending BDAC DAC DEFAULT");

		$buf = pack('C',3);

	} elsif($type eq 'DACI2CGEN') {
		my $length = length($data);

		$log->info("Sending BDAC I2C GENERAL DATA $length chunks");

		$buf = pack('C',4).pack('C',$length).$data;
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

	$log->info("Updating DAC: Sending $size bytes");

	eval {
		while ($bytesread = read(FS, my $buf, 36)) {

			assert(length($buf) == $bytesread);

			$client->sendBDACFrame('DACI2CDATA',$buf);

			$totalbytesread += $bytesread;

			$log->debug("Updating DAC: $totalbytesread / $size bytes");
	
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

		$log->info("Updating DAC: Restore default image");

		$client->showBriefly({
			'line'    => [ undef, $client->string("UPDATE_DSP_FAILURE_RESTORE")],
			'overlay' => [ undef, undef ],
		});

		return 0;
	}else {

		$client->sendBDACFrame('DACI2CDATAEND');
		$client->unblock();

		$log->info("Updating DAC: successfully completed");
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
	
	$log->debug($msg);
	
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

1;

__END__
