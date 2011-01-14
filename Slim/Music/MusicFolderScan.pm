package Slim::Music::MusicFolderScan;

# $Id
#
# Squeezebox Server Copyright 2001-2009 Logitech.
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
use Slim::Utils::Scanner::Local;
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
	my $audioDir = Slim::Utils::Misc::getAudioDir();

	if (defined $audioDir && -d $audioDir) {
		$enabled = 1;
	}

	Slim::Music::Import->addImporter( $class, {
		type   => 'file',
		weight => 1,   # always run the file importer first
	} );
	
	Slim::Music::Import->useImporter($class, $enabled);
}

sub startScan {
	my $class   = shift;
	my $dir     = shift || Slim::Utils::Misc::getAudioDir();
	my $recurse = shift;

	if (!defined $dir || !-d $dir) {

		main::INFOLOG && $log->info("Skipping music folder scan - audiodir is undefined. [$dir]");

		doneScanning();
		return;
	}

	if ($class->stillScanning) {

		main::INFOLOG && $log->info("Scan already in progress. Restarting");

		$class->stillScanning(0);
	}

	$class->stillScanning(1);

	if (!defined $recurse) {
		$recurse = 1;
	}

	main::INFOLOG && $log->info("Starting music folder scan in $dir");
	
	my $changes = Slim::Utils::Scanner::Local->rescan( $dir, {
		types    => 'audio',
		scanName => 'directory',
		no_async => 1,
		progress => 1,
	} );
	
	main::INFOLOG && $log->info("Finished scan of music folder (changes: $changes).");

	$class->stillScanning(0);

	Slim::Music::Import->endImporter($class);
	
	return $changes;
}

=head1 SEE ALSO

L<Slim::Music::Import>

=cut

1;

__END__
