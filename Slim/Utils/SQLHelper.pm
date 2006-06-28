package Slim::Utils::SQLHelper;

# $Id$

# Utility functions to handle reading of SQL files and executing them on the
# DB. This may be replaced by DBIx::Class's deploy functionality.

use strict;
use File::Spec::Functions qw(:ALL);

use Slim::Utils::OSDetect;
use Slim::Utils::Misc;

sub executeSQLFile {
	my $class  = shift;
	my $driver = shift;
	my $dbh    = shift;
	my $file   = shift;

	my $sqlFile = $file;

	if (!file_name_is_absolute($file)) {
		$sqlFile = catdir(Slim::Utils::OSDetect::dirsFor('SQL'), $driver, $file);
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

		if ($line =~ /^\s*(?:ALTER|CREATE|USE|SET|INSERT|UPDATE|DELETE|DROP|SELECT|OPTIMIZE)\s+/oi) {
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

1;

__END__
