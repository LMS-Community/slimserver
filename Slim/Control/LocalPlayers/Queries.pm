package Slim::Control::Queries;

# $Id:  $
#
# Logitech Media Server Copyright 2001-2012 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

################################################################################

=head1 NAME

Slim::Control::Queries

=head1 DESCRIPTION

L<Slim::Control::Queries> implements most Logitech Media Server queries and is designed to 
 be exclusively called through Request.pm and the mechanisms it defines.

 Except for subscribe-able queries (such as status and serverstatus), there are no
 important differences between the code for a query and one for
 a command. Please check the commented command in Commands.pm.

=cut

use strict;

use JSON::XS::VersionOneAndTwo;
use MIME::Base64 qw(encode_base64 decode_base64);
use Scalar::Util qw(blessed);
use URI::Escape;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('control.queries');

my $prefs = preferences('server');

###############################################################
#
# Methods only relevant for locally-attached players from here on

sub alarmPlaylistsQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['alarm'], ['playlists']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client   = $request->client();
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $menuMode = $request->getParam('menu') || 0;
	my $id       = $request->getParam('id');

	my $playlists      = Slim::Utils::Alarm->getPlaylists($client);
	my $alarm          = Slim::Utils::Alarm->getAlarm($client, $id) if $id;
	my $currentSetting = $alarm ? $alarm->playlist() : '';

	my @playlistChoices;
	my $loopname = 'item_loop';
	my $cnt = 0;
	
	my ($valid, $start, $end) = ( $menuMode ? (1, 0, scalar @$playlists) : $request->normalize(scalar($index), scalar($quantity), scalar @$playlists) );

	for my $typeRef (@$playlists[$start..$end]) {
		
		my $type    = $typeRef->{type};
		my @choices = ();
		my $aref    = $typeRef->{items};
		
		for my $choice (@$aref) {

			if ($menuMode) {
				my $radio = ( 
					( $currentSetting && $currentSetting eq $choice->{url} )
					|| ( !defined $choice->{url} && !defined $currentSetting )
				);

				my $subitem = {
					text    => $choice->{title},
					radio   => $radio + 0,
					nextWindow => 'refreshOrigin',
					actions => {
						do => {
							cmd    => [ 'alarm', 'update' ],
							params => {
								id          => $id,
								playlisturl => $choice->{url} || 0, # send 0 for "current playlist"
							},
						},
						preview => {
							title   => $choice->{title},
							cmd	=> [ 'playlist', 'preview' ],
							params  => {
								url	=>	$choice->{url}, 
								title	=>	$choice->{title},
							},
						},
					},
				};
				if ( ! $choice->{url} ) {
					$subitem->{actions}->{preview} = {
						cmd => [ 'play' ],
					};
				}
	
				
				if ($typeRef->{singleItem}) {
					$subitem->{'nextWindow'} = 'refresh';
				}
				
				push @choices, $subitem;
			}
			
			else {
				$request->addResultLoop($loopname, $cnt, 'category', $type);
				$request->addResultLoop($loopname, $cnt, 'title', $choice->{title});
				$request->addResultLoop($loopname, $cnt, 'url', $choice->{url});
				$request->addResultLoop($loopname, $cnt, 'singleton', $typeRef->{singleItem} ? '1' : '0');
				$cnt++;
			}
		}

		if ( scalar(@choices) ) {

			my $item = {
				text      => $type,
				offset    => 0,
				count     => scalar(@choices),
				item_loop => \@choices,
			};
			$request->setResultLoopHash($loopname, $cnt, $item);
			
			$cnt++;
		}
	}
	
	$request->addResult("offset", $start);
	$request->addResult("count", $cnt);
	$request->addResult('window', { textareaToken => 'SLIMBROWSER_ALARM_SOUND_HELP' } );
	$request->setStatusDone;
}

sub alarmsQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['alarms']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client   = $request->client();
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $filter	 = $request->getParam('filter');
	my $alarmDOW = $request->getParam('dow');
	
	# being nice: we'll still be accepting 'defined' though this doesn't make sense any longer
	if ($request->paramNotOneOfIfDefined($filter, ['all', 'defined', 'enabled'])) {
		$request->setStatusBadParams();
		return;
	}
	
	$request->addResult('fade', $prefs->client($client)->get('alarmfadeseconds'));
	
	$filter = 'enabled' if !defined $filter;

	my @alarms = grep {
		defined $alarmDOW
			? $_->day() == $alarmDOW
			: ($filter eq 'all' || ($filter eq 'enabled' && $_->enabled()))
	} Slim::Utils::Alarm->getAlarms($client, 1);

	my $count = scalar @alarms;
	$count += 0;
	$request->addResult('count', $count);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {

		my $loopname = 'alarms_loop';
		my $cnt = 0;
		
		for my $alarm (@alarms[$start..$end]) {

			my @dow;
			foreach (0..6) {
				push @dow, $_ if $alarm->day($_);
			}

			$request->addResultLoop($loopname, $cnt, 'id', $alarm->id());
			$request->addResultLoop($loopname, $cnt, 'dow', join(',', @dow));
			$request->addResultLoop($loopname, $cnt, 'enabled', $alarm->enabled());
			$request->addResultLoop($loopname, $cnt, 'repeat', $alarm->repeat());
			$request->addResultLoop($loopname, $cnt, 'time', $alarm->time());
			$request->addResultLoop($loopname, $cnt, 'volume', $alarm->volume());
			$request->addResultLoop($loopname, $cnt, 'url', $alarm->playlist() || 'CURRENT_PLAYLIST');
			$cnt++;
		}
	}

	$request->setStatusDone();
}

sub cursonginfoQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['duration', 'artist', 'album', 'title', 'genre',
			'path', 'remote', 'current_title']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	# get the query
	my $method = $request->getRequest(0);
	my $url = Slim::Player::Playlist::url($client);
	
	if (defined $url) {

		if ($method eq 'path') {
			
			$request->addResult("_$method", $url);

		} elsif ($method eq 'remote') {
			
			$request->addResult("_$method", 
				Slim::Music::Info::isRemoteURL($url));
			
		} elsif ($method eq 'current_title') {
			
			$request->addResult("_$method", 
				Slim::Music::Info::getCurrentTitle($client, $url));

		} else {

			my $songData = _songData(
				$request,
				$url,
				'dalg',			# tags needed for our entities
			);
			
			if (defined $songData->{$method}) {
				$request->addResult("_$method", $songData->{$method});
			}

		}
	}

	$request->setStatusDone();
}


