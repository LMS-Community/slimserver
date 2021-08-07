# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
package Slim::Player::SLIMP3;

use base qw(Slim::Player::Player);

use strict;

use Slim::Player::Player;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

my $log = logger('network.protocol.slimp3');

our $SLIMP3Connected = 0;

our $defaultPrefs = {
	bufferThreshold => 40,	# KB
};

sub new {
	my $class    = shift;
	my $id       = shift;
	my $paddr    = shift;
	my $revision = shift;
	my $udpsock  = shift;
	
	my $client = $class->SUPER::new($id, $paddr, $revision);

	# defined only for Slimp3
	$client->udpsock($udpsock);

	# Turn on readUDP in the select loop.
	$SLIMP3Connected = 1;

	# dsully - Mon Mar 21 20:17:44 PST 2005
	# Load these modules on the fly to save approx 700k of memory.
	for my $module (qw(Slim::Hardware::mas3507d Slim::Networking::SliMP3::Stream Slim::Display::Text)) {

		main::INFOLOG && $log->info("Loading module: $module");

		Slim::bootstrap::tryModuleLoad($module);

		if ($@) {
			logBacktrace("Couldn't load module: $module for SLIMP3: [$@] - THIS IS FATAL!");
			$@ = '';
		}
	}

	$client->display ( Slim::Display::Text->new($client) );

	return $client;
}

sub initPrefs {
	my $client = shift;

	$prefs->client($client)->init($defaultPrefs);

	$client->SUPER::initPrefs();
}

sub connected {
	return 1;
}

sub model {
	return 'slimp3';
}

sub modelName { 'SLIMP3' }

sub type {
	return 'player';
}

sub ticspersec {
	return 625000;
}

sub decoder {
	return 'mas3507d';
}

sub hasIR { 1 }

sub nextChunk {
	my $client = $_[0];
	
	my $chunk = Slim::Player::Source::nextChunk(@_);
	
	if (defined($chunk) && length($$chunk) == 0) {
		# EndOfStream
		$client->controller()->playerEndOfStream($client);
		
		# Bug 10400 - need to tell the controller to get next track ready
		# We may not actually be prepared to stream the next track yet 
		# but this will be checked when the controller calls isReadyToStream()
		$client->controller()->playerReadyToStream($client);
		
		if ($client->isSynced(1)) {
			return $chunk;	# playout
		} else {
			return undef;
		}
	}
	
	return $chunk;
}

sub underrun {
	my $client = $_[0];
	
	if (Slim::Networking::SliMP3::Stream::isPlaying($client)) {
		if ($client->controller()->isStreaming()) {
			$client->controller()->playerOutputUnderrun($client);
			return;
		} else {
			# Finished playout
			# and fall
		}	
	}
	Slim::Networking::SliMP3::Stream::stop($client);
	$client->controller()->playerStopped($client);	
}

sub autostart {
	my $client = $_[0];
	$client->controller()->playerTrackStarted($client);
}

sub heartbeat {
	my $client = $_[0];
	
	if ( !$client->bufferReady() && $client->bytesReceivedOffset() 		# may need to signal track-start
		&& ($client->bytesReceived() - $client->bytesReceivedOffset() - $client->bufferFullness() > 0) )
	{
		$client->bufferReady(1);	# to stop multiple starts 
		$client->controller()->playerTrackStarted($client);
	} else {
		$client->controller->playerStatusHeartbeat($client);
	}
}

sub isReadyToStream {
	my ($client, $song) = @_;
	
	return 1 if $client->readyToStream();
	
	return 0 if $client->isSynced(1);
	
	return 1; # assume safe to stream one file after another, even if frame rates different
}

sub play {
	my $client = shift;
	my $params = shift;
	
	if (Slim::Networking::SliMP3::Stream::isPlaying($client)) {
		assert(!$client->isSynced(1));
		
		$client->bytesReceivedOffset($client->streamBytes());
		$client->bufferReady(0);
		
		return 1;
	}
	
	$client->bytesReceivedOffset(0);
	$client->streamBytes(0);
		
	# make sure volume is set, without changing temp setting
	$client->volume($client->volume(),
					defined($client->tempVolume()));

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

	if ( $params->{'controller'}->streamUrlHandler()->isRemote() ) {	
		$client->buffering(bufferSize() / 2);
	}

	Slim::Networking::SliMP3::Stream::newStream($client, $params->{'paused'});
	
	return 1;
}

