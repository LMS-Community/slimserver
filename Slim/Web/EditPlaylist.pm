package Slim::Web::EditPlaylist;

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Slim::Utils::Misc;

# -------------------------------------------------------------
# The default playlist name is: Radio Station.pls
# Can be overwritten by adding ?dir=<playlistname.pls> to the calling URL
# -------------------------------------------------------------
sub editplaylist
{
	my( $client, $main_form_ref) = @_;

	my $dir = defined( $$main_form_ref{'dir'}) ? $$main_form_ref{'dir'} : "Radio Station.pls";
	my $fulldir = Slim::Utils::Misc::virtualToAbsolute( $dir);
	my $filehandle;
	my $count = 0;
	my $item;
	my @items;
	my %list_form;
	my $playlist;
	my $output = "";

	$$main_form_ref{'dir'} = $dir;

	$::d_http && msg( "browse virtual path: " . $dir . "\n");
	$::d_http && msg( "with absolute path: " . $fulldir . "\n");

	# Edit function - fill the to fields in the form
	if( defined( $$main_form_ref{'edit'}))
	{
		my $value = $$main_form_ref{'edit'};

		$filehandle = new FileHandle( $fulldir, "r");
		@items = Slim::Formats::Parse::PLS( $filehandle);
		close $filehandle;

		$$main_form_ref{'form_url'} = $items[$value];
		$$main_form_ref{'form_title'} = Slim::Music::Info::title( $items[$value]);
	}
	# Delete function - Remove entry from list
	elsif( defined( $$main_form_ref{'delete'}))
	{
		my $value = $$main_form_ref{'delete'};

		$filehandle = new FileHandle( $fulldir, "r");
		@items = Slim::Formats::Parse::PLS( $filehandle);
		close $filehandle;

		splice( @items, $value, 1);
		Slim::Formats::Parse::writePLS( \@items, undef, $fulldir);
	}
	# Add function - Add entry it not already in list
	elsif( defined( $$main_form_ref{'form_title'}))
	{
		my $found = 0;
		my $title = $$main_form_ref{'form_title'};
		my $newitem = $$main_form_ref{'form_url'};

		if( ( $title ne "") && ( $newitem ne ""))
		{
			$filehandle = new FileHandle( $fulldir, "r");
			@items = Slim::Formats::Parse::PLS( $filehandle);
			close $filehandle;

			Slim::Music::Info::setTitle( $newitem, $title);
			foreach $item (@items)
			{
				if( $item eq $newitem)
				{
					$found = 1;
					last;
				}
				::idleStreams();
			}
			if( $found == 0)
			{
				push( @items, $newitem);
			}
			Slim::Formats::Parse::writePLS( \@items, undef, $fulldir);
		}
	}
	# Up function - Move entry up in list
	elsif( defined( $$main_form_ref{'up'}))
	{
		my $value = $$main_form_ref{'up'};

		if( $value != 0)
		{
			$filehandle = new FileHandle( $fulldir, "r");
			@items = Slim::Formats::Parse::PLS( $filehandle);
			close $filehandle;

			$item = $items[$value];
			$items[$value] = $items[$value - 1];
			$items[$value - 1] = $item;

			Slim::Formats::Parse::writePLS( \@items, undef, $fulldir);
		}
	}
	# Down function - Move entry down in list
	elsif( defined( $$main_form_ref{'down'}))
	{
		my $value = $$main_form_ref{'down'};

		$filehandle = new FileHandle( $fulldir, "r");
		@items = Slim::Formats::Parse::PLS( $filehandle);
		close $filehandle;

		if( $value != scalar( @items) - 1)
		{
			$item = $items[$value];
			$items[$value] = $items[$value + 1];
			$items[$value + 1] = $item;

			Slim::Formats::Parse::writePLS( \@items, undef, $fulldir);
		}
	}

	$filehandle = new FileHandle( $fulldir, "r");
	# Create new file if it cannot be opened
	if( !defined( $filehandle))
	{
		$filehandle = new FileHandle( $fulldir, "w+");
	}
	@items = Slim::Formats::Parse::PLS( $filehandle);
	close $filehandle;

	foreach $item (@items)
	{
		my $title = Slim::Music::Info::title( $item);
		%list_form = ();
		$list_form{'num'} = $count++;
		$list_form{'odd'} = $count % 2;
		$list_form{'dir'} = $dir;
		$list_form{'title'} = $title;

		$playlist .= ${Slim::Web::HTTP::filltemplatefile( "edit_playlist_list.html", \%list_form)};

		::idleStreams();
	}

	$$main_form_ref{'playlist'} = $playlist;
	return Slim::Web::HTTP::filltemplatefile( "edit_playlist.html", $main_form_ref);
}

1;
	
