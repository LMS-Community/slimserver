package Slim::Music::DataSource;

# $Id: DataSource.pm,v 1.1 2004/08/13 07:42:30 vidur Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Misc;


# Retrieve a song entry:
# @param url - The URL of the song to retrieve
# @param fleshTags - Should we try to flesh out all metadata (possibly by
# reading tags from the original file) if we haven't already?
# @returns Song object or undef if not found
sub song {
	warn("Must be overridden by derived class");
}

# Retrieve a song attribute:
# @param url - The URL of the song
# @param attribute - The name of the attribute to retrieve
# @returns value of the attribute
sub songAttribute {
	my $self = shift;
	my $url = shift;
	my $attribute = shift;

	my $song = $self->song($url, 1);
	if ($song) {
		return $song->get($attribute);
	}

	return undef;
}

# In the future, these should be split the getFoo methods into two
# versions:
# - a search version that takes search patterns
# - a get version that takes unique identifiers

# Get all genres matching the search criteria
# @param genre_patterns - Ref to array of patterns to match in search
# @returns Array of genre objects
sub getGenres {
	warn("Must be overridden by derived class");
}

# Get all artists whose songs match the search criteria
# @param genre_patterns - Ref to array of patterns to match in search
# @param artist_patterns - Ref to array of patterns to match in search
# @param albums_patterns - Ref to array of patterns to match in search
# @returns Array of artist objects
sub getArtists {
	warn("Must be overridden by derived class");
}

# Get all artists containing songs that match the search criteria
# @param genre_patterns - Ref to array of patterns to match in search
# @param artist_patterns - Ref to array of patterns to match in search
# @param albums_patterns - Ref to array of patterns to match in search
# @returns Array of album objects
sub getAlbums {
	warn("Must be overridden by derived class");
}

# Get all songs that match the search criteria
# @param genre_patterns - Ref to array of patterns to match in search
# @param artist_patterns - Ref to array of patterns to match in search
# @param albums_patterns - Ref to array of patterns to match in search
# @param songs_patterns - Ref to array of patterns to match in search
# @returns Array of song objects
sub getSongs {
	warn("Must be overridden by derived class");
}

# Get a list of album objects with artwork
sub getAlbumsWithArtwork {
	warn("Must be overridden by derived class");
}

# Get the cumulative playing time of all songs
sub totalTime {
	warn("Must be overridden by derived class");
}

# Get the number of genres matching the search criteria
# @param genre_patterns - Ref to array of patterns to match in search
# @returns number of genres
sub genreCount {
	my $self = shift;
	
	my @genres = $self->genres(@_);
	return scalar(@genres);
}

# Get the number of artists whose songs match the search criteria
# @param genre_patterns - Ref to array of patterns to match in search
# @param artist_patterns - Ref to array of patterns to match in search
# @param albums_patterns - Ref to array of patterns to match in search
# @returns number of artists
sub artistCount {
	my $self = shift;
	
	my @artists = $self->artists(@_);
	return scalar(@artists);
}

# Get the number of albums containing songs that match the search
# criteria
# @param genre_patterns - Ref to array of patterns to match in search
# @param artist_patterns - Ref to array of patterns to match in search
# @param albums_patterns - Ref to array of patterns to match in search
# @returns Number of albums
sub albumCount {
	my $self = shift;
	
	my @albums = $self->albums(@_);
	return scalar(@albums);
}

# Get the number of  songs that match the search criteria
# @param genre_patterns - Ref to array of patterns to match in search
# @param artist_patterns - Ref to array of patterns to match in search
# @param albums_patterns - Ref to array of patterns to match in search
# @param songs_patterns - Ref to array of patterns to match in search
# @returns Number of songs
sub songCount {
	my $self = shift;
	
	my @songs = $self->songs(@_);
	return scalar(@songs);
}

# Get the external (for now iTunes and Moodlogic) playlists
sub getExternalPlaylists {
	warn("Must be overridden by derived class");
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

