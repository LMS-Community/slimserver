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
use Slim::Utils::Prefs;

{
	__PACKAGE__->mk_classdata('stillScanning');
}

my $log = logger('scan.import');

my $prefs = preferences('server');

sub init {
	my $class = shift;
	
	if ( main::IMAGE || main::VIDEO ) {
		require Slim::Utils::Scanner::LMS;
	}
	
	Slim::Music::Import->addImporter( $class, {
		type   => 'file',
		weight => 1,
	} );
	
	Slim::Music::Import->useImporter($class, 1);
}

sub startScan {
	my $class = shift;
	my $dirs  = shift || Slim::Utils::Misc::getMediaDirs();

	if (ref $dirs ne 'ARRAY' || scalar @{$dirs} == 0) {
		main::INFOLOG && $log->info("Skipping media folder scan - no folders defined.");
		$class->stillScanning(0);
		Slim::Music::Import->endImporter($class);
		return 0;
	}

	$class->stillScanning(1);

	my $changes = 0;
	
	# XXX until libmediascan supports audio, run the audio scanner first
	if ( ($dirs = Slim::Utils::Misc::getAudioDirs()) && scalar @{$dirs} ) {
		main::INFOLOG && $log->info("Starting audio-only scan in: " . Data::Dump::dump($dirs));
		
		my $c = Slim::Utils::Scanner::Local->rescan( $dirs, {
			types    => 'audio',
			scanName => 'directory',
			no_async => 1,
			progress => 1,
		} );
		
		$changes += $c;
	}

	if ( main::IMAGE || main::VIDEO ) {
		# get media folders without audio dirs
		my %seen = (); # to avoid duplicates
		$dirs = [ grep { !$seen{$_}++ } @{ Slim::Utils::Misc::getVideoDirs() }, @{ Slim::Utils::Misc::getImageDirs() } ];
	
		# XXX any good reason this doesn't just pass all dirs?
		for my $dir ( @{$dirs} ) {
			main::INFOLOG && $log->info("Starting media folder scan in: $dir" );
			my $c = Slim::Utils::Scanner::LMS->rescan( $dir, {
				scanName => 'directory',
				wipe     => main::SCANNER && $main::wipe ? 1 : 0, # XXX ugly
				no_async => 1,
				progress => 1,
			} );
		
			$changes += $c;
		}
	
		main::INFOLOG && $log->info("Finished scan of media folder (changes: $changes).");
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
