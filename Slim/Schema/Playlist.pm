package Slim::Schema::Playlist;

# $Id$

use strict;
use base 'Slim::Schema::Track';

use Scalar::Util qw(blessed);
use Slim::Utils::Log;

{
	my $class = __PACKAGE__;

	# Magic to create a ResultSource for this inherited class.
	$class->table($class->table);

	$class->resultset_class('Slim::Schema::ResultSet::Playlist');

	$class->has_many('playlist_tracks' => 'Slim::Schema::PlaylistTrack' => 'playlist');
}

sub tracks {
	my $self = shift;

	return $self->playlist_tracks(undef, { 'order_by' => 'me.position' })->search_related('track' => @_);
}

sub setTracks {
	my $self   = shift;
	my $tracks = shift;

	# With playlists in the database - we want to make sure the playlist is consistent to the user.
	my $autoCommit = Slim::Schema->storage->dbh->{'AutoCommit'};

	if ($autoCommit) {
		Slim::Schema->storage->dbh->{'AutoCommit'} = 0;
	}

	eval {
		Slim::Schema->txn_do(sub {

			# Remove the old tracks associated with this playlist.
			$self->playlist_tracks->delete;

			$self->_addTracksToPlaylist($tracks, 0);
		});
	};

	if ($@) {
		logError("Failed to add tracks to playlist: [$@]");
	}

	Slim::Schema->storage->dbh->{'AutoCommit'} = $autoCommit;
}

sub appendTracks {
	my $self   = shift;
	my $tracks = shift;

	my $autoCommit = Slim::Schema->storage->dbh->{'AutoCommit'};

	if ($autoCommit) {
		Slim::Schema->storage->dbh->{'AutoCommit'} = 0;
	}

	eval {
		Slim::Schema->txn_do(sub {

			# Get the current max track in the DB
			my $max = $self->search_related('playlist_tracks', undef, {

				'select' => [ \'MAX(position)' ],
				'as'     => [ 'maxPosition' ],

			})->single->get_column('maxPosition');

			$self->_addTracksToPlaylist($tracks, $max+1);
		});
	};

	if ($@) {
		logError("Failed to add tracks to playlist: [$@]");
	}

	Slim::Schema->storage->dbh->{'AutoCommit'} = $autoCommit;
}

sub _addTracksToPlaylist {
	my ($self, $tracks, $position) = @_;

	if (!$tracks || ref($tracks) ne 'ARRAY' || !scalar @$tracks) {
		$tracks = [];
	}

	for my $track (@$tracks) {

		# If tracks are being added via Browse Music Folder -
		# which still deals with URLs - get the objects to add.
		if (!blessed($track) || !$track->can('id')) {

			$track = Slim::Schema->rs('Track')->objectForUrl({
				'url'      => $track,
				'create'   => 1,
				'readTags' => 1,
			});
		}

		if (blessed($track) && $track->can('id')) {

			Slim::Schema->rs('PlaylistTrack')->create({
				playlist => $self,
				track    => $track,
				position => $position++
			});
		}

		# updating playlist can take several seconds - maintain streaming 
		main::idleStreams();
	}
}

# Return the next audio URL from a remote playlist
sub getNextEntry {
	my ( $self, $args ) = @_;
	
	my $log = logger('player.source');
	
	my $playlist = $args->{playlist} || $self;
	
	for my $track ( $playlist->tracks ) {
		my $type = $track->content_type;
		
		if ( Slim::Music::Info::isSong( $track, $type ) ) {
			# An audio URL
			if ( $args->{after} ) {
				if ( $args->{after}->url eq $track->url ) {
					# We are looking for the track after this one
					$log->debug( "Skipping " . $track->url . " we want the one after" );
					delete $args->{after};
				}
				else {
					$log->debug( "Skipping" . $track->url . ", haven't seen " . $args->{after}->url . " yet" );
				}
			}
			else {
				$log->debug( "Next playlist entry is " . $track->url );
				return $track;
			}
		}
		elsif ( Slim::Music::Info::isPlaylist( $track, $type ) ) {
			# A nested playlist, recurse into it
			$log->debug( 'Looking in nested playlist ' . $track->url );
			
			$track = Slim::Schema->rs('Playlist')->objectForUrl( {
				url => $track->url,
			} );
			
			if ( my $result = $self->getNextEntry( { %{$args}, playlist => $track } ) ) {
				$log->debug( 'Found audio URL in nested playlist: ' . $result->url );
				
				if ( $args->{after} ) {
					if ( $args->{after}->url eq $result->url ) {
						# We are looking for the track after this one
						$log->debug( "Skipping " . $result->url . " we want the one after" );
						delete $args->{after};
					}
					else {
						$log->debug( "Skipping" . $result->url . ", haven't seen " . $args->{after}->url . " yet" );
					}
				}
				else {
					$log->debug( "Next playlist entry is " . $result->url );
					return $result;
				}
			}
		}
	}
	
	# No audio URLs found
	return;
}

1;

__END__
