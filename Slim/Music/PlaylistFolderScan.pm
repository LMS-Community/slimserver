package Slim::Music::PlaylistFolderScan;

# $Id
#
# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Music::PlaylistFolderScan

=head1 DESCRIPTION

L<Slim::Music::PlaylistFolderScan>

=cut

use strict;
use base qw(Class::Data::Inheritable);

use Slim::Music::Import;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Scanner::Local;

{

	__PACKAGE__->mk_classdata('stillScanning');
}

my $log = logger('scan.import');

my $prefs = preferences('server');

sub init {
	my $class = shift;

	Slim::Music::Import->addImporter( $class, {
		type         => 'file',
		weight       => 10,
		playlistOnly => 1,
	} );

	# Enable Folder scan only if playlistdir is set and is a valid directory
	my $enabled  = 0;
	my $playlistDir = Slim::Utils::Misc::getPlaylistDir();

	if (defined $playlistDir && -d $playlistDir) {

		$enabled = 1;
	}

	Slim::Music::Import->useImporter($class, $enabled);
}

sub startScan {
	my $class   = shift;
	my $dir     = shift || Slim::Utils::Misc::getPlaylistDir();
	my $recurse = shift;

	if (main::SCANNER && scalar @ARGV && !Slim::Music::Import->scanPlaylistsOnly) {
		main::INFOLOG && $log->info("Skipping playlist folder scan - scanner was called with a single folder to scan.");

		$class->doneScanning();
		return;
	}

	if (!defined $dir || !-d $dir) {

		main::INFOLOG && $log->info("Skipping playlist folder scan - playlistdir is undefined.");

		$class->doneScanning();
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

	main::INFOLOG && $log->info("Starting playlist folder scan");
	
	my $changes = Slim::Utils::Scanner::Local->rescan( $dir, {
		types    => 'list',
		scanName => 'playlist',
		no_async => 1,
		progress => 1,
	} );

	$class->doneScanning;
	
	return $changes;
}

sub doneScanning {
	my $class = shift;

	# If scan aborted, $stillScanning will already be false.
	return if !$class->stillScanning;

	main::INFOLOG && $log->info("Finished scan of playlist folder.");

	$class->stillScanning(0);

	Slim::Music::Import->endImporter($class);
}

=head1 SEE ALSO

L<Slim::Music::Import>

=cut

1;

__END__
