# vim: foldmethod=marker
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
#

package Plugins::Live365::Plugin;

use strict;
use vars qw( $VERSION );
$VERSION = 1.20;

use Slim::Utils::Strings qw( string );
use Slim::Utils::Misc qw( msg );
use Slim::Control::Command;
use Slim::Display::Animation;

# Need this to include the other modules now that we split up Live365.pm
use Plugins::Live365::Web;
use Plugins::Live365::ProtocolHandler;
use Plugins::Live365::Live365API;

use constant ROWS_TO_RETRIEVE => 50;

# {{{ Initialize
our $live365;
Slim::Player::Source::registerProtocolHandler("live365", "Plugins::Live365::ProtocolHandler");

sub addMenu {
	return "RADIO";
}

sub getDisplayName {
	return 'PLUGIN_LIVE365_MODULE_NAME';
}

sub setupGroup {
	my %Group = (
		PrefOrder => [
			'plugin_live365_username',
			'plugin_live365_password',
			'plugin_live365_sort_order',
			'plugin_live365_web_show_details'
		],
		GroupHead => string( 'SETUP_GROUP_PLUGIN_LIVE365' ),
		GroupDesc => string( 'SETUP_GROUP_PLUGIN_LIVE365_DESC' ),
		GroupLine => 1,
		GroupSub  => 1,
		Suppress_PrefSub  => 1,
		Suppress_PrefLine => 1
	);

	my %sort_options = (
		'T:A' => string( 'SETUP_PLUGIN_LIVE365_SORT_TITLE' ),
		'B:D' => string( 'SETUP_PLUGIN_LIVE365_SORT_BPS' ),
		'R:D' => string( 'SETUP_PLUGIN_LIVE365_SORT_RATING' ),
		'L:D' => string( 'SETUP_PLUGIN_LIVE365_SORT_LISTENERS' ),
	);

	my %Prefs = (
		plugin_live365_username => {
		},
		plugin_live365_password => { 
			'onChange' => sub {
				my $encoded = pack( 'u', $_[1]->{plugin_live365_password}->{new} );
				Slim::Utils::Prefs::set( 'plugin_live365_password', $encoded );
			}
			,'inputTemplate' => 'setup_input_pwd.html'
			,'changeMsg' => string('SETUP_PLUGIN_LIVE365_PASSWORD_CHANGED')
		},
		plugin_live365_sort_order => {
			options => \%sort_options
		},
                plugin_live365_web_show_details => {
                        validate => \&Slim::Web::Setup::validateTrueFalse,
                        options  => {
                                1 => string('ON'),
                                0 => string('OFF')
                        },
                        'PrefChoose' => string('SETUP_PLUGIN_LIVE365_WEB_SHOW_DETAILS')
                }
	);

	return( \%Group, \%Prefs );
}

sub playOrAddCurrentStation {
	my $client = shift;
	my $play = shift;

	my $stationURL = $live365->{$client}->getCurrentChannelURL();
	$::d_plugins && msg( "Live365.ChannelMode URL: $stationURL\n" );

	my $line1;
	if ($play) {
		$line1 = $client->string('CONNECTING_FOR');
	}
	else {
		$line1 = $client->string('ADDING_TO_PLAYLIST');
	}

	my $title = $live365->{$client}->getCurrentStation()->{STATION_TITLE};
	$client->showBriefly(
		$client->renderOverlay($line1, $title, undef, Slim::Display::Display::symbol('notesymbol')),
		undef,
		1
	);

	Slim::Music::Info::setContentType($stationURL, 'mp3');
	Slim::Music::Info::setTitle($stationURL, $title);

	$play and $client->execute([ 'playlist', 'clear' ] );
	$client->execute([ 'playlist', 'add', $stationURL ] );
	$play and $client->execute([ 'play' ] );
}

# }}}

