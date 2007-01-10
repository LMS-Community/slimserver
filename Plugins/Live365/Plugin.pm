# Live365 tuner plugin for Slim Devices SlimServer
# Copyright (C) 2004  Jim Knepley
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

# $Id$

package Plugins::Live365::Plugin;

use strict;

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use Slim::Control::Request;

# Need this to include the other modules now that we split up Live365.pm
use Plugins::Live365::ProtocolHandler;
use Plugins::Live365::Live365API;
use Plugins::Live365::Settings;
use Plugins::Live365::Web;

use constant ROWS_TO_RETRIEVE => 50;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.live365',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

our $live365 = {};
our %channelModeFunctions;
our %mainModeFunctions;
our %genreModeFunctions;
our %searchModeFunctions;
our %infoModeFunctions = ();

my @searchModeItems = (
	[ 'PLUGIN_LIVE365_SEARCH_TAC', 'T:A:C' ],
	[ 'PLUGIN_LIVE365_SEARCH_A'  , 'A' ],
	[ 'PLUGIN_LIVE365_SEARCH_T'  , 'T' ],
	[ 'PLUGIN_LIVE365_SEARCH_C'  , 'C' ],
	[ 'PLUGIN_LIVE365_SEARCH_E'  , 'E' ],
	[ 'PLUGIN_LIVE365_SEARCH_L'  , 'L' ],
	[ 'PLUGIN_LIVE365_SEARCH_H'  , 'H' ]
);

our @mainModeItems;

our $mainModeIdx = 0;
our $searchModeIdx = 0;

our %searchString;
our @statusText;

my $cli_next;

sub getDisplayName {
	return 'PLUGIN_LIVE365_MODULE_NAME';
}

sub playOrAddCurrentStation {
	my $client = shift;
	my $play = shift;

	my $stationURL = $live365->{$client}->getCurrentChannelURL();

	$log->info("URL: $stationURL");

	my $line1;

	if ($play) {
		$line1 = $client->string('CONNECTING_FOR');
	}
	else {
		$line1 = $client->string('ADDING_TO_PLAYLIST');
	}

	my $title = $live365->{$client}->getCurrentStation()->{STATION_TITLE};

	$client->showBriefly({
		'line1'    => $line1,
		'line2'    => $title,
		'overlay2' => $client->symbols('notesymbol'),
	});

	Slim::Music::Info::setContentType($stationURL, 'mp3');
	Slim::Music::Info::setTitle($stationURL, $title);

	if ( $play ) {
		$client->execute([ 'playlist', 'clear' ] );
		$client->execute([ 'playlist', 'play', $stationURL ] );
	}
	else {
		$client->execute([ 'playlist', 'add', $stationURL ] );
	}
}

#############################
sub setMode {
	my $client = shift;
	my $entryType = shift;

	if ($entryType eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	if (!defined $live365->{$client} ) {
		$live365->{$client} = Plugins::Live365::Live365API->new;
	}

	my ( $loginModePtr ) = ( grep { $_->[0] eq 'loginMode' } @mainModeItems )[0];

	if ($entryType eq 'push' ) {
		loginMode($client, {'silent' => 1}) unless( $live365->{$client}->isLoggedIn() );
	}

	if( $live365->{$client}->isLoggedIn() ) {
		$loginModePtr->[1] = 'PLUGIN_LIVE365_LOGOUT';
	} else {
		$loginModePtr->[1] = 'PLUGIN_LIVE365_LOGIN';
	}
	
	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', {

		'listRef'        => \@mainModeItems,
		'externRef'      => sub { 

			if ($_[1][0] eq 'loginMode') {

				return $_[0]->string($live365->{$_[0]}->isLoggedIn() ? 'PLUGIN_LIVE365_LOGOUT' : 'PLUGIN_LIVE365_LOGIN');

			} else {

				return $_[0]->string($_[1][1]);
			}
		},

		'externRefArgs'  => 'CV',
		'header'         => \&mainHeader,
		'headerArgs'     => 'CI',
		'stringHeader'   => 1,
		'headerAddCount' => 1,
		'stringHeader'   => 1,
		'headerAddCount' => 1,
		'callback'       => \&mainExitHandler,
		'overlayRef'     => sub { return (undef, shift->symbols('rightarrow')) },
		'overlayRefArgs' => 'C',
	});
}

