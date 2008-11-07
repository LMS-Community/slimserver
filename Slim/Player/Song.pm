package Slim::Player::Song;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use bytes;
use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Schema;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Player::SongStreamController;
use Slim::Player::Pipeline;

use Scalar::Util qw(blessed);

use constant STATUS_READY     => 0;
use constant STATUS_STREAMING => 1;
use constant STATUS_PLAYING   => 2;
use constant STATUS_FAILED    => 3;
use constant STATUS_FINISHED  => 4;

my $log = logger('player.source');
my $prefs = preferences('server');

my $_liveCount = 0;

sub new {
	my ($class, $owner, $index, $seekdata) = @_;

	my $client = $owner->master();
	
	my $objOrUrl = Slim::Player::Playlist::song($client, $index) || return undef;
	
	# Bug: 3390 - reload the track if it's changed.
	my $url      = blessed($objOrUrl) && $objOrUrl->can('url') ? $objOrUrl->url : $objOrUrl;
	
 	my $track    = Slim::Schema->rs('Track')->objectForUrl({
		'url'      => $url,
		'readTags' => 1
	});

	if (!blessed($track) || !$track->can('url')) {
		# Try and create the track if we weren't able to fetch it.
		$track = Slim::Schema->rs('Track')->objectForUrl({
			'url'      => $url,
			'create'   => 1,
			'readTags' => 1
		});
		if (!blessed($track) || !$track->can('url')) {
			logError("Could not find an object for [$objOrUrl]!");
			return undef;
		}
	}
	
	$url = $track->url;

	$log->info("index $index -> $url");

# XXX - thsi test does not work with last.fm - not sure why it was here in the first place
#	if (!Slim::Music::Info::isURL($url)) {
#		logError("[$url] Unrecognized type " . Slim::Music::Info::contentType($url));
#
#		logError($client->string('PROBLEM_CONVERT_FILE'));
#		return undef;
#	}

	my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $url );
	if (!$handler) {
		logError("Could not find handler for $url!");
		return undef;
	}
		
	my $self = {
		index           => $index,
		status          => STATUS_READY,
		owner           => $owner,
		playlist        => Slim::Music::Info::isPlaylist($track, $track->content_type ) ? 1 : 0,
							# 0 = simple stream, 1 = playlist, 2 = repeating stream
		startOffset     => 0,
		handler         => $handler,
		track           => $track,
		streamUrl       => $url,	# May get updated later, either here or in handler
	};
	$self->{'seekdata'} = $seekdata if $seekdata;
	

	bless $self, $class;

	if ($handler->can('isRepeatingStream') && $handler->isRepeatingStream($self)) {
		$self->{'playlist'} = 2;
	}

	$_liveCount++;
	if ($log->is_debug)	{
		$log->debug("live=$_liveCount");
	}
		
	return $self;
}

sub DESTROY {
	my $self = shift;
	$_liveCount--;
	if ($log->is_debug)	{
		$log->debug(sprintf("live=$_liveCount: index=%d, url=%s", $self->{'index'}, $self->{'track'}->url));
	}
}

sub clonePlaylistSong {
	my ($old) = @_;
	
	assert($old->isPlaylist());
	
	my %new = %{$old};
	$new{'status'}        = STATUS_READY;
	$new{'startOffset'}   = 0;
	$new{'seekdata'}      = undef;
	$new{'duration'}      = undef;
	$new{'bitrate'}       = undef;
	$new{'transcoded'}    = undef;
	$new{'canSeek'}       = undef;
	$new{'canSeekError'}  = undef;
	delete $new{'streambitrate'};
		
	my $self = \%new;
	bless $self, ref $old;

	$_liveCount++;
	if ($log->is_debug)	{
		$log->debug("live=$_liveCount");
	}

	my $next = $self->_getNextPlaylistTrack();
	return undef unless $next;
	
	return $self;	
}

sub resetSeekdata {
	$_[0]->{'seekdata'} = undef;
}

sub _getNextPlaylistTrack {
	my ($self) = @_;
	
	if ($self->{'playlist'} == 2) {
		# leave it to the protocol handler
		$self->{'currentTrack'} = $self->{'track'};
		return $self->{'track'};
	}
	
	# Get the next good audio track
	my $playlist = Slim::Schema->rs('Playlist')->objectForUrl( {url => $self->{'track'}->url} );
	$log->debug( "Getting next audio URL from playlist" );	
	my $track = $playlist->getNextEntry($self->{'currentTrack'} ? {after => $self->{'currentTrack'}} : undef);
	if ($track) {
		$self->{'currentTrack'}        = $track;
		$self->{'currentTrackHandler'} = Slim::Player::ProtocolHandlers->handlerForURL($track->url);
		$self->{'streamUrl'}           = $track->url;
		$log->info( "Got next URL from playlist; track is: " . $track->url );	
		
	}
	return $track;
}