#############################
# Main mode {{{
# 
MAINMODE: {
my $mainModeIdx = 0;
my @mainModeItems = (
	[ 'genreMode',			'PLUGIN_LIVE365_BROWSEGENRES' ],
	[ 'Live365Channels',	'PLUGIN_LIVE365_BROWSEPICKS' ],
	[ 'Live365Channels',	'PLUGIN_LIVE365_BROWSEPROS' ],
	[ 'Live365Channels',	'PLUGIN_LIVE365_BROWSEALL' ],
	[ 'searchMode',			'PLUGIN_LIVE365_SEARCH' ],
	[ 'Live365Channels',	'PLUGIN_LIVE365_PRESETS' ],
	[ 'loginMode',			'PLUGIN_LIVE365_LOGIN' ]
);

sub setMode {
	my $client = shift;
	my $entryType = shift;

	$client->lines( \&mainModeLines );

	unless( defined $live365->{$client} ) {
		$live365->{$client} = new Plugins::Live365::Live365API();
	}

	my ( $loginModePtr ) = ( grep { $_->[0] eq 'loginMode' } @mainModeItems )[0];
	if( $entryType eq 'push' ) {
		Slim::Buttons::Common::pushMode( $client, 'loginMode', { silent => 1 } ) unless( $live365->{$client}->isLoggedIn() );
	}

	if( $live365->{$client}->isLoggedIn() ) {
		$loginModePtr->[1] = 'PLUGIN_LIVE365_LOGOUT';
	} else {
		$loginModePtr->[1] = 'PLUGIN_LIVE365_LOGIN';
	}
}

our %mainModeFunctions = (
	'up' => sub {
		my $client = shift;
		my $button = shift;
		my $newpos = Slim::Buttons::Common::scroll(
			$client,
			-1,
			scalar @mainModeItems,
			$mainModeIdx
		);
		if (scalar(@mainModeItems) < 2) {
			$client->bumpUp() if ($button !~ /repeat/);
		} elsif ($newpos != $mainModeIdx) {
			$mainModeIdx = $newpos;
			$client->pushUp();
		}
	},

	'down' => sub {
		my $client = shift;
		my $button = shift;
		my $newpos = Slim::Buttons::Common::scroll(
			$client,
			1,
			scalar @mainModeItems,
			$mainModeIdx
		);
		if (scalar(@mainModeItems) < 2) {
			$client->bumpDown() if ($button !~ /repeat/);
		} elsif ($newpos != $mainModeIdx) {
			$mainModeIdx = $newpos;
			$client->pushDown();
		}
	},

	'left' => sub {
		Slim::Buttons::Common::popModeRight( shift );
	},

	'right' => sub {
		my $client = shift;

		my $success = 0;
		my $stationParams = {};
		SWITCH: {
			$mainModeItems[$mainModeIdx][1] eq 'PLUGIN_LIVE365_PRESETS' && do {
				if( !$live365->{$client}->getSessionID() ) {
					Slim::Display::Animation::showBriefly( $client, $client->string( 'PLUGIN_LIVE365_NOT_LOGGED_IN' ));
				} else {
					$success = 1;
				}
				last SWITCH;
			};

			$mainModeItems[$mainModeIdx][1] eq 'PLUGIN_LIVE365_BROWSEALL' && do {
				$stationParams = {
					sort			=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
					searchfields	=> Slim::Utils::Prefs::get( 'plugin_live365_search_fields' )
				};
				$success = 1;
				last SWITCH;
			};

			$mainModeItems[$mainModeIdx][1] eq 'PLUGIN_LIVE365_BROWSEPICKS' && do {
				$stationParams = {
					sort			=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
					searchfields	=> Slim::Utils::Prefs::get( 'plugin_live365_search_fields' ),
					genre 			=> 'ESP'
				};
				$success = 1;
				last SWITCH;
			};

			$mainModeItems[$mainModeIdx][1] eq 'PLUGIN_LIVE365_BROWSEPROS' && do {
				$stationParams = {
					sort			=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
					searchfields	=> Slim::Utils::Prefs::get( 'plugin_live365_search_fields' ),
					genre			=> 'Pro'
				};
				$success = 1;
				last SWITCH;
			};

			$success = 1;
		}

		if( $success ) {
			if ($mainModeItems[$mainModeIdx][0] eq 'loginMode') {
				Slim::Buttons::Common::pushMode( $client, $mainModeItems[$mainModeIdx][0] );
			}
			else {
				Slim::Buttons::Common::pushModeLeft( $client, $mainModeItems[$mainModeIdx][0], { source => $mainModeItems[$mainModeIdx][1], stationParams => $stationParams } );
			}
		}
	}
);

sub mainModeLines {
	my $client = shift;
	my @lines;

	if( my $APImessage = $live365->{$client}->status() ) {
		$lines[0] = $client->string( $APImessage );
		return @lines;
	}

	$lines[0] = $client->string( 'PLUGIN_LIVE365_MODULE_NAME' ) . 
		' (' . ($mainModeIdx+1) .
		' ' .  $client->string('OF') . 
		' ' . (scalar(@mainModeItems)) . 
		')';
	$lines[1] = $client->string( $mainModeItems[$mainModeIdx][1] );

	$lines[3] = Slim::Hardware::VFD::symbol('rightarrow');

	return @lines;
}

sub getFunctions {
	return \%mainModeFunctions;
}

} # end main mode

# }}}

#############################
# Login mode {{{
#
our @statusText = qw(
	PLUGIN_LIVE365_LOGIN_SUCCESS
	PLUGIN_LIVE365_LOGIN_ERROR_NAME
	PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
	PLUGIN_LIVE365_LOGIN_ERROR_ACTION
	PLUGIN_LIVE365_LOGIN_ERROR_ORGANIZATION
	PLUGIN_LIVE365_LOGIN_ERROR_SESSION
	PLUGIN_LIVE365_LOGIN_ERROR_HTTP
);

