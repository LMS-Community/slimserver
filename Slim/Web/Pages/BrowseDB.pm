package Slim::Web::Pages::BrowseDB;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Scalar::Util qw(blessed);
use Storable;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

# This only remains in order to support potential 3rd party plugins still calling it. It's no longer being used in LMS core.

sub init {

	Slim::Web::Pages->addPageFunction( qr/^browsedb\.(?:htm|xml)/, \&browsedb );
}

my %mapLevel = (
	contributor => 'artists',
	album       => 'albums',
	track       => 'tracks',
	genre       => 'genres',
	year        => 'years',
	age         => 'albums',	# need sort:new too
	playlist    => 'playlists',
	playlistTrack => 'playlistTracks'
);

my %mapParams = (
	'contributor.id' => 'artist_id',
	'album.id'       => 'album_id',
	'track.id'       => 'track_id',
	'genre.id'       => 'genre_id',
	'year.id'        => 'year',
	'folder.id'      => 'folder_id',
	'playlist.id'    => 'playlist_id',
);

my %mapTitles = (
	contributor => ['Contributor', 'contributor.id'],
	album       => ['Album', 'album.id'],
	genre       => ['Genre', 'genre.id'],
	playlist    => ['Playlist', 'playlist.id'],
);

my %mapNames = (
	contributor => 'ARTIST',
	album       => 'ALBUM',
	track       => 'TRACK',
	genre       => 'GENRE',
	year        => 'YEAR',
	age         => 'ALBUM',	# need sort:new too
	playlist    => 'PLAYLIST',
);

sub browsedb {
	my ($client, $params) = @_;
	my $allArgs = \@_;

	my $hierarchy = $params->{'hierarchy'} || 'track';
	my $level     = $params->{'level'} || 0;
	my $orderBy   = $params->{'orderBy'} || '';
	my $player    = $params->{'player'};
	my $artwork   = $params->{'artwork'};

	my $log       = logger('database.info');
	
	my @levels = split (',', $hierarchy);

	# Make sure we're not out of bounds.
	my $maxLevel = scalar(@levels) - 1;

	if ($level > $maxLevel)	{
		$level = $maxLevel;
	}
	
	my %args = ('mode' => $mapLevel{$levels[$level]});
	if ($levels[$level] eq 'age') {
		$args{'sort'} = 'new';
	}
	
	foreach (keys %mapParams) {
		$args{$mapParams{$_}} = $params->{$_} if (exists $params->{$_});
	}
	
	# There is no CLI command to get artist/album/genre name from id
	my $title;
	if (my $titleMap = $mapTitles{$levels[0]}) {
		my $obj = Slim::Schema->find($titleMap->[0], $params->{$titleMap->[1]});
		$title = $obj->name if $obj;
	}
	$title = string($mapNames{$levels[0]}) . ' (' . $title . ')';
	
	my @verbs = ('browselibrary', 'items', 'feedMode:1', map {$_ . ':' . $args{$_}} keys %args);
	
	my $callback = sub {
		my ($client, $feed) = @_;
		Slim::Web::XMLBrowser->handleWebIndex( {
			client  => $client,
			feed    => $feed,
			timeout => 35,
			args    => $allArgs,
			title   => $title,
			path    => 'clixmlbrowser/clicmd=browselibrary+items&linktitle=' . Slim::Utils::Misc::escape($title)
						. join('&', '', map {$_ . '=' . $args{$_}} keys %args) . '/',
		} );
	};

	# execute CLI command
	main::INFOLOG && $log->is_info && $log->error('Use CLI: ', join(', ', @verbs));
	my $proxiedRequest = Slim::Control::Request::executeRequest( $client, \@verbs );
		
	# wrap async requests
	if ( $proxiedRequest->isStatusProcessing ) {			
		$proxiedRequest->callbackFunction( sub { $callback->($client, $_[0]->getResults); } );
	} else {
		$callback->($client, $proxiedRequest->getResults);
	}
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