sub getNextSong {
	my ($self, $successCb, $failCb) = @_;

	my $handler = $self->currentTrackHandler();
	
	$log->info($self->currentTrack()->url);

	#	if (playlist and no-track and (scanned or not scannable)) {
	if (!$self->{'currentTrack'}
		&& $self->isPlaylist()
		&& ($self->{'scanDone'} || !$handler->can('scanUrl')))
	{
		if (!$self->_getNextPlaylistTrack()) {
			&$failCb('PLAYLIST_NO_ITEMS_FOUND', $self->{'track'}->url);
			return;
		}
		$handler = $self->currentTrackHandler();
	}
	
	my $track   = $self->currentTrack();
	my $url     = $track->url;
	my $client  = $self->master();
	
	# If we have (a) a scannable playlist track,
	# or (b) a scannable track that is not yet scanned and could be a playlist ...
	if ($handler->can('scanUrl') && !$self->{'scanDone'}) {
		$self->{'scanDone'} = 1;
		$log->info("scanning URL $url");
		$handler->scanUrl($url, {
			client => $client,
			song   => $self,
			cb     => sub {
				my ( $newTrack, $error ) = @_;
				
				if ($newTrack) {
					
					if ($track != $newTrack) {
					
						if ($self->{'track'} == $track) {
							# Update of original track, by playlist or redirection
							$self->{'track'} = $newTrack;
							
							$log->info("Track updated by scan: $url -> " . $newTrack->url);
							
							# Replace the item on the playlist so it has the new track/URL
							my $i = 0;
							for my $item ( @{ Slim::Player::Playlist::playList($client) } ) {
								my $itemURL = blessed($item) ? $item->url : $item;
								if ( $itemURL eq $url ) {
									splice @{ Slim::Player::Playlist::playList($client) }, $i, 1, $newTrack;
									last;
								}
								$i++;
							}
						} elsif ($self->{'currentTrack'} && $self->{'currentTrack'} == $track) {
							# The current, playlist track got updated, maybe by redirection
							# Probably should not happen as redirection should have been
							# resolved during recursive scan of playlist.
							
							# Cannot update $self->{'currentTrack'} as would mess up playlist traversal
							$log->warn("Unexpected update of playlist track: $url -> " . $newTrack->url);
						}
					
						$track = $newTrack;
					}
										
					# maybe we just found or scanned a playlist
					if (!$self->{'currentTrack'} && !$self->{'playlist'}) {
						$self->{'playlist'} = 
							Slim::Music::Info::isPlaylist($track, $track->content_type) ? 1 : 0;
					}
					
					# if we just found a playlist					
					if (!$self->{'currentTrack'} && $self->isPlaylist()) {
						$log->info("Found a playlist");
						$self->getNextSong($successCb, $failCb);	# recurse
					} else {
						$self->getNextSong($successCb, $failCb);	# recurse
						# $successCb->();
					}
				}
				else {
					$error ||= 'PROBLEM_OPENING_REMOTE_URL';
					$failCb->($error, $url);
				}
			},
		} );
		return;
	}

	if ($handler->can('getNextTrack')) {
		$handler->getNextTrack($self, $successCb, $failCb);
		return;
	}

	# Hooks for unconverted handlers
	elsif ($handler->can('onDecoderUnderrun') || $handler->can('onJump')) {
		if ($handler->can('onJump') && 
			!($self->{'owner'}->{'playingState'} != Slim::Player::StreamingController::STOPPED()
			&& $handler->can('onDecoderUnderrun')))
		{
			$handler->onJump(master($self), $url, $self->{'seekdata'}, $successCb);
		} else {
			$handler->onDecoderUnderrun(master($self), $url, $successCb);
		}			
	} 
	
	else {
		# the simple case
		&$successCb();
	}

}

