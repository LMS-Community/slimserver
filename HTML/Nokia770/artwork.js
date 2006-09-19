var url = '[% webroot %]browsedb.html';
var parsedData;
var artistHrefTemplate = '[% webroot %]browsedb.html?hierarchy=album,track&amp;contributor.id=ARTIST&amp;level=1&player=[% playerURI %]';
var albumHrefTemplate = '[% webroot %]browsedb.html?hierarchy=album,track&level=1&album.id=ALBUM&player=[% playerURI %]';
var thumbHrefTemplate = '/music/COVER/thumb_250x250_f_000000.jpg';
var playAlbumTemplate = '[% webroot %]status.html?command=playlist&subcommand=loadtracks&album.id=ALBUM&player=[% playerURI %]';
var addAlbumTemplate = '[% webroot %]playlist.html?command=playlist&subcommand=addtracks&album.id=ALBUM&player=[% playerURI %]';
var blankRequest = 'hierarchy=album,track&level=0&artwork=2&player=00%3A04%3A20%3A05%3A1b%3A82&artwork=1&start=[% start %]&ajaxRequest=1';

var thisAlbum, thatAlbum;

[% PROCESS html/global.js %]
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

function showArrows(firstOne, secondOne, lastOne) {
	if (firstOne == '1') {
		Element.hide('last_cover');
		Element.show('next_cover');
	} else if (secondOne == lastOne) {
		Element.show('last_cover');
		Element.hide('next_cover');
	} else {
		Element.show('last_cover');
		Element.show('next_cover');
	}
}

function refreshThumbs(theData) {
	parsedData = fillDataHash(theData);
	showArrows(thisAlbum, thatAlbum, parsedData['last']);
	refreshThumb(parsedData, '1', thisAlbum);
	refreshThumb(parsedData, '2', thatAlbum);
}

function refreshThumb(theData, whichOne, thatOne) {
	parsedData = fillDataHash(theData);
	var thumbId = 'thumb_' + whichOne;
	var thumbKey = 'coverthumb_' + thatOne;
	var albumKey = 'albumid_' + thatOne;
	var playId = 'play_' + whichOne;
	var addId = 'add_' + whichOne;
	var thatThumb = parsedData[thumbKey];
	var thatAlbum = parsedData[albumKey];
	if ($(thumbId)) {
		var thumbHref = thumbHrefTemplate.replace('COVER', thatThumb);
		$(thumbId).src = thumbHref;
	}
	if ($(playId)) {
		var playHref = playAlbumTemplate.replace('ALBUM', thatAlbum);
		refreshHref(playId, playHref);
	}
	if ($(addId)) {
		var addHref = addAlbumTemplate.replace('ALBUM', thatAlbum);
		refreshHref(addId, addHref);
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
	refreshThumbs(parsedData);
}

function nextCover() {
	thisAlbum = thatAlbum;
	thatAlbum = parseInt(thatAlbum) + 1;
	refreshThumbs(parsedData);
}

function artworkBrowse(urlArgs, thisId, thatId) {
	thisAlbum = thisId;
	thatAlbum = thatId;
	getStatusData(urlArgs, refreshThumbs);
}

window.onload= function() {
	artworkBrowse(blankRequest, 1, 2);
	globalOnload();
}

