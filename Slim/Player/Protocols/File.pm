package Slim::Player::Protocols::File;


# Logitech Media Server Copyright 2001-2020 Logitech, Vidur Apparao.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;
use base qw(IO::File);

use File::Spec::Functions qw(catdir);
use IO::String;

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Formats;
use Slim::Player::Source;

use constant MAXCHUNKSIZE => 32768;

my $log = logger('player.source');
my $prefs = preferences('server');

sub new {
	my $class = shift;
	my $args  = shift;

	if (!$args->{'song'}) {
		logWarning("No song passed!");
		return undef;
	}

	my $self = $class->open($args);

	if (defined($self)) {
		${*$self}{'song'}        = $args->{'song'};
		${*$self}{'client'}      = $args->{'client'};
		${*$self}{'contentType'} = Slim::Music::Info::contentType($args->{'song'}->currentTrack());
		
		${*$self}{'handler'} = $class;
	}

	return $self;
}

sub open {
	my $class = shift;
	my $args  = shift;

	
	my $song     = $args->{'song'};
	my $track    = $song->currentTrack();
	my $url      = $track->url;
	my $client   = $args->{'client'};
	my $seekdata = $song->seekdata();
	
	my $seekoffset = 0;

	my $filepath = $class->pathFromFileURL($url);

	my ($size, $duration, $offset, $samplerate, $samplesize, $channels, $blockalign, $endian, $drm) =
		(0, 0, 0, 0, 0, 0, 0, undef, undef);
			
	# don't try and read this if we're a pipe
	if (!-p $filepath) {

		$size       = $track->audio_size() || -s $filepath;
		$duration   = $track->secs();
		$offset     = $track->audio_offset() || 0;
		$samplerate = $track->samplerate() || 0;
		$samplesize = $track->samplesize() || 0;
		$channels   = $track->channels() || 0;
		$blockalign = $track->block_alignment() || 1;
		$endian     = $track->endian() || '';
		$drm        = $track->drm();
		
		if ( main::INFOLOG && $log->is_info ) {
			$log->info("duration: [$duration] size: [$size] endian [$endian] offset: [$offset] for $url");
		}

		if ($drm) {
			logWarning("[$url] has DRM. Skipping.");
			$client->controller()->playerStreamingFailed($client, 'PROBLEM_DRM');
			return undef;
		}

		if (!$size && !$duration) {
			logWarning("[$url] not bothering opening file with zero size or duration");
			$client->controller()->playerStreamingFailed($client, 'PROBLEM_OPENING');
			return undef;
		}
	}

	main::INFOLOG && $log->info("Opening file $filepath");

	my $sock = $class->SUPER::new();
	if (!$sock->SUPER::open($filepath)) {
		logError("could not open $filepath: $!");		
		return undef;
	}
	
	binmode($sock);
	
	${*$sock}{'url'}      = $url;
	${*$sock}{'position'} = 0;
	${*$sock}{'logicalEndOfStream'} = $size + $offset;

	$song->samplerate($samplerate) if ($samplerate);
	$song->samplesize($samplesize) if ($samplesize);
	$song->channels($channels) if ($channels);

	$song->totalbytes($size);
	$song->duration($duration);
	$song->offset($offset);
	$song->blockalign($blockalign);
	
	my $format = Slim::Music::Info::contentType($track);
	
	my $seekoffset = $offset;
	my $streamLength = $size;
	
	if (defined $seekdata) {
		
		if (   ! $seekdata->{sourceStreamOffset}
			&& ! $seekdata->{restartOffset}
			&& $seekdata->{'timeOffset'}
			&& canSeek($class, $client, $song) )
		{
			$seekdata->{sourceStreamOffset} = _timeToOffset($sock, $format, $song, $seekdata->{'timeOffset'});
		}
		
		if ($seekdata->{restartOffset}) {								# used for reconnect
			$streamLength = $song->streamLength();
			$seekoffset = $seekdata->{restartOffset};
		} elsif ($seekdata->{sourceStreamOffset}) {						# used for seeking
			$seekoffset = $seekdata->{sourceStreamOffset};
			$streamLength -= $seekdata->{sourceStreamOffset} - $offset;
		} else {
			$seekoffset = $offset;										# normal case
		}
	}

	# Bug 6836 - support CUE files for Ogg
	# Also used for Xing frame in MP3 when seeking
	# WAV header, and ASF header
	${*$sock}{'initialAudioBlockRemaining'} = 0;

	${*$sock}{'streamFormat'} = $args->{'transcoder'}->{'streamformat'};

	if ( $seekoffset
		&& !$song->stripHeader
		# We do not need to worry about an initialAudioBlock when we are restarting
		# as getSeekDataByPosition() will not have allowed a restart within the
		# initialAudioBlock.
		&& !($seekdata && $seekdata->{restartOffset}) )
	{
		my $streamClass = _streamClassForFormat($format);

		if (!defined($song->initialAudioBlock()) && 
			$streamClass && $streamClass->can('getInitialAudioBlock'))
		{
			# We stash the initial audio block in the song because we may well want it
			# multiple times.
			$song->initialAudioBlock($streamClass->getInitialAudioBlock($sock, $track, $seekdata->{'timeOffset'}));
		}
		
		if ($song->initialAudioBlock()) {
			my $length = length($song->initialAudioBlock());
			main::DEBUGLOG && $log->debug("Got initial audio block of size $length");
			if ($seekoffset <= $length) {
				# Might as well just play from the start normally
				$streamLength = $size + $offset;
				$offset = $seekoffset = 0;
			} else {
				${*$sock}{'initialAudioBlockRemaining'} = $length;
				${*$sock}{'initialAudioBlockRef'} = \($song->initialAudioBlock());
				$streamLength += $length;
			}
			
			# For some files, we can't cache the audio block because it's different each time
			$song->initialAudioBlock(undef) if $streamClass->can('volatileInitialAudioBlock') && $streamClass->volatileInitialAudioBlock($track);
		}
	}
	
	if (defined $seekoffset) {
		main::INFOLOG && $log->info("Seeking in $seekoffset into $filepath");
		if (!defined(sysseek($sock, $seekoffset, 0))) {
			logError("could not seek to $seekoffset for $filepath: $!");
		} else {
			$client->songBytes($seekoffset - ($song->stripHeader ? $song->offset : ${*$sock}{'initialAudioBlockRemaining'}));
			${*$sock}{'position'} = $seekoffset;
			if ($seekoffset > $offset && $seekdata && $seekdata->{'timeOffset'}) {
				$song->startOffset($seekdata->{'timeOffset'});
			}
		}
	} else {
		$client->songBytes(0);
	}
	
	$song->streamLength($streamLength);
	
	# Bug 17727 - playback issues with mp3 + cue sheets on Windows
	# there's a bug in MP3::Cut::Gapless which fails the cache file check on Windows
	if ( !main::ISWINDOWS && $format eq 'mp3' && $track->virtual ) {
		eval {
			# Return a gapless MP3 stream for cue sheet tracks
			# XXX avoid calling the above stuff for these tracks, it's just wasted
			require MP3::Cut::Gapless;
		
			my ($start_ms, $end_ms);
		
			if ( $url =~ /#([^-]+)-([^-]+)$/ ) {
				$start_ms = sprintf "%d", $1 * 1000;
				$end_ms   = sprintf "%d", $2 * 1000; # XXX last track should be undef
			}
		
			if ( defined $seekdata && $seekdata->{timeOffset} ) {
				# XXX error checks?
				$start_ms += sprintf "%d", $seekdata->{timeOffset} * 1000;
			}
		
			main::INFOLOG && $log->is_info && $log->info("Opening gapless MP3 stream from time $start_ms to $end_ms");
		
			${*$sock}{mp3cut} = MP3::Cut::Gapless->new(
				file      => $filepath,
				cache_dir => catdir( $prefs->get('librarycachedir'), 'mp3cut' ),
				start_ms  => $start_ms,
				end_ms    => $end_ms,
			);
		};
		if ($@) {
			$log->warn("Unable to play MP3 cue track in gapless mode: $@");
			delete ${*$sock}{mp3cut};
		}
	}

	return $sock;
}

