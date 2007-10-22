package Slim::Web::Pages::Home;

# $Id$

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use POSIX ();
use HTTP::Status qw(RC_MOVED_TEMPORARILY);

use base qw(Slim::Web::Pages);

use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub init {
	my $class = shift;
	
	Slim::Web::HTTP::addPageFunction(qr/^$/, sub {$class->home(@_)});
	Slim::Web::HTTP::addPageFunction(qr/^home\.(?:htm|xml)/, sub {$class->home(@_)});
	Slim::Web::HTTP::addPageFunction(qr/^index\.(?:htm|xml)/, sub {$class->home(@_)});
	Slim::Web::HTTP::addPageFunction(qr/^squeezenetwork\.(?:htm|xml)/, sub {$class->squeezeNetwork(@_)});

	$class->addPageLinks("help",{'GETTING_STARTED' => "html/docs/quickstart.html"});
	$class->addPageLinks("help",{'HELP_REMOTE' => "html/docs/remote.html"});
	$class->addPageLinks("help",{'REMOTE_STREAMING' => "html/docs/remotestreaming.html"});
	$class->addPageLinks("help",{'FAQ' => "http://faq.slimdevices.com/"},1);
	$class->addPageLinks("plugins",{'SOFTSQUEEZE' => "html/softsqueeze/index.html"});
	$class->addPageLinks("help",{'TECHNICAL_INFORMATION' => "html/docs/index.html"});
	$class->addPageLinks("radio",{'SQUEEZENETWORK_SWITCH' => "squeezenetwork.html"});
}

sub home {
	my ($class, $client, $params, $gugus, $httpClient, $response) = @_;

	my $template = $params->{"path"} =~ /home\.(htm|xml)/ ? 'home.html' : 'index.html';
	
	# redirect to the setup wizard if it has never been run before 
	if (!$prefs->get('wizardDone')) {
		$response->code(RC_MOVED_TEMPORARILY);
		$response->header('Location' => '/settings/server/wizard.html');
		return Slim::Web::HTTP::filltemplatefile($template, $params);
	}

	my %listform = %$params;

	$params->{'nosetup'}  = 1 if $::nosetup;
	$params->{'noserver'} = 1 if $::noserver;
	$params->{'newVersion'} = $::newVersion if $::newVersion;

	if (!exists $Slim::Web::Pages::additionalLinks{"browse"}) {
		$class->addPageLinks("browse", {'BROWSE_BY_ARTIST' => "browsedb.html?hierarchy=contributor,album,track&amp;level=0"});
		$class->addPageLinks("browse", {'BROWSE_BY_GENRE'  => "browsedb.html?hierarchy=genre,contributor,album,track&amp;level=0"});
		$class->addPageLinks("browse", {'BROWSE_BY_ALBUM'  => "browsedb.html?hierarchy=album,track&amp;level=0"});
		$class->addPageLinks("browse", {'BROWSE_BY_YEAR'   => "browsedb.html?hierarchy=year,album,track&amp;level=0"});
		$class->addPageLinks("browse", {'BROWSE_NEW_MUSIC' => "browsedb.html?hierarchy=age,track&amp;level=0"});
	}

	if (!exists $Slim::Web::Pages::additionalLinks{"search"}) {
		$class->addPageLinks("search", {'SEARCHMUSIC' => "livesearch.html"});
		$class->addPageLinks("search", {'ADVANCEDSEARCH' => "advanced_search.html"});
	}

	if (!exists $Slim::Web::Pages::additionalLinks{"help"}) {
		$class->addPageLinks("help", {'GETTING_STARTED' => "html/docs/quickstart.html"});
		$class->addPageLinks("help", {'HELP_REMOTE' => "html/docs/remote.html"});
		$class->addPageLinks("help", {'REMOTE_STREAMING' => "html/docs/remotestreaming.html"});
		$class->addPageLinks("help", {'FAQ' => "html/docs/faq.html"});
		$class->addPageLinks("help", {'SOFTSQUEEZE' => "html/softsqueeze/index.html"});
		$class->addPageLinks("help", {'TECHNICAL_INFORMATION' => "html/docs/index.html"});
	}

	if ($prefs->get('audiodir')) {

		$class->addPageLinks("browse", {'BROWSE_MUSIC_FOLDER'   => "browsetree.html"});

	} else {

		$class->addPageLinks("browse", {'BROWSE_MUSIC_FOLDER' => undef});
		$params->{'nofolder'} = 1;
	}

	# Show playlists if any exists
	if ($prefs->get('playlistdir') || Slim::Schema->rs('Playlist')->getPlaylists->count) {

		$class->addPageLinks("browse", {'SAVED_PLAYLISTS' => "browsedb.html?hierarchy=playlist,playlistTrack&amp;level=0"});
	}

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

	# More leakage from the DigitalInput 'plugin'
	#
	# If our current player has digital inputs, show the menu.
	if ($client && Slim::Utils::PluginManager->isEnabled('Plugin::DigitalInput::Plugin')) {

		Slim::Plugin::DigitalInput::Plugin->webPages($client->hasDigitalIn);
	}

	# add favorites to first level of Default skin
	if (($params->{'skinOverride'} || $prefs->get('skin')) eq 'Default') {
		my $favs = Slim::Utils::Favorites->new($client);

		if ($favs) {
			$params->{'favorites'} = $favs->toplevel;
		}
	}

	$params->{'additionalLinks'} = \%Slim::Web::Pages::additionalLinks;

	$class->addPlayerList($client, $params);
	
	$class->addLibraryStats($params);

	return Slim::Web::HTTP::filltemplatefile($template, $params);
}

sub squeezeNetwork {
	my ($class, $client, $params) = @_;
	
	if ($client) {
		$params->{'playername'} = $client->name;
		
		Slim::Utils::Timers::setTimer(
			$client,
			time() + 1,
			sub {
				my $client = shift;
				Slim::Buttons::Common::pushModeLeft( $client, 'squeezenetwork.connect' );
			},
		);
	}
	
	return Slim::Web::HTTP::filltemplatefile('squeezenetwork.html', $params);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
