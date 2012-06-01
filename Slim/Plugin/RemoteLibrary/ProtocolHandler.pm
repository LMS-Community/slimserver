package Slim::Plugin::RemoteLibrary::ProtocolHandler;

# $Id$

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use IO::Socket qw(:crlf);

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string cstring);

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.remotelibrary',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_REMOTE_LIBRARY_MODULE_NAME',
} );

sub canSeek { 1 }

sub isRemote { 0 }	# There may be a couple of cases with transcoding where this would be a problem
					# but looks ok. Setting isRemote == 0 endures that streaming does not pause
					# for these types of stream

# Source for AudioScrobbler
sub audioScrobblerSource {
	# P = Chosen by the user
	return 'P';
}

# Suppress some messages during initial connection
sub suppressPlayersMessage {
	my ( $class, $client, $song, $string ) = @_;
	
	# Should be local => should not need these
	if ( $string eq 'GETTING_STREAM_INFO' || $string eq 'CONNECTING_FOR' || $string eq 'BUFFERING' ) {
		return 1;
	}
	
	return;
}

# Avoid scanning
sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{cb}->($args->{song}->currentTrack());
}

sub getNextTrack {
	my ( $class, $song, $successCb, $errorCb ) = @_;
	
	$successCb->();
}

sub usePlayerProxyStreaming { 0 }	# 0 => do not use player-supplier proxy streaming

sub getSeekData {
	my ( $class, $client, $song, $newtime ) = @_;
	
	main::INFOLOG && $log->info( "Trying to seek $newtime seconds" );
	
	return {
		timeOffset           => $newtime,
	};
}

sub getStreamRequestParams() {
	my ($class, $client, $url, $seekdata) = @_;
	
	my ($uuid, $path) = ($url =~ m%(?-:lms)://([^/]+)(/.*)%);
	
	return undef unless $uuid and $path;
	
	my $request = join($CRLF, (
		"GET $path HTTP/1.0",
		"Accept: */*",
		"Cache-Control: no-cache",
		"Connection: close",
		"X-LMS-Server: $uuid",
	));

	if ($seekdata && $seekdata->{'timeOffset'}) {
		my $seek = 'TimeSeekRange.dlna.org: npt=' . $seekdata->{'timeOffset'} . '-';
		$request .= $CRLF . $seek;
		
		# Fix progress bar
		$client->playingSong()->startOffset($seekdata->{timeOffset});
		$client->master()->remoteStreamStartTime( Time::HiRes::time() - $seekdata->{timeOffset} );
	}
	
	$request .= $CRLF . $CRLF;
	
	main::INFOLOG && $log->info($request);
	
	return (undef, 80, $request);
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	foreach ($client->syncGroupActiveMembers()) {
		return undef if !$_->lmsUrls();
	}

	return $song->streamUrl();
}

sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;
	
	my $track = Slim::Schema->objectForUrl($url);
	
	return {
		artist      => $track->artistname,
		album       => $track->albumname,
		cover       => $track->coverurl,
		duration    => $track->secs,
		replay_gain => $track->replay_gain,
		type        => cstring($client, uc($track->content_type)),
		title       => $track->name,
	};
}

# SN only, re-init upon reconnection
sub reinit {
	my ( $class, $client, $song ) = @_;
	
	# Reset song duration/progress bar
	my $currentURL = $song->streamUrl();
	
	main::DEBUGLOG && $log->debug("Re-init RemoteLibrary - $currentURL");
	
	return 1;
}

1;