sub open {
	my ($self, $seekdata) = @_;
	
	my $handler = $self->currentTrackHandler();
	my $client  = $self->master();
	my $track   = $self->currentTrack();
	assert($track);
	my $url     = $track->url;
	
	# Reset seekOffset - handlers will set this if necessary
	$self->{'startOffset'} = 0;
	
	# Restart direct-stream
	$self->{'directstream'} = 0;
	
	$log->info($url);
	
	$self->{'seekdata'} = $seekdata if $seekdata;
	
	# get transcoding command & stream-mode
	# IF command == '-' AND canDirectStream THEN
	#	direct stream
	# ELSE
	#	ASSERT stream-mode == 'I'  OR command != '-' 
	#
	#	IF stream-mode == 'I' OR handler-does-transcoding THEN
	#		open stream
	#	ENDIF
	#	IF command != '-' AND ! handler-does-transcoding THEN
	#		add transcoding pipeline
	#	ENDIF
	# ENDIF
	
	my $sock;
	my $format = Slim::Music::Info::contentType($track);
	
	$log->info("seek=", ($self->{'seekdata'} ? 'true' : 'false'), ' time=', ($self->{'seekdata'} ? $self->{'seekdata'}->{'timeOffset'} : 0),
		 ' canSeek=', $self->canSeek());
		 
	my $wantTranscoderSeek = $self->{'seekdata'} && $self->{'seekdata'}->{'timeOffset'} && $self->canSeek() == 2;
	my @wantOptions;
	push (@wantOptions, 'T') if ($wantTranscoderSeek);
	
	my @streamFormats;
	push (@streamFormats, 'I') if (! $wantTranscoderSeek);
	
	push @streamFormats, ($handler->isRemote ? 'R' : 'F');
	
	my $transcoder = Slim::Player::TranscodingHelper::getConvertCommand2(
		$self,
		$format,
		\@streamFormats, [], \@wantOptions);
	
	if (! $transcoder) {
		logError("Couldn't create command line for $format playback for [$url]");
		return (undef, 'PROBLEM_CONVERT_FILE', $url);
	} elsif ($log->is_info) {
		$log->info("Transcoder: streamMode=", $transcoder->{'streamMode'}, ", streamformat=", $transcoder->{'streamformat'});
	}
	
	if ($wantTranscoderSeek && (grep(/T/, @{$transcoder->{'usedCapabilities'}}))) {
		$transcoder->{'start'} = $self->{'startOffset'} = $self->{'seekdata'}->{'timeOffset'};
	}

	# TODO work this out for each player in the sync-group
	my $directUrl;
	if ($transcoder->{'command'} eq '-' && ($directUrl = $client->canDirectStream($url, $self))) {
		$log->info( "URL supports direct streaming [$url->$directUrl]" );
		$self->{'directstream'} = 1;
		$self->{'streamUrl'} = $directUrl;
	}
	
	else {
		my $handlerWillTranscode = $transcoder->{'command'} ne '-'
			&& $handler->can('canHandleTranscode') && $handler->canHandleTranscode($self);

		if ($transcoder->{'streamMode'} eq 'I' || $handlerWillTranscode) {
			$log->info("Opening stream (no direct streaming) using $handler [$url]");
		
			$sock = $handler->new({
				url        => $url, # it is just easier if we always include the URL here
				client     => $client,
				song       => $self,
				transcoder => $transcoder,
			});
		
			if (!$sock) {
				logWarning("stream failed to open [$url].");
				$self->{'status'} = STATUS_FAILED;
				return (undef, $self->isRemote() ? 'PROBLEM_CONNECTING' : 'PROBLEM_OPENING', $url);
			}
					
			my $contentType = Slim::Music::Info::mimeToType($sock->contentType) || $sock->contentType;
		
			# if it's an audio stream, try to stream,
			# either directly, or via transcoding.
			if (Slim::Music::Info::isSong($track, $contentType)) {
	
				$log->info("URL is a song (audio): $url, type=$contentType");
	
				if ($sock->opened() && !defined(Slim::Utils::Network::blocking($sock, 0))) {
					logError("Can't set remote stream nonblocking for url: [$url]");
					return (undef, 'PROBLEM_OPENING', $url);
				}
				
				if ($handlerWillTranscode) {
					$self->{'transcoded'} = 1;
					$self->{'streambitrate'} = $sock->getStreamBitrate($transcoder->{'rateLimit'});
				}
				
				# If the protocol handler has the bitrate set use this
				if ($sock->can('bitrate') && $sock->bitrate) {
					$self->{'bitrate'} = $sock->bitrate;
				}
			}	
			# if it's one of our playlists, parse it...
			elsif (Slim::Music::Info::isList($track, $contentType)) {
	
				# handle the case that we've actually
				# got a playlist in the list, rather
				# than a stream.
	
				# parse out the list
				my @items = Slim::Formats::Playlists->parseList($url, $sock);
	
				# hack to preserve the title of a song redirected through a playlist
				if (scalar(@items) == 1 && $items[0] && defined($track->title)) {
					Slim::Music::Info::setTitle($items[0], $track->title);
				}
	
				# close the socket
				$sock->close();
				$sock = undef;
	
				Slim::Player::Source::explodeSong($client, \@items);
	
				my $new = $self->new ($self->{'owner'}, $self->{'index'});
				%$self = %$new;
				
				# try to open the first item in the list, if there is one.
				$self->getNextSong (
					sub {return $self->open();}, # success
					sub {return(undef, @_);}    # fail
				);
				
			} else {
				logWarning("Don't know how to handle content for [$url] type: $contentType");
	
				$sock->close();
				$sock = undef;

				$self->{'status'} = STATUS_FAILED;
				return (undef, $self->isRemote() ? 'PROBLEM_CONNECTING' : 'PROBLEM_OPENING', $url);
			}		
		}	

		if ($transcoder->{'command'} ne '-' && ! $handlerWillTranscode) {
			# Need to transcode
				
			my $quality = $prefs->client($client)->get('lameQuality');
				
			my $command = Slim::Player::TranscodingHelper::tokenizeConvertCommand2(
				$transcoder, $sock ? '-' : $track->path, $self->{'streamUrl'}, 1, $quality
			);

			if (!defined($command)) {
				logError("Couldn't create command line for $format playback for [$self->{'streamUrl'}]");
				return (undef, 'PROBLEM_CONVERT_FILE', $url);
			}

			$log->info("Tokenized command $command");

			my $pipeline = Slim::Player::Pipeline->new($sock, $command);

			if (!defined($pipeline)) {
				$sock->close();
				logError("While creating conversion pipeline for: ", $self->{'streamUrl'});
				return (undef, 'PROBLEM_CONVERT_STREAM', $url);
			}
	
			$sock = $pipeline;
				
			$self->{'transcoded'} = 1;
				
			$self->{'streambitrate'} = guessBitrateFromFormat($transcoder->{'streamformat'}, $transcoder->{'rateLimit'});
		}
			
		$client->remoteStreamStartTime(Time::HiRes::time());
		$client->pauseTime(0);
	}

	my $streamControler;
	
	######################
	# make sure the filehandle was actually set
	if ($sock || $self->{'directstream'}) {

		if ($sock && $sock->opened()) {
			binmode($sock);
		}

		if ( !main::SLIM_SERVICE ) {
			# XXXX - this really needs to happen in the caller!
			# No database access here. - dsully
			# keep track of some stats for this track
			if ( $track->persistent ) {
				$track->persistent->set( playcount  => ( $track->persistent->playcount || 0 ) + 1 );
				$track->persistent->set( lastplayed => time() );
				$track->persistent->update;
				Slim::Schema->forceCommit();
			}
		}
		
		$self->{'streamFormat'} = $transcoder->{'streamformat'};
		$client->streamformat($self->{'streamFormat'}); # XXX legacy

		$streamControler = Slim::Player::SongStreamController->new($self, $sock);

	} else {

		logError("Can't open [$url] : $!");
		return (undef, 'PROBLEM_OPENING', $url);
	}

	Slim::Control::Request::notifyFromArray($client, ['playlist', 'open', $url]);

	$self->{'status'} = STATUS_STREAMING;
	
	$client->metaTitle(undef);
	
	return $streamControler;
}

