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
	
	Slim::Utils::Scanner::API->onFinished( {
		cb => sub {
			my $changeCount = shift;
			
			print "Scan finished, $changeCount changes made\n";
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
my @onNewImage;
my @onNewVideo;
my @onNewPlaylist;
my @onDeletedPlaylist;
my @onFinished;

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

=head2 Slim::Utils::Scanner::API->onNewImage( { cb => $cb } )

Register a handler that will be called when a new image is scanned.

The callback is passed an image hashref with all scan data. Note that images differ
from tracks, and there is no support for Slim::Schema objects for images. To alter the
data, call Slim::Schema::Image->updateOrCreateFromHash($hashref).

Multiple handlers may be registered, and they are called in the order they were registered.

=cut

sub onNewImage {
	my ( $class, $opts ) = @_;
	
	push @onNewImage, $opts;
}

=head2 Slim::Utils::Scanner::API->onNewVideo( { cb => $cb } )

Register a handler that will be called when a new video is scanned.

The callback is passed a video hashref with all scan data. Note that videos differ
from tracks, and there is no support for Slim::Schema objects for videos. To alter the
data, call Slim::Schema::Video->updateOrCreateFromHash($hashref).

Multiple handlers may be registered, and they are called in the order they were registered.

=cut

sub onNewVideo {
	my ( $class, $opts ) = @_;
	
	push @onNewVideo, $opts;
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

=head2 Slim::Utils::Scanner::API->onFinished( { cb => $cb } )

Register a handler that will be called when a scan has finished.

The callback function is passed the number of changes that were made.
This handler is called after new/changed/deleted handling, but before
the artwork precaching phase.

=cut

sub onFinished {
	my ( $class, $opts ) = @_;
	
	push @onFinished, $opts;
}

### Internal interface

sub _makeDispatcher {
	my ( $handlers, $objectClass, $type ) = @_;
	
	return 0 unless scalar @{$handlers};
	
	return sub {
		my $opts = shift; # { id, url, obj (sometimes) }
		
		for my $h ( @{$handlers} ) {
			if ( $opts->{id} ) { # Tracks, with object support
				my $arg1 = $opts->{id};
						
				if ( $h->{want_object} ) {
					$arg1 = $opts->{obj} ||= Slim::Schema->rs($objectClass)->find($arg1);
				}
			
				eval { $h->{cb}->( $arg1, $opts->{url} ) };
				if ( $@ ) {
					my $method = main::DEBUGLOG ? Slim::Utils::PerlRunTime::realNameForCodeRef( $h->{cb} ) : 'unk';
					Slim::Utils::Log::logError("Error in $type plugin handler for " . $opts->{url} . " ($method): $@");
				}
			}
			else { # Images/Videos
				eval { $h->{cb}->( $opts->{hashref} ) };
				if ( $@ ) {
					my $method = main::DEBUGLOG ? Slim::Utils::PerlRunTime::realNameForCodeRef( $h->{cb} ) : 'unk';
					Slim::Utils::Log::logError("Error in $type plugin handler for " . $opts->{hashref}->{url} . " ($method): $@");
				}
			}
		}
	};
}

sub _makeFinishedDispatcher {
	my $handlers = shift;
	
	return 0 unless scalar @{$handlers};
	
	return sub {
		my $count = shift;
		
		for my $h ( @{$handlers} ) {
			eval { $h->{cb}->($count) };
			if ( $@ ) {
				my $method = main::DEBUGLOG ? Slim::Utils::PerlRunTime::realNameForCodeRef( $h->{cb} ) : 'unk';
				Slim::Utils::Log::logError("Error in onFinished handler ($method): $@");
			}
		}
	};
}

sub getHandlers {	
	return {
		onNewTrackHandler        => _makeDispatcher( \@onNewTrack, 'Track', 'onNewTrack' ),
		onDeletedTrackHandler    => _makeDispatcher( \@onDeletedTrack, 'Track', 'onDeletedTrack' ),
		onChangedTrackHandler    => _makeDispatcher( \@onChangedTrack, 'Track', 'onChangedTrack' ),
		onNewImageHandler        => _makeDispatcher( \@onNewImage, undef, 'onNewImage' ),
		# onDeletedImageHandler
		# onChangedImageHandler
		onNewVideoHandler        => _makeDispatcher( \@onNewVideo, undef, 'onNewVideo' ),
		# onDeletedVideoHandler
		# onChangedVideoHandler
		onNewPlaylistHandler     => _makeDispatcher( \@onNewPlaylist, 'Playlist', 'onNewPlaylist' ),
		onDeletedPlaylistHandler => _makeDispatcher( \@onDeletedPlaylist, 'Playlist', 'onDeletedPlaylist' ),
		onFinishedHandler        => _makeFinishedDispatcher( \@onFinished ),
	};
}

1;