LOGINMODE: {
our $setLoginMode = sub {
	my $client = shift;
	my $silent = $client->param( 'silent');

	my $userID   = Slim::Utils::Prefs::get( 'plugin_live365_username' );
	my $password = Slim::Utils::Prefs::get( 'plugin_live365_password' );
	my $loggedIn = $live365->{$client}->isLoggedIn();

	if (defined $password) {
	    $password = unpack('u', $password);
	}

	if( $loggedIn ) {
		$::d_plugins && msg( "Logging out $userID\n" );
		my $logoutStatus = $live365->{$client}->logout($client, \&logoutDone);
	} else {
		if( $userID and $password ) {
			$::d_plugins && msg( "Logging in $userID\n" );
			my $loginStatus = $live365->{$client}->login( $userID, $password,
														  $client, \&loginDone);
		} else {
			$::d_plugins && msg( "Live365.login: no credentials set\n" );
			unless ($silent) {
				Slim::Display::Animation::showBriefly( $client, $client->string( 'PLUGIN_LIVE365_NO_CREDENTIALS' ) );
			}
			Slim::Buttons::Common::popMode( $client );
		}
	}
};

sub loginDone {
	my $client = shift;
	my $loginStatus = shift;
	my $webOnly = shift;

	my $silent = $client->param( 'silent');

	if( $loginStatus == 0 ) {
		Slim::Utils::Prefs::set( 'plugin_live365_sessionid', $live365->{$client}->getSessionID() );
		Slim::Utils::Prefs::set( 'plugin_live365_memberstatus', $live365->{$client}->getMemberStatus() );
		unless ($silent) {
			Slim::Display::Animation::showBriefly( $client, $client->string( 'PLUGIN_LIVE365_LOGIN_SUCCESS' ) );
		}
		$live365->{$client}->setLoggedIn( 1 );
		$::d_plugins && msg( "Live365 logged in: " . $live365->{$client}->getSessionID() . "\n" );
	} else {
		Slim::Utils::Prefs::set( 'plugin_live365_sessionid', undef );
		Slim::Utils::Prefs::set( 'plugin_live365_memberstatus', undef );
		Slim::Display::Animation::showBriefly( $client, $client->string( $statusText[ $loginStatus ] ) );
		$live365->{$client}->setLoggedIn( 0 );
		$::d_plugins && msg( "Live365 login failure: " . $statusText[ $loginStatus ] . "\n" );
	}

	Slim::Buttons::Common::popMode( $client );
}

sub logoutDone {
	my $client = shift;
	my $logoutStatus = shift;

	if( $logoutStatus == 0 ) {
		Slim::Display::Animation::showBriefly( $client, $client->string( $statusText[ $logoutStatus ] ) );
		  $::d_plugins && msg( "Live365 logged out.\n" );
	} else {
		Slim::Display::Animation::showBriefly( $client, $client->string( $statusText[ $logoutStatus ] ) );
		$::d_plugins && msg( "Live365 logout error: $statusText[ $logoutStatus ]\n" );
	}

	$live365->{$client}->setLoggedIn( 0 );
	Slim::Utils::Prefs::set( 'plugin_live365_sessionid', '' );

	Slim::Buttons::Common::popMode( $client );
}

my $noLoginMode = sub {
	my $client = shift;
};

Slim::Buttons::Common::addMode( 'loginMode', {}, $setLoginMode, $noLoginMode );

} # end login mode

# }}}

#############################
# Genre mode {{{
#
my @genreList = ();

GENREMODE: {
our $setGenreMode = sub {
	my $client = shift;
	$client->lines( \&GenreModeLines );

	if (!scalar(@genreList)) {
		$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_GENRES' );
		$live365->{$client}->loadGenreList($client, \&genreModeLoad, \&genreModeError);
	}
};

sub genreModeLoad {
	my $client = shift;
	my $list = shift;

	@genreList = @$list;

	$live365->{$client}->clearBlockingStatus();
	$client->update();
}

sub genreModeError {
	my $client = shift;

	$live365->{$client}->clearBlockingStatus();

	Slim::Display::Animation::showBriefly( $client, $client->string( 'PLUGIN_LIVE365_LOGIN_ERROR_HTTP' ), ' ' );
	Slim::Buttons::Common::popModeRight( $client );
}

our $noGenreMode = sub {
	my $client = shift;
};

our %genreModeFunctions = (
	'up' => sub {
		my $client = shift;
		my $button = shift;
		if (!scalar(@genreList)) {
			$client->bumpUp() if ($button !~ /repeat/);
			return;
		}
		my $genrePointer = $live365->{$client}->getGenrePointer();
		my $newPointer = Slim::Buttons::Common::scroll(
			$client,
			-1,
			scalar @genreList,
			$genrePointer
		);
		if ($newPointer != $genrePointer) {
			$live365->{$client}->setGenrePointer($newPointer);
			$client->pushUp();
		}
	},

	'down' => sub {
		my $client = shift;
		my $button = shift;
		if (!scalar(@genreList)) {
			$client->bumpDown() if ($button !~ /repeat/);
			return;
		}
		my $genrePointer = $live365->{$client}->getGenrePointer();
		my $newPointer = Slim::Buttons::Common::scroll(
			$client,
			1,
			scalar @genreList,
			$genrePointer
		);
		if ($newPointer != $genrePointer) {
			$live365->{$client}->setGenrePointer($newPointer);
			$client->pushDown();
		}
	},

	'left' => sub {
		my $client = shift;
		$live365->{$client}->stopLoading();
		Slim::Buttons::Common::popModeRight( $client );
	},

	'right' => sub {
		my $client = shift;
		if (!scalar(@genreList)) {
			$client->bumpRight();
			return;
		}

		my $genrePointer = $live365->{$client}->getGenrePointer();

		my $stationParams = {
			genre			=> $genreList[ $genrePointer ][1],
			sort			=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
			searchfields	=> Slim::Utils::Prefs::get( 'plugin_live365_search_fields' )
		};
		Slim::Buttons::Common::pushModeLeft( $client, 'Live365Channels', 
							{ source => $genreList[ $genrePointer ][0], 
							  stationParams => $stationParams  } );
	}
);

sub GenreModeLines {
	my $client = shift;
	my @lines = ();

	if( my $APImessage = $live365->{$client}->status() ) {
		$lines[0] = $client->string( $APImessage );
		return @lines;
	}

	my $genrePointer = $live365->{$client}->getGenrePointer();

	$lines[0] = sprintf( "%s (%d %s %d)",
		$client->string( 'PLUGIN_LIVE365_GENRES' ),
		$genrePointer + 1,
		$client->string( 'OF' ),
		scalar @genreList
	);
	$lines[1] = $genreList[ $genrePointer ][0];
	$lines[3] = Slim::Hardware::VFD::symbol('rightarrow');

	return @lines;
}

Slim::Buttons::Common::addMode( 'genreMode', \%genreModeFunctions, $setGenreMode, $noGenreMode );

} # end genre mode

