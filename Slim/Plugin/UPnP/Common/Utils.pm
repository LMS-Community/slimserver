package Slim::Plugin::UPnP::Common::Utils;

### TODO
#
# Support time-based seek for video using Media::Scan
# DLNA 7.3.59.2, ALLIP
# Avoid using duplicate ObjectIDs for the same item under different paths, use refID instead?
# /cover URLs don't support Range requests, or have correct *.dlna.org header support

use strict;

use Scalar::Util qw(blessed);
use POSIX qw(strftime);
use List::Util qw(min);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

use Exporter::Lite;
our @EXPORT_OK = qw(xmlEscape xmlUnescape secsToHMS hmsToSecs absURL trackDetails videoDetails imageDetails);

my $log   = logger('plugin.upnp');
my $prefs = preferences('server');

use constant DLNA_FLAGS        => sprintf "%.8x%.24x", (1 << 24) | (1 << 22) | (1 << 21) | (1 << 20), 0;
use constant DLNA_FLAGS_IMAGES => sprintf "%.8x%.24x", (1 << 23) | (1 << 22) | (1 << 21) | (1 << 20), 0;

my $HAS_LAME;
sub HAS_LAME {
	return $HAS_LAME if defined $HAS_LAME;
	
	$HAS_LAME = Slim::Utils::Misc::findbin('lame') ? 1 : 0;
	return $HAS_LAME;
}