# make this conversion accessible to sub-classes
sub pathFromFileURL {
	Slim::Utils::Misc::pathFromFileURL($_[1]);
}

sub sysread {
	my $self = $_[0];
	my $n	 = $_[2];
	
	if ( ${*$self}{mp3cut} ) {
		# Get audio data from MP3::Cut::Gapless object instead of directly from the file
		$n = ${*$self}{mp3cut}->read( $_[1], $n );
		${*$self}{position} += $n unless (!defined($n) || $n <= 0);
		return $n;
	}

	if (my $length = ${*$self}{'initialAudioBlockRemaining'}) {
		
		my $chunkLength = $length;
		my $chunkref;
		
		main::DEBUGLOG && $log->debug("getting initial audio block of size $length");
		
		if ($length > $n || $length < length(${${*$self}{'initialAudioBlockRef'}})) {
			$chunkLength = $length > $n ? $n : $length;
			my $chunk = substr(${${*$self}{'initialAudioBlockRef'}}, -$length, $chunkLength);
			$chunkref = \$chunk;
			${*$self}{'initialAudioBlockRemaining'} = ($length - $chunkLength);
		} else {
			${*$self}{'initialAudioBlockRemaining'} = 0;
			$chunkref = ${*$self}{'initialAudioBlockRef'};
		}
	
		($_[3] ? substr($_[1], $_[3]) : $_[1]) = $$chunkref;
		return $chunkLength;
	}
	
	else {
		my $remaining = ${*$self}{'logicalEndOfStream'} - ${*$self}{'position'};
		if ($remaining <= 0) {
			$log->warn("Trying to read past the end of file: " . ${*$self}{'url'} );
			return 0;
		}
		if ($n > $remaining) {$n = $remaining;}

		$n = sysread($self, $_[1], $n, $_[3] || 0);
		${*$self}{'position'} += $n unless (!defined($n) || $n <= 0);
		return $n;
	}
}