# }}}

#############################
# Channel mode {{{
#
CHANNELMODE: {
our $setChannelMode = sub {
	my $client = shift;
	my $method = shift;

	$client->lines( \&channelModeLines );
	
	if ($method ne 'pop') {
		$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_DIRECTORY' );

		my $source = $client->param('source');
		if (defined($source) && $source eq 'PLUGIN_LIVE365_PRESETS') {
			$live365->{$client}->clearStationDirectory();
			$live365->{$client}->loadMemberPresets($source,
												   $client, 
												   \&channelModeLoad,
												   \&channelModeError);
			return;
		}
		elsif (!defined($source) ||
			   $source ne $live365->{$client}->getStationSource()) {

			my $pointer = defined($source) ? $live365->{$client}->getChannelModePointer($source) || 0 : 0;

			my $stationParams = $client->param('stationParams');

			# If the last position within the station list is greater than
			# the default number of rows to retrieve, get enough so that
			# we have a non-sparse station array.
			if ($pointer > ROWS_TO_RETRIEVE) {
				$stationParams->{'rows'} = $pointer + ROWS_TO_RETRIEVE;
			}
			else {
				$stationParams->{'rows'} = ROWS_TO_RETRIEVE;
			}

			$live365->{$client}->clearStationDirectory();
			$live365->{$client}->loadStationDirectory(
													  $source,
													  $client, 
													  \&channelModeLoad,
													  \&channelModeError,
													  0,
													  %$stationParams);
			return;
		}
		channelModeLoad($client);
	}
};

sub channelModeLoad {
	my $client = shift;

	my $source = $client->param('source');
	
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
	$client->update();
}

sub channelModeError {
	my $client = shift;

	my $source = $client->param( 'source');

	$live365->{$client}->clearBlockingStatus();

	if ($live365->{$client}->isLoggedIn()) {
		$::d_plugins && defined($source) && msg( "No stations for source: $source\n");
		Slim::Display::Animation::showBriefly( $client, $client->string( 'PLUGIN_LIVE365_NOSTATIONS' ), ' ' );
	} else {
		Slim::Display::Animation::showBriefly( $client, $client->string('PLUGIN_LIVE365_NOT_LOGGED_IN' ), ' ' );
	}


	Slim::Buttons::Common::popModeRight( $client );
}

my $noChannelMode = sub {
	my $client = shift;
};

our %channelModeFunctions = (
    'up' => sub {
        my $client = shift;
	my $button = shift;

		# Since we haven't necessarially loaded out to the end of the list yet, 
		# we can't wrap around from the top. This will be addressed in a later
		# version.
		if( $live365->{$client}->getStationListPointer() == 0 ) {
			$client->bumpUp() if ($button !~ /repeat/);
			return;
		}

		my $newStationPointer = Slim::Buttons::Common::scroll(
            $client,
            -1,
            $live365->{$client}->getStationListLength(),
            $live365->{$client}->getStationListPointer()
		);
		if ($newStationPointer != $live365->{$client}->getStationListPointer()) {
			$live365->{$client}->setStationListPointer($newStationPointer);
			
			$client->pushUp();
		}
    },

    'down' => sub {
        my $client = shift;
	my $button = shift;

		if (!$live365->{$client}->getStationListLength()) {
			$client->bumpDown() if ($button !~ /repeat/);
			return;
		}
		
        my $newStationPointer = Slim::Buttons::Common::scroll(
            $client,
            1,
            $live365->{$client}->getStationListLength(),
            $live365->{$client}->getStationListPointer()
        );

		if( $live365->{$client}->willRequireLoad( $newStationPointer ) ) {
			$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_DIRECTORY' );
			$client->update();
        	$live365->{$client}->setStationListPointer($newStationPointer, 
													   $client,
													   \&channelAdditionalLoad,
													   \&channelAdditionalError);
		} elsif ($newStationPointer != $live365->{$client}->getStationListPointer()) {
        	$live365->{$client}->setStationListPointer( $newStationPointer );
			$client->pushDown();
		}

    },

    'left' => sub {
        my $client = shift;

		my $source = $client->param( 'source');
		if (defined($source)) {
			$live365->{$client}->setChannelModePointer($source, 
				$live365->{$client}->getStationListPointer());
		}

		$live365->{$client}->stopLoading();

        Slim::Buttons::Common::popModeRight( $client );
    },

    'right' => sub {
        my $client = shift;

		if (!$live365->{$client}->getStationListLength()) {
			$client->bumpRight();
			return;
		}

		my $source = $client->param( 'source');
		if (defined($source)) {
			$live365->{$client}->setChannelModePointer($source, 
				$live365->{$client}->getStationListPointer());
		}
	
        Slim::Buttons::Common::pushModeLeft( $client, 'ChannelInfo' );
    },

    'play' => sub {
		my $client = shift;

		playOrAddCurrentStation($client, 1);
    },

	'add' => sub {
		my $client = shift;

		playOrAddCurrentStation($client, 0);
    }
);

sub channelAdditionalLoad {
	my $client = shift;

	$live365->{$client}->clearBlockingStatus();
	$client->update();
}

sub channelAdditionalError {
	my $client = shift;

	$live365->{$client}->clearBlockingStatus();
	$client->update();
}

sub channelModeLines {
	my $client = shift;
	my @lines = ();

	if( my $APImessage = $live365->{$client}->status() ) {
		$lines[0] = $client->string( $APImessage );
		return @lines;
	}

	if( $live365->{$client}->getStationListLength() > 0 ) {
		$lines[0] = sprintf( "%s (%d %s %d)",
			$client->string( 'PLUGIN_LIVE365_STATIONS' ),
			$live365->{$client}->getStationListPointer() + 1,
			$client->string( 'OF' ),
			$live365->{$client}->getStationListLength()
		);

		$lines[1] = $live365->{$client}->getCurrentStation()->{STATION_TITLE};
		$lines[3] = Slim::Hardware::VFD::symbol('rightarrow');
	} else {
		$lines[0] = $client->string( 'PLUGIN_LIVE365_NOSTATIONS' );
	}

	return @lines;
}

Slim::Buttons::Common::addMode( 'Live365Channels', \%channelModeFunctions, $setChannelMode, $noChannelMode );

} # end channel mode

