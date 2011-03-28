package Slim::Video::VideoFolderScan;

# $Id
#
# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Video::VideoFolderScan

=head1 DESCRIPTION

=cut

use strict;
use base qw(Class::Data::Inheritable);

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Scanner::LMS;
use Slim::Utils::Prefs;

{

	__PACKAGE__->mk_classdata('stillScanning');
}

my $log = logger('scan.import');

my $prefs = preferences('server');

sub init {
	my $class = shift;

	# Enable Folder scan only if videodir is set and is a valid directory
	my $enabled  = 0;
	my $videodir = Slim::Utils::Misc::getVideoDir();

	if (defined $videodir && -d $videodir) {
		$enabled = 1;
	}

	Slim::Music::Import->addImporter( $class, {
		type   => 'file',
		weight => 2,   # after music
	} );
	
	Slim::Music::Import->useImporter($class, $enabled);
}

sub startScan {
	my $class   = shift;
	my $dir     = shift || Slim::Utils::Misc::getVideoDir();

	if (!defined $dir || !-d $dir) {

		main::INFOLOG && $log->info("Skipping video folder scan - videodir is undefined. [$dir]");

		doneScanning();
		return;
	}

	if ($class->stillScanning) {

		main::INFOLOG && $log->info("Scan already in progress. Restarting");

		$class->stillScanning(0);
	}

	$class->stillScanning(1);

	main::INFOLOG && $log->info("Starting video folder scan in $dir");
	
	my $changes = Slim::Utils::Scanner::LMS->rescan( $dir, {
		types    => 'video',
		scanName => 'directory',
		no_async => 1,
		progress => 1,
	} );
	
	main::INFOLOG && $log->info("Finished scan of video folder (changes: $changes).");

	$class->stillScanning(0);

	Slim::Music::Import->endImporter($class);
	
	return $changes;
}

=head1 SEE ALSO

L<Slim::Music::Import>

=cut

1;

__END__
