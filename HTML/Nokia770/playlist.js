var pageFirstItem = [% IF pageinfo.startitem %][% pageinfo.startitem %][% ELSE %]0[% END %];
var pageLastItem =  [% IF playlist_items.last.num %][% playlist_items.last.num %][% ELSE %]0[% END %];
var player = '[% playerURI %]';
var url = 'playlist.html';
var timeoutID = false;

var playlistBlankRequest = '[% webroot %]playlist.html?player=[% playerURI %]&ajaxRequest=1&start=[% pageinfo.startitem %]';
var trackHrefTemplate = '[% webroot %]songinfo.html?item=ITEM&amp;player=[% playerURI %]';
var artistHrefTemplate = '[% webroot %]browsedb.html?hierarchy=contributor,album,track&amp;contributor.id=ARTIST&amp;level=1&player=[% playerURI %]';
var albumHrefTemplate = '[% webroot %]browsedb.html?hierarchy=contributor,album,track&level=1&album.id=ALBUM&player=[% playerURI %]';

var deleteTrackNum = null;
var thisTrack;
var thatTrack;
var timeToRefresh = 20000;
var previousState = new Object();

[% PROCESS skin_global.js %]

// parses the data if it has not been done already
function fillDataHash(theData) {
	var returnData = null;
	if (theData['player_id']) { 
		return theData;
	} else {
		var myData = theData.responseText;
		returnData = parseData(myData);
		return returnData;
	}
}

function refreshTwo(theData) {
	var parsedData = fillDataHash(theData);
	refreshPlaylistElements(parsedData, thisTrack);
	refreshPlaylistElements(parsedData, thatTrack);
}

function refreshAll(theData) {
	var parsedData = fillDataHash(theData);
	var startTrack = getStartTrack(parsedData);
	// refresh playlist header
	if ($('playlistsize')) {
		$('playlistsize').innerHTML = parsedData['playlistsize'];
	}
	// refresh pagebar and pagebarheader
	var prefix = [ 'header_', 'footer_' ];
	var suffix = [ 'first_item', 'last_item', 'playlistsize' ];
	for (var i=0; i < prefix.length; i++) {
		for (var j=0; j < suffix.length; j++) {
			var thisId = prefix[i] + suffix[j];
			if ($(thisId)) {
				var key = suffix[j];
				if (key == 'playlistsize') {
					$(thisId).innerHTML = parsedData[key];
				} else {
					$(thisId).innerHTML = parseInt(parsedData[key])+1;
				}
			}
		}
	}

	// truncate rows that need not be there
	var cullRowStart = parseInt(parsedData['last_item']) - parseInt(parsedData['first_item']) + 1;
	truncateAt('playlist_table', cullRowStart);
	for (r=pageFirstItem; r <= pageLastItem; r++) {
		refreshPlaylistElements(parsedData, r);
	}
}

function refreshPlaylistElements(theData, r) {
	var parsedData = fillDataHash(theData);
	// items to refresh: tracklink, artistlink, albumlink
	var linkIds = { tracklink:  { id:'tracklink_', stub:trackHrefTemplate, replaceString: 'ITEM', key: 'item_', inner: 'title_'},
			albumlink:  { id: 'albumlink_', stub:albumHrefTemplate, replaceString: 'ALBUM', key: 'albumid_', inner: 'album_'}};
	for (obj in linkIds) {
		var thisId = linkIds[obj].id + r.toString();		
		var thisKeyId = linkIds[obj].key +r.toString();
		var thisKey = parsedData[thisKeyId];
		var stub = linkIds[obj].stub;
		var innerTextId = linkIds[obj].inner + r.toString();
		var innerText = parsedData[innerTextId];
		var replaceMe = eval("/" + linkIds[obj].replaceString + "/");
		if ($(thisId)) {
			var thisHref = stub.replace(replaceMe, thisKey);
			$(thisId).href = thisHref;
			$(thisId).innerHTML = innerText;
		}
	}
	var artist_elem = 'artist_' + r.toString();
	refreshElement('artist_' + r.toString(),parsedData[artist_elem]);
	refreshItemClass(parsedData, r);
}

function getStartTrack(theData) {
	var parsedData = fillDataHash(theData);
	if (deleteTrackNum != null) {
		return parseInt(deleteTrackNum);
	} else {
		var firstItem = parsedData['first_item'];
		return parseInt(firstItem);
	}
}