# }}}

#############################
# Information mode {{{
#
INFOMODE: {

our $setInfoMode = sub {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_INFORMATION' );
	$client->update();

	$live365->{$client}->loadInfoForStation( $live365->{$client}->getCurrentStation()->{STATION_ID}, $client, \&infoModeLoad, \&infoModeError );;
};

sub infoModeLoad {
	my $client = shift;

	my @infoItems = $live365->{$client}->getStationInfo();
	my @items = map {"{PLUGIN_LIVE365_". $_->[0] . "}: " . $_->[1]} @infoItems;

	infoModeCommon($client, @items);
}

sub infoModeError {
	my $client = shift;

	infoModeCommon($client, "{PLUGIN_LIVE365_NO_INFO}");
}

sub infoModeCommon {
	my $client = shift;

	my $url = $live365->{$client}->getCurrentChannelURL();
	my $title = $live365->{$client}->getCurrentStation()->{STATION_TITLE};

	# use remotetrackinfo mode to show all details
	my %params = (
		url => $url,
		title => $title,
		details => \@_,
	);

	$live365->{$client}->clearBlockingStatus();
	Slim::Buttons::Common::pushMode($client, 'remotetrackinfo', \%params);  
	$client->update();
}

our $noInfoMode = sub {
	my $client = shift;
};

our %infoModeFunctions = (
);

Slim::Buttons::Common::addMode( 'ChannelInfo', \%infoModeFunctions, $setInfoMode, $noInfoMode );

} # end info mode

# }}}

#############################
# Search mode {{{
#
SEARCHMODE: { 

our %searchString;

our @searchModeItems = (
	[ 'PLUGIN_LIVE365_SEARCH_TAC', 'T:A:C' ],
	[ 'PLUGIN_LIVE365_SEARCH_A', 'A' ],
	[ 'PLUGIN_LIVE365_SEARCH_T', 'T' ],
	[ 'PLUGIN_LIVE365_SEARCH_C', 'C' ],
	[ 'PLUGIN_LIVE365_SEARCH_E', 'E' ],
	[ 'PLUGIN_LIVE365_SEARCH_L', 'L' ],
	[ 'PLUGIN_LIVE365_SEARCH_H', 'H' ]
);

my $searchModeIdx = 0;

our $setSearchMode = sub {
	my $client = shift;

	$client->lines( \&searchModeLines );

	$searchString{$client} = '';
};

our %searchModeFunctions = (
	'up' => sub {
		my $client = shift;
		my $newIdx = Slim::Buttons::Common::scroll(
			$client,
			-1,
			scalar @searchModeItems,
			$searchModeIdx
		);
		if ($searchModeIdx != $newIdx) {
			$searchModeIdx = $newIdx;
			$client->pushUp();
		}
	},

	'down' => sub {
		my $client = shift;
		my $newIdx = Slim::Buttons::Common::scroll(
			$client,
			1,
			scalar @searchModeItems,
			$searchModeIdx
		);
		if ($searchModeIdx != $newIdx) {
			$searchModeIdx = $newIdx;
			$client->pushDown();
		}
	},

	'left' => sub {
		Slim::Buttons::Common::popModeRight( shift );
	},

	'right' => sub {
		my $client = shift;
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Text',
			{
				'callback'	=> \&doSearch,
				'valueRef'	=> \$searchString{$client},
				'header'	=> $client->string( 'PLUGIN_LIVE365_SEARCHPROMPT' ),
				'cursorPos' => 0
			}
		);
	}
);

