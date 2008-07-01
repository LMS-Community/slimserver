package Slim::Player::Protocols::HTTP;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech, Vidur Apparao.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;
use base qw(Slim::Formats::HTTP);

use File::Spec::Functions qw(:ALL);
use IO::String;
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::Remote;
use Slim::Utils::Unicode;

use constant MAXCHUNKSIZE => 32768;

my $log = logger('player.streaming.remote');

sub new {
	my $class = shift;
	my $args  = shift;

	if (!$args->{'url'}) {

		logWarning("No url passed!");
		return undef;
	}

	my $self = $class->open($args);

	if (defined($self)) {
		${*$self}{'url'}     = $args->{'url'};
		${*$self}{'client'}  = $args->{'client'};
	}

	return $self;
}

sub readMetaData {
	my $self = shift;
	my $client = ${*$self}{'client'};

	my $metadataSize = 0;
	my $byteRead = 0;

	while ($byteRead == 0) {

		$byteRead = $self->SUPER::sysread($metadataSize, 1);

		if ($!) {

			if ($! ne "Unknown error" && $! != EWOULDBLOCK) {

			 	#$log->warn("Warning: Metadata byte not read! $!");
			 	return;

			 } else {

				#$log->debug("Metadata byte not read, trying again: $!");  
			 }
		}

		$byteRead = defined $byteRead ? $byteRead : 0;
	}
	
	$metadataSize = ord($metadataSize) * 16;
	
	if ($metadataSize > 0) {
		$log->debug("Metadata size: $metadataSize");
		
		my $metadata;
		my $metadatapart;
		
		do {
			$metadatapart = '';
			$byteRead = $self->SUPER::sysread($metadatapart, $metadataSize);

			if ($!) {
				if ($! ne "Unknown error" && $! != EWOULDBLOCK) {

					#$log->info("Metadata bytes not read! $!");
					return;

				} else {

					#$log->info("Metadata bytes not read, trying again: $!");
				}
			}

			$byteRead = 0 if (!defined($byteRead));
			$metadataSize -= $byteRead;	
			$metadata .= $metadatapart;	

		} while ($metadataSize > 0);			

		$log->info("Metadata: $metadata");

		${*$self}{'title'} = parseMetadata($client, $self->url, $metadata);

		# new song, so reset counters
		$client->songBytes(0);
	}
}

sub getFormatForURL {
	my $classOrSelf = shift;
	my $url = shift;

	return Slim::Music::Info::typeFromSuffix($url);
}

