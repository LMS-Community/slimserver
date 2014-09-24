package Slim::Music::VirtualLibraries;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Music::VirtualLibraries

=head1 DESCRIPTION

Helper class to deal with virtual libraries. Plugins can register virtual library handlers to do the actual filtering.

=head1 METHODS


	my $class = 'Slim::Plugin::MyVirtualLibrary';

	# Define some virtual libraries.
	# - id:        the library's ID. Use something specific to your plugin to prevent dupes.
	# - name:      the user facing name, shown in menus and settings
	# - sql:       a SQL statement which creates the records in library_track
	# - scannerCB: a sub ref to some code creating the records in library_track. Use scannerCB
	#              if your library logic is a bit more complex than a simple SQL statement.
	# - priority:  optionally define a numerical priority if you want your library definition
	#              to be evaluated in a given order. Lower values are built first. Defaults to 0.
	# - unregisterCB: optionally define a callback to be executed before a library view is
	#              being removed. Can eg. be used to clean up some plugin specific data.
	
	# sql and scannerCB are mutually exclusive. scannerCB takes precedence over sql.
	
	Slim::Music::VirtualLibraries->registerLibrary( {
		id => 'demoLongTracks',
		name => 'Longish tracks only',
		# %s is being replaced with the library's internal ID
		sql => qq{
			INSERT OR IGNORE INTO library_track (library, track)
				SELECT '%s', tracks.id 
				FROM tracks 
				WHERE tracks.secs > 600
		},
		unregisterCB => sub {
			my $id = shift;
			# do something useful wehn this library is being unregistered
			$prefs->remove('library_' . $id);
		}
	} );
	
	Slim::Music::VirtualLibraries->registerLibrary( {
		id => 'demoComplexLibrary',
		name => 'Library based on some complex processing',
		scannerCB => sub {
			my $id = shift;		# use this internal ID rather than yours!
			
			# do some serious processing here
			...
			
			# don't forget to update the library_track table with ($id, 'track_id') tuples at some point!
		}
	} );

L<Slim::Music::VirtualLibraries>

=cut

use strict;

use Digest::MD5 qw(md5_hex);

use Slim::Utils::Log qw(logError);
use Slim::Utils::Prefs;
use Slim::Music::Import;

my $prefs = preferences('server');

my %libraries;

sub init {
	my $class = shift;
	
	Slim::Music::Import->addImporter( $class, {
		type   => 'post',
		weight => 100,
	} );
}

sub registerLibrary {
	my ($class, $args) = @_;

	if ( !$args->{id} ) {
		logError('Invalid parameters: you need to register with a name and a unique ID');
		return;
	}
	
	# we use a short hashed version of the real ID
	my $id  = $args->{id};
	my $id2 = substr(md5_hex($id), 0, 8);
	
	if ( $libraries{$id2} ) {
		logError('Duplicate library ID: ' . $id);
		return;
	}
	
	$libraries{$id2} = $args;
	$libraries{$id2}->{name} ||= $args->{id};

	Slim::Music::Import->useImporter( $class, 1);
	
	return $id2;
}

sub unregisterLibrary {
	my ($class, $id) = @_;
	
	$id = $class->getRealId($id);
	
	return unless $id && $libraries{$id};
	
	if ($libraries{$id}->{unregisterCB}) {
		$libraries{$id}->{unregisterCB}->($libraries{$id}->{id});
	}

	# make sure noone is using this library any more
	foreach my $clientPref ( $prefs->allClients ) {
		$clientPref->remove('libraryId');
	}
	
	delete $libraries{$id};
}

# called by the scanner module
sub startScan {
	my $class = shift;
	
	return unless hasLibraries();
	
	my $count = hasLibraries();

	my $progress = Slim::Utils::Progress->new({ 
		'type'  => 'importer', 
		'name'  => 'virtuallibraries', 
		'total' => $count, 
		'bar'   => 1
	});

	my $delete_sth;
	foreach my $id ( sort { ($libraries{$a}->{priority} || 0) <=> ($libraries{$b}->{priority} || 0) } keys %libraries ) {
		$progress->update($libraries{$id}->{name});
		Slim::Schema->forceCommit;
		
		$class->rebuild($id);
	}

	$progress->final($count);

	Slim::Music::Import->endImporter($class);
}

sub rebuild {
	my ($class, $id) = @_;
	
	$id = $class->getRealId($id);
	
	my $args = $libraries{$id};

	return unless $args && ref $args eq 'HASH';

	if ( my $cb = $args->{scannerCB} ) {
		$cb->($id);
	}
	elsif ( my $sql = $args->{sql} ) {
		my $dbh = Slim::Schema->dbh;

		# SQL code is supposed to re-build the full library. Delete the old values first:
		my $delete_sth = $dbh->prepare_cached('DELETE FROM library_track WHERE library = ?');
		$delete_sth->execute($id);
		
		$dbh->do( sprintf($sql, $id) );
	}
	
	return 1;
}


sub getLibraries {
	return \%libraries;
}

sub hasLibraries {
	return scalar keys %libraries;
}

# because we store a hashed version of the ID we might need to look it up
sub getRealId {
	my ($class, $id) = @_;
	
	return $id if $libraries{$id};
	
	my ($id2) = grep { $libraries{$_}->{id} eq $id } keys %libraries;
	return $id2;
}

# return a library ID set for a client or globally in LMS
sub getLibraryIdForClient {
	my ($class, $client) = @_;
	
	return '' unless keys %libraries;
	
	my $id;
	$id   = $prefs->client($client)->get('libraryId') if $client;
	$id ||= $prefs->get('libraryId');
	
	return '' unless $id && $libraries{$id};
	
	return $id || '';
}

sub getNameForId {
	my ($class, $id) = @_;
	
	$id = $class->getRealId($id);
	
	return '' unless $libraries{$id};
	return $libraries{$id}->{name} || '';
}


1;