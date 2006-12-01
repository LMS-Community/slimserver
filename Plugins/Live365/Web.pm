package Plugins::Live365::Web;

# ***** BEGIN LICENSE BLOCK *****
# Version: MPL 1.1/GPL 2.0/LGPL 2.1
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
# 
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
# 
# The Original Code is the SlimServer Live365 Plugin.
# 
# The Initial Developer of the Original Code is Vidur Apparao.
# Portions created by the Initial Developer are Copyright (C) 2004
# the Initial Developer. All Rights Reserved.
# 
# Contributor(s):
# 
# Alternatively, the contents of this file may be used under the
# terms of the GNU General Public License Version 2 or later (the
# "GPL"), in which case the provisions of the GPL are applicable 
# instead of those above.  If you wish to allow use of your 
# version of this file only under the terms of the GPL and not to
# allow others to use your version of this file under the MPL,
# indicate your decision by deleting the provisions above and
# replace them with the notice and other provisions required by
# the GPL.	If you do not delete the provisions above, a recipient
# may use your version of this file under either the MPL or the
# GPL.
#
# ***** END LICENSE BLOCK ***** */

# $Id$

use strict;

use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use Slim::Utils::Misc;

use Plugins::Live365::Live365API;

use constant ROWS_TO_RETRIEVE => 50;

my $API = Plugins::Live365::Live365API->new;
my $log = logger('plugin.live365');

#  Handle play or add actions on a station
sub handleAction {
	my ($client, $params) = @_;

	my $mode      = $params->{'mode'};
	my $current   = $params->{'current'} || 1;
	my $action    = $params->{'action'};
	my $stationid = $params->{'id'};

	if (defined($client)) {

		my $play = ($action eq 'play');

		$API->setStationListPointer($current-1);
	
		my $stationURL = $API->getCurrentChannelURL();

		$log->info("ChannelMode URL: $stationURL");
	
		Slim::Music::Info::setContentType($stationURL, 'mp3');
		Slim::Music::Info::setTitle($stationURL, $API->getCurrentStation()->{STATION_TITLE});
		
		if ( $play ) {
			$client->execute([ 'playlist', 'clear' ]);
			$client->execute([ 'playlist', 'play', $stationURL ]);
		}
		else {
			$client->execute([ 'playlist', 'add', $stationURL ]);
		}
	}

	my $webroot = $params->{'webroot'};
	$webroot =~ s/(.*?)plugins.*$/$1/;

	return filltemplatefile("live365_redirect.html", $params);
}

#  Handle browsing genres or stations for a genre.
#    Play some async games here.  No response until we get a callback from the completion
#    of the Async_HTTP login request.

sub handleBrowseGenre {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $errcode = startBrowseGenre($client, $params, $callback, $httpClient, $response);
	
	# Errcode > 0 is a real error.  Show it on the next screen.
	# Errcode = 0 means the browse is in progress.
	# Errcode < 0 means normal completion with no async stuff needed.
	if ($errcode != 0) {
		if ($errcode > 0) {
			$params->{'errmsg'} = "PLUGIN_LIVE365_LOADING_GENRES_ERROR";
		}
		return handleIndex($client,$params);
	}

	storeAsyncRequest("xxx", "genre", {
		client     => $client,
		params     => $params,
		callback   => $callback,
		httpClient => $httpClient,
		response   => $response
	});

	return undef;
}

sub startBrowseGenre {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $genreid = $params->{'id'};

	if ($genreid eq 'root') {
		$API->loadGenreList($client, \&completeBrowseGenre, \&errorBrowseGenre);
	}
	else {
		# See startBrowseStations for how paging works
		my @optionalFirstParam;

		if ($params->{'start'}) {
			@optionalFirstParam = ( "first", $params->{'start'} + 1);
		}
		
		$API->clearStationDirectory();

		$API->loadStationDirectory(
			$genreid, $client, \&completeBrowseGenre, \&errorBrowseGenre, 0,
			'genre'	       => $genreid,
			'sort'         => Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
			'rows'         => ROWS_TO_RETRIEVE,
			'searchfields' => Slim::Utils::Prefs::get( 'plugin_live365_search_fields' ),
			@optionalFirstParam
		);
	}
	
	return 0;
}

