package Slim::Web::History;

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use POSIX;
use Slim::Utils::Misc;

use Slim::Utils::Strings qw(string);

# a cache of songs played
my @history = ();

sub get_history {
	return @history;
}

# Clear can be used to clear the history cache.
sub clear {
	@history =();
	unlink(catfile(Slim::Utils::Prefs::get('playlistdir'),'__history.m3u'));
	undef;
};

# recount processes the history list by counting the number of times a song appears, and then
# sorting the list based on that number.  The sorted list is returned.  The returned list 
# will be a two dimensional array (N by 2).  Each element contains the song name, and the number
# of times it appeared in the history.
sub recount {
	my @outlist;
	my $listcount = 0;
	my $i=1;
	my $item;
	my $title;
	my $count;
	
	@outlist = ();
	
    if (scalar(@history)) {        
        
	    # Cycle through the history and count songs. 
        my %outhash;
	foreach $item (@history) {
		if (!exists($outhash{$item})) {
			$outhash{$item}[0] = $item;
			$outhash{$item}[2] = $listcount;
		}
		$outhash{$item}[1]++;
		$listcount++;
	}
        # Sort array by song count descending and (for ties) last played ascending
	@outlist = sort {$b->[1] <=> $a->[1] || $a->[2] <=> $b->[2]} values %outhash;
    	#return @outlist[sort {$outlist[$b][1] <=> $outlist[$a][1] || $outlist[$a][2] <=> $outlist[$b][2]} 0..$#outlist];
    }
    return @outlist;
};

#
#	load the track history from an M3U file
#	(don't worry if the file doesn't exist)
#
sub load {
    @history = ();
    return undef unless Slim::Utils::Prefs::get('savehistory');

    my $filename = catfile(Slim::Utils::Prefs::get('playlistdir'),'__history.m3u');

    open (FILE,$filename) or return undef;
    @history = Slim::Formats::Parse::M3U(
	\*FILE,
	Slim::Utils::Prefs::get('mp3dir'),
    );
    close FILE;
    undef;
}

# Record takes a song name and stores it at the first position of an array.  The max 
sub record {
    my $song = shift;
    return unless Slim::Utils::Prefs::get('historylength');
    # Add the newest song to the font of the list, so that the most recent song is at the top.
    unshift @history,$song;
    
    if (scalar(@history) > Slim::Utils::Prefs::get('historylength')) { pop @history; }
    if (Slim::Utils::Prefs::get('savehistory') && Slim::Utils::Prefs::get('playlistdir')) {
	Slim::Formats::Parse::writeM3U(
	    \@history,
	    catfile(Slim::Utils::Prefs::get('playlistdir'),'__history.m3u'),
	);
    }
};

#shrink history array if historylength is modified to be smaller than the current history array
sub adjustHistoryLength {
	my $newlen = Slim::Utils::Prefs::get('historylength');
	if (!$newlen) {
		clear();
	} elsif ($newlen < scalar(@history)) {
		splice @history,$newlen;
		if (Slim::Utils::Prefs::get('savehistory') && Slim::Utils::Prefs::get('playlistdir')) {
			Slim::Formats::Parse::writeM3U(\@history,catfile(Slim::Utils::Prefs::get('playlistdir'),'__history.m3u'));
		}
	}
}


# Histlist fills variables for populating an html file. 
sub hitlist {
	my($client, $paramref) = @_;
	my $output = "";
	my @items = ();
	my %list_form;
	my $i;
	my $song;
	my $itemnumber=0;
	my $maxplayed=0;

	@items = recount();
	if (scalar(@items)) {
		for ($i = 0; $i < scalar(@items); $i++) {
		    if ($maxplayed==0) { $maxplayed = $items[$i][1]; }
    		%list_form = ();
            $song = $items[$i][0];

			$list_form{'title'} 	= Slim::Music::Info::standardTitle(undef,$song);
			$list_form{'artist'} 	= Slim::Music::Info::artist($song);
			$list_form{'album'} 	= Slim::Music::Info::album($song);
			$list_form{'itempath'} = $song;
			$list_form{'odd'}	  = ($itemnumber + 1) % 2;
			$list_form{'song_bar'} = hitlist_bar($paramref, $items[$i][1], $maxplayed );
			$list_form{'player'} = $$paramref{'player'};
			$itemnumber++;

			$list_form{'skinOverride'} = $$paramref{'skinOverride'};
			$list_form{'song_count'} = $items[$i][1];
			$$paramref{'browse_list'} .= &Slim::Web::HTTP::filltemplatefile("hitlist_list.html", \%list_form);
		}
	}

	$$paramref{'total_song_count'} = Slim::Music::Info::songCount([],[],[],[]);
	$$paramref{'genre_count'} = Slim::Music::Info::genreCount([],[],[],[]);
	$$paramref{'artist_count'} = Slim::Music::Info::artistCount([],[],[],[]);
	$$paramref{'album_count'} = Slim::Music::Info::albumCount([],[],[],[]);

	$output .= &Slim::Web::HTTP::filltemplatefile("hitlist.html", $paramref);
}

sub hitlist_bar {
	my $paramRef = shift;
    my $curr = shift;
    my $max = shift;
    my $returnval="";
    
    $paramRef->{'cell_full'} = (($curr*100)/$max) > 9;
    $returnval .= &Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $paramRef);
    $paramRef->{'cell_full'} = (($curr*100)/$max) > 19;
    $returnval .= &Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $paramRef);
    $paramRef->{'cell_full'} = (($curr*100)/$max) > 29;
    $returnval .= &Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $paramRef);
    $paramRef->{'cell_full'} = (($curr*100)/$max) > 39;
    $returnval .= &Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $paramRef);
    $paramRef->{'cell_full'} = (($curr*100)/$max) > 49;
    $returnval .= &Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $paramRef);
    $paramRef->{'cell_full'} = (($curr*100)/$max) > 59;
    $returnval .= &Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $paramRef);
    $paramRef->{'cell_full'} = (($curr*100)/$max) > 69;
    $returnval .= &Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $paramRef);
    $paramRef->{'cell_full'} = (($curr*100)/$max) > 79;
    $returnval .= &Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $paramRef);
    $paramRef->{'cell_full'} = (($curr*100)/$max) > 89;
    $returnval .= &Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $paramRef);
    $paramRef->{'cell_full'} = ($curr == $max);
    $returnval .= &Slim::Web::HTTP::filltemplatefile("hitlist_bar.html", $paramRef);
    
    return $returnval;
}



	
1;
	
