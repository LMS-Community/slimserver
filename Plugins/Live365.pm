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

# {{{ Plugins::Live365::Live365API 

package Plugins::Live365::Live365API;

use strict;
use vars qw( $VERSION );
$VERSION = 1.10;

use XML::Simple;
use IO::Socket;

sub new {
	my $class = shift;  
	my $self  = {
		member_name		=> '',
		password		=> '',
		sessionid		=> '',
		DirectoryLoaded	=> 0,
		GenresLoaded	=> 0,
		stationPointer	=> 0,
		genrePointer	=> 0,
		reqBatch		=> 1,
		status			=> 0,
		@_
	};

	bless $self, $class;

	return $self;
}


sub setBlockingStatus {
	my $self = shift;
	my $status = shift;

	$self->{status} = $status;
}

sub clearBlockingStatus {
	my $self = shift;

	$self->{status} = undef;
}

sub status {
	my $self = shift;

	return $self->{status};
}


#############################
# Web functions
#
sub httpRequest {
	my $self = shift;
	my $url  = shift;
	my $args = shift;
	my $response;

	my $proxy = Slim::Utils::Prefs::get('webproxy');
	my $peeraddr = 'www.live365.com';
	if ($proxy) {
		$peeraddr = $proxy;
		$url = "http://www.live365.com$url";
	}

	my $socket = new IO::Socket::INET(
		PeerAddr	=> $peeraddr,
		PeerPort	=> 80,
		Proto		=> 'tcp',
		Type		=> SOCK_STREAM
	) or return undef;

	my $stringArgs = join( '&', map { "$_=$args->{$_}" } grep { $args->{$_} } keys %$args );
	$url .= "?$stringArgs" if( $stringArgs );
	my $getRequest = "GET $url HTTP/1.0\n\n";

	print $socket $getRequest;
	{
		local $/ = undef;
		$response = <$socket>;
	}
	$response =~ s/\015?\012/\n/g;

	close $socket;

	my ( $headers, $content ) = split( /\n\n/, $response, 2 );

	if( $headers !~ /^HTTP\/1.. 200 OK/ ) {
		$content = undef;
	}

	return wantarray ? ( $headers, $content ) : $content; 
}


#############################
# Protocol handler functions
#
sub getRedirectURL {
    my $self = shift;
    my $url  = shift;

    my( $headers, $content ) = $self->httpRequest( $url );

    $headers =~ /^HTTP\/1\.\d 302/ or return undef;
    my( $redir ) = $headers =~ /Location: (.+)/ or return undef;

    return $redir;
}

sub GetLive365Playlist {
    my $self   = shift;
    my $isVIP  = shift;
    my $handle = shift;

    my %args = (
        handler  => 'playlist',
        cmd      => 'view',
        handle   => $isVIP ? "afl:$handle" : $handle,
        viewType => 'xml'
    );

    my( $headers, $playlist ) = $self->httpRequest( '/pls/front', \%args );

    return $playlist;
}


#############################
# Login functions
#
sub login {
	my $self = shift;
	my ( $username, $password ) = @_;

	my %args = (
		action		=> 'login',
		remember	=> 'Y',
		org			=> 'live365',
		member_name	=> $username,
		password	=> $password
	);

	my $xmlResponse = $self->httpRequest( '/cgi-bin/api_login.cgi', \%args );
	if( !defined $xmlResponse ) {
		return 6;  # PLUGIN_LIVE365_LOGIN_ERROR_HTTP
	}

	eval '$self->{Login} = XMLin( $xmlResponse )'; 
	return 2 if $@; # PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
	
	$self->{sessionid} = $self->{Login}->{Session_ID};
	$self->{vip} = $self->{Login}->{Member_Status} eq 'PREFERRED';

	return $self->{Login}->{Code};
}

