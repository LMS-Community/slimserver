var url = '[% webroot %]browsedb.html';
var parsedData;
var artistHrefTemplate = '[% webroot %]browsedb.html?hierarchy=album,track&amp;contributor.id=ARTIST&amp;level=1&player=[% playerURI %]';
var albumHrefTemplate = '[% webroot %]browsedb.html?hierarchy=album,track&level=1&album.id=ALBUM&player=[% playerURI %]';
var playAlbumTemplate = '[% webroot %]status.html?command=playlist&subcommand=loadtracks&album.id=ALBUM&player=[% playerURI %]';
var addAlbumTemplate = '[% webroot %]playlist.html?command=playlist&subcommand=addtracks&album.id=ALBUM&player=[% playerURI %]';
var blankRequest = 'hierarchy=album,track&level=0&artwork=2&player=00%3A04%3A20%3A05%3A1b%3A82&start=[% start %]&ajaxRequest=1';

var pAT = 'javascript:changeOSD("AlBuM [% "NOW_PLAYING" | string %]"); addItem("command=playlist&subcommand=loadtracks&album.id=ALBUM&player=[% playerURI %]")';
var aAT = 'javascript:changeOSD("[% "ADDING_TO_PLAYLIST" | string %] AlBuM"); addItem("command=playlist&subcommand=addtracks&album.id=ALBUM&player=[% playerURI %]")';

var thisAlbum, thatAlbum, clickedItem;

[% PROCESS skin_global.js %]

function addItem(args) {
	url = '[% webroot %]status.html';
        getStatusData(args, showAdded);
	url = '[% webroot %]browsedb.html';
}

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

function emptyFunction() {
	return true;
}

function showArrows(firstOne, secondOne, lastOne) {
	if (firstOne == '0') {
		if ($('last_cover_click')) {
			$('last_cover_click').onclick = emptyFunction;
			$('last_cover_click').src = '[% webroot %]html/images/rew.gif';
		}
		if ($('next_cover_click')) {
			$('next_cover_click').onclick = nextCover;
			$('next_cover_click').src = '[% webroot %]html/images/ffw_active.gif';
		}
	} else if (secondOne == lastOne) {
		if ($('last_cover_click')) {
			$('last_cover_click').onclick = lastCover;
			$('last_cover_click').src = '[% webroot %]html/images/rew_active.gif';
		}
		if ($('next_cover_click')) {
			$('next_cover_click').onclick = emptyFunction;
			$('next_cover_click').src = '[% webroot %]html/images/ffw.gif';
		}
	} else {
		if ($('last_cover_click')) {
			$('last_cover_click').onclick = lastCover;
			$('last_cover_click').src = '[% webroot %]html/images/rew_active.gif';
		}
		if ($('next_cover_click')) {
			$('next_cover_click').onclick = nextCover;
			$('next_cover_click').src = '[% webroot %]html/images/ffw_active.gif';
		}
	}
}

function refreshThumbs(theData) {
	parsedData = fillDataHash(theData);
	showArrows(thisAlbum, thatAlbum, parsedData['last']);
	hideAlbumInfo();
	refreshThumb(parsedData, '0', thisAlbum);
	refreshThumb(parsedData, '1', thatAlbum);
}

function refreshThumb(theData, whichOne, thatOne) {
	parsedData = fillDataHash(theData);
	var thumbId = 'cover_' + whichOne;
	var thumbKey = 'coverthumb_' + thatOne;
	var albumKey = 'albumid_' + thatOne;
	var albumTextKey = 'album_' + thatOne;
	var artistTextKey = 'artist_' + thatOne;
	var playId = 'play_' + whichOne;
	var addId = 'add_' + whichOne;
	var thatThumb = parsedData[thumbKey];
	var thatAlbum = parsedData[albumKey];
	var artistAlbum = parsedData[artistTextKey] + ' - ' + parsedData[albumTextKey];

	if ($(thumbId)) {
		var thumbHref = thumbHrefTemplate.replace('COVER', thatThumb);
		$(thumbId).src = thumbHref;
	}
	if ($(playId)) {
		//var playHref = playAlbumTemplate.replace('ALBUM', thatAlbum);
		var playHref = pAT.replace('ALBUM', thatAlbum);
		playHref = playHref.replace('AlBuM', artistAlbum);
		refreshHref(playId, playHref);
		//$(playId).onclick = playHref;
	}
	if ($(addId)) {
		//var addHref = addAlbumTemplate.replace('ALBUM', thatAlbum);
		var addHref = aAT.replace('ALBUM', thatAlbum);
		addHref = addHref.replace('AlBuM', artistAlbum);
		refreshHref(addId, addHref);
		//$(addId).onclick = addHref;
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

function popUpAlbumInfo(thisOne, albumId) {
	var lookupId;
	if (albumId) {
		lookupId = thisOne;
	} else {
		if (thisOne == 0) {
			clickedItem = thisAlbum;
		} else {
			clickedItem = thatAlbum;
		}
		var albumKey = 'albumid_' + clickedItem;
		lookupId = parsedData[albumKey];
	}
	
	// here we go-- get the album track details via an ajax call
	// pop up a list of the tracks in an inline div, including play/add buttons next to tracks
	// add a close button for the div to hide it
	if ($('albumInfo')) {
		$('trackInfo').innerHTML = '';
		Element.show('albumInfo');
		var newArgs = 'artwork=4&hierarchy=album,track&level=1&player=[% playerURI %]&album.id='+parseInt(lookupId);
		getStatusData(newArgs,updateTrackInfo);
	}
}

function updateTrackInfo(theData) {
	var myData = theData.responseText;
       	var showDivs = [ 'albumInfo', 'trackInfo', 'closeAlbumInfo' ];
        showDivs.each(function(key) {
		if ($(key)) {
			Element.setStyle(key, { border: '1px solid black' } );
			Element.show(key);
		}
	});
	if ($('trackInfo')) {
		$('trackInfo').innerHTML = myData;
	}
}

function hideAlbumInfo() {
	if ($('trackInfo')) {
		$('trackInfo').innerHTML = '';
	}
        var hideDivs = [ 'albumInfo', 'trackInfo', 'closeAlbumInfo' ];
        hideDivs.each(function(key) {
                if ($(key)) {
			Element.setStyle(key, { border: '0px'} );
			Element.hide(key);
                }
        });
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

function enlargeThumbs() {
	if (thumbSize == 700) {
		return;
	} else {
		thumbSize = thumbSize + 50;
		resizeThumbs();
	}
}

function shrinkThumbs() {
	if (thumbSize == 50) {
		return;
	} else {
		thumbSize = thumbSize - 50;
		resizeThumbs();
	}
}

function resizeThumbs() {
	thumbHrefTemplate = '/music/COVER/thumb_'+thumbSize+'x'+thumbSize+'_p.png';
	refreshThumbs(parsedData);
	setCookie( 'Squeezebox-thumbSize', thumbSize );
}

window.onload= function() {
	artworkBrowse(blankRequest, 0, 1);
	globalOnload();
}

