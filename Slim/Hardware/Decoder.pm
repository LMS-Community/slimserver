package Slim::Hardware::Decoder;

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# The two micronas chips have a lot in common wrt volume/tone/balance 
# controls, so all the shared stuff goes here.

use strict;

use Slim::Hardware::mas3507d;
use Slim::Hardware::mas35x9;
use Slim::Utils::Misc;
use Slim::Networking::Stream;



#
# initialize the MAS3507D and tell the client to start a new stream
#

sub reset {
	my $client = shift;
	my $format = shift;

	if ($client->decoder eq 'mas3507d') {

		$client->i2c(
			 Slim::Hardware::mas3507d::masWrite('config','00002')
			.Slim::Hardware::mas3507d::masWrite('loadconfig')
			.Slim::Hardware::mas3507d::masWrite('plloffset48','5d9e9')
			.Slim::Hardware::mas3507d::masWrite('plloffset44','cecf5')
			.Slim::Hardware::mas3507d::masWrite('setpll')
		);

		# sleep for .05 seconds
		# this little kludge is to prevent overflowing cs8900's RX buf because the client
		# is still processing the i2c commands we just sent.
		select(undef,undef,undef,.05);

	} elsif ($client->decoder eq 'mas35x9') {

#		$client->i2c(
#			Slim::Hardware::mas35x9::uncompressed_firmware_init_string()
#		);
		;
	}
	
	# no init necessary for mas35x9; the client does it

}	


sub volume {
	my ($client, $volume) = @_;

	if ($client->decoder eq 'mas3507d') {
		
		# volume squared seems to correlate better with the linear scale.  
		# I'm sure there's something optimal, but this is better.

		my $level = sprintf('%X', 0xFFFFF - 0x7FFFF * ($volume ** 2));

		$client->i2c(
			 Slim::Hardware::mas3507d::masWrite('ll', $level)
			.Slim::Hardware::mas3507d::masWrite('rr', $level)
		);

	} else {

		# really the only way to make everyone happy will be use a combination of digital and analog volume controls as the 
		# default, but then have knobs so you can tune it for max headphone power, lowest noise at low volume, 
		# fixed/variable s/pdif, etc.

		if (1) {
			# here's one way to do it: adjust digital gains, leave fixed 3db boost on the main volume control
			# this does achieve good analog output voltage (important for headphone power) but is not optimal
			# for low volume levels. If only the analog outputs are being used, and digital gain is not required, then 
			# use the other method.
			#
			# When the main volume control is set to +3db (0x7600), there is no clipping at the analog outputs 
			# at max volume, for the loudest 1KHz sine wave I could record.
			#
			# At +12db, the clipping level is around 23/40 (on our thermometer bar).
			#
			# The higher the analog gain is set, the closer it can "match" (3v pk-pk) the max S/PDIF level. 
			# However, at any more than +3db it starts to get noisy, so +3db is the max we should use without 
			# some clever tricks to combine the two gain controls.
			#

			my $level = sprintf('%X', 0xFFFFF - 0x7FFFF * (($volume * 40/40)**2));
			$client->i2c(
				Slim::Hardware::mas35x9::masWrite('out_LL', $level)
				.Slim::Hardware::mas35x9::masWrite('out_RR', $level)
				.Slim::Hardware::mas35x9::masWrite('VOLUME', '7600')
			);

		} else {
			# or: leave the digital controls always at 0db and vary the main volume:
			# much better for the analog outputs, but this does force the S/PDIF level to be fixed.

			print "\$volume: $volume\n";

			my $level = sprintf('%02X00', 0x73 * $volume**2);

			print "level: $level\n";

			$client->i2c(
				Slim::Hardware::mas35x9::masWrite('out_LL',  '80000')
				.Slim::Hardware::mas35x9::masWrite('out_RR', '80000')
				.Slim::Hardware::mas35x9::masWrite('VOLUME', $level)
			);
		}
	}
}

#
# set the MAS3507D treble in the range of -1 to 1
#

sub treble {
	my ($client, $treble) = @_;

	if ($client->decoder eq 'mas3507d') {	
		$client->i2c(
			Slim::Hardware::mas3507d::masWrite('treble',
				Slim::Hardware::mas3507d::getToneCode($treble,'treble')
			)
		);	
#		$client->i2c(
#			Slim::Hardware::mas3507d::masWrite('prefactor', $prefactorCodes{$treble})
#		);	
	} elsif ($client->decoder eq 'mas35x9') {	
		$client->i2c(
			Slim::Hardware::mas35x9::masWrite('TREBLE',
				Slim::Hardware::mas35x9::getToneCode($treble,'treble')
			)
		);	
	} else {
		$::d_control && msg("Unknown decoder " . $client->decoder . " trying to set treble.\n");
		return;
	}
	$::d_control && msg("setting new treble value of $treble\n"); 
}

#
# set the MAS3507D bass in the range of -1 to 1
#

sub bass {
	my ($client, $bass) = @_;
	
	if ($client->decoder eq 'mas3507d') {
		$client->i2c(
			Slim::Hardware::mas3507d::masWrite('bass',
				Slim::Hardware::mas3507d::getToneCode($bass,'bass')
			)
		);	
#		$client->i2c(
#			Slim::Hardware::mas3507d::masWrite('prefactor', $prefactorCodes{$bass})
#		);	
	} elsif ($client->decoder eq 'mas35x9') {
		$client->i2c(
			Slim::Hardware::mas35x9::masWrite('BASS',
				Slim::Hardware::mas35x9::getToneCode($bass,'bass')
			)
		);	
	} else {
		$::d_control && msg("Unknown decoder " . $client->decoder . " trying to set bass.\n");
		return;
	}
	$::d_control && msg("setting new bass value of $bass\n");
}


1;

__END__