sub logout {
	my $self = shift;

	if( !$self->{sessionid} ) {
		return 1;
	}

	my %args = (
		action		=> 'logout',
		sessionid	=> $self->{sessionid},
		org			=> 'live365'
	);

	my $xmlResponse = $self->httpRequest( '/cgi-bin/api_login.cgi', \%args ); 
	if( !defined $xmlResponse ) {
		return 6;  # PLUGIN_LIVE365_LOGIN_ERROR_HTTP
	}

	eval '$self->{Logout} = XMLin( $xmlResponse )'; 
	return 2 if $@; # PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
	
	$self->{sessionid} = undef;

	return $self->{Logout}->{Code};
}

sub getSessionID {
	my $self = shift;

	return $self->{sessionid};
}
sub isLoggedIn {
	my $self = shift;

	return defined( $self->{loggedin} ) && $self->{loggedin} == 1;
}

sub setLoggedIn {
	my $self = shift;
	my $val  = shift;

	return $self->{loggedin} = $val;
}


sub setSessionID {
	my $self = shift;

	$self->{sessionid} = shift;
}

sub getMemberStatus {
	my $self = shift;

	return $self->{vip};
}


#############################
# Genre functions 
#
sub loadGenreList {
	my $self = shift;

	# If we've already loaded the genres, don't do it again.
	if( defined( $self->{Genres}->{Code} ) && $self->{Genres}->{Code} == 0 ) {
		return @{ $self->{GenreList} };
	}

	my %args = (
		format => 'xml'
	);

	my $xmlGenres = $self->httpRequest( '/cgi-bin/api_genres.cgi', \%args );

	return undef if !defined $xmlGenres;

	eval '$self->{Genres} = XMLin( $xmlGenres )'; 
	return undef if $@;

	# Build full display names for genres that list a Parent_ID
	# (...and I'm happy I get to use an Orcish maneuver, it's a geek thing)
	my %parentNameCache = ();
	my @tmpGenres = @{ $self->{Genres}->{Genres}->{Genre} };
	foreach my $g ( @tmpGenres ) {
		if ( $g->{Parent_ID} != 0 ) {
			my $baseName = $parentNameCache{ $g->{Parent_ID} }
				||= ( grep { $g->{Parent_ID} == $_->{ID} } @tmpGenres )[0]->{Display_Name};
			$g->{Display_Name} = "$baseName $g->{Display_Name}";
		}

		push @{ $self->{GenreList} }, [ $g->{Display_Name}, $g->{Name} ];
	}

	return @{ $self->{GenreList} };
}


#############################
# Station preset functions
#
sub loadMemberPresets {
	my $self = shift;

	my %args = (
		action		=> "get",
		sessionid	=> $self->{sessionid},
		device_id	=> "UNKNOWN",
		app_id		=> "live365:BROWSER",
		first		=> 1,
		rows		=> 200,
		access		=> "ALL",
		format		=> "xml"
	);

	my $xmlPresets = $self->httpRequest( '/cgi-bin/api_presets.cgi', \%args );
	if( !defined $xmlPresets ) {
		return undef;
	}

	eval '$self->{Directory} = XMLin( $xmlPresets, forcearray => [ "LIVE365_STATION" ] )';
	return undef if $@;
	
	if( defined $self->{Directory}->{LIVE365_STATION} ) {
		push @{ $self->{Stations} }, @{ $self->{Directory}->{LIVE365_STATION} };
	} else {
		$self->{Directory}->{LIVE365_STATION} = [];
	}

	return scalar @{ $self->{Directory}->{LIVE365_STATION} } > 0;
}