sub canDirectStream {
	return 0;
}

sub isRemote {
	return 0;
}

sub audioScrobblerSource {
	my ( $class, $client, $url ) = @_;
	
	# Scrobble as 'chosen by user' content
	return 'P';
}

sub contentType {
	my $self = shift;

	return ${*$self}{'contentType'};
}


sub _streamClassForFormat {
	my ($streamFormat) = @_;

	if ($streamFormat && Slim::Formats->loadTagFormatForType($streamFormat)) {
		return Slim::Formats->classForFormat($streamFormat);
	}
}

sub _timeToOffset {
	my $sock     = shift;
	my $format   = shift;
	my $song     = shift;
	my $time     = shift;
	
	my $offset   = $song->offset() || 0;
	my $size     = $song->totalbytes();
	my $duration = $song->duration();
	my $align    = $song->blockalign();

	# Short circuit the computation if the time for which we're asking
	# is outside the song boundaries
	if ($time >= $duration) {
		return $size;
	} elsif ($time < 0) {
		return $offset;
	}

	my $byterate = $duration ? ($size / $duration) : 0;
	my $seekoffset   = int($byterate * $time);

	my $streamClass = _streamClassForFormat($format);

	if ($streamClass && $streamClass->can('findFrameBoundaries')) {
		# Bug 16068, adjust time if this is a virtual track in a cue sheet
		if ( $song->currentTrack()->url =~ /#([^-]+)-([^-]+)$/ ) {
			$time += $1;
		}
		
		main::INFOLOG && $log->is_info && $log->info("seeking using $streamClass findFrameBoundaries(" . ($seekoffset + $offset) . ", $time)");
		$seekoffset  = $streamClass->findFrameBoundaries($sock, $seekoffset + $offset, $time);
	} else {
		$seekoffset -= $seekoffset % $align;
		$seekoffset += $offset;
	}
	
	# Some modules may return -1 to indicate they couldn't find a frame
	if ( $seekoffset < 1 ) {
		$seekoffset = 0;
	}
	
	main::INFOLOG && $log->info("$time -> $seekoffset (align: $align size: $size duration: $duration)");

	return $seekoffset;
}

sub getSeekData {
	my $class    = shift;
	my $client   = shift;
	my $song     = shift; # ignored at the moment
	my $time     = shift;
	
	# Do it all later at open time
	return {timeOffset => $time};
}

sub getSeekDataByPosition {
	my (undef, undef, $song, $bytesReceived) = @_;
	
	my $streamLength = $song->streamLength();
	
	if ( !$streamLength
		|| $song->initialAudioBlock() && $bytesReceived < $song->initialAudioBlock() )
	{
		return undef;
	}

	my $position = $song->totalbytes() - ($streamLength - $bytesReceived);
	
	if ($position <= 0) {
		return undef;
	}
	
	my $seekdata = $song->seekdata || {}; # We preserve the original seekdata so we know the time-offset, if any
	return {%$seekdata, restartOffset => $position + $song->offset()};
}

sub canSeek {
	my ($class, $client, $song) = @_;
	
	my $url = $song->currentTrack()->url;
	
	my $type = Slim::Music::Info::contentType($url);
	
	unless (Slim::Formats->loadTagFormatForType($type)) {return 0;}
	
	my $formatClass = Slim::Formats->classForFormat($type);
	
	return ($formatClass && $formatClass->can('canSeek')) ? $formatClass->canSeek($url) : 0;	
}

sub canSeekError {
	my ($class, $client, $song) = @_;
	
	return ('SEEK_ERROR_TYPE_NOT_SUPPORTED', Slim::Music::Info::contentType($song->currentTrack()->url));
}

sub getIcon {
	my ( $class, $url ) = @_;

	if (Slim::Music::Info::isSong($url)) {
		
		my $track = Slim::Schema->objectForUrl({
			'url' => $url,
		});

		if ($track && $track->coverArt) {
			return 'music/' . $track->id . '/cover.png';
		}

	}
	
	elsif (Slim::Music::Info::isPlaylist($url)) {
		return 'html/images/playlists.png';
	}
	
	return 'html/images/cover.png';
}

1;

__END__