function refreshItemClass(theData, r) {
	var parsedData = fillDataHash(theData);
	var linkId = 'tracklink_' + r.toString();
	var table = $('playlist_table');
	var playingIds = [ 'pause_', 'playcurrent_', 'playnext_' ];
	var otherIds = [ 'remove_', 'play_', 'up_', 'next_', 'down_' ];
	var rowId = 'row' + r.toString();
	var oddKey = 'odd_' + r.toString();
	// this is the current song in the playlist
	if (parsedData['currentsongnum'] == r) {
		$(rowId).className = 'playing';
		$(linkId).className = 'playingitemtext';
		for (i=0; i<=otherIds.length; i++) {
			var thisId = otherIds[i] + r.toString();
			if ($(thisId)) {
				Element.hide(thisId);
			}
		}
		for (i=0; i<=playingIds.length; i++) {
			var thisId = playingIds[i] + r.toString();
			if ($(thisId)) {
				if (r == parseInt(parsedData['last_item']) && playingIds[i] == 'playnext_')  {
						Element.hide(thisId);
				} else {
					Element.show(thisId);
				}
			}
		}
	// this is not the current song in the playlist
	} else {
		if (parsedData[oddKey] == 1) {
			$(rowId).className = 'even';
		} else {
			$(rowId).className = 'odd';
		}
		$(linkId).className = 'itemtext';
		for (i=0; i<=otherIds.length; i++) {
			var thisId = otherIds[i] + r.toString();
			if ($(thisId)) {
				if (	(r == parseInt(parsedData['last_item']) && otherIds[i] == 'down_') ||
					(r == parseInt(parsedData['first_item']) && otherIds[i] == 'up_' )
				   )   {
					Element.hide(thisId);
				} else {
					Element.show(thisId);
				}
			}
		}
		for (i=0; i<=playingIds.length; i++) {
			var thisId = playingIds[i] + r.toString();
			if ($(thisId)) {
				Element.hide(thisId);
			}
		}
	}
}

// refreshes the className on the track name to indicate the currently playing track
function refreshPlayingTrack(theData) {
	var parsedData = fillDataHash(theData);
	refreshItemClass(parsedData, thisTrack);
}

// this function should be used solely for the more complicated 'next' request
function refreshOnNext(theData) {
	var parsedData = fillDataHash(theData);
	previousState = parsedData;
	var extraArg = parseInt(previousState['currentsongnum']);
	if (parseInt(thisTrack) > extraArg) {
		extraArg = extraArg + 1;
	}
	var nextTrackArgTemplate = 'p0=playlist&p1=move&p2=ITEM&player=[% playerURI %]&start=START&p3=EXTRA&ajaxRequest=1';
	nextTrackArgTemplate = nextTrackArgTemplate.replace(/ITEM/, thisTrack);
	nextTrackArgTemplate = nextTrackArgTemplate.replace(/EXTRA/, extraArg);
	nextTrackArgTemplate = nextTrackArgTemplate.replace(/START/, previousState['first_item']);
	var urlArgs = nextTrackArgTemplate;
	getStatusData(urlArgs, refreshAll);
	return true;
}

// this function is called after querying status.html. 
// this is only to update the timeToRefresh variable
// so playlist knows when to refresh
function refreshProgress(theData) {
	var parsedData = fillDataHash(theData);
	if (parseInt(parsedData['playmode']) == 1) {
		timeToRefresh = (parseInt(parsedData['durationseconds']) - parseInt(parsedData['songtime']))*1000 + 1000; // time left in seconds * 1000ms/1sec + 1second
	} else {
		timeToRefresh = 10000; // 10 seconds
	}
	if (timeToRefresh > 10000) {
		timeToRefresh = 10000; // 10 seconds
	}
	// set the timeout
	if (!timeoutID) {
		timeoutID = setTimeout("doPlaylistRefresh()", timeToRefresh-100);
	} else {
		clearTimeout(timeoutID);
		timeoutID = setTimeout("doPlaylistRefresh()", timeToRefresh-100);
	}
}

function doPlaylistRefresh() {
        var args = 'player='+player+'&ajaxRequest=1&start=[% pageinfo.startitem %]';
        getStatusData(args, refreshAll);
	setRefreshTime();
}

function playlistPlayTrack(urlArgs) {
	getStatusData(urlArgs, refreshAll);
	setRefreshTime();
}

function playlistNextTrack(urlArgs, thisRow) {
	thisTrack = thisRow;
	getStatusData(playlistBlankRequest, refreshOnNext);
	setRefreshTime();
}

function playlistSwapTrack(urlArgs, thisRow, otherRow) {
	thisTrack = thisRow;
	thatTrack = otherRow;
	getStatusData(urlArgs, refreshTwo);
}

function playlistDeleteTrack(trackNum, urlArgs) {
	deleteTrackNum = trackNum;
	getStatusData(urlArgs, refreshAll);
}

function setRefreshTime() {
	var args = 'player='+player+'&ajaxRequest=1';
	url = 'status.html';
	getStatusData(args, refreshProgress);
	url = 'playlist.html';
}

window.onload= function() {
	setRefreshTime();
	globalOnload();
}

