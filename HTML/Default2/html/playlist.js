/////////////////////////////
//                         //
//  Playlist -- Variables  //
//                         //
/////////////////////////////

var playlist = new Array();

var cansave = 0;
var playlistinfo = "";

var BY = ' by ';
var FROM = ' from ';

//////////////////////////////////////
//                                  //
//  Playlist -- Update And Display  //
//                                  //
//////////////////////////////////////

function updatePlaylist(args) {
	var url = webroot + "playlist.xml?player=" + currentPlayer;
	if (args) {
		url = url + args;
	}
	postback(url, updatePlaylist_handler);
}

function updatePlaylist_handler(req, url) {
	playlistnodes = req.responseXML.getElementsByTagName("playlistitem");
	var resp = req.responseXML;
	var newPlaylist = new Array();
	listbox = document.getElementById("playlist");


	csIndex = currentSong - 1;

	for (i = 0; i < playlistnodes.length; i++) {
		newitem = new Object();

		for (j = 0; j < playlistnodes[i].attributes.length; j++) {
			plni = playlistnodes[i].attributes[j];
			newitem[plni.name] = plni.value;
		}

		iv = playlistnodes[i].getElementsByTagName("title")[0];
		if (iv && iv.firstChild) newitem.title = iv.firstChild.data; else newitem.title = "";
		iv = playlistnodes[i].getElementsByTagName("artist")[0];
		if (iv && iv.firstChild) newitem.artist = iv.firstChild.data; else newitem.artist = "";
		if (iv) newitem.artistid = iv.getAttribute("id");
		if (iv) newitem.noartist = iv.getAttribute("no");
		iv = playlistnodes[i].getElementsByTagName("album")[0];
		if (iv && iv.firstChild) newitem.album = iv.firstChild.data; else newitem.album = "";
		iv = playlistnodes[i].getElementsByTagName("url")[0];
		if (iv && iv.firstChild) newitem.url = iv.firstChild.data; else newitem.url = "";
		newPlaylist.push(newitem);
	}

	if (playlist.length < newPlaylist.length) baselength = playlist.length;
	else baselength = newPlaylist.length;

	for (i = 0; i < baselength; i++) {
		newHTML = '<a onclick="doSelect(event)" class="plstitle">' + newPlaylist[i].title + '</a>'
		if (!newPlaylist[i].noalbum && newPlaylist[i].album != "") {
			newHTML += FROM + '<a onclick="doAlbum(event)">' + newPlaylist[i].album + '</a>';
		}
		if (!newPlaylist[i].noartist && newPlaylist[i].artist != "") {
			newHTML += BY + '<a onclick="doArtist(event)">' + newPlaylist[i].artist + '</a>';
		}

		if (listbox.rows[i].childNodes[0].innerHTML != newHTML) {
			listbox.rows[i].childNodes[0].innerHTML = newHTML;
		}

		if (listbox.rows[i].url != newPlaylist[i].url) {
			listbox.rows[i].url = newPlaylist[i].url;
		}
	}

	if (playlist.length < newPlaylist.length) {
		for (i = baselength; i < newPlaylist.length; i++) {
			theTR = listbox.insertRow(-1);
			theTR.url = newPlaylist[i].url;

			buttonsTD = document.createElement('td');
			buttonsTD.innerHTML = '<img onclick="doMoveDown(event)" src="html/images/playlist/down.gif"/>' +
				'<img onclick="doMoveUp(event)" src="html/images/playlist/up.gif"/><img oncli' +
				'ck="doRemove(event)" src="html/images/playlist/delete.gif"/>';
			buttonsTD.className = "playlistbuttons";

			titleTD = document.createElement('td');
			titleTD.innerHTML = '<a onclick="doSelect(event)" class="plstitle">'+newPlaylist[i].title+'</a>';
			if (!newPlaylist[i].noalbum && newPlaylist[i].album != "") {
				titleTD.innerHTML += FROM + '<a onclick="doAlbum(event)">' + newPlaylist[i].album + '</a>';
			}
			if (!newPlaylist[i].noartist && newPlaylist[i].artist != "") {
				titleTD.innerHTML += BY + '<a onclick="doArtist(event)">' + newPlaylist[i].artist + '</a>';
			}

			titleTD.className = "playlistitem";

			theTR.appendChild(titleTD);
			theTR.appendChild(buttonsTD);
		}
	}
	if (newPlaylist.length < playlist.length) {
		extras = playlist.length - baselength;
		for (i = 0; i < extras; i++) {
			listbox.deleteRow(baselength);
		}
	}

	highlightCurrentSong();

	playlist = newPlaylist;

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
			if (i % 2) {
				listbox.rows[i].className = "even";
			} else {
				listbox.rows[i].className = "odd";
			}
		}
	}
        if (currentSong > 0 && listbox.rows[currentSong - 1]) {
                listbox.rows[currentSong - 1].className += " currentsong";
        }
}

