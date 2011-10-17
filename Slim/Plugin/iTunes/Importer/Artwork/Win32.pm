package Slim::Plugin::iTunes::Importer::Artwork::Win32;

use strict;
use base 'Slim::Plugin::iTunes::Importer::Artwork';

use Win32::OLE;
use Win32::Process::List;

use File::Spec::Functions qw(:ALL);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Versions;

my $log   = logger('plugin.itunes');
my $prefs = preferences('plugin.itunes');

my $itunes;
my $wasRunning;

sub initArtworkExport {
	my $p = Win32::Process::List->new;
	my %processes = $p->GetProcesses();
	$wasRunning = grep { lc($processes{$_}) eq 'itunes.exe' } keys %processes;

	$itunes = Win32::OLE->GetActiveObject('iTunes.Application') || Win32::OLE->new('iTunes.Application');
}

sub supportsArtworkExport {
	return 0 unless $itunes;

	my $version = $itunes->Version;
	
	if ( Slim::Utils::Versions->compareVersions($version, '7.7') >= 0 ) {
		# 7.7+ required for persistent ID support
		return 1;
	}

	$log->error("iTunes version is too old for artwork export (you have $version, need 7.7 or higher)");
	
	return 0;
}

sub exportDownloadedArtwork {
	my ( $class, $cachedir ) = @_;
	
	my $isDebug = $log->is_debug;
	
	my $skipUnchecked = !$prefs->get('ignore_disabled') ? 1 : 0;
	
	my %seenAlbums = ();
	
	my $library = $itunes->LibraryPlaylist;
	my $tracks  = $library->Tracks;
	my $count   = $tracks->Count;
	
	my $progress = Slim::Utils::Progress->new( { 
		type  => 'importer', 
		name  => 'itunes_artwork_phase_1', 
		total => $count,
		bar   => 1,
	} );
	
	for ( my $i = 1; $i <= $count; $i++ ) {
		$progress->update;
		
		my $track = $tracks->Item($i);
		
		# Skip unchecked?
		if ( $skipUnchecked && !$track->Enabled ) {
			next;
		}
		
		my $key = $track->Artist . $track->Album;
		
		if ( !$seenAlbums{$key} ) {		
			if ( my $artworks = $track->Artwork ) {
				if ( $artworks->Count > 0 ) {
					my $artwork = $artworks->Item(1);
					if ( $artwork->isDownloadedArtwork ) {
						my $format = $artwork->Format;
						if ( $format >= 1 && $format <= 3 ) { # jpg, png, bmp
							my $ext      = (undef, 'jpg', 'png', 'bmp')[ $format ];
							my $pid      = _getPersistentId( $track );
							my $filename = catfile( $cachedir, $pid . '.' . $ext );
					
							$artwork->SaveArtworkToFile($filename);
					
							$seenAlbums{$key} = 1;
						
							$isDebug && $log->debug( "Exporting downloaded artwork for ID $pid: " . $track->Album );
						}
					}
				}
			}
		}
	}
	
	$progress->final;
}

sub exportSingleArtwork {
	my ( $class, $cachedir, $track ) = @_;
	
	my $search = $track->title;
	my $pid    = $track->extid;
	
	my $library = $itunes->LibraryPlaylist;

	if ( my $tracks = $library->Search( $search, 1 ) ) {
		for ( my $i = 1; $i <= $tracks->Count; $i++ ) {
			my $track = $tracks->Item($i);
			my $tpid  = _getPersistentId($track);
			
			if ( $tpid eq $pid ) {
				if ( my $artworks = $track->Artwork ) {
					if ( $artworks->Count > 0 ) {
						my $artwork = $artworks->Item(1);
						my $format  = $artwork->Format;
						if ( $format >= 1 && $format <= 3 ) { # jpg, png, bmp
							my $ext      = (undef, 'jpg', 'png', 'bmp')[ $format ];
							my $filename = catfile( $cachedir, $pid . '.' . $ext );
					
							$artwork->SaveArtworkToFile($filename);
						
							main::DEBUGLOG && $log->is_debug && $log->debug( "Exporting single artwork for ID $pid: " . $track->Album );
							
							return $filename;
						}
					}
				}
				
				last;
			}
		}
	}
	
	return;
}

sub finishArtworkExport {
	my ( $class, $cachedir ) = @_;
	
	$itunes->Quit unless $wasRunning;
	$itunes = undef;
}

sub _getPersistentId {
	my $track = shift;
	
	my $pidh = $itunes->ITObjectPersistentIDHigh($track);
	my $pidl = $itunes->ITObjectPersistentIDLow($track);
	
	$pidh = unpack( 'H*', pack( 'N', $pidh ) );
	$pidl = unpack( 'H*', pack( 'N', $pidl ) );
	
	return uc( $pidh . $pidl );
}

1;
