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

package Plugins::Live365;

use strict;
use vars qw( $VERSION );
$VERSION = 1.00;

use Slim::Utils::Strings qw( string );
use Slim::Utils::Misc qw( msg );
use Slim::Control::Command;
use Slim::Display::Animation;
use Live365::Live365API 1.00;

my $live365;

sub addMenu {
	return "RADIO";
}

sub getDisplayName {
	return string( 'PLUGIN_LIVE365_MODULE_NAME' );
}

sub strings {
	local $/ = undef;
	<DATA>;
}

sub setupGroup {
	my %Group = (
		PrefOrder => [
			'plugin_live365_username',
			'plugin_live365_password',
			'plugin_live365_sort_order'
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
		'L:D' => string( 'SETUP_PLUGIN_LIVE365_SORT_LISTENERS' )
	);

	my %Prefs = (
		plugin_live365_username => {
			validate => \&Slim::Web::Setup::validateHasText
		},
		plugin_live365_password => { 
			validate => \&Slim::Web::Setup::validateHasText,
			onChange => sub {
				my $encoded = pack( 'u', $_[1]->{plugin_live365_password}->{new} );
				Slim::Utils::Prefs::set( 'plugin_live365_password', $encoded );
			}
		},
		plugin_live365_sort_order => {
			options => \%sort_options
		}
	);

	return( \%Group, \%Prefs );
}

sub playOrAddCurrentStation {
	my $client = shift;
	my $play = shift;

	my $stationURL = $live365->{$client}->getCurrentChannelURL();
	$::d_plugins && msg( "Live365.ChannelMode URL: $stationURL\n" );

	Slim::Music::Info::setContentType($stationURL, 'mp3');
	Slim::Music::Info::setTitle($stationURL, $live365->{$client}->getCurrentStation()->{STATION_TITLE});

	$play and Slim::Control::Command::execute( $client, [ 'playlist', 'clear' ] );
	Slim::Control::Command::execute( $client, [ 'playlist', 'add', $stationURL ] );
	$play and Slim::Control::Command::execute( $client, [ 'play' ] );
}

#############################
# Main mode
# 
MAINMODE: {
my $mainModeIdx = 0;
my @mainModeItems = (
	[ 'Live365Channels', 'PLUGIN_LIVE365_PRESETS' ],
	[ 'searchMode', 'PLUGIN_LIVE365_SEARCH' ],
	[ 'genreMode', 'PLUGIN_LIVE365_BROWSEGENRES' ],
	[ 'Live365Channels', 'PLUGIN_LIVE365_BROWSEPICKS' ],
	[ 'Live365Channels', 'PLUGIN_LIVE365_BROWSEPROS' ],
	[ 'Live365Channels', 'PLUGIN_LIVE365_BROWSEALL' ],
	[ 'loginMode', 'PLUGIN_LIVE365_LOGIN_MODE' ]
);

sub setMode {
	my $client = shift;
	my $entryType = shift;

	$client->lines( \&mainModeLines );

	$live365->{$client} = new Live365::Live365API();

	if( $entryType eq 'push' ) {
		if( my $sessionid = Slim::Utils::Prefs::get( 'plugin_live365_sessionid' ) ) {
			$::d_plugins && msg( "Live365.MainMode using stored session ID: $sessionid\n" );
			$live365->{$client}->setSessionID( $sessionid );
		} else {
			my $userID   = Slim::Utils::Prefs::get( 'plugin_live365_username' );
			my $password = Slim::Utils::Prefs::get( 'plugin_live365_password' );
	
			if( !( $userID and $password ) ) {
				$::d_plugins && msg( "Live365.login: no credentials set\n" );
			} else {
				my $loginStatus = $live365->{$client}->login( $userID, unpack( 'u', $password ) );

				if( $loginStatus == 0 ) {
					$::d_plugins && msg( "Live365 logged in: " . $live365->{$client}->getSessionID() . "\n" );
					Slim::Utils::Prefs::set( 'plugin_live365_sessionid', $live365->{$client}->getSessionID() );
				} else {
					$::d_plugins && msg( "Live365 login error: $loginStatus\n" );
				}
			}
		}
	}

	$client->update();
}

my %mainModeFunctions = (
	'up' => sub {
		my $client = shift;
		$mainModeIdx = Slim::Buttons::Common::scroll(
			$client,
			-1,
			scalar @mainModeItems,
			$mainModeIdx
		);
		$client->update();
	},

	'down' => sub {
		my $client = shift;
		$mainModeIdx = Slim::Buttons::Common::scroll(
			$client,
			1,
			scalar @mainModeItems,
			$mainModeIdx
		);
		$client->update();
	},

	'left' => sub {
		Slim::Buttons::Common::popModeRight( shift );
	},

	'right' => sub {
		my $client = shift;
		$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_DIRECTORY' );
		$client->update();

		my $success = 0;
		SWITCH: {
			$mainModeItems[$mainModeIdx][1] eq 'PLUGIN_LIVE365_PRESETS' && do {
				if( !$live365->{$client}->getSessionID() ) {
					$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_NOT_LOGGED_IN' );
					$client->update();
					sleep 1;
				} else {
					$live365->{$client}->clearStationDirectory();
					$live365->{$client}->loadMemberPresets() and $success = 1;
				}
				last SWITCH;
			};

			$mainModeItems[$mainModeIdx][1] eq 'PLUGIN_LIVE365_BROWSEALL' && do {
				$live365->{$client}->clearStationDirectory();
				$live365->{$client}->loadStationDirectory(
					sort			=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
					searchfields	=> Slim::Utils::Prefs::get( 'plugin_live365_search_fields' )
				) and $success = 1;
				last SWITCH;
			};

			$mainModeItems[$mainModeIdx][1] eq 'PLUGIN_LIVE365_BROWSEPICKS' && do {
				$live365->{$client}->clearStationDirectory();
	  			$live365->{$client}->loadStationDirectory(
					sort			=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
					searchfields	=> Slim::Utils::Prefs::get( 'plugin_live365_search_fields' ),
					genre 			=> 'ESP'
				) and $success = 1;
				last SWITCH;
			};

			$mainModeItems[$mainModeIdx][1] eq 'PLUGIN_LIVE365_BROWSEPROS' && do {
				$live365->{$client}->clearStationDirectory();
				$live365->{$client}->loadStationDirectory(
					sort			=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
					searchfields	=> Slim::Utils::Prefs::get( 'plugin_live365_search_fields' ),
					genre			=> 'Pro'
				) and $success = 1;
				last SWITCH;
			};

			$success = 1;
		}
		$live365->{$client}->clearBlockingStatus();
		$client->update();

		if( $success ) {
			Slim::Buttons::Common::pushModeLeft( $client, $mainModeItems[$mainModeIdx][0] );
		}
	}
);

sub mainModeLines {
	my $client = shift;
	my @lines;

	if( my $APImessage = $live365->{$client}->status() ) {
		$lines[0] = string( $APImessage );
		return @lines;
	}

	$lines[0] = string( 'PLUGIN_LIVE365_MODULE_NAME' );
	$lines[1] = string( $mainModeItems[$mainModeIdx][1] );

	$lines[3] = Slim::Hardware::VFD::symbol('rightarrow');

	return @lines;
}

sub getFunctions {
	return \%mainModeFunctions;
}

} # end main mode


#############################
# Login mode
#
LOGINMODE: {
my $loginModeOk = 0;
my $loginModeIdx = 0;
my @loginModeItems = (
	'PLUGIN_LIVE365_LOGIN', 
	'PLUGIN_LIVE365_LOGOUT'
);

my $setLoginMode = sub {
	my $client = shift;
	$client->lines( \&loginModeLines );

	my $userID   = Slim::Utils::Prefs::get( 'plugin_live365_username' );
	my $password = Slim::Utils::Prefs::get( 'plugin_live365_password' );

	if( !( $userID and $password ) ) {
		$::d_plugins && msg( "Live365.login: no credentials set\n" );
		$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_NO_CREDENTIALS' );
	} else {
		$::d_plugins && msg( "Live365.login: ok\n" );
		$loginModeOk = 1;
		$live365->{$client}->clearBlockingStatus();
	}

	$loginModeIdx = 0;
};

my $noLoginMode = sub {
	my $client = shift;
};

my %loginModeFunctions = (
	'up' => sub {
		my $client = shift;
		$loginModeIdx = Slim::Buttons::Common::scroll(
			$client,
			-1,
			scalar @loginModeItems,
			$loginModeIdx
		);
		$client->update();
	},

	'down' => sub {
		my $client = shift;
		$loginModeIdx = Slim::Buttons::Common::scroll(
			$client,
			1,
			scalar @loginModeItems,
			$loginModeIdx
		);
		$client->update();
	},

	'left' => sub {
		Slim::Buttons::Common::popModeRight( shift );
	},

	'right' => sub {
		my $client = shift;

		return unless $loginModeOk;

		my @statusText = qw(
			PLUGIN_LIVE365_LOGIN_SUCCESS
			PLUGIN_LIVE365_LOGIN_ERROR_NAME
			PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
			PLUGIN_LIVE365_LOGIN_ERROR_ACTION
			PLUGIN_LIVE365_LOGIN_ERROR_ORGANIZATION
			PLUGIN_LIVE365_LOGIN_ERROR_SESSION
			PLUGIN_LIVE365_LOGIN_ERROR_HTTP
		);

		$loginModeItems[ $loginModeIdx ] eq 'PLUGIN_LIVE365_LOGIN'  && do {
			$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOGGING_IN' );
			$client->update();

			my $loginStatus = $live365->{$client}->login(
				Slim::Utils::Prefs::get( 'plugin_live365_username' ),
 				unpack( 'u', Slim::Utils::Prefs::get( 'plugin_live365_password' ) )
			);

			if( $loginStatus == 0 ) {
				$::d_plugins && msg( "Live365 logged in: " . $live365->{$client}->getSessionID() . "\n" );
				Slim::Utils::Prefs::set( 'plugin_live365_sessionid', $live365->{$client}->getSessionID() );
				Slim::Display::Animation::showBriefly( $client, string( $statusText[ $loginStatus ] ) );
			} else {
				$::d_plugins && msg( "Live365 login error: $loginStatus\n" );
				Slim::Display::Animation::showBriefly( $client, string( $statusText[ $loginStatus ] ) );
			}
		};

		$loginModeItems[ $loginModeIdx ] eq 'PLUGIN_LIVE365_LOGOUT' && do {
			$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOGGING_OUT' );
			$client->update();

			my $logoutStatus = $live365->{$client}->logout();
			if( $logoutStatus == 0 ) {
				$::d_plugins && msg( "Live365 logged out\n" );
				Slim::Utils::Prefs::set( 'plugin_live365_sessionid', '' );
				Slim::Display::Animation::showBriefly( $client, string( $statusText[ $logoutStatus ] ) );
			} else {
				$::d_plugins && msg( "Live365 logout error: $logoutStatus\n" );
				Slim::Display::Animation::showBriefly( $client, string( $statusText[ $logoutStatus ] ) );
			}
		};

		sleep 1;

		$live365->{$client}->clearBlockingStatus();
		$client->update();
	}
);

sub loginModeLines {
	my $client = shift;
	my @lines;

	if( my $APImessage = $live365->{$client}->status() ) {
		$lines[0] = string( $APImessage );
		return @lines;
	}

	my $sessionID = Slim::Utils::Prefs::get( 'plugin_live365_sessionid' );
	if( $sessionID ) {
		$lines[0] = sprintf(
			string( 'PLUGIN_LIVE365_LOGIN_HEADER' ), 
			( split( /:/, $sessionID ) )[0]
		);
	} else {
		$lines[0] = string( 'PLUGIN_LIVE365_NOT_LOGGED_IN' );
	}

	$lines[1] = string( $loginModeItems[ $loginModeIdx ] );

	$lines[3] = Slim::Hardware::VFD::symbol('rightarrow');

	return @lines;
}

Slim::Buttons::Common::addMode( 'loginMode', \%loginModeFunctions, $setLoginMode, $noLoginMode );

} # end login mode


#############################
# Genre mode
#
my @genreList = ();
my $genrePointer = 0;

GENREMODE: {
my $setGenreMode = sub {
	my $client = shift;
	$client->lines( \&GenreModeLines );

	$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_GENRES' );
	$client->update();

	@genreList = $live365->{$client}->loadGenreList();

	if (! @genreList) {
		Slim::Display::Animation::showBriefly( $client, string( 'PLUGIN_LIVE365_LOGIN_ERROR_HTTP' ), ' ' );
		Slim::Buttons::Common::popModeRight( shift );
	}

	$live365->{$client}->clearBlockingStatus();
	$client->update();
};

my $noGenreMode = sub {
	my $client = shift;
};

my %genreModeFunctions = (
	'up' => sub {
		my $client = shift;
		$genrePointer = Slim::Buttons::Common::scroll(
			$client,
			-1,
			scalar @genreList,
			$genrePointer
		);
		$client->update();
	},

	'down' => sub {
		my $client = shift;
		$genrePointer = Slim::Buttons::Common::scroll(
			$client,
			1,
			scalar @genreList,
			$genrePointer
		);
		$client->update();
	},

	'left' => sub {
		Slim::Buttons::Common::popModeRight( shift );
	},

	'right' => sub {
		my $client = shift;
		$live365->{$client}->setStationListPointer( 0 );
		$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_DIRECTORY' );
		$client->update();

		$live365->{$client}->clearStationDirectory();
		my $loaded = $live365->{$client}->loadStationDirectory(
			genre			=> $genreList[ $genrePointer ][1],
			sort			=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
			searchfields	=> Slim::Utils::Prefs::get( 'plugin_live365_search_fields' )
		);

 		if( $loaded ) {
			Slim::Buttons::Common::pushModeLeft( $client, 'Live365Channels' );
		} else {
			$::d_plugins && msg( "No stations for genre: " . $genreList[ $genrePointer ][0] . "\n" );
			Slim::Display::Animation::showBriefly( $client, string( 'PLUGIN_LIVE365_NOSTATIONS' ), ' ' );
			sleep 1;
		}

		$live365->{$client}->clearBlockingStatus();
		$client->update();
	}
);

sub GenreModeLines {
	my $client = shift;
	my @lines = ();

	if( my $APImessage = $live365->{$client}->status() ) {
		$lines[0] = string( $APImessage );
		return @lines;
	}

	$lines[0] = sprintf( "%s (%d %s %d)",
		string( 'PLUGIN_LIVE365_GENRES' ),
		$genrePointer + 1,
		string( 'OF' ),
		scalar @genreList
	);
	$lines[1] = $genreList[ $genrePointer ][0];
	$lines[3] = Slim::Hardware::VFD::symbol('rightarrow');

	return @lines;
}

Slim::Buttons::Common::addMode( 'genreMode', \%genreModeFunctions, $setGenreMode, $noGenreMode );

} # end genre mode


#############################
# Channel mode
#
CHANNELMODE: {
my $setChannelMode = sub {
	my $client = shift;

	$client->lines( \&channelModeLines );
};

my $noChannelMode = sub {
	my $client = shift;
};

my %channelModeFunctions = (
    'up' => sub {
        my $client = shift;

		# Since we haven't necessarially loaded out to the end of the list yet, 
		# we can't wrap around from the top. This will be addressed in a later
		# version.
		if( $live365->{$client}->getStationListPointer() == 0 ) {
			Slim::Display::Animation::bumpUp( $client );
			return;
		}

		$live365->{$client}->setStationListPointer( Slim::Buttons::Common::scroll(
            $client,
            -1,
            $live365->{$client}->getStationListLength(),
            $live365->{$client}->getStationListPointer()
        ) );

        $client->update();
    },

    'down' => sub {
        my $client = shift;
		
        my $newStationPointer = Slim::Buttons::Common::scroll(
            $client,
            1,
            $live365->{$client}->getStationListLength(),
            $live365->{$client}->getStationListPointer()
        );

		if( $live365->{$client}->willRequireLoad( $newStationPointer ) ) {
			$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_DIRECTORY' );
			$client->update();
        	$live365->{$client}->setStationListPointer( $newStationPointer );
			$live365->{$client}->clearBlockingStatus();
		} else {
        	$live365->{$client}->setStationListPointer( $newStationPointer );
		}

        $client->update();
    },

    'left' => sub {
        Slim::Buttons::Common::popModeRight( shift );
    },

	'right' => sub {
		Slim::Buttons::Common::pushModeLeft( shift, 'ChannelInfo' );
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

sub channelModeLines {
	my $client = shift;
	my @lines = ();

	if( my $APImessage = $live365->{$client}->status() ) {
		$lines[0] = string( $APImessage );
		return @lines;
	}

	if( $live365->{$client}->getStationListLength() > 0 ) {
		$lines[0] = sprintf( "%s (%d %s %d)",
			string( 'PLUGIN_LIVE365_STATIONS' ),
			$live365->{$client}->getStationListPointer() + 1,
			string( 'OF' ),
			$live365->{$client}->getStationListLength()
		);

		$lines[1] = $live365->{$client}->getCurrentStation()->{STATION_TITLE};
		$lines[3] = Slim::Hardware::VFD::symbol('rightarrow');
	} else {
		$lines[0] = string( 'PLUGIN_LIVE365_NOSTATIONS' );
	}

	return @lines;
}

Slim::Buttons::Common::addMode( 'Live365Channels', \%channelModeFunctions, $setChannelMode, $noChannelMode );

} # end channel mode


#############################
# Information mode
#
INFOMODE: {
my @infoItems = ();
my $infoItem = 0;

my $setInfoMode = sub {
	my $client = shift;
	$client->lines( \&infoModeLines );

	$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_INFORMATION' );
	$client->update();

	$live365->{$client}->loadInfoForStation( $live365->{$client}->getCurrentStation()->{STATION_ID} ) or
		Slim::Buttons::Common::popModeRight( $client );

	@infoItems = $live365->{$client}->getStationInfo();
	# unshift @infoItems, [ 'DESCRIPTION', $live365->{$client}->getStationInfoString( 'STATION_DESCRIPTION' ) ];

	$live365->{$client}->clearBlockingStatus();
	$client->update();

	$infoItem = 0;
};

my $noInfoMode = sub {
	my $client = shift;
};

my %infoModeFunctions = (
	'up' => sub {
		my $client = shift;
		$infoItem = Slim::Buttons::Common::scroll(
			$client,
			-1,
			scalar @infoItems,
			$infoItem
		);
		$client->update();
	},

	'down' => sub {
		my $client = shift;
		$infoItem = Slim::Buttons::Common::scroll(
			$client,
			1,
			scalar @infoItems,
			$infoItem
        );
		$client->update()
	},

	'left' => sub {
		Slim::Buttons::Common::popModeRight( shift );
	},

	'right' => sub {
		Slim::Display::Animation::bumpRight( shift );
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

sub infoModeLines {
	my $client = shift;
	my @lines;

	if( my $APImessage = $live365->{$client}->status() ) {
		$lines[0] = string( $APImessage );
		return @lines;
	}

	$lines[0] = $live365->{$client}->getStationInfoString( 'STATION_TITLE' );

	$lines[1] = sprintf( "%s: %s",
		string( 'PLUGIN_LIVE365_' . $infoItems[ $infoItem ]->[0] ),
		$infoItems[ $infoItem ]->[1]
	);

	return @lines;
}

Slim::Buttons::Common::addMode( 'ChannelInfo', \%infoModeFunctions, $setInfoMode, $noInfoMode );

} # end info mode

#############################
#
# Search mode
#
SEARCHMODE: { 

my %searchString;

my @searchModeItems = (
	[ 'PLUGIN_LIVE365_SEARCH_TAC', 'T:A:C' ],
	[ 'PLUGIN_LIVE365_SEARCH_A', 'A' ],
	[ 'PLUGIN_LIVE365_SEARCH_T', 'T' ],
	[ 'PLUGIN_LIVE365_SEARCH_C', 'C' ],
	[ 'PLUGIN_LIVE365_SEARCH_E', 'E' ],
	[ 'PLUGIN_LIVE365_SEARCH_L', 'L' ],
	[ 'PLUGIN_LIVE365_SEARCH_H', 'H' ]
);

my $searchModeIdx = 0;

my $setSearchMode = sub {
	my $client = shift;

	$client->lines( \&searchModeLines );

	$searchString{$client} = '';
};

my %searchModeFunctions = (
	'up' => sub {
		my $client = shift;
		$searchModeIdx = Slim::Buttons::Common::scroll(
			$client,
			-1,
			scalar @searchModeItems,
			$searchModeIdx
		);
		$client->update();
	},

	'down' => sub {
		my $client = shift;
		$searchModeIdx = Slim::Buttons::Common::scroll(
			$client,
			1,
			scalar @searchModeItems,
			$searchModeIdx
		);
		$client->update();
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
				'header'	=> string( 'PLUGIN_LIVE365_SEARCHPROMPT' ),
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

	# callback runs in the INPUT.Text mode, so setBlockingStatus is irrelevant unless we reassign.
	my $oldLineFunc = $client->lines();
	$client->lines( \&searchModeLines );

	$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_DIRECTORY' );
	$client->update();

	$live365->{$client}->clearStationDirectory();
	$live365->{$client}->loadStationDirectory(
		searchdesc	=> $searchString{$client},
		sort		=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
		searchfields	=> $searchModeItems[$searchModeIdx][1]
	);

	$live365->{$client}->clearBlockingStatus();
	$client->update();

	$client->lines( $oldLineFunc );
	$client->update();

	Slim::Buttons::Common::pushModeLeft( $client, 'Live365Channels' );
}

sub searchModeLines {
	my $client = shift;
	my @lines;

	if( my $APImessage = $live365->{$client}->status() ) {
		$lines[0] = string( $APImessage );
		return @lines;
	}

	$lines[0] = string( 'PLUGIN_LIVE365_SEARCH' );
	$lines[1] = string( $searchModeItems[$searchModeIdx][0] );

	$lines[3] = Slim::Hardware::VFD::symbol('rightarrow');

	return @lines;
}

Slim::Buttons::Common::addMode( 'searchMode', \%searchModeFunctions, $setSearchMode, $noSearchMode );

} # end search mode

1;

__DATA__
PLUGIN_LIVE365_MODULE_NAME
	EN	Live365

PLUGIN_LIVE365_LOGIN_MODE
	EN	Manage your Live365 session

PLUGIN_LIVE365_LOGIN
	EN	Log in to Live365

PLUGIN_LIVE365_LOGOUT
	EN	Log out from Live365

PLUGIN_LIVE365_LOGIN_HEADER
	EN	Logged on to Live365 as %s

PLUGIN_LIVE365_NOT_LOGGED_IN
	EN	Not logged in to Live365

PLUGIN_LIVE365_LOGGING_IN
	EN	Logging in to Live365...

PLUGIN_LIVE365_LOGGING_OUT
	EN	Logging out from Live365...

PLUGIN_LIVE365_NO_CREDENTIALS
	EN	No Live365 account information

PLUGIN_LIVE365_LOGIN_SUCCESS
	EN	Live365 operation successful

PLUGIN_LIVE365_LOGIN_ERROR_NAME
	EN	Live365 member name problem

PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
	EN	Live365 login problem

PLUGIN_LIVE365_LOGIN_ERROR_ACTION
	EN	Live365 unknown action

PLUGIN_LIVE365_LOGIN_ERROR_ORGANIZATION
	EN	Live365 unknown organization

PLUGIN_LIVE365_LOGIN_ERROR_SESSION
	EN	Live365 session no longer valid

PLUGIN_LIVE365_LOGIN_ERROR_HTTP
	EN	Live365 website error, try again

PLUGIN_LIVE365_LOADING_GENRES
	EN	Loading genre list from Live365...

PLUGIN_LIVE365_LOADING_GENRES_ERROR
	EN	Error loading genres, try again

PLUGIN_LIVE365_PRESETS
	EN	Browse your Live365 presets

PLUGIN_LIVE365_BROWSEGENRES
	EN	Browse Live365 by genre

PLUGIN_LIVE365_BROWSEALL
	EN	Browse all Live365 stations (many)

PLUGIN_LIVE365_BROWSEPICKS
	EN	Browse Live365 Editor Station Picks

PLUGIN_LIVE365_BROWSEPROS
	EN	Browse Live365 Professional stations

PLUGIN_LIVE365_SEARCH
	EN	Search Live365 stations

PLUGIN_LIVE365_SEARCHPROMPT
	EN	Enter search term:

PLUGIN_LIVE365_LOADING_DIRECTORY
	EN	Loading directory list from Live365...

PLUGIN_LIVE365_NOSTATIONS
	EN	Live365 returned no stations

PLUGIN_LIVE365_LOADING_INFORMATION
	EN	Loading channel information...

PLUGIN_LIVE365_DESCRIPTION
	EN	Description

PLUGIN_LIVE365_STATION_LISTENERS_ACTIVE
	EN	Active listeners

PLUGIN_LIVE365_STATION_LISTENERS_MAX
	EN	Maximum listeners

PLUGIN_LIVE365_LISTENER_ACCESS
	EN	Listener access

PLUGIN_LIVE365_STATION_QUALITY_LEVEL
	EN	Station quality

PLUGIN_LIVE365_STATION_CONNECTION
	EN	Bandwidth

PLUGIN_LIVE365_STATION_CODEC
	EN	Codec

PLUGIN_LIVE365_ERROR
	EN	Live365 ERROR

PLUGIN_LIVE365_SEARCH_TAC
	EN	Search Artists/Tracks/CDs

PLUGIN_LIVE365_SEARCH_A
	EN	Search Artists

PLUGIN_LIVE365_SEARCH_T
	EN	Search Tracks

PLUGIN_LIVE365_SEARCH_C
	EN	Search CDs

PLUGIN_LIVE365_SEARCH_E
	EN	Search Live365 stations

PLUGIN_LIVE365_SEARCH_L
	EN	Search Live365 locations

PLUGIN_LIVE365_SEARCH_H
	EN	Search Live365 broadcasters

SETUP_GROUP_PLUGIN_LIVE365
	EN	Live365 - The World's Largest Internet Radio Network

SETUP_GROUP_PLUGIN_LIVE365_DESC
	EN	Search, browse, and tune Live365 stations

SETUP_PLUGIN_LIVE365_USERNAME
	EN	Live365 username

SETUP_PLUGIN_LIVE365_USERNAME_DESC
	EN	Your Live365 username, visit live365.com to sign up

SETUP_PLUGIN_LIVE365_PASSWORD
	EN	Live365 password

SETUP_PLUGIN_LIVE365_PASSWORD_DESC
	EN	Your Live365 password

SETUP_PLUGIN_LIVE365_SORT_ORDER
	EN	Sort columns

SETUP_PLUGIN_LIVE365_SORT_ORDER_DESC
	EN	Define the sort order of stations

SETUP_PLUGIN_LIVE365_SORT_TITLE
	EN	Station title

SETUP_PLUGIN_LIVE365_SORT_BPS
	EN	Station bitrate

SETUP_PLUGIN_LIVE365_SORT_RATING
	EN	Station rating

SETUP_PLUGIN_LIVE365_SORT_LISTENERS
	EN	Number of listeners

PLUGIN_LIVE365_GENRES
	EN	Live365 genres

PLUGIN_LIVE365_STATIONS
	EN	Live365 stations

PLUGIN_LIVE365_POPULAR
	EN	Popular

PLUGIN_LIVE365_RECENT
	EN	Recent

__END__