#############################
# Station functions
#
sub loadStationDirectory {
	my $self = shift;

	my %args = (
		site		=> "xml",		# requests the data in XML format
		access		=> "ALL",		# "ALL:PUBLIC:PRIVATE:NONE"
		clienttype	=> 0,			# 3rd party MP3 player
		first		=> 1,			# first row to print
		rows		=> 50,			# number of rows to print, default 25, max 200
		genre		=> "All",		# Limit display to these genres
		maxspeed	=> 256,			# max bitrate to include
		minspeed	=> 0,			# min bitrate to include
		quality		=> 0,			# AM (0-99), FM (100-199), CD (200+)
		only		=> "",			# "E:I:L:O:R:S:X" only include stations with these attribs
		searchdesc	=> "",			# search term to look for
		searchgenre	=> "All",		# genre restriction when searching
		searchfields=> "T:A:C",		# "K:E:D:G:H:T:A:C:F:L:I:S", fields for searchdesc
		sort		=> "L:D;R:D",	# "T|D|C|G|R|L|H:U|D;<2>;<3>"
		source		=> "Live365:RdRunnder:BT",
		tag			=> "",
		text		=> "",
		@_
	);

	my $xmlDirectory = $self->httpRequest( '/cgi-bin/directory.cgi', \%args );
	if( !defined $xmlDirectory ) {
		return undef;
	}

	eval '$self->{Directory} = XMLin( $xmlDirectory, forcearray => [ "LIVE365_STATION" ] )';
	return undef if $@;
	
	if( defined $self->{Directory}->{LIVE365_STATION} ) {
		push @{ $self->{Stations} }, @{ $self->{Directory}->{LIVE365_STATION} };
	} else {
		$self->{Directory}->{LIVE365_STATION} = [];
	}

	return scalar @{ $self->{Directory}->{LIVE365_STATION} } > 0;
}

sub clearStationDirectory {
	my $self = shift;

	$self->{Stations} = [];
}


sub getCurrentStation {
	my $self = shift;

    if( defined( my $current = $self->{Stations}->[$self->{stationPointer}] ) ) {
		return $current;
	} else {
		return undef;
	}

	# return $self->{Stations}->[$self->{stationPointer}];
}


sub getStationListPointer {
	my $self = shift;

	return $self->{stationPointer};
}

sub willRequireLoad {
	my $self = shift;
	my $req  = shift;

	return ( $req > $#{ $self->{Stations} } &&
			 $self->{Directory}->{LIVE365_DIRECTORY_FILTERS}->{DIRECTORY_MORE_ROWS_AVAILABLE} );
}

sub setStationListPointer { 
	my $self = shift;
	my $req  = shift;

	if( $req > $#{ $self->{Stations} } && $self->{Directory}->{LIVE365_DIRECTORY_FILTERS}->{DIRECTORY_MORE_ROWS_AVAILABLE} ) {
		$self->loadStationDirectory( first => scalar @{ $self->{Stations} } );
	}

	$self->{stationPointer} = $req;
}

sub getStationListLength {
	my $self = shift;

	return $self->{Directory}->{LIVE365_DIRECTORY_FILTERS}->{DIRECTORY_ROWS_RETURNED};
}

sub getChannelModePointer {
	my $self = shift;
	my $mode = shift;

	return $self->{modePointer}->{$mode};
}

sub setChannelModePointer {
	my $self = shift;
	my $mode = shift;
	my $pointer = shift;

	$self->{modePointer}->{$mode} = $pointer;
}

sub findChannelStartingWith {
	# Very, very slow for long search spaces.
	my $self = shift;
	my $startsWith = lc shift;

	my $thisChannel = $self->getCurrentStation();;

	# Only reset the entire channel list if we might already be past the title we want.
	if( ( $startsWith cmp lc substr( $thisChannel->{STATION_TITLE}, 0, 1 ) ) <= 0 ) {
		$self->resetChannelList();
	}

	# Scan the channel list until we either find a channel or pass it's spot.
	while( $thisChannel = $self->getNextChannelRecord() ) {
		if( ( $startsWith cmp lc substr( $thisChannel->{STATION_TITLE}, 0, 1 ) ) == 0 ) {
			return $thisChannel;
		}
	}
	return undef;
}


