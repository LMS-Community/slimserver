package Slim::Schema::ResultSet::Playlist;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Base);

use Scalar::Util qw(blessed);
use Slim::Utils::Prefs;

sub title {
	my $self = shift;

	return 'SAVED_PLAYLISTS';
}

sub suppressAll { 1 }

sub browse {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	return $self->getPlaylists;
}

sub descendPlaylistTrack {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	# Get a clean resultset - otherwise we may be restricting by content
	# type, which doesn't make sense when explictly browsing a playlist.
	my $playlist = $self->result_source->resultset->find($cond->{'me.id'}) || return undef;

	return $playlist->tracks;
}

sub clearExternalPlaylists {
	my $self = shift;
	my $url  = shift;

	# We can specify a url prefix to only delete certain types of external
	# playlists - ie: only iTunes, or only MusicMagic.
	for my $track ($self->getPlaylists('external')) {

		# XXX - exception should go here. Comming soon.
		if (!blessed($track) || !$track->can('url')) {
			next;
		}

		$track->delete if (defined $url ? $track->url =~ /^$url/ : 1);
	}

	Slim::Schema->forceCommit;
}

sub clearInternalPlaylists {
	my $self = shift;

	for my $track ($self->getPlaylists('internal')) {

		# XXX - exception should go here. Comming soon.
		if (!blessed($track) || !$track->can('delete')) {
			next;
		}

		$track->delete;
	}

	Slim::Schema->forceCommit;
}

# Get the playlists
# param $type is 'all' for all playlists, 'internal' for internal playlists
# 'external' for external playlists. Default is 'all'.
# param $search is a search term on the playlist title.
sub getPlaylists {
	my $self   = shift;
	my $type   = shift || 'all';
	my $search = shift;

	my @playlists = ();

	if ($type eq 'all' || $type eq 'internal') {
		push @playlists, $Slim::Music::Info::suffixes{'playlist:'};
	}

	# Don't search for playlists if the plugin isn't enabled.
	if ($type eq 'all' || $type eq 'external') {

		for my $importer (qw(itunes musicmagic)) {
	
			my $prefs = preferences("plugin.$importer");
	
			if ($prefs->get($importer)) {
	
				push @playlists, $Slim::Music::Info::suffixes{sprintf('%splaylist:', $importer)};
			}
		}
	}

	return () unless (scalar @playlists);

	my $find = {
		'content_type' => { 'in' => \@playlists },
	};

	if (defined $search) {
		$find->{'titlesearch'} = {'like' => $search};
	}

	# Add search criteria for playlists
	my $rs = $self->search($find, { 'order_by' => 'titlesort' });

	return wantarray ? $rs->all : $rs;
}

sub getPlaylistForClient {
	my $self   = shift;
	my $client = shift;

	return $self->single({
		'url' => sprintf('clientplaylist://%s', $client->id),
	});
}

sub objectForUrl {
	my $self = shift;
	my $args = shift;

	$args->{'playlist'} = 1;

	return Slim::Schema->objectForUrl($args);
}

sub updateOrCreate {
	my $self = shift;
	my $args = shift;

	$args->{'playlist'} = 1;

	return Slim::Schema->updateOrCreate($args);
}

1;