# Static method
sub guessBitrateFromFormat {
	my ($format, $maxRate) = @_;
	
	# Hack to set up stream bitrate for songTime for SliMP3/SB1
	# Also used when rebuffering, etc.
	if ($format eq 'mp3') {
		return ($maxRate || 320) * 1000;
	} elsif ($format eq 'wav' || $format eq 'aif') {
		# Just assume standard rate
		return 44_100 * 16 * 2;
	} elsif ($format eq 'flc') {
		# Assume 50% compression at standard rate
		return 44_100 * 16;
	}
}

sub pluginData {
	my ( $self, $key, $value ) = @_;
	
	my $namespace;
	
	# if called from a plugin, we automatically use the plugin's namespace for keys
	my $package = caller(0);
	if ( $package =~ /^(?:Slim::Plugin|Plugins)::(\w+)/ ) {
		$namespace = $1;
	}
	
	if (!defined $self->{'pluginData'}) {
		$self->{'pluginData'} = {};
	}	
	
	my $ref;
	if ($namespace) {
		if (!defined $self->{'pluginData'}->{$namespace}) {
			$self->{'pluginData'}->{$namespace} = {};
		}
		$ref = $self->{'pluginData'}->{$namespace};
	} else {
		$ref = $self->{'pluginData'};
	}	

	if ( !defined $key ) {
		return $ref;
	}
	
	if ( defined $value ) {
		$ref->{$key} = $value;
	}
	
	return $ref->{$key};
}


