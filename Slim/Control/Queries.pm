package Slim::Control::Queries;

# Logitech Media Server Copyright 2001-2011 Logitech.
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

use Storable;
use JSON::XS::VersionOneAndTwo;
use Digest::MD5 qw(md5_hex);
use MIME::Base64 qw(encode_base64);
use Scalar::Util qw(blessed);
use URI::Escape;
use Tie::Cache::LRU::Expires;

use Slim::Utils::Alarm;
use Slim::Utils::Log;
use Slim::Utils::Unicode;
use Slim::Utils::Prefs;
use Slim::Utils::Text;
use Slim::Web::ImageProxy qw(proxiedImage);

{
	if (main::ISWINDOWS) {
		require Slim::Utils::OS::Win32;
	}
}

my $log = logger('control.queries');

my $prefs = preferences('server');

# Frequently used data can be cached in memory, such as the list of albums for Jive
our $cache = {};

# small, short lived cache of folder entries to prevent repeated disk reads on BMF
tie our %bmfCache, 'Tie::Cache::LRU::Expires', EXPIRES => 60, ENTRIES => $prefs->get('dbhighmem') ? 1024 : 5;

sub init {
	my $class = shift;
	
	# Wipe cached data after rescan
	if ( !main::SCANNER ) {
		Slim::Control::Request::subscribe( sub {
			$class->wipeCaches;
		}, [['rescan'], ['done']] );

		if (main::LIBRARY) {
			require Slim::Control::Library::Queries;
		}
	}
}

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


sub debugQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['debug']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $category = $request->getParam('_debugflag');

	if ( !defined $category || !Slim::Utils::Log->isValidCategory($category) ) {

		$request->setStatusBadParams();
		return;
	}

	my $categories = Slim::Utils::Log->allCategories;
	
	if (defined $categories->{$category}) {
	
		$request->addResult('_value', $categories->{$category});
		
		$request->setStatusDone();

	} else {

		$request->setStatusBadParams();
	}
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

sub getStringQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['getstring']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $tokenlist = $request->getParam('_tokens');

	foreach my $token (split /,/, $tokenlist) {
		
		# check whether string exists or not, to prevent stack dumps if
		# client queries inexistent string
		if (Slim::Utils::Strings::stringExists($token)) {
			
			$request->addResult($token, $request->string($token));
		}
		
		else {
			
			$request->addResult($token, '');
		}
	}
	
	$request->setStatusDone();
}


sub irenableQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['irenable']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	$request->addResult('_irenable', $client->irenable());
	
	$request->setStatusDone();
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

sub musicfolderQuery {
	mediafolderQuery(@_);
}