sub completeBrowseGenre {
	my $client = shift;
	my $list = shift;

	my $body = "";

	my $fullparams = fetchAsyncRequest('xxx', 'genre');
	my $params     = $fullparams->{'params'};
	my $genreid    = $params->{'id'};

	if ($genreid eq 'root') {

		my @genreList = @$list;

		if (scalar @genreList == 0) {

			$params->{'errmsg'} = "PLUGIN_LIVE365_LOADING_GENRES_ERROR";
			$body = handleIndex($client,$params);

		} else {

			my %listform = %$params;
			my $i = 0;

			for my $genre (@genreList) {

				$listform{'genreid'} = @$genre[1];
				$listform{'genrename'} = @$genre[0];
				$listform{'genremode'} = 1;
				$listform{'odd'} = $i++ % 2;
				$params->{'browse_list'} .= ${filltemplatefile("live365_browse_list.html", \%listform)};
			}
		}

	} else {

		push @{$params->{'pwd_list'}}, {
			'hreftype'  => 'Live365Browse',
			'title'     => $params->{'name'},
			'genreid'   => $genreid,
			'genrename' => $params->{'name'},
			'type'      => 'genres'
		};

		$params->{'listname'} = $params->{'name'};
		$body = buildStationBrowseHTML($params);
	}

	if ($body eq "") {
		$body = filltemplatefile("live365_browse.html", $params);
	}

	createAsyncWebPage($client, $body, $fullparams);
}

sub errorBrowseGenre {
	my $client = shift;
	my $list   = shift;

	my $body = "";

	my $fullparams = fetchAsyncRequest('xxx','genre');
	my $params     = $fullparams->{'params'};
	my $genreid    = $params->{'id'};

	if ($genreid eq 'root') {
		$params->{'errmsg'} = "PLUGIN_LIVE365_LOADING_GENRES_ERROR";
		$body = handleIndex($client,$params);
	} else {
		$params->{'errmsg'} = "PLUGIN_LIVE365_LOADING_GENRES_ERROR";
		$body = filltemplatefile("live365_browse.html", $params);
	}

	createAsyncWebPage($client,$body,$fullparams);
}

#
#  Handle browsing stations for by any method except by genre
#    Play some async games here.  No response until we get a callback from the completion
#    of the Async_HTTP login request.
#
sub handleBrowseStation {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $errcode = startBrowseStation($client, $params, $callback, $httpClient, $response);
	
	# Errcode > 0 is a real error.  Show it on the next screen.
	# Errcode = 0 means the browse is in progress.
	# Errcode < 0 means normal completion with no async stuff needed.
	if ($errcode != 0) {

		if ($errcode > 0) {
			$params->{'errmsg'} = "PLUGIN_LIVE365_LOGIN_ERROR_ACTION";
		}

		return handleIndex($client,$params);
	}

	storeAsyncRequest("xxx", "station", {
		client     => $client,
		params     => $params,
		callback   => $callback,
		httpClient => $httpClient,
		response   => $response
	});

	return undef;
}

my %lookupStrings = (
	"presets"     => "PLUGIN_LIVE365_PRESETS",
	"picks"       => "PLUGIN_LIVE365_BROWSEPICKS",
	"pro"         => "PLUGIN_LIVE365_BROWSEPROS",
	"all"         => "PLUGIN_LIVE365_BROWSEALL",
	"tac"         => "PLUGIN_LIVE365_SEARCH_TAC",
	"artist"      => "PLUGIN_LIVE365_SEARCH_A",
	"track"       => "PLUGIN_LIVE365_SEARCH_T",
	"cd"          => "PLUGIN_LIVE365_SEARCH_C",
	"station"     => "PLUGIN_LIVE365_SEARCH_E",
	"location"    => "PLUGIN_LIVE365_SEARCH_L",
	"broadcaster" => "PLUGIN_LIVE365_SEARCH_H",
	"genres"      => "PLUGIN_LIVE365_BROWSEGENRES",
);

my %lookupGenres = (
	"presets" => "N/A",  # Not used
	"picks"   => "ESP",
	"pro"     => "Pro",
	"all"     => "All"
);

sub startBrowseStation {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $brtype = $params->{'type'};

	my $source = $lookupStrings{$brtype};

	if ($brtype eq 'presets') {

		# Presets.  Clear everything and reload just because we're lazy.
		$API->clearStationDirectory();
		$API->loadMemberPresets( $source, $client, \&completeBrowseStation, \&errorBrowseStation);
			
	} elsif ($lookupGenres{$brtype}) {

		# This is ugly but it's easy and it works.  We don't page like the Slim clients do.
		#   Slim clients page by retrieving the first N channels, then as you scroll, they
		#   append the next N channels, and so on... the Stations hash grows.
		#   We will only ever have N channels in the Stations hash.  We clear and reload
		#   the N channels page by page.  It allows us to skip around pages a bit easier
		#   at the expense of a possible performance hit.
		my @optionalFirstParam = ();

		if ($params->{'start'}) {
			@optionalFirstParam = ( "first", $params->{'start'} + 1);
		}
		
		$API->clearStationDirectory();
		$API->loadStationDirectory(
			$source,
			$client, 
			\&completeBrowseStation,
			\&errorBrowseStation,
			0,
			'sort'         => Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
			'searchfields' => Slim::Utils::Prefs::get( 'plugin_live365_search_fields' ),
			'rows'         => ROWS_TO_RETRIEVE,
			'genre'	       => $lookupGenres{$brtype},
			@optionalFirstParam
		);

	} else {

		# What are you asking us to do?!?
		return 1;
	}

	return 0;
}

