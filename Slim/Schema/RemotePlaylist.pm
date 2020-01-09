package Slim::Schema::RemotePlaylist;


# This is an emulation of the Slim::Schema::Playlist API for remote tracks

use strict;

use base qw(Slim::Schema::RemoteTrack);

use Scalar::Util qw(blessed);

use Slim::Utils::Log;

my $log = logger('formats.metadata');

{
	__PACKAGE__->mk_accessor('rw', 'tracksRef');
}

sub setTracks {
	my ($self, $tracksRef) = @_;
	
	my @tracks = @$tracksRef;	# copy
	
	main::DEBUGLOG && $log->is_debug && $log->debug(join "\n", map ($_->url, @tracks));
	
	$self->tracksRef(\@tracks);
}

sub appendTracks {
	my ($self, $tracksRef) = @_;
	
	push @{$self->tracksRef()}, @$tracksRef;
}

sub tracks {
	my $self = shift;
	my $tracksRef = $self->tracksRef();
	
	return ($tracksRef ? @$tracksRef : ());
}

# Return the next audio URL from a remote playlist
sub getNextEntry {
	my ( $self, $args ) = @_;
	
	my $playlist = $args->{playlist} || $self;
	
	# Bug 16052: protect against empty apparent playlists
	if (!$playlist->can('tracks')) {
		return;
	}
	
	for my $track ( $playlist->tracks ) {
		my $type = $track->content_type;
		
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug( "Considering " . $track->url . " (type: $type)" );
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
			
			# Remote playlists cannot contain nested local playlist so do not need to do a schema lookup here
			
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