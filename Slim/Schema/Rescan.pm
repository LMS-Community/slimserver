package Slim::Schema::Rescan;


use strict;
use base 'Slim::Schema::DBI';

{
	my $class = __PACKAGE__;

	$class->table('rescans');

	$class->add_columns(qw/id files_scanned files_to_scan start_time end_time/);
	$class->set_primary_key('id');
}

sub totalTime {
	my $self = shift;

	return ($self->end_time - $self->start_time);
}

1;

__END__
