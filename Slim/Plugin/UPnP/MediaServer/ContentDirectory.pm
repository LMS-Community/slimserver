package Slim::Plugin::UPnP::MediaServer::ContentDirectory;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use I18N::LangTags qw(extract_language_tags);
use URI::Escape qw(uri_escape_utf8 uri_escape);
use SOAP::Lite;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Text;
use Slim::Web::HTTP;

use Slim::Plugin::UPnP::Common::Utils qw(xmlEscape absURL secsToHMS trackDetails);

use constant EVENT_RATE => 2;

my $log = logger('plugin.upnp');
my $prefs = preferences('server');

my $STATE;

sub init {
	my $class = shift;

	Slim::Web::Pages->addPageFunction(
		'plugins/UPnP/MediaServer/ContentDirectory.xml',
		\&description,
	);

	$STATE = {
		SystemUpdateID => Slim::Music::Import->lastScanTime(),
		_subscribers   => 0,
		_last_evented  => 0,
	};

	# Monitor for changes in the database
	Slim::Control::Request::subscribe( \&refreshSystemUpdateID, [['rescan'], ['done']] );
}

sub shutdown { }

sub refreshSystemUpdateID {
	$STATE->{SystemUpdateID} = Slim::Music::Import->lastScanTime();
	__PACKAGE__->event('SystemUpdateID');
}

sub description {
	my ( $client, $params ) = @_;

	main::DEBUGLOG && $log->is_debug && $log->debug('MediaServer ContentDirectory.xml requested by ' . $params->{userAgent});

	return Slim::Web::HTTP::filltemplatefile( "plugins/UPnP/MediaServer/ContentDirectory.xml", $params );
}

### Eventing

sub subscribe {
	my ( $class, $client, $uuid ) = @_;

	# Bump the number of subscribers
	$STATE->{_subscribers}++;

	# Send initial event
	sendEvent( $uuid, 'SystemUpdateID' );
}

sub event {
	my ( $class, $var ) = @_;

	if ( $STATE->{_subscribers} ) {
		# Don't send more often than every 0.2 seconds
		Slim::Utils::Timers::killTimers( undef, \&sendEvent );

		my $lastAt = $STATE->{_last_evented};
		my $sendAt = Time::HiRes::time();

		if ( $sendAt - $lastAt < EVENT_RATE ) {
			$sendAt += EVENT_RATE - ($sendAt - $lastAt);
		}

		Slim::Utils::Timers::setTimer(
			undef,
			$sendAt,
			\&sendEvent,
			$var,
		);
	}
}

sub sendEvent {
	my ( $uuid, $var ) = @_;

	Slim::Plugin::UPnP::Events->notify(
		service => __PACKAGE__,
		id      => $uuid || 0, # 0 will notify everyone
		data    => {
			$var => $STATE->{$var},
		},
	);

	# Indicate when last event was sent
	$STATE->{_last_evented} = Time::HiRes::time();
}

sub unsubscribe {
	if ( $STATE->{_subscribers} > 0 ) {
		$STATE->{_subscribers}--;
	}
}

### Action methods

sub GetSearchCapabilities {
	return SOAP::Data->name(
		SearchCaps => 'dc:title,dc:creator,upnp:artist,upnp:album,upnp:genre,upnp:class,@id,@refID',
	);
}

sub GetSortCapabilities {
	return SOAP::Data->name(
		SortCaps => 'dc:title,dc:creator,dc:date,upnp:artist,upnp:album,upnp:genre,upnp:originalTrackNumber',
	);
}

sub GetSystemUpdateID {
	return SOAP::Data->name( Id => $STATE->{SystemUpdateID} );
}

