package Slim::Music::MusicFolderScan;

# $Id
#
# SlimServer Copyright (c) 2001-2006  Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Music::MusicFolderScan

=head1 DESCRIPTION

=cut

use strict;
use base qw(Class::Data::Inheritable);

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Scanner;
use Slim::Utils::Prefs;

{

	__PACKAGE__->mk_classdata('stillScanning');
}

my $log = logger('scan.import');

my $prefs = preferences('server');

sub init {
	my $class = shift;

	# Enable Folder scan only if audiodir is set and is a valid directory
	my $enabled  = 0;
	my $audioDir = $prefs->get('audiodir');

	if (defined $audioDir && -d $audioDir) {

		$enabled = 1;
	}

	Slim::Music::Import->addImporter($class);
	Slim::Music::Import->useImporter($class, $enabled);
}

sub startScan {
	my $class   = shift;
	my $dir     = shift || $prefs->get('audiodir');
	my $recurse = shift;

	if (!defined $dir || !-d $dir) {

		$log->info("Skipping music folder scan - audiodir is undefined. [$dir]");

		doneScanning();
		return;
	}

	if ($class->stillScanning) {

		$log->info("Scan already in progress. Restarting");

		$class->stillScanning(0);
	}

	$class->stillScanning(1);

	if (!defined $recurse) {
		$recurse = 1;
	}

	$log->info("Starting music folder scan in $dir");

	Slim::Utils::Scanner->scanDirectory({
		'url'       => $dir,
		'recursive' => $recurse,
		'types'     => 'audio',
		'scanName'  => 'directory',
	});

	$log->info("Finished background scan of music folder.");

	$class->stillScanning(0);

	Slim::Music::Import->endImporter($class);
}

=head1 SEE ALSO

L<Slim::Music::Import>

=cut

1;

__END__
