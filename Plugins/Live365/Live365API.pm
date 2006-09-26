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
use Slim::Utils::Misc qw( msg );
use vars qw( $VERSION );
$VERSION = 1.20;

use XML::Simple;
use IO::Socket;

my $live365_base = "http://www.live365.com";

# Make the login-specific information global between all instances of
# API objects.  That way we only login/logout once even if we have
# multiple clients attached.
my %loginInformation = (
		'sessionid'	=> undef,
		'vip'       => 0,
		'loggedin'  => 0
		);

sub new {
	my $class = shift;  
	my $self  = {
		'member_name'    => '',
		'password'       => '',
		'sessionid'      => '',
		'stationPointer' => 0,
		'genrePointer'   => 0,
		'stationSource'  => '',
		'reqBatch'       => 1,
		'status'         => 0,
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

sub stopLoading {
	my $self = shift;

	if (defined($self->{asyncHTTP})) {
		$self->{asyncHTTP}->close();
	}
}

#############################
# Web functions
#
sub asyncHTTPRequest {
	my $self = shift;
	my $path  = shift;
	my $args = shift;
	my $loadCallback = shift;
	my $errorCallback = shift;
	my $callbackArgs = shift;

	my $http = Slim::Networking::SimpleAsyncHTTP->new($loadCallback,
													  $errorCallback,
													  $callbackArgs);

	my $stringArgs = join( '&', map { "$_=" . URI::Escape::uri_escape($args->{$_}) } grep { $args->{$_} } keys %$args );
	my $url = $live365_base . $path . '?' . $stringArgs;
	$http->get($url);

	$::d_plugins && msg("Live365: Loading $url\n");

	$self->{asyncHTTP} = $http;
}

#############################
# Protocol handler functions
#
sub GetLive365Playlist {
    my $self   = shift;
    my $isVIP  = shift;
    my $handle = shift;
	my $callback = shift;
	my $callbackargs = shift;

    my %args = (
        'handler'  => 'playlist',
        'cmd'      => 'view',
        'handle'   => $isVIP ? "afl:$handle" : $handle,
        'viewType' => 'xml'
    );

	$self->asyncHTTPRequest('/pls/front',
							\%args,
							\&playlistLoadSub,
							\&playlistErrorSub,
							{self => $self,
							 callback => $callback,
							 callbackargs => $callbackargs});
}

sub playlistLoadSub {
	my $http = shift;
	my $self = $http->params('self');
	my $callback = $http->params('callback');
	my $callbackargs = $http->params('callbackargs');

	$self->{asyncHTTP} = undef;

	&$callback($http->content(), $callbackargs);
}

sub playlistErrorSub {
	my $http = shift;
	my $self = $http->params('self');
	my $callback = $http->params('callback');
	my $callbackargs = $http->params('callbackargs');

	$self->{asyncHTTP} = undef;

	&$callback(undef, $callbackargs);
}

#############################
# Login functions
#
sub login {
	my $self = shift;
	my $username = shift;
	my $password = shift;
	my $client = shift;
	my $callback = shift;
	my $silent = shift;

	my %args = (
		'action'      => 'login',
		'remember'    => 'Y',
		'org'         => 'live365',
		'member_name' => $username,
		'password'    => $password
	);

	$self->asyncHTTPRequest('/cgi-bin/api_login.cgi',
							\%args,
							\&authLoadSub,
							\&authErrorSub,
							{self => $self,
							 client => $client,
							 callback => $callback,
							 login => 1,
							 silent => $silent});
}


sub logout {
	my $self = shift;
	my $client = shift;
	my $callback = shift;
	my $silent = shift;

	if( !$loginInformation{sessionid} ) {
		&$callback($client, 0);
	}

	my %args = (
		'action'    => 'logout',
		'sessionid' => $loginInformation{sessionid},
		'org'       => 'live365'
	);

	$self->asyncHTTPRequest('/cgi-bin/api_login.cgi',
							\%args,
							\&authLoadSub,
							\&authErrorSub,
							{self => $self,
							 client => $client,
							 callback => $callback,
							 silent => $silent});
}

sub authLoadSub {
	my $http = shift;
	my $self = $http->params('self');
	my $client = $http->params('client');
	my $callback = $http->params('callback');
	my $login = $http->params('login');
	my $silent = $http->params('silent');

	$self->{asyncHTTP} = undef;

	if(!defined $http->contentRef) {
		$::d_plugins && msg("Live365API: No content received from api_login.cgi\n");
		&$callback($client, {'status' => 6, 'silent' => $silent}); # PLUGIN_LIVE365_LOGIN_ERROR_HTTP
		return;  
	}

	my $resp = eval { XMLin($http->contentRef) }; 

	if ($@) {
		$::d_plugins && msg("Live365API: XML parsing error on api_login.cgi: $@\n");
		&$callback($client, {'status' => 2, 'silent' => $silent}); # PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
		return;  
	}

	if ($login) {
		$loginInformation{sessionid} = $resp->{Session_ID};
		$loginInformation{vip} = $resp->{Member_Status} eq 'PREFERRED';
	}
	else {
		$loginInformation{sessionid} = undef;
	}

	&$callback($client, {'status' => $resp->{Code}, 'silent' => $silent});
}

sub authErrorSub {
	my ( $http, $error ) = @_;
	my $self = $http->params('self');
	my $client = $http->params('client');
	my $callback = $http->params('callback');
	my $silent = $http->params('silent');

	$self->{asyncHTTP} = undef;
	
	$::d_plugins && msg("Live365API: Error on api_login.cgi: $error\n");
	
	&$callback($client, {'status' => 6, 'silent' => $silent}); # PLUGIN_LIVE365_LOGIN_ERROR_HTTP
}

sub getSessionID {
	my $self = shift;

	return $loginInformation{sessionid};
}

sub isLoggedIn {
	my $self = shift;

	return defined( $loginInformation{loggedin} ) && $loginInformation{loggedin} == 1;
}

sub setLoggedIn {
	my $self = shift;
	my $val  = shift;

	return $loginInformation{loggedin} = $val;
}


sub setSessionID {
	my $self = shift;

	$loginInformation{sessionid} = shift;
}

sub getMemberStatus {
	my $self = shift;

	return $loginInformation{vip};
}


#############################
# Genre functions 
#
sub loadGenreList {
	my $self = shift;
	my $client = shift;
	my $loadSub = shift;
	my $errorSub = shift;

	my %args = (
		'format' => 'xml',
	);

	$self->asyncHTTPRequest('/cgi-bin/api_genres.cgi',
							\%args,
							\&genreListLoadSub,
							\&genreListErrorSub,
							{self => $self,
							 client => $client,
							 loadSub => $loadSub,
							 errorSub => $errorSub,});
}

sub genreListLoadSub {
	my $http = shift;
	my $self = $http->params('self');
	my $client = $http->params('client');
	my $loadSub = $http->params('loadSub');
	my $errorSub = $http->params('errorSub');

	$self->{asyncHTTP} = undef;

	if (!defined($http->contentRef)) {
		&$errorSub($client);
		return;
	}

	my $genres = eval { XMLin($http->contentRef) };

	if ($@) {
		&$errorSub($client);
		return;
	}

	my @list = ();
	# Build full display names for genres that list a Parent_ID
	# (...and I'm happy I get to use an Orcish maneuver, it's a geek thing)
	my %parentNameCache = ();
	my @tmpGenres = @{ $genres->{Genres}->{Genre} };
	foreach my $g ( @tmpGenres ) {
		if ( $g->{Parent_ID} != 0 ) {
			my $baseName = $parentNameCache{ $g->{Parent_ID} }
				||= ( grep { $g->{Parent_ID} == $_->{ID} } @tmpGenres )[0]->{Display_Name};
			$g->{Display_Name} = "$baseName $g->{Display_Name}";
		}

		push @list, [ $g->{Display_Name}, $g->{Name} ];
	}

	&$loadSub($client, \@list);
}

sub genreListErrorSub {
	my $http = shift;
	my $self = $http->params('self');
	my $client = $http->params('client');
	my $errorSub = $http->params('errorSub');

	$self->{asyncHTTP} = undef;
	&$errorSub($client);
}

sub getGenrePointer {
	my $self = shift;

	return $self->{genrePointer} || 0;
}

sub setGenrePointer {
	my $self = shift;
	my $pointer = shift;

	$self->{genrePointer} = $pointer;
}

#############################
# Station preset functions
#
sub loadMemberPresets {
	my $self = shift;
	my $source = shift;
	my $client = shift;
	my $loadSub = shift;
	my $errorSub = shift;

	my %args = (
		'action'    => "get",
		'sessionid' => $loginInformation{sessionid},
		'device_id' => "UNKNOWN",
		'app_id'    => "live365:BROWSER",
		'first'     => 1,
		'rows'      => 200,
		'access'    => "ALL",
		'format'    => "xml"
	);

	$self->asyncHTTPRequest('/cgi-bin/api_presets.cgi',
							\%args,
							\&presetsLoadSub,
							\&presetsErrorSub,
							{'self'     => $self,
							 'client'   => $client,
							 'source'   => $source,
							 'loadSub'  => $loadSub,
							 'errorSub' => $errorSub,});
}

sub presetsLoadSub {
	my $http = shift;
	my $self = $http->params('self');
	my $client = $http->params('client');
	my $source = $http->params('source');
	my $loadSub = $http->params('loadSub');
	my $errorSub = $http->params('errorSub');

	$self->{asyncHTTP} = undef;

	if( !defined $http->contentRef ) {
		&$errorSub($client);
		return;
	}

	$self->{Directory} = eval { XMLin($http->contentRef, forcearray => [ "LIVE365_STATION" ]) };

	if ($@) {
		$::d_plugins && msg("Error parsing presets: $@" );
		&$errorSub($client);
		return;
	}
	
	if( defined $self->{Directory}->{LIVE365_STATION} ) {

		push @{ $self->{Stations} }, @{ $self->{Directory}->{LIVE365_STATION} };

	} elsif ($http->content =~ /Failed - invalid login session/) {

		# Very lazy way to search the XML for an error message
		# indicating that our session timed out
		$loginInformation{loggedin} = 0;
		$::d_plugins && msg("Login session timed out");
		&$errorSub($client);
		return;

	} else {

		$self->{Directory}->{LIVE365_STATION} = [];
	}

	$self->{stationSource} = $source;

	&$loadSub($client);
}

sub presetsErrorSub {
	my $http = shift;
	my $self = $http->params('self');
	my $client = $http->params('client');
	my $errorSub = $http->params('errorSub');

	$self->{asyncHTTP} = undef;
	&$errorSub($client);
}

#############################
# Station functions
#
sub loadStationDirectory {
	my $self = shift;
	my $source = shift;
	my $client = shift;
	my $loadSub = shift;
	my $errorSub = shift;
	my $paging = shift;
	
	my @addlargs = @_;

	# Added to handle loading of additional stations later from original args when paging
	if ($paging && defined($self->{currentargs})) {
		push(@addlargs, @{$self->{currentargs}});
	} else {
		$self->{currentargs} = \@addlargs;
	}

	my %args = (
		'site'         => "xml",     # requests the data in XML format
		'access'       => "ALL",     # "ALL:PUBLIC:PRIVATE:NONE"
		'clienttype'   => 0,         # 3rd party MP3 player
		'first'        => 1,         # first row to print
		'rows'         => 50,        # number of rows to print, default 25, max 200
		'genre'        => "All",     # Limit display to these genres
		'maxspeed'     => 256,       # max bitrate to include
		'minspeed'     => 0,         # min bitrate to include
		'quality'      => 0,         # AM (0-99), FM (100-199), CD (200+)
		'only'         => "",        # "E:I:L:O:R:S:X" only include stations with these attribs
		'searchdesc'   => "",        # search term to look for
		'searchgenre'  => "All",     # genre restriction when searching
		'searchfields' => "T:A:C",   # "K:E:D:G:H:T:A:C:F:L:I:S", fields for searchdesc
		'sort'         => "L:D;R:D", # "T|D|C|G|R|L|H:U|D;<2>;<3>"
		'source'       => "Live365:RdRunnder:BT",
		'tag'          => "",
		'text'         => "",
		@addlargs
	);

	$self->asyncHTTPRequest('/cgi-bin/directory.cgi',
							\%args,
							\&stationLoadSub,
							\&stationErrorSub,
							{self => $self,
							 client => $client,
							 source => $source,
							 loadSub => $loadSub,
							 errorSub => $errorSub,});
}

sub stationLoadSub {
	my $http = shift;
	my $self = $http->params('self');
	my $client = $http->params('client');
	my $source = $http->params('source');
	my $loadSub = $http->params('loadSub');
	my $errorSub = $http->params('errorSub');

	$self->{asyncHTTP} = undef;

	if( !defined $http->contentRef ) {
		&$errorSub($client);
		return;
	}

	$self->{Directory} = eval { XMLin($http->contentRef, forcearray => [ "LIVE365_STATION" ] ) };

	if ($@) {
		$::d_plugins && msg("Error parsing station directory: $@" );	
		&$errorSub($client);
		return;
	}
	
	if( defined $self->{Directory}->{LIVE365_STATION} ) {
		push @{ $self->{Stations} }, @{ $self->{Directory}->{LIVE365_STATION} };
	} else {
		$self->{Directory}->{LIVE365_STATION} = [];
	}

	$self->{stationSource} = $source;

	&$loadSub($client);
}

sub stationErrorSub {
	my $http = shift;
	my $self = $http->params('self');
	my $client = $http->params('client');
	my $errorSub = $http->params('errorSub');

	$self->{asyncHTTP} = undef;
	
	if ( $errorSub && ref $errorSub eq 'CODE' ) {
		$errorSub->($client);
	}
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

sub getStationSource {
	my $self = shift;

	return $self->{stationSource};
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
	my $client = shift;
	my $loadSub = shift;
	my $errorSub = shift;

	$self->{stationPointer} = $req;

	if( $req > $#{ $self->{Stations} } && $self->{Directory}->{LIVE365_DIRECTORY_FILTERS}->{DIRECTORY_MORE_ROWS_AVAILABLE} ) {
		$self->loadStationDirectory( $self->{stationSource}, $client, $loadSub, $errorSub, 1, first => scalar @{ $self->{Stations} } + 1 );
	}
	elsif (defined($loadSub)) {
		&$loadSub($client);
	}
}

sub getStationListLength {
	my $self = shift;

	return $self->{Directory}->{LIVE365_DIRECTORY_FILTERS}->{DIRECTORY_TOTAL_RESULTS};
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
	if( $loginInformation{sessionid} ) {
		$url .= '?sessionid=' . $loginInformation{sessionid};
	}

	return $url;
}


#############################
# Information functions
#
sub loadInfoForStation {
	my $self = shift;
	my $stationID = shift;
	my $client = shift;
	my $loadSub = shift;
	my $errorSub = shift;

	if ( defined $self->{currentStationInfo} && $stationID == $self->{currentStationInfo} ) {
		&$loadSub($client);
		return;
	}

	my %args = (
		'format'  => 'xml',
		'in'      => 'STATIONS',
		'channel' => $stationID
	);

	$self->asyncHTTPRequest('/cgi-bin/station_info.cgi',
							\%args,
							\&infoLoadSub,
							\&infoErrorSub,
							{self => $self,
							 client => $client,
							 loadSub => $loadSub,
							 errorSub => $errorSub,
							 stationID => $stationID});
}

sub infoLoadSub {
	my $http = shift;
	my $self = $http->params('self');
	my $client = $http->params('client');
	my $loadSub = $http->params('loadSub');
	my $errorSub = $http->params('errorSub');
	my $stationID = $http->params('stationID');

	$self->{asyncHTTP} = undef;

	if (!defined($http->contentRef)) {
		&$errorSub($client);
		return;
	}

	$self->{StationInfo} = eval { XMLin($http->contentRef) };

	if ($@) {
		$::d_plugins && msg("Error parsing station info: $@" );	
		&$errorSub($client);
		return;
	}

	$self->{currentStationInfo} = $stationID;
	
	&$loadSub($client);
}

sub infoErrorSub {
	my $http = shift;
	my $self = $http->params('self');
	my $client = $http->params('client');
	my $errorSub = $http->params('errorSub');

	$self->{asyncHTTP} = undef;
	&$errorSub($client);
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

sub getStationInfoURL {
	my $self = shift;

	my $url = $self->{StationInfo}->{LIVE365_STATION}->{STATION_ADDRESS};
	$url =~ s/^http:/live365:/;
	if( $loginInformation{sessionid} ) {
		$url .= '?sessionid=' . $loginInformation{sessionid};
	}

	return $url;
}


1;

# }}}
