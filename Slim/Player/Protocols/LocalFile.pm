package Slim::Player::Protocols::LocalFile;

# Subclass of file: protocol handler to allow Squeezelite local players to open the file from disk directly
# When Squeezelite is directly connected it will advertise 'loc' as a format indicating local playback is possible

use strict;

use Slim::Utils::Log;
use base qw(Slim::Player::Protocols::File);

sub canDirectStreamSong {
	my ($class, $client, $song) = @_;

	# local player only for players supporting 'loc' and non sync, non seek case, non virtual track (from CUE sheet)
	if ($client->can('myFormats') && $client->myFormats->[-1] eq 'loc' && 
			!$client->isSynced && !$song->seekdata && !$song->track->virtual) {
		return "file://127.0.0.1:3483/" . $song->track->url;
	}

	# fall through to normal server based playback
	return 0;
}

sub requestString {
	# not implemented in the base class as method is not normally called for file, so no need to fall through
	my ($class, $client, $url, undef, $seekdata) = @_;

	$url =~ s{^file://127\.0\.0\.1:3483/}{};

	my $filepath = Slim::Utils::Misc::pathFromFileURL($url);

	return $filepath;
}

1;