sub mediafolderQuery {
	my $request = shift;
	
	main::INFOLOG && $log->info("mediafolderQuery()");

	# check this is the correct query.
	if ($request->isNotQuery([['mediafolder']]) && $request->isNotQuery([['musicfolder']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client   = $request->client();
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $folderId = $request->getParam('folder_id');
	my $want_top = $request->getParam('return_top');
	my $url      = $request->getParam('url');
	my $type     = $request->getParam('type') || '';
	my $tags     = $request->getParam('tags') || '';
	
	# duration is not available for anything but audio files
	$tags =~ s/d// if $type && $type ne 'audio';
	
	my ($sql, $volatileUrl);
	
	# Bug 17436, don't allow BMF if a scan is running, browse without storing tracks in database instead
	# Don't use the library when running in nolibrary mode either.
	if (!main::LIBRARY || Slim::Music::Import->stillScanning()) {
		$volatileUrl = 1;
	}

	if (Slim::Music::Info::isVolatileURL($url)) {
		# if we're dealing with temporary items, store the real URL in $volatileUrl
		$volatileUrl = $url;
		$volatileUrl =~ s/^tmp/file/;
	}
	
	# url overrides any folderId
	my $params = ();
	my $mediaDirs = Slim::Utils::Misc::getMediaDirs($type || 'audio');
	
	$params->{recursive} = $request->getParam('recursive');
	
	# add "volatile" folders which are not scanned, to be browsed and played on the fly
	push @$mediaDirs, map { 
		my $url = Slim::Utils::Misc::fileURLFromPath($_);
		$url =~ s/^file/tmp/;
		$url;
	} @{ Slim::Utils::Misc::getInactiveMediaDirs() } if !$type || $type eq 'audio';
	
	my ($topLevelObj, $items, $count, $topPath, $realName);
	
	my $bmfUrlForName = $cache->{bmfUrlForName} || {};
	
	my $highmem = $prefs->get('dbhighmem');
				
	my $filter = sub {
		# if a $sth is passed, we'll do a quick lookup to check existence only, not returning an actual object if possible
		my ($filename, $topPath, $sth) = @_;

		my $url = $bmfUrlForName->{$filename . $topPath};
		if (!$url) {
			$url ||= Slim::Utils::Misc::fixPath($filename, $topPath) || '';
			
			# keep a cache of the mapping in memory if we can afford it
			if ($highmem && $url) {
				$bmfUrlForName->{$filename . $topPath} ||= $url;
			}
		}

		# Amazingly, this just works. :)
		# Do the cheap compare for osName first - so non-windows users
		# won't take the penalty for the lookup.
		if (main::ISWINDOWS && Slim::Music::Info::isWinShortcut($url)) {
			($realName, $url) = Slim::Utils::OS::Win32->getShortcut($url);
		}
		
		elsif (main::ISMAC) {
			if ( my $alias = Slim::Utils::Misc::pathFromMacAlias($url) ) {
				$url = $alias;
			}
		}

		if (main::LIBRARY && $sth && $url) {
			# don't create the dir objects in the first pass - we can create them later when paging through the list
			# only run a quick, relatively cheap test on the type of the URL
			$sth->execute($url);
			
			my $itemDetails = $sth->fetchrow_hashref;
			return 1 if $itemDetails && $itemDetails->{content_type};
			
			my $type = Slim::Music::Info::typeFromPath($url) || 'nada';
			return 1 if $type eq 'dir'; 
		}
		
		$url =~ s/^file/tmp/ if $volatileUrl;

		# if we have dbhighmem configured, use a memory cache to prevent slow lookups
		my $item = $bmfCache{$url} || Slim::Schema->objectForUrl({
			'url'      => $url,
			'create'   => 1,
			'readTags' => 1,
			'playlist' => Slim::Music::Info::isPlaylist($url),
		}) if $url;

		if ( (blessed($item) && $item->can('content_type')) || ($params->{typeRegEx} && $filename =~ $params->{typeRegEx}) ) {

			if ($highmem) {
				$bmfCache{$url} = $item;
			}

			# when dealing with a volatile file, read tags, as above objectForUrl() would not scan remote files
			if ( $volatileUrl ) {
				require Slim::Player::Protocols::Volatile;
				Slim::Player::Protocols::Volatile->getMetadataFor($client, $url);
			}
			
			return $item;
		}
	};

	if ( !defined $url && !defined $folderId && scalar(@$mediaDirs) > 1) {
		
		$items = $mediaDirs;
		$count = scalar(@$items);
		$topPath = '';

	}

	else {

		if ($volatileUrl && $url) {
			# We can't work with the URL for volatile objects. Make sure there is an object for it.
			my $item = Slim::Schema->objectForUrl({
				'url'      => $url,
				'create'   => 1,
			});
			$params->{'id'} = $item->id;
		}
		elsif (defined $url) {
			$params->{'url'} = $volatileUrl || $url;
		}
		elsif ($folderId) {
			$params->{'id'} = $folderId;
			$volatileUrl = 1 if $folderId < 0;
		}
		# no path given and in volatile mode - we've been called for the root during a scan
		elsif ($volatileUrl && scalar @$mediaDirs) {
			my $url = $mediaDirs->[0];

			if (!Slim::Music::Info::isURL($url)) {
				$url = Slim::Utils::Misc::fileURLFromPath($url);
			}
			$url =~ s/^file/tmp/;

			my $item = Slim::Schema->objectForUrl({
				'url'      => $url,
				'create'   => 1,
			});

			$params->{'id'} = $item->id;
		}
		elsif (scalar @$mediaDirs) {
			$params->{'url'} = $mediaDirs->[0];
		}

		if ($type) {
			$params->{typeRegEx} = Slim::Music::Info::validTypeExtensions($type);

			# if we need the artwork, we'll have to look them up in their own tables for videos/images
			if (main::LIBRARY && $tags && $type eq 'image') {
				$sql = 'SELECT * FROM images WHERE url = ?';
			}
			elsif (main::LIBRARY && $tags && $type eq 'video') {
				$sql = 'SELECT * FROM videos WHERE url = ?';
			}
		}
	
		# if this is a follow up query ($index > 0), try to read from the cache
		my $cacheKey = md5_hex(($params->{url} || $params->{id} || '') . $type . (main::LIBRARY ? Slim::Music::VirtualLibraries->getLibraryIdForClient($client) : ''));
		if (my $cachedItem = $bmfCache{$cacheKey}) {
			$items       = $cachedItem->{items};
			$topLevelObj = $cachedItem->{topLevelObj};
			$count       = $cachedItem->{count};
			
			# bump the timeout on the cache
			$bmfCache{$cacheKey} = $cachedItem;
		}
		else {
			my $files;
			($topLevelObj, $files, $count) = Slim::Utils::Misc::findAndScanDirectoryTree($params);

			$topPath = blessed($topLevelObj) ? $topLevelObj->path : '';
			
			my $sth = !$volatileUrl && (!$type || $type eq 'audio') ? Slim::Schema->dbh->prepare_cached('SELECT content_type FROM tracks WHERE url = ?') : undef;
			
			my $chunkCount = 0;
			$items = [ grep {
				main::idleStreams() unless ++$chunkCount % 20;
				$filter->($_, $topPath, $sth);
			} @$files ];

			$sth->finish() if $sth;

			$count = scalar @$items;
		
			# cache results in case the same folder is queried again shortly 
			# should speed up Jive BMF, as only the first chunk needs to run the full loop above
			$bmfCache{$cacheKey} = {
				items       => $items,
				topLevelObj => $topLevelObj,
				count       => $count,
			} if scalar @$items > 10 && ($params->{url} || $params->{id});
		}

		if ($want_top) {
			$items = [ $topLevelObj->url ];
			$count = 1;
		}

		# create filtered data
		$topPath = $topLevelObj->path if blessed($topLevelObj);
	}

	# now build the result

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {

		my $loopname = 'folder_loop';
		my $chunkCount = 0;

		my $sth = $sql ? Slim::Schema->dbh->prepare_cached($sql) : undef;

		my $x = $start-1;
		for my $filename (@$items[$start..$end]) {

			my $id;
			$realName = '';
			my $item = $filter->($filename, $topPath) || '';

			if ( (!blessed($item) || !$item->can('content_type')) 
				&& (!$params->{typeRegEx} || $filename !~ $params->{typeRegEx}) )
			{
				logError("Invalid item found in pre-filtered list - this should not happen! ($topPath -> $filename)");
				$count--;
				next;
			}
			elsif (blessed($item)) {
				$id = $item->id();
			}

			$x++;
			main::idleStreams() unless $x % 20;
			
			$id += 0;

			my $url = $item->url;
			
			# if we're dealing with temporary items, store the real URL in $volatileUrl
			if ($volatileUrl) {
				$volatileUrl = $url;
				$volatileUrl =~ s/^tmp/file/;
			}
			
			$realName ||= Slim::Music::Info::fileName($volatileUrl || $url);
			
			# volatile folder in browse root?
			my $isDir;
			if (!$realName || Slim::Music::Info::isVolatileURL($realName) && $id < 0) {
				my $url2 = $url;
				$url2 =~ s/^tmp/file/;
				$realName = '[' . Slim::Music::Info::fileName($url2) . ']';
				$isDir = Slim::Music::Info::isDir($url2);
			}

			my $textKey = uc(substr($realName, 0, 1));
			
			$request->addResultLoop($loopname, $chunkCount, 'id', $id);
			$request->addResultLoop($loopname, $chunkCount, 'filename', $realName);
		
			if ($isDir || Slim::Music::Info::isDir($volatileUrl || $item)) {
				$request->addResultLoop($loopname, $chunkCount, 'type', 'folder');
			} elsif (Slim::Music::Info::isPlaylist($volatileUrl || $item)) {
				$request->addResultLoop($loopname, $chunkCount, 'type', 'playlist');
			} elsif ($params->{typeRegEx} && $filename =~ $params->{typeRegEx}) {
				$request->addResultLoop($loopname, $chunkCount, 'type', $type);
			
				# only do this for images & videos where we'll need the hash for the artwork
				if (main::LIBRARY && $sth) {
					$sth->execute($volatileUrl || $url);
					
					my $itemDetails = $sth->fetchrow_hashref;
					
					if ($type eq 'video') {
						foreach my $k (keys %$itemDetails) {
							$itemDetails->{"videos.$k"} = $itemDetails->{$k} unless $k =~ /^videos\./;
						}
						
						_videoData($request, $loopname, $chunkCount, $tags, $itemDetails);
					}
					
					elsif ($type eq 'image') {
						utf8::decode( $itemDetails->{'images.title'} ) if exists $itemDetails->{'images.title'};
						utf8::decode( $itemDetails->{'images.album'} ) if exists $itemDetails->{'images.album'};

						foreach my $k (keys %$itemDetails) {
							$itemDetails->{"images.$k"} = $itemDetails->{$k} unless $k =~ /^images\./;
						}
						_imageData($request, $loopname, $chunkCount, $tags, $itemDetails);
					}
	
				}
				
			} elsif (Slim::Music::Info::isSong($volatileUrl || $item) && $type ne 'video') {
				$request->addResultLoop($loopname, $chunkCount, 'type', 'track');
			} elsif (-d Slim::Utils::Misc::pathFromMacAlias($volatileUrl || $url)) {
				$request->addResultLoop($loopname, $chunkCount, 'type', 'folder');
			} else {
				$request->addResultLoop($loopname, $chunkCount, 'type', 'unknown');
			}

			$tags =~ /c/ && $request->addResultLoop($loopname, $chunkCount, 'coverid', $item->coverid);
			$tags =~ /d/ && $request->addResultLoop($loopname, $chunkCount, 'duration', $item->duration);
			$tags =~ /s/ && $request->addResultLoop($loopname, $chunkCount, 'textkey', $textKey);
			$tags =~ /u/ && $request->addResultLoop($loopname, $chunkCount, 'url', $url);
			$tags =~ /t/ && $request->addResultLoop($loopname, $chunkCount, 'title', $realName);

			# XXX - This is not in line with other queries requesting the content type, 
			#       where the latter would be returned as the "type" value. But I don't
			#       want to break backwards compatibility, therefore returning 'ct' instead.
			$tags =~ /o/ && $request->addResultLoop($loopname, $chunkCount, 'ct', $item->content_type);

			$chunkCount++;
		}
		
		$sth->finish() if $sth;
	}

	$request->addResult('count', $count);
	
	if (main::LIBRARY && !$volatileUrl) {
		# we might have changed - flush to the db to be in sync.
		$topLevelObj->update if blessed($topLevelObj);

		# this is not always needed, but if only single tracks were added through BMF,
		# the caches would get out of sync
		Slim::Schema->wipeCaches;
		Slim::Music::Import->setLastScanTime();
	}
	
	if ( $highmem ) {
		# don't grow infinitely - reset after 512 entries
		if ( scalar keys %$bmfUrlForName > 512 ) {
			$bmfUrlForName = {};
		}
		
		$cache->{bmfUrlForName} = $bmfUrlForName;
	}
	
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
		_addPlayersLoop($request, $start, $end, \@prefs);
	}
	
	$request->setStatusDone();
}

sub _addPlayersLoop {
	my ($request, $start, $end, $savePrefs) = @_;
	
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
			if (defined $eachclient->sequenceNumber()) {
				$request->addResultLoop('players_loop', $cnt,
					'seq_no', $eachclient->sequenceNumber());
			}
			$request->addResultLoop('players_loop', $cnt, 
				'model', $eachclient->model(1));
			$request->addResultLoop('players_loop', $cnt, 
				'modelname', $eachclient->modelName());
			$request->addResultLoop('players_loop', $cnt, 
				'power', $eachclient->power() ? 1 : 0);
			$request->addResultLoop('players_loop', $cnt, 
				'isplaying', $eachclient->isPlaying() ? 1 : 0);
			$request->addResultLoop('players_loop', $cnt, 
				'displaytype', $eachclient->vfdmodel())
				unless ($eachclient->model() eq 'http');
			$request->addResultLoop('players_loop', $cnt, 
				'isplayer', $eachclient->isPlayer() || 0);
			$request->addResultLoop('players_loop', $cnt, 
				'canpoweroff', $eachclient->canPowerOff());
			$request->addResultLoop('players_loop', $cnt, 
				'connected', ($eachclient->connected() || 0));
			$request->addResultLoop('players_loop', $cnt,
				'firmware', $eachclient->revision());
			$request->addResultLoop('players_loop', $cnt, 
				'player_needs_upgrade', 1)
				if ($eachclient->needsUpgrade());
			$request->addResultLoop('players_loop', $cnt,
				'player_is_upgrading', 1)
				if ($eachclient->isUpgrading());

			for my $pref (@$savePrefs) {
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

sub playlistPlaylistsinfoQuery {
	my $request = shift;

	# check this is the correct query
	if ($request->isNotQuery([['playlist'], ['playlistsinfo']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();

	my $playlistObj = $client->currentPlaylist();
	
	if (blessed($playlistObj)) {
		if ($playlistObj->can('id')) {
			$request->addResult("id", $playlistObj->id());
		}

		$request->addResult("name", $playlistObj->title());
				
		$request->addResult("modified", $client->currentPlaylistModified());

		$request->addResult("url", $playlistObj->url());
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


sub prefQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['pref']]) && $request->isNotQuery([['playerpref']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client;

	if ($request->isQuery([['playerpref']])) {
		
		$client = $request->client();
		
		unless ($client) {			
			$request->setStatusBadDispatch();
			return;
		}
	}

	# get the parameters
	my $prefName = $request->getParam('_prefname');

	# split pref name from namespace: name.space.pref:
	my $namespace = 'server';
	if ($prefName =~ /^(.*?):(.+)$/) {
		$namespace = $1;
		$prefName = $2;
	}
	
	if (!defined $prefName || !defined $namespace) {
		$request->setStatusBadParams();
		return;
	}

	$request->addResult('_p2', $client
		? preferences($namespace)->client($client)->get($prefName)
		: preferences($namespace)->get($prefName)
	);
	
	$request->setStatusDone();
}


sub prefValidateQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['pref'], ['validate']]) && $request->isNotQuery([['playerpref'], ['validate']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $client = $request->client();

	# get our parameters
	my $prefName = $request->getParam('_prefname');
	my $newValue = $request->getParam('_newvalue');

	# split pref name from namespace: name.space.pref:
	my $namespace = 'server';
	if ($prefName =~ /^(.*?):(.+)$/) {
		$namespace = $1;
		$prefName = $2;
	}
	
	if (!defined $prefName || !defined $namespace || !defined $newValue) {
		$request->setStatusBadParams();
		return;
	}

	$request->addResult('valid', 
		($client
			? preferences($namespace)->client($client)->validate($prefName, $newValue)
			: preferences($namespace)->validate($prefName, $newValue)
		) 
		? 1 : 0
	);
	
	$request->setStatusDone();
}


sub readDirectoryQuery {
	my $request = shift;

	main::INFOLOG && $log->info("readDirectoryQuery");

	# check this is the correct query.
	if ($request->isNotQuery([['readdirectory']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $index      = $request->getParam('_index');
	my $quantity   = $request->getParam('_quantity');
	my $folder     = $request->getParam('folder');
	my $filter     = $request->getParam('filter');

	use File::Spec::Functions qw(catdir);
	my @fsitems;		# raw list of items 
	my %fsitems;		# meta data cache

	if (main::ISWINDOWS && $folder eq '/') {
		@fsitems = sort map {
			$fsitems{"$_"} = {
				d => 1,
				f => 0
			};
			"$_"; 
		} Slim::Utils::OS::Win32->getDrives();
		$folder = '';
	}
	else {
		$filter ||= '';

		my $filterRE = qr/./ unless ($filter eq 'musicfiles');

		# get file system items in $folder
		@fsitems = Slim::Utils::Misc::readDirectory(catdir($folder), $filterRE);
		map { 
			$fsitems{$_} = {
				d => -d catdir($folder, $_),
				f => -f _
			}
		} @fsitems;
	}

	if ($filter eq 'foldersonly') {
		@fsitems = grep { $fsitems{$_}->{d} } @fsitems;
	}

	elsif ($filter eq 'filesonly') {
		@fsitems = grep { $fsitems{$_}->{f} } @fsitems;
	}

	# return all folders plus files of type
	elsif ($filter =~ /^filetype:(.*)/) {
		my $filterRE = qr/(?:\.$1)$/i;
		@fsitems = grep { $fsitems{$_}->{d} || $_ =~ $filterRE } @fsitems;
	}

	# search anywhere within path/filename
	elsif ($filter && $filter !~ /^(?:filename|filetype):/) {
		@fsitems = grep { catdir($folder, $_) =~ /$filter/i } @fsitems;
	}

	my $count = @fsitems;
	$count += 0;
	$request->addResult('count', $count);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {
		my $idx = $start;
		my $cnt = 0;

		if (scalar(@fsitems)) {
			# sort folders < files
			@fsitems = sort { 
				if ($fsitems{$a}->{d}) {
					if ($fsitems{$b}->{d}) { uc($a) cmp uc($b) }
					else { -1 }
				}
				else {
					if ($fsitems{$b}->{d}) { 1 }
					else { uc($a) cmp uc($b) }
				}
			} @fsitems;

			my $path;
			for my $item (@fsitems[$start..$end]) {
				$path = ($folder ? catdir($folder, $item) : $item);

				my $name = $item;
				my $decodedName;

				# display full name if we got a Windows 8.3 file name
				if (main::ISWINDOWS && $name =~ /~\d/) {
					$decodedName = Slim::Music::Info::fileName($path);
				} else {
					$decodedName = Slim::Utils::Unicode::utf8decode_locale($name);
				}

				$request->addResultLoop('fsitems_loop', $cnt, 'path', Slim::Utils::Unicode::utf8decode_locale($path));
				$request->addResultLoop('fsitems_loop', $cnt, 'name', $decodedName);
				
				$request->addResultLoop('fsitems_loop', $cnt, 'isfolder', $fsitems{$item}->{d});

				$idx++;
				$cnt++;
			}	
		}
	}

	$request->setStatusDone();	
}


# the filter function decides, based on a notified request, if the serverstatus
# query must be re-executed.
sub serverstatusQuery_filter {
	my $self = shift;
	my $request = shift;
	
	# we want to know about clients going away as soon as possible
	if ($request->isCommand([['client'], ['forget']]) || $request->isCommand([['connect']])) {
		return 1;
	}
	
	# we want to know about rescan and all client notifs, as well as power on/off
	# FIXME: wipecache and rescan are synonyms...
	if ($request->isCommand([['wipecache', 'rescan', 'client', 'power']])) {
		return 1.3;
	}
	
	# FIXME: prefset???
	# we want to know about any pref in our array
	if (defined(my $prefsPtr = $self->privateData()->{'server'})) {
		if ($request->isCommand([['pref']])) {
			if (defined(my $reqpref = $request->getParam('_prefname'))) {
				if (grep($reqpref, @{$prefsPtr})) {
					return 1.3;
				}
			}
		}
	}
	if (defined(my $prefsPtr = $self->privateData()->{'player'})) {
		if ($request->isCommand([['playerpref']])) {
			if (defined(my $reqpref = $request->getParam('_prefname'))) {
				if (grep($reqpref, @{$prefsPtr})) {
					return 1.3;
				}
			}
		}
	}
	if ($request->isCommand([['name']])) {
		return 1.3;
	}
	
	return 0;
}


sub serverstatusQuery {
	my $request = shift;
	
	main::INFOLOG && $log->debug("serverstatusQuery()");

	# check this is the correct query
	if ($request->isNotQuery([['serverstatus']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	if ( main::LIBRARY && Slim::Schema::hasLibrary() ) {
		if (Slim::Music::Import->stillScanning()) {
			$request->addResult('rescan', "1");
			if (my $p = Slim::Schema->rs('Progress')->search({ 'type' => 'importer', 'active' => 1 })->first) {

				# remove leading path information from the progress name
				my $name = $p->name;
				$name =~ s/(.*)\|//;
	
				$request->addResult('progressname', $request->string($name . '_PROGRESS'));
				$request->addResult('progressdone', $p->done);
				$request->addResult('progresstotal', $p->total);
			}
		}
		else {
			$request->addResult( lastscan => Slim::Music::Import->lastScanTime() );

			# XXX This needs to be fixed, failures are not reported
			#if ($p[-1]->name eq 'failure') {
			#	_scanFailed($request, $p[-1]->info);
			#}
		}
	}
	
	# add version
	$request->addResult('version', $::VERSION);

	# add server_uuid
	$request->addResult('uuid', $prefs->get('server_uuid'));
	
	if ( my $mac = Slim::Utils::OSDetect->getOS()->getMACAddress() ) {
		$request->addResult('mac', $mac);
	}

	if ( main::LIBRARY && Slim::Schema::hasLibrary() ) {
		# add totals
		my $totals = Slim::Schema->totals($request->client);
		
		$request->addResult("info total albums", $totals->{album});
		$request->addResult("info total artists", $totals->{contributor});
		$request->addResult("info total genres", $totals->{genre});
		$request->addResult("info total songs", $totals->{track});
		$request->addResult("info total duration", Slim::Schema->totalTime());
	}

	my %savePrefs;
	if (defined(my $pref_list = $request->getParam('prefs'))) {

		# split on commas
		my @prefs = split(/,/, $pref_list);
		$savePrefs{'server'} = \@prefs;
	
		for my $pref (@{$savePrefs{'server'}}) {
			if (defined(my $value = $prefs->get($pref))) {
				$request->addResult($pref, $value);
			}
		}
	}
	if (defined(my $pref_list = $request->getParam('playerprefs'))) {

		# split on commas
		my @prefs = split(/,/, $pref_list);
		$savePrefs{'player'} = \@prefs;
		
	}


	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');

	my $count = Slim::Player::Client::clientCount();
	$count += 0;

	$request->addResult('player count', $count);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {
		_addPlayersLoop($request, $start, $end, $savePrefs{'player'});
	}

	if (!main::NOMYSB) {
		# return list of players connected to SN
		my @sn_players = Slim::Networking::SqueezeNetwork::Players->get_players();
	
		$count = scalar @sn_players || 0;
	
		$request->addResult('sn player count', $count);
	
		($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);
	
		if ($valid) {
	
			my $sn_cnt = 0;
				
			for my $player ( @sn_players ) {
				$request->addResultLoop(
					'sn_players_loop', $sn_cnt, 'id', $player->{id}
				);
				
				$request->addResultLoop( 
					'sn_players_loop', $sn_cnt, 'name', $player->{name}
				);
				
				$request->addResultLoop(
					'sn_players_loop', $sn_cnt, 'playerid', $player->{mac}
				);
				
				$request->addResultLoop(
					'sn_players_loop', $sn_cnt, 'model', $player->{model}
				);
					
				$sn_cnt++;
			}
		}
	}

	# return list of players connected to other servers
	my $other_players = Slim::Networking::Discovery::Players::getPlayerList();

	$count = scalar keys %{$other_players} || 0;

	$request->addResult('other player count', $count);

	($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

	if ($valid) {

		my $other_cnt = 0;
			
		for my $player ( keys %{$other_players} ) {
			$request->addResultLoop(
				'other_players_loop', $other_cnt, 'playerid', $player
			);

			$request->addResultLoop( 
				'other_players_loop', $other_cnt, 'name', $other_players->{$player}->{name}
			);

			$request->addResultLoop(
				'other_players_loop', $other_cnt, 'model', $other_players->{$player}->{model}
			);

			$request->addResultLoop(
				'other_players_loop', $other_cnt, 'server', $other_players->{$player}->{server}
			);

			$request->addResultLoop(
				'other_players_loop', $other_cnt, 'serverurl', 
					Slim::Networking::Discovery::Server::getWebHostAddress($other_players->{$player}->{server})
			);

			$other_cnt++;
		}
	}
	
	# manage the subscription
	if (defined(my $timeout = $request->getParam('subscribe'))) {
	
		# store the prefs array as private data so our filter above can find it back
		$request->privateData(\%savePrefs);
		
		# register ourselves to be automatically re-executed on timeout or filter
		$request->registerAutoExecute($timeout, \&serverstatusQuery_filter);
	}
	
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
		if ( defined($prefname) && ( $prefname =~ /^(?:alarmSnoozeSeconds|digitalVolumeControl|libraryId)$/ ) ) {
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
	if (!defined($client)) {
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

	if ( main::LIBRARY && Slim::Music::Import->stillScanning() ) {
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
	
	if ( main::LIBRARY && (my $library_id = Slim::Music::VirtualLibraries->getLibraryIdForClient($client)) ) {
		$request->addResult("library_id", $library_id);
		$request->addResult("library_name", Slim::Music::VirtualLibraries->getNameForId($library_id, $client));
	}

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

	# send client pref for digital volume control
	my $digitalVolumeControl = $prefs->client($client)->get('digitalVolumeControl');
	if ( defined($digitalVolumeControl) ) {
		$request->addResult('digital_volume_control', $digitalVolumeControl + 0);
	}
	
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
		my $tags     = $request->getParam('tags') || '';
		my $index    = $request->getParam('_index');
		my $quantity = $request->getParam('_quantity');
		
		my $loop = $menuMode ? 'item_loop' : 'playlist_loop';
		my $totalOnly;
		
		if ( $menuMode ) {
			# Set required tags for menuMode
			$tags = 'aAlKNcxJ';
		}
		# DD - total playtime for the current playlist, nothing else returned
		elsif ( $tags =~ /DD/ ) {
			$totalOnly = 1;
			$tags = 'd';
			$index = 0;
			$quantity = $songCount;
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
		
		my $track;
		
		if (!$totalOnly) {
			$track = Slim::Player::Playlist::song($client, $playlist_cur_index, $refreshTrack);
	
			if ($track->remote) {
				$tags .= "B" unless $totalOnly; # include button remapping
				my $metadata = _songData($request, $track, $tags);
				$request->addResult('remoteMeta', $metadata);
			}
		}

		# if repeat is 1 (song) and modecurrent, then show the current song
		if ($modecurrent && ($repeat == 1) && $quantity && !$totalOnly) {

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
				
				my (@tracks, @trackIds);
				foreach my $track ( Slim::Player::Playlist::songs($client, $start, $end) ) {
					next unless defined $track;
					
					if ( $track->remote ) {
						push @tracks, $track;
					}
					elsif ( main::LIBRARY ) {
						push @tracks, $track->id;
						push @trackIds, $tracks[-1];
					}
				}
				
				# get hash of tagged data for all tracks
				my $songData = _getTagDataForTracks( $tags, {
					trackIds => \@trackIds,
				} ) if main::LIBRARY && scalar @trackIds;
				
				# no need to use Tie::IxHash to preserve order when we return JSON Data
				my $fast = ($totalOnly || ($request->source && $request->source =~ m{/slim/request\b|JSONRPC|internal})) ? 1 : 0;

				# Slice and map playlist to get only the requested IDs
				$idx = $start;
				my $totalDuration = 0;
				
				foreach( @tracks ) {
					# Use songData for track, if remote use the object directly
					my $data = ref $_ ? $_ : $songData->{$_};

					# 17352 - when the db is not fully populated yet, and a stored player playlist
					# references a track not in the db yet, we can fail
					next if !$data;

					if ($totalOnly) {
						my $trackData = _songData($request, $data, $tags, $fast);
						$totalDuration += $trackData->{duration};
					}
					elsif ($menuMode) {
						_addJiveSong($request, $loop, $count, $idx, $data);
						# add clear and save playlist items at the bottom
						if ( ($idx+1)  == $songCount) {
							_addJivePlaylistControls($request, $loop, $count);
						}
					}
					else {
						_addSong(	$request, $loop, $count, 
									$data, $tags,
									'playlist index', $idx, $fast
								);
					}

					$count++;
					$idx++;
					
					# give peace a chance...
					# This is need much less now that the DB query is done ahead of time
					main::idleStreams() if ! ($count % 20);
				}
				
				if ($totalOnly) {
					$request->addResult('playlist duration', $totalDuration || 0);
				}
				
				# we don't do that in menu mode!
				if (!$menuMode && !$totalOnly) {
				
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

sub songinfoQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['songinfo']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $tags  = 'abcdefghijJklmnopqrstvwxyzBCDEFHIJKLMNOQRTUVWXY'; # all letter EXCEPT u, A & S, G & P, Z
	my $track;

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');
	my $url	     = $request->getParam('url');
	my $trackID  = $request->getParam('track_id');
	my $tagsprm  = $request->getParam('tags');
	
	if (!defined $trackID && !defined $url) {
		$request->setStatusBadParams();
		return;
	}

	# did we have override on the defaults?
	$tags = $tagsprm if defined $tagsprm;

	# find the track
	if (defined $trackID){

		$track = Slim::Schema->find('Track', $trackID);

	} else {

		if ( defined $url ){

			$track = Slim::Schema->objectForUrl($url);
		}
	}
	
	# now build the result
	
	if (main::LIBRARY && Slim::Music::Import->stillScanning()) {
		$request->addResult("rescan", 1);
	}

	if (blessed($track) && $track->can('id')) {

		my $trackId = $track->id();
		$trackId += 0;

		my $hashRef = _songData($request, $track, $tags);
		my $count = scalar (keys %{$hashRef});

		$count += 0;

		my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

		my $loopname = 'songinfo_loop';
		my $chunkCount = 0;

		if ($valid) {

			# this is where we construct the nowplaying menu
			my $idx = 0;
	
			while (my ($key, $val) = each %{$hashRef}) {
				if ($idx >= $start && $idx <= $end) {
	
					$request->addResultLoop($loopname, $chunkCount, $key, $val);
	
					$chunkCount++;					
				}
				$idx++;
			}
		}
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


sub versionQuery {
	my $request = shift;

	# check this is the correct query.
	if ($request->isNotQuery([['version']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no params for the version query

	$request->addResult('_version', $::VERSION);
	
	$request->setStatusDone();
}

################################################################################
# Special queries
################################################################################

=head2 dynamicAutoQuery( $request, $query, $funcptr, $data )

 This function is a helper function for any query that needs to poll enabled
 plugins. In particular, this is used to implement the CLI radios query,
 that returns all enabled radios plugins. This function is best understood
 by looking as well in the code used in the plugins.
 
 Each plugins does in initPlugin (edited for clarity):
 
    $funcptr = addDispatch(['radios'], [0, 1, 1, \&cli_radiosQuery]);
 
 For the first plugin, $funcptr will be undef. For all the subsequent ones
 $funcptr will point to the preceding plugin cli_radiosQuery() function.
 
 The cli_radiosQuery function looks like:
 
    sub cli_radiosQuery {
      my $request = shift;
      
      my $data = {
         #...
      };
 
      dynamicAutoQuery($request, 'radios', $funcptr, $data);
    }
 
 The plugin only defines a hash with its own data and calls dynamicAutoQuery.
 
 dynamicAutoQuery will call each plugin function recursively and add the
 data to the request results. It checks $funcptr for undefined to know if
 more plugins are to be called or not.
 
=cut

sub dynamicAutoQuery {
	my $request = shift;                       # the request we're handling
	my $query   = shift || return;             # query name
	my $funcptr = shift;                       # data returned by addDispatch
	my $data    = shift || return;             # data to add to results

	# check this is the correct query.
	if ($request->isNotQuery([[$query]])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity') || 0;
	my $sort     = $request->getParam('sort');
	my $menu     = $request->getParam('menu');

	my $menuMode = defined $menu;

	# we have multiple times the same resultset, so we need a loop, named
	# after the query name (this is never printed, it's just used to distinguish
	# loops in the same request results.
	my $loop = $menuMode?'item_loop':$query . 's_loop';

	# if the caller asked for results in the query ("radios 0 0" returns 
	# immediately)
	if ($quantity) {

		# add the data to the results
		my $cnt = $request->getResultLoopCount($loop) || 0;
		
		if ( ref $data eq 'HASH' && scalar keys %{$data} ) {
			$data->{weight} = $data->{weight} || 1000;
			$request->setResultLoopHash($loop, $cnt, $data);
		}
		
		# more to jump to?
		# note we carefully check $funcptr is not a lemon
		if (defined $funcptr && ref($funcptr) eq 'CODE') {
			
			eval { &{$funcptr}($request) };
	
			# arrange for some useful logging if we fail
			if ($@) {

				logError("While trying to run function coderef: [$@]");
				$request->setStatusBadDispatch();
				$request->dump('Request');

			}
		}
		
		# $funcptr is undefined, we have everybody, now slice & count
		else {
			
			# sort if requested to do so
			if ($sort) {
				$request->sortResultLoop($loop, $sort);
			}
			
			# slice as needed
			my $count = $request->getResultLoopCount($loop);
			$request->sliceResultLoop($loop, $index, $quantity);
			$request->addResult('offset', $request->getParam('_index')) if $menuMode;
			$count += 0;
			$request->setResultFirst('count', $count);
			
			# don't forget to call that to trigger notifications, if any
			$request->setStatusDone();
		}
	}
	else {
		$request->setStatusDone();
	}
}

################################################################################
# Helper functions
################################################################################

sub _addSong {
	my $request   = shift; # request
	my $loop      = shift; # loop
	my $index     = shift; # loop index
	my $pathOrObj = shift; # song path or object, or hash from titlesQuery
	my $tags      = shift; # tags to use
	my $prefixKey = shift; # prefix key, if any
	my $prefixVal = shift; # prefix value, if any   
	my $fast      = shift;
	
	# get the hash with the data	
	my $hashRef = _songData($request, $pathOrObj, $tags, $fast);
	
	# add the prefix in the first position, use a fancy feature of
	# Tie::LLHash
	if (defined $prefixKey && defined $hashRef) {
		if ($fast) {
			$hashRef->{$prefixKey} = $prefixVal;
		}
		else {
			(tied %{$hashRef})->Unshift($prefixKey => $prefixVal);
		}
	}
	
	# add it directly to the result loop
	$request->setResultLoopHash($loop, $index, $hashRef);
}

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

	$request->addResultLoop($loop, $count, 'text', $text);
	$request->addResultLoop($loop, $count, 'icon-id', '/html/images/playlistclear.png');
	$request->addResultLoop($loop, $count, 'offset', 0);
	$request->addResultLoop($loop, $count, 'count', 2);
	$request->addResultLoop($loop, $count, 'item_loop', \@clear_playlist);

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

	# Save Playlist item
	$text = $client->string('SAVE_PLAYLIST');
	$request->addResultLoop($loop, $count, 'text', $text);
	$request->addResultLoop($loop, $count, 'icon-id', '/html/images/playlistsave.png');
	$request->addResultLoop($loop, $count, 'input', $input);
	$request->addResultLoop($loop, $count, 'actions', $actions);
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
		'aAlKNcxJ',			# tags needed for our entities
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
	my $iconId = $songData->{coverid} || $songData->{artwork_track_id};
	
	if ( defined($songData->{artwork_url}) ) {
		$request->addResultLoop( $loop, $count, 'icon', proxiedImage($songData->{artwork_url}) );
	}
	elsif ( defined $iconId ) {
		$request->addResultLoop($loop, $count, 'icon-id', proxiedImage($iconId));
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


my %tagMap = (
	# Tag    Tag name             Token            Track method         Track field
	#------------------------------------------------------------------------------
	  'u' => ['url',              'LOCATION',      'url'],              #url
	  'o' => ['type',             'TYPE',          'content_type'],     #content_type
	                                                                    #titlesort 
	                                                                    #titlesearch 
	  'a' => ['artist',           'ARTIST',        'artistName'],       #->contributors
	  'e' => ['album_id',         '',              'albumid'],          #album 
	  'l' => ['album',            'ALBUM',         'albumname'],        #->album.title
	  't' => ['tracknum',         'TRACK',         'tracknum'],         #tracknum
	  'n' => ['modificationTime', 'MODTIME',       'modificationTime'], #timestamp
	  'D' => ['addedTime',        'ADDTIME',       'addedTime'],        #added_time
	  'U' => ['lastUpdated',      'UPDTIME',       'lastUpdated'],      #updated_time
	  'f' => ['filesize',         'FILELENGTH',    'filesize'],         #filesize
	                                                                    #tag 
	  'i' => ['disc',             'DISC',          'disc'],             #disc
	  'j' => ['coverart',         'SHOW_ARTWORK',  'coverArtExists'],   #cover
	  'x' => ['remote',           '',              'remote'],           #remote 
	                                                                    #audio 
	                                                                    #audio_size 
	                                                                    #audio_offset
	  'y' => ['year',             'YEAR',          'year'],             #year
	  'd' => ['duration',         'LENGTH',        'secs'],             #secs
	                                                                    #vbr_scale 
	  'r' => ['bitrate',          'BITRATE',       'prettyBitRate'],    #bitrate
	  'T' => ['samplerate',       'SAMPLERATE',    'samplerate'],       #samplerate 
	  'I' => ['samplesize',       'SAMPLESIZE',    'samplesize'],       #samplesize 
	  'H' => ['channels',         'CHANNELS',      'channels'],         #channels 
	  'F' => ['dlna_profile',     'DLNA_PROFILE',  'dlna_profile'],     #dlna_profile
	                                                                    #block_alignment
	                                                                    #endian 
	  'm' => ['bpm',              'BPM',           'bpm'],              #bpm
	  'v' => ['tagversion',       'TAGVERSION',    'tagversion'],       #tagversion
	# 'z' => ['drm',              '',              'drm'],              #drm
	  'M' => ['musicmagic_mixable', '',            'musicmagic_mixable'], #musicmagic_mixable
	                                                                    #musicbrainz_id 
	                                                                    #lastplayed 
	                                                                    #lossless 
	  'w' => ['lyrics',           'LYRICS',        'lyrics'],           #lyrics 
	  'R' => ['rating',           'RATING',        'rating'],           #rating 
	  'O' => ['playcount',        'PLAYCOUNT',     'playcount'],        #playcOunt 
	  'Y' => ['replay_gain',      'REPLAYGAIN',    'replay_gain'],      #replay_gain 
	                                                                    #replay_peak

	  'c' => ['coverid',          'COVERID',       'coverid'],          # coverid
	  'K' => ['artwork_url',      '',              'coverurl'],         # artwork URL, not in db
	  'B' => ['buttons',          '',              'buttons'],          # radio stream special buttons
	  'L' => ['info_link',        '',              'info_link'],        # special trackinfo link for i.e. Pandora
	  'N' => ['remote_title'],                                          # remote stream title


	# Tag    Tag name              Token              Relationship     Method          Track relationship
	#--------------------------------------------------------------------------------------------------
	  's' => ['artist_id',         '',                'artist',        'id'],           #->contributors
	  'A' => ['<role>',            '<ROLE>',          'contributors',  'name'],         #->contributors[role].name
	  'S' => ['<role>_ids',        '',                'contributors',  'id'],           #->contributors[role].id
                                                                            
	  'q' => ['disccount',         '',                'album',         'discc'],        #->album.discc
	  'J' => ['artwork_track_id',  'COVERART',        'album',         'artwork'],      #->album.artwork
	  'C' => ['compilation',       'COMPILATION',     'album',         'compilation'],  #->album.compilation
	  'X' => ['album_replay_gain', 'ALBUMREPLAYGAIN', 'album',         'replay_gain'],  #->album.replay_gain
                                                                            
	  'g' => ['genre',             'GENRE',           'genre',         'name'],         #->genre_track->genre.name
	  'p' => ['genre_id',          '',                'genre',         'id'],           #->genre_track->genre.id
	  'G' => ['genres',            'GENRE',           'genres',        'name'],         #->genre_track->genres.name
	  'P' => ['genre_ids',         '',                'genres',        'id'],           #->genre_track->genres.id
                                                                            
	  'k' => ['comment',           'COMMENT',         'comment'],                       #->comment_object

);

# Map tag -> column to avoid a huge if-else structure
my %colMap = (
	g => 'genres.name',
	G => 'genres',
	p => 'genres.id',
	P => 'genre_ids',
	a => 'contributors.name',
	's' => 'contributors.id',
	l => 'albums.title',
	e => 'tracks.album',
	d => 'tracks.secs',
	i => 'tracks.disc',
	q => 'albums.discc',
	t => 'tracks.tracknum',
	y => 'tracks.year',
	m => 'tracks.bpm',
	M => sub { $_[0]->{'tracks.musicmagic_mixable'} ? 1 : 0 },
	k => 'comment',
	o => 'tracks.content_type',
	v => 'tracks.tagversion',
	r => sub { Slim::Music::Info::getPrettyBitrate( $_[0]->{'tracks.bitrate'}, $_[0]->{'tracks.vbr_scale'} ) },
	f => 'tracks.filesize',
	j => sub { $_[0]->{'tracks.cover'} ? 1 : 0 },
	J => 'albums.artwork',
	n => 'tracks.timestamp',
	F => 'tracks.dlna_profile',
	D => 'tracks.added_time',
	U => 'tracks.updated_time',
	C => sub { $_[0]->{'albums.compilation'} ? 1 : 0 },
	Y => 'tracks.replay_gain',
	X => 'albums.replay_gain',
	R => 'tracks_persistent.rating',
	O => 'tracks_persistent.playcount',
	T => 'tracks.samplerate',
	I => 'tracks.samplesize',
	u => 'tracks.url',
	w => 'tracks.lyrics',
	x => sub { $_[0]->{'tracks.remote'} ? 1 : 0 },
	c => 'tracks.coverid',
	H => 'tracks.channels',
);

sub _songDataFromHash {
	my ( $request, $res, $tags, $fast ) = @_;
	
	my %returnHash;
	
	# define an ordered hash for our results
	tie (%returnHash, "Tie::IxHash") unless $fast;
	
	$returnHash{id}    = $res->{'tracks.id'};
	$returnHash{title} = $res->{'tracks.title'};
	
	my @contributorRoles = Slim::Schema::Contributor->contributorRoles;
	
	# loop so that stuff is returned in the order given...
	for my $tag (split (//, $tags)) {
		my $tagref = $tagMap{$tag} or next;
		
		# Special case for A/S which return multiple keys
		if ( $tag eq 'A' ) {
			# if we don't have an explicit track artist defined, we're going to assume the track's artist was the track artist
			if ( $res->{artist} && $res->{albumartist} && $res->{artist} ne $res->{albumartist}) {
				$res->{trackartist} ||= $res->{artist};
			}

			for my $role ( @contributorRoles ) {
				$role = lc $role;
				if ( defined $res->{$role} ) {
					$returnHash{$role} = $res->{$role};
				}
			}
		}
		elsif ( $tag eq 'S' ) {
			for my $role ( @contributorRoles ) {
				$role = lc $role;
				if ( defined $res->{"${role}_ids"} ) {
					$returnHash{"${role}_ids"} = $res->{"${role}_ids"};
				}
			}
		}
		# eg. the web UI is requesting some tags which are only available for remote tracks,
		# such as 'B' (custom button handler). They would return empty here - ignore them.
		elsif ( my $map = $colMap{$tag} ) {
			my $value = ref $map eq 'CODE' ? $map->($res) : $res->{$map};

			if (defined $value && $value ne '') {
				$returnHash{ $tagref->[0] } = $value;
			}
		}
	}		
	
	return \%returnHash;
}

sub _songData {
	my $request   = shift; # current request object
	my $pathOrObj = shift; # song path or object
	my $tags      = shift; # tags to use
	my $fast      = shift; # don't use Tie::IxHash for performance
	
	if ( ref $pathOrObj eq 'HASH' ) {
		# Hash from direct DBI query in titlesQuery
		return _songDataFromHash($request, $pathOrObj, $tags, $fast);
	}

	# figure out the track object
	my $track     = Slim::Schema->objectForUrl($pathOrObj);

	if (!blessed($track) || !$track->can('id')) {

		logError("Called with invalid object or path: $pathOrObj!");
		
		# For some reason, $pathOrObj may be an id... try that before giving up...
		if ($pathOrObj =~ /^\d+$/) {
			$track = Slim::Schema->find('Track', $pathOrObj);
		}

		if (!blessed($track) || !$track->can('id')) {

			logError("Can't make track from: $pathOrObj!");
			return;
		}
	}
	
	# If we have a remote track, check if a plugin can provide metadata
	my $remoteMeta = {};
	my $isRemote = $track->remote;
	my $url = $track->url;
	
	if ( $isRemote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);
		
		if ( $handler && $handler->can('getMetadataFor') ) {
			# Don't modify source data
			$remoteMeta = Storable::dclone(
				$handler->getMetadataFor( $request->client, $url )
			);
			
			$remoteMeta->{a} = $remoteMeta->{artist};
			$remoteMeta->{A} = $remoteMeta->{artist};
			$remoteMeta->{l} = $remoteMeta->{album};
			$remoteMeta->{i} = $remoteMeta->{disc};
			$remoteMeta->{K} = $remoteMeta->{cover};
			$remoteMeta->{d} = ( $remoteMeta->{duration} || 0 ) + 0;
			$remoteMeta->{Y} = $remoteMeta->{replay_gain};
			$remoteMeta->{o} = $remoteMeta->{type};
			$remoteMeta->{r} = $remoteMeta->{bitrate};
			$remoteMeta->{B} = $remoteMeta->{buttons};
			$remoteMeta->{L} = $remoteMeta->{info_link};
			$remoteMeta->{t} = $remoteMeta->{tracknum};
		}
	}
	
	my $parentTrack;
	if ( my $client = $request->client ) { # Bug 13062, songinfo may be called without a client
		if (my $song = $client->currentSongForUrl($url)) {
			my $t = $song->currentTrack();
			if ($t->url ne $url) {
				$parentTrack = $track;
				$track = $t;
				$isRemote = $track->remote;
			}
		}
	}

	my %returnHash;
	
	# define an ordered hash for our results
	tie (%returnHash, "Tie::IxHash") unless $fast;

	$returnHash{'id'}    = $track->id;
	$returnHash{'title'} = $remoteMeta->{title} || $track->title;
	
	# loop so that stuff is returned in the order given...
	for my $tag (split (//, $tags)) {
		
		my $tagref = $tagMap{$tag} or next;
		
		# special case, remote stream name
		if ($tag eq 'N') {
			if ($parentTrack) {
				$returnHash{$tagref->[0]} = $parentTrack->title;
			} elsif ( $isRemote && !$track->secs && $remoteMeta->{title} && !$remoteMeta->{album} ) {
				if (my $meta = $track->title) {
					$returnHash{$tagref->[0]} = $meta;
				}
			}
		}
		
		# special case for remote flag, since we had to evaluate it anyway
		# only include it if it is true
		elsif ($tag eq 'x' && $isRemote) {
			$returnHash{$tagref->[0]} = 1;
		}
		
		# special case artists (tag A and S)
		elsif ($tag eq 'A' || $tag eq 'S') {
			if ( my $meta = $remoteMeta->{$tag} ) {
				$returnHash{artist} = $meta;
				next;
			}
			
			if ( main::LIBRARY && defined(my $submethod = $tagref->[3]) ) {
				
				my $postfix = ($tag eq 'S')?"_ids":"";
			
				foreach my $type (Slim::Schema::Contributor::contributorRoles()) {
						
					my $key = lc($type) . $postfix;
					my $contributors = $track->contributorsOfType($type) or next;
					my @values = map { $_ = $_->$submethod() } $contributors->all;
					my $value = join(', ', @values);
			
					if (defined $value && $value ne '') {

						# add the tag to the result
						$returnHash{$key} = $value;
					}
				}
			}
		}

		# if we have a method/relationship for the tag
		elsif (defined(my $method = $tagref->[2])) {
			
			my $value;
			my $key = $tagref->[0];
			
			# Override with remote track metadata if available
			if ( defined $remoteMeta->{$tag} ) {
				$value = $remoteMeta->{$tag};
			}
			
			elsif ($method eq '' || !$track->can($method)) {
				next;
			}

			# tag with submethod
			elsif (defined(my $submethod = $tagref->[3])) {

				# call submethod
				if (defined(my $related = $track->$method)) {
					
					# array returned/genre
					if ( blessed($related) && $related->isa('Slim::Schema::ResultSet::Genre')) {
						$value = join(', ', map { $_ = $_->$submethod() } $related->all);
					} elsif ( $isRemote ) {
						$value = $related;
					} else {
						$value = $related->$submethod();
					}
				}
			}
			
			# simple track method
			else {
				$value = $track->$method();
			}
			
			# correct values
			if (($tag eq 'R' || $tag eq 'x') && $value == 0) {
				$value = undef;
			}
			# we might need to proxy the image request to resize it
			elsif ($tag eq 'K' && $value) {
				$value = proxiedImage($value); 
			}
			
			# if we have a value
			if (defined $value && $value ne '') {

				# add the tag to the result
				$returnHash{$key} = $value;
			}
		}
	}

	return \%returnHash;
}

# this is a silly little sub that allows jive cover art to be rendered in a large window
sub showArtwork {

	main::INFOLOG && $log->info("Begin showArtwork Function");
	my $request = shift;

	# get our parameters
	my $id = $request->getParam('_artworkid');

	if ($id =~ /:\/\//) {
		$request->addResult('artworkUrl'  => proxiedImage($id));
	} else {
		$request->addResult('artworkId'  => $id);
	}

	$request->addResult('offset', 0);
	$request->setStatusDone();

}

# Wipe cached data, called after a rescan
sub wipeCaches {
	$cache = {};
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
