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
use base qw(Slim::Player::Squeezebox2);

use Slim::Player::ProtocolHandlers;
use Slim::Player::Transporter;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Hardware::BacklightLED;

my $prefs = preferences('server');

my $LED_ALL = 0xFFFF;
my $LED_POWER = 0x0200;

our $defaultPrefs = {
	'analogOutMode'        => 1,      # default sub-out
	'bass'                 => 0,
	'treble'               => 0,
	'stereoxl'             => 0,
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

	Slim::Control::Request::addDispatch(['boomdac', '_command'], [1, 0, 0, \&Slim::Player::Boom::boomI2C]);

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

sub maxTreble {	return 100; }
sub minTreble {	return -100; }

sub maxBass {	return 100; }
sub minBass {	return -100; }

sub maxXL {	return 10; }
sub minXL {	return -90; }

sub stereoXL {
	return 0;
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

sub power {
	my $client = shift;
	my $on = $_[0];
	my $currOn = $prefs->client( $client)->get( 'power') || 0;

	if( defined( $on) && (!defined(Slim::Buttons::Common::mode($client)) || ($currOn != $on))) {
		if( $on == 1) {
			Slim::Hardware::BacklightLED::setBacklightLED( $client, $LED_ALL);
		} else {
			Slim::Hardware::BacklightLED::setBacklightLED( $client, $LED_POWER);
		}
	}
	return $client->SUPER::power(@_);
}

sub setRTCTime {
	my $client = shift;
	my $data;

	# According to Michael there is a player specific date format, but I was not able
	#  to test this as I don't know where to set it via web interface
	my $dateTimeFormat = preferences('plugin.datetime')->client($client)->get('timeformat');
	if( $dateTimeFormat eq "") {
		# Try the date time screensaver date format, if set differently from system wide setting
		$dateTimeFormat = preferences('plugin.datetime')->get('timeformat');
	}
	if( $dateTimeFormat eq "") {
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
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	my $h_10 = int( $hour / 10);
	my $h_1 = $hour % 10;
	my $m_10 = int( $min / 10);
	my $m_1 = $min % 10;
	my $s_10 = int( $sec / 10);
	my $s_1 = $sec % 10;
	my $hhhBCD = $h_10 * 16 + $h_1;
	my $mmmBCD = $m_10 * 16 + $m_1;
	my $sssBCD = $s_10 * 16 + $s_1;

	$data = pack( 'C', 0x03);	# Set time (hours, minutes and seconds)
	$data .= pack( 'C', $hhhBCD);
	$data .= pack( 'C', $mmmBCD);
	$data .= pack( 'C', $sssBCD);
	$client->sendFrame( 'rtcs', \$data);
}

# TODO: Sync alarm time whenever needed (i.e. when user changes alarm in SC, ...)
sub setRTCAlarm {
	my $client = shift;

#	Sample how to set alarm
#	- Alarm time needs to be set always in 24h mode
#	- Hours and minutes are in BCD format (see setRTCTime)
#	- Setting the MSB (0x80) makes the hour, minute or both active

#	$data = pack( 'C', 0x04);	# Set alarm (hours and minutes)
#	$data .= pack( 'C', $alarmHourBCD | 0x80);
#	$data .= pack( 'C', $alarmMinuteBCD | 0x80);
#	$client->sendFrame( 'rtcs', \$data);


#	Sample how to clear alarm

#	$data = pack( 'C', 0x04);	# Set alarm (hours and minutes)
#	$data .= pack( 'C', 0x00);
#	$data .= pack( 'C', 0x00);
#	$client->sendFrame( 'rtcs', \$data);

}

# Change the analog output mode between headphone and sub-woofer
# If no mode is specified, the value of the client's analogOutMode preference is used.
# Otherwise the mode is temporarily changed to the given value without altering the preference.
sub setAnalogOutMode {
	my $client = shift;
	# 0 = headphone (i.e. internal speakers off), 1 = sub 
	my $mode = shift;

	if ($mode == undef) {
		$mode = $prefs->client($client)->get('analogOutMode');
	}
	
	my $data = pack('C', $mode);
	$client->sendFrame('audo', \$data);
}

sub bass {
	my $client = shift;
	my $newbass = shift;

	my $bass = $client->SUPER::bass($newbass);
	if (defined($newbass)) {
		#do bass bdac code here, then you can remove the warning
		warn "bass adjusted to $newbass";
	}

	return $bass;
}

sub treble {
	my $client = shift;
	my $newtreble = shift;

	my $treble = $client->SUPER::treble($newtreble);
	if (defined($newtreble)) {
		#do treble bdac code here, then you can remove the warning
		warn "treble adjusted to $newtreble";
	}
	return $treble;
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
		my $length = length($data)/8;

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
		$msg .= sprintf("0x%02x ", $d);
	}
	
	$msg .= "]";
	
	$log->debug($msg);
	
	$client->sendFrame('bdac', \$data);
	
	$request->setStatusDone();
}

1;

__END__
