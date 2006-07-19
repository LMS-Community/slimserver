/////////////////////////////////////////
//                                     //
//  Status Header -- Variables + Init  //
//                                     //
/////////////////////////////////////////

var lastCounterPos;
var counterResyncFlag;
var clearedLastTime;

var totalTime, progressAt, progressEnd;

var curPlayMode;

var currentSong;
var songCount;

var repMode, shufMode, curVol;

var controlLockout;

var lastCoverArt;

function initStatus() {
	volumeContainer = document.getElementById("volume");

	for (i = 0; i < 11; i++) {
		theA = document.createElement('DIV');
		theA.className = "fakelink volitem";
		if (i > 8) {
			theA.style.left = (i*17 - 36) + "px";
			theA.style.width = "17px";
		} else {
			theA.style.left = (i*13) + "px";
			theA.style.width = "13px";
		}
		theA.volval = i*10;
		theA.onclick = doVolume;

		volumeContainer.appendChild(theA);
		updateStatus();
		updatePlaylist();
	}

	document.getElementById("playlist").deleteRow(0);
	// XXX ^ that should be in initPlaylist, but it's not worth making another function for

	document.getElementById("playersel").options.length = 0;
/*
	updateCounterPeriodically();
*/
	document.onkeydown = handlekey;
}

function handlekey(e) {
	if (!e) e = window.event;
	if (e.keyCode) kc = e.keyCode;
	else if (e.which) kc = e.which;
	else return true;

	var tg = (e.target) ? e.target : e.srcElement;

	if (tg.name) return true;

	if (e.ctrlKey || e.altKey) return true;

	if (kc == 67) doPause();	// c
	else if (kc == 88) doPlay();	// x
	else if (kc == 66) doNext();	// b
	else if (kc == 90) doPrev();	// z
	else if (kc == 86) doStop();	// v
	else if (kc == 82) rotateRepeat();	// r
	else if (kc == 83) rotateShuffle();	// s
	else if (kc == 109 || kc == 189) decVolume();	// - (firefox 109, others 189)
	else if (kc == 61 || kc == 187) incVolume();	// = (firefox 61, others 187)
	else return true;

	return false;
}

function abortkey(e) {
	return true;
}

///////////////////////////////////////////
//                                       //
//  Status Header -- Update And Display  //
//                                       //
///////////////////////////////////////////

function updateStatus(args) {
	var url = webroot + "status_header.xml?player=" + currentPlayer;
	if (args) {
		url = url + args;
	}
	postback(url, updateStatus_handler);
}

function getdata(resp, respname) {
	resps = resp.getElementsByTagName(respname);
	if (resps && resps[0] && resps[0].firstChild) {
		return resps[0].firstChild.data;
	} else {
		return "";
	}
}

function updateStatus_handler(req, url) {
	var response = req.responseXML;
	var player = getdata(response, "playermodel");
	if (player == "NOPLAYER") {
		currentSong = 0;
		songCount = 0;
		progressEnd = 0;
		totalTime = ' ' + timetostr(progressEnd);
		displayPlayMode("stop");
		songCounterUpdate();

		displayPlayMode("none");
		displayRepeat(-1);
		displayShuffle(-1);
		displayCoverArt("");


		controlLockout = 1;
	} else {	
		controlLockout = 0;
//		document.getElementById("rightdeck").selectedIndex = 0;
//		document.getElementById("player").value = player;

		displayPlayerModel(getdata(response, "playermodel"));

		playmode = getdata(response, "playmode");

		currentSong = getdata(response, "currentsong");
		songCount = getdata(response, "songcount");

		displayPlayMode(playmode);

		progressAt = getdata(response, "songtime");
		progressEnd = getdata(response, "songlength");
	        totalTime = ' ' + timetostr(progressEnd);

		songCounterUpdate();

		var albumdisplay = getdata(response, "album");
		displayCurrentSong(getdata(response, "songtitle"), getdata(response, "artist"), albumdisplay);

		highlightCurrentSong();

		displayRepeat(getdata(response, "repeat"));
		displayShuffle(getdata(response, "shuffle"));

		displayVolume(getdata(response, "volume"));
	
		displayCoverArt(getdata(response, "coverart"));

	}

	if (response.getElementsByTagName("playlist").length > 0) {
		updatePlaylist_handler(req, url);
	}

	if (statusRefs == 0) {
		statusRefs++;
		maybeDoneLoading();
	}
}


