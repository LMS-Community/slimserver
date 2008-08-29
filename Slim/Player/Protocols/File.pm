package Slim::Player::Protocols::File;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech, Vidur Apparao.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

use strict;
use base qw(IO::File);

use File::Spec::Functions qw(:ALL);
use IO::String;

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Formats;
use Slim::Player::Source;

use constant MAXCHUNKSIZE => 32768;

my $log = logger('player.source');

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
	my $seekdata = $args->{'song'}->{'seekdata'};
	
	my $seekoffset = 0;

	my $filepath = Slim::Utils::Misc::pathFromFileURL($url);

	my ($size, $duration, $offset, $samplerate, $samplesize, $channels, $blockalign, $endian, $drm) =
		(0, 0, 0, 0, 0, 0, 0, undef, undef);
			
	# don't try and read this if we're a pipe
	if (!-p $filepath) {

		$size       = $track->audio_size() || -s $filepath;
		$duration   = $track->durationSeconds();
		$offset     = $track->audio_offset() || 0;
		$samplerate = $track->samplerate() || 0;
		$samplesize = $track->samplesize() || 0;
		$channels   = $track->channels() || 0;
		$blockalign = $track->block_alignment() || 1;
		$endian     = $track->endian() || '';
		$drm        = $track->drm();
		
		if ( $log->is_info ) {
			$log->info("duration: [$duration] size: [$size] endian [$endian] offset: [$offset] for $url");
		}

		if ($drm) {
			logWarning("[$url] has DRM. Skipping.");
			Slim::Player::Source::errorOpening($client, 'PROBLEM_DRM');
			return undef;
		}

		if (!$size && !$duration) {
			logWarning("[$url] not bothering opening file with zero size or duration");
			Slim::Player::Source::errorOpening($client);
			return undef;
		}
	}

	$log->info("Opening file $filepath");

	my $sock = $class->SUPER::new();
	if (!$sock->SUPER::open($filepath)) {
		logError("could not open $filepath: $!");		
		return undef;
	}
	
	${*$sock}{'position'} = 0;
	${*$sock}{'logicalEndOfStream'} = $size + $offset;

	$song->{'samplerate'} = $samplerate if ($samplerate);
	$song->{'samplesize'} = $samplesize if ($samplesize);
	$song->{'channels'}   = $channels if ($channels);

	$song->{'totalbytes'} = $size;
	$song->{'duration'}   = $duration;
	$song->{'offset'}     = $offset;
	$song->{'blockalign'} = $blockalign;
	
	my $format = Slim::Music::Info::contentType($track);
	
	my $seekoffset = $offset;
	
	if (defined $seekdata) {
		
		if (!$seekdata->{sourceStreamOffset} && !$seekdata->{playingStreamOffset} && $seekdata->{'timeOffset'}) {
			$seekdata->{sourceStreamOffset} = _timeToOffset($sock, $format, $song, $seekdata->{'timeOffset'});
		}
		
		if ($seekdata->{sourceStreamOffset}) {							# used for seeking
			$seekoffset = $seekdata->{sourceStreamOffset};
		} elsif ($seekdata->{playingStreamOffset}) {					# used for reconnect
			$seekoffset = $offset + $seekdata->{playingStreamOffset};
		} else {
			$seekoffset = $offset;										# normal case
		}
	}

	# Bug 6836 - support CUE files for Ogg
	${*$sock}{'initialAudioBlockRemaining'} = 0;

	if ( $seekoffset && $format eq 'ogg' ) {
		my $streamClass = _streamClassForFormat($format);

		if (!defined($song->{'initialAudioBlock'}) && 
			$streamClass && $streamClass->can('getInitialAudioBlock'))
		{
			# We stash the initial audio block in the song because we may well want it
			# multiple times.
			$song->{'initialAudioBlock'} = $streamClass->getInitialAudioBlock($sock);

			my $length = length($song->{'initialAudioBlock'});
			$log->debug("Got initial audio block of size $length");
			if ($seekoffset <= $length) {
				# Might as well just play from the start normally
				$offset = $seekoffset = 0;
			} else {
				${*$sock}{'initialAudioBlockRemaining'} = $length;
				${*$sock}{'initialAudioBlockRef'} = \$song->{'initialAudioBlock'};
			}
		}
	}
	
	if ($seekoffset) {
		$log->info("Seeking in $seekoffset into $filepath");
		if (!defined(sysseek($sock, $seekoffset, 0))) {
			logError("could not seek to $seekoffset for $filepath: $!");
		} else {
			$client->songBytes($seekoffset);
			${*$sock}{'position'} = $seekoffset;
			if ($seekoffset > $offset && $seekdata && $seekdata->{'timeOffset'}) {
				$song->{'startOffset'} = $seekdata->{'timeOffset'};
			}
		}
	}

	return $sock;
}

sub sysread {
    my $self = $_[0];
    my $n    = $_[2];

	if (my $length = ${*$self}{'initialAudioBlockRemaining'}) {
		
		my $chunkLength = $length;
		my $chunkref;
		
		$log->debug("getting initial audio block of size $length");
		
		if ($length > $n) {
			$chunkLength = $n;
			$chunkref = substr(${*$self}{'initialAudioBlockRef'}, -$length, $chunkLength);
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

		$n = sysread($self, $_[1], $n, $_[3]);
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
	
	my $offset   = $song->{'offset'} || 0;
	my $size     = $song->{'totalbytes'};
	my $duration = $song->{'duration'};
	my $align    = $song->{'blockalign'};

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
		$seekoffset  = $streamClass->findFrameBoundaries($sock, $seekoffset + $offset);
	} else {
		$seekoffset -= $seekoffset % $align;
		$seekoffset += $offset;
	}
	
	$log->info("$time -> $seekoffset (align: $align size: $size duration: $duration)");

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

sub canSeek {
	my ($class, $client, $song) = @_;
	
	my $url = $song->currentTrack()->url;
	
	my $type = Slim::Music::Info::contentType($url);
	
	unless (Slim::Formats->loadTagFormatForType($type)) {return 0;}
	
	my $formatClass = Slim::Formats->classForFormat($type);
	
	return ($formatClass && $formatClass->can('canSeek')) ? $formatClass->canSeek($url) : 0;	
}

1;

__END__
