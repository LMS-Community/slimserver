/* * * * * * * * *\
 *   Playlist    *
\* * * * * * * * */

var playlistcombo;
var playlist = new Array();

function playlistHandler(resp) {
	if (playlistcombo.parent.isDragging) return;

	var playlistnodes = resp.xml.getElementsByTagName("playlistitem");
	var newPlaylist = new Array();

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

	playlist = newPlaylist;

	var combolist = new Array();
	for (i = 0; i < playlistnodes.length; i++) {
		newitem = new Object();
		newitem.title = '<a onclick="doSelect(event)">' + newPlaylist[i].title + '</a>';
		if (!newPlaylist[i].noartist && newPlaylist[i].artist != "") {
			newitem.title += JXTK.String("BY") + '<a onclick="doArtist(event)">' + newPlaylist[i].artist + '</a>';
		}
		combolist.push(newitem);
	}

	playlistcombo.selectedIndex = currentSong - 1; 
	playlistcombo.update(combolist);
}

function doSelect(event) {
	event = JXTK.Misc().fixEvent(event);
	var selIndex = event.targ.parentNode.parentNode.index;

	curPlayMode = "play";
	currentSong = selIndex + 1;
	displaySong(playlist[selIndex].title, playlist[selIndex].artist, playlist[selIndex].album);
	updatePlayString();
	playlistcombo.selectIndex(selIndex);
	progressAt = 0;

	// XXX FIXME:  The length of the song should be in playlist[] as well, but it's not available from
	// XXX FIXME  Slim::Web::Pages::buildPlaylist. Unfortunately buildPlaylist is already a "hot loop",
	// XXX FIXME  but hopefully pulling the length out of the DB won't add much. Hopefully.
	
	updateProgressBar();

	statusbackend.submit("&p0=playlist&p1=jump&p2=" + selIndex);
}

function doArtist(event) {
	event = JXTK.Misc().fixEvent(event);
	var selIndex = event.targ.parentNode.parentNode.index;

        browseurl("browsedb.html?hierarchy=artist,album,track&level=1&artist=" + playlist[selIndex].artistid);
}

function playlistXButtonHandler(button) {
	var selIndex = button.el.parentNode.parentNode.index
	if (selIndex < 0 || songCount <= 0) return;

	playlist.splice(selIndex, 1);
	if (selIndex <= (currentSong - 1)) {
		currentSong--;
	}
	songCount--;

	if (songCount == 0) {
		displaySong("", "", "");
		currentSong = 0;
	} else if ((selIndex == songCount) && currentSong == songCount) {
		displaySong(playlist[0].title, playlist[0].artist, playlist[0].album);
	} else if (selIndex == currentSong - 1) {
		displaySong(playlist[selIndex].title, playlist[selIndex].artist, playlist[selIndex].album);
	}

	updatePlayString();

	playlistcombo.deleteRow(selIndex);
	if (songCount > 0) playlistcombo.selectIndex(currentSong - 1);

	statusbackend.submit("&p0=playlist&p1=delete&p2=" + selIndex);
}

function playlistDragEndHandler(movecount, elementpos) {
	var newpos = movecount + elementpos;
	statusbackend.submit('&p0=playlist&p1=move&p2=' + elementpos + '&p3=' + newpos);
}

function initPlaylist() {
	var buttonsTemplate = document.createElement('div');
        buttonsTemplate.className = "playlistbuttons";

	var xButton = document.createElement('img');
	xButton.src = 'html/images/remove.gif';
	buttonsTemplate.appendChild(xButton);

	var dragButton = document.createElement('img');
	dragButton.src = 'html/images/moveupdown.gif';
	dragButton.className = 'dragbutton';
	buttonsTemplate.appendChild(dragButton);

	playlistcombo = JXTK.ComboList().createComboList("playlist", buttonsTemplate, function(row) {
		var xButtonObj = JXTK.Button().createButtonFromTag(row.firstChild.firstChild);
		xButtonObj.addClickHandler(playlistXButtonHandler);

		this.makeRowDraggable(row, row.firstChild.childNodes[1], playlistDragEndHandler);
	});

	playlistcombo.setScrollBase(document.getElementById("outerplaylist"));

	statusbackend.addHandler(playlistHandler);
}