sub getCurrentChannelURL {
	my $self = shift;

	my $url = $self->{Stations}->[$self->{stationPointer}]->{STATION_ADDRESS};
	$url =~ s/^http:/live365:/;
	if( $self->{sessionid} ) {
		$url .= '?sessionid=' . $self->{sessionid};
	}

	return $url;
}


#############################
# Information functions
#
sub loadInfoForStation {
	my $self = shift;
	my $stationID = shift;

	return 1 if( defined $self->{currentStationInfo} && $stationID == $self->{currentStationInfo} );

	my %args = (
		format	=> 'xml',
		in		=> 'STATIONS',
		channel	=> $stationID
	); 

	my $xmlInfo = $self->httpRequest( '/cgi-bin/station_info.cgi', \%args );
	if( !defined $xmlInfo ) {
		return undef;
	}

	eval '$self->{StationInfo} = XMLin( $xmlInfo )';
	return undef if $@;
	
	$self->{currentStationInfo} = $stationID;

    return defined $self->{StationInfo}->{LIVE365_STATION};
}

sub getStationInfo {
	my $self = shift;

	my @infoItems = (
		[ 'STATION_LISTENERS_ACTIVE' ],
		[ 'STATION_LISTENERS_MAX' ],
		[ 'LISTENER_ACCESS' ],
		[ 'STATION_QUALITY_LEVEL' ],
		[ 'STATION_CONNECTION' ],
		[ 'STATION_CODEC' ]
	);

	# Convert quality levels to a canonical phrase
	my $quality = \$self->{StationInfo}->{LIVE365_STATION}->{STATION_QUALITY_LEVEL};
	QUALITY: {
		last QUALITY if( $$quality =~ /AM|FM|CD/ );
		$$quality >= 0 && $$quality <= 99 && do {
			$$quality = 'AM radio';
			last QUALITY;
		};

		$$quality >= 100 && $$quality <=199 && do {
			$$quality = 'FM radio';
			last QUALITY;
		};

		$$quality >= 200 && do {
			$$quality = 'CD';
			last QUALITY;
		}; 
	}

	foreach my $item ( @infoItems ) {
		$item->[1] = $self->{StationInfo}->{LIVE365_STATION}->{ $item->[0] };
	}

	return @infoItems;
}

sub getStationInfoString {
	my $self = shift;
	my $infoString = shift;

	return $self->{StationInfo}->{LIVE365_STATION}->{$infoString};
}

1;

# }}}

#  Plugins::Live365::ProtocolHandler

package Plugins::Live365::ProtocolHandler;

use strict;
use Slim::Utils::Misc qw( msg );
use Slim::Utils::Timers;
use Slim::Player::Playlist;
use Slim::Player::Source;
use base qw( Slim::Player::Protocols::HTTP );
use IO::Socket;
use XML::Simple;
use vars qw( $VERSION );
$VERSION = 1.10;

sub new {
	my $class = shift;
	my $args = shift;
	
	my $url = $args->{'url'};
	my $client = $args->{'client'};
	my $self = $args->{'self'};

	my $api = new Plugins::Live365::Live365API();

	if( my( $station, $handle ) = $url =~ m{^live365://(www.live365.com/play/([^/?]+).+)$} ) {
		$::d_plugins && msg( "Live365.protocolHandler requested: $url ($handle)\n" );	

		my $realURL = $api->getRedirectURL( $url ) or do {
			$::d_plugins && msg( "Live365.protocolHandler can't determine real station URL.\n" );
			return undef;
		};

		$::d_plugins && msg( "Live365 station really at: '$realURL'\n" );

		$self = $class->SUPER::new({ 
				'url' => $realURL, 
				'client' => $client, 
				'infoUrl' => $url,
				'create' => 1,
			});

		if( $handle =~ /[a-zA-Z]/ ) {  # if our URL doesn't look like a handle, don't try to get a playlist
			my $isVIP = Slim::Utils::Prefs::get( 'plugin_live365_memberstatus' );
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time() + 5,
				\&getPlaylist,
				( $self, $handle, $url, $isVIP )
			);
		}
	} else {
		$::d_plugins && msg( "Not a Live365 station URL: $url\n" );
	}

	return $self;
}