sub completeBrowseStation {
	my $client = shift;

	my $fullparams = fetchAsyncRequest('xxx','station');
	my $params = $fullparams->{'params'};
	my $brtype = $params->{'type'};

	my $body = buildStationBrowseHTML($params);

	createAsyncWebPage($client,$body,$fullparams);
}

sub errorBrowseStation {
	my $client = shift;

	my $fullparams = fetchAsyncRequest('xxx','station');
	my $params = $fullparams->{'params'};
	
        if ($API->isLoggedIn()) {
                $params->{'errmsg'} = "PLUGIN_LIVE365_NOSTATIONS";
        } else {
                $params->{'errmsg'} = "PLUGIN_LIVE365_NOT_LOGGED_IN";
        }

	my $body = handleIndex($client,$params);
		
	createAsyncWebPage($client,$body,$fullparams);
}

sub buildStationBrowseHTML {
	my $params = shift;
	my $isSearch = shift;
	my $start;
	my $end;

	# Get actual matched stations
	my $totalcount = $API->getStationListLength();

	# Set up paging links for search vs. browse
	my $targetPage;
	my $targetParms;

	if ($isSearch) {

		$targetPage = "search.html";
		$targetParms = "type=" . $params->{'type'} . "&query=" .
			URI::Escape::uri_escape($params->{'query'}) .
			"&player=" . $params->{'player'};

	} else {

		$targetPage = "browse.html";
		$targetParms = "type=" . $params->{'type'} . "&player=" . $params->{'player'};

		if ($params->{'id'}) {
			$targetParms .= "&id=" . $params->{'id'};
		}

		if ($params->{'name'}) {
			$targetParms .= "&name=" . $params->{'name'};
		}
	}

	# If we have nothing to show, show an error.
	if ($totalcount == 0) {

		$params->{'errmsg'} = "PLUGIN_LIVE365_NOSTATIONS";

	} else {
	
		# Handle paging sections, if necessary
		if ($totalcount <= ROWS_TO_RETRIEVE) {
	
			# Force this since we're not paging anyway and simpleHeader likes to start
			# counting at zero otherwise.
			$params->{'start'} = 1;

			Slim::Web::Pages->simpleHeader({
				'itemCount'    => $totalcount,
				'startRef'     => \$params->{'start'},
				'headerRef'    => \$params->{'browselist_header'},
				'skinOverride' => $params->{'skinOverride'},
				'perPage'      => ROWS_TO_RETRIEVE,
			});
	
		} else {

			$params->{'pageinfo'} = Slim::Web::Pages->pageInfo({
				'itemCount'    => $totalcount,
				'path'         => $targetPage,
				'otherParams'  => $targetParms,
				'start'        => $params->{'start'},
				'perPage'      => ROWS_TO_RETRIEVE,
			});
		}
	
		my %listform = %$params;
		my $i        = 0;
		my $slist    = $API->{Stations};

		for my $station (@$slist) {

			$listform{'stationid'}    = $station->{STATION_ID};
			$listform{'stationname'}  = $station->{STATION_TITLE};
			$listform{'listeners'}    = $station->{STATION_LISTENERS_ACTIVE};
			$listform{'maxlisteners'} = $station->{STATION_LISTENERS_MAX};
			$listform{'connection'}   = $station->{STATION_CONNECTION};
			$listform{'rating'}       = $station->{STATION_RATING};
			$listform{'quality'}      = $station->{STATION_QUALITY_LEVEL};
			$listform{'access'}       = $station->{LISTENER_ACCESS};
			$listform{'stationmode'}  = 1;
			$listform{'odd'}          = $i++ % 2;
			$listform{'current'}      = $i;
			$listform{'mode'}         = "";

			if ($params->{'extrainfo_function'}) {
				$listform{'extrainfo'} = eval($params->{'extrainfo_function'});
			}

			$params->{'browse_list'} .= ${filltemplatefile("live365_browse_list.html", \%listform)};
		}

		$params->{'match_count'} = $totalcount;
	}

	return filltemplatefile(($isSearch ? "live365_search.html" : "live365_browse.html"), $params);
}

