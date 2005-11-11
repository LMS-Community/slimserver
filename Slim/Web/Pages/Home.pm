package Slim::Web::Pages::Home;

# $Id: Pages.pm 5121 2005-11-09 17:07:36Z dsully $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use POSIX ();

use Slim::Web::Pages;

sub init {
	
	Slim::Web::HTTP::addPageFunction(qr/^$/,\&home);
	Slim::Web::HTTP::addPageFunction(qr/^home\.(?:htm|xml)/,\&home);
	Slim::Web::HTTP::addPageFunction(qr/^index\.(?:htm|xml)/,\&home);

	addLinks("help",{'GETTING_STARTED' => "html/docs/quickstart.html"});
	addLinks("help",{'PLAYER_SETUP' => "html/docs/ipconfig.html"});
	addLinks("help",{'USING_REMOTE' => "html/docs/interface.html"});
	addLinks("help",{'HELP_REMOTE' => "html/help_remote.html"});
	addLinks("help",{'HELP_RADIO' => "html/docs/radio.html"});
	addLinks("help",{'REMOTE_STREAMING' => "html/docs/remotestreaming.html"});
	addLinks("help",{'FAQ' => "html/docs/faq.html"});
	addLinks("help",{'SOFTSQUEEZE' => "html/softsqueeze/index.html"});
	addLinks("help",{'TECHNICAL_INFORMATION' => "html/docs/index.html"});
}

sub home {
	my ($client, $params) = @_;

	my %listform = %$params;

	if (defined $params->{'forget'}) {
		Slim::Player::Client::forgetClient(Slim::Player::Client::getClient($params->{'forget'}));
	}

	$params->{'nosetup'}  = 1 if $::nosetup;
	$params->{'noserver'} = 1 if $::noserver;
	$params->{'newVersion'} = $::newVersion if $::newVersion;

	if (!exists $Slim::Web::Pages::additionalLinks{"browse"}) {
		addLinks("browse",{'BROWSE_BY_ARTIST' => "browsedb.html?hierarchy=artist,album,track&level=0"});
		addLinks("browse",{'BROWSE_BY_GENRE'  => "browsedb.html?hierarchy=genre,artist,album,track&level=0"});
		addLinks("browse",{'BROWSE_BY_ALBUM'  => "browsedb.html?hierarchy=album,track&level=0"});
		addLinks("browse",{'BROWSE_BY_YEAR'   => "browsedb.html?hierarchy=year,album,track&level=0"});
		addLinks("browse",{'BROWSE_NEW_MUSIC' => "browsedb.html?hierarchy=age,track&level=0"});
	}

	if (!exists $Slim::Web::Pages::additionalLinks{"search"}) {
		addLinks("search", {'SEARCH' => "livesearch.html"});
		addLinks("search", {'ADVANCEDSEARCH' => "advanced_search.html"});
	}

	if (!exists $Slim::Web::Pages::additionalLinks{"help"}) {
		addLinks("help",{'GETTING_STARTED' => "html/docs/quickstart.html"});
		addLinks("help",{'PLAYER_SETUP' => "html/docs/ipconfig.html"});
		addLinks("help",{'USING_REMOTE' => "html/docs/interface.html"});
		addLinks("help",{'HELP_REMOTE' => "html/help_remote.html"});
		addLinks("help",{'HELP_RADIO' => "html/docs/radio.html"});
		addLinks("help",{'REMOTE_STREAMING' => "html/docs/remotestreaming.html"});
		addLinks("help",{'FAQ' => "html/docs/faq.html"});
		addLinks("help",{'SOFTSQUEEZE' => "html/softsqueeze/index.html"});
		addLinks("help",{'TECHNICAL_INFORMATION' => "html/docs/index.html"});
	}

	if (Slim::Utils::Prefs::get('lookForArtwork')) {
		addLinks("browse",{'BROWSE_BY_ARTWORK' => "browsedb.html?hierarchy=artwork,track&level=0"});
	} else {
		addLinks("browse",{'BROWSE_BY_ARTWORK' => undef});
		$params->{'noartwork'} = 1;
	}
	
	if (Slim::Utils::Prefs::get('audiodir')) {
		addLinks("browse",{'BROWSE_MUSIC_FOLDER'   => "browsetree.html"});
	} else {
		addLinks("browse",{'BROWSE_MUSIC_FOLDER' => undef});
		$params->{'nofolder'}=1;
	}

	# Always show Browse Playlists, as it's stored in the db now.
	addLinks("browse",{'SAVED_PLAYLISTS' => "browsedb.html?hierarchy=playlist,playlistTrack&level=0"});

	# fill out the client setup choices
	for my $player (sort { $a->name() cmp $b->name() } Slim::Player::Client::clients()) {

		# every player gets a page.
		# next if (!$player->isPlayer());
		$listform{'playername'}   = $player->name();
		$listform{'playerid'}     = $player->id();
		$listform{'player'}       = $params->{'player'};
		$listform{'skinOverride'} = $params->{'skinOverride'};
		$params->{'player_list'} .= ${Slim::Web::HTTP::filltemplatefile("homeplayer_list.html", \%listform)};
	}

	Slim::Buttons::Plugins::addSetupGroups();
	$params->{'additionalLinks'} = \%Slim::Web::Pages::additionalLinks;

	Slim::Web::Pages->addPlayerList($client, $params);
	
	Slim::Web::Pages->addLibraryStats($params);

	my $template = $params->{"path"}  =~ /home\.(htm|xml)/ ? 'home.html' : 'index.html';
	
	return Slim::Web::HTTP::filltemplatefile($template, $params);
}

sub addLinks {
	Slim::Web::Pages->addPageLinks(@_);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
