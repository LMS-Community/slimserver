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

use Slim::Formats::RemoteMetadata;
use Slim::Music::Info;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::Remote;
use Slim::Utils::Unicode;

use constant MAXCHUNKSIZE => 32768;

my $log       = logger('player.streaming.remote');
my $directlog = logger('player.streaming.direct');
my $sourcelog = logger('player.source');

sub new {
	my $class = shift;
	my $args  = shift;

	if (!$args->{'song'}) {

		logWarning("No song passed!");
		
		# XXX: MusicIP abuses this as a non-async HTTP client, can't return undef
		# return undef;
	}

	my $self = $class->open($args);

	if (defined($self)) {
		${*$self}{'song'}    = $args->{'song'};
		${*$self}{'client'}  = $args->{'client'};
		${*$self}{'url'}     = $args->{'url'};
	}

	return $self;
}

sub isRemote { 1 }

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

		${*$self}{'title'} = __PACKAGE__->parseMetadata($client, $self->url, $metadata);

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
	my ( $class, $client, $url, $metadata ) = @_;

	$url = Slim::Player::Playlist::url(
		$client, Slim::Player::Source::streamingSongIndex($client)
	);
	
	# See if there is a parser for this stream
	my $parser = Slim::Formats::RemoteMetadata->getParserFor( $url );
	if ( $parser ) {
		if ( $log->is_debug ) {
			$log->debug( 'Trying metadata parser ' . Slim::Utils::PerlRunTime::realNameForCodeRef($parser) );
		}
		
		my $handled = eval { $parser->( $client, $url, $metadata ) };
		if ( $@ ) {
			my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($parser);
			logger('formats.metadata')->error( "Metadata parser $name failed: $@" );
		}
		return if $handled;
	}

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
		Slim::Music::Info::setDelayedTitle( $client, $url, $newTitle );
	}
	
	# Check for Ogg metadata, which is formatted as a series of
	# 2-byte length/string pairs.
	elsif ( $metadata =~ /^Ogg(.+)/ ) {
		my $comments = $1;
		my $meta = {};
		while ( $comments ) {
			my $length = unpack 'n', substr( $comments, 0, 2, '' );
			my $value  = substr $comments, 0, $length, '';
			
			# Look for artist/title/album
			if ( $value =~ /ARTIST=(.+)/i ) {
				$meta->{artist} = $1;
			}
			elsif ( $value =~ /ALBUM=(.+)/i ) {
				$meta->{album} = $1;
			}
			elsif ( $value =~ /TITLE=(.+)/i ) {
				$meta->{title} = $1;
			}
		}
		
		if ( $directlog->is_debug ) {
			$directlog->debug( 'Ogg metadata: ' . Data::Dump::dump($meta) );
		}
		
		# Re-use wmaMeta field
		my $song = $client->controller()->songStreamController()->song();
		
		my $cb = sub {
			$song->pluginData( wmaMeta => $meta );
		};
		
		# Delay metadata according to buffer size if we already have metadata
		if ( $song->pluginData('wmaMeta') ) {
			Slim::Music::Info::setDelayedCallback( $client, $cb, 'output-only' );
		}
		else {
			$cb->();
		}
		
		return;
	}
	
	# Check for an image URL in the metadata.  Currently, only Radio Paradise supports this
	if ( $metadata =~ /StreamUrl=\'([^']+)\'/ ) {
		my $metaUrl = $1;
		if ( $metaUrl =~ /\.(?:jpe?g|gif|png)$/i ) {
			# Set this in the artwork cache after a delay
			my $delay = Slim::Music::Info::getStreamDelay($client);
			
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time() + $delay,
				sub {
					my $cache = Slim::Utils::Cache->new( 'Artwork', 1, 1 );
					$cache->set( "remote_image_$url", $metaUrl, 3600 );
					
					$directlog->debug("Updating stream artwork to $metaUrl");
				},
			);
		}
	}

	return undef;
}

sub canDirectStream {
	my ($classOrSelf, $client, $url, $inType) = @_;
	
	if ( !main::SLIM_SERVICE ) {
		# When synced, we don't direct stream so that the server can proxy a single
		# stream for all players
		if ( $client->isSynced(1) ) {

			if ( $directlog->is_info ) {
				$directlog->info(sprintf(
					"[%s] Not direct streaming because player is synced", $client->id
				));
			}

			return 0;
		}

		# Allow user pref to select the method for streaming
		if ( my $method = preferences('server')->client($client)->get('mp3StreamingMethod') ) {
			if ( $method == 1 ) {
				$directlog->debug("Not direct streaming because of mp3StreamingMethod pref");
				return 0;
			}
		}
	}
	
	if ( main::SLIM_SERVICE ) {
		# Strip noscan info from URL
		$url =~ s/#slim:.+$//;
	}

	return $url;
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

	return $readLength;
}