#  Handle Browse action (Genres or Stations)
#    Just refer them off to the right handler after checking the client and login status.

sub handleBrowse {
	my ($client, $params) = @_;

	if (!($API->isLoggedIn())) {
		$params->{'errmsg'} = "PLUGIN_LIVE365_NOT_LOGGED_IN";
		return handleIndex(@_);
	}

	my $brtype = $params->{'type'};

	$params->{'listname'} = string($lookupStrings{$brtype});

	$params->{'pwd_list'} = [
		{
			'hreftype' => 'Live365Index',
			'title' => string("PLUGIN_LIVE365_MODULE_NAME"),
		},
		{
			'hreftype' => 'Live365Browse',
			'title' => $params->{'listname'},
			'genreid' => $params->{'type'} eq "genres" ? 'root' : '',
			'type' => $brtype,
		},
	];

	if ($params->{'type'} eq "genres") {
		return handleBrowseGenre(@_);
	}
	else {
		return handleBrowseStation(@_);
	}

	return undef;
}

#
#  Handle searching stations by a variety of methods
#    Play some async games here.  No response until we get a callback from the completion
#    of the Async_HTTP search request.
#
sub handleSearch {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	if (!($API->isLoggedIn())) {
		$params->{'errmsg'} = "PLUGIN_LIVE365_NOT_LOGGED_IN";
		return handleIndex(@_);
	}

	my $brtype = $params->{'type'};

	$params->{'listname'} = string($lookupStrings{$brtype});

	$params->{'pwd_list'} = [
		{
			'hreftype' => 'Live365Index',
			'title' => string("PLUGIN_LIVE365_MODULE_NAME"),
		},
		{
			'hreftype' => 'Live365Search',
			'title' => string("PLUGIN_LIVE365_SEARCH"),
			'type' => $brtype,
		},
	];

	# Short circuit error msg if query param not given
	if (!$params->{'query'}) {

		$params->{'numresults'} = -1;

		return filltemplatefile("live365_search.html", $params);
	}

	my $errcode = startSearch($client, $params, $callback, $httpClient, $response);
	
	# Errcode > 0 is a real error.  Show it on the next screen.
	# Errcode = 0 means the search is in progress.
	# Errcode < 0 means normal completion with no async stuff needed.
	if ($errcode != 0) {

		if ($errcode > 0) {
			$params->{'errmsg'} = "PLUGIN_LIVE365_NOSTATIONS";
		}

		return filltemplatefile("live365_search.html", $params);
	}

	storeAsyncRequest("xxx", "search", {
		client     => $client,
		params     => $params,
		callback   => $callback,
		httpClient => $httpClient,
		response   => $response
	});

	return undef;
}

my %lookupSearchFields = (
	"tac"         => "T:A:C",
	"artist"      => "A",
	"track"       => "T",
	"cd"          => "C",
	"station"     => "E",
	"location"    => "L",
	"broadcaster" => "H",
);

my %lookupExtraInfo = (
	"tac"         => "\&showPlaylistMatches(\$station->{STATION_PLAYLIST_INFO}->{PlaylistEntry})",
	"artist"      => "\&showPlaylistMatches(\$station->{STATION_PLAYLIST_INFO}->{PlaylistEntry})",
	"track"       => "\&showPlaylistMatches(\$station->{STATION_PLAYLIST_INFO}->{PlaylistEntry})",
	"cd"          => "\&showPlaylistMatches(\$station->{STATION_PLAYLIST_INFO}->{PlaylistEntry})",
	"station"     => "",
	"location"    => "\$station->{STATION_LOCATION}",
	"broadcaster" => "\$station->{STATION_BROADCASTER}",
);

sub startSearch {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $query = $params->{'query'};
	my $type  = $params->{'type'};

	my $source = $lookupStrings{$type};

	# See startBrowseStations for how paging works
	my @optionalFirstParam;

	if ($params->{'start'}) {
		@optionalFirstParam = ( "first", $params->{'start'} + 1);
	}
	
	$API->clearStationDirectory();
	$API->loadStationDirectory(
		$source,
		$client, 
		\&completeSearch,
		\&errorSearch,
		0,
		'sort'         => Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
		'searchfields' => $lookupSearchFields{$type},
		'rows'         => ROWS_TO_RETRIEVE,
		'searchdesc'   => $query,
		@optionalFirstParam
	);

	return 0;
}

