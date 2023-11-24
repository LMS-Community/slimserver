package Slim::Schema::DBI;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(DBIx::Class);

use Slim::Utils::Log;

my $dirtyCount = 0;

{
	my $class = __PACKAGE__;

	my @components = qw(PK::Auto Core);

	if ($] > 5.007) {
		unshift @components, 'UTF8Columns';
	}

	$class->load_components(@components);
}

sub update {
	my $self = shift;

	if ( !main::SCANNER ) {
		return $self->SUPER::update;
	}

	if ($self->is_changed) {

		$dirtyCount++;
		$self->SUPER::update;
	}

	# This is only applicable to the scanner, as the main process is in AutoCommit mode.
	# Commit to the DB every 500 updates.. just a random number.
	if (($dirtyCount % 500) == 0) {

		Slim::Schema->forceCommit;
		$dirtyCount = 0;
	}

	return 1;
}

sub get {
	my $self = shift;

	return @{$self->{_column_data}}{@_};
}

sub set {
	return shift->set_column(@_);
}

# Walk any table and check for foreign rows that still exist.
# TODO - can probably be removed, as it's not called any more. Probably replaced by the rescan() method in many cases (eg. Slim::Schema::Album->rescan)?
sub removeStaleDBEntries {
	my $class   = shift;
	my $foreign = shift;

	my $log     = logger('scan.import');

	main::INFOLOG && $log->info("Starting stale cleanup for class $class / $foreign");

	my $rs   = Slim::Schema->search($class, undef, { 'prefetch' => $foreign });
	my $vaId = Slim::Schema->variousArtistsObject->id;

	# fetch one at a time to keep memory usage in check.
        while (my $obj = $rs->next) {

		# Don't delete the VA object.
		if ($obj->id == $vaId) {
			next;
		}

		if ($obj->search_related($foreign)->count == 0) {

			if ( main::INFOLOG && $log->is_info ) {
				$log->info(sprintf("DB garbage collection - removing $class: %s - no more $foreign!", $obj->name));
			}

			$obj->delete;

			$dirtyCount++;
		}
	}

	main::INFOLOG && $log->info("Finished stale cleanup for class $class / $foreign");
}

1;

__END__
