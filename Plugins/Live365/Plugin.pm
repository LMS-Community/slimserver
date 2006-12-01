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
	'category'     => 'plugin.digitalinput',
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

sub addMenu {
	return "RADIO";
}

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
		'overlayRef'     => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
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

sub getFunctions {
	return \%mainModeFunctions;
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
		'overlayRef'     => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
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
		'overlayRef'     => sub { return (undef, Slim::Display::Display::symbol('notesymbol')) },
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
		'overlayRef'     => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
		'overlayRefArgs' => '',
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

	my $arrow = Slim::Display::Display::symbol('rightarrow');

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
	$log->debug("Begin Function");
	
	my %pages = (
		"browse\.(?:htm|xml)"   => \&Plugins::Live365::Web::handleBrowse,
		"search\.(?:htm|xml)"   => \&Plugins::Live365::Web::handleSearch,
		"action\.(?:htm|xml)"   => \&Plugins::Live365::Web::handleAction,
		"index\.(?:htm|xml)"    => \&Plugins::Live365::Web::handleIndex,
		"loginout\.(?:htm|xml)" => \&Plugins::Live365::Web::handleLogin
	);

	if (grep { $_ eq 'Live365::Plugin' } Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks("radio", { 'PLUGIN_LIVE365_MODULE_NAME' => undef } );
	} else {
		Slim::Web::Pages->addPageLinks("radio", { 'PLUGIN_LIVE365_MODULE_NAME' => "plugins/Live365/index.html?autologin=1" } );
	}
	
	return (\%pages, undef);
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

	$log->info("Initializing.");

	Slim::Player::ProtocolHandlers->registerHandler("live365", "Plugins::Live365::ProtocolHandler");

	Plugins::Live365::Settings->new;

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

sub strings {
	return q^
PLUGIN_LIVE365_MODULE_NAME
	EN	Live365 Internet Radio
	ES	Radio por Internet Live365
	HE	LIVE365
	NL	Live365 Internet radio

PLUGIN_LIVE365_LOGOUT
	CS	Odhlásit
	DE	Abmelden
	EN	Log out
	ES	Desconectarse
	NL	Afmelden

PLUGIN_LIVE365_LOGIN
	CS	Přihlásit
	DE	Anmelden
	EN	Log in
	ES	Conectarse
	NL	Aanmelden

PLUGIN_LIVE365_NOT_LOGGED_IN
	DE	Nicht bei Live365 angemeldet
	EN	Not logged in to Live365
	ES	No se ha ingresado a Live365
	NL	Niet aangemeld bij Live365

PLUGIN_LIVE365_NO_CREDENTIALS
	DE	Keine Live365 Anmeldeinformationen
	EN	No Live365 account information
	ES	No existe información de cuenta para Live365
	NL	Geen Live365 gebruikersinformatie

PLUGIN_LIVE365_LOGIN_SUCCESS
	DE	Erfolgreich
	EN	Successful
	ES	Exitoso
	NL	Succesvol

PLUGIN_LIVE365_LOGIN_ERROR_NAME
	DE	Problem mit Anmeldenamen
	EN	Member name problem
	ES	Problema con el nombre de miembro
	NL	"Member name" probleem

PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
	CS	Problém s přihlášením
	DE	Problem beim Anmelden
	EN	Login problem
	ES	Problema de conexión
	NL	Aanmeldprobleem

PLUGIN_LIVE365_LOGIN_ERROR_ACTION
	DE	Unbekannter Vorgang
	EN	Unknown action
	ES	Acción desconocida
	NL	Onbekende actie

PLUGIN_LIVE365_LOGIN_ERROR_ORGANIZATION
	DE	Unbekannte Organisation
	EN	Unknown organization
	ES	Organización desconocida
	NL	Onbekende organisatie

PLUGIN_LIVE365_LOGIN_ERROR_SESSION
	DE	Sitzung abgelaufen. Bitte neu anmelden.
	EN	Session no longer valid. Log in again.
	ES	La sesión ya no es válida. Conectate nuevamente.
	NL	Sessie niet langer geldig. Meld opnieuw aan.

PLUGIN_LIVE365_LOGIN_ERROR_HTTP
	DE	Problem mit Live365 Website. Bitte neu versuchen.
	EN	Live365 website error, try again
	ES	Error del sitio web de Live365, intentar nuevamente
	NL	Live365 website fout, probeer opnieuw

PLUGIN_LIVE365_LOADING_GENRES
	CS	Stahuji žánry z Live365...
	DE	Genre-Liste wird von Live365 geladen...
	EN	Loading genre list from Live365...
	ES	Cargando la lista de géneros de Live365...
	NL	Laden genre lijst van Live365...

PLUGIN_LIVE365_LOADING_GENRES_ERROR
	CS	Chyba při stahování stylů. Zkuste to prosím později.
	DE	Fehler beim Laden der Genre-Liste. Bitte neu versuchen.
	EN	Error loading genres, try again
	ES	Error al cargar géneros, intente nuevamente...
	NL	Fout bij laden genres, probeer opnieuw

PLUGIN_LIVE365_PRESETS
	DE	Meine Voreinstellungen
	EN	My presets
	ES	Mis presets
	NL	Mijn voorkeuren

PLUGIN_LIVE365_BROWSEGENRES
	CS	Procházeet žánry
	DE	Musikstile durchsuchen
	EN	Browse genres
	ES	Examinar géneros
	FI	Selaa tyylilajeittain
	NL	Bekijk genres

PLUGIN_LIVE365_BROWSEALL
	CS	Procházet všechny stanice (mnoho)
	DE	Alle Stationen durchsuchen (viele)
	EN	Browse all stations (many)
	ES	Recorrer todas las estaciones (muchas)
	FI	Selaa kaikki asemat (paljon)
	NL	Bekijk alle stations (veel)

PLUGIN_LIVE365_BROWSEPICKS
	DE	Editor Picks durchsuchen
	EN	Browse editor picks
	ES	Revisar las elegidas por el editor
	NL	Bekijk redactie voorkeuren

PLUGIN_LIVE365_BROWSEPROS
	CS	Procházet profesionální stanice
	DE	Professionelle Stationen durchsuchen
	EN	Browse professional stations
	ES	Recorrer estaciones profesionales
	FI	Selaa ammattimaiset asemat
	NL	Bekijk professionele stations

PLUGIN_LIVE365_SEARCH
	DE	Live365 durchsuchen
	EN	Search Live365
	ES	Buscar en Live365
	NL	Zoek Live365

PLUGIN_LIVE365_SEARCHPROMPT
	DE	Live365 durchsuchen nach:
	EN	Search Live365:
	ES	Buscar en Live365:
	NL	Zoek Live365:

PLUGIN_LIVE365_LOADING_DIRECTORY
	CS	Nahrávám...
	DE	Lade...
	EN	Loading...
	ES	Cargando...
	NL	Laden...

PLUGIN_LIVE365_NOSTATIONS
	DE	Keine Station gefunden
	EN	No stations found
	ES	No se encontraron estaciones
	NL	Geen stations gevonden

PLUGIN_LIVE365_LOADING_INFORMATION
	DE	Senderinformation wird geladen...
	EN	Loading channel information...
	ES	Cargando información de canales...
	NL	laden kanaal informatie...

PLUGIN_LIVE365_DESCRIPTION
	CS	Popis stanice
	DE	Sender Beschreibung
	EN	Station Description
	ES	Descripción de estación
	NL	Beschrijving station

PLUGIN_LIVE365_STATION_LISTENERS_ACTIVE
	CS	Aktivních posluchačů
	DE	Aktive Zuhörer
	EN	Active listeners
	ES	Oyentes activos
	NL	Actieve luisteraars

PLUGIN_LIVE365_STATION_LISTENERS_MAX
	CS	Maximum posluchačů
	DE	Maximale Anzahl Zuhörer
	EN	Maximum listeners
	ES	Cantidad máxima de oyentes
	NL	Maximum aantal luisteraars

PLUGIN_LIVE365_LISTENER_ACCESS
	DE	Zuhörer Zugang
	EN	Listener access
	ES	Acceso para oyentes
	NL	Luisteraar toegang

PLUGIN_LIVE365_STATION_QUALITY_LEVEL
	CS	Kvalita vysílání stanice
	DE	Sender Qualität
	EN	Station quality
	ES	Calidad de la estación
	NL	Zender kwaliteit

PLUGIN_LIVE365_STATION_CONNECTION
	DE	Bandbreite
	EN	Bandwidth
	ES	Ancho de Banda
	NL	Bandbreedte

PLUGIN_LIVE365_STATION_CODEC
	EN	Codec
	ES	Codificador

PLUGIN_LIVE365_ERROR
	DE	Live365 Fehler
	EN	Live365 ERROR
	ES	ERROR de Live365
	NL	Live365 fout

PLUGIN_LIVE365_SEARCH_TAC
	DE	Nach Interpret/Lied/Album suchen
	EN	Search Artists/Tracks/CDs
	ES	Buscar Artistas/Canciones/CDs
	NL	Zoek artiesten/liedjes/CD's

PLUGIN_LIVE365_SEARCH_A
	DE	Suche Interpret
	EN	Search Artists
	ES	Buscar Artistas
	NL	Zoek artiesten

PLUGIN_LIVE365_SEARCH_T
	DE	Suche Lieder
	EN	Search Tracks
	ES	Buscar Canciones
	NL	Zoek liedje

PLUGIN_LIVE365_SEARCH_C
	DE	Suche Album
	EN	Search Albums
	ES	Buscar Discos
	NL	Zoek albums

PLUGIN_LIVE365_SEARCH_E
	DE	Nach Sender suchen
	EN	Search Stations
	ES	Buscar estaciones
	NL	Zoek stations

PLUGIN_LIVE365_SEARCH_L
	DE	Nach Region suchen
	EN	Search Locations
	ES	Buscar Lugares
	NL	Zoek locaties

PLUGIN_LIVE365_SEARCH_H
	DE	Nach Broadcaster suchen
	EN	Search Broadcasters
	ES	Buscar emisoras
	NL	Zoek omroepen

SETUP_GROUP_PLUGIN_LIVE365
	EN	Live365 Internet Radio
	ES	Radio por Internet Live365
	NL	Live365 Internet radio

SETUP_GROUP_PLUGIN_LIVE365_DESC
	CS	Prohledávat, procházet a ladit stanice Live365
	DE	Suche und höre Live365 Radiostationen
	EN	Search, browse, and tune Live365 stations
	ES	Buscar, recorrer y sintonizar estaciones Live365
	FR	Recherchez, parcourez et connectez-vous aux stations Live365
	IT	Cerca, sfoglia e sintonizza stazioni Live365
	NL	Zoek, bekijk en afstemmen Live365 stations

SETUP_PLUGIN_LIVE365_USERNAME
	DE	Live365 Benutzername
	EN	Live365 Username
	ES	Usuario de Live365
	FR	Nom d'utilisateur Live365
	IT	Codice utente Live365
	NL	Live365 gebruikersnaam

SETUP_PLUGIN_LIVE365_USERNAME_DESC
	DE	Ihr Live365 Benutzername, besuche live365.com zum Einschreiben
	EN	Your Live365 username, visit live365.com to sign up
	ES	Tu nombre de usuario de Live365,  visitar live365.com para registrarse
	FR	Votre nom d'utilisateur Live365 (visitez live365.com pour vous inscrire) :
	IT	Il tuo codice utente su Live365, visita live365.com per registrarti
	NL	Je Live365 gebruikersnaam, bezoek live365.com om aan te melden

SETUP_PLUGIN_LIVE365_PASSWORD
	DE	Live365 Passwort
	EN	Live365 Password
	ES	Contraseña para Live365
	FR	Mot de passe Live365
	NL	Live365 wachtwoord

SETUP_PLUGIN_LIVE365_PASSWORD_DESC
	DE	Dein Live365 Passwort
	EN	Your Live365 password
	ES	Tu contraseña para Live365
	FR	Votre mot de passe Live365 :
	IT	La tua password Live365
	NL	Je Live365 wachtwoord

SETUP_PLUGIN_LIVE365_PASSWORD_CHANGED
	DE	Dein Live365 Passwort wurde geändert
	EN	Your Live365 password has been changed
	ES	La contraseña para Live365 ha sido cambiada
	FR	Votre mot de passe Live365 a été modifié
	IT	La tua password Live365 e' stata cambiata
	NL	Je Live365 wachtwoord is gewijzigd

SETUP_PLUGIN_LIVE365_SORT_ORDER
	DE	Spalten sortieren
	EN	Sort columns
	ES	Columnas para ordenar
	FR	Ordre de tri
	IT	Ordina colonne
	NL	Sorteer kolommen

SETUP_PLUGIN_LIVE365_SORT_ORDER_DESC
	DE	Sortierreihenfolge der Sender definieren
	EN	Define the sort order of stations
	ES	Definir la secuencia de ordenamiento para estaciones
	FR	Spécifiez le paramètre de tri des stations
	IT	Definisci l'ordinamento delle stazioni
	NL	Definieer sorteer volgorde van stations

SETUP_PLUGIN_LIVE365_SORT_TITLE
	CS	Název stanice
	DE	Sender Sortierung
	EN	Station title
	ES	Título de la estación
	FR	Nom de la station
	IT	Nome stazione
	NL	Station titel

SETUP_PLUGIN_LIVE365_SORT_BPS
	DE	Sender Bitrate
	EN	Station bitrate
	ES	Tasa de bits de la estación
	FR	Taux binaire de la station
	IT	Bitrate stazione
	NL	Zender bitrate

SETUP_PLUGIN_LIVE365_SORT_RATING
	DE	Sender Beurteilung
	EN	Station rating
	ES	Calificación de la estación
	FR	Classement de la station
	IT	Valutazione stazione
	NL	Station beoordeling

SETUP_PLUGIN_LIVE365_SORT_LISTENERS
	DE	Anzahl Hörer
	EN	Number of listeners
	ES	Número de Oyentes
	FR	Nombre de connectés
	IT	Numero di ascoltatori
	NL	Aantal luisteraars

SETUP_PLUGIN_LIVE365_WEB_SHOW_DETAILS
	DE	Detaillierte Live365 Suchresultate
	EN	Detailed Live365 search results
	ES	Resultados detallados de búsqueda en Live365
	FR	Résultats de recherche détaillés Live365
	IT	Risultati di ricerca dettagliati su Live365
	NL	Gedetailleerde zoekresultaten

SETUP_PLUGIN_LIVE365_WEB_SHOW_DETAILS_DESC
	DE	Zeige detaillierte Suchresultate, wenn im Live365 Webinterface gesucht wird. Dies beinhaltet Interpreten, Titel und Albuminformationen wenn nach einem dieser Kriterien gesucht wird. Dies kann die Suchresultate etwas unübersichtlicher machen.
	EN	Show detailed results when searching Live365 through the web interface.  Includes artist, track, and album info when searching for one of these.  May make your search results longer and harder to browse.
	ES	Mostrar resultados detallados cuando se busca en Live365 a través de la interface web. Se incluye información de  artista, canción y disco cuando se busca por alguno de ellos. Esto puede generar resultados más largos y dificiles de recorrer.
	FR	Affiche des résultats détaillés (artiste, morceau, informations album) lors d'une recherche sur Live365 par l'interface web. La taille et la lisibilité des résultats peuvent s'en trouver affectées.
	IT	Mostra risultati dettagliati quando cerchi su Live365 attraverso l'interfaccia web. Include artista, traccia e informazioni sull'album quando cerchi uno di questi. Puo' rendere il risultato della ricerca piu' lungo e difficile da sfogliare.
	NL	Laat gedetailleerde resultaten zien bij het zoeken op Live365 via de web interface. Laat artiest, liedje en album informatie zien bij het zoeken op een van deze items. De resultatenlijst zal langer zijn en lastiger te lezen.

PLUGIN_LIVE365_GENRES
	CS	Styly Live365
	DE	Live365 Musikstile
	EN	Live365 genres
	ES	Géneros de Live365

PLUGIN_LIVE365_STATIONS
	DE	Live365 Sender
	EN	Live365 stations
	ES	Estaciones de Live365
	NL	Live365 zenders

PLUGIN_LIVE365_POPULAR
	DE	Populär
	EN	Popular
	NL	Populair

PLUGIN_LIVE365_RECENT
	DE	Kürzlich gehört
	EN	Recent
	ES	Reciente

PLUGIN_LIVE365_NO_INFO
	DE	Fehler beim Laden der Informationen
	EN	Error loading info
	NL	Fout bij laden info

TACMATCHING
	DE	Passende Interpreten/Titel/Alben
	EN	Tracks/Artists/CDs matching
	ES	Canciones/Artistas/CDs coincidentes
	IT	Tracce/Artisti/CD corrispondenti
	NL	Liedjes/Artiesten/CD's matchen

STATIONSMATCHING
	DE	Passende Sender
	EN	Stations matching
	ES	Estaciones coinciden
	IT	Stazioni corrispondenti a
	NL	Bij elkaar passende stations

LOCATIONSMATCHING
	DE	Passende Region
	EN	Locations matching
	ES	Ubicaciones coincidentes
	FI	Täsmäävät sijainnit
	IT	Locazioni corrispondenti a
	NL	Locatie matching

BROADCASTERSMATCHING
	DE	Passende Broadcaster
	EN	Broadcasters matching
	ES	Emisoras coincidentes
	FI	Lähettäjät jotka täsmäävät
	IT	Emittenti corrispondenti a
	NL	Omroep matching

PLUGIN_LIVE365_NO_INFO
	DE	Fehler beim Laden der Informationen
	EN	Error loading info
	ES	Error al cargar información
^;
}

1;