sub completeSearch {
	my $client = shift;

	my $fullparams = fetchAsyncRequest('xxx','search');
	my $params = $fullparams->{'params'};
	my $brtype = $params->{'type'};

	my $showDetails = Slim::Utils::Prefs::get( 'plugin_live365_web_show_details' );

	push @{$params->{'pwd_list'}}, {
		'hreftype' => 'Live365Search',
		'title'    => join(' -> ', $params->{'listname'}, $params->{'query'}),
		'type'     => $brtype,
		'query'    => $params->{'query'},
	};

	if ($showDetails) {
		$params->{'extrainfo_function'} = $lookupExtraInfo{$brtype};
	}

	my $body = buildStationBrowseHTML($params,1);

	createAsyncWebPage($client,$body,$fullparams);
}

sub errorSearch {
	my $client = shift;

	my $fullparams = fetchAsyncRequest('xxx','search');
	my $params = $fullparams->{'params'};
	$params->{'errmsg'} = "PLUGIN_LIVE365_NOSTATIONS";

	my $body = filltemplatefile("live365_search.html", $params);
		
	createAsyncWebPage($client,$body,$fullparams);
}

#
#  Helper routine to format XML data returned from Live365 when
#    searching playlist artist, song, or album.
#
sub showPlaylistMatches {
	my $plist = shift;
	my @templist;
	my $retval = "";

	if (ref($plist) ne "ARRAY") {
		# One match in the playlist
		@templist = ($plist);
	} else {
		@templist = @$plist;
	}

	foreach my $item (@templist) {

		# Empty values in the XML show up as refs to hashes
		if (ref($item->{Artist}) eq "HASH" || ref($item->{Title}) eq "HASH") {

			next;
		}

		$retval .= "<br>\n" if ($retval);
		$retval .= $item->{Artist} . " - " . $item->{Title};
		$retval .= " (" . $item->{Album} . ")" unless (ref($item->{Album}) eq "HASH");
	}

	return $retval;
}

#
#  Handle main Index page.
#    Nothing fancy, no async stuff here unless login is needed
#
sub handleIndex {
	my ($client, $params) = @_;

	my $body = "";

	$params->{'loggedin'} = $API->isLoggedIn();

	if ($params->{'autologin'} && !($params->{'loggedin'})) {

		$params->{'action'} = "in";

		# Stop infinite loops in the event we don't log in successfully
		$params->{'autologin'} = 0;

		return handleLogin(@_);
	}

	$body = filltemplatefile("live365_index.html", $params);

	return $body;
}

#
#  Handle Login/Logout actions.
#    Play some async games here.  No response until we get a callback from the completion
#    of the Async_HTTP login request. 
#
sub handleLogin {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	storeAsyncRequest("xxx", "login", {
		client     => $client,
		params     => $params,
		callback   => $callback,
		httpClient => $httpClient,
		response   => $response
	});

	my $errcode = doLoginLogout($client, $params, $callback, $httpClient, $response);
	
	# Errcode > 0 is a real error.  Show it on the next screen.
	# Errcode = 0 means the login is in progress.
	# Errcode < 0 means normal completion with no async stuff needed.
	if ($errcode != 0) {

		if ($errcode > 0) {
			$params->{'errmsg'} = "PLUGIN_LIVE365_NO_CREDENTIALS";
		}

		return handleIndex($client,$params);
	}

	return undef;
}

my @login_statusText = qw(
	PLUGIN_LIVE365_LOGIN_SUCCESS
	PLUGIN_LIVE365_LOGIN_ERROR_NAME
	PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
	PLUGIN_LIVE365_LOGIN_ERROR_ACTION
	PLUGIN_LIVE365_LOGIN_ERROR_ORGANIZATION
	PLUGIN_LIVE365_LOGIN_ERROR_SESSION
	PLUGIN_LIVE365_LOGIN_ERROR_HTTP
);

sub doLoginLogout {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	my $action = $params->{'action'};

	my $userID   = Slim::Utils::Prefs::get( 'plugin_live365_username' );
	my $password = Slim::Utils::Prefs::get( 'plugin_live365_password' );

	if (defined $password) {
		$password = unpack('u', $password);
	}

	if ($action eq 'in') {

		if ($userID and $password ) {

			$log->info("Logging in $userID");

			my $loginStatus = $API->login( $userID, $password, $client, \&webLoginDone);

		} else {

			$log->warn("Warning: No credentials set for login");

			return 1;
		}

	} else {

		$log->info("Logging out $userID");

		my $logoutStatus = $API->logout($client, \&webLogoutDone);
	}

	return 0;
}