sub mainExitHandler {
	my ($client,$exitType) = @_;

	$exitType = uc($exitType);

	my $selection = ${$client->modeParam('valueRef')};

	if ($exitType eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} else {

		my $success = 0;
		my $stationParams = {};

		SWITCH: {

			$selection->[1] eq 'PLUGIN_LIVE365_PRESETS' && do {

				if (!$live365->{$client}->getSessionID() ) {

					$client->showBriefly({'line1' => $client->string( 'PLUGIN_LIVE365_NOT_LOGGED_IN' )});

				} else {

					$success = 1;
				}

				last SWITCH;
			};

			$selection->[1] eq 'PLUGIN_LIVE365_BROWSEALL' && do {

				$stationParams = {
					'sort'	       => Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
					'searchfields' => Slim::Utils::Prefs::get( 'plugin_live365_search_fields' )
				};

				$success = 1;

				last SWITCH;
			};

			$selection->[1] eq 'PLUGIN_LIVE365_BROWSEPICKS' && do {

				$stationParams = {
					'sort'	       => Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
					'searchfields' => Slim::Utils::Prefs::get( 'plugin_live365_search_fields' ),
					'genre'        => 'ESP'
				};

				$success = 1;

				last SWITCH;
			};

			$selection->[1] eq 'PLUGIN_LIVE365_BROWSEPROS' && do {

				$stationParams = {
					'sort'	       => Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
					'searchfields' => Slim::Utils::Prefs::get( 'plugin_live365_search_fields' ),
					'genre'	       => 'Pro'
				};

				$success = 1;

				last SWITCH;
			};

			$success = 1;
		}

		if ($success) {

			if ($selection->[0] eq 'loginMode') {

				loginMode($client);

			} else {

				Slim::Buttons::Common::pushModeLeft($client, $selection->[0], {
					source        => $selection->[1],
					stationParams => $stationParams
				});
			}
		}
	}
}

sub mainHeader {
	my $client = shift;
	my $index = shift;

	if ( my $APImessage = $live365->{$client}->status() ) {

		return $client->string( $APImessage);

	} else {

		return $client->string('PLUGIN_LIVE365_MODULE_NAME');
	}
}

#############################
sub loginMode {
	my $client = shift;
	my $args = shift;
	
	my $silent = $args->{'silent'};

	my $userID   = Slim::Utils::Prefs::get( 'plugin_live365_username' );
	my $password = Slim::Utils::Prefs::get( 'plugin_live365_password' );
	my $loggedIn = $live365->{$client}->isLoggedIn();

	if (defined $password) {
		$password = unpack('u', $password);
	}

	if( $loggedIn ) {

		$log->info("Logging out $userID");

		my $logoutStatus = $live365->{$client}->logout($client, \&logoutDone, $silent);
	
	} else {
	
		if ($userID and $password) {

			$log->info("Logging in $userID");

			my $loginStatus = $live365->{$client}->login( $userID, $password, $client, \&loginDone, $silent);

		} else {

			$log->warn("Warning: No credentials set.");

			if (!$silent) {
				$client->showBriefly({'line1' => $client->string( 'PLUGIN_LIVE365_NO_CREDENTIALS' )});
			}
		}
	}
}

sub loginDone {
	my $client = shift;
	my $args   = shift;
	
	my $loginStatus = $args->{'status'};
	my $webOnly     = $args->{'webOnly'};
	my $silent      = $args->{'silent'};

	if( $loginStatus == 0 ) {

		Slim::Utils::Prefs::set( 'plugin_live365_sessionid', $live365->{$client}->getSessionID() );
		Slim::Utils::Prefs::set( 'plugin_live365_memberstatus', $live365->{$client}->getMemberStatus() );

		if (!$silent) {
			$client->showBriefly({'line1' => $client->string( 'PLUGIN_LIVE365_LOGIN_SUCCESS' )});
		}

		$live365->{$client}->setLoggedIn(1);

		$log->info("Logged in: " . $live365->{$client}->getSessionID);

	} else {

		Slim::Utils::Prefs::set( 'plugin_live365_sessionid', undef );
		Slim::Utils::Prefs::set( 'plugin_live365_memberstatus', undef );

		$client->showBriefly({'line1' => $client->string( $statusText[ $loginStatus ] )});

		$live365->{$client}->setLoggedIn( 0 );

		$log->warn("Warning: Login failure: $statusText[$loginStatus]");
	}
}

