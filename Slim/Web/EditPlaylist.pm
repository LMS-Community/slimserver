package Slim::Web::EditPlaylist;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Formats::Parse;
use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Web::HTTP;

# -------------------------------------------------------------
# The default playlist name is: Radio Station.pls
# Can be overwritten by adding ?dir=<playlistname.pls> to the calling URL
# -------------------------------------------------------------
sub editplaylist {
	my ($client, $params) = @_;

	my $dir = defined( $params->{'dir'}) ? $params->{'dir'} : "Radio Station.pls";
	my $ds  = Slim::Music::Info::getCurrentDataStore();

	my $fulldir = Slim::Utils::Misc::virtualToAbsolute($dir);
	my $dirObj  = $ds->objectForUrl($fulldir) || do {

		$::d_playlist && Slim::Utils::Misc::msg("Couldn't find a directory entry for: [$fulldir]\n");

		return Slim::Web::HTTP::filltemplatefile("edit_playlist.html", $params);
	};

	my $filehandle = FileHandle->new(Slim::Utils::Misc::pathFromFileURL($fulldir), "r");

	my $count = 0;
	my $playlist;
	my $changed = 1;

	$params->{'dir'} = $dir;

	$::d_http && msg( "browse virtual path: " . $dir . "\n");
	$::d_http && msg( "with absolute path: " . $fulldir . "\n");

	my @items = Slim::Formats::Parse::parseList($dir, $filehandle);

	$filehandle->close if defined($filehandle);
	
	# Edit function - fill the to fields in the form
	if (defined($params->{'edit'})) {

		my $value = $params->{'edit'};
		my $track = $ds->objectForUrl($items[$value]);
		
		$params->{'form_url'}   = $items[$value];
		$params->{'form_title'} = $track->title();

	} elsif (defined($params->{'delete'})) {

		# Delete function - Remove entry from list
		my $value = $params->{'delete'};

		splice(@items, $value, 1);

		$changed = 1;

	} elsif (defined($params->{'form_title'})) {

		# Add function - Add entry it not already in list
		my $found = 0;
		my $title = $params->{'form_title'};
		my $newitem = $params->{'form_url'};

		if ($title && $newitem) {

			Slim::Music::Info::setTitle($newitem, $title);
			for my $item (@items) {

				if ($item eq $newitem) {
					$found = 1;
					last;
				}
				::idleStreams();
			}

			if ($found == 0) {
				push( @items, $newitem);
			}

			$changed = 1;
		}

	} elsif (defined($params->{'up'})) {

		# Up function - Move entry up in list
		my $value = $params->{'up'};

		if ($value != 0) {

			my $item = $items[$value];
			$items[$value] = $items[$value - 1];
			$items[$value - 1] = $item;

			$changed = 1;
		}

	} elsif (defined($params->{'down'})) {

		# Down function - Move entry down in list
		my $value = $params->{'down'};

		if ($value != scalar(@items) - 1) {

			my $item = $items[$value];
			$items[$value] = $items[$value + 1];
			$items[$value + 1] = $item;
			$changed = 1;			
		}
	}

	if ($changed) {
		Slim::Formats::Parse::writeList(\@items, undef, $fulldir);
	}
	
	my %list_form = %$params;

	for my $item (@items) {

		$::d_playlist && Slim::Utils::Misc::msg("Adding item: [$item] to playlist edit.\n");

		my $track = $ds->objectForUrl($item) || next;
		my $title = $track->title();

		$list_form{'num'}   = $count++;
		$list_form{'odd'}   = $count % 2;
		$list_form{'dir'}   = $dir;
		$list_form{'title'} = $title;
		$list_form{'itempath'} = $item;

		$playlist .= ${Slim::Web::HTTP::filltemplatefile("edit_playlist_list.html", \%list_form)};

		::idleStreams();
	}

	$params->{'playlist'}     = $playlist;
	$params->{'playlistname'} = $dirObj->title();

	return Slim::Web::HTTP::filltemplatefile("edit_playlist.html", $params);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
