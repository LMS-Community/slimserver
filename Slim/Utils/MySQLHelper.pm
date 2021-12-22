package Slim::Utils::MySQLHelper;


=head1 NAME

Slim::Utils::MySQLHelper

=head1 SYNOPSIS

Slim::Utils::MySQLHelper->init

=head1 DESCRIPTION

Helper class for launching MySQL, installing the system tables, etc.

=head1 METHODS

=cut

use strict;
use base qw(Class::Data::Inheritable);
use DBI;
use DBI::Const::GetInfoType;
use File::Path;
use File::Slurp;
use File::Spec::Functions qw(:ALL);
use Proc::Background;
use Time::HiRes qw(sleep);

{
	if (main::ISWINDOWS) {
		require Win32::Service;
	}
}

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Utils::SQLHelper;
use Slim::Utils::Prefs;

{
	my $class = __PACKAGE__;

	for my $accessor (qw(confFile socketFile)) {
		$class->mk_classdata($accessor);
	}
}

my $log = logger('database.mysql');

my $prefs = preferences('server');

sub storageClass {'DBIx::Class::Storage::DBI::mysql'};

sub default_dbsource { 'dbi:mysql:hostname=127.0.0.1;port=9092;database=%s' }

=head2 init()

Initializes the entire MySQL subsystem - creates the config file, and starts the server.

=cut

sub init {
	my $class = shift;

	# Reset dbsource pref if it's not for MySQL
	if ( $prefs->get('dbsource') !~ /^dbi:mysql/ ) {
		$prefs->set( dbsource => default_dbsource() );
		$prefs->set( dbsource => $class->source() );
	}

	# Check to see if our private port is being used. If not, we'll assume
	# the user has setup their own copy of MySQL.
	if ($prefs->get('dbsource') !~ /port=9092/) {

		main::INFOLOG && $log->info("Not starting MySQL - looks to be user/system configured.");
		Slim::Utils::OSDetect::getOS->initMySQL($class);

		return 1;
	}

	$log->error("Invalid MySQL configuration.");

	return;
}

sub source {
	return sprintf($prefs->get('dbsource'), 'slimserver');
}

sub on_connect_do {
	return [ 'SET NAMES UTF8' ];
}

sub collate {
	my $class = shift;

	my $lang = $prefs->get('language');

	my $collation
		= $lang eq 'CS' ? 'utf8_czech_ci'
		: $lang eq 'SV' ? 'utf8_swedish_ci'
		: $lang eq 'DA' ? 'utf8_danish_ci'
		: $lang eq 'ES' ? 'utf8_spanish_ci'
		: $lang eq 'PL' ? 'utf8_polish_ci'
		: 'utf8_general_ci';

	return "COLLATE $collation ";
}

=head2 randomFunction()

Returns RAND(), MySQL-specific random function

=cut

sub randomFunction { 'RAND()' }

=head2 prepend0( $string )

Returns concat( '0', $string )

=cut

sub prepend0 { "concat('0', " . $_[1] . ")" }

=head2 append0( $string )

Returns concat( $string, '0' )

=cut

sub append0 { "concat(" . $_[1] . ", '0')" }

=head2 concatFunction()

Returns 'concat', used in a string comparison to see if something has already been concat()'ed

=cut

sub concatFunction { 'concat' }

=head2 dbh()

Returns a L<DBI> database handle, using the dbsource preference setting .

=cut

sub dbh {
	my $class = shift;
	my $dsn   = '';

	if (main::ISWINDOWS) {

		$dsn = $prefs->get('dbsource');
		$dsn =~ s/;database=.+;?//;

	} else {

		$dsn = sprintf('dbi:mysql:mysql_read_default_file=%s', $class->confFile );
	}

	$^W = 0;

	return eval { DBI->connect($dsn, undef, undef, { 'PrintError' => 0, 'RaiseError' => 0 }) };
}

=head2 mysqlVersion( $dbh )

Returns the version of MySQL that the $dbh is connected to.

=cut

sub sqlVersion {
	my $class = shift;
	my $dbh   = shift || return 0;

	my $mysqlVersion = $dbh->get_info($GetInfoType{'SQL_DBMS_VER'}) || 0;

	if ($mysqlVersion && $mysqlVersion =~ /^(\d+\.\d+)/) {

        	return $1;
	}

	return $mysqlVersion || 0;
}

=head2 mysqlVersionLong( $dbh )

Returns the long version string, i.e. 5.0.22-standard

=cut

sub sqlVersionLong {
	my $class = shift;
	my $dbh   = shift || return 0;

	my ($mysqlVersion) = $dbh->selectrow_array( 'SELECT version()' );

	return 'MySQL ' . $mysqlVersion || 0;
}

=head2 canCacheDBHandle( )

Is it permitted to cache the DB handle for the period that the DB is open?

=cut

sub canCacheDBHandle {
	return 0;
}

sub checkDataSource { }

sub beforeScan { }

sub afterScan { }

sub exitScan { }

sub optimizeDB { }

sub updateProgress { }

sub postConnect { }
sub addPostConnectHandler {}

sub pragma { }

sub cleanup {}

=head1 SEE ALSO

L<DBI>

L<DBD::mysql>

L<http://www.mysql.com/>

=cut

1;

__END__