function displayPlayMode(mode) {
	if (mode == "play") {
		document.getElementById("playbutton").className = "active";
		document.getElementById("pausebutton").className = "";
		document.getElementById("stopbutton").className = "";
		curPlayMode = "play";
	} else if (mode == "pause") {
		document.getElementById("playbutton").className = "";
		document.getElementById("pausebutton").className = "active";
		document.getElementById("stopbutton").className = "";
		curPlayMode = "pause";
	} else if (mode == "stop") {
		document.getElementById("playbutton").className = "";
		document.getElementById("pausebutton").className = "";
		document.getElementById("stopbutton").className = "active";
		curPlayMode = "stop";
	} else {
		document.getElementById("playbutton").className = "";
		document.getElementById("pausebutton").className = "";
		document.getElementById("stopbutton").className = "";
		curPlayMode = "none";
	}

	displayPlayString();	
}

function displayPlayString() {
	var playstring;
	if (curPlayMode == "play") {
		playstring = "Now playing";
	} else if (curPlayMode == "pause") {
		playstring = "Now paused on";
	} else {
		playstring = "Now stopped on";
	}
	if (currentSong != "") {
		playstring += " <b>" + currentSong + "</b> of <b>" + songCount + "</b>";
	}

	if (document.getElementById("playstring").innerHTML != playstring) {
		document.getElementById("playstring").innerHTML = playstring;
	}
}

function displayCurrentSong(song, artist, album) {
        // Checking first prevents flicker (at least with Firefox) on slow computers.

	var songstring = "<b>" + song;
	if (album != "") songstring += "</b> from <b>" + album;
	if (artist != "") songstring += "</b> by <b>" + artist;
	songstring += "</b>";

	if (document.getElementById("song").innerHTML != songstring) {
	       	document.getElementById("song").innerHTML = songstring;
	}
}

function displayRepeat(mode) {
	repMode = mode;
	if (mode == 1) {
		document.getElementById("repeatone").className = "fakelink active";
		document.getElementById("repeatall").className = "fakelink";
		document.getElementById("repeatoff").className = "fakelink";
	} else if (mode == 2) {
		document.getElementById("repeatone").className = "fakelink";
		document.getElementById("repeatall").className = "fakelink active";
		document.getElementById("repeatoff").className = "fakelink";
	} else if (mode == 0) {
		document.getElementById("repeatone").className = "fakelink";
		document.getElementById("repeatall").className = "fakelink";
		document.getElementById("repeatoff").className = "fakelink active";
	} else {
		document.getElementById("repeatone").className = "fakelink";
		document.getElementById("repeatall").className = "fakelink";
		document.getElementById("repeatoff").className = "fakelink";
	}
}

function displayShuffle(mode) {
	shufMode = mode;
	if (mode == 1) {
		document.getElementById("shufsongs").className = "fakelink active";
		document.getElementById("shufalbums").className = "fakelink";
		document.getElementById("shufnone").className = "fakelink";
	} else if (mode == 2) {
		document.getElementById("shufsongs").className = "fakelink";
		document.getElementById("shufalbums").className = "fakelink active";
		document.getElementById("shufnone").className = "fakelink";
	} else if (mode == 0) {
		document.getElementById("shufsongs").className = "fakelink";
		document.getElementById("shufalbums").className = "fakelink";
		document.getElementById("shufnone").className = "fakelink active";
	} else {
		document.getElementById("shufsongs").className = "fakelink";
		document.getElementById("shufalbums").className = "fakelink";
		document.getElementById("shufnone").className = "fakelink";
	}
}

function displayVolume(volume) {
	curVol = volume;

	for (i = 0; i < 11; i++) {
		document.getElementById("volume").childNodes[i].style.background = "transparent";
	}

	i = Math.floor(volume / 10);
	volnode = document.getElementById("volume").childNodes[i];
	/* volnode.style.background = "red"; */
	
	bkgstr = "url(html/images/volume_sel.gif) -";
	if (i > 8) {
		bkgstr += (i*17 - 36);
	} else {
		bkgstr += (i*13);
	}
	bkgstr += "px -2px no-repeat";

	volnode.style.background = bkgstr;
}

function displayCoverArt(url) {
/*
	if (url != "") {
		if (url != lastCoverArt) {
			document.getElementById("coverart").src = "/music/" + url + "/thumb.jpg";
			lastCoverArt = url;
		}
		document.getElementById("coverart").style.display = "block";
		document.getElementById("playtext").style.left = "120px";
		document.getElementById("playtext").style.width = "270px";
	} else {
		document.getElementById("coverart").style.display = "none";
		document.getElementById("playtext").style.left = "10px";
		document.getElementById("playtext").style.width = "380px";
	}
*/
}

function displayPlayerModel(model) {
	document.getElementById("logo").src = "html/images/" + model + "_logo.gif";
}


/////////////////////////////////
//                             //
//  Status Header -- Commands  //
//                             //
/////////////////////////////////

function doPlayerChange(event) {
	currentPlayer = document.getElementById("playersel").value;
	updateStatusCombined();
}

function doPlay() {
	if (controlLockout) return;
	if (curPlayMode != "play") {
		displayPlayMode("play");
		updateStatus("&p0=play");
	}
}

