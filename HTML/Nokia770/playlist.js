var player = '[% playerURI %]';
var url = 'playlist.html';
var intervalID = false;

var trackHrefTemplate = '[% webroot %]songinfo.html?item=ITEM&amp;player=[% playerURI %]';
var artistHrefTemplate = '[% webroot %]browsedb.html?hierarchy=artist,album,track&amp;artist=ARTIST&amp;level=1&player=[% playerURI %]';
var albumHrefTemplate = '[% webroot %]browsedb.html?hierarchy=album,track&level=1&album=ALBUM&player=[% playerURI %]';

var deleteTrackNum;

[% PROCESS global.js %]

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

function refreshAll(theData) {
	inc = 0;
	var parsedData = fillDataHash(theData);
	// rewrite playlist_table from row 1 to row X
	refreshTable(parsedData);
}

function refreshTable(theData) {
	var parsedData = fillDataHash(theData);
	var startTrack = getStartTrack(theData);
	for (r=startTrack; r <= parsedData['last_item']; r++) {
		// items to refresh: tracklink, artistlink, albumlink
		var linkIds = { tracklink:  { id:'tracklink_', stub:trackHrefTemplate, replaceString: 'ITEM', key: 'item_', inner: 'title_'},
				artistlink: { id: 'artistlink_', stub:artistHrefTemplate, replaceString: 'ARTIST', key: 'artistid_', inner: 'artist_'},
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
	}
	// truncate rows that need not be there
	var cullRowStart = parseInt(parsedData['last_item'])+1;
	truncateAt('playlist_table', cullRowStart);

	// make current song have the right controls and className
	refreshItemClass(theData);
}

function refreshPlaylistElements(theData) {
	var parsedData = fillDataHash(theData);
}

function getStartTrack(theData) {
	var parsedData = fillDataHash(theData);
	if (deleteTrackNum != 0) {
		return parseInt(deleteTrackNum) - 1;
	} else {
		return parsedData['first_item'];
	}
}

// refreshes the className on the track name to indicate the currently playing track
function refreshItemClass(theData) {
	var parsedData = fillDataHash(theData);
	var table = $('playlist_table');
	var playingIds = [ 'pause_', 'playcurrent_' ];
	var otherIds = [ 'remove_', 'play_', 'up_', 'next_', 'down_' ];
	var startTrack = getStartTrack(theData) ;
	for (r=startTrack; r <= parsedData['last_item']; r++) {
		var linkId = 'tracklink_' + r;
		var removeId = 'remove_' + r;
		var pauseId = 'pause_' + r;
		var playId = 'play_' + r;
		var playCurrentId = 'playcurrent_' + r;
		var upId = 'up_' + r;
		var nextId = 'next_' + r;
		if (parsedData['currentsongnum'] == r) {
			$(linkId).className = 'playingitemtext';
			for (i=0; i<=otherIds.length; i++) {
				var thisId = otherIds[i] + r;
				if ($(thisId)) {
					$(thisId).style.display = 'none';
				}
			}
			for (i=0; i<=playingIds.length; i++) {
				var thisId = playingIds[i] + r;
				if ($(thisId)) {
					$(thisId).style.display = 'block';
				}
			}
		} else {
			$(linkId).className = 'itemtext';
			for (i=0; i<=otherIds.length; i++) {
				var thisId = otherIds[i] + r;
				if ($(thisId)) {
					$(thisId).style.display = 'block';
				}
			}
			for (i=0; i<=playingIds.length; i++) {
				var thisId = playingIds[i] + r;
				if ($(thisId)) {
					$(thisId).style.display = 'none';
				}
			}
		}
	}
}

function refreshNothing(theData) {
	return true;
}

function playlistPlayTrack(urlArgs) {
	getStatusData(urlArgs, refreshItemClass);
}

function swapTrack(urlArgs, thisRow, otherRow) {
	getStatusData(urlArgs, refreshAll);
	// swap thisRow with otherRow
}

function deleteTrack(trackNum, urlArgs) {
	deleteTrackNum = trackNum;
	getStatusData(urlArgs, refreshAll);
}

/*
window.onload= function() {
	var args = 'player='+player+'&ajaxRequest=1';
	getStatusData(args, refreshAll);
}
*/