sub parseDirectHeaders {
	my ( $class, $client, $url, @headers ) = @_;
	
	my $isDebug = $directlog->is_debug;
	
	# May get a track object
	if ( blessed($url) ) {
		$url = $url->url;
	}
	
	my ($title, $bitrate, $metaint, $redir, $contentType, $length, $body);
	
	foreach my $header (@headers) {
	
		$isDebug && $directlog->debug("header-ds: $header");

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
		
	return ($title, $bitrate, $metaint, $redir, $contentType, $length, $body);
}

sub scanUrl {
	my ( $class, $url, $args ) = @_;
	
	my $callersCallback = $args->{'cb'};
	
	$args->{'cb'} = sub {
		my ( $track ) = @_;
		if ( $track ) {
			# An HTTP URL may really be an MMS URL,
			# check now and if so, change the URL before playback
			if ( $track->content_type eq 'wma' ) {
				$log->debug( "Changing URL to MMS protocol: " . $track->url);
				my $mmsURL = $track->url;
				$mmsURL =~ s/^http/mms/i;
				$track->url( $mmsURL );
				$track->update;
			}
		}
		
		$callersCallback->(@_);
	};
	
	Slim::Utils::Scanner::Remote->scanURL($url, $args);
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
	
	# Check for an alternate metadata provider for this URL
	my $provider = Slim::Formats::RemoteMetadata->getProviderFor($url);
	if ( $provider ) {
		my $metadata = eval { $provider->( $client, $url ) };
		if ( $@ ) {
			my $name = Slim::Utils::PerlRunTime::realNameForCodeRef($provider);
			$log->error( "Metadata provider $name failed: $@" );
		}
		elsif ( scalar keys %{$metadata} ) {
			return $metadata;
		}
	}
	
	# Check for parsed WMA metadata, this is here because WMA may
	# use HTTP protocol handler
	if ( my $song = $client->playingSong() ) {
		if ( my $meta = $song->pluginData('wmaMeta') ) {
			my $data = {};
			if ( $meta->{artist} ) {
				$data->{artist} = $meta->{artist};
			}
			if ( $meta->{album} ) {
				$data->{album} = $meta->{album};
			}
			if ( $meta->{title} ) {
				$data->{title} = $meta->{title};
			}
			if ( $meta->{cover} ) {
				$data->{cover} = $meta->{cover};
			}
	
			if ( scalar keys %{$data} ) {
				return $data;
			}
		}
	}
	
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
	
	# Check for radio URLs with cached covers
	my $cache = Slim::Utils::Cache->new( 'Artwork', 1, 1 );
	my $cover = $cache->get( "remote_image_$url" );
	
	# Item may be a playlist, so get the real URL playing
	if ( Slim::Music::Info::isPlaylist($url) ) {
		if (my $cur = $client->currentTrackForUrl($url)) {
			$url = $cur->url;
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
	
	if ( $url =~ /archive\.org/ || $url =~ m|squeezenetwork\.com.+/lma/| ) {
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
		if ( main::SLIM_SERVICE || Slim::Plugin::InternetRadio::Plugin::RadioIO->can('_pluginDataFor') ) {
			# RadioIO
			my $icon = main::SLIM_SERVICE
				? 'http://www.squeezenetwork.com/static/images/icons/radioio.png'
				: Slim::Plugin::InternetRadio::Plugin::RadioIO->_pluginDataFor('icon');
				
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

		if ( (my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url)) !~ /^(?:$class|Slim::Player::Protocols::MMS)$/ )  {
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
	my ( $class, $client, $song ) = @_;
	
	$client = $client->master();
	
	# Can only seek if bitrate and duration are known
	my $bitrate = $song->bitrate();
	my $seconds = $song->duration();
	
	if ( !$bitrate || !$seconds ) {
		#$log->debug( "bitrate: $bitrate, duration: $seconds" );
		#$log->debug( "Unknown bitrate or duration, seek disabled" );
		return 0;
	}
		
	return 1;
}

sub canSeekError {
	my ( $class, $client, $song ) = @_;
	
	my $url = $song->currentTrack()->url;
	
	my $ct = Slim::Music::Info::contentType($url);
	
	if ( $ct ne 'mp3' ) {
		return ( 'SEEK_ERROR_TYPE_NOT_SUPPORTED', $ct );
	} 
	
	if ( !$song->bitrate() ) {
		$log->info("bitrate unknown for: " . $url);
		return 'SEEK_ERROR_MP3_UNKNOWN_BITRATE';
	}
	elsif ( !$song->duration() ) {
		return 'SEEK_ERROR_MP3_UNKNOWN_DURATION';
	}
	
	return 'SEEK_ERROR_MP3';
}

sub getSeekData {
	my ( $class, $client, $song, $newtime ) = @_;
	
	# Determine byte offset and song length in bytes
	my $bitrate = $song->bitrate() || return;
		
	$bitrate /= 1000;
		
	$log->info( "Trying to seek $newtime seconds into $bitrate kbps" );
	
	return {
		sourceStreamOffset   => ( ( $bitrate * 1024 ) / 8 ) * $newtime,
		timeOffset           => $newtime,
	};
}

sub getSeekDataByPosition {
	my ($class, $client, $song, $bytesReceived) = @_;
	
	return {sourceStreamOffset => $bytesReceived};
}

# reinit is used on SN to maintain seamless playback when bumped to another instance
sub reinit {
	my ( $class, $client, $song ) = @_;
	
	$log->debug("Re-init HTTP");
	
	# Back to Now Playing
	Slim::Buttons::Common::pushMode( $client, 'playlist' );
	
	# Trigger event logging timer for this stream
	Slim::Control::Request::notifyFromArray(
		$client,
		[ 'playlist', 'newsong', Slim::Music::Info::standardTitle( $client, $song->{streamUrl} ), 0 ]
	);
	
	return 1;
}

1;

__END__
