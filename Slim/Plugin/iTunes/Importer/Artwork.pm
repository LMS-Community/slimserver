package Slim::Plugin::iTunes::Importer::Artwork;

use strict;
use base 'Slim::Plugin::iTunes::Importer';

use File::Basename;
use File::Next;
use File::Path qw(mkpath);
use File::Spec::Functions qw(:ALL);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('plugin.itunes');
my $prefs = preferences('plugin.itunes');

sub startArtworkScan {
	my $class = shift;

	if ( !$class->useiTunesLibrary ) {
		return;
	}
	
	return if !$prefs->get('extract_artwork');
	
	$class->initArtworkExport;
	
	# Make sure iTunes version is new enough for this
	if ( !$class->supportsArtworkExport ) {
		return;
	}
	
	my $isDebug = $log->is_debug;
	
	# Export all downloaded artwork to cache directory
	# This full export is only performed once per 'wipe'
	my $cachedir = catdir( preferences('server')->get('librarycachedir'), 'iTunesArtwork' );
	if ( !-d $cachedir ) {
		mkpath($cachedir) or do {
			logError("Unable to create iTunes artwork cache dir $cachedir");
			return;
		};
	
		main::DEBUGLOG && $log->debug("Exporting iTunes artwork to $cachedir");
	
		$class->exportDownloadedArtwork($cachedir);
	
		# Match all artwork that was exported with the correct track
		my $iter = File::Next::files( {
			file_filter   => sub { /\.(?:jpg|png|bmp)$/i },
			error_handler => sub { errorMsg("$_\n") },
		}, $cachedir );
	
		while ( my $file = $iter->() ) {
			# Get iTunes persistent ID from filename and match to Track object
			$file = basename($file);
			my ($pid) = $file =~ /^([^.]+)/;
		
			my $track = Slim::Schema->rs('Track')->single( { extid => $pid } );
		
			if ( $track ) {			
				if ( !$track->coverArtExists ) {
					$isDebug && $log->debug( "Updating artwork for " . $track->album->title );
				
					$track->cover( catfile( $cachedir, $file ) );
					$track->coverid(undef); # will be reset by next call to coverid
					$track->update;
				
					my $album = $track->album;
					$album->artwork( $track->coverid );
					$album->update;
				}
				else {
					$isDebug && $log->debug( "Album " . $track->album->title . " already has artwork" );
				}
			}
			else {
				$isDebug && $log->debug( "Track not found for persistent ID $pid" );
			}
		}
	}
	
	# Performed on every rescan, for any album in SC with no artwork,
	# check iTunes for downloaded or manually added artwork
	
	# Find all albums that came from iTunes and do not have artwork
	# Since iTunes stores artwork at the track level, we need to check every
	# track for artwork
	my $rs = Slim::Schema->rs('Track')->search( {
		'me.extid'      => { '!=' => undef },
		'album.artwork' => { '=' => undef },
	},
	{
		join => 'album',
	} );
	
	my $progress;
	
	if ( my $count = $rs->count ) {
		$progress = Slim::Utils::Progress->new( { 
			type  => 'importer', 
			name  => 'itunes_artwork_phase_2', 
			total => $count,
			bar   => 1,
		} );
		
		while ( my $track = $rs->next ) {
			# If this album got artwork from another track on this album, skip
			next if $track->album->artwork;
			
			if ( my $file = $class->exportSingleArtwork( $cachedir, $track ) ) {
				$isDebug && $log->debug( "Updating artwork for " . $track->album->title );
				
				$track->cover( catfile( $cachedir, $file ) );
				$track->coverid(undef); # will be reset by next call to coverid
				$track->update;
				
				my $album = $track->album;
				$album->artwork( $track->coverid );
				$album->update;
			}
			else {
				$isDebug && $log->debug( "Artwork not found for album " . $track->album->title );
			}
			
			$progress->update;
		}
		
		$progress->final;
	}
	
	$class->finishArtworkExport($cachedir);
	
	Slim::Music::Import->endImporter($class);
}

1;