package Slim::Plugin::iTunes::Importer::Artwork;

use strict;
use base 'Slim::Plugin::iTunes::Importer';

use File::Basename;
use File::Next;
use File::Path qw(mkpath);
use File::Spec::Functions qw(:ALL);

use Slim::Utils::Log;

my $log = logger('plugin.itunes');

sub startArtworkScan {
	my $class = shift;

	if ( !$class->useiTunesLibrary ) {
		return;
	}
	
	my $isDebug = $log->is_debug;
	
	# Export all downloaded artwork to cache directory
	my $cachedir = catdir( Slim::Utils::OSDetect::dirsFor('cache'), 'iTunesArtwork' );
	
	if ( !-d $cachedir ) {
		mkpath($cachedir) or do {
			logError("Unable to create iTunes artwork cache dir $cachedir");
			return;
		};
	}
	
	$log->debug("Exporting iTunes artwork to $cachedir");
	
	$class->exportDownloadedArtwork($cachedir);
	
	# Match all artwork that was exported with the correct track
	my $iter = File::Next::files( {
		file_filter   => sub { /\.(?:jpg|png)$/i },
		error_handler => sub { errorMsg("$_\n") },
	}, $cachedir );
	
	while ( my $file = $iter->() ) {
		# Get iTunes persistent ID from filename and match to Track object
		$file = basename($file);
		my ($pid) = $file =~ /^([^.]+)/;
		
		my $track = Slim::Schema->rs('Track')->single( { extid => $pid } );
		
		if ( $track ) {			
			if ( !$track->coverArtExists ) {
				$isDebug && $log->debug( "Updating artwork for $pid (" . $track->title . ")" );
				
				$track->cover( catfile( $cachedir, $file ) );
				$track->update;
				
				my $album = $track->album;
				if ( !$album->artwork ) {
					$album->artwork( $track->id );
					$album->update;
				}
				
				Slim::Music::Artwork::precacheArtwork( $track->id );
			}
			else {
				$isDebug && $log->debug( "Track $pid (" . $track->title . ") already has artwork" );
			}
		}
		else {
			$isDebug && $log->debug( "Track not found for persistent ID $pid" );
		}
	}
	
	# XXX: go through all remaining items without artwork, check iTunes for
	# artwork, as it may have been manually added by the user
	
	Slim::Music::Import->endImporter($class);
}

1;