sub connectedQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['connected']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();
	
	$request->addResult('_connected', $client->connected() || 0);
	
	$request->setStatusDone();
}

sub displayQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['display']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();
	
	my $parsed = $client->curLines();

	$request->addResult('_line1', $parsed->{line}[0] || '');
	$request->addResult('_line2', $parsed->{line}[1] || '');
		
	$request->setStatusDone();
}


sub displaynowQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['displaynow']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();

	$request->addResult('_line1', $client->prevline1());
	$request->addResult('_line2', $client->prevline2());
		
	$request->setStatusDone();
}


sub displaystatusQuery_filter {
	my $self = shift;
	my $request = shift;

	# we only listen to display messages
	return 0 if !$request->isCommand([['displaynotify']]);

	# retrieve the clientid, abort if not about us
	my $clientid   = $request->clientid() || return 0;
	my $myclientid = $self->clientid() || return 0; 
	return 0 if $clientid ne $myclientid;

	my $subs     = $self->getParam('subscribe');
	my $type     = $request->getParam('_type');
	my $parts    = $request->getParam('_parts');
	my $duration = $request->getParam('_duration');

	# check displaynotify type against subscription ('showbriefly', 'update', 'bits', 'all')
	if ($subs eq $type || ($subs eq 'bits' && $type ne 'showbriefly') || $subs eq 'all') {

		my $pd = $self->privateData;

		# display forwarding is suppressed for this subscriber source
		return 0 if exists $parts->{ $pd->{'format'} } && !$parts->{ $pd->{'format'} };

		# don't send updates if there is no change
		return 0 if ($type eq 'update' && !$self->client->display->renderCache->{'screen1'}->{'changed'});

		# store display info in subscription request so it can be accessed by displaystatusQuery
		$pd->{'type'}     = $type;
		$pd->{'parts'}    = $parts;
		$pd->{'duration'} = $duration;

		# execute the query immediately
		$self->__autoexecute;
	}

	return 0;
}

sub displaystatusQuery {
	my $request = shift;
	
	main::DEBUGLOG && $log->debug("displaystatusQuery()");

	# check this is the correct query
	if ($request->isNotQuery([['displaystatus']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $subs  = $request->getParam('subscribe');

	# return any previously stored display info from displaynotify
	if (my $pd = $request->privateData) {

		my $client   = $request->client;
		my $format   = $pd->{'format'};
		my $type     = $pd->{'type'};
		my $parts    = $type eq 'showbriefly' ? $pd->{'parts'} : $client->display->renderCache;
		my $duration = $pd->{'duration'};

		$request->addResult('type', $type);

		# return screen1 info if more than one screen
		my $screen1 = $parts->{'screen1'} || $parts;

		if ($subs eq 'bits' && $screen1->{'bitsref'}) {

			# send the display bitmap if it exists (graphics display)
			use bytes;

			my $bits = ${$screen1->{'bitsref'}};
			if ($screen1->{'scroll'}) {
				$bits |= substr(${$screen1->{'scrollbitsref'}}, 0, $screen1->{'overlaystart'}[$screen1->{'scrollline'}]);
			}

			$request->addResult('bits', MIME::Base64::encode_base64($bits) );
			$request->addResult('ext', $screen1->{'extent'});

		} elsif ($format eq 'cli') {

			# format display for cli
			for my $c (keys %$screen1) {
				next unless $c =~ /^(line|center|overlay)$/;
				for my $l (0..$#{$screen1->{$c}}) {
					$request->addResult("$c$l", $screen1->{$c}[$l]) if ($screen1->{$c}[$l] ne '');
				}
			}

		} elsif ($format eq 'jive') {

			# send display to jive from one of the following components
			if (my $ref = $parts->{'jive'} && ref $parts->{'jive'}) {
				if ($ref eq 'CODE') {
					$request->addResult('display', $parts->{'jive'}->() );
				} elsif($ref eq 'ARRAY') {
					$request->addResult('display', { 'text' => $parts->{'jive'} });
				} else {
					$request->addResult('display', $parts->{'jive'} );
				}
			} else {
				my $display = { 
					'text' => $screen1->{'line'} || $screen1->{'center'}
				};
				
				$display->{duration} = $duration if $duration;
				
				$request->addResult('display', $display);
			}
		}

	} elsif ($subs =~ /showbriefly|update|bits|all/) {
		# new subscription request - add subscription, assume cli or jive format for the moment
		$request->privateData({ 'format' => $request->source eq 'CLI' ? 'cli' : 'jive' }); 

		my $client = $request->client;

		main::DEBUGLOG && $log->debug("adding displaystatus subscription $subs");

		if ($subs eq 'bits') {

			if ($client->display->isa('Slim::Display::NoDisplay')) {
				# there is currently no display class, we need an emulated display to generate bits
				Slim::bootstrap::tryModuleLoad('Slim::Display::EmulatedSqueezebox2');
				if ($@) {
					$log->logBacktrace;
					logError("Couldn't load Slim::Display::EmulatedSqueezebox2: [$@]");

				} else {
					# swap to emulated display
					$client->display->forgetDisplay();
					$client->display( Slim::Display::EmulatedSqueezebox2->new($client) );
					$client->display->init;				
					# register ourselves for execution and a cleanup function to swap the display class back
					$request->registerAutoExecute(0, \&displaystatusQuery_filter, \&_displaystatusCleanupEmulated);
				}

			} elsif ($client->display->isa('Slim::Display::EmulatedSqueezebox2')) {
				# register ourselves for execution and a cleanup function to swap the display class back
				$request->registerAutoExecute(0, \&displaystatusQuery_filter, \&_displaystatusCleanupEmulated);

			} else {
				# register ourselves for execution and a cleanup function to clear width override when subscription ends
				$request->registerAutoExecute(0, \&displaystatusQuery_filter, sub {
					$client->display->widthOverride(1, undef);
					if ( !Slim::Control::Request::hasSubscribers('displaystatus', $client->id) ) {
						main::INFOLOG && $log->info("last listener - suppressing display notify");
						$client->display->notifyLevel(0);
					}
					$client->update;
				});
			}

			# override width for new subscription
			$client->display->widthOverride(1, $request->getParam('width'));

		} else {
			$request->registerAutoExecute(0, \&displaystatusQuery_filter, sub {
				if ( !Slim::Control::Request::hasSubscribers('displaystatus', $client->id) ) {
					main::INFOLOG && $log->info("last listener - suppressing display notify");
					$client->display->notifyLevel(0);
				}
			});
		}

		if ($subs eq 'showbriefly') {
			$client->display->notifyLevel(1);
		} else {
			$client->display->notifyLevel(2);
			$client->update;
		}
	}
	
	$request->setStatusDone();
}

# cleanup function to disable display emulation.  This is a named sub so that it can be suppressed when resubscribing.
sub _displaystatusCleanupEmulated {
	my $request = shift;
	my $client  = $request->client;

	if ( !Slim::Control::Request::hasSubscribers('displaystatus', $client->id) ) {
		main::INFOLOG && $log->info("last listener - swapping back to NoDisplay class");
		$client->display->forgetDisplay();
		$client->display( Slim::Display::NoDisplay->new($client) );
		$client->display->init;
	}
}


sub linesperscreenQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['linesperscreen']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();

	$request->addResult('_linesperscreen', $client->linesPerScreen());
	
	$request->setStatusDone();
}


sub mixerQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['mixer'], ['volume', 'muting', 'treble', 'bass', 'pitch']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client = $request->client();
	my $entity = $request->getRequest(1);

	if ($entity eq 'muting') {
		$request->addResult("_$entity", $prefs->client($client)->get("mute"));
	}
	elsif ($entity eq 'volume') {
		$request->addResult("_$entity", $prefs->client($client)->get("volume"));
	} else {
		$request->addResult("_$entity", $client->$entity());
	}
	
	$request->setStatusDone();
}


sub modeQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['mode']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();

	$request->addResult('_mode', Slim::Player::Source::playmode($client));
	
	$request->setStatusDone();
}


