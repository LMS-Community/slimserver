package Slim::Schema::Progress;


use strict;
use base 'Slim::Schema::DBI';

{
	my $class = __PACKAGE__;

	$class->table('progress');

	$class->add_columns(qw/id type name active total done start finish info/);
	$class->set_primary_key('id');

	if ($] > 5.007) {
		$class->utf8_columns(qw/name info/);
	}
}

1;

__END__