sub logoutDone {
	my $client = shift;
	my $args = shift;
	
	my $logoutStatus = $args->{'status'};
	my $silent       = $args->{'silent'};

	if( $logoutStatus == 0 ) {

		$client->showBriefly({'line1' => $client->string( $statusText[ $logoutStatus ])});

		$log->info("Logged out.");

	} else {

		$client->showBriefly({'line1' => $client->string( $statusText[ $logoutStatus ])});

		$log->error("Error: While trying to logout: $statusText[ $logoutStatus ]");
	}

	$live365->{$client}->setLoggedIn( 0 );

	Slim::Utils::Prefs::set( 'plugin_live365_sessionid', '' );
}

sub noLoginMode {
	my $client = shift;
}

#############################
my @genreList = ();

sub setGenreMode {
	my $client = shift;
	my $entryType = shift;

	if ($entryType eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	$client->lines( \&loadingLines );

	if (!scalar(@genreList)) {
		$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_GENRES' );
		$live365->{$client}->loadGenreList($client, \&genreModeLoad, \&genreModeError);
	} else {
		genreModeLoad($client);
	}
}

sub genreModeLoad {
	my $client = shift;
	my $list = shift;

	@genreList = @$list if $list;

	$live365->{$client}->clearBlockingStatus();

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', {
		'listRef'        => \@genreList,
		'externRef'      => sub { return $_[1][0] },
		'externRefArgs'  => 'CV',
		'header'         => sub {
			if( my $APImessage = $live365->{$client}->status() ) {
				return $_[0]->string( $APImessage );
			} else {
				return $_[0]->string('PLUGIN_LIVE365_GENRES');
			}
		},
		'headerArgs'     => 'C',
		'stringHeader'   => 1,
		'headerAddCount' => 1,
		'stringHeader'   => 1,
		'headerAddCount' => 1,
		'callback'       => \&genreExitHandler,
		'overlayRef'     => sub { return (undef, shift->symbols('rightarrow')) },
		'overlayRefArgs' => 'C',
		'isSorted'       => 'L',
		'lookupRef'      => sub { 
			my $index = shift;
			return $genreList[$index][0];
		},
		'lookupRefArgs'  => 'I',
	});
}

sub genreModeError {
	my $client = shift;

	$live365->{$client}->clearBlockingStatus();

	$client->showBriefly({'line1' => $client->string( 'PLUGIN_LIVE365_LOGIN_ERROR_HTTP' )});
}

sub genreExitHandler {
	my ($client,$exitType) = @_;

	$exitType = uc($exitType);
	my $selection = ${$client->modeParam('valueRef')};

	if ($exitType eq 'LEFT') {

		$live365->{$client}->stopLoading();
		Slim::Buttons::Common::popModeRight( $client );

	} else {

		if (!scalar(@genreList)) {
			$client->bumpRight();
			return;
		}

		my $genrePointer = ${$client->modeParam('valueRef')};
		
		my $stationParams = {
			'genre'	       => $genrePointer->[1],
			'sort'         => Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
			'searchfields' => Slim::Utils::Prefs::get( 'plugin_live365_search_fields' )
		};

		Slim::Buttons::Common::pushModeLeft($client, 'Live365Channels', {
			source => $genrePointer->[0], 
			stationParams => $stationParams
		});
	}
}

sub noGenreMode {
	my $client = shift;
}