sub nameQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['name']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();

	$request->addResult("_value", $client->name());
	
	$request->setStatusDone();
}


sub playerXQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['player'], ['count', 'name', 'address', 'ip', 'id', 'model', 'displaytype', 'isplayer', 'canpoweroff', 'uuid']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $entity;
	$entity      = $request->getRequest(1);
	# if element 1 is 'player', that means next element is the entity
	$entity      = $request->getRequest(2) if $entity eq 'player';  
	my $clientparam = $request->getParam('_IDorIndex');
	
	if ($entity eq 'count') {
		$request->addResult("_$entity", Slim::Player::Client::clientCount());

	} else {	
		my $client;
		
		# were we passed an ID?
		if (defined $clientparam && Slim::Utils::Misc::validMacAddress($clientparam)) {

			$client = Slim::Player::Client::getClient($clientparam);

		} else {
		
			# otherwise, try for an index
			my @clients = Slim::Player::Client::clients();

			if (defined $clientparam && defined $clients[$clientparam]) {
				$client = $clients[$clientparam];
			}
		}

		# brute force attempt using eg. player's IP address (web clients)
		if (!defined $client) {
			$client = Slim::Player::Client::getClient($clientparam);
		}

		if (defined $client) {

			if ($entity eq "name") {
				$request->addResult("_$entity", $client->name());
			} elsif ($entity eq "address" || $entity eq "id") {
				$request->addResult("_$entity", $client->id());
			} elsif ($entity eq "ip") {
				$request->addResult("_$entity", $client->ipport());
			} elsif ($entity eq "model") {
				$request->addResult("_$entity", $client->model());
			} elsif ($entity eq "isplayer") {
				$request->addResult("_$entity", $client->isPlayer());
			} elsif ($entity eq "displaytype") {
				$request->addResult("_$entity", $client->vfdmodel());
			} elsif ($entity eq "canpoweroff") {
				$request->addResult("_$entity", $client->canPowerOff());
			} elsif ($entity eq "uuid") {
                                $request->addResult("_$entity", $client->uuid());
                        }
		}
	}
	
	$request->setStatusDone();
}

sub playersQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['players']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	
	my @prefs;
	
	if (defined(my $pref_list = $request->getParam('playerprefs'))) {

		# split on commas
		@prefs = split(/,/, $pref_list);
	}
	
	my $count = Slim::Player::Client::clientCount();
	$count += 0;

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);
	$request->addResult('count', $count);

	if ($valid) {
		my $idx = $start;
		my $cnt = 0;
		my @players = Slim::Player::Client::clients();

		if (scalar(@players) > 0) {

			for my $eachclient (@players[$start..$end]) {
				$request->addResultLoop('players_loop', $cnt, 
					'playerindex', $idx);
				$request->addResultLoop('players_loop', $cnt, 
					'playerid', $eachclient->id());
                                $request->addResultLoop('players_loop', $cnt,
                                        'uuid', $eachclient->uuid());
				$request->addResultLoop('players_loop', $cnt, 
					'ip', $eachclient->ipport());
				$request->addResultLoop('players_loop', $cnt, 
					'name', $eachclient->name());
				$request->addResultLoop('players_loop', $cnt, 
					'model', $eachclient->model(1));
				$request->addResultLoop('players_loop', $cnt, 
					'isplayer', $eachclient->isPlayer());
				$request->addResultLoop('players_loop', $cnt, 
					'displaytype', $eachclient->vfdmodel())
					unless ($eachclient->model() eq 'http');
				$request->addResultLoop('players_loop', $cnt, 
					'canpoweroff', $eachclient->canPowerOff());
				$request->addResultLoop('players_loop', $cnt, 
					'connected', ($eachclient->connected() || 0));

				for my $pref (@prefs) {
					if (defined(my $value = $prefs->client($eachclient)->get($pref))) {
						$request->addResultLoop('players_loop', $cnt, 
							$pref, $value);
					}
				}
					
				$idx++;
				$cnt++;
			}	
		}
	}
	
	$request->setStatusDone();
}


