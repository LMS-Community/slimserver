package Slim::DataStores::DBI;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base 'DBIx::Class::Schema';

use Slim::Utils::Misc;
use Slim::Utils::Prefs;

sub init {
	my $class = __PACKAGE__;

	my $source   = sprintf(Slim::Utils::Prefs::get('dbsource'), 'slimserver');
	my $username = Slim::Utils::Prefs::get('dbusername');
	my $password = Slim::Utils::Prefs::get('dbpassword');

	$class->connection($source, $username, $password, { 
		RaiseError => 1,
		AutoCommit => 0,
		PrintError => 1,
		Taint      => 1,
	});

	my $dbh = $class->storage->dbh || do {

		# Not much we can do if there's no DB.
		msg("Couldn't connect to info database! Fatal error: [$!] Exiting!\n");
		bt();
		exit;
	};

	$class->load_classes(qw/
		Age
		Album
		Comment
		Contributor
		ContributorAlbum
		ContributorTrack
		Genre
		GenreTrack
		MetaInformation
		PlaylistTrack
		Rescan
		Track 
		Year 
	/);
}

sub rs {
	my $class = shift;

	return $class->resultset(@_);
}

sub search {
	my $class   = shift;
	my $rsClass = shift;

	return $class->resultset($rsClass)->search(@_);
}

sub find {
	my $class   = shift;
	my $rsClass = shift;

	return $class->resultset($rsClass)->find(@_);
}

1;

__END__