sub webLoginDone {
	my $client = shift;
	my $args   = shift;

	my $loginStatus = $args->{'status'};

	my $params = fetchAsyncRequest('xxx','login');

	if( $loginStatus == 0 ) {

		Slim::Utils::Prefs::set( 'plugin_live365_sessionid', $API->getSessionID() );
		Slim::Utils::Prefs::set( 'plugin_live365_memberstatus', $API->getMemberStatus() );

		$API->setLoggedIn( 1 );

		$log->info("Logged in: ", $API->getSessionID);

	} else {

		Slim::Utils::Prefs::set( 'plugin_live365_sessionid', undef );
		Slim::Utils::Prefs::set( 'plugin_live365_memberstatus', undef );

		$API->setLoggedIn( 0 );

		$log->warn("Warning: login failure: $login_statusText[$loginStatus]");

		$params->{'params'}->{'errmsg'} = $login_statusText[ $loginStatus ];
	}

	my $body = handleIndex($client, $params->{'params'});
	
	createAsyncWebPage($client, $body, $params);
}

sub webLogoutDone {
	my $client = shift;

	$API->setLoggedIn( 0 );

	Slim::Utils::Prefs::set( 'plugin_live365_sessionid', '' );

	#my $params = fetchAsyncRequest($client->id(),'login');
	my $params = fetchAsyncRequest('xxx', 'login');

	my $body = handleIndex($client,$params->{'params'});
	
	createAsyncWebPage($client,$body,$params);
}

#
#  Pretty much stolen from the Shoutcast Plugin.
#    Send output back to the Asynchronous web page handler once we've built the page
#
sub createAsyncWebPage {
	my $APIclient = shift;
	my $output = shift;
	my $params = shift;
	
	# create webpage if we were called asynchronously
	my $current_player = "";

	if (defined $APIclient) {

		$current_player = $APIclient->id;
	}
		
	$params->{callback}->($current_player, $params->{params}, $output, $params->{httpClient}, $params->{response});
}

#
# Routines and hash to manage the queue of parameters etc. for pending asynchronous requests.
#   Keyed by operation and client ID
#   Note: Fetching an object automatically deletes it
#
my %async_queue = ();

sub storeAsyncRequest {
	my ($client, $operation, $params) = @_;
	
	my $asynckey = $operation . "--" . $client;

	$async_queue{$asynckey} = $params;
}

sub fetchAsyncRequest {
	my ($client, $operation) = @_;

	my $asynckey = $operation . "--" . $client;
	my $retval   = $async_queue{$asynckey};

	delete $async_queue{$asynckey};

	return $retval;
}

#
#  Local routine that just is a shortcut for the one in Slim::Web::HTTP.
#    The RealSlim plugin just did it this way.
#
sub filltemplatefile {
	return Slim::Web::HTTP::filltemplatefile(@_);
}


####
# CLI access routines
####

sub cli_login {
	my $request = shift;
	
	# get user and password
	my $userID   = Slim::Utils::Prefs::get( 'plugin_live365_username' );
	my $password = Slim::Utils::Prefs::get( 'plugin_live365_password' );

	# unpack pwd
	if (defined $password) {
		$password = unpack('u', $password);
	}

	if( $userID and $password ) {

		$log->info("Logging in $userID (from CLI)");

		my $loginStatus = $API->login( $userID, $password, $request, \&cli_login_cb);

		return 1;
	} 
	else {

		$log->warn("Warning: No credentials set for login (from CLI)");

		return 0;
	}
}

sub cli_login_cb {
	my $request = shift;
	my $loginStatus = shift;

	if( $loginStatus == 0 ) {

		Slim::Utils::Prefs::set( 'plugin_live365_sessionid', $API->getSessionID() );
		Slim::Utils::Prefs::set( 'plugin_live365_memberstatus', $API->getMemberStatus() );

		$API->setLoggedIn( 1 );

		$log->info("Logged in: ", $API->getSessionID, " (from CLI)");

	} else {

		Slim::Utils::Prefs::set( 'plugin_live365_sessionid', undef );
		Slim::Utils::Prefs::set( 'plugin_live365_memberstatus', undef );

		$API->setLoggedIn( 0 );

		# remember we failed so we don't try it again...
		$request->addParam('__loginfailed', 1);

		$log->warn("Warning: login failure: $login_statusText[$loginStatus] (from CLI)");
	}

	# this will re-call the cli handling function we left for handling login
	$request->jumpbacktofunc;
}