sub parseMetadata {
	my $client   = shift;
	my $url      = shift;
	my $metadata = shift;

	$url = Slim::Player::Playlist::url(
		$client, Slim::Player::Source::streamingSongIndex($client)
	);

	if ($metadata =~ (/StreamTitle=\'(.*?)\'(;|$)/)) {

		my $newTitle = Slim::Utils::Unicode::utf8decode_guess($1, 'iso-8859-1');

		# capitalize titles that are all lowercase
		# XXX: Why do we do this?  Shouldn't we let metadata display as-is?
		if (lc($newTitle) eq $newTitle) {
			$newTitle =~ s/ (
					  (^\w)    #at the beginning of the line
					  |        # or
					  (\s\w)   #preceded by whitespace
					  |        # or
					  (-\w)   #preceded by dash
					  )
				/\U$1/xg;
		}
		
		# Delay the title set
		return Slim::Music::Info::setDelayedTitle( $client, $url, $newTitle );
	}

	return undef;
}

sub canDirectStream {
	my ($classOrSelf, $client, $url) = @_;
	
	# When synced, we don't direct stream so that the server can proxy a single
	# stream for all players
	if ( Slim::Player::Sync::isSynced($client) ) {

		if ( logger('player.streaming.direct')->is_info ) {
			logger('player.streaming.direct')->info(sprintf(
				"[%s] Not direct streaming because player is synced", $client->id
			));
		}

		return 0;
	}

	# Allow user pref to select the method for streaming
	if ( my $method = preferences('server')->client($client)->get('mp3StreamingMethod') ) {
		if ( $method == 1 ) {
			logger('player.streaming.direct')->debug("Not direct streaming because of mp3StreamingMethod pref");
			return 0;
		}
	}

	# Check the available types - direct stream MP3, but not Ogg.
	my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand($client, $url);

	if (defined $command && $command eq '-' || $format eq 'mp3') {
		return $url;
	}

	return 0;
}

sub sysread {
	my $self = $_[0];
	my $chunkSize = $_[2];

	my $metaInterval = ${*$self}{'metaInterval'};
	my $metaPointer  = ${*$self}{'metaPointer'};

	if ($metaInterval && ($metaPointer + $chunkSize) > $metaInterval) {

		$chunkSize = $metaInterval - $metaPointer;

		# This is very verbose...
		#$log->debug("Reduced chunksize to $chunkSize for metadata");
	}

	my $readLength = CORE::sysread($self, $_[1], $chunkSize, length($_[1] || ''));

	if ($metaInterval && $readLength) {

		$metaPointer += $readLength;
		${*$self}{'metaPointer'} = $metaPointer;

		# handle instream metadata for shoutcast/icecast
		if ($metaPointer == $metaInterval) {

			$self->readMetaData();

			${*$self}{'metaPointer'} = 0;

		} elsif ($metaPointer > $metaInterval) {

			$log->debug("The shoutcast metadata overshot the interval.");
		}	
	}
	
	# Use MPEG::Audio::Frame to detect the bitrate if we didn't see an icy header
	if ( !$self->bitrate && $self->contentType =~ /^(?:mp3|audio\/mpeg)$/ ) {

		my $io = IO::String->new($_[1]);

		$log->info("Trying to read bitrate from stream");

		my ($bitrate, $vbr) = Slim::Utils::Scanner::scanBitrate($io);

		Slim::Music::Info::setBitrate( $self->infoUrl, $bitrate, $vbr );
		${*$self}{'bitrate'} = $bitrate;
		
		if ( $self->client && $self->bitrate > 0 && $self->contentLength > 0 ) {

			# if we know the bitrate and length of a stream, display a progress bar
			if ( $self->bitrate < 1000 ) {
				${*$self}{'bitrate'} *= 1000;
			}
			
			# But don't update the progress bar if it was already set in parseHeaders
			# using previously-known duration info
			unless ( my $secs = Slim::Music::Info::getDuration( $self->url ) ) {
								
				$self->client->streamingProgressBar( {
					'url'     => $self->url,
					'bitrate' => $self->bitrate,
					'length'  => $self->contentLength,
				} );
			}
		}
	}
	
	# XXX: Add scanBitrate support for non-directstreaming Ogg and FLAC

	return $readLength;
}

sub parseDirectHeaders {
	my ( $class, $client, $url, @headers ) = @_;
	
	my ($title, $bitrate, $metaint, $redir, $contentType, $length, $body);
	
	foreach my $header (@headers) {
	
		logger('player.streaming.direct')->debug("header-ds: $header");

		if ($header =~ /^(?:ic[ey]-name|x-audiocast-name):\s*(.+)/i) {
			
			$title = Slim::Utils::Unicode::utf8decode_guess($1, 'iso-8859-1');
		}
		
		elsif ($header =~ /^(?:icy-br|x-audiocast-bitrate):\s*(.+)/i) {
			$bitrate = $1 * 1000;
		}
	
		elsif ($header =~ /^icy-metaint:\s*(.+)/) {
			$metaint = $1;
		}
	
		elsif ($header =~ /^Location:\s*(.*)/i) {
			$redir = $1;
		}
		
		elsif ($header =~ /^Content-Type:\s*(.*)/i) {
			$contentType = $1;
		}
		
		elsif ($header =~ /^Content-Length:\s*(.*)/i) {
			$length = $1;
		}
		
		# mp3tunes metadata, this is a bit of hack but creating
		# an mp3tunes protocol handler is overkill
		elsif ( $url =~ /mp3tunes\.com/ && $header =~ /^X-Locker-Info:\s*(.+)/i ) {
			Slim::Plugin::MP3tunes::Plugin->setLockerInfo( $client, $url, $1 );
		}
	}

	$contentType = Slim::Music::Info::mimeToType($contentType);
	
	if ( !$contentType ) {
		# Bugs 7225, 7423
		# Default contentType to mp3 as some servers don't send the type
		# or send an invalid type we don't include in types.conf
		$contentType = 'mp3';
	}
	
	if ( $length && $contentType eq 'mp3' ) {
		logger('player.streaming.direct')->debug("Stream supports seeking");
		$client->scanData->{mp3_can_seek} = 1;
	}
	else {
		logger('player.streaming.direct')->debug("Stream does not support seeking");
		delete $client->scanData->{mp3_can_seek};
	}
	
	return ($title, $bitrate, $metaint, $redir, $contentType, $length, $body);
}

sub parseDirectBody {
	my ( $class, $client, $url, $body ) = @_;

	logger('player.streaming.direct')->info("Parsing body for bitrate.");

	my $contentType = Slim::Music::Info::contentType($url);

	my ($bitrate, $vbr) = Slim::Utils::Scanner::scanBitrate( $body, $contentType, $url );

	if ( $bitrate ) {
		Slim::Music::Info::setBitrate( $url, $bitrate, $vbr );
	}

	# Must return a track object to play
	my $track = Slim::Schema->rs('Track')->objectForUrl({
		'url'      => $url,
		'readTags' => 1
	});

	return $track;
}

# Whether or not to display buffering info while a track is loading
sub showBuffering {
	my ( $class, $client, $url ) = @_;
	
	return $client->showBuffering;
}

# Handle normal advances to the next track
sub onDecoderUnderrun {
	my ( $class, $client, $nextURL, $callback ) = @_;
	
	# Flag that we don't want any buffering messages while loading the next track,
	$client->showBuffering( 0 );
	
	# Special handling needed when synced since onDecoderUnderrun is
	# called for all players
	if ( Slim::Player::Sync::isSynced($client) ) {
		if ( !Slim::Player::Sync::isMaster($client) ) {
			# Only the master needs to scan the track
			$log->debug('Letting sync master scan next track');
			
			$callback->();
			
			return;
		}
	}
	
	# If user was listening to a playlist, it may contain non-infinite tracks
	# so this lets us advance to the next entry in the playlist.  We just
	# want to skip scanHTTPTrack in this case, and the onUnderrun callback
	# will handle playing the next entry
	if ( $client->remotePlaylistCurrentEntry ) {
		my $playlist = Slim::Schema->rs('Playlist')->objectForUrl( { 	 
			url => Slim::Player::Playlist::url($client), 	 
		} );
		
		if ( my $nextEntry = $playlist->getNextEntry( { after => $client->remotePlaylistCurrentEntry } ) ) {
			$log->debug( 'Playlist contains more tracks, not scanning next track, waiting for underrun' );
			return;
		}
	}
	
	$log->debug( 'Scanning next HTTP track before playback' );
	
	$class->scanHTTPTrack( $client, $nextURL, $callback );
}

sub onUnderrun {
	my ( $class, $client, $url, $callback ) = @_;
	
	# Special handling needed when synced since onUnderrun is
	# called for all players
	if ( Slim::Player::Sync::isSynced($client) ) {
		if ( !Slim::Player::Sync::isMaster($client) ) {
			# Only the master needs to scan the track
			$log->debug('Letting sync master handle onUnderrun');
			
			$callback->();
			
			return;
		}
	}
	
	# If user was listening to a playlist, it may contain non-infinite tracks
	# so this lets us advance to the next entry in the playlist
	if ( $client->remotePlaylistCurrentEntry ) {
		my $playlist = Slim::Schema->rs('Playlist')->objectForUrl( { 	 
			url => Slim::Player::Playlist::url($client), 	 
		} );
		
		if ( my $nextEntry = $playlist->getNextEntry( { after => $client->remotePlaylistCurrentEntry } ) ) {
			# Jump to the same track where we'll play the next item in the playlist
			
			$client->remotePlaylistCurrentEntry( $nextEntry );
			
			$log->debug( "Jumping to same track to play the next entry in the playlist" );

			if ( $nextEntry->title !~ /^(?:http|mms)/ ) {
				Slim::Music::Info::setCurrentTitle( $playlist->url, $nextEntry->title );
			}

			Slim::Player::Source::jumpto( $client, '+0' );
			
			return;
		}
	}
	
	$callback->();
}

# On skip, load the next track before playback
sub onJump {
	my ( $class, $client, $nextURL, $callback ) = @_;
	
	# If seeking, we can avoid scanning
	if ( $client->scanData->{seekdata} ) {
		# XXX: we could set showBuffering to 0 but on slow
		# streams there would be no feedback
		
		$callback->();
		return;
	}

	# Display buffering info on loading the next track
	$client->showBuffering( 1 );

	$log->debug( 'Scanning next HTTP track before playback' );
		
	$class->scanHTTPTrack( $client, $nextURL, $callback );
}

sub scanHTTPTrack {
	my ( $class, $client, $nextURL, $callback ) = @_;
	
	$client = $client->masterOrSelf;
	
	# Clear previous playlist entry if any
	$client->remotePlaylistCurrentEntry( undef );
	
	# Bug 7739, Scan the next track/playlist before we play it
	Slim::Utils::Scanner::Remote->scanURL( $nextURL, {
		client => $client,
		cb     => sub {
			my ( $track, $error ) = @_;
			
			if ( $track ) {
				# An HTTP URL may really be an MMS URL,
				# check now and if so, change the URL before playback
				if ( $track->content_type eq 'wma' ) {
					$log->debug( "Changing URL to MMS protocol: $nextURL" );
					my $mmsURL = $nextURL;
					$mmsURL =~ s/^http/mms/i;
					$track->url( $mmsURL );
					$track->update;
					
					# Replace the item on the playlist so it has the new URL
					my $i = 0;
					for my $item ( @{ Slim::Player::Playlist::playList($client) } ) {
						my $itemURL = blessed($item) ? $item->url : $item;
						if ( $itemURL eq $nextURL ) {
							splice @{ Slim::Player::Playlist::playList($client) }, $i, 1, $track;
							last;
						}
						$i++;
					}
				}
				
				$callback->();
			}
			else {
				my $line1;
				$error ||= 'PROBLEM_OPENING_REMOTE_URL';

				# If the playlist was unable to load a remote URL, notify
				# This is used for logging broken stream links
				Slim::Control::Request::notifyFromArray( $client, [ 'playlist', 'cant_open', $nextURL, $error ] );

				if ( uc($error) eq $error ) {
					$line1 = $client->string($error);
				}
				else {
					$line1 = $error;
				}

				# Show an error message
				$client->showBriefly( {
					line => [ $line1, $nextURL ],
				}, {
					scroll    => 1,
					firstline => 1,
					duration  => 5,
				} );
			}
		},
	} );
}

# Allow mp3tunes tracks to be scrobbled
sub audioScrobblerSource {
	my ( $class, $client, $url ) = @_;
	
	if ( $url =~ /mp3tunes\.com/ ) {
		# Scrobble mp3tunes as 'chosen by user' content
		return 'P';
	}
	 
	# R (radio source)
	return 'R';
}

sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;

	my ($artist, $title);
	# Radio tracks, return artist and title if the metadata looks like Artist - Title
	if ( my $currentTitle = Slim::Music::Info::getCurrentTitle( $client, $url ) ) {
		my @dashes = $currentTitle =~ /( - )/g;
		if ( scalar @dashes == 1 ) {
			($artist, $title) = split / - /, $currentTitle;
		}

		else {
			$title = $currentTitle;
		}
	}
	
	# Remember playlist URL
	my $playlistURL = $url;
	
	# Check for radio URLs with cached covers (RadioTime)
	my $cache = Slim::Utils::Cache->new( 'Artwork', 1, 1 );
	my $cover = $cache->get( "remote_image_$url" );
	
	# Item may be a playlist, so get the real URL playing
	if ( Slim::Music::Info::isPlaylist($url) ) {
		if ( my $entry = $client->remotePlaylistCurrentEntry ) {
			$url = $entry->url;
		}
	}
	
	# Remote streams may include ID3 tags with embedded artwork
	# Example: http://downloads.bbc.co.uk/podcasts/radio4/excessbag/excessbag_20080426-1217.mp3
	my $track = Slim::Schema->rs('Track')->objectForUrl( {
		url => $url,
	} );
	
	return {} unless $track;
	
	if ( $track->cover ) {
		$cover = '/music/' . $track->id . '/cover.jpg';
	}
	
	if ( $url =~ /mp3tunes\.com/ || $url =~ m|squeezenetwork\.com.+/mp3tunes| ) {
		if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::MP3tunes::Plugin') ) {
			my $icon = Slim::Plugin::MP3tunes::Plugin->_pluginDataFor('icon');
			my $meta = Slim::Plugin::MP3tunes::Plugin->getLockerInfo( $client, $url );
			if ( $meta ) {
				# Metadata for currently playing song
				return {
					artist   => $meta->{artist},
					album    => $meta->{album},
					tracknum => $meta->{tracknum},
					title    => $meta->{title},
					cover    => $cover || $meta->{cover} || $icon,
					icon     => $icon,
					type     => 'MP3tunes',
				};
			}
			else {
				# Metadata for items in the playlist that have not yet been played
			
				# We can still get cover art for items not yet played
				if ( !$cover && $url =~ /hasArt=1/ ) {
					my ($id)  = $url =~ m/([0-9a-f]+\?sid=[0-9a-f]+)/;
					$cover    = "http://content.mp3tunes.com/storage/albumartget/$id";
				}
			
				return {
					cover    => $cover || $icon,
					icon     => $icon,
					type     => 'MP3tunes',
				};
			}
		}
	}
	elsif ( $url =~ /archive\.org/ || $url =~ m|squeezenetwork\.com.+/lma/| ) {
		if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::LMA::Plugin') ) {
			my $icon = Slim::Plugin::LMA::Plugin->_pluginDataFor('icon');
			return {
				title    => $title,
				cover    => $cover || $icon,
				icon     => $icon,
				type     => 'Live Music Archive',
			};
		}
	}
	elsif ( $playlistURL =~ /radioio/i ) {
		if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::RadioIO::Plugin') ) {
			# RadioIO
			my $icon = Slim::Plugin::RadioIO::Plugin->_pluginDataFor('icon');
			return {
				artist   => $artist,
				title    => $title,
				cover    => $icon,
				icon     => $icon,
				type     => 'MP3 (RadioIO)',
			};
		}
	}
	else {	

		if ( (my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url)) ne $class )  {
			if ( $handler && $handler->can('getMetadataFor') ) {
				return $handler->getMetadataFor( $client, $url );
			}
		}	

		my $type = uc( $track->content_type ) . ' '
			. ( defined $client ? $client->string('RADIO') : Slim::Utils::Strings::string('RADIO') );
		
		return {
			artist   => $artist,
			title    => $title,
			type     => $type,
			bitrate  => $track->prettyBitRate,
			duration => $track->secs,
			cover    => $cover,
		};
	}
	
	return {};
}