my $noSearchMode = sub {
	my $client = shift;
};

sub doSearch {
	my $client = shift;
	my $exitType = shift;

	my $arrow = Slim::Display::Display::symbol('rightarrow');
	$searchString{$client} =~ s/$arrow//;

	ExitEventType: {
		$::d_plugins && msg( "Live365.doSearch exit input mode: '$exitType'\n" );

		$exitType =~ /(backspace|cursor_left|delete|scroll_left)/ && do {
			Slim::Buttons::Common::popModeRight( $client );
			return;
			last ExitEventType;
		};

		$exitType =~ /(cursor_right|nextChar|scroll_right)/ && do {
			if( $searchString{$client} eq '' ) {
				$::d_plugins && msg( "Live365.doSearch string empty, returning\n" );
				return;
			}
			$::d_plugins && msg( "Live365.doSearch string: '$searchString{$client}'\n" );
			last ExitEventType;
		};

		$::d_plugins && msg( "Live365.doSearch: unsupported exit '$exitType'\n" );
		return;
	}

	my $stationParams = {
		searchdesc	=> $searchString{$client},
		sort		=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
		searchfields	=> $searchModeItems[$searchModeIdx][1]
	};

	Slim::Buttons::Common::pushModeLeft( $client, 'Live365Channels',
										 { stationParams => $stationParams } );
}

sub searchModeLines {
	my $client = shift;
	my @lines;

	if( my $APImessage = $live365->{$client}->status() ) {
		$lines[0] = $client->string( $APImessage );
		return @lines;
	}

	$lines[0] = $client->string( 'PLUGIN_LIVE365_SEARCH' );
	$lines[1] = $client->string( $searchModeItems[$searchModeIdx][0] );

	$lines[3] = Slim::Hardware::VFD::symbol('rightarrow');

	return @lines;
}

Slim::Buttons::Common::addMode( 'searchMode', \%searchModeFunctions, $setSearchMode, $noSearchMode );

} # end search mode

