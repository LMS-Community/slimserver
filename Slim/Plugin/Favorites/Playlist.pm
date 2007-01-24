package Slim::Plugin::Favorites::Playlist;

# $Id$

# Class to allow importing of playlist formats understood by SlimServer into opml files
# subclass the normal server format classes to avoid loading any data into the database

use strict;

our @ISA;

sub new {
	my $class         = shift;
	my $playlistClass = shift;

	@ISA = ( $playlistClass );

	return bless {}, $class;
}

sub _updateMetaData {
	my $class = shift;
	my $entry = shift;
	my $attib = shift;

	# return an opml entry in hash format
	return {
		'URL'  => $entry,
		'text' => $attib->{'TITLE'},
		'type' => 'audio',
	};
}

1;