function doPause() {
	if (controlLockout) return;
	if (curPlayMode != "play") {
		displayPlayMode("play");
		updateStatus("&p0=play");
	} else {
		displayPlayMode("pause");
		updateStatus("&p0=pause");
	}
}

function doStop() {
	if (controlLockout) return;
	displayPlayMode("stop");
	updateStatus("&p0=stop");
}

function doPrev() {
	if (controlLockout) return;
	currentSong--;
	if (currentSong == 0) currentSong = songCount;
	displayCurrentSong(playlist[currentSong - 1].title, playlist[currentSong - 1].artist, playlist[currentSong - 1].album);
	displayPlayMode("play");
	progressAt = 0;
	resyncSongCounter();
	highlightCurrentSong();
	updateStatus('&p0=playlist&p1=jump&p2=-1');
}

function doNext() {
	if (controlLockout) return;
	currentSong++;
	if (currentSong > songCount) currentSong = 1;
	displayCurrentSong(playlist[currentSong - 1].title, playlist[currentSong - 1].artist, playlist[currentSong - 1].album);
	displayPlayMode("play");
	progressAt = 0;
	resyncSongCounter();
	highlightCurrentSong();
	updateStatus('&p0=playlist&p1=jump&p2=%2b1');
}

function doVolume(e) {
	if (controlLockout) return;
	if (!e) e = window.event;
	if (e.target) et = e.target; else et = e.srcElement;
	if (et.volval == 0) et.volval = "0";
	if (et.volval) {
		displayVolume(et.volval);
		updateStatus("&p0=mixer&p1=volume&p2=" + et.volval);
	}
}

function incVolume() {
	// Firefox seems to think that 20 + 10 = 2010...
	curVol -= -10;
	if (curVol > 100) curVol = 100;
	displayVolume(curVol);
	updateStatus("&p0=mixer&p1=volume&p2=" + curVol);
}

function decVolume() {
	curVol -= 10;
	if (curVol < 0) curVol = 0;
	displayVolume(curVol);
	updateStatus("&p0=mixer&p1=volume&p2=" + curVol);
}

function doRepeat(repmode) {
	if (controlLockout) return;
	displayRepeat(repmode);
	cmdstring = "&p0=playlist&p1=repeat&p2=" + repmode;
	updateStatus(cmdstring);
}

function rotateRepeat() {
	repMode++;
	if (repMode == 3) repMode = 0;
	doRepeat(repMode);
}

function doShuffle(shufmode) {
	if (controlLockout) return;
	displayShuffle(shufmode);
	cmdstring = "&p0=playlist&p1=shuffle&p2=" + shufmode;
	updateStatusCombined(cmdstring);
	updatePlaylist();
}

function rotateShuffle() {
	shufMode++;
	if (shufMode == 3) shufMode = 0;
	doShuffle(shufMode);
}

function songCounterUpdate() {
	/*var progbar = document.getElementById("progressBar");

	if (curPlayMode == "stop" || curPlayMode == "none") {
		if (clearedLastTime != 1) {
			for (i = 0; i < 50; i++) { 
				progbar.childNodes[i].src = "html/images/pixel.png";
			}
			progbar.lastChild.nodeValue = ' ' + timetostr(0) + ' / ' + totalTime;
			clearedLastTime = 1;
			lastCounterPos = 0;
		}
	} else {
		clearedLastTime = 0;

		p = Math.floor(progressAt * 50 / progressEnd);

		if (p == lastCounterPos) {
		} else if (p == lastCounterPos + 1) {
			progbar.childNodes[p].src = "html/images/pixel_s.png";
		} else {
			for (i = 0; i < 50; i++) { 
				progbar.childNodes[i].src = "html/images/pixel" + (i <= p ? '_s' : '') + ".png";
			}
		}

		if (progressEnd == 0) {
			progbar.lastChild.nodeValue = ' ' + timetostr(progressAt);
		} else {
			progbar.lastChild.nodeValue = ' ' + timetostr(progressAt) + ' / ' + totalTime;
		}

		lastCounterPos = p;
	}
*/
}

function timetostr(t) {
	mins = Math.floor(t / 60);
	secs = (t % 60);
	if (secs == 0) {
		return mins + ':00';
	} else if (secs < 10) {
		return mins + ':0' + secs;
	} else {
		return mins + ':' + secs;
	}
}

function updateCounterPeriodically() {
	if (counterResyncFlag == 1) {
		counterResyncFlag = 0;
		return;
	}
	setTimeout("updateCounterPeriodically()", 1000);

	if (curPlayMode == "play") { 
		progressAt++;
		if(progressAt > progressEnd && progressEnd > 0) progressAt = progressAt % progressEnd;
	}
	songCounterUpdate();
}

function resyncSongCounter() {
	songCounterUpdate();
}

