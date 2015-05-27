package Slim::Schema::Playlist;

# $Id$

use strict;
use base 'Slim::Schema::Track';

use Slim::Schema::ResultSet::Playlist;

use Scalar::Util qw(blessed);
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

{
	my $class = __PACKAGE__;

	# Magic to create a ResultSource for this inherited class.
	$class->table($class->table);

	$class->resultset_class('Slim::Schema::ResultSet::Playlist');

	$class->has_many('playlist_tracks' => 'Slim::Schema::PlaylistTrack' => 'playlist');
}

sub tracks {
	my $self = shift;
	my $library_id = shift;
	
	return Slim::Schema->rs('PlaylistTrack')->getTracks($self->id, $library_id);
}

sub setTracks {
	my $self   = shift;
	my $tracks = shift;

	# Do not turn change autocommit.

	my $work = sub {
		# Remove the old tracks associated with this playlist.
		$self->playlist_tracks->delete;
		$self->_addTracksToPlaylist($tracks, 0);
	};
	
	# Bug 12091: Only use a txn_do() if autocommit is on
	eval {
		if (Slim::Schema->dbh->{'AutoCommit'}) {
			Slim::Schema->txn_do($work);
		} else {
			&$work;
		}
	};

	if ($@) {
		logError("Failed to add tracks to playlist: [$@]");
	}

}

sub appendTracks {
	my $self   = shift;
	my $tracks = shift;

	# Do not turn change autocommit.

	my $work = sub {

		# Get the current max track in the DB
		
		# Bug 13185, I don't think we can do this with DBIC due to inflate_result
		my $max = 0;
		
		my $dbh = Slim::Schema->dbh;
		my $sth = $dbh->prepare_cached( qq{
			SELECT MAX(position) FROM playlist_track WHERE playlist = ? LIMIT 1
		} );
		$sth->execute( $self->id );
		if ( my ($pos) = $sth->fetchrow_array ) {
			$max = $pos;
		}
		$sth->finish;

		$self->_addTracksToPlaylist($tracks, $max+1);
	};
	
	# Bug 12091: Only use a txn_do() if autocommit is on
	eval {
		if (Slim::Schema->dbh->{'AutoCommit'}) {
			Slim::Schema->txn_do($work);
		} else {
			&$work;
		}
	};

	if ($@) {
		logError("Failed to add tracks to playlist: [$@]");
	}

}

sub _addTracksToPlaylist {
	my ($self, $tracks, $position) = @_;

	if (!$tracks || ref($tracks) ne 'ARRAY' || !scalar @$tracks) {
		$tracks = [];
	}

	for my $track (@$tracks) {

		# If tracks are being added via Browse Music Folder -
		# which still deals with URLs - get the objects to add.
		if (!blessed($track) || !$track->can('url')) {

			$track = Slim::Schema->objectForUrl({
				'url'      => $track,
				'create'   => 1,
				'readTags' => 1,
			});
		}

		if (blessed($track) && $track->can('url')) {

			Slim::Schema->rs('PlaylistTrack')->create({
				playlist => $self,
				track    => $track->url,
				position => $position++
			});
		}

		# updating playlist can take several seconds - maintain streaming 
		main::idleStreams();
	}
}

# Return the next audio URL from a remote playlist
# XXX probably obsolete, see RemotePlaylist
sub getNextEntry {
	my ( $self, $args ) = @_;
	
	my $log = logger('player.source');
	
	my $playlist = $args->{playlist} || $self;
	
	for my $track ( $playlist->tracks ) {
		my $type = $track->content_type;
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Considering " . $track->url . " ($type)" );
		}
		
		if ( Slim::Music::Info::isSong( $track, $type ) ) {
			# An audio URL
			if ( $args->{after} ) {
				if ( $args->{after}->url eq $track->url ) {
					# We are looking for the track after this one
					main::DEBUGLOG && $log->debug( "Skipping " . $track->url . ", we want the one after" );
					delete $args->{after};
				}
				else {
					main::DEBUGLOG && $log->debug( "Skipping" . $track->url . ", haven't seen " . $args->{after}->url . " yet" );
				}
			}
			else {
				main::DEBUGLOG && $log->debug( "Next playlist entry is " . $track->url );
				return $track;
			}
		}
		elsif ( Slim::Music::Info::isPlaylist( $track, $type ) ) {
			# A nested playlist, recurse into it
			main::DEBUGLOG && $log->debug( 'Looking in nested playlist ' . $track->url );
			
			$track = Slim::Schema->objectForUrl( {
				url => $track->url,
				playlist => 1,
			} ) unless $track->isRemoteURL();
			
			if ( my $result = $self->getNextEntry( { %{$args}, playlist => $track } ) ) {
				main::DEBUGLOG && $log->debug( 'Found audio URL in nested playlist: ' . $result->url );
				return $result;
			}
		}
	}
	
	# No audio URLs found
	return;
}

1;

__END__