sub isActive            {return $_[0]->{'status'} < STATUS_FAILED;}
sub master              {return $_[0]->{'owner'}->master();}
sub currentTrack        {return $_[0]->{'currentTrack'}        || $_[0]->{'track'};}
sub currentTrackHandler {return $_[0]->{'currentTrackHandler'} || $_[0]->{'handler'};}
sub isRemote            {return $_[0]->currentTrackHandler()->isRemote();}  
sub duration            {return $_[0]->{'duration'} || $_[0]->currentTrack()->durationSeconds();}
sub bitrate             {return $_[0]->{'bitrate'} || $_[0]->currentTrack()->bitrate();}
sub streamformat        {return $_[0]->{'streamFormat'} || Slim::Music::Info::contentType($_[0]->currentTrack());}
sub isPlaylist          {return $_[0]->{'playlist'};}

sub getSeekDataByPosition {
	my ($self, $bytesReceived) = @_;
	
	return undef if $self->{'transcoded'};
	
	my $handler = $self->currentTrackHandler();
	
	if ($handler->can('getSeekDataByPosition')) {
		return $handler->getSeekDataByPosition($self->master(), $self, $bytesReceived);
	} else {
		return undef;
	}
}

sub streambitrate {
	my $self = shift;
	return (exists $self->{'streambitrate'} ? $self->{'streambitrate'} : $self->bitrate());
}

sub canSeek {
	my $self = shift;
	
	my $canSeek = $self->canDoSeek();
	
	return ($canSeek ? $canSeek : ($canSeek, @{$self->{'canSeekError'}}));
}

sub canDoSeek {
	my $self = shift;
	
	return $self->{'canSeek'} if (defined $self->{'canSeek'});
	
	my $needEndSeek;
	if (my $anchor = Slim::Utils::Misc::anchorFromURL($self->currentTrack->url())) {
		$needEndSeek = ($anchor =~ /[\d.:]+-[\d.:]+/);
	}
	
	my $handler = $self->currentTrackHandler();
	
	if (!$needEndSeek && $handler->can('canSeek')) {
		if ($handler->canSeek( $self->master(), $self )) {
			return $self->{'canSeek'} = 1 if $handler->isRemote();
			
			# If dealing with local file and transcoding then best let transcoder seek if it can
			
			# First see how we would stream without seeking question
			my $transcoder = Slim::Player::TranscodingHelper::getConvertCommand2(
				$self,
				Slim::Music::Info::contentType($self->currentTrack),
				['I', 'F'], [], []);
				
			if (! $transcoder) {
				$self->{'canSeekError'} = [ 'SEEK_ERROR_TRANSCODED' ];
				return $self->{'canSeek'} = 0;
			}
			
			# Is this pass-through?
			if ($transcoder->{'command'} eq '-') {
				return $self->{'canSeek'} = 1; # nice simple case
			}
			
			# no, then could we get a seeking transcoder?
			if (Slim::Player::TranscodingHelper::getConvertCommand2(
				$self,
				Slim::Music::Info::contentType($self->currentTrack),
				['I', 'F'], ['T'], []))
			{
				return $self->{'canSeek'} = 2;
			}
			
			# no, then did the transcoder accept stdin?
			if ($transcoder->{'streamMode'} eq 'I') {
				return $self->{'canSeek'} = 1;
			} else {
				$self->{'canSeekError'} = [ 'SEEK_ERROR_TRANSCODED' ];
				return $self->{'canSeek'} = 0;
			}
			
		} else {
			$self->{'canSeekError'} = [$handler->can('canSeekError') 
					? $handler->canSeekError( $self->master(), $self  )
					: ('SEEK_ERROR_REMOTE')];
		}
	} 
	
	if (Slim::Player::TranscodingHelper::getConvertCommand2(
			$self,
			Slim::Music::Info::contentType($self->currentTrack),
			[$handler->isRemote ? 'R' : 'F'], ['T'], []))
	{
		return $self->{'canSeek'} = 2;
	}
	
	if (!$self->{'canSeekError'}) {
		$self->{'canSeekError'} = [ 'SEEK_ERROR_REMOTE' ];
	}
	
	return $self->{'canSeek'} = 0;
}


1;