#
# tell the client to unpause the decoder
#
sub resume {
	my $client = shift;
	# make sure volume is set, without changing temp setting
	$client->volume($client->volume(), defined($client->tempVolume()));

	Slim::Networking::SliMP3::Stream::unpause($client);
	$client->SUPER::resume();
	return 1;
}

sub startAt {
	my ($client, $at) = @_;

	# make sure volume is set, without changing temp setting
	$client->volume($client->volume(), defined($client->tempVolume()));

	Slim::Networking::SliMP3::Stream::unpause($client, $at - $client->packetLatency());
	return 1;
}

sub packetLatency {
	my $client = shift;
	return (
		Slim::Networking::SliMP3::Stream::getMedianLatencyMicroSeconds($client) / 1000000
		||
		$client->SUPER::packetLatency()
	);
}

#
# pause
#
sub pause {
	my $client = shift;

	Slim::Networking::SliMP3::Stream::pause($client);

	$client->SUPER::pause();

	return 1;
}

#
# pauseForInterval
#
sub pauseForInterval {
	my $client   = shift;
	my $interval = shift;

	return Slim::Networking::SliMP3::Stream::pause($client, $interval);
}

#
# does the same thing as pause
#
sub stop {
	my $client = shift;

	Slim::Networking::SliMP3::Stream::stop($client);
	$client->SUPER::stop();
	
}

sub bufferFullness {
	my $client = shift;

	return Slim::Networking::SliMP3::Stream::fullness($client);
}

sub bufferSize {
	return 131072;
}

sub formats {
	return ('mp3');
}

sub vfd {
	my $client = shift;
	my $data = shift;

	my $frame;
	assert($client->udpsock);
	$frame = 'l                 '.$data;
	send($client->udpsock, $frame, 0, $client->paddr()); 
}

sub udpstream {
	my ($client, $controlcode, $wptr, $seq, $chunk) = @_;
		        
	my $frame = pack 'aCxxxxn xxn xxxxxx', (
		'm',                            # 'm' == mp3 data
		$controlcode,                   # control code   
		$wptr,                          # wptr
		$seq);

        
	$frame .= $chunk;
        
	send($client->udpsock, $frame, 0, $client->paddr());
}

sub i2c {
	my ($client, $data) = @_;

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(sprintf("sending [%d] bytes", length($data)));
	}

	send($client->udpsock, '2                 '.$data, 0, $client->paddr);
}

sub volume {
	my $client = shift;
	my $newvolume = shift;

	my $volume = $client->SUPER::volume($newvolume, @_);

	if (defined($newvolume)) {
		# volume squared seems to correlate better with the linear scale.  
		# I'm sure there's something optimal, but this is better.
	
		my $level = sprintf('%05X', 0x80000 * (($volume / $client->maxVolume) ** 2));
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug($client->id() . " volume: newvolume=$newvolume volume=$volume level=$level");
		}
		
		$client->i2c(
			 Slim::Hardware::mas3507d::masWrite('ll', $level)
			.Slim::Hardware::mas3507d::masWrite('rr', $level)
		);
	}

	return $volume;
}

sub bass {
	my $client = shift;
	my $newbass = shift;
	my $bass = $client->SUPER::bass($newbass);

	$client->i2c( Slim::Hardware::mas3507d::masWrite('bass', Slim::Hardware::mas3507d::getToneCode($bass,'bass'))) if (defined($newbass));

	return $bass;
}

sub treble {
	my $client = shift;
	my $newtreble = shift;
	my $treble = $client->SUPER::treble($newtreble);

	$client->i2c( Slim::Hardware::mas3507d::masWrite('treble', Slim::Hardware::mas3507d::getToneCode($treble,'treble'))) if (defined($newtreble));

	return $treble;
}


1;
