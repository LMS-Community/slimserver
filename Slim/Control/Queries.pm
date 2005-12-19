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
	
	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotQuery(['mode'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	$request->addResult('_p1', Slim::Player::Source::playmode($client));
	
	$request->setStatusDone();
}

sub playerprefQuery {
	my $request = shift;
	
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