sub Browse {
	my ( $class, undef, $args, $headers, $request_addr ) = @_;

	my $id     = $args->{ObjectID};
	my $flag   = $args->{BrowseFlag};
	my $filter = $args->{Filter};
	my $start  = $args->{StartingIndex};
	my $limit  = $args->{RequestedCount};
	my $sort   = $args->{SortCriteria};

	my $cmd;
	my $xml;
	my $results;
	my $count = 0;
	my $total = 0;

	# Missing arguments result in a 402 Invalid Args error
	if ( !defined $id || !defined $flag || !defined $filter || !defined $start || !defined $limit || !defined $sort ) {
		return [ 402 ];
	}

	if ( $flag !~ /^(?:BrowseMetadata|BrowseDirectChildren)$/ ) {
		return [ 720 => 'Cannot process the request (invalid BrowseFlag)' ];
	}

	# spec says "RequestedCount=0 indicates request all entries.", but we don't want to kill the server, only return 200 items
	if ( $limit == 0 ) {
		$limit = 200;
	}

	# Verify sort
	my ($valid, undef) = _decodeSortCriteria($sort, '');
	if ( $sort && !$valid ) {
		return [ 709 => 'Unsupported or invalid sort criteria' ];
	}

	# Strings are needed for the top-level and years menus
	my $strings;
	my $string = sub {
		# Localize menu options from Accept-Language header
		if ( !$strings ) {
			$strings = Slim::Utils::Strings::loadAdditional( $prefs->get('language') );

			if ( my $lang = $headers->{'accept-language'} ) {
				my $all_langs = Slim::Utils::Strings::languageOptions();

				foreach my $language (extract_language_tags($lang)) {
					$language = uc($language);
					$language =~ s/-/_/;  # we're using zh_cn, the header says zh-cn

					if (defined $all_langs->{$language}) {
						$strings = Slim::Utils::Strings::loadAdditional($language);
						last;
					}
				}
			}
		}

		my $token = uc(shift);
		my $string = $strings->{$token};
		if ( @_ ) { return sprintf( $string, @_ ); }
		return $string;
	};

	# ContentDirectory menu/IDs are as follows:                CLI query:

	# Home Menu
	# ---------
	# Music
	# Video
	# Pictures

	# Music (/music)
	# -----
	# Artists (/a)                                             artists
	#   Artist 1 (/a/<id>/l)                                   albums artist_id:<id> sort:album
	#     Album 1 (/a/<id>/l/<id>/t)                           titles album_id:<id> sort:tracknum
	#       Track 1 (/a/<id>/l/<id>/t/<id>)                    titles track_id:<id>
	# Albums (/l)                                              albums sort:album
	#   Album 1 (/l/<id>/t)                                    titles album_id:<id> sort:tracknum
	#     Track 1 (/l/<id>/t/<id>)                             titles track_id:<id>
	# Genres (/g)                                              genres sort:album
	#   Genre 1 (/g/<id>/a)                                    artists genre_id:<id>
	#     Artist 1 (/g/<id>/a/<id>/l)                          albums genre_id:<id> artist_id:<id> sort:album
	#       Album 1 (/g/<id>/a/<id>/l/<id>/t)                  titles album_id:<id> sort:tracknum
	#         Track 1 (/g/<id>/a/<id>/l/<id>/t/<id>)           titles track_id:<id>
	# Year (/y)                                                years
	#   2010 (/y/2010/l)                                       albums year:<id> sort:album
	#     Album 1 (/y/2010/l/<id>/t)                           titles album_id:<id> sort:tracknum
	#       Track 1 (/y/2010/l/<id>/t/<id>)                    titles track_id:<id>
	# New Music (/n)                                           albums sort:new
	#   Album 1 (/n/<id>/t)                                    titles album_id:<id> sort:tracknum
	#     Track 1 (/n/<id>/t/<id>)                             titles track_id:<id>
	# Music Folder (/m)                                        musicfolder
	#   Folder (/m/<id>/m)                                     musicfolder folder_id:<id>
	# Playlists (/p)                                           playlists
	#   Playlist 1 (/p/<id>/t)                                 playlists tracks playlist_id:<id>
	#     Track 1 (/p/<id>/t/<id>)                             titles track_id:<id>

	# Extras for standalone track items, AVTransport uses these
	# Tracks (/t) (cannot be browsed)
	#   Track 1 (/t/<id>)

	if ( $id eq '0' || ($flag eq 'BrowseMetadata' && $id =~ m{^/(?:music|video|images)$}) ) { # top-level menu
		my $type = 'object.container';
		my $menu = [
			{ id => '/music', parentID => 0, type => $type, title => $string->('MUSIC') },
		];

		if ( $flag eq 'BrowseMetadata' ) {
			if ( $id eq '0' ) {
				$menu = [ {
					id         => 0,
					parentID   => -1,
					type       => 'object.container',
					title      => 'Logitech Media Server [' . xmlEscape(Slim::Utils::Misc::getLibraryName()) . ']',
					searchable => 1,
				} ];
			}
			else {
				# pull out the desired menu item
				my ($item) = grep { $_->{id} eq $id } @{$menu};
				$menu = [ $item ];
			}
		}

		($xml, $count, $total) = _arrayToDIDLLite( {
			array  => $menu,
			sort   => $sort,
			start  => $start,
			limit  => $limit,
			filter => $filter,
		} );
	}
	elsif ( $id eq '/music' || ($flag eq 'BrowseMetadata' && length($id) == 2) ) { # Music menu, or metadata for a music menu item
		my $type = 'object.container';
		my $menu = [
			{ id => '/a', parentID => '/music', type => $type, title => $string->('ARTISTS') },
			{ id => '/l', parentID => '/music', type => $type, title => $string->('ALBUMS') },
			{ id => '/g', parentID => '/music', type => $type, title => $string->('GENRES') },
			{ id => '/y', parentID => '/music', type => $type, title => $string->('BROWSE_BY_YEAR') },
			{ id => '/n', parentID => '/music', type => $type, title => $string->('BROWSE_NEW_MUSIC') },
			{ id => '/m', parentID => '/music', type => $type, title => $string->('BROWSE_MUSIC_FOLDER') },
			#{ id => '/p', parentID => '/music', type => $type, title => $string->('PLAYLISTS') },
		];

		if ( $flag eq 'BrowseMetadata' ) {
			# pull out the desired menu item
			my ($item) = grep { $_->{id} eq $id } @{$menu};
			$menu = [ $item ];
		}

		($xml, $count, $total) = _arrayToDIDLLite( {
			array  => $menu,
			sort   => $sort,
			start  => $start,
			limit  => $limit,
			filter => $filter,
		} );
	}
	else {
		# Determine CLI command to use
		# The command is different depending on the flag:
		# BrowseMetadata will request only 1 specific item
		# BrowseDirectChildren will request the desired number of children
		if ( $id =~ m{^/a} ) {
			if ( $id =~ m{/l/(\d+)/t$} ) {
				my $album_id = $1;

				if ( $sort && $sort !~ /^\+upnp:originalTrackNumber$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit album_id:$album_id sort:tracknum tags:AGldyorfTIctnDUFH"
					: "albums 0 1 album_id:$album_id tags:alyj";
			}
			elsif ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDUFH"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDUFH";
			}
			elsif ( $id =~ m{/a/(\d+)/l$} ) {
				my $artist_id = $1;

				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = $flag eq 'BrowseDirectChildren'
					? "albums $start $limit artist_id:$artist_id sort:album tags:alyj"
					: "artists 0 1 artist_id:$artist_id";
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = "artists $start $limit";
			}
		}
		elsif ( $id =~ m{^/l} ) {
			if ( $id =~ m{/l/(\d+)/t$} ) {
				my $album_id = $1;

				if ( $sort && $sort !~ /^\+upnp:originalTrackNumber$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit album_id:$album_id sort:tracknum tags:AGldyorfTIctnDUFH"
					: "albums 0 1 album_id:$album_id tags:alyj";
			}
			elsif ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDUFH"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDUFH";
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = "albums $start $limit sort:album tags:alyj";
			}
		}
		elsif ( $id =~ m{^/g} ) {
			if ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDUFH"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDUFH";
			}
			elsif ( $id =~ m{^/g/\d+/a/\d+/l/(\d+)/t$} ) {
				my $album_id = $1;

				if ( $sort && $sort !~ /^\+upnp:originalTrackNumber$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit album_id:$album_id sort:tracknum tags:AGldyorfTIctnDUFH"
					: "albums 0 1 album_id:$album_id tags:alyj";
			}
			elsif ( $id =~ m{^/g/(\d+)/a/(\d+)/l$} ) {
				my ($genre_id, $artist_id) = ($1, $2);

				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = $flag eq 'BrowseDirectChildren'
					? "albums $start $limit genre_id:$genre_id artist_id:$artist_id sort:album tags:alyj"
					: "artists 0 1 genre_id:$genre_id artist_id:$artist_id";
			}
			elsif ( $id =~ m{^/g/(\d+)/a$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "artists $start $limit genre_id:$1"
					: "genres 0 1 genre_id:$1"
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = "genres $start $limit";
			}
		}
		elsif ( $id =~ m{^/y} ) {
			if ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDUFH"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDUFH";
			}
			elsif ( $id =~ m{/l/(\d+)/t$} ) {
				my $album_id = $1;

				if ( $sort && $sort !~ /^\+upnp:originalTrackNumber$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit album_id:$album_id sort:tracknum tags:AGldyorfTIctnDUFH"
					: "albums 0 1 album_id:$album_id tags:alyj";
			}
			elsif ( $id =~ m{/y/(\d+)/l$} ) {
				my $year = $1;

				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = $flag eq 'BrowseDirectChildren'
					? "albums $start $limit year:$year sort:album tags:alyj"
					: "years 0 1 year:$year";
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = "years $start $limit";
			}
		}
		elsif ( $id =~ m{^/n} ) {
			if ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDUFH"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDUFH";
			}
			elsif ( $id =~ m{/n/(\d+)/t$} ) {
				my $album_id = $1;

				if ( $sort && $sort !~ /^\+upnp:originalTrackNumber$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit album_id:$album_id sort:tracknum tags:AGldyorfTIctnDUFH"
					: "albums 0 1 album_id:$album_id tags:alyj";
			}
			else {
				# Limit results to pref or 100
				my $preflimit = $prefs->get('browseagelimit') || 100;
				if ( $limit > $preflimit ) {
					$limit = $preflimit;
				}

				$cmd = "albums $start $limit sort:new tags:alyj";
			}
		}
		elsif ( $id =~ m{^/m} ) {
			if ( $id =~ m{/m/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDUFH"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDUFH";
			}
			elsif ( $id =~ m{/m/(\d+)/m$} ) {
				my $fid = $1;

				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = $flag eq 'BrowseDirectChildren'
					? "musicfolder $start $limit folder_id:$fid"
					: "musicfolder 0 1 folder_id:$fid return_top:1";
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = "musicfolder $start $limit";
			}
		}
		elsif ( $id =~ m{^/p} ) {
			if ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDUFH"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDUFH";
			}
			elsif ( $id =~ m{^/p/(\d+)/t$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "playlists tracks $start $limit playlist_id:$1 tags:AGldyorfTIctnDUFH"
					: "playlists 0 1 playlist_id:$1";
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}

				$cmd = "playlists $start $limit";
			}
		}
		elsif ( $id =~ m{^/t/(\d+)$} ) {
			$cmd = "titles 0 1 track_id:$1 tags:AGldyorfTIctnDUFH";
		}

		### Video
		elsif ( $id =~ m{^/va} ) { # All Videos
			if ( $id =~ m{/([0-9a-f]{8})$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "video_titles $start $limit video_id:$1 tags:dorfcwhtnDUlF"
					: "video_titles 0 1 video_id:$1 tags:dorfcwhtnDUlF";
			}
			else {
				$cmd = "video_titles $start $limit tags:dorfcwhtnDUlF";
			}
		}

		elsif ( $id =~ m{^/vf} ) {      # folders
			my ($folderId) = $id =~ m{^/vf/(.+)};

			if ( $folderId ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "mediafolder $start $limit type:video folder_id:$folderId tags:dorfcwhtnDUlJF"
					: "mediafolder 0 1 type:video folder_id:$folderId return_top:1 tags:dorfcwhtnDUlJF";
			}

			elsif ( $id eq '/vf' ) {
				$cmd = "mediafolder $start $limit type:video tags:dorfcwhtnDUlJF";
			}
		}

		### Images
		elsif ( $id =~ m{^/ia} ) { # All Images
			if ( $id =~ m{/([0-9a-f]{8})$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles $start $limit image_id:$1 tags:ofwhtnDUlOF"
					: "image_titles 0 1 image_id:$1 tags:ofwhtnDUlOF";
			}
			else {
				$cmd = "image_titles $start $limit tags:ofwhtnDUlOF";
			}
		}

		elsif ( $id =~ m{^/if} ) {      # folders
			my ($folderId) = $id =~ m{^/if/(.+)};

			if ( $folderId ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "mediafolder $start $limit type:image folder_id:$folderId tags:ofwhtnDUlOJF"
					: "mediafolder 0 1 type:image folder_id:$folderId return_top:1 tags:ofwhtnDUlOJF";
			}

			elsif ( $id eq '/if' ) {
				$cmd = "mediafolder $start $limit type:image tags:ofwhtnDUlOJF";
			}
		}

		elsif ( $id =~ m{^/il} ) {      # albums
			my ($albumId) = $id =~ m{^/il/(.+)};

			if ( $albumId ) {
				$albumId = main::ISWINDOWS ? uri_escape($albumId) : uri_escape_utf8($albumId);

				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles $start $limit albums:1 search:$albumId tags:ofwhtnDUlOF"
					: "image_titles 0 1 albums:1";
			}

			elsif ( $id eq '/il' ) {
				$cmd = "image_titles $start $limit albums:1";
			}
		}

		elsif ( $id =~ m{^/(?:it|id)} ) { # timeline hierarchy

			my ($tlId) = $id =~ m{^/(?:it|id)/(.+)};
			my ($year, $month, $day, $pic) = $tlId ? split('/', $tlId) : ();

			if ( $pic ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles 0 1 image_id:$pic tags:ofwhtnDUlOF"
					: "image_titles 0 1 timeline:day search:$year-$month-$day tags:ofwhtnDUlOF";
			}

			# if we've got a full date, show pictures
			elsif ( $year && $month && $day ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles $start $limit timeline:day search:$year-$month-$day tags:ofwhtnDUlOF"
					: "image_titles 0 1 timeline:days search:$year-$month"; # XXX should this have tags?
			}

			# show days for a given month/year
			elsif ( $year && $month ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles $start $limit timeline:days search:$year-$month"
					: "image_titles 0 1 timeline:months search:$year";
			}

			# show months for a given year
			elsif ( $year ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles $start $limit timeline:months search:$year"
					: "image_titles 0 1 timeline:years";
			}

			elsif ( $id eq '/it' ) {
				$cmd = "image_titles $start $limit timeline:years";
			}

			elsif ( $id eq '/id' ) {
				$cmd = "image_titles $start $limit timeline:dates";
			}
		}

		if ( !$cmd ) {
			return [ 701 => 'No such object' ];
		}

		main::INFOLOG && $log->is_info && $log->info("Executing command: $cmd");

		# Run the request
		my $request = Slim::Control::Request->new( undef, [ split( / /, $cmd ) ] );
		if ( $request->isStatusDispatchable ) {
			$request->execute();
			if ( $request->isStatusError ) {
				return [ 720 => 'Cannot process the request (' . $request->getStatusText . ')' ];
			}
			$results = $request->getResults;
		}
		else {
			return [ 720 => 'Cannot process the request (' . $request->getStatusText . ')' ];
		}

		my ($parentID) = $id =~ m{^(.*)/};

		($xml, $count, $total) = _queryToDIDLLite( {
			cmd      => $cmd,
			results  => $results,
			flag     => $flag,
			id       => $id,
			parentID => $parentID,
			filter   => $filter,
			string   => $string,

			request_addr => $request_addr,
		} );
	}

	utf8::encode($xml); # Just to be safe, not sure this is needed

	return (
		SOAP::Data->name( Result         => $xml ),
		SOAP::Data->name( NumberReturned => $count ),
		SOAP::Data->name( TotalMatches   => $total ),
		SOAP::Data->name( UpdateID       => $STATE->{SystemUpdateID} ),
	);
}

sub Search {
	my ( $class, undef, $args, $headers, $request_addr ) = @_;

	my $id     = $args->{ContainerID};
	my $search = $args->{SearchCriteria} || '*';
	my $filter = $args->{Filter};
	my $start  = $args->{StartingIndex};
	my $limit  = $args->{RequestedCount};
	my $sort   = $args->{SortCriteria};

	my $xml;
	my $results;
	my $count = 0;
	my $total = 0;

	# Missing arguments result in a 402 Invalid Args error
	if ( !defined $id || !defined $search || !defined $filter || !defined $start || !defined $limit || !defined $sort ) {
		return [ 402 ];
	}

	if ( $id ne '0' ) {
		return [ 710 => 'No such container' ];
	}

	# spec says "RequestedCount=0 indicates request all entries.", but we don't want to kill the server, only return 200 items
	if ( $limit == 0 ) {
		$limit = 200;
	}

	my ($cmd, $table, $searchsql, $tags) = _decodeSearchCriteria($search);

	my ($sortsql, $stags) = _decodeSortCriteria($sort, $table);
	$tags .= $stags;

	if ($cmd eq 'image_titles') {
		$tags .= 'ofwhtnDUlOF';
	}
	elsif ($cmd eq 'video_titles') {
		$tags .= 'dorfcwhtnDUlF';
	}
	else {
		# Avoid 'A' and 'G' tags because they will run extra queries
		$tags .= 'agldyorfTIctnDUFH';
	}

	if ( $sort && !$sortsql ) {
		return [ 709 => 'Unsupported or invalid sort criteria' ];
	}

	if ( !$cmd ) {
		return [ 708 => 'Unsupported or invalid search criteria' ];
	}

	# Construct query
	$cmd = [ $cmd, $start, $limit, "tags:$tags", "search:sql=($searchsql)", "sort:sql=$sortsql" ];

	main::INFOLOG && $log->is_info && $log->info("Executing command: " . Data::Dump::dump($cmd));

	# Run the request
	my $results;
	my $request = Slim::Control::Request->new( undef, $cmd );
	if ( $request->isStatusDispatchable ) {
		$request->execute();
		if ( $request->isStatusError ) {
			return [ 708 => 'Unsupported or invalid search criteria' ];
		}
		$results = $request->getResults;
	}
	else {
		return [ 708 => 'Unsupported or invalid search criteria' ];
	}

	($xml, $count, $total) = _queryToDIDLLite( {
		cmd      => $cmd,
		results  => $results,
		flag     => '',
		id       => $table eq 'tracks' ? '/t' : $table eq 'videos' ? '/v' : '/i',
		filter   => $filter,

		request_addr => $request_addr,
	} );

	return (
		SOAP::Data->name( Result         => $xml ),
		SOAP::Data->name( NumberReturned => $count ),
		SOAP::Data->name( TotalMatches   => $total ),
		SOAP::Data->name( UpdateID       => $STATE->{SystemUpdateID} ),
	);
}

sub _queryToDIDLLite {
	my $args = shift;

	my $cmd      = $args->{cmd};
	my $results  = $args->{results};
	my $flag     = $args->{flag};
	my $id       = $args->{id};
	my $parentID = $args->{parentID};
	my $filter   = $args->{filter};

	my $request_addr = $args->{request_addr};

	my $count    = 0;
	my $total    = $results->{count};

	my $filterall = ($filter =~ /\*/);

	if ( ref $cmd eq 'ARRAY' ) {
		$cmd = join( ' ', @{$cmd} );
	}

	my $xml = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:pv="http://www.pv.com/pvns/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">';

	if ( $cmd =~ /^artists/ ) {
		for my $artist ( @{ $results->{artists_loop} || [] } ) {
			$count++;
			my $aid = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $artist->{id} . '/l';
			my $parent = $id;

			if ( $flag eq 'BrowseMetadata' ) { # point parent to the artist's parent
				($parent) = $id =~ m{^(.*/a)};
			}

			$xml .= qq{<container id="${aid}" parentID="${parent}" restricted="1">}
				. '<upnp:class>object.container.person.musicArtist</upnp:class>'
				. '<dc:title>' . xmlEscape($artist->{artist}) . '</dc:title>'
				. '</container>';
		}
	}
	elsif ( $cmd =~ /^albums/ ) {
		# Fixup total for sort:new listing
		if ( $cmd =~ /sort:new/ && (my $max = $prefs->get('browseagelimit')) < $total) {
			$total = $max if $max < $total;
		}

		for my $album ( @{ $results->{albums_loop} || [] } ) {
			$count++;
			my $aid    = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $album->{id} . '/t';
			my $parent = $id;

			if ( $flag eq 'BrowseMetadata' ) { # point parent to the album's parent
				($parent) = $id =~ m{^(.*/(?:l|n))}; # both /l and /n top-level items use this
			}

			my $coverid = $album->{artwork_track_id};

			# XXX musicAlbum should have upnp:genre and @childCount, although not required (DLNA 7.3.25.3)
			$xml .= qq{<container id="${aid}" parentID="${parent}" restricted="1">}
				. '<upnp:class>object.container.album.musicAlbum</upnp:class>'
				. '<dc:title>' . xmlEscape($album->{album}) . '</dc:title>';

			if ( $filterall || $filter =~ /dc:creator/ ) {
				$xml .= '<dc:creator>' . xmlEscape($album->{artist}) . '</dc:creator>';
			}
			if ( $filterall || $filter =~ /upnp:artist/ ) {
				$xml .= '<upnp:artist>' . xmlEscape($album->{artist}) . '</upnp:artist>';
			}
			if ( $filterall || $filter =~ /dc:date/ ) {
				$xml .= '<dc:date>' . xmlEscape( sprintf("%04d", $album->{year}) ) . '-01-01</dc:date>'; # DLNA requires MM-DD
			}
			if ( $coverid && ($filterall || $filter =~ /upnp:albumArtURI/) ) {
				# DLNA 7.3.61.1, provide multiple albumArtURI items, at least one of which is JPEG_TN (160x160)
				$xml .= '<upnp:albumArtURI dlna:profileID="JPEG_TN" xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">'
					. absURL("/music/$coverid/cover_160x160_m.jpg", $request_addr) . '</upnp:albumArtURI>';
				$xml .= '<upnp:albumArtURI>' . absURL("/music/$coverid/cover", $request_addr) . '</upnp:albumArtURI>';
			}

			$xml .= '</container>';
		}
	}
	elsif ( $cmd =~ /^genres/ ) {
		for my $genre ( @{ $results->{genres_loop} || [] } ) {
			$count++;
			my $gid = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $genre->{id} . '/a';
			my $parent = $id;

			if ( $flag eq 'BrowseMetadata' ) { # point parent to the genre's parent
				($parent) = $id =~ m{^(.*/g)};
			}

			$xml .= qq{<container id="${gid}" parentID="${parent}" restricted="1">}
				. '<upnp:class>object.container.genre.musicGenre</upnp:class>'
				. '<dc:title>' . xmlEscape($genre->{genre}) . '</dc:title>'
				. '</container>';
		}
	}
	elsif ( $cmd =~ /^years/ ) {
		for my $year ( @{ $results->{years_loop} || [] } ) {
			$count++;
			my $year = $year->{year};

			my $yid = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $year . '/l';
			my $parent = $id;

			if ( $flag eq 'BrowseMetadata' ) { # point parent to the year's parent
				($parent) = $id =~ m{^(.*/y)};
			}

			if ( $year eq '0' ) {
				$year = $args->{string}->('UNK');
			}

			$xml .= qq{<container id="${yid}" parentID="${parent}" restricted="1">}
				. '<upnp:class>object.container</upnp:class>'
				. '<dc:title>' . $year . '</dc:title>'
				. '</container>';
		}
	}
	elsif ( $cmd =~ /^musicfolder/ ) {
		my @trackIds;
		for my $folder ( @{ $results->{folder_loop} || [] } ) {
			my $fid = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $folder->{id} . '/m';
			my $parent = $id;

			if ( $flag eq 'BrowseMetadata' ) { # point parent to the folder's parent
				($parent) = $id =~ m{^(.*/m)/\d+/m};
			}

			my $type = $folder->{type};

			if ( $type eq 'folder' ) {
				$count++;
				$xml .= qq{<container id="${fid}" parentID="${parent}" restricted="1">}
					. '<upnp:class>object.container.storageFolder</upnp:class>'
					. '<dc:title>' . xmlEscape($folder->{filename}) . '</dc:title>'
					. '</container>';
			}
			elsif ( $type eq 'playlist' ) {
				warn "*** Playlist type: " . Data::Dump::dump($folder) . "\n";
				$total--;
			}
			elsif ( $type eq 'track' ) {
				# Save the track ID for later lookup
				push @trackIds, $folder->{id};
				$total--;
			}
		}

		if ( scalar @trackIds ) {
			my $tracks = Slim::Control::Queries::_getTagDataForTracks( 'AGldyorfTIctnDUFH', {
				trackIds => \@trackIds,
			} );

			for my $trackId ( @trackIds ) {
				$count++;
				$total++;
				my $track = $tracks->{$trackId};
				my $tid = $id . '/' . $trackId;

				# Rewrite id to end with /t/<id> so it doesn't look like another folder
				$tid =~ s{m/(\d+)$}{t/$1};

				$xml .= qq{<item id="${tid}" parentID="${id}" restricted="1">}
				 	. trackDetails($track, $filter, $request_addr)
					. '</item>';
			}
		}
	}
	elsif ( $cmd =~ /^titles/ ) {
		for my $track ( @{ $results->{titles_loop} || [] } ) {
			$count++;
			my $tid    = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $track->{id};
			my $parent = $id;

			if ( $flag eq 'BrowseMetadata' ) { # point parent to the track's parent
				($parent) = $id =~ m{^(.*/t)};

				# Special case for /m path items, their parent ends in /m
				if ( $parent =~ m{^/m} ) {
					$parent =~ s/t$/m/;
				}
			}

			$xml .= qq{<item id="${tid}" parentID="${parent}" restricted="1">}
			 	. trackDetails($track, $filter, $request_addr)
			 	. '</item>';
		}
	}
	elsif ( $cmd =~ /^playlists tracks/ ) {
		for my $track ( @{ $results->{playlisttracks_loop} || [] } ) {
			$count++;
			my $tid    = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $track->{id};
			my $parent = $id;

			if ( $flag eq 'BrowseMetadata' ) { # point parent to the track's parent
				($parent) = $id =~ m{^(.*/t)};
			}

			$xml .= qq{<item id="${tid}" parentID="${parent}" restricted="1">}
			 	. trackDetails($track, $filter, $request_addr)
			 	. '</item>';
		}
	}
	elsif ( $cmd =~ /^playlists/ ) {
		for my $playlist ( @{ $results->{playlists_loop} || [] } ) {
			$count++;
			my $pid = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $playlist->{id} . '/t';

			$xml .= qq{<container id="${pid}" parentID="/p" restricted="1">}
				. '<upnp:class>object.container.playlistContainer</upnp:class>'
				. '<dc:title>' . xmlEscape($playlist->{playlist}) . '</dc:title>'
				. '</container>';
		}
	}

	$xml .= '</DIDL-Lite>';

	return ($xml, $count, $total);
}

sub _arrayToDIDLLite {
	my $args = shift;

	my $array  = $args->{array};
	my $sort   = $args->{sort};
	my $start  = $args->{start};
	my $limit  = $args->{limit};
	my $filter = $args->{filter};

	my $count = 0;
	my $total = 0;

	my $filterall = ($filter =~ /\*/);

	my $xml = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">';

	my @sorted;

	# Only title is available for sorting here
	if ( $sort && $sort =~ /([+-])dc:title/ ) {
		if ( $1 eq '+' ) {
			@sorted = sort { $a->{title} cmp $b->{title} } @{$array};
		}
		else {
			@sorted = sort { $b->{title} cmp $a->{title} } @{$array};
		}
	}
	else {
		@sorted = @{$array};
	}

	for my $item ( @sorted ) {
		$total++;

		if ($start) {
			next if $start >= $total;
		}

		if ($limit) {
			next if $limit <= $count;
		}

		$count++;

		my $id         = $item->{id};
		my $parentID   = $item->{parentID};
		my $type       = $item->{type};
		my $title      = $item->{title};
		my $searchable = $item->{searchable} || 0;

		if ( $type =~ /container/ ) {
			$xml .= qq{<container id="${id}" parentID="${parentID}" restricted="1"};
			if ( $filterall || $filter =~ /\@searchable/ ) {
				$xml .= qq{ searchable="${searchable}"};
			}
			$xml .= qq{>}
				. "<upnp:class>${type}</upnp:class>"
				. '<dc:title>' . xmlEscape($title) . '</dc:title>';

			# DLNA 7.3.67.4, add searchClass info
			if ($id == 0 && ($filterall || $filter =~ /upnp:searchClass/) ) {
				$xml .= qq{<upnp:searchClass includeDerived="0">object.item.audioItem</upnp:searchClass>}
					  . qq{<upnp:searchClass includeDerived="0">object.item.imageItem</upnp:searchClass>}
					  . qq{<upnp:searchClass includeDerived="0">object.item.videoItem</upnp:searchClass>};
			}

			$xml .= '</container>';
		}
	}

	$xml .= '</DIDL-Lite>';

	return ($xml, $count, $total);
}

sub _decodeSearchCriteria {
	my $search = shift;

	my $cmd = 'titles';
	my $table = 'tracks';
	my $idcol = 'id'; # XXX switch to hash for audio tracks
	my $tags = '';

	if ( $search eq '*' ) {
		# XXX need to search all types together
		return ( $cmd, $table, '1=1', $tags );
	}

	# Fix quotes and apos
	$search =~ s/&quot;/"/g;
	$search =~ s/&apos;/'/g;

	# Handle derivedfrom
	if ( $search =~ s/upnp:class derivedfrom "([^"]+)"/1=1/ig ) {
		my $sclass = $1;
		if ( $sclass =~ /object\.item\.videoItem/i ) {
			$cmd = 'video_titles';
			$table = 'videos';
			$idcol = 'hash';
		}
		elsif ( $sclass =~ /object\.item\.imageItem/i ) {
			$cmd = 'image_titles';
			$table = 'images';
			$idcol = 'hash';
		}
	}

	# Tweak all title/namesearch columns to use the normalized version
	if ( $search =~ /(dc:title|dc:creator|upnp:artist|upnp:album|upnp:genre)\s+contains\s+"([^"]+)"/ ) {
		my $field = $1;
		my $query = Slim::Utils::Text::ignoreCaseArticles($2, 1);
		$search =~ s/${field}\s+contains\s+"[^"]+"/${field} contains "$query"/;
	}

	# Replace 'contains "x"' and 'doesNotContain "x" with 'LIKE "%X%"' and 'NOT LIKE "%X%"'
	$search =~ s/contains\s+"([^"]+)"/LIKE "%%\U$1%%"/ig;
	$search =~ s/doesNotContain\s+"([^"]+)"/NOT LIKE "%%\U$1%%"/ig;

	$search =~ s/\@id/${table}.${idcol}/g;
	$search =~ s/\@refID exists (?:true|false)/1=1/ig;
	$search =~ s/upnp:class exists (?:true|false)/1=1/ig;

	# Replace 'exists true' and 'exists false'
	$search =~ s/exists\s+true/IS NOT NULL/ig;
	$search =~ s/exists\s+false/IS NULL/ig;

	# Replace properties, checks for LIKE are to avoid changing 'dc:title = "literal"'
	$search =~ s/dc:title LIKE/${table}.titlesearch LIKE/g;
	$search =~ s/dc:title/${table}.title/g; # will handle 'dc:title =', 'dc:title exists', etc

	if ( $search =~ s/pv:lastUpdated/${table}.updated_time/g ) {
		$tags .= 'U';
	}

	if ( $cmd eq 'titles' ) {
		# These search params are only valid for audio
		if ( $search =~ s/dc:creator LIKE/contributors.namesearch LIKE/g ) {
			$tags .= 'a';
		}
		if ( $search =~ s/dc:creator/contributors.name/g ) {
			$tags .= 'a';
		}

		if ( $search =~ s/upnp:artist LIKE/contributors.namesearch LIKE/g ) {
			$tags .= 'a';
		}
		if ( $search =~ s/upnp:artist/contributors.name/g ) {
			$tags .= 'a';
		}

		if ( $search =~ s/upnp:album LIKE/albums.titlesearch LIKE/g ) {
			$tags .= 'l';
		}
		if ( $search =~ s/upnp:album/albums.title/g ) {
			$tags .= 'l';
		}

		if ( $search =~ s/upnp:genre LIKE/genres.namesearch LIKE/g ) {
			$tags .= 'g';
		}
		if ( $search =~ s/upnp:genre/genres.name/g ) {
			$tags .= 'g';
		}
	}

	return ( $cmd, $table, $search, $tags );
}