sub xmlEscape {
	my $text = shift;
	
	if ( $text =~ /[\&\<\>'"]/) {
		$text =~ s/&/&amp;/go;
		$text =~ s/</&lt;/go;
		$text =~ s/>/&gt;/go;
		$text =~ s/'/&apos;/go;
		$text =~ s/"/&quot;/go;
	}
	
	return $text;
}

sub xmlUnescape {
	my $text = shift;
	
	if ( $text =~ /[\&]/) {
		$text =~ s/&amp;/&/go;
		$text =~ s/&lt;/</go;
		$text =~ s/&gt;/>/go;
		$text =~ s/&apos;/'/go;
		$text =~ s/&quot;/"/go;
	}
	
	return $text;
}

# seconds to H:MM:SS[.F+]
sub secsToHMS {
	my $secs = shift;
	
	my $elapsed = sprintf '%d:%02d:%02d', int($secs / 3600) % 24, int($secs / 60) % 60, $secs % 60;
	
	if ( $secs =~ /(\.\d+)$/ ) {
		my $frac = sprintf( '%.3f', $1 );
		$frac =~ s/^0//;
		$elapsed .= $frac;
	}
	
	return $elapsed;
}

# H:MM:SS[.F+] to seconds
sub hmsToSecs {
	my $hms = shift;
	
	my ($h, $m, $s) = split /:/, $hms;
	
	return ($h * 3600) + ($m * 60) + $s;
}

sub absURL {
	my ($path, $addr) = @_;
	
	if ( !$addr ) {
		$addr = Slim::Utils::Network::serverAddr();
	}
	
	($addr) = split /:/, $addr; # remove port in case it gets here from the Host header
	
	my $hostport = $addr . ':' . $prefs->get('httpport');
	
	return xmlEscape("http://${hostport}${path}");
}

sub trackDetails {
	my ( $track, $filter, $request_addr ) = @_;
	
	my $filterall = ($filter =~ /\*/);
	
	if ( blessed($track) ) {
		# Convert from a Track object
		# Going through a titles query request will be the fastest way, to avoid slow DBIC joins and such.
		my $request = Slim::Control::Request->new( undef, [ 'titles', 0, 1, 'track_id:' . $track->id, 'tags:AGldyorfTIct' ] );
		$request->execute();
		if ( $request->isStatusError ) {
			$log->error('Cannot convert Track object to hashref: ' . $request->getStatusText);
			return '';
		}
		
		my $results = $request->getResults;
		if ( $results->{count} != 1 ) {
			$log->error('Cannot convert Track object to hashref: no track found');
			return '';
		}
		
		$track = $results->{titles_loop}->[0];
	}
	
	my $xml;
	
	my @albumartists = split /, /, $track->{albumartist};
	my @artists      = split /, /, $track->{artist};
	
	my $primary_artist = $albumartists[0] ? $albumartists[0] : $artists[0];
	
	# This supports either track data from CLI results or _getTagDataForTracks, thus
	# the checks for alternate hash keys
	
	$xml .= '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
		. '<dc:title>' . xmlEscape($track->{title} || $track->{'tracks.title'}) . '</dc:title>';
	
	if ( $filterall || $filter =~ /dc:creator/ ) {
		$xml .= '<dc:creator>' . xmlEscape($primary_artist) . '</dc:creator>';
	}
	
	if ( $filterall || $filter =~ /upnp:album/ ) {
		$xml .= '<upnp:album>' . xmlEscape($track->{album} || $track->{'albums.title'}) . '</upnp:album>';
	}
	
	my %roles;
	map { push @{$roles{albumartist}}, $_ } @albumartists;
	map { push @{$roles{artist}}, $_ } @artists;
	map { push @{$roles{composer}}, $_ } split /, /, $track->{composer};
	map { push @{$roles{conductor}}, $_ } split /, /, $track->{conductor};
	map { push @{$roles{band}}, $_ } split /, /, $track->{band};
	map { push @{$roles{trackartist}}, $_ } split /, /, $track->{trackartist};
	
	my $artistfilter = ( $filterall || $filter =~ /upnp:artist/ );
	my $contribfilter = ( $filterall || $filter =~ /dc:contributor/ );
	while ( my ($role, $names) = each %roles ) {
		for my $artist ( @{$names} ) {
			my $x = xmlEscape($artist);
			if ( $artistfilter ) { $xml .= "<upnp:artist role=\"${role}\">${x}</upnp:artist>"; }
			if ( $contribfilter ) { $xml .= "<dc:contributor>${x}</dc:contributor>"; }
		}
	}
	
	if ( my $tracknum = ($track->{tracknum} || $track->{'tracks.tracknum'}) ) {
		if ( $filterall || $filter =~ /upnp:originalTrackNumber/ ) {
			$xml .= "<upnp:originalTrackNumber>${tracknum}</upnp:originalTrackNumber>";
		}
	}
	
	if ( my $date = ($track->{year} || $track->{'tracks.year'}) ) {
		if ( $filterall || $filter =~ /dc:date/ ) {
			$xml .= "<dc:date>${date}-01-01</dc:date>"; # DLNA requires MM-DD values
		}
	}
	
	if ( my @genres = split /, /, ($track->{genres} || $track->{genre} || $track->{'genres.name'}) ) { # XXX we don't actually fetch multiple genres currently
		if ( $filterall || $filter =~ /upnp:genre/ ) {
			for my $genre ( @genres ) {
				$xml .= '<upnp:genre>' . xmlEscape($genre) . '</upnp:genre>';
			}
		}
	}
	
	if ( my $coverid = ($track->{coverid} || $track->{'tracks.coverid'}) ) {
		if ( $filterall || $filter =~ /upnp:albumArtURI/ ) {
			# DLNA 7.3.61.1, provide multiple albumArtURI items, at least one of which is JPEG_TN (160x160)
			$xml .= '<upnp:albumArtURI dlna:profileID="JPEG_TN" xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">'
				. absURL("/music/$coverid/cover_160x160_m.jpg", $request_addr) . '</upnp:albumArtURI>';
			$xml .= '<upnp:albumArtURI>' . absURL("/music/$coverid/cover", $request_addr) . '</upnp:albumArtURI>';
		}
	}
	
	# mtime is used for all values as fallback
	my $mtime = $track->{modificationTime} || $track->{'tracks.timestamp'};
	
	if ( $filterall || $filter =~ /pv:modificationTime/ ) {
		$xml .= "<pv:modificationTime>${mtime}</pv:modificationTime>";
	}
	
	if ( $filterall || $filter =~ /pv:addedTime/ ) {
		my $added_time = $track->{addedTime} || $track->{'tracks.added_time'} || $mtime;
		$xml .= "<pv:addedTime>${added_time}</pv:addedTime>";
	}
	
	if ( $filterall || $filter =~ /pv:lastUpdated/ ) {
		my $updated = $track->{lastUpdated} || $track->{'tracks.updated_time'} || $mtime;
		$xml .= "<pv:lastUpdated>${updated}</pv:lastUpdated>";
	}
	
	if ( $filterall || $filter =~ /res/ ) {
		my ($bitrate) = $track->{bitrate} =~ /^(\d+)/;
		if ( !$bitrate && $track->{'tracks.bitrate'} ) {
			$bitrate = $track->{'tracks.bitrate'} / 1000;
		}
		
		# We need to provide a <res> for the native file, as well as compatability formats via transcoding
		my $content_type = $track->{type} || $track->{'tracks.content_type'};
		my $native_type = $Slim::Music::Info::types{$content_type};
		
		# Bug 17882, use DLNA-required audio/mp4 instead of audio/m4a
		$native_type = 'audio/mp4' if $native_type eq 'audio/m4a';
		
		# Setup transcoding formats for non-PCM/MP3 content
		my @other_types;
		if ( $content_type !~ /^(?:mp3|aif|pcm|wav)$/ ) {
			push @other_types, 'audio/mpeg' if HAS_LAME();
			push @other_types, 'audio/L16';
		}
		else {
			# Fix PCM type string
			if ( $content_type ne 'mp3' ) {
				$native_type = 'audio/L16';
			}
		}
		
		for my $type ( $native_type, @other_types ) {
			my $dlna;
			my $ext = Slim::Music::Info::mimeToType($type);
			
			if ( $type eq $native_type ) {
				my $profile = $track->{dlna_profile} || $track->{'tracks.dlna_profile'};
				if ( $profile ) {
					my $canseek = ($profile eq 'MP3' || $profile =~ /^WMA/);
					$dlna = "DLNA.ORG_PN=${profile};DLNA.ORG_OP=" . ($canseek ? '11' : '01') . ";DLNA.ORG_FLAGS=01700000000000000000000000000000";
				}
				else {
					my $canseek = ($type eq 'audio/x-flac' || $type eq 'audio/x-ogg');
					$dlna = 'DLNA.ORG_OP=' . ($canseek ? '11' : '01') . ";DLNA.ORG_FLAGS=01700000000000000000000000000000";
				}
			}
			else {
				# Add DLNA.ORG_CI=1 for transcoded content
				if ( $type eq 'audio/mpeg' ) {
					$dlna = 'DLNA.ORG_PN=MP3;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000';
				}
				elsif ( $type eq 'audio/L16' ) {
					$dlna = 'DLNA.ORG_PN=LPCM;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000';
					
					$ext = 'aif';
					$type .= ';rate=' . ($track->{samplerate} || $track->{'tracks.samplerate'})
						. ';channels=' . ($track->{channels} || $track->{'tracks.channels'});
				}
			}
			
			$xml .= '<res protocolInfo="http-get:*:' . $type . ':' . $dlna . '"';
		
			if ( ($filterall || $filter =~ /res\@size/) && $type eq $native_type ) {
				# Size only available for native type
				$xml .= ' size="' . ($track->{filesize} || $track->{'tracks.filesize'}) . '"';
			}
			if ( $filterall || $filter =~ /res\@duration/ ) {
				$xml .= ' duration="' . secsToHMS($track->{duration} || $track->{'tracks.secs'}) . '"';
			}
			if ( ($filterall || $filter =~ /res\@bitrate/) && $type eq $native_type ) {
				# Bitrate only available for native type
				$xml .= ' bitrate="' . (($bitrate * 1000) / 8) . '"'; # yes, it's bytes/second for some reason
			}

			if ( my $bps = ($track->{samplesize} || $track->{'tracks.samplesize'}) ) {
				if ( $filterall || $filter =~ /res\@bitsPerSample/ ) {
					$xml .= " bitsPerSample=\"${bps}\"";
				}
			}

			if ( $filterall || $filter =~ /res\@sampleFrequency/ ) {
				$xml .= ' sampleFrequency="' . ($track->{samplerate} || $track->{'tracks.samplerate'}) . '"';
			}
			
			if ( $ext eq 'mp3' ) {
				$ext = 'mp3?bitrate=320';
			}
		
			$xml .= '>' . absURL('/music/' . ($track->{id} || $track->{'tracks.id'}) . '/download.' . $ext, $request_addr) . '</res>';
		}
	}
	
	return $xml;
}

sub videoDetails {
	my ( $video, $filter, $request_addr ) = @_;
	
	my $filterall = ($filter =~ /\*/);
	
	my $xml;
	
	# This supports either track data from CLI results or _getTagDataForTracks, thus
	# the checks for alternate hash keys
	
	my $hash = $video->{id} || $video->{'videos.id'}; # id is the hash column
	
	$xml .= '<upnp:class>object.item.videoItem</upnp:class>'
		. '<dc:title>' . xmlEscape($video->{title} || $video->{'videos.title'}) . '</dc:title>';
	
	if ( $filterall || $filter =~ /upnp:album/ ) {
		$xml .= '<upnp:album>' . xmlEscape($video->{album} || $video->{'videos.album'}) . '</upnp:album>';
	}

	# DLNA 7.3.60 specifies that image/video thumbnails should be provided in a separate <res> item, but a lot
	# of clients need albumArtURI. We will return both methods
	if ( $filterall || $filter =~ /upnp:albumArtURI/ ) {
		# DLNA 7.3.61.1, provide multiple albumArtURI items, at least one of which is JPEG_TN (160x160)
		$xml .= '<upnp:albumArtURI dlna:profileID="JPEG_TN" xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">'
			. absURL("/video/${hash}/cover_160x160_m.jpg", $request_addr) . '</upnp:albumArtURI>';
		$xml .= '<upnp:albumArtURI>' . absURL("/video/${hash}/cover", $request_addr) . '</upnp:albumArtURI>';
	}
	
	# mtime is used for all values as fallback
	my $mtime = $video->{mtime} || $video->{'videos.mtime'};
	
	if ( $filterall || $filter =~ /pv:modificationTime/ ) {
		$xml .= "<pv:modificationTime>${mtime}</pv:modificationTime>";
	}
	
	if ( $filterall || $filter =~ /pv:addedTime/ ) {
		my $added_time = $video->{added_time} || $video->{'videos.added_time'} || $mtime;
		$xml .= "<pv:addedTime>${added_time}</pv:addedTime>";
	}
	
	if ( $filterall || $filter =~ /pv:lastUpdated/ ) {
		my $updated = $video->{updated_time} || $video->{'videos.updated_time'} || $mtime;
		$xml .= "<pv:lastUpdated>${updated}</pv:lastUpdated>";
	}
	
	if ( $filterall || $filter =~ /res/ ) {
		my ($bitrate) = $video->{bitrate} =~ /^(\d+)/;
		if ( !$bitrate && $video->{'videos.bitrate'} ) {
			$bitrate = $video->{'videos.bitrate'} / 1000;
		}
		
		my $type = $video->{mime_type} || $video->{'videos.mime_type'};
		
		my $dlna = '*';
		if ( my $profile = $video->{dlna_profile} || $video->{'videos.dlna_profile'} ) {
			# XXX support time-based video seeking via Media::Scan
			$dlna = "DLNA.ORG_PN=${profile};DLNA.ORG_OP=01;DLNA.ORG_FLAGS=" . DLNA_FLAGS();
		}
		
		$xml .= '<res protocolInfo="http-get:*:' . $type . ":${dlna}\"";
	
		if ( ($filterall || $filter =~ /res\@size/) ) {
			$xml .= ' size="' . ($video->{filesize} || $video->{'videos.filesize'}) . '"';
		}
		if ( $filterall || $filter =~ /res\@duration/ ) {
			$xml .= ' duration="' . secsToHMS($video->{duration} || $video->{'videos.secs'}) . '"';
		}
		if ( ($filterall || $filter =~ /res\@bitrate/) ) {
			$xml .= ' bitrate="' . (($bitrate * 1000) / 8) . '"'; # yes, it's bytes/second for some reason
		}
		if ( ($filterall || $filter =~ /res\@resolution/) ) {
			$xml .= ' resolution="' . $video->{width} . 'x' . $video->{height} . '"';
		}
	
		$xml .= '>' . absURL("/video/${hash}/download", $request_addr) . '</res>';
		
		# DLNA 7.3.60, provide video thumbnails as <res> items
		$xml .= '<res protocolInfo="http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_TN;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=' . DLNA_FLAGS_IMAGES() . '">'
			. absURL("/video/${hash}/cover_160x160_m.jpg", $request_addr)
			. '</res>';
		$xml .= '<res protocolInfo="http-get:*:image/png:DLNA.ORG_PN=PNG_TN;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=' . DLNA_FLAGS_IMAGES() . '">'
			. absURL("/video/${hash}/cover_160x160_m.png", $request_addr)
			. '</res>';
	}
	
	return $xml;
}

sub imageDetails {
	my ( $image, $filter, $request_addr ) = @_;
	
	my $filterall = ($filter =~ /\*/);
	
	my $xml;
	
	# This supports either track data from CLI results or _getTagDataForTracks, thus
	# the checks for alternate hash keys
	
	my $hash = $image->{id} || $image->{'images.id'}; # id is the hash column
	
	$xml .= '<upnp:class>object.item.imageItem.photo</upnp:class>'
		. '<dc:title>' . xmlEscape($image->{title} || $image->{'images.title'}) . '</dc:title>';
		
	if ( $image->{original_time} ) {
		if ( $filterall || $filter =~ /dc:date/ ) {
			my @time = localtime($image->{original_time});
		
			if (scalar @time > 5) {
				$xml .= '<dc:date>' . xmlEscape( strftime('%Y-%m-%d', @time) ) . '</dc:date>'
			}
		}
	}
	
	if ( $filterall || $filter =~ /upnp:album/ ) {
		$xml .= '<upnp:album>' . xmlEscape($image->{album} || $image->{'images.album'}) . '</upnp:album>';
	}

	# DLNA 7.3.60 specifies that image/video thumbnails should be provided in a separate <res> item, but a lot
	# of clients need albumArtURI. We will return both methods
	if ( $filterall || $filter =~ /upnp:albumArtURI/ ) {
		# DLNA 7.3.61.1, provide multiple albumArtURI items, at least one of which is JPEG_TN (160x160)
		$xml .= '<upnp:albumArtURI dlna:profileID="JPEG_TN" xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">'
			. absURL("/image/${hash}/cover_160x160_m.jpg", $request_addr) . '</upnp:albumArtURI>';
		$xml .= '<upnp:albumArtURI dlna:profileID="PNG_TN" xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">'
			. absURL("/image/${hash}/cover_160x160_m.png", $request_addr) . '</upnp:albumArtURI>';
	}
	
	# XXX is this OK to use as modificationTime?
	my $mtime = $image->{original_time} || $image->{'images.original_time'};
	
	if ( $filterall || $filter =~ /pv:modificationTime/ ) {
		$xml .= "<pv:modificationTime>${mtime}</pv:modificationTime>";
	}
	
	if ( $filterall || $filter =~ /pv:addedTime/ ) {
		my $added_time = $image->{added_time} || $image->{'images.added_time'} || $mtime;
		$xml .= "<pv:addedTime>${added_time}</pv:addedTime>";
	}
	
	if ( $filterall || $filter =~ /pv:lastUpdated/ ) {
		my $updated = $image->{updated_time} || $image->{'images.updated_time'} || $mtime;
		$xml .= "<pv:lastUpdated>${updated}</pv:lastUpdated>";
	}
	
	if ( $filterall || $filter =~ /res/ ) {
		my $type = $image->{mime_type} || $image->{'images.mime_type'};
		my $profile = $image->{dlna_profile} || $image->{'images.dlna_profile'};
		my $transcoded = 0;
		
		# Don't serve BMP files directly, they are too huge and most clients can't render them anyway.
		# Always serve them as JPG
		if ( $type =~ /bmp/ ) {
			$transcoded = 1;
			$type = 'image/jpeg';
			$profile = 'JPEG_LRG';
		}

		my $dlna = '*';
		if ($profile) {
			$dlna  = "DLNA.ORG_PN=${profile};";
			$dlna .= "DLNA.ORG_CI=1;" if $transcoded;
			$dlna .= "DLNA.ORG_OP=01;DLNA.ORG_FLAGS=" . DLNA_FLAGS_IMAGES();
		}
		
		$xml .= '<res protocolInfo="http-get:*:' . $type . ":${dlna}\"";
	
		if ( !$transcoded && ($filterall || $filter =~ /res\@size/) ) {
			$xml .= ' size="' . ($image->{filesize} || $image->{'images.filesize'}) . '"';
		}
		if ( ($filterall || $filter =~ /res\@resolution/) ) {
			$xml .= ' resolution="' . $image->{width} . 'x' . $image->{height} . '"';
		}
		
		my $maxSize = $prefs->get('maxUPnPImageSize');
	
		# if the image isn't default landscape mode, send it through the resizer to fix the orientation
		if ( $image->{width} > $maxSize || ($image->{orientation} && ($image->{width} || $image->{height})) ) {
			# XXX - PlugPlayer fails to display full size rotated images?
			# limiting to full HD resolution for now, speeding up rendering considerably
			# XXX - don't use image's exact width/height, as this would cause the resizer to short-circuit without rotating the image first...
			my $maxSize = min($maxSize || 9999, ($image->{width} || 9999) - 1, ($image->{height} || 9999) - 1);
			
			$xml .= '>' . absURL("/image/${hash}/cover_${maxSize}x${maxSize}_o", $request_addr) . '</res>';
		}
		else {
			if ($transcoded) {
				$xml .= '>' . absURL("/image/${hash}/cover.jpg", $request_addr) . '</res>';
			}
			else {
				$xml .= '>' . absURL("/image/${hash}/cover", $request_addr) . '</res>';
			}
		}
		
		# DLNA 7.3.60, provide image thumbnails as <res> items
		$xml .= '<res protocolInfo="http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_TN;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=' . DLNA_FLAGS_IMAGES() . '">'
			. absURL("/image/${hash}/cover_160x160_m.jpg", $request_addr)
			. '</res>';
		$xml .= '<res protocolInfo="http-get:*:image/png:DLNA.ORG_PN=PNG_TN;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=' . DLNA_FLAGS_IMAGES() . '">'
			. absURL("/image/${hash}/cover_160x160_m.png", $request_addr)
			. '</res>';
	}
	
	return $xml;
}

1;