function displayPlaylistHeader() {
	if (cansave) {
		document.getElementById("savebutton").style.display = "inline";
	} else {
		document.getElementById("savebutton").style.display = "none";
	}

	// document.getElementById("playlistinfo").innerHTML = playlistinfo;
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
	playlist.splice(selIndex, 1);
	if (songCount == 1) {
		displayCurrentSong("", "", "");
	} else if ((selIndex == songCount - 1) && currentSong == songCount) {
		displayCurrentSong(playlist[0].title, playlist[0].artist, playlist[0].album);
	} else if (selIndex == currentSong - 1) { 
		displayCurrentSong(playlist[selIndex].title, playlist[selIndex].artist, playlist[selIndex].album);
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

	selrow = listbox.rows[selIndex - 1].childNodes[0].innerHTML;
	listbox.rows[selIndex - 1].childNodes[0].innerHTML = listbox.rows[selIndex].childNodes[0].innerHTML;
	listbox.rows[selIndex].childNodes[0].innerHTML = selrow;

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

	selrow = listbox.rows[selIndex].childNodes[0].innerHTML;
	listbox.rows[selIndex].childNodes[0].innerHTML = listbox.rows[selIndex + 1].childNodes[0].innerHTML;
	listbox.rows[selIndex + 1].childNodes[0].innerHTML = selrow;

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
		if (et.nodeType == 3) etpp = et.parentNode.parentNode.parentNode;
		else etpp = et.parentNode.parentNode;
		selIndex = etpp.rowIndex;
	} else {
		return;
	}
	if (selIndex < 0 || selIndex >= songCount) return;
	displayPlayMode("play");
	currentSong = selIndex + 1;
	displayCurrentSong(playlist[selIndex].title, playlist[selIndex].artist, playlist[selIndex].album);
	displayPlayString();
	highlightCurrentSong();

	cmdstring = "&p0=playlist&p1=jump&p2=" + selIndex;
	updateStatus(cmdstring);
}

function doArtist(e) {
	if (!e) var e = window.event;
	et = (e.target || e.srcElement);
	if (!et) return;
	if (et && et.parentNode && et.parentNode.parentNode) {
		if (et.nodeType == 3) etpp = et.parentNode.parentNode.parentNode;
		else etpp = et.parentNode.parentNode;
		selIndex = etpp.rowIndex;
	} else {
		return;
	}
	if (selIndex < 0 || selIndex >= songCount) return;

	browseurl("browsedb.html?hierarchy=artist,album,track&level=1&contributor.id=" + playlist[selIndex].artistid);
}

function doAlbum(e) {
	if (!e) var e = window.event;
	et = (e.target || e.srcElement);
	if (!et) return;
	if (et && et.parentNode && et.parentNode.parentNode) {
		if (et.nodeType == 3) etpp = et.parentNode.parentNode.parentNode;
		else etpp = et.parentNode.parentNode;
		selIndex = etpp.rowIndex;
	} else {
		return;
	}
	if (selIndex < 0 || selIndex >= songCount) return;

	browseurl("browsedb.html?hierarchy=album,track&level=1&album.id=" + playlist[selIndex].albumid);
}

function doSave() {
	browseurl("edit_playlist.html?saveCurrentPlaylist=1");
}

function doDownload() {
	if (controlLockout) return;
	document.location.href = "/playlist.m3u?player=" + currentPlayer; 
}

function doClear() {
	if (controlLockout) return;
	listbox = document.getElementById("playlist");
	displayCurrentSong("", "", "");
	playlist = new Array();
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