sub getPlaylist {
	my ( $client, $self, $handle, $url, $isVIP ) = @_;

	my $currentSong = Slim::Player::Playlist::playList($client)->[0];
	my $currentMode = Slim::Player::Source::playmode($client);
	 
	return undef if ($currentSong !~ /^live365:/ || $currentMode ne 'play');

	# store the original title as a fallback, once.
	#${*$self}{live365_original_title} ||= Slim::Music::Info::title();

	my $api = new Plugins::Live365::Live365API();

	my $playlist = $api->GetLive365Playlist( $isVIP, $handle );

	$::d_plugins && msg( "Got playlist response: $playlist\n" );

	my $newTitle = '';
	my $nowPlaying = XMLin( $playlist, ForceContent => 1 );
	my $nextRefresh;

	if( defined $nowPlaying && defined $nowPlaying->{PlaylistEntry} && defined $nowPlaying->{Refresh} ) {

		$nextRefresh = $nowPlaying->{Refresh}->{content} || 60;
		my @titleComponents = ();
		if ($nowPlaying->{PlaylistEntry}->[0]->{Title}->{content}) {
			push @titleComponents, $nowPlaying->{PlaylistEntry}->[0]->{Title}->{content};
		}
		if ($nowPlaying->{PlaylistEntry}->[0]->{Artist}->{content}) {
			push @titleComponents, $nowPlaying->{PlaylistEntry}->[0]->{Artist}->{content};
		}
		if ($nowPlaying->{PlaylistEntry}->[0]->{Album}->{content}) {
			push @titleComponents, $nowPlaying->{PlaylistEntry}->[0]->{Album}->{content};
		}

		$newTitle = join(" - ", @titleComponents);
	}
	else {
		$::d_plugins && msg( "Playlist handler returned an invalid response, falling back to the station title" );
		$newTitle = ${*$self}{live365_original_title};
	}

	if ($newTitle) {
		$::d_plugins && msg( "Live365 Now Playing: $newTitle\n" );
		$::d_plugins && msg( "Live365 next update: $nextRefresh seconds\n" );
		
		$client->killAnimation();
		Slim::Music::Info::setCurrentTitle( $url, $newTitle);
		
		#XXX Fixme $client->songDuration doesn't exist any more, need
		# a different way to set the time. perhaps changing setTitle above
		# to setInfo and accept an args hash.
		#$::d_plugins && msg( "Live365 setting songtime: $nextRefresh\n" );
		$client->remoteStreamStartTime(Time::HiRes::time());
		#$client->songduration($nextRefresh) if $nextRefresh;
	}

	if ( $nextRefresh and $currentSong =~ /^live365:/ ) {
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + $nextRefresh,
			\&getPlaylist,
			( $self, $handle, $url, $isVIP )
		);
	}
}

sub DESTROY {
	my $self = shift;

	$::d_plugins && msg( ref($self) . " shutting down\n" );

	Slim::Utils::Timers::killTimers( ${*$self}{client}, \&getPlaylist )
		or $::d_plugins && msg( "Live365 failed to kill playlist job timer.\n" );
}

1;

# 

# {{{ Plugins::Live365

package Plugins::Live365;

use strict;
use vars qw( $VERSION );
$VERSION = 1.10;

use Slim::Utils::Strings qw( string );
use Slim::Utils::Misc qw( msg );
use Slim::Control::Command;
use Slim::Display::Animation;

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
	Slim::Music::Info::setTitle($stationURL, 
		   $live365->{$client}->getCurrentStation()->{STATION_TITLE});

	$play and Slim::Control::Command::execute( $client, [ 'playlist', 'clear' ] );
	Slim::Control::Command::execute( $client, [ 'playlist', 'add', $stationURL ] );
	$play and Slim::Control::Command::execute( $client, [ 'play' ] );
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

	$client->update();
}