# login management for cli handling code
sub cli_manage_login {
	my $request = shift;

	# check we're logged in
	if (!$API->isLoggedIn) {
	
		# try to login or check if we failed already
		if (!cli_login($request) || $request->getParam('__loginfailed')) {

			# cannot login for some reason
			$request->addResult("loginerror", 1);
			$request->addResult('count', 0);
	
			$request->setStatusDone();	
			return 1;

		} else {

			# login in progress, wave bye bye
			$request->setStatusProcessing();
			return 1;
		}
	}

	return 0;
}

# handles 'live365 genres'
sub cli_genresQuery {
	my $request = shift;
	
	$log->info("Begin Function");

	# check this is the correct query
	if ($request->isNotQuery([['live365'], ['genres']])) {

		$request->setStatusBadDispatch();
		return;
	}
	
	if (cli_manage_login($request)) {

		return;
	}
	
	$API->loadGenreList($request, \&cli_genresQuery_cb, \&cli_error_cb);

	$request->setStatusProcessing();
}

sub cli_genresQuery_cb {
	my $request = shift;
	my $list = shift;

	# get our parameters
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');

	my @genreList = @$list;

	if (!@genreList) {
	
		$request->addResult('networkerror', 1);
		$request->addResult('count', 0);
		
	}
	else {
		
		my $count = scalar @genreList;
	
		$request->addResult('count', $count);

		my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);

		if ($valid) {

			my $loopname = '@genres';
			my $cnt = 0;
			for my $genre (@genreList[$start..$end]) {
				$request->addResultLoop($loopname, $cnt, 'id', @$genre[1]);
				$request->addResultLoop($loopname, $cnt, 'name', @$genre[0]);
				$cnt++;
			}
		}
	}

	$request->setStatusDone();	
}

my %cli_sort_lookup = (
	'name' 	    => 'T:A',
	'bitrate'   => 'B:D',
	'rating'    => 'R:D',
	'listeners' => 'L:D',
);

# handles 'live365 stations'
sub cli_stationsQuery {
	my $request = shift;
	
	$log->info("Enter\n");

	# check this is the correct query
	if ($request->isNotQuery([['live365'], ['stations']])) {

		$request->setStatusBadDispatch();
		return;
	}
	
	# manage login
	if (cli_manage_login($request)) {

		return;
	}

	# get our parameter
	my $genre = $request->getParam('genre_id');

	$API->clearStationDirectory();

	if ($genre eq 'presets') {

		$API->loadMemberPresets(
			$genre,
			$request, 
			\&cli_stationsQuery_cb, 
			\&cli_error_cb
		);
	}
	else {
	
		# get the rest of our parameters
		my $index    = $request->getParam('_index');
		my $quantity = $request->getParam('_quantity');
		my $sort     = $request->getParam('sort');
		my $query    = $request->getParam('search');
		my $queryf   = $request->getParam('searchtype');
		
		# param checks & lookups
		if ($request->paramNotOneOfIfDefined($sort, [keys %cli_sort_lookup])) {
			$request->setStatusBadParams();
			return;
		}
		
		# use default sort or lookup definition
		if (defined $sort) {
			$sort = $cli_sort_lookup{$sort};
		}
		else {
			$sort = Slim::Utils::Prefs::get( 'plugin_live365_sort_order' );
		}
		
		# use default search field of lookup definition
		if (defined $queryf) {
			$queryf = $lookupSearchFields{$queryf};
		}
		else {
			$queryf = Slim::Utils::Prefs::get( 'plugin_live365_search_fields' );
		}
	
		# make sure genre is defined
		if (!defined $genre) {
			$genre = 'all';
		}

		# for pre-defined genres, look up the defition. Otherwise it is a genre id
		# returned by "live365 genres".
		if (defined $lookupGenres{$genre}) {
			$genre = $lookupGenres{$genre};
		}

		# perform our async magic with all params
		$API->loadStationDirectory(
			$genre, 
			$request, 
			\&cli_stationsQuery_cb, 
			\&cli_error_cb, 
			0,
			'genre'	       => $genre,
			'sort'	       => $sort,
			'rows'	       => $quantity,
			'first'	       => $index + 1,
			'searchfields' => $queryf,
			'searchdesc'   => $query,
		);
	}

	$request->setStatusProcessing();
}

