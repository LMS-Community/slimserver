package Slim::Control::Queries;

# $Id: Command.pm 5121 2005-11-09 17:07:36Z dsully $
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use Scalar::Util qw(blessed);

use Slim::Control::Request;
use Slim::Music::Import;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

sub cursonginfoQuery {
	my $request = shift;
	
	$::d_command && msg("cursonginfoQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['duration', 'artist', 'album', 'title', 'genre', 'path'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	# get the query
	my $method = $request->getRequest();
	my $url = Slim::Player::Playlist::song($client);
	
	if (defined $url) {

		if ($method eq 'path') {
			
			$request->addResult('_p1', $url);
		
		} else {
			
			my $ds = Slim::Music::Info::getCurrentDataStore();
			my $track  = $ds->objectForUrl(Slim::Player::Playlist::song($client));
			
			if (!blessed($track) || !$track->can('secs')) {
				msg("Couldn't fetch object for URL: [$url] - skipping track\n");
				bt();
			} else {
			
				if ($method eq 'duration') {
			
					$request->addResult('_p1', $track->secs() || 0);
				
				} else {
					
					$request->addResult('_p1', $track->$method() || 0);
				}
			}
		}
	}
	
	$request->setStatusDone();
}

sub connectedQuery {
	my $request = shift;
	
	$::d_command && msg("connectedQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['connected'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();
	
	$request->addResult('_p1', $client->connected() || 0);
	
	$request->setStatusDone();
}

sub debugQuery {
	my $request = shift;
	
	$::d_command && msg("debugQuery()\n");

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['debug'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# use positional parameters as backups
	my $debugFlag = $request->getParam('_debugflag');
	
	if ( !defined $debugFlag || !($debugFlag =~ /^d_/) ) {
		$request->setStatusBadParams();
		return;
	}
	
	$debugFlag = "::" . $debugFlag;
	no strict 'refs';
	
	my $isValue = $$debugFlag;
	$isValue ||= 0;
	
	$request->addResult('_p2', $isValue);
	
	$request->setStatusDone();
}

sub displayQuery {
	my $request = shift;
	
	$::d_command && msg("displayQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['display'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();
	
	my $parsed = $client->parseLines(Slim::Display::Display::curLines($client));

	$request->addResult('_p1', $parsed->{line1} || '');
	$request->addResult('_p2', $parsed->{line2} || '');
		
	$request->setStatusDone();
}

sub displaynowQuery {
	my $request = shift;
	
	$::d_command && msg("displaynowQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['displaynow'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	$request->addResult('_p1', $client->prevline1());
	$request->addResult('_p2', $client->prevline2());
		
	$request->setStatusDone();
}

sub infototalQuery {
	my $request = shift;
	
	$::d_command && msg("infototalQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['info'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $total  = $request->getRequest(1);
	my $entity = $request->getRequest(2);

	if (!defined $total || $total ne 'total' ||
		$request->paramUndefinedOrNotOneOf($entity, ['genres', 'artists', 'albums', 'songs'])) {
		$request->setStatusBadParams();
		return;
	}		

	# get the DB
	my $ds = Slim::Music::Info::getCurrentDataStore();
	
	if ($entity eq 'albums') {
		$request->addResult('_p3', $ds->count('album'));
	}
	if ($entity eq 'artists') {
		$request->addResult('_p3', $ds->count('contributor'));
	}
	if ($entity eq 'genres') {
		$request->addResult('_p3', $ds->count('genre'));
	}
	if ($entity eq 'songs') {
		$request->addResult('_p3', $ds->count('track'));
	}			
	
	$request->setStatusDone();
}

sub linesperscreenQuery {
	my $request = shift;
	
	$::d_command && msg("linesperscreenQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['linesperscreen'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	$request->addResult('_p1', $client->linesPerScreen());
	
	$request->setStatusDone();
}

sub mixerQuery {
	my $request = shift;
	
	$::d_command && msg("mixerQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['mixer'])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();
	my $entity = $request->getRequest(1);

	if ($request->paramUndefinedOrNotOneOf($entity, ['volume', 'muting', 'treble', 'bass', 'pitch'])) {
		$request->setStatusBadParams();
		return;
	}		
	
	if ($entity eq 'muting') {
		$request->addResult('_p2', $client->prefGet("mute"));
	} else {
		$request->addResult('_p2', $client->$entity());
	}
	
	$request->setStatusDone();
}

sub modeQuery {
	my $request = shift;
	
	$::d_command && msg("modeQuery()\n");

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['mode'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	$request->addResult('_p1', Slim::Player::Source::playmode($client));
	
	$request->setStatusDone();
}

sub playlistinfoQuery {
	my $request = shift;
	
	$::d_command && msg("playlistinfoQuery()\n");

	# check this is the correct query
	if ($request->isNotQuery(['playlist'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client   = $request->client();
	my $entity = $request->getRequest(1);
	my $index = $request->getParam('_index');
	
	if ($request->paramUndefinedOrNotOneOf($entity, ['name', 'url', 'modified', 
			'tracks', 'duration', 'artist', 'album', 'title', 'genre', 'path', 
			'repeat', 'shuffle', 'index', 'jump'])) {
		$request->setStatusBadParams();
		return;
	}
	
	if ($entity eq 'repeat') {
		$request->addResult("_$entity", Slim::Player::Playlist::repeat($client));
	}
	if ($entity eq 'shuffle') {
		$request->addResult("_$entity", Slim::Player::Playlist::shuffle($client));
	}
	if ($entity eq 'index' || $entity eq 'jump') {
		$request->addResult("_$entity", Slim::Player::Source::playingSongIndex($client));
	}
	if ($entity eq 'name') {
		$request->addResult("_$entity", Slim::Music::Info::standardTitle($client, $client->currentPlaylist()));
	}
	if ($entity eq 'url') {
		$request->addResult("_$entity", $client->currentPlaylist());
	}
	if ($entity eq 'modified') {
		$request->addResult("_$entity", $client->currentPlaylistModified());
	}
	if ($entity eq 'tracks') {
		$request->addResult("_$entity", Slim::Player::Playlist::count($client));
	}
	if ($entity eq 'path') {
		$request->addResult("_$entity", Slim::Player::Playlist::song($client, $index) || 0);
	}
	if ($entity =~ /(duration|artist|album|title|genre)/) {

		my $ds = Slim::Music::Info::getCurrentDataStore();
		my $url = Slim::Player::Playlist::song($client, $index);
		my $obj = $ds->objectForUrl($url, 1, 1);

		if (blessed($obj) && $obj->can('secs')) {

			# Just call the method on Track
			if ($entity eq 'duration') {
				$request->addResult("_$entity", $obj->secs());
			}
			else {
				$request->addResult("_$entity", $obj->$entity());
			}
		}
	}
	
	$request->setStatusDone();
}

sub playerprefQuery {
	my $request = shift;
	
	$::d_command && msg("playerprefQuery()\n");

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['playerpref'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# use positional parameters as backups
	my $client   = $request->client();
	my $prefName = $request->getParam('_prefname');
	
	if (!defined $prefName) {
		$request->setStatusBadParams();
		return;
	}

	$request->addResult('_p2', $client->prefGet($prefName));
	
	$request->setStatusDone();
}

sub powerQuery {
	my $request = shift;
	
	$::d_command && msg("powerQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['power'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	$request->addResult('_p1', $client->power());
	
	$request->setStatusDone();
}

sub prefQuery {
	my $request = shift;
	
	$::d_command && msg("prefQuery()\n");

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['pref'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $prefName = $request->getParam('_prefname');
	
	if (!defined $prefName) {
		$request->setStatusBadParams();
		return;
	}

	$request->addResult('_p2', Slim::Utils::Prefs::get($prefName));
	
	$request->setStatusDone();
}

sub rateQuery {
	my $request = shift;
	
	$::d_command && msg("rateQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['rate'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	$request->addResult('_p1', Slim::Player::Source::rate($client));
	
	$request->setStatusDone();
}

sub rescanQuery {
	my $request = shift;
	
	$::d_command && msg("rescanQuery()\n");

	if ($request->isNotQuery(['rescan'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the rescan query

	$request->addResult('_p1', Slim::Music::Import::stillScanning() ? 1 : 0);
	
	$request->setStatusDone();
}

sub signalstrengthQuery {
	my $request = shift;
	
	$::d_command && msg("signalstrengthQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['signalstrength'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	$request->addResult('_p1', $client->signalStrength() || 0);
	
	$request->setStatusDone();
}

sub sleepQuery {
	my $request = shift;
	
	$::d_command && msg("sleepQuery()\n");

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['sleep'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	my $isValue = $client->sleepTime() - Time::HiRes::time();
	if ($isValue < 0) {
		$isValue = 0;
	}
	
	$request->addResult('_p1', $isValue);
	
	$request->setStatusDone();
}

sub syncQuery {
	my $request = shift;
	
	$::d_command && msg("syncQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['sync'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	if (Slim::Player::Sync::isSynced($client)) {
	
		my @buddies = Slim::Player::Sync::syncedWith($client);
		for my $eachclient (@buddies) {
			$request->addResult('_p1', $eachclient->id());
		}
	} else {
	
		$request->addResult('_p1', '-');
	}
	
	$request->setStatusDone();
}

sub timeQuery {
	my $request = shift;
	
	$::d_command && msg("timeQuery()\n");

	# check this is the correct command.
	if ($request->isNotQuery(['time', 'gototime'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	$request->addResult('_p1', Slim::Player::Source::songTime($client));
	
	$request->setStatusDone();
}

sub versionQuery {
	my $request = shift;
	
	$::d_command && msg("versionQuery()\n");

	if ($request->isNotQuery(['version'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the version query

	$request->addResult('_p1', $::VERSION);
	
	$request->setStatusDone();
}



1;

__END__
