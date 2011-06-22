package Slim::Media::MediaFolderScan;

# $Id
#
# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Media::MediaFolderScan

=head1 DESCRIPTION

=cut

use strict;
use base qw(Class::Data::Inheritable);

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Scanner::Local;
use Slim::Utils::Scanner::LMS;
use Slim::Utils::Prefs;

{
	__PACKAGE__->mk_classdata('stillScanning');
}

my $log = logger('scan.import');

my $prefs = preferences('server');

sub init {
	my $class = shift;
	
	Slim::Music::Import->addImporter( $class, {
		type   => 'file',
		weight => 1,
	} );
	
	Slim::Music::Import->useImporter($class, 1);
}

sub startScan {
	my $class   = shift;
	my $dirs    = shift || Slim::Utils::Misc::getMediaDirs();

	if (ref $dirs ne 'ARRAY' || scalar @{$dirs} == 0) {
		main::INFOLOG && $log->info("Skipping media folder scan - no folders defined.");
		$class->stillScanning(0);
		Slim::Music::Import->endImporter($class);
		return;
	}

	$class->stillScanning(1);

	main::INFOLOG && $log->info("Starting media folder scan in: " . join(', ', @{$dirs}) );
	
	my $changes = Slim::Utils::Scanner::LMS->rescan( $dirs, {
		scanName => 'directory',
		no_async => 1,
		progress => 1,
	} );
	
	main::INFOLOG && $log->info("Finished scan of media folder (changes: $changes).");
	
	# XXX until libmediascan supports audio, run the audio scanner now
	for my $dir ( @{$dirs} ) {
		main::INFOLOG && $log->info("Starting audio-only scan in: $dir");
		
		$changes += Slim::Utils::Scanner::Local->rescan( $dir, {
			types    => 'audio',
			scanName => 'directory',
			no_async => 1,
			progress => 1,
		} );
	}

	$class->stillScanning(0);

	Slim::Music::Import->endImporter($class);
	
	return $changes;
}

=head1 SEE ALSO

L<Slim::Music::Import>

=cut

1;

__END__
