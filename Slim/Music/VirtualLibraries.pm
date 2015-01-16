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
	# - persist:   keep track of the library definition without the caller's help. This option
	#              is invalid if you use any of the callback parameters.
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

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Music::Import;

my $serverPrefs = preferences('server');
my $prefs = preferences('virtualLibraries');

my $log = logger('database.virtuallibraries');

my %libraries;

sub init {
	my $class = shift;
	
	Slim::Music::Import->addImporter( $class, {
		type   => 'post',
		weight => 100,
	} );
	
	# restore virtual libraries
	foreach my $vlid ( grep /^vlid_[\da-f]+$/, keys %{$prefs->all} ) {
		my $vl = $prefs->get($vlid);

		$class->registerLibrary( $vl ) if $vl && ref $vl eq 'HASH';
	}
}

sub registerLibrary {
	my ($class, $args) = @_;

	if ( !$args->{id} ) {
		$log->error('Invalid parameters: you need to register with a name and a unique ID');
		return;
	}
	
	# we use a short hashed version of the real ID
	my $id  = $args->{id};
	my $id2 = substr(md5_hex($id), 0, 8);
	
	if ( $args->{persist} ) {
		if ( $args->{scannerCB} || $args->{unregisterCB} ) {
			$log->error('Invalid parameters: you cannot persist a library definition with callbacks: ' . Data::Dump::dump($args));
			return;
		}
		
		delete $args->{persist};
		
		$prefs->set('vlid_' . $id2, $args);
	}
	
	if ( $libraries{$id2} ) {
		$log->error('Duplicate library ID: ' . $id);
		return;
	}
	
	if ( $args->{sql} ) {
		# SQL can be a list ref as returned by $rs->as_query
		if ( ref $args->{sql} ) {
			$args->{params} = [ map { $_->[1] } splice @{$args->{sql}}, 1 ];
			$args->{sql}    = shift @{$args->{sql}};
		}
		
		if ( $args->{sql} !~ /SELECT .*\%s/si ) {
			main::INFOLOG && $log->info("Missing library ID placeholder: " . $args->{sql});
			$args->{sql} = "INSERT OR IGNORE INTO library_track (library, track) SELECT '%s', id FROM (" . $args->{sql} . ")";
			main::DEBUGLOG && $log->debug("Using: " . $args->{sql});
		}
		
		if ( $args->{sql} !~ /INSERT/i ) {
			main::INFOLOG && $log->info("Missing INSERT statement in SQL: " . $args->{sql});
			$args->{sql} = 'INSERT OR IGNORE INTO library_track (library, track) ' . $args->{sql};
			main::DEBUGLOG && $log->debug("Using: " . $args->{sql});
		}
	}

	if ( $class->getIdForName($args->{name}) ) {
		my $timeFormat = $serverPrefs->get('timeFormat');
		$timeFormat =~ s/%M/%M.%S/;
		$args->{name} .= ' - ' . Slim::Utils::DateTime::shortDateF() . ' '. Slim::Utils::DateTime::timeF(time, $timeFormat);
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
	foreach my $clientPref ( $serverPrefs->allClients ) {
		$clientPref->remove('libraryId');
	}
	
	delete $libraries{$id};
	$prefs->remove('vlid_'  . $id);	
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
		
		$dbh->do( sprintf($sql, $id), undef, @{ $args->{params} || [] } );
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
	
	return if !$id || $id == -1;
	
	return $id if $libraries{$id};
	
	my ($id2) = grep { $libraries{$_}->{id} eq $id } keys %libraries;
	return $id2;
}

# return a library ID set for a client or globally in LMS
sub getLibraryIdForClient {
	my ($class, $client) = @_;
	
	return '' unless keys %libraries;
	
	my $id;
	$id   = $serverPrefs->client($client)->get('libraryId') if $client;
	$id ||= $serverPrefs->get('libraryId');
	
	return '' unless $id && $libraries{$id};
	
	return $id || '';
}

sub getNameForId {
	my ($class, $id) = @_;
	
	$id = $class->getRealId($id);
	
	return '' unless $libraries{$id};
	return $libraries{$id}->{name} || '';
}

sub getIdForName {
	my ($class, $name) = @_;
	
	return '' unless keys %libraries;
	
	my ($id) = grep { $libraries{$_}->{name} eq $name } keys %libraries;
	
	return $id || ''; 
}

sub getTrackCount {
	my ($class, $id) = @_;
	
	$id = $class->getRealId($id);
	
	return 0 unless $libraries{$id};

	my $sth = Slim::Schema->dbh->prepare_cached('SELECT COUNT(1) FROM library_track WHERE library = ? GROUP BY library');
	
	$sth->execute($id);
	my ($count) = $sth->fetchrow_array();
	$sth->finish;
	
	return $count || 0;
}

1;