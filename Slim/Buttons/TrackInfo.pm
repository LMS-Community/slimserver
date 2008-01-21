package Slim::Buttons::TrackInfo;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Displays the extra track information screen that is got into by pressing right on an item 
# in the now playing screen.

=head1 NAME

Slim::Buttons::TrackInfo

=head1 DESCRIPTION

L<Slim::Buttons::TrackInfo> is a module to handle the player UI for 
a list of information about a track in the local library.

=cut

use strict;
use Scalar::Util qw(blessed);

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Log;
use Slim::Utils::Favorites;

our %functions = ();

# button functions for track info screens
sub init {

	Slim::Buttons::Common::addMode('trackinfo', getFunctions(), \&setMode);
	
	Slim::Control::Request::addDispatch(
		[ 'trackinfo', 'items', '_index', '_quantity' ],
		[ 1, 1, 1, \&cliQuery ]
	);

	%functions = (

		'play' => sub  {
			my $client = shift;
			my $button = shift;
			my $addOrInsert = shift;

			playOrAdd($client,$addOrInsert);
		},
	);
}

sub cliQuery {
	my $request = shift;
	
	my $client = $request->client;
	my $url    = $request->getParam('url');
	
	# Default menu, todo
	my $feed = {};
	
	# Protocol Handlers can define their own track info OPML menus
	my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $url );
	if ( $handler && $handler->can('trackInfoURL') ) {
		$feed = $handler->trackInfoURL( $client, $url );
	}
	
	Slim::Buttons::XMLBrowser::cliQuery( 'trackinfo', $feed, $request );
}

sub playOrAdd {
	my $client = shift;
	my $addOrInsert = shift || 0;

	my ($command, $string, $line1);
	
	if ($addOrInsert == 2) {

		$string  = 'INSERT_TO_PLAYLIST';
		$command = "inserttracks";

	} elsif ($addOrInsert == 1) {

		$string  = 'ADDING_TO_PLAYLIST';
		$command = "addtracks";

	} else {

		if (Slim::Player::Playlist::shuffle($client)) {

			$string = 'PLAYING_RANDOMLY_FROM';

		} else {

			$string = 'NOW_PLAYING_FROM';
		}

		$command = "loadtracks";
	}

	my $curItem = $client->trackInfoContent->[$client->modeParam('listIndex')];

	if (!defined $curItem) {
		Slim::Buttons::Common::popModeRight($client);

		$client->execute(["button", $addOrInsert ? "add" : "play", undef]);

		return;
	}

	my ($line2, $termlist) = _trackDataForCurrentItem($client, $curItem);

	if ($client->linesPerScreen == 1) {
		$line2 = $client->doubleString($string);
	} else {
		$line1 = $client->string($string);
	}

	$client->showBriefly( {
		'line'    => [ $line1, $line2 ],
		'overlay' => [ undef, $client->symbols('notesymbol') ]
	});

	$client->execute(['playlist', $command, $termlist]);
}