sub cli_stationsQuery_cb {
	my $request = shift;
	my $list    = shift;

	my $count   = $API->getStationListLength();
	my $slist   = $API->{Stations};
	my $start   = 0;
	my $end     = scalar @$slist - 1;
	my $valid   = 1;

	#Data::Dump::dump($slist);

	if ($API->getStationSource() eq 'presets') {

		# need to handle paging here...
		my $index    = $request->getParam('_index');
		my $quantity = $request->getParam('_quantity');
		
		($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $count);		
	}

	$request->addResult('count', $count);
		
	if ($valid) {

		my $cnt = 0;
		for my $station (@$slist[$start..$end]) {
			$request->addResultLoop('@stations', $cnt, 'id', $station->{STATION_ID});
			$request->addResultLoop('@stations', $cnt, 'name', $station->{STATION_TITLE});
			$request->addResultLoop('@stations', $cnt, 'listeners', $station->{STATION_LISTENERS_ACTIVE});
			$request->addResultLoop('@stations', $cnt, 'maxlisteners', $station->{STATION_LISTENERS_MAX});
			$request->addResultLoop('@stations', $cnt, 'bitrate', $station->{STATION_CONNECTION});
			$request->addResultLoop('@stations', $cnt, 'rating', $station->{STATION_RATING});
			$request->addResultLoop('@stations', $cnt, 'quality', $station->{STATION_QUALITY_LEVEL});
			$request->addResultLoop('@stations', $cnt, 'access', $station->{LISTENER_ACCESS});
			$request->addResultLoop('@stations', $cnt, 'location', $station->{STATION_LOCATION});
			$request->addResultLoop('@stations', $cnt, 'broadcaster', $station->{STATION_BROADCASTER});
			
			# can be added if requested. Need tag?
			#$request->addResultLoop('@stations', $cnt, 'genres', $station->{STATION_GENRE}); # 'alternative, power pop, indie rock',
			#$request->addResultLoop('@stations', $cnt, 'description', $station->{STATION_DESCRIPTION}); # 'Music for people in their 30\'s who feel like they are in their 20\'s',
			#$request->addResultLoop('@stations', $cnt, 'broadcaster_url', $station->{STATION_BROADCASTER_URL}); # 'http://www.live365.com/stations/chickenjuggler',
			#$request->addResultLoop('@stations', $cnt, 'playlist', $station->{STATION_PLAYLIST_INFO}); # {'PlaylistEntry' => { 'Album' => 'RAISING HELL', 'Artist' => '   RUN-D.M.C.', 'Title' => 'YOU BE ILLIN\'' }},
			#$request->addResultLoop('@stations', $cnt, 'keywords', $station->{STATION_KEYWORDS}); # 'remix mix tivo itunes mobile dj party live free schedule email vip beer cigarettes rent'
			#$request->addResultLoop('@stations', $cnt, 'live365_attr', $station->{LIVE365_ATTRIBUTES}); # {'STATION_ATTR' => [ [Editor\'s pick]', [Professional]' ] },
			$cnt++;
		}
	}
	$request->setStatusDone();	
}

# handles "live365 playlist play..."
sub cli_playlistCommand {
	my $request = shift;
	
	$log->info("Begin Function");

	# check this is the correct query
	if ($request->isNotCommand([['live365'], ['playlist']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# manage login
	return if cli_manage_login($request);

	# get our parameter
	my $mode      = $request->getParam('_mode');
	my $stationid = $request->getParam('station_id');

	# param checks
	if ($request->paramUndefinedOrNotOneOf($mode, ['play', 'add'])) {
		$request->setStatusBadParams();
		return;
	}

	if (!defined $stationid) {
		$request->setStatusBadParams();
		return;
	}
	
	# load data about this station
	$API->loadInfoForStation(
		$stationid,
		$request,
		\&cli_playlistCommand_cb,
		\&cli_error_cb
	);
	
	$request->setStatusProcessing();	
}

sub cli_playlistCommand_cb {
	my $request = shift;

	# get params	
	my $mode   = $request->getParam('_mode');
	my $client = $request->client();
	my $play   = ($mode eq 'play');

	# data was loaded, get URL
	my $stationURL = $API->getStationInfoURL();

	$log->info("URL: $stationURL (from CLI)");
	
	Slim::Music::Info::setContentType($stationURL, 'mp3');
	Slim::Music::Info::setTitle($stationURL, $API->getStationInfoString('STATION_TITLE'));

	if ($play) {
		$client->execute([ 'playlist', 'clear' ] );
	}

	$client->execute([ 'playlist', 'add', $stationURL ] );

	if ($play) {
		$client->execute([ 'play' ] );
	}

	$request->setStatusDone();		
}

sub cli_error_cb {
	my $request = shift;
	
	$request->addResult('networkerror', 1);
	$request->addResult('count', 0);
	$request->setStatusDone();	
}

1;