sub getIcon {
	my ( $class, $url ) = @_;

	my $handler;

	if ( ($handler = Slim::Player::ProtocolHandlers->iconHandlerForURL($url)) && ref $handler eq 'CODE' ) {
		return &{$handler};
	}

	return 'html/images/radio.png';
}

sub canSeek {
	my ( $class, $client, $url ) = @_;
	
	$client = $client->masterOrSelf;
	
	if ( Slim::Music::Info::isPlaylist($url) ) {
		if ( my $entry = $client->remotePlaylistCurrentEntry ) {
			$url = $entry->url;
		}
	}
	
	# Can only seek if bitrate and duration are known
	my $bitrate = Slim::Music::Info::getBitrate( $url );
	my $seconds = Slim::Music::Info::getDuration( $url );
	
	if ( !$bitrate || !$seconds ) {
		#$log->debug( "bitrate: $bitrate, duration: $seconds" );
		#$log->debug( "Unknown bitrate or duration, seek disabled" );
		return 0;
	}
	
	if ( $client->scanData->{mp3_can_seek} ) {
		return 1;
	}
	
	#$log->debug( "Seek not possible, content-length missing or wrong content-type" );
	
	return 0;
}

sub canSeekError {
	my ( $class, $client, $url ) = @_;
	
	if ( Slim::Music::Info::isPlaylist($url) ) {
		if ( my $entry = $client->remotePlaylistCurrentEntry ) {
			$url = $entry->url;
		}
	}
	
	my $ct = Slim::Music::Info::contentType($url);
	
	if ( $ct ne 'mp3' ) {
		return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', $ct );
	} 
	
	if ( !Slim::Music::Info::getBitrate( $url ) ) {
		return 'SEEK_ERROR_MP3_UNKNOWN_BITRATE';
	}
	elsif ( !Slim::Music::Info::getDuration( $url ) ) {
		return 'SEEK_ERROR_MP3_UNKNOWN_DURATION';
	}
	
	return 'SEEK_ERROR_MP3';
}

