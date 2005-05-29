/////////////////////////////
//                         //
//  Playlist -- Variables  //
//                         //
/////////////////////////////

var playlist = new Array();

var cansave = 0;
var playlistinfo = "";

var BY;
var FROM;

//////////////////////
//                  //
// Playlist -- Drag //
//                  //
//////////////////////

function playlistDragMove(dragEvent) {
	var helpers = ToolMan.helpers();
	var coordinates = ToolMan.coordinates();
	var opl = document.getElementById("outerplaylist");

	var item = dragEvent.group.element;
	var xmouse = dragEvent.transformedMouseOffset;
	var moveTo = null;

	var previous = helpers.previousItem(item, item.nodeName);
	while (previous != null) {
		var bottomRight = coordinates.bottomRightOffset(previous);
		if (xmouse.y <= (bottomRight.y - opl.scrollTop) && xmouse.x <= bottomRight.x) {
			moveTo = previous;
			dragEvent.group.movecount--;
		}
		previous = helpers.previousItem(previous, item.nodeName);
	}
	if (moveTo != null) {
		helpers.moveBefore(item, moveTo);
		return;
	}

	var next = helpers.nextItem(item, item.nodeName);
	while (next != null) {
		var topLeft = coordinates.topLeftOffset(next);
		if ((topLeft.y - opl.scrollTop) <= xmouse.y && topLeft.x <= xmouse.x) {
			moveTo = next;
			dragEvent.group.movecount++;
		}
		next = helpers.nextItem(next, item.nodeName);
	}
	if (moveTo != null) {
		helpers.moveBefore(item, helpers.nextItem(moveTo, item.nodeName));
		return;
	}


}
function playlistDragEnd(dragEvent) {
	ToolMan.coordinates().create(0, 0).reposition(dragEvent.group.element);

	dragEvent.group.element.parentNode.isDragging = 0;

	var elementpos = dragEvent.group.element.pos;
	var elementparent = dragEvent.group.element.parentNode;

	if ((dragEvent.group.movecount >= 1) || (dragEvent.group.movecount <= -1)) {
		newpos = dragEvent.group.movecount + elementpos;
		cmdstring = '&p0=playlist&p1=move&p2=' + elementpos + '&p3=' + newpos;
		updateStatusCombined(cmdstring);
	}

	for (i = 0; i < elementparent.childNodes.length; i++) {
		elementparent.childNodes[i].pos = i;
		elementparent.childNodes[i].childNodes[1].innerHTML = i + 1;
	}

}

function playlistDragMakeSortable(item, handle) {
	var coordinates = ToolMan.coordinates();
	listbox = document.getElementById("playlist");

	var group = ToolMan.drag().createSimpleGroup(item, handle);

	// This is unnecessary if we have a separate handle:
	//group.setThreshold(4);

	var min, max;

	group.register('dragstart', function(dragEvent) {
		dragEvent.group.movecount = 0;
		dragEvent.group.element.parentNode.isDragging = 1;

		var items = listbox.getElementsByTagName("li");
		min = coordinates.topLeftOffset(items[0]);
		max = coordinates.topLeftOffset(items[items.length - 1]);
	});

	group.register('dragmove', playlistDragMove);
	group.register('dragend', playlistDragEnd);

	group.addTransform(function(coordinate, dragEvent) {
		return coordinate.constrainTo(min, max);
	});

	group.verticalOnly();
}

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

function updatePlaylistList(resp, listbox) {
	var playlistnodes = resp.getElementsByTagName("playlistitem");
	var newPlaylist = new Array();

	var baselength;
	var csIndex = currentSong - 1;

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
		iv = playlistnodes[i].getElementsByTagName("album")[0];
		if (iv && iv.firstChild) newitem.album = iv.firstChild.data; else newitem.album = "";
		iv = playlistnodes[i].getElementsByTagName("url")[0];
		if (iv && iv.firstChild) newitem.url = iv.firstChild.data; else newitem.url = "";
		newPlaylist.push(newitem);
	}

	if (playlist.length < newPlaylist.length) baselength = playlist.length;
	else baselength = newPlaylist.length;

	for (i = 0; i < baselength; i++) {
		newHTML = '<a onclick="doSelect(event)">' + newPlaylist[i].title + '</a>';
		if (!newPlaylist[i].noartist && newPlaylist[i].artist != "") {
			newHTML += BY + '<a onclick="doArtist(event)">' + newPlaylist[i].artist + '</a>';
		}

		if (listbox.childNodes[i].childNodes[2].innerHTML != newHTML) {
			listbox.childNodes[i].childNodes[2].innerHTML = newHTML;
		}

		newNum = i + 1 + "";
		if (listbox.childNodes[i].childNodes[1].innerHTML != newNum) {
			listbox.childNodes[i].childNodes[1].innerHTML = newNum;
		}

		if (listbox.childNodes[i].url != newPlaylist[i].url) {
			listbox.childNodes[i].url = newPlaylist[i].url;
		}

		if (i == csIndex) {
			listbox.childNodes[i].className = "currentsong";
		} else {
			listbox.childNodes[i].className = "";
		}
		listbox.childNodes[i].pos = i;
	}

	if (playlist.length < newPlaylist.length) {
		for (i = baselength; i < newPlaylist.length; i++) {
			theTR = document.createElement('li');

			theTR.url = newPlaylist[i].url;
			theTR.pos = i;

			if (i == csIndex) {
				theTR.className = "currentsong";
			} else {
				theTR.className = "";
			}

			buttonsTD = document.createElement('div');
			//buttonsTD.innerHTML = '<img onclick="doRemove(event)" src="html/images/remove.gif"/><img ' +
			//	'onclick="doMoveUp(event)" src="html/images/move_up.gif"/><img onclick="doMoveDown(' +
			//	'event)" src="html/images/move_down.gif"/>';
			buttonsTD.innerHTML = '<img onclick="doRemove(event)" src="html/images/remove.gif"/>';
			buttonsTD.className = "playlistbuttons";

			dragButton = document.createElement('img');
			dragButton.src = 'html/images/moveupdown.gif';
			dragButton.className = 'dragbutton';
			buttonsTD.appendChild(dragButton);

			indexTD = document.createElement('div');
			indexTD.innerHTML = i + 1;
			indexTD.className = "playlistindex";

			titleTD = document.createElement('div');
			newHTML = '<a onclick="doSelect(event)">' + newPlaylist[i].title + '</a>'
			if (!newPlaylist[i].noartist && newPlaylist[i].artist != "") {
				newHTML += BY + '<a onclick="doArtist(event)">' + newPlaylist[i].artist + '</a>';
			}
			titleTD.innerHTML = newHTML;
			titleTD.className = "playlistlisting";

			theTR.appendChild(buttonsTD);
			theTR.appendChild(indexTD);
			theTR.appendChild(titleTD);

			listbox.appendChild(theTR);

			playlistDragMakeSortable(theTR, dragButton);
		}
	}

	if (newPlaylist.length < playlist.length) {
		extras = playlist.length - baselength;
		for (i = 0; i < extras; i++) {
			listbox.removeChild(listbox.childNodes[baselength]);
		}
	}

	highlightCurrentSong();

	playlist = newPlaylist;
}


