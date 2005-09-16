/* * * * * * * * *\
 *    Status     *
\* * * * * * * * */

var statusbackend;

var playbutton, stopbutton;
var prevbutton, nextbutton;
var repeatbuttons = new Array();
var shufflebuttons = new Array();
var powerbuttons = new Array();
var volumebar, progressbar, progresstext;
var playstringtext, songtext, artisttext, albumtext;

var statusObj;

var progressAt = 0, progressEnd = 0, progressEndText = "0:00";
var curPlayMode;
var lastCoverArt, currentSong, songCount;

var curRep, curShuf;

function doBrowseCommand(cmd, args) {
	var cmds;

	if (typeof cmd == "array") {
		cmds = cmd;
	} else if (typeof cmd == "object") {
		// I don't know why this happens...
		cmds = new Array();
		for (var i = 0; i < cmd.length; i++) cmds.push(cmd[i]);
	} else if (cmd == "addtracks" || cmd == "loadtracks") {
		cmds = [ 'playlist', cmd, args ];
	} else {
		cmds = [ 'playlistcontrol', 'cmd:' + cmd ];

		var carr = args.split('&');
		if (carr[0] == '') carr.shift();

		for (var i = 0; i < carr.length; i++) {
			var cp = carr[i].split('=');
			cmds.push(cp[0] + '_id:' + cp[1]);
		}
	}

	ss.call("slim.doCommand", [ curPlayer, cmds ]);
	getStatus();
}

function doBrowseTreeCommand(cmd, args) {
	ss.call("slim.doCommand", [ curPlayer, [ 'playlist', cmd, args ] ]);
	getStatus();
}

function getStatusPeriodically() {
	getStatus();
	setTimeout(getStatusPeriodically, 5000);
}

function makeRepShufClosure(i, buttonlist, cmdarr) {
	cmdarr.push(i);
	return function() {
		for (var j = 0; j < buttonlist.length; j++) {
			buttonlist[j].setState(j == i ? true : false);
		}
		curRep = i;
		ss.call("slim.doCommand", [ curPlayer, cmdarr ], true);
	}
}

function timetostr(t) {
	var mins = Math.floor(t / 60);
	var secs = (t % 60);
	if (secs == 0) {
		return mins + ':00';
	} else if (secs < 10) {
		return mins + ':0' + secs;
	} else {
		return mins + ':' + secs;
	}
}

function updateProgressBar() {
	if (curPlayMode == "play" || curPlayMode == "pause") {
		progressbar.setValue(progressAt / progressEnd * 50);
		if (progressEnd == 0) {
			progresstext.setText(' ' + timetostr(progressAt));
		} else {
			progresstext.setText(' ' + timetostr(progressAt) + ' / ' + progressEndText);
		}
	} else {
		progressbar.setValue(-1);
		progresstext.setText(' 0:00 / ' + progressEndText);
	}
}

function updateCounterPeriodically() {
	setTimeout("updateCounterPeriodically()", 1000);

	if (curPlayMode == "play") {
		progressAt++;
		if(progressAt > progressEnd && progressEnd > 0) progressAt = progressAt % progressEnd;
	}
	updateProgressBar();
}

function incVolume() {
	var cv = volumebar.getValue();
	cv++;
        if (cv > 10) cv = 10;
	volumebar.setValue(cv);
	ss.call("slim.doCommand", [ curPlayer, [ "mixer", "volume", cv * 10 ] ], true);
}

function decVolume() {
	var cv = volumebar.getValue();
	cv--;
        if (cv < 0) cv = 0;
	volumebar.setValue(cv);
	ss.call("slim.doCommand", [ curPlayer, [ "mixer", "volume", cv * 10 ] ], true);
}

function rotateRepeat() {
	curRep++;
	if (curRep == 3) curRep = 0;
	for (var i = 0; i < 3; i++) repeatbuttons[i].setState(i == curRep);
	ss.call("slim.doCommand", [ curPlayer, [ "playlist", "repeat", curRep ] ], true);
}

function rotateShuffle() {
	curShuf++;
	if (curShuf == 3) curShuf = 0;
	for (var i = 0; i < 3; i++) shufflebuttons[i].setState(i == curShuf);
	ss.call("slim.doCommand", [ curPlayer, [ "playlist", "shuffle", curShuf ] ]);
	getPlaylist();
	getStatus();
}


function updateStatus() {
	var playstring;
	if (curPlayMode == "play") {
		playstring = "Now playing";
		playbutton.setState(true);
		stopbutton.setState(false);
	} else if (curPlayMode == "pause") {
		playstring = "Now paused on";
		playbutton.setState(false);
		stopbutton.setState(false);
	} else {
		playstring = "Now stopped on";
		playbutton.setState(false);
		stopbutton.setState(true);
	}

	if (songCount > 0) {
		songtext.setText(playlistObj[currentSong].title);

		if (playlistObj[currentSong].contributors[0] && playlistObj[currentSong].contributors[0].name)
			artisttext.setText(playlistObj[currentSong].contributors[0].name);
		else 
			artisttext.setText('');

		if (playlistObj[currentSong].album && playlistObj[currentSong].album.title)
			albumtext.setText(playlistObj[currentSong].album.title);
		else
			albumtext.setText('');

		progressEnd = Math.round(playlistObj[currentSong].secs);
		playstring += " <b>" + (currentSong - -1) + "</b> of <b>" + songCount + "</b>";
	} else {
		songtext.setText('');
		artisttext.setText('');
		albumtext.setText('');
		progressEnd = 0;
	}

	playstringtext.setText(playstring);

	if (playlistObj[currentSong] && playlistObj[currentSong].cover) {
		if (playlistObj[currentSong].id != lastCoverArt) {
			document.getElementById("coverart").src = "/music/" + playlistObj[currentSong].id + "/thumb.jpg";
			lastCoverArt = playlistObj[currentSong].id;
		}
		document.getElementById("coverart").style.display = "block";
		document.getElementById("playtext").style.left = "120px";
		document.getElementById("playtext").style.width = "270px";
	} else {
		document.getElementById("coverart").style.display = "none";
		document.getElementById("playtext").style.left = "10px";
		document.getElementById("playtext").style.width = "380px";
	}

	progressEndText = timetostr(progressEnd);
	updateProgressBar();

	playlistcombo.selectIndex(currentSong);
}

