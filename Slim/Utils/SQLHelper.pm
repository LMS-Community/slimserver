package Slim::Utils::SQLHelper;

# $Id$

# Utility functions to handle reading of SQL files and executing them on the
# DB. This may be replaced by a combination of DBIx::Class's deploy
# functionality, in combination with DBIx::Migration.

use strict;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

use Slim::Utils::Misc;

sub executeSQLFile {
	my $class  = shift;
	my $driver = shift;
	my $dbh    = shift;
	my $file   = shift;

	my $sqlFile = $file;

	if (!file_name_is_absolute($file)) {
		$sqlFile = catdir($Bin, "SQL", $driver, $file);
	}

	$::d_info && msg("Executing SQL file $sqlFile\n");

	open(my $fh, $sqlFile) or do {

		errorMsg("executeSQLFile: Couldn't open file [$sqlFile] : $!\n");
		return 0;
	};

	my $statement   = '';
	my $inStatement = 0;

	for my $line (<$fh>) {
		chomp $line;

		# skip and strip comments & empty lines
		$line =~ s/\s*--.*?$//o;
		$line =~ s/^\s*//o;

		next if $line =~ /^--/;
		next if $line =~ /^\s*$/;

		if ($line =~ /^\s*(?:CREATE|USE|SET|INSERT|UPDATE|DELETE|DROP|SELECT)\s+/oi) {
			$inStatement = 1;
		}

		if ($line =~ /;/ && $inStatement) {

			$statement .= $line;

			$::d_sql && msg("Executing SQL statement: [$statement]\n");

			eval { $dbh->do($statement) };

			if ($@) {
				msg("Couldn't execute SQL statement: [$statement] : [$@]\n");
			}

			$statement   = '';
			$inStatement = 0;
			next;
		}

		$statement .= $line if $inStatement;
	}

	close $fh;

	return 1;
}

# This is a mess. Use DBIx::Migration instead.
sub findUpgrade {
	my $class       = shift;
	my $driver      = shift;
	my $currVersion = shift;

	my $sqlVerFilePath = catdir($Bin, "SQL", $driver, "sql.version");

	my $versionFile;

	open($versionFile, $sqlVerFilePath) or do {

		errorMsg("findUpgrade: Can't open file [$sqlVerFilePath] : $!\n");
		return 0;
	};

	my ($line, $from, $to);

	while ($line = <$versionFile>) {
		$line=~/^(\d+)\s+(\d+)\s*$/ || next;
		($from, $to) = ($1, $2);
		$from == $currVersion && last;
	}

	close($versionFile);

	if ((!defined $from) || ($from != $currVersion)) {
		$::d_info && msg("No upgrades found for database v. ". $currVersion."\n");
		return 0;
	}

	my $file = shift || catdir($Bin, "SQL", $driver, "Upgrades", "$to.sql");

	if (!-f $file && ($to != 99999)) {
		$::d_info && msg("database v. ".$currVersion." should be upgraded to v. $to but the files does not exist!\n");
		return 0;
	}

	$::d_info && msg("database v. ".$currVersion." requires upgrade to $to\n");

	return $to;
}

1;

__END__