#############################
sub setChannelMode {
	my $client    = shift;
	my $entryType = shift;

	if ($entryType eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	$client->lines( \&loadingLines );
	
	$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_DIRECTORY' );

	my $source = $client->modeParam('source');

	if (defined($source) && $source eq 'PLUGIN_LIVE365_PRESETS') {

		$live365->{$client}->clearStationDirectory();

		$live365->{$client}->loadMemberPresets(
			$source,
			$client, 
			\&channelModeLoad,
			\&channelModeError
		);

		return;

	} elsif (!defined($source) || $source ne $live365->{$client}->getStationSource()) {

		my $pointer = defined($source) ? $live365->{$client}->getChannelModePointer($source) || 0 : 0;

		my $stationParams = $client->modeParam('stationParams');

		# If the last position within the station list is greater than
		# the default number of rows to retrieve, get enough so that
		# we have a non-sparse station array.
		if ($pointer > ROWS_TO_RETRIEVE) {

			$stationParams->{'rows'} = $pointer + ROWS_TO_RETRIEVE;

		} else {

			$stationParams->{'rows'} = ROWS_TO_RETRIEVE;
		}

		$live365->{$client}->clearStationDirectory();
		$live365->{$client}->loadStationDirectory(
			$source, $client, \&channelModeLoad, \&channelModeError, 0, %$stationParams
		);

		return;
	}

	channelModeLoad($client);
}

sub channelModeLoad {
	my $client = shift || return;

	my $source = $client->modeParam('source');
	
	# Check if the current pointer for the source mode is greater than
	# the number of stations currently loaded. If so, clip it.
	my $pointer = defined($source) ? $live365->{$client}->getChannelModePointer($source) || 0 : 0;

	my $listlength = $live365->{$client}->getStationListLength();

	if ($listlength) {

		if ($pointer >= $listlength) {
			$pointer = $listlength - 1;
		}
		
		$live365->{$client}->setStationListPointer($pointer);
	}

	$live365->{$client}->clearBlockingStatus();
	
	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', {
		'listRef'        => [1..$live365->{$client}->getStationListLength()],
		'externRef'      => sub { 

			if (my $station = $live365->{$_[0]}->getCurrentStation()) {

				return $station->{STATION_TITLE};

			} elsif ( my $APImessage = $live365->{$client}->status() ) {

				return $_[0]->string( $APImessage );
			}
		},

		'externRefArgs'  => 'C',
		'header'         => sub {

			if( my $APImessage = $live365->{$client}->status() ) {

				return $_[0]->string( $APImessage );

			} else {

				return $_[0]->string('PLUGIN_LIVE365_STATIONS');
			}
		},
		'headerArgs'     => 'C',
		'stringHeader'   => 1,
		'headerAddCount' => 1,
		'stringHeader'   => 1,
		'headerAddCount' => 1,
		'onChange' => sub {
			if( $live365->{$client}->willRequireLoad( $_[1] ) ) {

				$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_DIRECTORY' );

				$client->update();

				$live365->{$_[0]}->setStationListPointer(
					$_[1], 
					$_[0],
					\&channelAdditionalLoad,
					\&channelAdditionalError
				);

			} else {

				$live365->{$client}->setStationListPointer( $_[1] );
			}
		},

		'onChangeArgs'   => 'CV',
		'callback'       => \&channelExitHandler,
		'overlayRef'     => sub { return (undef, shift->symbols('notesymbol')) },
		'overlayRefArgs' => 'C',
	});
}

sub channelExitHandler {
	my ($client,$exitType) = @_;

	$exitType = uc($exitType);

	my $selection = ${$client->modeParam('valueRef')};

	if ($exitType eq 'LEFT') {

		$live365->{$client}->stopLoading();
		Slim::Buttons::Common::popModeRight( $client );

	} else {

		if (!$live365->{$client}->getStationListLength()) {

			$client->bumpRight();
			return;
		}

		my $source = $client->modeParam('source');

		if (defined $source) {

			$live365->{$client}->setChannelModePointer(
				$source, $live365->{$client}->getStationListPointer
			);
		}
	
		Slim::Buttons::Common::pushModeLeft( $client, 'ChannelInfo' );
	}
}

sub channelModeError {
	my $client = shift;

	my $source = $client->modeParam( 'source');

	$live365->{$client}->clearBlockingStatus();

	if ($live365->{$client}->isLoggedIn) {

		if (defined $source) {
			$log->warn("Warning: No stations for source: $source");
		}

		$client->showBriefly({'line1' => $client->string( 'PLUGIN_LIVE365_NOSTATIONS' )});

	} else {

		$client->showBriefly({'line1' => $client->string('PLUGIN_LIVE365_NOT_LOGGED_IN' )});
	}

	Slim::Buttons::Common::popModeRight( $client );
}

sub noChannelMode {
	my $client = shift;
}

sub channelAdditionalLoad {
	my $client = shift || return;

	# if the numberscroll has been used, we may have to keep loading additional blocks until 
	# it is in range of the new stationListPointer
	if( $live365->{$client}->willRequireLoad( $live365->{$client}->getStationListPointer ) ) {

		$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_DIRECTORY' );

		$client->update;

		$live365->{$client}->setStationListPointer(
			$live365->{$client}->getStationListPointer, 
			$client,
			\&channelAdditionalLoad,
			\&channelAdditionalError
		);

	} else {

		$live365->{$client}->clearBlockingStatus;
		$client->update;
	}
}

