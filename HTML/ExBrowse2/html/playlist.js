/////////////////////////////
//                         //
//  Playlist -- Variables  //
//                         //
/////////////////////////////

var playlistNames = new Array();
var playlistURLs = new Array();
var playlistArtists = new Array();
var playlistAlbums = new Array();

var cansave = 0;
var playlistinfo = "";

var BY = ' by ';

//////////////////////////////////////
//                                  //
//  Playlist -- Update And Display  //
//                                  //
//////////////////////////////////////

function updatePlaylist(args) {
	var url = "/ExBrowse2/playlist.xml?player=" + currentPlayer;
	if (args) {
		url = url + args;
	}
	postback(url, updatePlaylist_handler);
}

function updatePlaylist_handler(req, url) {
	playlistnodes = req.responseXML.getElementsByTagName("playlistitem");
	var resp = req.responseXML;
	var newPlaylistNames = new Array();
	var newPlaylistURLs = new Array();
	var newPlaylistArtists = new Array();
	var newPlaylistAlbums = new Array();
	listbox = document.getElementById("playlist");


	csIndex = currentSong - 1;

	for (i = 0; i < playlistnodes.length; i++) {
		iv = playlistnodes[i].getElementsByTagName("title")[0];
		if (iv && iv.firstChild) newPlaylistNames.push(iv.firstChild.data); else newPlaylistNames.push("");
		iv = playlistnodes[i].getElementsByTagName("artist")[0];
		if (iv && iv.firstChild) newPlaylistArtists.push(iv.firstChild.data); else newPlaylistArtists.push("");
		iv = playlistnodes[i].getElementsByTagName("album")[0];
		if (iv && iv.firstChild) newPlaylistAlbums.push(iv.firstChild.data); else newPlaylistAlbums.push("");
		iv = playlistnodes[i].getElementsByTagName("url")[0];
		if (iv && iv.firstChild) newPlaylistURLs.push(iv.firstChild.data); else newPlaylistURLs.push("");
	}

	if (playlistNames.length < newPlaylistNames.length) baselength = playlistNames.length;
	else baselength = newPlaylistNames.length;

	for (i = 0; i < baselength; i++) {
		newHTML = '<a onclick="doSelect(event)">' + newPlaylistNames[i] + '</a>'
			+ BY + '<a onclick="doArtist(event)">' + newPlaylistArtists[i] + '</a>';
		if (listbox.rows[i].childNodes[2].innerHTML != newHTML) {
			listbox.rows[i].childNodes[2].innerHTML = newHTML;
		}

		newNum = i + 1 + "";
		if (listbox.rows[i].childNodes[1].innerHTML != newNum) {
			listbox.rows[i].childNodes[1].innerHTML = newNum;
		}

		if (listbox.rows[i].url != newPlaylistURLs[i]) {
			listbox.rows[i].url = newPlaylistURLs[i];
		}

		if (i == csIndex) {
			listbox.rows[i].className = "currentsong";
		} else {
			listbox.rows[i].className = "";
		}
	}

	if (playlistNames.length < newPlaylistNames.length) {
		for (i = baselength; i < newPlaylistNames.length; i++) {
			theTR = listbox.insertRow(i);
			theTR.url = newPlaylistURLs[i];
			if (i == csIndex) {
				theTR.className = "currentsong";
			} else {
				theTR.className = "";
			}

			buttonsTD = document.createElement('td');
			buttonsTD.innerHTML = '<img onclick="doRemove(event)" src="html/images/remove.gif"/><img ' +
				'onclick="doMoveUp(event)" src="html/images/move_up.gif"/><img onclick="doMoveDown(' +
				'event)" src="html/images/move_down.gif"/>';
			buttonsTD.className = "playlistbuttons";

			indexTD = document.createElement('td');
			indexTD.innerHTML = i + 1;
			indexTD.className = "playlistindex";

			titleTD = document.createElement('td');
			titleTD.innerHTML = '<a onclick="doSelect(event)">' + newPlaylistNames[i] + '</a>' + BY +
				'<a onclick="doArtist(event)">' + newPlaylistArtists[i] + '</a>';
			titleTD.className = "listing";

			theTR.appendChild(buttonsTD);
			theTR.appendChild(indexTD);
			theTR.appendChild(titleTD);
		}
	}
	if (newPlaylistNames.length < playlistNames.length) {
		extras = playlistNames.length - baselength;
		for (i = 0; i < extras; i++) {
			listbox.deleteRow(baselength);
		}
	}

	highlightCurrentSong();

	playlistNames = newPlaylistNames;
	playlistURLs = newPlaylistURLs;
	playlistArtists = newPlaylistArtists;
	playlistAlbums = newPlaylistAlbums;

	cansave = getdata(resp, "cansave");
	playlistinfo = getdata(resp, "playlistinfo");
	displayPlaylistHeader();	

	if (playlistRefs == 0) {
		playlistRefs++;
		maybeDoneLoading();
	}
}

function highlightCurrentSong() {
        listbox = document.getElementById("playlist");
	for (i = 0; i < songCount; i++) {
		if (listbox.rows[i]) {
			listbox.rows[i].className = "";
		}
	}
        if (currentSong > 0 && listbox.rows[currentSong - 1]) {
                listbox.rows[currentSong - 1].className = "currentsong";
        }
}

function displayPlaylistHeader() {
	if (cansave) {
		document.getElementById("savebutton").style.display = "inline";
	} else {
		document.getElementById("savebutton").style.display = "none";
	}

	document.getElementById("playlistinfo").innerHTML = playlistinfo;
}

