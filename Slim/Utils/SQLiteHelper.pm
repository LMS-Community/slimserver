package Slim::Utils::SQLiteHelper;

# $Id$

=head1 NAME

Slim::Utils::SQLiteHelper

=head1 SYNOPSIS

Slim::Utils::SQLiteHelper->init

=head1 DESCRIPTION

Currently only used for SN

=head1 METHODS

=cut

use strict;
use File::Path;
use File::Slurp;
use File::Spec::Functions qw(:ALL);
use Time::HiRes qw(sleep);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::SQLHelper;
use Slim::Utils::Prefs;

my $log = logger('database.info');

my $prefs = preferences('server');

sub storageClass { 'DBIx::Class::Storage::DBI::SQLite' };

sub default_dbsource { 'dbi:SQLite:dbname=%s' }

sub init {
	my ( $class, $dbh ) = @_;
	
	if ( main::SLIM_SERVICE ) {
		# Create new empty database every time we startup on SN
		require File::Slurp;
		require FindBin;
		
		my $text = File::Slurp::read_file( "$FindBin::Bin/SQL/slimservice/slimservice-sqlite.sql" );
		
		$text =~ s/\s*--.*$//g;
		for my $sql ( split /;/, $text ) {
			next unless $sql =~ /\w/;
			$dbh->do($sql);
		}
	}
}

sub source {
	my $source;
	
	if ( main::SLIM_SERVICE ) {
		my $config = SDI::Util::SNConfig::get_config();
		my $db = ( $config->{database}->{sqlite_path} || '.' ) . "/slimservice.$$.db";
		
		unlink $db if -e $db;
		
		$source = "dbi:SQLite:dbname=$db";
	}
	else {
		$source = sprintf( $prefs->get('dbsource'), catfile( $prefs->get('librarycachedir'), 'squeezebox.db' ) );
	}
	
	return $source;
}

sub on_connect_do {
	return [
		'PRAGMA synchronous = OFF',
		'PRAGMA journal_mode = MEMORY',
		'PRAGMA temp_store = MEMORY',
	];
}

sub changeCollation {
	my ( $class, $dbh, $collation ) = @_;
	
	# XXX
}

=head2 randomFunction()

Returns RAND(), MySQL-specific random function

=cut

sub randomFunction { 'RANDOM()' }

=head2 prepend0( $string )

Returns concat( '0', $string )

=cut

sub prepend0 { '0 || ' . $_[1] }

=head2 append0( $string )

Returns concat( $string, '0' )

=cut

sub append0 {  $_[1] . ' || 0' }

=head2 concatFunction()

Returns 'concat', used in a string comparison to see if something has already been concat()'ed

=cut

sub concatFunction { ' || ' }

=head2 sqlVersion( $dbh )

Returns the version of MySQL that the $dbh is connected to.

=cut

sub sqlVersion {
	my $class = shift;
	my $dbh   = shift || return 0;
	
	return 'SQLite'; # XXX
}

=head2 sqlVersionLong( $dbh )

Returns the long version string, i.e. 5.0.22-standard

=cut

sub sqlVersionLong {
	my $class = shift;
	my $dbh   = shift || return 0;
	
	return 'SQLite'; # XXX
}	

=head2 cleanup()

Shut down when Squeezebox Server is shut down.

=cut

sub cleanup { }

1;
