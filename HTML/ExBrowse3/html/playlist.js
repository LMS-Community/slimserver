/* * * * * * * * *\
 *   Playlist    *
\* * * * * * * * */

var playlistcombo;
var playlistObj;

var itemsPerCall = 50;

function getPlaylistInit() {
	// get the playlist, then go back to continue loading the page
	if (!curPlayer) return;

	getPlaylist(mainload);
	return { async: true };
}

function getPlaylist(callbackfunc, newArr) {
	if (!curPlayer) return;
	if (playlistcombo.getEl().isDragging) return;

	if (!newArr) newArr = [];

	// recursively download new playlist items
	ss.call("slim.getPlaylist", [ curPlayer, newArr.length, itemsPerCall ], function(rv) {
		if (rv.result.length == itemsPerCall) {
			// if we got all the items we requested, then check for more
			getPlaylist(callbackfunc, newArr.concat(rv.result));
		} else {
			// otherwise, we've hit the end - save, update, and callback
			playlistObj = newArr.concat(rv.result);
			updatePlaylist();
			if (callbackfunc) callbackfunc();
		}
	} );
}

function updatePlaylist() {
	var combolist = [ ];

	for (var i = 0; i < playlistObj.length; i++) {
		var newitem = { title :
			(playlistObj[i].tracknum ?
				(
					(playlistObj[i].album && playlistObj[i].album.discc && playlistObj[i].album.disc) ?
					(playlistObj[i].album.disc + '-') :
					''
				) + playlistObj[i].tracknum + '. '
				: ''
			) +
			'<a onclick="doSelect(event)">' +
			playlistObj[i].title +
			'</a> ' +
			(
				(playlistObj[i].album && playlistObj[i].album.title) ?
				(
					JXTK2.String.getString("FROM") +
					' <a onclick="doAlbum(' + playlistObj[i].album.id + ')">' +
					playlistObj[i].album.title + '</a> '
				) :
				''
			) +
			(
				(playlistObj[i].contributors[0] && playlistObj[i].contributors[0].name) ?
				(
					JXTK2.String.getString("BY") +
					' <a onclick="doArtist(' + playlistObj[i].contributors[0].id + ')">' +
					playlistObj[i].contributors[0].name + '</a>'
				) :
				''
			)
		};
		combolist.push(newitem);
	}

	playlistcombo.selectedIndex = currentSong - 1; 
	playlistcombo.update(combolist);
}

function doSelect(event) {
	event = JXTK2.Misc.fixEvent(event);
	var selIndex = event.targ.parentNode.parentNode.index;

	curPlayMode = "play";
	currentSong = selIndex;
	progressAt = 0;

	updateStatus();

	ss.call('slim.doCommand', [ curPlayer, [ 'playlist', 'jump', selIndex ] ], true);
}

function doArtist(id) {
        browseurl("browsedb.html?hierarchy=contributor,album,track&level=1&contributor.id=" + id);
}

function doAlbum(id) {
        browseurl("browsedb.html?hierarchy=album,track&level=1&album.id=" + id);
}

function playlistXButtonHandler(button) {
	var selIndex = button.getEl().parentNode.parentNode.index;
	if (selIndex < 0 || songCount <= 0) return;

	playlistObj.splice(selIndex, 1);

	songCount--;
	if (selIndex == currentSong) progressAt = 0;
	if (selIndex < currentSong ) currentSong--;
	if ((songCount == 0) || (selIndex == songCount && currentSong == songCount)) currentSong = 0;

	playlistcombo.deleteRow(selIndex);

	updateStatus();

	ss.call('slim.doCommand', [ curPlayer, [ 'playlist', 'delete', selIndex ] ], true);
}

function playlistDragEndHandler(movecount, elementpos) {
	var newpos = elementpos + movecount;

	var dsong = playlistObj.splice(elementpos, 1)[0];
	playlistObj.splice(newpos, 0, dsong);

	if (elementpos == currentSong) currentSong = newpos;
	else if (elementpos < currentSong && newpos >= currentSong) currentSong--;
	else if (elementpos > currentSong && newpos <= currentSong) currentSong++;

	updatePlaylist();
	updateStatus();

	ss.call('slim.doCommand', [ curPlayer, [ 'playlist', 'move', elementpos, newpos ] ], true);
}

function doSave() {
	// XXX FIXME: Consider whether a JXTK::TextButton widget would be good for these buttons

	browseurl("edit_playlist.html?saveCurrentPlaylist=1");
}

function doDownload() {
	document.location.href = "/playlist.m3u?player=" + curPlayer;
}

function doClear() {
	playlist = new Array();
	playlistcombo.update(playlist);
	currentSong = 0;
	songCount = 0;
	curPlayMode = "stop";
	progressAt = 0;
	updateStatus();
	ss.call('slim.doCommand', [ curPlayer, [ 'playlist', 'clear' ] ], true);
}

function initPlaylist() {
	var buttonsTemplate = document.createElement('div');
        buttonsTemplate.className = "playlistbuttons";

	var xButton = document.createElement('img');
	xButton.src = 'html/images/remove.gif';
	xButton.title = JXTK2.String.getString("DELETE");
	xButton.alt = JXTK2.String.getString("DELETE");
	buttonsTemplate.appendChild(xButton);

	var dragButton = document.createElement('img');
	dragButton.src = 'html/images/moveupdown.gif';
	dragButton.className = 'dragbutton';
	dragButton.title = JXTK2.String.getString("MOVE");
	dragButton.alt = JXTK2.String.getString("MOVE");
	buttonsTemplate.appendChild(dragButton);

	playlistcombo = new JXTK2.ComboList("playlist", buttonsTemplate, function(clist, row) {
		var xButtonObj = new JXTK2.Button(row.firstChild.firstChild);
		xButtonObj.addClickHandler(playlistXButtonHandler);
		clist.makeRowDraggable(row, row.firstChild.childNodes[1], playlistDragEndHandler);
	});

	playlistcombo.setScrollBase(document.getElementById("outerplaylist"));
}

