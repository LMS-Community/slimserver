package Slim::Web::EditPlaylist;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Slim::Utils::Misc;

# -------------------------------------------------------------
# The default playlist name is: Radio Station.pls
# Can be overwritten by adding ?dir=<playlistname.pls> to the calling URL
# -------------------------------------------------------------
sub editplaylist {

	my ($client, $params) = @_;

	my $dir = defined( $params->{'dir'}) ? $params->{'dir'} : "Radio Station.pls";

	my $fulldir = Slim::Utils::Misc::virtualToAbsolute( $dir);

	my $filehandle = FileHandle->new($fulldir, "r");

	my $count = 0;
	my $playlist;

	$params->{'dir'} = $dir;

	$::d_http && msg( "browse virtual path: " . $dir . "\n");
	$::d_http && msg( "with absolute path: " . $fulldir . "\n");

	# Edit function - fill the to fields in the form
	if (defined($params->{'edit'})) {

		my $value = $params->{'edit'};
		my @items = Slim::Formats::Parse::PLS($filehandle);

		$params->{'form_url'}   = $items[$value];
		$params->{'form_title'} = Slim::Music::Info::title($items[$value]);

	} elsif (defined($params->{'delete'})) {

		# Delete function - Remove entry from list
		my $value = $params->{'delete'};
		my @items = Slim::Formats::Parse::PLS( $filehandle);

		splice(@items, $value, 1);

		Slim::Formats::Parse::writePLS(\@items, undef, $fulldir);

	} elsif (defined($params->{'form_title'})) {

		# Add function - Add entry it not already in list
		my $found = 0;
		my $title = $params->{'form_title'};
		my $newitem = $params->{'form_url'};

		if (($title ne "") && ($newitem ne "")) {

			my @items = Slim::Formats::Parse::PLS( $filehandle);

			Slim::Music::Info::setTitle( $newitem, $title);
			foreach my $item (@items) {

				if ($item eq $newitem) {
					$found = 1;
					last;
				}
				::idleStreams();
			}

			if ($found == 0) {
				push( @items, $newitem);
			}

			Slim::Formats::Parse::writePLS(\@items, undef, $fulldir);
		}

	} elsif (defined($params->{'up'})) {

		# Up function - Move entry up in list
		my $value = $params->{'up'};

		if ($value != 0) {

			my @items = Slim::Formats::Parse::PLS($filehandle);

			my $item = $items[$value];
			$items[$value] = $items[$value - 1];
			$items[$value - 1] = $item;

			Slim::Formats::Parse::writePLS(\@items, undef, $fulldir);
		}

	} elsif (defined($params->{'down'})) {

		# Down function - Move entry down in list
		my $value = $params->{'down'};
		my @items = Slim::Formats::Parse::PLS($filehandle);

		if ($value != scalar(@items) - 1) {

			my $item = $items[$value];
			$items[$value] = $items[$value + 1];
			$items[$value + 1] = $item;

			Slim::Formats::Parse::writePLS(\@items, undef, $fulldir);
		}
	}

	# close and reopen.
	$filehandle->close if defined($filehandle);

	$filehandle = FileHandle->new($fulldir, "r") || do {

		# Create new file if it cannot be opened
		$filehandle = FileHandle->new($fulldir, "w+");
	};

	my @items = Slim::Formats::Parse::PLS($filehandle);

	$filehandle->close();

	my %list_form = %$params;

	foreach my $item (@items) {

		my $title = Slim::Music::Info::title( $item);

		$list_form{'num'}   = $count++;
		$list_form{'odd'}   = $count % 2;
		$list_form{'dir'}   = $dir;
		$list_form{'title'} = $title;

		$playlist .= ${Slim::Web::HTTP::filltemplatefile( "edit_playlist_list.html", \%list_form)};

		::idleStreams();
	}

	$params->{'playlist'} = $playlist;

	return Slim::Web::HTTP::filltemplatefile( "edit_playlist.html", $params);
}

1;