function getStatusPeriodically() {
	getStatus();
	setTimeout(getStatusPeriodically, 10000);
}

function getStatus() {
	if (!curPlayer) return;

	var statusobj = ss.call("slim.doCommand", [ curPlayer, [ "status" ] ]).result;
	var so = unCLI(statusobj);

	currentSong = so.playlist_cur_index;
	if (currentSong == undefined) currentSong = -1;
	songCount = so.playlist_tracks;
	if (songCount == undefined) songCount = 0;

	// Only redownload the playlist if it seems to have changed.
	if ((!playlistObj) ||
	    (songCount != playlistObj.length) ||
	    (!playlistObj[currentSong]) ||
	    (Math.round(playlistObj[currentSong].secs) != Math.round(so.duration))) {
		getPlaylist();
	} 

	curPlayMode = so.mode;
	curRep = so['playlist repeat'];
	for (var i = 0; i < 3; i++) repeatbuttons[i].setState(i == curRep);

	curShuf = so['playlist shuffle'];
	for (var i = 0; i < 3; i++) shufflebuttons[i].setState(i == curShuf);

	powerbuttons[0].setState(so.power == 0);
	powerbuttons[1].setState(so.power == 1);

	volumebar.setValue(so['mixer volume'] / 10);

	progressAt = Math.round(so.time);
	var newProgressEnd = Math.round(so.duration);
	if (progressEnd != newProgressEnd) {
		progressEnd = newProgressEnd;
		progressEndText = timetostr(progressEnd);
	}

	updateStatus();
}


function initStatusControls() {
	playbutton = new JXTK2.Button("playbutton", function() {
		if (curPlayMode != "play") {
			curPlayMode = "play";
		} else {
			curPlayMode = "pause";
		}
		updateStatus();
		ss.call("slim.doCommand", [ curPlayer, [ "pause" ] ], true);
	});

	playbutton.useKey(88); // x
	playbutton.useKey(67); // c

	stopbutton = new JXTK2.Button("stopbutton", function() {
		curPlayMode = "stop";
		progressAt = 0;
		updateStatus();
		ss.call("slim.doCommand", [ curPlayer, [ "stop" ] ], true);
	});

	stopbutton.useKey(86); // v

	prevbutton = new JXTK2.Button("prevbutton", function() {
		currentSong--;
		if (currentSong == -1) currentSong = songCount - 1;
		curPlayMode = "play";
		progressAt = 0;
		updateStatus();
		ss.call("slim.doCommand", [ curPlayer, [ "playlist", "jump", "-1" ] ], true);
	});

	prevbutton.useKey(90); // z

	nextbutton = new JXTK2.Button("nextbutton", function() {
		currentSong++;
		if (currentSong >= songCount) currentSong = 0;
		curPlayMode = "play";
		progressAt = 0;
		updateStatus();
		ss.call("slim.doCommand", [ curPlayer, [ "playlist", "jump", "+1" ] ], true);
	});

	nextbutton.useKey(66); // b

	for (var i = 0; i < 3; i++) {
		repeatbuttons[i] = new JXTK2.Button("repeat" + i, makeRepShufClosure(i, repeatbuttons, [ "playlist", "repeat" ]));
	}

	for (var i = 0; i < 3; i++) {
		shufflebuttons[i] = new JXTK2.Button("shuf" + i, makeRepShufClosure(i, shufflebuttons, [ "playlist", "shuffle" ]));
	}

	powerbuttons[0] = new JXTK2.Button("power0", makeRepShufClosure(0, powerbuttons, [ "power" ]));
	powerbuttons[1] = new JXTK2.Button("power1", makeRepShufClosure(1, powerbuttons, [ "power" ]));

	playstringtext = new JXTK2.Textbox("playstring");

	songtext = new JXTK2.Textbox("song");
	artisttext = new JXTK2.Textbox("artist");
	albumtext = new JXTK2.Textbox("album");

	document.getElementById("coverart").style.display = "none";
	document.getElementById("playtext").style.left = "10px";
	document.getElementById("playtext").style.width = "380px";

	volumebar = new JXTK2.ButtonBar("volume");
	volumebar.populate("IMG", 11, "html/images/volpixel_t.gif", 4, 2);
	volumebar.addClickHandler(function (button) {
		var cv = button.index;
		volumebar.setValue(cv);
		ss.call("slim.doCommand", [ curPlayer, [ "mixer", "volume", cv * 10 ] ], true);
	});

	progressbar = new JXTK2.ButtonBar("progressbar");
	progressbar.populate("IMG", 50, "html/images/pixel.gif");

	progresstext = new JXTK2.Textbox("progresstext");

	JXTK2.Key.registerKey(61, incVolume);  // = (firefox)
	JXTK2.Key.registerKey(187, incVolume); // = (others)
	JXTK2.Key.registerKey(109, decVolume); // - (firefox)
	JXTK2.Key.registerKey(189, decVolume); // - (others)
	JXTK2.Key.registerKey(82, rotateRepeat);  // r
	JXTK2.Key.registerKey(83, rotateShuffle); // s
}

function initStatus() {
	initStatusControls();

	updateCounterPeriodically();
}