sub _trackDataForCurrentItem {
	my $client  = shift;
	my $item    = shift || return;

	my $curType = $item->{'type'} || '';
	my $curObj  = $item->{'obj'}  || '';

	my $line2  = blessed($curObj) ? $curObj->name : $curObj;
	my $search = '';

	if (grep { /^$curType$/ } Slim::Schema::Contributor->contributorRoles) {

		$search = sprintf('contributor.id=%d', $curObj->id);

	} elsif (blessed($curObj)) {

		$search = sprintf('%s.id=%d', lc($curType), $curObj->id);

	} else {

		# Don't expect to get here, but just in case.
		$search = sprintf('%s.id=%d', lc($curType), $curObj);
	}

	return ($line2, $search);
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	# Protocol Handlers can setup their own track info
	my $track   = track($client);
	my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $track->url );
	if ( $handler && $handler->can('trackInfo') ) {
		# trackInfo method is responsible for pushing its own mode
		$handler->trackInfo( $client, $track );
		return;
	}

	loadDataForTrack( $client, $track );

	my %params = (
		'header'         => sub { return Slim::Music::Info::getCurrentTitle( $client, $track->url )},
		'headerArgs'     => 'CVI',
		'listRef'        => $client->trackInfoLines,
		'externRef'      => \&infoLine,
		'externRefArgs'  => 'CVI',
		'overlayRef'     => \&overlay,
		'overlayRefArgs' => 'CVI',
		'callback'       => \&listExitHandler,

		# carry some params forward
		'track'          => $client->modeParam('track'),
		'current'        => $client->modeParam('current'),
		'favorite'       => $client->modeParam('favorite'),
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

# get (and optionally set) the track URL
sub track {
	my $client = shift;
	
	unshift @_, 'track';
	return $client->modeParam(@_);
}

sub loadDataForTrack {
	my $client = shift;
	my $url    = shift;

	@{$client->trackInfoLines}   = ();
	@{$client->trackInfoContent} = ();
	
	# Bug 6704
	# Always get the latest data out of the database instead of using cached
	# playlist track object.  This allows a stream title to change dynamically
	# for example
	if ( blessed($url) ) {
		$url = $url->url;
	}

	my $track = Slim::Schema->rs('Track')->objectForUrl($url);

	# Couldn't get a track or URL? How do people get in this state?
	if (!$url || !blessed($track) || !$track->can('title')) {
		push (@{$client->trackInfoLines}, "Error! url: [$url] is empty or a track could not be retrieved.\n");
		push (@{$client->trackInfoContent}, undef);

		return;
	}
	
	# If Audioscrobbler is enabled and the current track can be scrobbled,
	# add 'Last.fm: Love this track' as the first item
	if ( Slim::Utils::PluginManager->isEnabled( 'Slim::Plugin::AudioScrobbler::Plugin' ) ) {
		if ( Slim::Plugin::AudioScrobbler::Plugin->canScrobble( $client, $track ) ) {
			push @{$client->trackInfoLines}, $client->string('PLUGIN_AUDIOSCROBBLER_LOVE_TRACK');
			push @{$client->trackInfoContent}, sub {
				my $client = shift;
				
				$client->execute( [ 'audioscrobbler', 'loveTrack', $track->url ] );
				
				$client->showBriefly( {
					line => [ 
						$client->string('PLUGIN_AUDIOSCROBBLER_LOVE_TRACK'), 
						$client->string('PLUGIN_AUDIOSCROBBLER_TRACK_LOVED'),
					],
				} );
			};
		}
	}

	if (my $title = $track->title) {
		push (@{$client->trackInfoLines}, $client->string('TITLE') . ": $title");
		push (@{$client->trackInfoContent}, undef);
	}

	# Loop through the contributor types and append
	for my $role (sort $track->contributorRoles) {

		for my $contributor ($track->contributorsOfType($role)) {

			push (@{$client->trackInfoLines}, sprintf('%s: %s', $client->string(uc($role)), $contributor->name));
			push (@{$client->trackInfoContent}, {
				'type' => uc($role),
				'obj'  => $contributor,
			});
		}
	}

	# Used below for ReplayGain
	my $album = $track->album;

	if ($album) {
		push (@{$client->trackInfoLines}, join(': ', $client->string('ALBUM'), $album->name));
		push (@{$client->trackInfoContent}, {
			'type' => 'ALBUM',
			'obj'  => $album,
		});
	}

	if (my $tracknum = $track->tracknum) {
		push (@{$client->trackInfoLines}, $client->string('TRACK') . ": $tracknum");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $year = $track->year) {
		push (@{$client->trackInfoLines}, $client->string('YEAR') . ": $year");
		push (@{$client->trackInfoContent}, {
			'type' => 'YEAR',
			'obj'  => $year,
		});
	}

	for my $genre ($track->genres) {

		push (@{$client->trackInfoLines}, join(': ', $client->string('GENRE'), $genre->name));
		push (@{$client->trackInfoContent}, {
			'type' => 'GENRE',
			'obj'  => $genre,
		});
	}

	if (my $ct = Slim::Schema->contentType($track)) {
		push (@{$client->trackInfoLines}, $client->string('TYPE') . ": " . $client->string(uc($ct)));
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $comment = $track->comment) {
		push (@{$client->trackInfoLines}, $client->string('COMMENT') . ": $comment");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $duration = $track->duration) {
		push (@{$client->trackInfoLines}, $client->string('LENGTH') . ": $duration");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $replaygain = $track->replay_gain) {
		push (@{$client->trackInfoLines}, $client->string('REPLAYGAIN') . ": " . sprintf("%2.2f",$replaygain) . " dB");
		push (@{$client->trackInfoContent}, undef);
	}
	
	if (my $rating = $track->rating) {
		push (@{$client->trackInfoLines}, $client->string('RATING') . ": " . sprintf("%d",$rating) . " /100");
		push (@{$client->trackInfoContent}, undef);
	}
	
	if (blessed($album) && $album->can('replay_gain')) {

		if (my $albumreplaygain = $album->replay_gain) {
			push (@{$client->trackInfoLines}, $client->string('ALBUMREPLAYGAIN') . ": " . sprintf("%2.2f",$albumreplaygain) . " dB");
			push (@{$client->trackInfoContent}, undef);
		}
	}

	if ( my $bitrate = ( Slim::Music::Info::getCurrentBitrate($track->url) || $track->prettyBitRate ) ) {
		
		# A bitrate of -1 is set by Scanner::scanBitrate or Formats::*::scanBitrate when the
		# bitrate of a remote stream can't be determined
		if ( $bitrate ne '-1' ) {
			my $undermax = Slim::Player::TranscodingHelper::underMax($client, $track->url);
			my $rate     = $bitrate;
			my $convert  = '';

			if (!$undermax) {

				$rate = Slim::Utils::Prefs::maxRate($client) . $client->string('KBPS') . " ABR";
			}

			if ($client->modeParam('current') && (defined $undermax && !$undermax)) { 

				$convert = sprintf('(%s %s)', $client->string('CONVERTED_TO'), $rate);
			}

			push (@{$client->trackInfoLines}, sprintf("%s: %s %s",
				$client->string('BITRATE'), $bitrate, $convert,
			));

			push (@{$client->trackInfoContent}, undef);
		}
	}

	if ($track->samplerate) {
		push (@{$client->trackInfoLines}, $client->string('SAMPLERATE') . ": " . $track->prettySampleRate);
		push (@{$client->trackInfoContent}, undef);
	}

	if ($track->samplesize) {
		push (@{$client->trackInfoLines}, $client->string('SAMPLESIZE') . ": " . $track->samplesize . " " . $client->string('BITS'));
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $len = $track->filesize) {
		push (@{$client->trackInfoLines}, $client->string('FILELENGTH') . ": " . Slim::Utils::Misc::delimitThousands($len));
		push (@{$client->trackInfoContent}, undef);
	}

	if ( !Slim::Music::Info::isRemoteURL($track->url) ) {
		if (my $age = $track->modificationTime) {
			push (@{$client->trackInfoLines}, $client->string('MODTIME').": $age");
			push (@{$client->trackInfoContent}, undef);
		}
	}

	if (my $url = $track->url) {
		push (@{$client->trackInfoLines}, "URL: ". Slim::Utils::Misc::unescape($url));
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $tag = $track->tagversion) {
		push (@{$client->trackInfoLines}, $client->string('TAGVERSION') . ": $tag");
		push (@{$client->trackInfoContent}, undef);
	}

	if ($track->drm) {
		push (@{$client->trackInfoLines}, $client->string('DRM'));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::isURL($track->url) && Slim::Utils::Favorites->enabled) {

		$client->modeParam( 'favorite', Slim::Utils::Favorites->new($client)->findUrl($track->url) );

		push (@{$client->trackInfoLines}, 'FAVORITE'); # replaced in lines()
		push (@{$client->trackInfoContent}, {
			'type' => 'FAVORITE',
			'obj'  => '',
		});
	}
}

sub listExitHandler {
	my ($client,$exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);
		
	} elsif ($exittype eq 'RIGHT') {

		my $push     = 1;

		# Look up if this is an artist, album, year etc
		my $curItem  = $client->trackInfoContent->[$client->modeParam('listIndex')] || '';
		my $oldlines = $client->curLines();

		# Get object for currently being browsed song from the datasource
		# This probably isn't necessary as track($client) is already an object!
		my $track = Slim::Schema->rs('Track')->objectForUrl(track($client));

		if (!blessed($track)) {

			logError("Unable to fetch valid track object for currently selected item!");
			return 0;
		}

		my $album       = $track->album;
		my $contributor = '';
		my $curType     = '';
		my $curObj      = '';

		if (ref($curItem) eq 'HASH') {
			$curType = $curItem->{'type'};
			$curObj  = $curItem->{'obj'};
		}
		elsif ( ref $curItem eq 'CODE' ) {
			return $curItem->( $client );
		}

		# Tracks can not have an artist at all, but have a different
		# type of contributor. Use that if we are looking for that type.
		if (grep { /^$curType$/ } Slim::Schema::Contributor->contributorRoles) {

			$contributor = $curObj;

		} else {

			$contributor = $track->artist;
		}

		# Bug: 2528 Only check to see if album & contributor are valid
		# objects if we're going to be performing a method call on
		# them. Otherwise it's ok to not have them for Internet Radio
		# streams which can be saved to favorites.
		if ($curType && $curObj) {

			if (!blessed($album) || !blessed($contributor)) {

				logError("Unable to fetch valid album or artist object for currently selected track!");
				return 0;
			}
		}

		my $selectionCriteria = {
			'track.id'       => $track->id,
			'album.id'       => ( blessed $album ) ? $album->id : undef,
			'contributor.id' => ( blessed $contributor ) ? $contributor->id : undef,
		};

		if ($curType eq 'ALBUM') {

			Slim::Buttons::Common::pushMode($client, 'browsedb', {
				'hierarchy'         => 'album,track',
				'level'             => 1,
				'findCriteria'      => { 'album.id' => $curObj->id },
				'selectionCriteria' => $selectionCriteria,
			});

		} elsif (grep { /^$curType$/ } Slim::Schema::Contributor->contributorRoles) {

			Slim::Buttons::Common::pushMode($client, 'browsedb', {
				'hierarchy'         => 'contributor,album,track',
				'level'             => 1,
				'findCriteria'      => {
					'contributor.id'   => $curObj->id,
					'contributor.role' => $curType,
				},
				'selectionCriteria' => $selectionCriteria,
			});

		} elsif ($curType eq 'GENRE') {

			Slim::Buttons::Common::pushMode($client, 'browsedb', {
				'hierarchy'         => 'genre,contributor,album,track',
				'level'             => 1,
				'findCriteria'      => { 'genre.id' => $curObj->id },
				'selectionCriteria' => $selectionCriteria,
			});

		} elsif ($curType eq 'YEAR') {

			Slim::Buttons::Common::pushMode($client, 'browsedb', {
				'hierarchy'         => 'year,album,track',
				'level'             => 1,
				'findCriteria'      => { 'year.id' => $curObj },
				'selectionCriteria' => $selectionCriteria,
			});

		} elsif ($curType eq 'FAVORITE') {

			my $favorites = Slim::Utils::Favorites->new($client);
			my $favIndex = $client->modeParam('favorite');

			if (!defined $favIndex) {

				$favIndex = $favorites->add(track($client), $track->title || $track->url);

				$client->showBriefly( {
					'line' => [ $client->string('FAVORITES_ADDING'), $track->title || $track->url ]
				   });

				$client->modeParam('favorite', $favIndex);

			} else {

				# Bug 6177, Menu to confirm favorite removal
				Slim::Buttons::Common::pushModeLeft( $client, 'favorites.delete', {
					title => $track->title || $track->url,
					index => $favIndex,
					depth => 2,
				} );
				
			}

			$push = 0;

		} else {

			$push = 0;
			$client->bumpRight;
		}

		if ($push) {
			$client->pushLeft($oldlines, $client->curLines());
		}
	}
}