sub channelAdditionalError {
	my $client = shift;

	$live365->{$client}->clearBlockingStatus;
	$client->update;
}

sub loadingLines {
	my $client = shift;

	if (my $APImessage = $live365->{$client}->status() ) {

		return { 'line1' => $client->string( $APImessage ) };
	}
}

#############################
sub setInfoMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_INFORMATION' );
	$client->update();

	$live365->{$client}->loadInfoForStation( $live365->{$client}->getCurrentStation()->{STATION_ID}, $client, \&infoModeLoad, \&infoModeError );;
}

sub infoModeLoad {
	my $client = shift;

	my @infoItems = $live365->{$client}->getStationInfo();
	my @items     = map {"{PLUGIN_LIVE365_". $_->[0] . "}: " . $_->[1]} @infoItems;

	infoModeCommon($client, @items);
}

sub infoModeError {
	my $client = shift;

	infoModeCommon($client, "{PLUGIN_LIVE365_NO_INFO}");
}

sub infoModeCommon {
	my $client = shift;

	my $url   = $live365->{$client}->getCurrentChannelURL();
	my $title = $live365->{$client}->getCurrentStation()->{STATION_TITLE};

	# use remotetrackinfo mode to show all details
	my %params  = (
		url     => $url,
		title   => $title,
		details => \@_,
	);

	$live365->{$client}->clearBlockingStatus();

	Slim::Buttons::Common::pushMode($client, 'remotetrackinfo', \%params);  

	$client->update();
}

sub noInfoMode {
	my $client = shift;
}

#############################
sub setSearchMode {
	my $client = shift;
	my $entryType = shift;

	if ($entryType eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	$searchString{$client} = '';

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', {
		'listRef'        => \@searchModeItems,
		'externRef'      => sub { 

			if (my $APImessage = $live365->{$client}->status() ) {

				return $_[0]->string( $APImessage )

			} else {

				return $_[0]->string($_[1][0]);
			}
		},

		'externRefArgs'  => 'CV',
		'header'         => 'PLUGIN_LIVE365_SEARCH',
		'stringHeader'   => 1,
		'headerAddCount' => 1,
		'callback'       => \&searchExitHandler,
		'overlayRef'     => sub { return (undef, shift->symbols('rightarrow')) },
		'overlayRefArgs' => 'C',
	});
}

sub searchExitHandler {
	my ($client,$exitType) = @_;

	$exitType = uc($exitType);
	
	if ($exitType eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} else {

		my $type = ${$client->modeParam('valueRef')}->[1];

		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Text', {

			'callback'     => \&doSearch,
			'valueRef'     => \$searchString{$client},
			'header'       => $client->string( 'PLUGIN_LIVE365_SEARCHPROMPT' ),
			'cursorPos'    => 0,
			'searchfields' => $type,
		});
	}
}

sub noSearchMode {
	my $client = shift;
}

sub doSearch {
	my $client = shift;
	my $exitType = shift;

	my $arrow = $client->symbols('rightarrow');

	$searchString{$client} =~ s/$arrow//;

	my $searchfields = $client->modeParam('searchfields');

	ExitEventType: {

		$log->debug("Exit input mode: '$exitType'");

		$exitType =~ /(backspace|cursor_left|delete|scroll_left)/ && do {

			Slim::Buttons::Common::popModeRight( $client );
			return;
		};

		$exitType =~ /(cursor_right|nextChar|scroll_right)/ && do {

			if ($searchString{$client} eq '' ) {

				$log->debug("String empty, returning" );
				return;
			}

			$log->debug("Search string: '$searchString{$client}'");

			last ExitEventType;
		};

		$log->warn("Warning: unsupported exit '$exitType'");

		return;
	}

	my $stationParams = {
		'searchdesc'   => $searchString{$client},
		'sort'         => Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
		'searchfields' => $searchfields
	};

	Slim::Buttons::Common::pushModeLeft($client, 'Live365Channels', { stationParams => $stationParams });
}