function updatePlaylist_handler(req, url) {
	var resp = req.responseXML;
	var listbox = document.getElementById("playlist");

	if (!listbox.isDragging) {
		updatePlaylistList(resp, listbox);
	}

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
		if (listbox.childNodes[i]) {
			listbox.childNodes[i].className = "";
		}
	}
        if (currentSong > 0 && listbox.childNodes[currentSong - 1]) {
                listbox.childNodes[currentSong - 1].className = "currentsong";
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
		selIndex = et.parentNode.parentNode.pos;
	} else {
		return;
	}

	if (selIndex < 0) return;
	listbox = document.getElementById("playlist");
	listbox.removeChild(listbox.childNodes[selIndex]);
	playlist.splice(selIndex, 1);
	if (songCount == 1) {
		displayCurrentSong("", "", "");
	} else if ((selIndex == songCount - 1) && currentSong == songCount) {
		displayCurrentSong(playlist[0].title, playlist[0].artist, playlist[0].album);
	} else if (selIndex == currentSong - 1) { 
		displayCurrentSong(playlist[selIndex].title, playlist[selIndex].artist, playlist[selIndex].album);
	}

	if (selIndex < songCount - 1) {
		for (i = selIndex; i < songCount - 1; i++) {
                	listbox.childNodes[i].childNodes[1].innerHTML = i + 1;
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
		selIndex = et.parentNode.parentNode.pos;
	} else {
		return;
	}
	if (selIndex < 1) return;
	listbox = document.getElementById("playlist");

	selrow = listbox.childNodes[selIndex - 1].childNodes[2].innerHTML;
	listbox.childNodes[selIndex - 1].childNodes[2].innerHTML = listbox.childNodes[selIndex].childNodes[2].innerHTML;
	listbox.childNodes[selIndex].childNodes[2].innerHTML = selrow;

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
		selIndex = et.parentNode.parentNode.pos;
	} else {
		return;
	}
	if (selIndex < 0 || selIndex >= (songCount - 1)) return;

	selrow = listbox.childNodes[selIndex].childNodes[2].innerHTML;
	listbox.childNodes[selIndex].childNodes[2].innerHTML = listbox.childNodes[selIndex + 1].childNodes[2].innerHTML;
	listbox.childNodes[selIndex + 1].childNodes[2].innerHTML = selrow;

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
		etpp = et.parentNode.parentNode;
		if (etpp.parentNode.pos) {
			selIndex = etpp.parentNode.pos;
		} else {
			selIndex = etpp.pos;
		}
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
		etpp = et.parentNode.parentNode;
		if (etpp.parentNode.pos) {
			selIndex = etpp.parentNode.pos;
		} else {
			selIndex = etpp.pos;
		}
	} else {
		return;
	}
	if (selIndex < 0 || selIndex >= songCount) return;

	browseurl("browsedb.html?hierarchy=artist,album,track&level=1&artist=" + playlist[selIndex].artistid);
}

function doAlbum(e) {
	if (!e) var e = window.event;
	et = (e.target || e.srcElement);
	if (!et) return;
	if (et && et.parentNode && et.parentNode.parentNode) {
		etpp = et.parentNode.parentNode;
		if (etpp.parentNode.rowIndex) {
			selIndex = etpp.parentNode.rowIndex;
		} else {
			selIndex = etpp.rowIndex;
		}
	} else {
		return;
	}
	if (selIndex < 0 || selIndex >= songCount) return;

	browseurl("browsedb.html?hierarchy=album,track&level=1&album=" + playlist[selIndex].albumid);
}

function doSave() {
	browseurl("browse.html?dir=__playlists/__current.m3u");
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
		listbox.removeChild(listbox.firstChild);
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
