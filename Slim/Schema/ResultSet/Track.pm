package Slim::Schema::ResultSet::Track;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Base);

use Slim::Utils::Prefs;

sub pageBarResults {
	my $self = shift;

	my $table = $self->{'attrs'}{'alias'};
	my $name  = "$table.titlesort";

	# SUBSTR() is supported by both MySQL and SQLite
	$self->search(undef, {
		'select'     => [ \"SUBSTR($name, 1, 1)", { count => \"DISTINCT($table.id)" } ],
		as           => [ 'letter', 'count' ],
		group_by     => \"SUBSTR($name, 1, 1)",
		result_class => 'Slim::Schema::PageBar',
	});
}

sub ignoreArticles { 1 }

sub searchColumn {
	my $self  = shift;

	return 'titlesearch';
}

sub searchNames {
	my $self  = shift;
	my $terms = shift;
	my $attrs = shift || {};
	
	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	$attrs->{'order_by'} ||= "me.disc, me.titlesort $collate";
	$attrs->{'distinct'} ||= 'me.id';

	return $self->search({
		'me.titlesearch' => { 'like' => $terms },
		'me.audio'       => 1,
	}, $attrs);
}

sub orderBy {
	my $self = shift;

	return 'album.titlesort,me.disc,me.tracknum,me.titlesort';
}

sub browse {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	
	my $sqlHelperClass = Slim::Utils::OSDetect->getOS()->sqlHelperClass();
	my $collate = $sqlHelperClass->collate();
	
	my $sort = shift || "me.titlesort $collate";
	
	my $join = '';

	# Only search for audio
	$cond->{'me.audio'} = 1;

	# If we need to order by album,titlesort, etc - join on album.
	if ($sort) {

		if ($sort =~ /album\./) {
			$join = 'album';
		}
		
		$sort =~ s/((?:\w+\.)?\w+sort)/$sqlHelperClass->prepend0($1) . " $collate"/eg;
	}

	# Join on album
	return $self->search($self->fixupFindKeys($cond), {
		'order_by' => $sort,
		'distinct' => 'me.id',
		'join'     => $join,
	});
}

# XXX  - These are wrappers around the methods in Slim::Schema, which need to
# be moved here. This is the proper API, and we want to have people using this
# now, and we can migrate the code underneath later.

sub objectForUrl {
	my $self = shift;

	return Slim::Schema->objectForUrl(@_);
}

sub updateOrCreate {
	my $self = shift;

	return Slim::Schema->updateOrCreate(@_);
}

# Do a raw query against the DB to get a list of track urls, without inflating anything.
sub allTracksAsPaths {
	my $self  = shift;
	my $path  = shift || '';

	my $dbh   = $self->result_source->storage->dbh;
	my $sth   = $dbh->prepare("SELECT url FROM tracks WHERE url LIKE '$path%'");
	my @paths = ();
	
	$sth->execute;

	while ( my ($url) = $sth->fetchrow_array ) {
		push @paths, Slim::Utils::Misc::pathFromFileURL($url, 1);
	}

	return \@paths;
}

# XXX: replace above method after scanner is fully refactored
sub allTracksAsPathsWithMTime {
	my $self  = shift;
	my $path  = shift || '';
	
	if ( $path !~ /^file/ ) {
		$path = Slim::Utils::Misc::fileURLFromPath($path);
	}

	my $dbh   = $self->result_source->storage->dbh;
	my $sth   = $dbh->prepare( qq{
		SELECT   url, timestamp, filesize
		FROM     tracks
		WHERE    url LIKE '$path%' 
		AND      content_type != 'dir'
		ORDER BY url
	} );
	
	my @paths = ();
	
	$sth->execute;

	while ( my ($url, $mtime, $size) = $sth->fetchrow_array ) {
		push @paths, [ Slim::Utils::Misc::pathFromFileURL($url, 1), $mtime, $size ];
	}

	return \@paths;
}

1;