sub getSeekData {
	my ( $class, $client, $url, $newtime ) = @_;
	
	if ( Slim::Music::Info::isPlaylist($url) ) {
		if ( my $entry = $client->remotePlaylistCurrentEntry ) {
			$url = $entry->url;
		}
	}
	
	# Determine byte offset and song length in bytes
	my $bitrate = Slim::Music::Info::getBitrate( $url ) || return;
	my $seconds = Slim::Music::Info::getDuration( $url ) || return;
		
	$bitrate /= 1000;
		
	$log->debug( "Trying to seek $newtime seconds into $bitrate kbps stream of $seconds length" );
	
	my $data = {
		newoffset         => ( ( $bitrate * 1024 ) / 8 ) * $newtime,
		songLengthInBytes => ( ( $bitrate * 1024 ) / 8 ) * $seconds,
	};
	
	return $data;
}

sub setSeekData {
	my ( $class, $client, $url, $newtime, $newoffset ) = @_;
	
	my @clients;
	
	if ( Slim::Player::Sync::isSynced($client) ) {
		# if synced, save seek data for all players
		my $master = Slim::Player::Sync::masterOrSelf($client);
		push @clients, $master, @{ $master->slaves };
	}
	else {
		push @clients, $client;
	}
	
	for my $client ( @clients ) {
		# Save the new seek point
		$client->scanData( {
			seekdata => {
				newtime   => $newtime,
				newoffset => $newoffset,
			},
		} );
	}
}

sub onOpen {
	my ( $class, $client, $track ) = @_;
	
	$client = $client->masterOrSelf;
	
	if ( Slim::Music::Info::isPlaylist( $track, $track->content_type ) ) {
		if ( my $next = $client->remotePlaylistCurrentEntry ) {
			return $next;
		}
		
		# Return the first good audio track
		my $playlist = Slim::Schema->rs('Playlist')->objectForUrl( {
			url => $track->url,
		} );
		
		$log->debug( "Getting next audio URL from playlist" );
		
		my $next = $playlist->getNextEntry;
		
		# Save the current playlist entry being used
		$client->remotePlaylistCurrentEntry( $next );
		
		return $next;
	}
	
	return $track;
}

1;

__END__