sub _decodeSortCriteria {
	my $sort = shift;
	my $table = shift;

	# Note: collate intentionally not used here, doesn't seem to work with multiple values

	my @sql;
	my $tags = '';

	# Supported SortCaps:
	#
	# dc:title
	# dc:creator
	# dc:date
	# upnp:artist
	# upnp:album
	# upnp:genre
	# upnp:originalTrackNumber
	# pv:modificationTime
	# pv:addedTime
	# pv:lastUpdated

	for ( split /,/, $sort ) {
		if ( /^([+-])(.+)/ ) {
			my $dir = $1 eq '+' ? 'ASC' : 'DESC';

			if ( $2 eq 'dc:title' ) {
				push @sql, "${table}.titlesort $dir";
			}
			elsif ( $2 eq 'dc:creator' || $2 eq 'upnp:artist' ) {
				push @sql, "contributors.namesort $dir";
				$tags .= 'a';
			}
			elsif ( $2 eq 'upnp:album' ) {
				push @sql, "albums.titlesort $dir";
				$tags .= 'l';
			}
			elsif ( $2 eq 'upnp:genre' ) {
				push @sql, "genres.namesort $dir";
				$tags .= 'g';
			}
			elsif ( $2 eq 'upnp:originalTrackNumber' ) {
				push @sql, "tracks.tracknum $dir";
			}
			elsif ( $2 eq 'pv:modificationTime' || $2 eq 'dc:date' ) {
				if ( $table eq 'tracks' ) {
					push @sql, "${table}.timestamp $dir";
				}
				else {
					push @sql, "${table}.mtime $dir";
				}
			}
			elsif ( $2 eq 'pv:addedTime' ) {
				push @sql, "${table}.added_time $dir";
			}
			elsif ( $2 eq 'pv:lastUpdated' ) {
				push @sql, "${table}.updated_time $dir";
			}
		}
	}

	return ( join(', ', @sql), $tags );
}

1;