////////////////////////////
//                        //
//  Playlist -- Commands  //
//                        //
////////////////////////////

function doRemove(e) {
	if (!e) var e = window.event;
	et = (e.target || e.srcElement);
	if (!et) return;
	if (et && et.parentNode && et.parentNode.parentNode) {
		selIndex = et.parentNode.parentNode.rowIndex;
	} else {
		return;
	}

	if (selIndex < 0) return;
	listbox = document.getElementById("playlist");
	listbox.deleteRow(selIndex);
	playlistNames.splice(selIndex, 1);
	playlistURLs.splice(selIndex, 1);
	playlistArtists.splice(selIndex, 1);
	playlistAlbums.splice(selIndex, 1);
	if (songCount == 1) {
		displayCurrentSong("", "", "");
	} else if ((selIndex == songCount - 1) && currentSong == songCount) {
		displayCurrentSong(playlistNames[0], playlistArtists[0], playlistAlbums[0]);
	} else if (selIndex == currentSong - 1) { 
		displayCurrentSong(playlistNames[selIndex], playlistArtists[selIndex], playlistAlbums[selIndex]);
	}

	if (selIndex < songCount - 1) {
		for (i = selIndex; i < songCount - 1; i++) {
                	listbox.rows[i].childNodes[1].innerHTML = i + 1;
		}
	}

	if (selIndex < (currentSong - 1)) {
		currentSong--;
	}

	songCount--;
	displayPlayString();
	highlightCurrentSong();

	cmdstring = "&p0=playlist&p1=delete&p2=" + selIndex;
	updateStatusCombined(cmdstring);
}

function doMoveUp(e) {
	if (!e) var e = window.event;
	et = (e.target || e.srcElement);
	if (!et) return;
	if (et && et.parentNode && et.parentNode.parentNode) {
		selIndex = et.parentNode.parentNode.rowIndex;
	} else {
		return;
	}
	if (selIndex < 1) return;
	listbox = document.getElementById("playlist");

	selrow = listbox.rows[selIndex - 1].childNodes[2].innerHTML;
	listbox.rows[selIndex - 1].childNodes[2].innerHTML = listbox.rows[selIndex].childNodes[2].innerHTML;
	listbox.rows[selIndex].childNodes[2].innerHTML = selrow;

	if (selIndex == currentSong) {
		currentSong++;
		displayPlayString();
	} else if (selIndex == (currentSong - 1)) {
		currentSong--;
		displayPlayString();
	}

	highlightCurrentSong();

	cmdstring = '&p0=playlist&p1=move&p2=' + selIndex + '&p3=%2D1';
	updateStatusCombined(cmdstring);
}

function doMoveDown(e) {
	if (!e) var e = window.event;
	et = (e.target || e.srcElement);
	if (!et) return;
	if (et && et.parentNode && et.parentNode.parentNode) {
		selIndex = et.parentNode.parentNode.rowIndex;
	} else {
		return;
	}
	if (selIndex < 0 || selIndex >= (songCount - 1)) return;

	selrow = listbox.rows[selIndex].childNodes[2].innerHTML;
	listbox.rows[selIndex].childNodes[2].innerHTML = listbox.rows[selIndex + 1].childNodes[2].innerHTML;
	listbox.rows[selIndex + 1].childNodes[2].innerHTML = selrow;

	if (selIndex == (currentSong - 1)) {
		currentSong++;
		displayPlayString();
	} else if (selIndex == (currentSong - 2)) {
		currentSong--;
		displayPlayString();
	}

	highlightCurrentSong();

	cmdstring = '&p0=playlist&p1=move&p2=' + selIndex + '&p3=%2B1';
	updateStatusCombined(cmdstring);
}

function doSelect(e) {
	if (!e) var e = window.event;
	et = (e.target || e.srcElement);
	if (!et) return;
	if (et && et.parentNode && et.parentNode.parentNode) {
		selIndex = et.parentNode.parentNode.rowIndex;
	} else {
		return;
	}
	if (selIndex < 0 || selIndex >= songCount) return;

	displayPlayMode("play");
	currentSong = selIndex + 1;
	displayCurrentSong(playlistNames[selIndex], playlistArtists[selIndex], playlistAlbums[selIndex]);
	displayPlayString();
	highlightCurrentSong();

	cmdstring = "&p0=playlist&p1=jump&p2=" + selIndex;
	updateStatus(cmdstring);
}

function doArtist(e) {
	if (!e) var e = window.event;
	et = (e.target || e.srcElement);
	if (!et) return;

	// XXX FIXME this is disabled until the artist id is provided in status_list.html
}

function doSave() {
	browseurl("browse.html?dir=__playlists/__current.m3u");
}

function doDownload() {
	document.location.href = "/playlist.m3u?player=" + currentPlayer; 
}

function doClear() {
	listbox = document.getElementById("playlist");
	displayCurrentSong("", "", "");
	playlistNames = new Array();
	playlistArtists = new Array();
	playlistAlbums = new Array();
	playlistURLs = new Array();
	for (i = 0; i < songCount; i++) {
		listbox.deleteRow(0);
	}
	currentSong = 0;
	songCount = 0;
        displayPlayMode("stop");
	lastCounterPos = 0;
	progressAt = 0;
	progressEnd = 0;
        totalTime = timetostr(0);
	songCounterUpdate();
	cansave = 0;
	playlistinfo = "";
	displayPlaylistHeader();
	updateStatusCombined("&p0=playlist&p1=clear");
}