# Add web pages and handlers.  See Plugins::Live365::Web for handlers.
sub webPages {
	my $class = shift;

	my $urlBase = 'plugins/Live365';

	Slim::Web::Pages->addPageLinks("radio", { 'PLUGIN_LIVE365_MODULE_NAME' => "$urlBase/index.html?autologin=1" } );

	Slim::Web::HTTP::addPageFunction("$urlBase/browse.html",  \&Plugins::Live365::Web::handleBrowse);
	Slim::Web::HTTP::addPageFunction("$urlBase/search.html",  \&Plugins::Live365::Web::handleSearch);
	Slim::Web::HTTP::addPageFunction("$urlBase/action.html",  \&Plugins::Live365::Web::handleAction);
	Slim::Web::HTTP::addPageFunction("$urlBase/index.html",    \&Plugins::Live365::Web::handleIndex);
	Slim::Web::HTTP::addPageFunction("$urlBase/loginout.html", \&Plugins::Live365::Web::handleLogin);
}

sub getLive365 {
	my $client = shift;
	
	if ( defined $live365->{$client} ) {
		return $live365->{$client};
	} else {
		return undef;
	}
}

sub initPlugin {
	my $class = shift;

	$log->info("Initializing.");

	Slim::Player::ProtocolHandlers->registerHandler("live365", "Plugins::Live365::ProtocolHandler");

	Plugins::Live365::Settings->new;

	$class->webPages;

	Slim::Buttons::Common::addMode( $class,            \%mainModeFunctions,    \&setMode);
	Slim::Buttons::Common::addMode( 'searchMode',      \%searchModeFunctions,  \&setSearchMode,  \&noSearchMode );
	Slim::Buttons::Common::addMode( 'genreMode',       \%genreModeFunctions,   \&setGenreMode,   \&noGenreMode );
	Slim::Buttons::Common::addMode( 'ChannelInfo',     \%infoModeFunctions,    \&setInfoMode,    \&noInfoMode );
	Slim::Buttons::Common::addMode( 'Live365Channels', \%channelModeFunctions, \&setChannelMode, \&noChannelMode );

	@mainModeItems = (
		[ 'genreMode',	     'PLUGIN_LIVE365_BROWSEGENRES' ],
		[ 'Live365Channels', 'PLUGIN_LIVE365_BROWSEPICKS' ],
		[ 'Live365Channels', 'PLUGIN_LIVE365_BROWSEPROS' ],
		[ 'Live365Channels', 'PLUGIN_LIVE365_BROWSEALL' ],
		[ 'searchMode',	     'PLUGIN_LIVE365_SEARCH' ],
		[ 'Live365Channels', 'PLUGIN_LIVE365_PRESETS' ],
		[ 'loginMode',	     'PLUGIN_LIVE365_LOGIN' ]
	);

	@statusText = qw(
		PLUGIN_LIVE365_LOGIN_SUCCESS
		PLUGIN_LIVE365_LOGIN_ERROR_NAME
		PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
		PLUGIN_LIVE365_LOGIN_ERROR_ACTION
		PLUGIN_LIVE365_LOGIN_ERROR_ORGANIZATION
		PLUGIN_LIVE365_LOGIN_ERROR_SESSION
		PLUGIN_LIVE365_LOGIN_ERROR_HTTP
	);
	
	# register our functions
	
#		  |requires Client
#		  |  |is a Query
#		  |  |  |has Tags
#		  |  |  |  |Function to call
#		  C  Q  T  F
	Slim::Control::Request::addDispatch(['live365', 'genres', '_index', '_quantity'],  
		 [0, 1, 1, \&Plugins::Live365::Web::cli_genresQuery]);
	Slim::Control::Request::addDispatch(['live365', 'stations', '_index', '_quantity'],  
		 [0, 1, 1, \&Plugins::Live365::Web::cli_stationsQuery]);
	Slim::Control::Request::addDispatch(['live365', 'playlist', '_mode'],  
		 [1, 0, 1, \&Plugins::Live365::Web::cli_playlistCommand]);
	$cli_next=Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],
		 [0, 1, 1, \&cli_radiosQuery]);

	%channelModeFunctions = (
		'play' => sub {
			my $client = shift;
	
			playOrAddCurrentStation($client, 1);
		},
	
		'add' => sub {
			my $client = shift;
	
			playOrAddCurrentStation($client, 0);
		}
	);
}

sub cli_radiosQuery {
	my $request = shift;

	$log->debug("Begin Function");

	# what we want the query to report about ourself
	my $data = {
		'cmd'  => 'live365',                    # cmd label
		'name' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
		'type' => 'live365',              # type
	};
	
	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

1;
