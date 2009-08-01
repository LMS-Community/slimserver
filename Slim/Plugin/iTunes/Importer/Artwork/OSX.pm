package Slim::Plugin::iTunes::Importer::Artwork::OSX;

use strict;
use base 'Slim::Plugin::iTunes::Importer::Artwork';

use File::Spec::Functions qw(:ALL);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('plugin.itunes');
my $prefs = preferences('plugin.itunes');

sub initArtworkExport { }

sub supportsArtworkExport { 1 }

sub exportDownloadedArtwork {
	my ( $class, $cachedir ) = @_;
	
	my $isDebug = $log->is_debug;
	
	my $osa    = Slim::Utils::Misc::findbin('osascript');
	my $script = Slim::Utils::Misc::findbin('itartwork.scpt');
	
	my $index = 0;
	my $total = 0;
	my $skipUnchecked = !$prefs->get('ignore_disabled') ? '--skip-unchecked' : '';
	my $done;
	my $progress;
	
	while ( !$done ) {
		$index++;
		
		open my $proc, "$osa $script $cachedir --iter $index $skipUnchecked |" or do {
			logError("Unable to run artwork script: $!");
			return;
		};
		
		my $status = <$proc>;
		chomp $status;
		
		close $proc;
		
		if ( $status =~ m{^(\d+)/(\d+)} ) {
			$index     = $1;
			$total     = $2;
			
			$isDebug && $log->debug( $status );
			
			if ( !$progress ) {
				$progress = Slim::Utils::Progress->new( { 
					type  => 'importer', 
					name  => 'itunes_artwork_phase_1', 
					total => $total,
					bar   => 1,
				} );
			}
			
			$progress->update( undef, $index );
			
			if ( $index >= $total ) {
				$done = 1;
				
				$progress->final;
			}
		}
		else {
			logError("Invalid output from artwork script: $status");
			
			return;
		}
	}
}

sub exportSingleArtwork {
	my ( $class, $cachedir, $track ) = @_;
	
	my $osa    = Slim::Utils::Misc::findbin('osascript');
	my $script = Slim::Utils::Misc::findbin('itartwork.scpt');
	
	my $search = $track->title;
	my $pid    = $track->extid;
	
	if ( $search =~ /"/ ) {
		$search =~ s/"/\\"/g;
	}
	
	open my $proc, "$osa $script $cachedir --single \"$search\" $pid |" or do {
		logError("Unable to run artwork script: $!");
		return;
	};
	
	my $status = <$proc>;
	chomp $status;
	
	close $proc;
	
	if ( $status =~ /^OK (.+)/ ) {
		my $file = $1;
		
		main::DEBUGLOG && $log->is_debug && $log->debug( $status );
		
		return $file;
	}
	else {
		logError("Error from artwork script: $status");
	}
	
	return;
}

sub finishArtworkExport {
	my ( $class, $cachedir ) = @_;
	
	# Tell iTunes to quit if we had to start it
	my $osa    = Slim::Utils::Misc::findbin('osascript');
	my $script = Slim::Utils::Misc::findbin('itartwork.scpt');
	
	open my $proc, "$osa $script $cachedir --shutdown | " or do {
		logError("Unable to run artwork shutdown script: $!");
		return;
	};
	
	my $status = <$proc>;
	chomp $status;
	
	main::DEBUGLOG && $log->is_debug && $log->debug($status);
}

1;