our %mainModeFunctions = (
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
			if ($mainModeItems[$mainModeIdx][0] eq 'loginMode') {
				Slim::Buttons::Common::pushMode( $client, $mainModeItems[$mainModeIdx][0] );
			}
			else {
				Slim::Buttons::Common::pushModeLeft( $client, $mainModeItems[$mainModeIdx][0], { source => $mainModeItems[$mainModeIdx][1] } );
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
LOGINMODE: {
our $setLoginMode = sub {
	my $client = shift;
	my $silent = $client->param( 'silent');

	my @statusText = qw(
		PLUGIN_LIVE365_LOGIN_SUCCESS
		PLUGIN_LIVE365_LOGIN_ERROR_NAME
		PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
		PLUGIN_LIVE365_LOGIN_ERROR_ACTION
		PLUGIN_LIVE365_LOGIN_ERROR_ORGANIZATION
		PLUGIN_LIVE365_LOGIN_ERROR_SESSION
		PLUGIN_LIVE365_LOGIN_ERROR_HTTP
	);

	my $userID   = Slim::Utils::Prefs::get( 'plugin_live365_username' );
	my $password = unpack( 'u', Slim::Utils::Prefs::get( 'plugin_live365_password' ) );
	my $loggedIn = $live365->{$client}->isLoggedIn();

	if( $loggedIn ) {
		$::d_plugins && msg( "Logging out $userID\n" );
		my $logoutStatus = $live365->{$client}->logout();

		if( $logoutStatus == 0 ) {
			Slim::Display::Animation::showBriefly( $client, $client->string( $statusText[ $logoutStatus ] ) );
			$::d_plugins && msg( "Live365 logged out.\n" );
		} else {
			Slim::Display::Animation::showBriefly( $client, $client->string( $statusText[ $logoutStatus ] ) );
			$::d_plugins && msg( "Live365 logout error: $statusText[ $logoutStatus ]\n" );
		}

		$live365->{$client}->setLoggedIn( 0 );
		Slim::Utils::Prefs::set( 'plugin_live365_sessionid', '' );
	} else {
		if( $userID and $password ) {
			$::d_plugins && msg( "Logging in $userID\n" );
			my $loginStatus = $live365->{$client}->login( $userID, $password );

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
		} else {
			$::d_plugins && msg( "Live365.login: no credentials set\n" );
			unless ($silent) {
				Slim::Display::Animation::showBriefly( $client, $client->string( 'PLUGIN_LIVE365_NO_CREDENTIALS' ) );
			}
		}
	}

	unless ($silent) {
		sleep 1;
	}
	Slim::Buttons::Common::popMode( $client );
};

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
my $genrePointer = 0;

GENREMODE: {
our $setGenreMode = sub {
	my $client = shift;
	$client->lines( \&GenreModeLines );

	$live365->{$client}->setBlockingStatus( 'PLUGIN_LIVE365_LOADING_GENRES' );
	$client->update();

	@genreList = $live365->{$client}->loadGenreList();

	if ( !@genreList ) {
		Slim::Display::Animation::showBriefly( $client, $client->string( 'PLUGIN_LIVE365_LOGIN_ERROR_HTTP' ), ' ' );
		Slim::Buttons::Common::popModeRight( $client );
	}

	$live365->{$client}->clearBlockingStatus();
	$client->update();
};

our $noGenreMode = sub {
	my $client = shift;
};

our %genreModeFunctions = (
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
			Slim::Buttons::Common::pushModeLeft( $client, 'Live365Channels', { source => $genreList[ $genrePointer ][0] } );
		} else {
			$::d_plugins && msg( "No stations for genre: " . $genreList[ $genrePointer ][0] . "\n" );
			Slim::Display::Animation::showBriefly( $client, $client->string( 'PLUGIN_LIVE365_NOSTATIONS' ), ' ' );
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
		$lines[0] = $client->string( $APImessage );
		return @lines;
	}

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

	my $source = $client->param( 'source');
	if (defined($source)) {
		$live365->{$client}->setStationListPointer(
			$live365->{$client}->getChannelModePointer($source) ||
		        0);
	}

	my $pointer = $live365->{$client}->getStationListPointer();
	my $listlength = $live365->{$client}->getStationListLength();
	if ($listlength && $pointer >= $listlength) {
		$live365->{$client}->setStationListPointer($listlength-1);
	}
	$client->lines( \&channelModeLines );
};

my $noChannelMode = sub {
	my $client = shift;
};

our %channelModeFunctions = (
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
        my $client = shift;

	my $source = $client->param( 'source');
	if (defined($source)) {
		$live365->{$client}->setChannelModePointer($source, 
				$live365->{$client}->getStationListPointer());
	}

        Slim::Buttons::Common::popModeRight( $client );
    },

    'right' => sub {
        my $client = shift;

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
our @infoItems = ();
my $infoItem = 0;

our $setInfoMode = sub {
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

our $noInfoMode = sub {
	my $client = shift;
};

our %infoModeFunctions = (
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
		$lines[0] = $client->string( $APImessage );
		return @lines;
	}

	$lines[0] = $live365->{$client}->getStationInfoString( 'STATION_TITLE' );

	$lines[1] = sprintf( "%s: %s",
		$client->string( 'PLUGIN_LIVE365_' . $infoItems[ $infoItem ]->[0] ),
		$infoItems[ $infoItem ]->[1]
	);

	return @lines;
}

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

	$live365->{$client}->setStationListPointer( 0 );
	Slim::Buttons::Common::pushModeLeft( $client, 'Live365Channels' );
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
	DE	Abmelden
	EN	Log out
	ES	Desconectarse

PLUGIN_LIVE365_LOGIN
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
	DE	Genre-Liste wird von Live365 geladen...
	EN	Loading genre list from Live365...
	ES	Cargando la lista de géneros de Live365...

PLUGIN_LIVE365_LOADING_GENRES_ERROR
	DE	Fehler beim Laden der Genre-Liste. Bitte neu versuchen.
	EN	Error loading genres, try again
	ES	Error al cargar géneros, intente nuevamente...

PLUGIN_LIVE365_PRESETS
	DE	Meine Voreinstellungen
	EN	My presets
	ES	Mis presets

PLUGIN_LIVE365_BROWSEGENRES
	DE	Musikstile durchsuchen
	EN	Browse genres
	ES	Examinar géneros

PLUGIN_LIVE365_BROWSEALL
	DE	Alle Stationen durchsuchen (viele)
	EN	Browse all stations (many)
	ES	Recorrer todas las estaciones (muchas)

PLUGIN_LIVE365_BROWSEPICKS
	DE	Editor Picks durchsuchen
	EN	Browse editor picks
	ES	Revisar las elegidas por el editor

PLUGIN_LIVE365_BROWSEPROS
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
	DE	Sender Beschreibung
	EN	Station Description
	ES	Descripción de estación

PLUGIN_LIVE365_STATION_LISTENERS_ACTIVE
	DE	Aktive Zuhörer
	EN	Active listeners
	ES	Oyentes activos

PLUGIN_LIVE365_STATION_LISTENERS_MAX
	DE	Maximale Anzahl Zuhörer
	EN	Maximum listeners
	ES	Cantidad máxima de oyentes

PLUGIN_LIVE365_LISTENER_ACCESS
	DE	Zuhörer Zugang
	EN	Listener access
	ES	Acceso para oyentes

PLUGIN_LIVE365_STATION_QUALITY_LEVEL
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

PLUGIN_LIVE365_GENRES
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
	^;
}

# }}}

1;

# }}}

