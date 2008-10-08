package Slim::Plugin::iTunes::Importer::Artwork::OSX;

use strict;
use base 'Slim::Plugin::iTunes::Importer::Artwork';

use File::Spec::Functions qw(:ALL);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('plugin.itunes');
my $prefs = preferences('plugin.itunes');

sub exportDownloadedArtwork {
	my ( $class, $dest ) = @_;
	
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
		
		open my $proc, "$osa $script $dest --iter $index $skipUnchecked |" or do {
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
					name  => 'ITUNES_EXPORTING_DOWNLOADED_ARTWORK', 
					total => $total,
					bar   => 1,
				} );
			}
			
			$progress->update( $status, $index );
			
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

1;