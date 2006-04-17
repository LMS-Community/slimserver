var url = 'browsedb.html';

var artistHrefTemplate = '[% webroot %]browsedb.html?hierarchy=artist,album,track&amp;artist=ARTIST&amp;level=1&player=[% playerURI %]';
var albumHrefTemplate = '[% webroot %]browsedb.html?hierarchy=album,track&level=1&album=ALBUM&player=[% playerURI %]';
var thumbHrefTemplate = '/music/COVER/cover.jpg';
//var blankRequest = '[% additionalLinks.browse.BROWSE_BY_ARTWORK %]&player=[% playerURI %]&artwork=1&ajaxRequest=1';
var blankRequest = 'hierarchy=artwork,track&level=0&sort=artist,year,album&&player=00%3A04%3A20%3A05%3A1b%3A82&artwork=1&start=[% start %]&ajaxRequest=1';
//blankRequest = blankRequest.replace('browsedb.html?','');

var thisAlbum;
var thatAlbum;

[% PROCESS html/global.js %]

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

function showArrows(firstOne, secondOne, lastOne) {
	if (firstOne == '0') {
		$('last_cover').style.display = 'none';
		$('next_cover').style.display = 'block';
	} else if (secondOne == lastOne) {
		$('last_cover').style.display = 'block';
		$('next_cover').style.display = 'none';
	} else {
		$('last_cover').style.display = 'block';
		$('next_cover').style.display = 'block';
	}
}

function refreshThumbs(theData) {
	var parsedData = fillDataHash(theData);
	showArrows(thisAlbum, thatAlbum, parsedData['last']);
	refreshThumb(parsedData, '1', thisAlbum);
	refreshThumb(parsedData, '2', thatAlbum);
}

function refreshThumb(theData, whichOne, thatOne) {
	var parsedData = fillDataHash(theData);
	var thumbId = 'thumb_' + whichOne;
	var albumKey = 'coverthumb_' + thatOne;
	var thatAlbum = parsedData[albumKey];
	if ($(thumbId)) {
		var thumbHref = thumbHrefTemplate.replace('COVER', thatAlbum);
		$(thumbId).src = thumbHref;
	}
	var textKeys = [ 'artist_', 'album_' ];
	for (var i = 0; i < textKeys.length; i++) {
		var thisIdKey = textKeys[i] + whichOne;
		var thisDataKey = textKeys[i] + thatOne;
		if ($(thisIdKey)) {
			$(thisIdKey).innerHTML = parsedData[thisDataKey];
		}
	}
}

function lastCover() {
	thatAlbum = thisAlbum;
	thisAlbum = parseInt(thisAlbum) - 1;
	artworkBrowse(blankRequest, thisAlbum, thatAlbum);
}

function nextCover() {
	thisAlbum = thatAlbum;
	thatAlbum = parseInt(thatAlbum) + 1;
	artworkBrowse(blankRequest, thisAlbum, thatAlbum);
}

function artworkBrowse(urlArgs, thisId, thatId) {
	thisAlbum = thisId;
	thatAlbum = thatId;
	getStatusData(urlArgs, refreshThumbs);
}

// create a table with all necessary elements for browsing artwork
function setupThumbTable() {
}

window.onload= function() {
//	setupThumbTable();
	artworkBrowse(blankRequest, 0, 1);
}