sub strings {
	return q^PLUGIN_LIVE365_MODULE_NAME
	EN	Live365 Internet Radio
	ES	Radio por Internet Live365

PLUGIN_LIVE365_LOGOUT
	CZ	Odhlásit
	DE	Abmelden
	EN	Log out
	ES	Desconectarse

PLUGIN_LIVE365_LOGIN
	CZ	Přihlásit
	DE	Anmelden
	EN	Log in
	ES	Conectarse

PLUGIN_LIVE365_NOT_LOGGED_IN
	DE	Nicht bei Live365 angemeldet
	EN	Not logged in to Live365
	ES	No se ha ingresado a Live365

PLUGIN_LIVE365_NO_CREDENTIALS
	DE	Keine Live365 Anmeldeinformationen
	EN	No Live365 account information
	ES	No existe información de cuenta para Live365

PLUGIN_LIVE365_LOGIN_SUCCESS
	DE	Erfolgreich
	EN	Successful
	ES	Exitoso

PLUGIN_LIVE365_LOGIN_ERROR_NAME
	DE	Problem mit Anmeldenamen
	EN	Member name problem
	ES	Problema con el nombre de miembro

PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
	CZ	Problém s přihlášením
	DE	Problem beim Anmelden
	EN	Login problem
	ES	Problema de conexión

PLUGIN_LIVE365_LOGIN_ERROR_ACTION
	DE	Unbekannter Vorgang
	EN	Unknown action
	ES	Acción desconocida

PLUGIN_LIVE365_LOGIN_ERROR_ORGANIZATION
	DE	Unbekannte Organisation
	EN	Unknown organization
	ES	Organización desconocida

PLUGIN_LIVE365_LOGIN_ERROR_SESSION
	DE	Sitzung abgelaufen. Bitte neu anmelden.
	EN	Session no longer valid. Log in again.
	ES	La sesión ya no es válida. Conectate nuevamente.

PLUGIN_LIVE365_LOGIN_ERROR_HTTP
	DE	Problem mit Live365 Website. Bitte neu versuchen.
	EN	Live365 website error, try again
	ES	Error del sitio web de Live365, intentar nuevamente

PLUGIN_LIVE365_LOADING_GENRES
	CZ	Stahuji žánry z Live365...
	DE	Genre-Liste wird von Live365 geladen...
	EN	Loading genre list from Live365...
	ES	Cargando la lista de géneros de Live365...

PLUGIN_LIVE365_LOADING_GENRES_ERROR
	CZ	Chyba při stahování stylů. Zkuste to prosím později.
	DE	Fehler beim Laden der Genre-Liste. Bitte neu versuchen.
	EN	Error loading genres, try again
	ES	Error al cargar géneros, intente nuevamente...

PLUGIN_LIVE365_PRESETS
	DE	Meine Voreinstellungen
	EN	My presets
	ES	Mis presets

PLUGIN_LIVE365_BROWSEGENRES
	CZ	Procházeet žánry
	DE	Musikstile durchsuchen
	EN	Browse genres
	ES	Examinar géneros

PLUGIN_LIVE365_BROWSEALL
	CZ	Procházet všechny stanice (mnoho)
	DE	Alle Stationen durchsuchen (viele)
	EN	Browse all stations (many)
	ES	Recorrer todas las estaciones (muchas)

PLUGIN_LIVE365_BROWSEPICKS
	DE	Editor Picks durchsuchen
	EN	Browse editor picks
	ES	Revisar las elegidas por el editor

PLUGIN_LIVE365_BROWSEPROS
	CZ	Procházet profesionální stanice
	DE	Professionelle Stationen durchsuchen
	EN	Browse professional stations
	ES	Recorrer estaciones profesionales

PLUGIN_LIVE365_SEARCH
	DE	Live365 durchsuchen
	EN	Search Live365
	ES	Buscar en Live365

PLUGIN_LIVE365_SEARCHPROMPT
	DE	Live365 durchsuchen nach:
	EN	Search Live365:
	ES	Buscar en Live365:

PLUGIN_LIVE365_LOADING_DIRECTORY
	CZ	Nahrávám...
	DE	Lade...
	EN	Loading...
	ES	Cargando...

PLUGIN_LIVE365_NOSTATIONS
	DE	Keine Station gefunden
	EN	No stations found
	ES	No se encontraron estaciones

PLUGIN_LIVE365_LOADING_INFORMATION
	DE	Senderinformation wird geladen...
	EN	Loading channel information...
	ES	Cargando información de canales...

PLUGIN_LIVE365_DESCRIPTION
	CZ	Popis stanice
	DE	Sender Beschreibung
	EN	Station Description
	ES	Descripción de estación

PLUGIN_LIVE365_STATION_LISTENERS_ACTIVE
	CZ	Aktivních posluchačů
	DE	Aktive Zuhörer
	EN	Active listeners
	ES	Oyentes activos

PLUGIN_LIVE365_STATION_LISTENERS_MAX
	CZ	Maximum posluchačů
	DE	Maximale Anzahl Zuhörer
	EN	Maximum listeners
	ES	Cantidad máxima de oyentes

PLUGIN_LIVE365_LISTENER_ACCESS
	DE	Zuhörer Zugang
	EN	Listener access
	ES	Acceso para oyentes

PLUGIN_LIVE365_STATION_QUALITY_LEVEL
	CZ	Kvalita vysílání stanice
	DE	Sender Qualität
	EN	Station quality
	ES	Calidad de la estación

PLUGIN_LIVE365_STATION_CONNECTION
	DE	Bandbreite
	EN	Bandwidth
	ES	Ancho de Banda

PLUGIN_LIVE365_STATION_CODEC
	EN	Codec
	ES	Codificador

PLUGIN_LIVE365_ERROR
	DE	Live365 Fehler
	EN	Live365 ERROR
	ES	ERROR de Live365

PLUGIN_LIVE365_SEARCH_TAC
	DE	Nach Interpret/Song/Album suchen
	EN	Search Artists/Tracks/CDs
	ES	Buscar Artistas/Canciones/CDs

PLUGIN_LIVE365_SEARCH_A
	DE	Suche Interpret
	EN	Search Artists
	ES	Buscar Artistas

PLUGIN_LIVE365_SEARCH_T
	DE	Suche Song
	EN	Search Tracks
	ES	Buscar Canciones

PLUGIN_LIVE365_SEARCH_C
	DE	Suche Album
	EN	Search Albums
	ES	Buscar Discos

PLUGIN_LIVE365_SEARCH_E
	DE	Nach Sender suchen
	EN	Search Stations
	ES	Buscar estaciones

PLUGIN_LIVE365_SEARCH_L
	DE	Nach Region suchen
	EN	Search Locations
	ES	Buscar Lugares

PLUGIN_LIVE365_SEARCH_H
	DE	Nach Broadcaster suchen
	EN	Search Broadcasters
	ES	Buscar emisoras

SETUP_GROUP_PLUGIN_LIVE365
	EN	Live365 Internet Radio
	ES	Radio por Internet Live365

SETUP_GROUP_PLUGIN_LIVE365_DESC
	CZ	Prohledávat, procházet a ladit stanice Live365
	DE	Suche und höre Live365 Radiostationen
	EN	Search, browse, and tune Live365 stations
	ES	Buscar, recorrer y sintonizar estaciones Live365

SETUP_PLUGIN_LIVE365_USERNAME
	DE	Live365 Benutzername
	EN	Live365 Username
	ES	Usuario de Live365

SETUP_PLUGIN_LIVE365_USERNAME_DESC
	DE	Ihr Live365 Benutzername, besuche live365.com zum Einschreiben
	EN	Your Live365 username, visit live365.com to sign up
	ES	Tu nombre de usuario de Live365,  visitar live365.com para registrarse

SETUP_PLUGIN_LIVE365_PASSWORD
	DE	Live365 Passwort
	EN	Live365 Password
	ES	Contraseña para Live365

SETUP_PLUGIN_LIVE365_PASSWORD_DESC
	DE	Dein Live365 Passwort
	EN	Your Live365 password
	ES	Tu contraseña para Live365

SETUP_PLUGIN_LIVE365_PASSWORD_CHANGED
	DE	Dein Live365 Passwort wurde geändert
	EN	Your Live365 password has been changed
	ES	La contraseña para Live365 ha sido cambiada

SETUP_PLUGIN_LIVE365_SORT_ORDER
	DE	Spalten sortieren
	EN	Sort columns
	ES	Columnas para ordenar

SETUP_PLUGIN_LIVE365_SORT_ORDER_DESC
	DE	Sortierreihenfolge der Sender definieren
	EN	Define the sort order of stations
	ES	Definir la secuencia de ordenamiento para estaciones

SETUP_PLUGIN_LIVE365_SORT_TITLE
	CZ	Název stanice
	DE	Sender Sortierung
	EN	Station title
	ES	Título de la estación

SETUP_PLUGIN_LIVE365_SORT_BPS
	DE	Sender Bitrate
	EN	Station bitrate
	ES	Tasa de bits de la estación

SETUP_PLUGIN_LIVE365_SORT_RATING
	DE	Sender Beurteilung
	EN	Station rating
	ES	Calificación de la estación

SETUP_PLUGIN_LIVE365_SORT_LISTENERS
	DE	Anzahl Hörer
	EN	Number of listeners
	ES	Número de Oyentes

SETUP_PLUGIN_LIVE365_WEB_SHOW_DETAILS
	DE	Detaillierte Live365 Suchresultate
	EN	Detailed Live365 search results
	ES	Resultados detallados de búsqueda en Live365

SETUP_PLUGIN_LIVE365_WEB_SHOW_DETAILS_DESC
	DE	Zeige detaillierte Suchresultate, wenn im Live365 Webinterface gesucht wird. Dies beinhaltet Interpreten, Titel und Albuminformationen wenn nach einem dieser Kriterien gesucht wird. Dies kann die Suchresultate etwas unübersichtlicher machen.
	EN	Show detailed results when searching Live365 through the web interface.  Includes artist, track, and album info when searching for one of these.  May make your search results longer and harder to browse.
	ES	Mostrar resultados detallados cuando se busca en Live365 a través de la interface web. Se incluye información de  artista, canción y disco cuando se busca por alguno de ellos. Esto puede generar resultados más largos y dificiles de recorrer.

PLUGIN_LIVE365_GENRES
	CZ	Styly Live365
	DE	Live365 Musikstile
	EN	Live365 genres
	ES	Géneros de Live365

PLUGIN_LIVE365_STATIONS
	DE	Live365 Sender
	EN	Live365 stations
	ES	Estaciones de Live365

PLUGIN_LIVE365_POPULAR
	DE	Populär
	EN	Popular

PLUGIN_LIVE365_RECENT
	DE	Kürzlich gehört
	EN	Recent
	ES	Reciente

PLUGIN_LIVE365_NO_INFO
	DE	Fehler beim Laden der Informationen
	EN	Error loading info

TACMATCHING
	DE	Passende Interpreten/Titel/Alben
	EN	Tracks/Artists/CDs matching
	ES	Canciones/Artistas/CDs coincidentes

STATIONSMATCHING
	DE	Passende Sender
	EN	Stations matching
	ES	Estaciones coinciden

LOCATIONSMATCHING
	DE	Passende Region
	EN	Locations matching
	ES	Ubicaciones coincidentes

BROADCASTERSMATCHING
	DE	Passende Broadcaster
	EN	Broadcasters matching
	ES	Emisoras coincidentes

PLUGIN_LIVE365_NO_INFO
	DE	Fehler beim Laden der Informationen
	EN	Error loading info
	ES	Error al cargar información

	^;
}

#
# Add web pages and handlers.  See Plugins::Live365::Web for handlers.
#
sub webPages {
	my %pages = (
		"browse\.(?:htm|xml)" => \&Plugins::Live365::Web::handleBrowse,
		"search\.(?:htm|xml)" => \&Plugins::Live365::Web::handleSearch,
		"action\.(?:htm|xml)" => \&Plugins::Live365::Web::handleAction,
		"index\.(?:htm|xml)" => \&Plugins::Live365::Web::handleIndex,
		"loginout\.(?:htm|xml)" => \&Plugins::Live365::Web::handleLogin
	);

	if (grep {$_ eq 'Live365::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages::addLinks("radio", { 'PLUGIN_LIVE365_MODULE_NAME' => undef } );
	} else {
		Slim::Web::Pages::addLinks("radio", { 'PLUGIN_LIVE365_MODULE_NAME' => "plugins/Live365/index.html?autologin=1" } );
	}
	
	return (\%pages, undef);
}

# }}}

1;

# }}}