sub infoLine {
	my ($client,$value,$index) = @_;

	# 2nd line's content is provided entirely by trackInfoLines, which returns an array of information lines
	my $line2 = $client->trackInfoLines->[$index];

	# special case favorites line, which must be determined dynamically
	if ($line2 eq 'FAVORITE') {
		my $favIndex = $client->modeParam('favorite');
		if (!defined $favIndex) {
			$line2 = $client->string('FAVORITES_RIGHT_TO_ADD');
		} else {
			if ($favIndex =~ /^\d+$/) {
				# existing favorite at top level - display favorite number starting at 1 (favs are zero based)
				$line2 = $client->string('FAVORITES_FAVORITE') . ' ' . ($favIndex + 1);
			} else {
				# existing favorite not at top level - don't display number
				$line2 = $client->string('FAVORITES_FAVORITE');
			}
		}
	}

	return $line2;
}

sub overlay {
	my ($client,$value,$index) = @_;

	# add position string
	my $overlay1 = ' (' . ($index+1) . ' ' . $client->string('OF') .' ' . scalar(@{$client->trackInfoLines}) . ')';

	# add note symbol
	$overlay1 .= $client->symbols('notesymbol');

	# add right arrow symbol if current line can point to more info e.g. artist, album, year etc
	my $overlay2 = defined($client->trackInfoContent->[$index]) ? $client->symbols('rightarrow') : undef;

	return ($overlay1, $overlay2);
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;

__END__
