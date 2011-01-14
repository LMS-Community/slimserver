package Slim::Utils::Scanner::API;

# $Id$

use strict;

use Slim::Utils::Log ();

### Public interface

=head1 SYNOPSIS

	use Slim::Utils::Scanner::API;
	
	Slim::Utils::Scanner::API->onNewTrack( {
		want_object => 1,
		cb => sub {
			my ( $track, $url ) = @_;
			
			print "New track scanned: " . $track->title . "\n";
		},
	} );

=head1 METHODS

=head2 Slim::Utils::Scanner::API->onNewTrack( { want_object => 0, cb => $cb } )

Register a handler that will be called when a new track is scanned.

By default, the callback is passed a track ID and a URL. If want_object is set to 1,
the callback will be passed a L<Slim::Schema::Track> object instead of an ID. Note that
Track objects should be avoided when possible to avoid slowing down the scanner.

Multiple handlers may be registered, and they are called in the order they were registered.

=cut

my @onNewTrack;
my @onDeletedTrack;
my @onChangedTrack;
my @onNewPlaylist;
my @onDeletedPlaylist;

sub onNewTrack {
	my ( $class, $opts ) = @_;
	
	push @onNewTrack, $opts;
}

=head2 Slim::Utils::Scanner::API->onDeletedTrack( \%options )

Register a handler that will be called right before a track is deleted.

See onNewTrack for options information.

=cut

sub onDeletedTrack {
	my ( $class, $opts ) = @_;
	
	push @onDeletedTrack, $opts;
}

=head2 Slim::Utils::Scanner::API->onChangedTrack( \%options )

Register a handler that will be called when a track has changed.

See onNewTrack for options information.

=cut

sub onChangedTrack {
	my ( $class, $opts ) = @_;
	
	push @onChangedTrack, $opts;
}

=head2 Slim::Utils::Scanner::API->onNewPlaylist( \%options )

Register a handler that will be called when a new playlist is scanned. Note that
onNewTrack (if set) will have been called for all tracks in the playlist prior to
this handler being called.

By default, the callback is passed a playlist ID. If want_object is set to 1,
the callback will be passed a L<Slim::Schema::Playlist> object instead. Note that
Playlist objects should be avoided when possible to avoid slowing down the scanner.

=cut

sub onNewPlaylist {
	my ( $class, $opts ) = @_;
	
	push @onNewPlaylist, $opts;
}

=head2 Slim::Utils::Scanner::API->onDeletedPlaylist( \%options )

Register a handler that will be called right before a playlist is deleted.

See onNewPlaylist for options information.

NOTE: There is no onChangedPlaylist because the scanner simply deletes the playlist,
and then adds it back as a new playlist.

=cut

sub onDeletedPlaylist {
	my ( $class, $opts ) = @_;
	
	push @onDeletedPlaylist, $opts;
}

### Internal interface

sub _makeDispatcher {
	my ( $handlers, $objectClass, $type ) = @_;
	
	return 0 unless scalar @{$handlers};
	
	return sub {
		my $opts = shift; # { id, url, obj (sometimes) }
		
		for my $h ( @{$handlers} ) {
			my $arg1 = $opts->{id};
						
			if ( $h->{want_object} ) {
				$arg1 = $opts->{obj} || Slim::Schema->rs($objectClass)->find($arg1);
			}
			
			eval { $h->{cb}->( $arg1, $opts->{url} ) };
			if ( $@ ) {
				require Slim::Utils::PerlRunTime;
				my $method = Slim::Utils::PerlRunTime::realNameForCodeRef( $h->{cb} );
				Slim::Utils::Log::logError("Error in $type handler for ID " . $opts->{id} . " ($method): $@");
			}
		}
	};
}

sub getHandlers {	
	return {
		onNewTrackHandler        => _makeDispatcher( \@onNewTrack, 'Track', 'onNewTrack' ),
		onDeletedTrackHandler    => _makeDispatcher( \@onDeletedTrack, 'Track', 'onDeletedTrack' ),
		onChangedTrackHandler    => _makeDispatcher( \@onChangedTrack, 'Track', 'onChangedTrack' ),
		onNewPlaylistHandler     => _makeDispatcher( \@onNewPlaylist, 'Playlist', 'onNewPlaylist' ),
		onDeletedPlaylistHandler => _makeDispatcher( \@onDeletedPlaylist, 'Playlist', 'onDeletedPlaylist' ),
	};
}

1;