sub playlistXQuery {
	my $request = shift;

	# check this is the correct query
	if ($request->isNotQuery([['playlist'], ['name', 'url', 'modified', 
			'tracks', 'duration', 'artist', 'album', 'title', 'genre', 'path', 
			'repeat', 'shuffle', 'index', 'jump', 'remote']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();
	my $entity = $request->getRequest(1);
	my $index  = $request->getParam('_index');
		
	if ($entity eq 'repeat') {
		$request->addResult("_$entity", Slim::Player::Playlist::repeat($client));

	} elsif ($entity eq 'shuffle') {
		$request->addResult("_$entity", Slim::Player::Playlist::shuffle($client));

	} elsif ($entity eq 'index' || $entity eq 'jump') {
		$request->addResult("_$entity", Slim::Player::Source::playingSongIndex($client));

	} elsif ($entity eq 'name' && defined(my $playlistObj = $client->currentPlaylist())) {
		$request->addResult("_$entity", Slim::Music::Info::standardTitle($client, $playlistObj));

	} elsif ($entity eq 'url') {
		my $result = $client->currentPlaylist();
		$request->addResult("_$entity", $result);

	} elsif ($entity eq 'modified') {
		$request->addResult("_$entity", $client->currentPlaylistModified());

	} elsif ($entity eq 'tracks') {
		$request->addResult("_$entity", Slim::Player::Playlist::count($client));

	} elsif ($entity eq 'path') {
		my $result = Slim::Player::Playlist::url($client, $index);
		$request->addResult("_$entity",  $result || 0);

	} elsif ($entity eq 'remote') {
		if (defined (my $url = Slim::Player::Playlist::url($client, $index))) {
			$request->addResult("_$entity", Slim::Music::Info::isRemoteURL($url));
		}
		
	} elsif ($entity =~ /(duration|artist|album|title|genre|name)/) {

		my $songData = _songData(
			$request,
			Slim::Player::Playlist::song($client, $index),
			'dalgN',			# tags needed for our entities
		);
		
		if (defined $songData->{$entity}) {
			$request->addResult("_$entity", $songData->{$entity});
		}
		elsif ($entity eq 'name' && defined $songData->{remote_title}) {
			$request->addResult("_$entity", $songData->{remote_title});
		}
	}
	
	$request->setStatusDone();
}


sub powerQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['power']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	$request->addResult('_power', $client->power());
	
	$request->setStatusDone();
}


sub signalstrengthQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['signalstrength']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	$request->addResult('_signalstrength', $client->signalStrength() || 0);
	
	$request->setStatusDone();
}


sub sleepQuery {
	my $request = shift;

	# check this is the correct query
	if ($request->isNotQuery([['sleep']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	my $isValue = $client->sleepTime() - Time::HiRes::time();
	if ($isValue < 0) {
		$isValue = 0;
	}
	
	$request->addResult('_sleep', $isValue);
	
	$request->setStatusDone();
}


# the filter function decides, based on a notified request, if the status
# query must be re-executed.
sub statusQuery_filter {
	my $self = shift;
	my $request = shift;
	
	# retrieve the clientid, abort if not about us
	my $clientid   = $request->clientid() || return 0;
	my $myclientid = $self->clientid() || return 0;
	
	# Bug 10064: playlist notifications get sent to everyone in the sync-group
	if ($request->isCommand([['playlist', 'newmetadata']]) && (my $client = $request->client)) {
		return 0 if !grep($_->id eq $myclientid, $client->syncGroupActiveMembers());
	} else {
		return 0 if $clientid ne $myclientid;
	}
	
	# ignore most prefset commands, but e.g. alarmSnoozeSeconds needs to generate a playerstatus update
	if ( $request->isCommand( [['prefset', 'playerpref']] ) ) {
		my $prefname = $request->getParam('_prefname');
		if ( defined($prefname) && ( $prefname eq 'alarmSnoozeSeconds' || $prefname eq 'digitalVolumeControl' ) ) {
			# this needs to pass through the filter
		}
		else {
			return 0;
		}
	}

	# commands we ignore
	return 0 if $request->isCommand([['ir', 'button', 'debug', 'pref', 'display']]);

	# special case: the client is gone!
	if ($request->isCommand([['client'], ['forget']])) {
		
		# pretend we do not need a client, otherwise execute() fails
		# and validate() deletes the client info!
		$self->needClient(0);
		
		# we'll unsubscribe above if there is no client
		return 1;
	}

	# suppress frequent updates during volume changes
	if ($request->isCommand([['mixer'], ['volume']])) {

		return 3;
	}

	# give it a tad more time for muting to leave room for the fade to finish
	# see bug 5255
	if ($request->isCommand([['mixer'], ['muting']])) {

		return 1.4;
	}

	# give it more time for stop as this is often followed by a new play
	# command (for example, with track skip), and the new status may be delayed
	if ($request->isCommand([['playlist'],['stop']])) {
		return 2.0;
	}

	# This is quite likely about to be followed by a 'playlist newsong' so
	# we only want to generate this if the newsong is delayed, as can be
	# the case with remote tracks.
	# Note that the 1.5s here and the 1s from 'playlist stop' above could
	# accumulate in the worst case.
	if ($request->isCommand([['playlist'], ['open', 'jump']])) {
		return 2.5;
	}

	# send every other notif with a small delay to accomodate
	# bursts of commands
	return 1.3;
}


sub statusQuery {
	my $request = shift;
	
	my $isDebug = main::DEBUGLOG && $log->is_debug;
	
	main::DEBUGLOG && $isDebug && $log->debug("statusQuery()");

	# check this is the correct query
	if ($request->isNotQuery([['status']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the initial parameters
	my $client = $request->client();
	my $menu = $request->getParam('menu');
	
	# menu/jive mgmt
	my $menuMode = defined $menu;
	my $useContextMenu = $request->getParam('useContextMenu');

	# accomodate the fact we can be called automatically when the client is gone
	if (!defined($client) || $client->isa('Slim::Player::Disconnected')) {
		$request->addResult('error', "invalid player");
		# Still need to (re)register the autoexec if this is a subscription so
		# that the subscription does not dissappear while a Comet client thinks
		# that it is still valid.
		goto do_it_again;
	}
	
	my $connected    = $client->connected() || 0;
	my $power        = $client->power();
	my $repeat       = Slim::Player::Playlist::repeat($client);
	my $shuffle      = Slim::Player::Playlist::shuffle($client);
	my $songCount    = Slim::Player::Playlist::count($client);

	my $idx = 0;


	# now add the data...

	if (Slim::Music::Import->stillScanning()) {
		$request->addResult('rescan', "1");
	}

	if ($client->needsUpgrade()) {
		$request->addResult('player_needs_upgrade', "1");
	}
	
	if ($client->isUpgrading()) {
		$request->addResult('player_is_upgrading', "1");
	}
	
	# add player info...
	if (my $name = $client->name()) {
		$request->addResult("player_name", $name);
	}
	$request->addResult("player_connected", $connected);
	$request->addResult("player_ip", $client->ipport()) if $connected;

	# add showBriefly info
	if ($client->display->renderCache->{showBriefly}
		&& $client->display->renderCache->{showBriefly}->{line}
		&& $client->display->renderCache->{showBriefly}->{ttl} > time()) {
		$request->addResult('showBriefly', $client->display->renderCache->{showBriefly}->{line});
	}

	if ($client->isPlayer()) {
		$power += 0;
		$request->addResult("power", $power);
	}
	
	if ($client->isa('Slim::Player::Squeezebox')) {
		$request->addResult("signalstrength", ($client->signalStrength() || 0));
	}
	
	my $playlist_cur_index;
	
	$request->addResult('mode', Slim::Player::Source::playmode($client));
	if ($client->isPlaying() && !$client->isPlaying('really')) {
		$request->addResult('waitingToPlay', 1);	
	}

	if (my $song = $client->playingSong()) {

		if ($song->isRemote()) {
			$request->addResult('remote', 1);
			$request->addResult('current_title', 
				Slim::Music::Info::getCurrentTitle($client, $song->currentTrack()->url));
		}
			
		$request->addResult('time', 
			Slim::Player::Source::songTime($client));

		# This is just here for backward compatibility with older SBC firmware
		$request->addResult('rate', 1);
			
		if (my $dur = $song->duration()) {
			$dur += 0;
			$request->addResult('duration', $dur);
		}
			
		my $canSeek = Slim::Music::Info::canSeek($client, $song);
		if ($canSeek) {
			$request->addResult('can_seek', 1);
		}
	}
		
	if ($client->currentSleepTime()) {

		my $sleep = $client->sleepTime() - Time::HiRes::time();
		$request->addResult('sleep', $client->currentSleepTime() * 60);
		$request->addResult('will_sleep_in', ($sleep < 0 ? 0 : $sleep));
	}
		
	if ($client->isSynced()) {

		my $master = $client->master();

		$request->addResult('sync_master', $master->id());

		my @slaves = Slim::Player::Sync::slaves($master);
		my @sync_slaves = map { $_->id } @slaves;

		$request->addResult('sync_slaves', join(",", @sync_slaves));
	}
	
	if ($client->hasVolumeControl()) {
		# undefined for remote streams
		my $vol = $prefs->client($client)->get('volume');
		$vol += 0;
		$request->addResult("mixer volume", $vol);
	}
		
	if ($client->maxBass() - $client->minBass() > 0) {
		$request->addResult("mixer bass", $client->bass());
	}

	if ($client->maxTreble() - $client->minTreble() > 0) {
		$request->addResult("mixer treble", $client->treble());
	}

	if ($client->maxPitch() - $client->minPitch()) {
		$request->addResult("mixer pitch", $client->pitch());
	}

	$repeat += 0;
	$request->addResult("playlist repeat", $repeat);
	$shuffle += 0;
	$request->addResult("playlist shuffle", $shuffle); 

	# Backwards compatibility - now obsolete
	$request->addResult("playlist mode", 'off');

	if (defined $client->sequenceNumber()) {
		$request->addResult("seq_no", $client->sequenceNumber());
	}

	if (defined (my $playlistObj = $client->currentPlaylist())) {
		$request->addResult("playlist_id", $playlistObj->id());
		$request->addResult("playlist_name", $playlistObj->title());
		$request->addResult("playlist_modified", $client->currentPlaylistModified());
	}

	if ($songCount > 0) {
		$playlist_cur_index = Slim::Player::Source::playingSongIndex($client);
		$request->addResult(
			"playlist_cur_index", 
			$playlist_cur_index
		);
		$request->addResult("playlist_timestamp", $client->currentPlaylistUpdateTime());
	}

	$request->addResult("playlist_tracks", $songCount);
	
	# give a count in menu mode no matter what
	if ($menuMode) {
		# send information about the alarm state to SP
		my $alarmNext    = Slim::Utils::Alarm->alarmInNextDay($client);
		my $alarmComing  = $alarmNext ? 'set' : 'none';
		my $alarmCurrent = Slim::Utils::Alarm->getCurrentAlarm($client);
		# alarm_state
		# 'active': means alarm currently going off
		# 'set':    alarm set to go off in next 24h on this player
		# 'none':   alarm set to go off in next 24h on this player
		# 'snooze': alarm is active but currently snoozing
		if (defined($alarmCurrent)) {
			my $snoozing     = $alarmCurrent->snoozeActive();
			if ($snoozing) {
				$request->addResult('alarm_state', 'snooze');
				$request->addResult('alarm_next', 0);
			} else {
				$request->addResult('alarm_state', 'active');
				$request->addResult('alarm_next', 0);
			}
		} else {
			$request->addResult('alarm_state', $alarmComing);
			$request->addResult('alarm_next', defined $alarmNext ? $alarmNext + 0 : 0);
		}

		# NEW ALARM CODE
		# Add alarm version so a player can do the right thing
		$request->addResult('alarm_version', 2);

		# The alarm_state and alarm_next are only good for an alarm in the next 24 hours
		#  but we need the next alarm (which could be further away than 24 hours)
		my $alarmNextAlarm = Slim::Utils::Alarm->getNextAlarm($client);

		if($alarmNextAlarm and $alarmNextAlarm->enabled()) {
			# Get epoch seconds
			my $alarmNext2 = $alarmNextAlarm->nextDue();
			$request->addResult('alarm_next2', $alarmNext2);
			# Get repeat status
			my $alarmRepeat = $alarmNextAlarm->repeat();
			$request->addResult('alarm_repeat', $alarmRepeat);
			# Get days alarm is active
			my $alarmDays = "";
			for my $i (0..6) {
				$alarmDays .= $alarmNextAlarm->day($i) ? "1" : "0";
			}
			$request->addResult('alarm_days', $alarmDays);
		}

		# send client pref for alarm snooze
		my $alarm_snooze_seconds = $prefs->client($client)->get('alarmSnoozeSeconds');
		$request->addResult('alarm_snooze_seconds', defined $alarm_snooze_seconds ? $alarm_snooze_seconds + 0 : 540);

		# send client pref for alarm timeout
		my $alarm_timeout_seconds = $prefs->client($client)->get('alarmTimeoutSeconds');
		$request->addResult('alarm_timeout_seconds', defined $alarm_timeout_seconds ? $alarm_timeout_seconds + 0 : 300);

		# send client pref for digital volume control
		my $digitalVolumeControl = $prefs->client($client)->get('digitalVolumeControl');
		if ( defined($digitalVolumeControl) ) {
			$request->addResult('digital_volume_control', $digitalVolumeControl + 0);
		}

		# send which presets are defined
		my $presets = $prefs->client($client)->get('presets');
		my $presetLoop;
		my $presetData; # send detailed preset data in a separate loop so we don't break backwards compatibility
		for my $i (0..9) {
			if ( ref($presets) eq 'ARRAY' && defined $presets->[$i] ) {
				if ( ref($presets->[$i]) eq 'HASH') {	
				$presetLoop->[$i] = 1;
					for my $key (keys %{$presets->[$i]}) {
						if (defined $presets->[$i]->{$key}) {
							$presetData->[$i]->{$key} = $presets->[$i]->{$key};
						}
					}
			} else {
				$presetLoop->[$i] = 0;
					$presetData->[$i] = {};
			}
			} else {
				$presetLoop->[$i] = 0;
				$presetData->[$i] = {};
		}
		}
		$request->addResult('preset_loop', $presetLoop);
		$request->addResult('preset_data', $presetData);

		main::DEBUGLOG && $isDebug && $log->debug("statusQuery(): setup base for jive");
		$songCount += 0;
		# add two for playlist save/clear to the count if the playlist is non-empty
		my $menuCount = $songCount?$songCount+2:0;
			
		if ( main::SLIM_SERVICE ) {
			# Bug 7437, No Playlist Save on SN
			$menuCount--;
		}
		
		$request->addResult("count", $menuCount);
		
		my $base;
		if ( $useContextMenu ) {
			# context menu for 'more' action
			$base->{'actions'}{'more'} = _contextMenuBase('track');
			# this is the current playlist, so tell SC the context of this menu
			$base->{'actions'}{'more'}{'params'}{'context'} = 'playlist';
		} else {
			$base = {
				actions => {
					go => {
						cmd => ['trackinfo', 'items'],
						params => {
							menu => 'nowhere', 
							useContextMenu => 1,
							context => 'playlist',
						},
						itemsParams => 'params',
					},
				},
			};
		}
		$request->addResult('base', $base);
	}
	
	if ($songCount > 0) {
	
		main::DEBUGLOG && $isDebug && $log->debug("statusQuery(): setup non-zero player response");
		# get the other parameters
		my $tags     = $request->getParam('tags');
		my $index    = $request->getParam('_index');
		my $quantity = $request->getParam('_quantity');
		
		my $loop = $menuMode ? 'item_loop' : 'playlist_loop';
		
		if ( $menuMode ) {
			# Set required tags for menuMode
			$tags = 'aAlKNcx';
		}
		else {
			$tags = 'gald' if !defined $tags;
		}

		# we can return playlist data.
		# which mode are we in?
		my $modecurrent = 0;

		if (defined($index) && ($index eq "-")) {
			$modecurrent = 1;
		}
		
		# bug 9132: rating might have changed
		# we need to be sure we have the latest data from the DB if ratings are requested
		my $refreshTrack = $tags =~ /R/;
		
		my $track = Slim::Player::Playlist::song($client, $playlist_cur_index, $refreshTrack);

		if ($track->remote) {
			$tags .= "B"; # include button remapping
			my $metadata = _songData($request, $track, $tags);
			$request->addResult('remoteMeta', $metadata);
		}

		# if repeat is 1 (song) and modecurrent, then show the current song
		if ($modecurrent && ($repeat == 1) && $quantity) {

			$request->addResult('offset', $playlist_cur_index) if $menuMode;

			if ($menuMode) {
				_addJiveSong($request, $loop, 0, $playlist_cur_index, $track);
			}
			else {
				_addSong($request, $loop, 0, 
					$track, $tags,
					'playlist index', $playlist_cur_index
				);
			}
			
		} else {

			my ($valid, $start, $end);
			
			if ($modecurrent) {
				($valid, $start, $end) = $request->normalize($playlist_cur_index, scalar($quantity), $songCount);
			} else {
				($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $songCount);
			}

			if ($valid) {
				my $count = 0;
				$start += 0;
				$request->addResult('offset', $request->getParam('_index')) if $menuMode;
				
				my @tracks = Slim::Player::Playlist::songs($client, $start, $end);
				
				# Slice and map playlist to get only the requested IDs
				my @trackIds = grep (defined $_, map { (!defined $_ || $_->remote) ? undef : $_->id } @tracks);
				
				# get hash of tagged data for all tracks
				my $songData = _getTagDataForTracks( $tags, {
					trackIds => \@trackIds,
				} ) if scalar @trackIds;
				
				$idx = $start;
				foreach( @tracks ) {
					# XXX - need to resolve how we get here in the first place
					# should not need this:
					next if !defined $_;

					# Use songData for track, if remote use the object directly
					my $data = $_->remote ? $_ : $songData->{$_->id};

					# 17352 - when the db is not fully populated yet, and a stored player playlist
					# references a track not in the db yet, we can fail
					next if !$data;

					if ($menuMode) {
						_addJiveSong($request, $loop, $count, $idx, $data);
						# add clear and save playlist items at the bottom
						if ( ($idx+1)  == $songCount) {
							_addJivePlaylistControls($request, $loop, $count);
						}
					}
					else {
						_addSong(	$request, $loop, $count, 
									$data, $tags,
									'playlist index', $idx
								);
					}

					$count++;
					$idx++;
					
					# give peace a chance...
					# This is need much less now that the DB query is done ahead of time
					main::idleStreams() if ! ($count % 20);
				}
				
				# we don't do that in menu mode!
				if (!$menuMode) {
				
					my $repShuffle = $prefs->get('reshuffleOnRepeat');
					my $canPredictFuture = ($repeat == 2)  			# we're repeating all
											&& 						# and
											(	($shuffle == 0)		# either we're not shuffling
												||					# or
												(!$repShuffle));	# we don't reshuffle
				
					if ($modecurrent && $canPredictFuture && ($count < scalar($quantity))) {
						
						# XXX: port this to use _getTagDataForTracks

						# wrap around the playlist...
						($valid, $start, $end) = $request->normalize(0, (scalar($quantity) - $count), $songCount);		

						if ($valid) {

							for ($idx = $start; $idx <= $end; $idx++){

								_addSong($request, $loop, $count, 
									Slim::Player::Playlist::song($client, $idx, $refreshTrack), $tags,
									'playlist index', $idx
								);

								$count++;
								main::idleStreams();
							}
						}
					}

				}
			}
		}
	}

do_it_again:
	# manage the subscription
	if (defined(my $timeout = $request->getParam('subscribe'))) {
		main::DEBUGLOG && $isDebug && $log->debug("statusQuery(): setting up subscription");
	
		# register ourselves to be automatically re-executed on timeout or filter
		$request->registerAutoExecute($timeout, \&statusQuery_filter);
	}
	
	$request->setStatusDone();
}


sub syncQuery {
	my $request = shift;

	# check this is the correct query
	if ($request->isNotQuery([['sync']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	if ($client->isSynced()) {
	
		my @sync_buddies = map { $_->id() } $client->syncedWith();

		$request->addResult('_sync', join(",", @sync_buddies));
	} else {
	
		$request->addResult('_sync', '-');
	}
	
	$request->setStatusDone();
}


sub syncGroupsQuery {
	my $request = shift;

	# check this is the correct query
	if ($request->isNotQuery([['syncgroups']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	
	my $cnt      = 0;
	my @players  = Slim::Player::Client::clients();
	my $loopname = 'syncgroups_loop'; 

	if (scalar(@players) > 0) {

		for my $eachclient (@players) {
			
			# create a group if $eachclient is a master
			if ($eachclient->isSynced() && Slim::Player::Sync::isMaster($eachclient)) {
				my @sync_buddies = map { $_->id() } $eachclient->syncedWith();
				my @sync_names   = map { $_->name() } $eachclient->syncedWith();
		
				$request->addResultLoop($loopname, $cnt, 'sync_members', join(",", $eachclient->id, @sync_buddies));				
				$request->addResultLoop($loopname, $cnt, 'sync_member_names', join(",", $eachclient->name, @sync_names));				
				
				$cnt++;
			}
		}
	}
	
	$request->setStatusDone();
}


sub timeQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['time', 'gototime']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	$request->addResult('_time', Slim::Player::Source::songTime($client));
	
	$request->setStatusDone();
}


################################################################################
# Helper functions
################################################################################

sub _addJivePlaylistControls {

	my ($request, $loop, $count) = @_;
	
	my $client = $request->client || return;
	
	# clear playlist
	my $text = $client->string('CLEAR_PLAYLIST');
	# add clear playlist and save playlist menu items
	$count++;
	my @clear_playlist = (
		{
			text    => $client->string('CANCEL'),
			actions => {
				go => {
					player => 0,
					cmd    => [ 'jiveblankcommand' ],
				},
			},
			nextWindow => 'parent',
		},
		{
			text    => $client->string('CLEAR_PLAYLIST'),
			actions => {
				do => {
					player => 0,
					cmd    => ['playlist', 'clear'],
				},
			},
			nextWindow => 'home',
		},
	);
	
	my $clearicon = main::SLIM_SERVICE
		? Slim::Networking::SqueezeNetwork->url('/static/images/icons/playlistclear.png', 'external')
		: '/html/images/playlistclear.png';

	$request->addResultLoop($loop, $count, 'text', $text);
	$request->addResultLoop($loop, $count, 'icon-id', $clearicon);
	$request->addResultLoop($loop, $count, 'offset', 0);
	$request->addResultLoop($loop, $count, 'count', 2);
	$request->addResultLoop($loop, $count, 'item_loop', \@clear_playlist);
	
	if ( main::SLIM_SERVICE ) {
		# Bug 7110, move images
		use Slim::Networking::SqueezeNetwork;
		$request->addResultLoop( $loop, $count, 'icon', Slim::Networking::SqueezeNetwork->url('/static/jive/images/blank.png', 1) );
	}

	# save playlist
	my $input = {
		len          => 1,
		allowedChars => $client->string('JIVE_ALLOWEDCHARS_WITHCAPS'),
		help         => {
			text => $client->string('JIVE_SAVEPLAYLIST_HELP'),
		},
	};
	my $actions = {
		do => {
			player => 0,
			cmd    => ['playlist', 'save'],
			params => {
				playlistName => '__INPUT__',
			},
			itemsParams => 'params',
		},
	};
	$count++;

	# Bug 7437, don't display Save Playlist on SN
	if ( !main::SLIM_SERVICE ) {
		$text = $client->string('SAVE_PLAYLIST');
		$request->addResultLoop($loop, $count, 'text', $text);
		$request->addResultLoop($loop, $count, 'icon-id', '/html/images/playlistsave.png');
		$request->addResultLoop($loop, $count, 'input', $input);
		$request->addResultLoop($loop, $count, 'actions', $actions);
	}
}


# **********************************************************************
# *** This is a performance-critical method ***
# Take cake to understand the performance implications of any changes.

sub _addJiveSong {
	my $request   = shift; # request
	my $loop      = shift; # loop
	my $count     = shift; # loop index
	my $index     = shift; # playlist index
	my $track     = shift || return;
	
	my $songData  = _songData(
		$request,
		$track,
		'aAlKNcx',			# tags needed for our entities
	);
	
	my $isRemote = $songData->{remote};
	
	$request->addResultLoop($loop, $count, 'trackType', $isRemote ? 'radio' : 'local');
	
	my $text   = $songData->{title};
	my $title  = $text;
	my $album  = $songData->{album};
	my $artist = $songData->{artist};
	
	# Bug 15779, include other role data
	# XXX may want to include all contributor roles here?
	my (%artists, @artists);
	foreach ('albumartist', 'trackartist', 'artist') {
		
		next if !$songData->{$_};
		
		foreach my $a ( split (/, /, $songData->{$_}) ) {
			if ( $a && !$artists{$a} ) {
				push @artists, $a;
				$artists{$a} = 1;
			}
		}
	}
	$artist = join(', ', @artists);
	
	if ( $isRemote && $text && $album && $artist ) {
		$request->addResult('current_title');
	}

	my @secondLine;
	if (defined $artist) {
		push @secondLine, $artist;
	}
	if (defined $album) {
		push @secondLine, $album;
	}

	# Special case for Internet Radio streams, if the track is remote, has no duration,
	# has title metadata, and has no album metadata, display the station title as line 1 of the text
	if ( $songData->{remote_title} && $songData->{remote_title} ne $title && !$album && $isRemote && !$track->secs ) {
		push @secondLine, $songData->{remote_title};
		$album = $songData->{remote_title};
		$request->addResult('current_title');
	}

	my $secondLine = join(' - ', @secondLine);
	$text .= "\n" . $secondLine;

	# Bug 7443, check for a track cover before using the album cover
	my $iconId = $songData->{coverid};
	
	if ( defined($songData->{artwork_url}) ) {
		$request->addResultLoop( $loop, $count, 'icon', $songData->{artwork_url} );
	}
	elsif ( main::SLIM_SERVICE ) {
		# send radio placeholder art when on mysb.com
		$request->addResultLoop($loop, $count, 'icon-id',
			Slim::Networking::SqueezeNetwork->url('/static/images/icons/radio.png', 'external')
		);
	}
	elsif ( defined $iconId ) {
		$request->addResultLoop($loop, $count, 'icon-id', $iconId);
	}
	elsif ( $isRemote ) {
		# send radio placeholder art for remote tracks with no art
		$request->addResultLoop($loop, $count, 'icon-id', '/html/images/radio.png');
	}

	# split to three discrete elements for NP screen
	if ( defined($title) ) {
		$request->addResultLoop($loop, $count, 'track', $title);
	} else {
		$request->addResultLoop($loop, $count, 'track', '');
	}
	if ( defined($album) ) {
		$request->addResultLoop($loop, $count, 'album', $album);
	} else {
		$request->addResultLoop($loop, $count, 'album', '');
	}
	if ( defined($artist) ) {
		$request->addResultLoop($loop, $count, 'artist', $artist);
	} else {
		$request->addResultLoop($loop, $count, 'artist', '');
	}
	# deliver as one formatted multi-line string for NP playlist screen
	$request->addResultLoop($loop, $count, 'text', $text);

	my $params = {
		'track_id' => ($songData->{'id'} + 0), 
		'playlist_index' => $index,
	};
	$request->addResultLoop($loop, $count, 'params', $params);
	$request->addResultLoop($loop, $count, 'style', 'itemplay');
}


# contextMenuQuery is a wrapper for producing context menus for various objects
sub contextMenuQuery {

	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['contextmenu']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');

	my $client        = $request->client();
	my $menu          = $request->getParam('menu');

	# this subroutine is just a wrapper, so we prep the @requestParams array to pass on to another command
	my $params = $request->getParamsCopy();
	my @requestParams = ();
	for my $key (keys %$params) {
		next if $key eq '_index' || $key eq '_quantity';
		push @requestParams, $key . ':' . $params->{$key};
	}

	my $proxiedRequest;
	if (defined($menu)) {
		# send the command to *info, where * is the param given to the menu command
		my $command = $menu . 'info';
		$proxiedRequest = Slim::Control::Request->new( $client->id, [ $command, 'items', $index, $quantity, @requestParams ] );

		# Bug 17357, propagate the connectionID as info handlers cache sessions based on this
		$proxiedRequest->connectionID( $request->connectionID );
		$proxiedRequest->execute();

		# Bug 13744, wrap async requests
		if ( $proxiedRequest->isStatusProcessing ) {			
			$proxiedRequest->callbackFunction( sub {
				$request->setRawResults( $_[0]->getResults );
				$request->setStatusDone();
			} );
			
			$request->setStatusProcessing();
			return;
		}
		
	# if we get here, we punt
	} else {
		$request->setStatusBadParams();
	}

	# now we have the response in $proxiedRequest that needs to get its output sent via $request
	$request->setRawResults( $proxiedRequest->getResults );

}

# currently this sends back a callback that is only for tracks
# to be expanded to work with artist/album/etc. later
sub _contextMenuBase {

	my $menu = shift;

	return {
		player => 0,
		cmd => ['contextmenu', ],
			'params' => {
				'menu' => $menu,
			},
		itemsParams => 'params',
		window => { 
			isContextMenu => 1, 
		},
	};

}

=head1 SEE ALSO

L<Slim::Control::Request.pm>

=cut


1;

__END__
