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

var controlLockout;

function initStatus() {
        progbar = document.getElementById("progressBar");

        for (i = 0; i < 50; i++) {
                theImg = document.createElement('IMG');
                theImg.height = 8;
                theImg.width = 4;
                theImg.hspace = 1;
                theImg.border = 0;
                theImg.src = 'html/images/pixel.png';
                progbar.appendChild(theImg);
        }
        theTxt = document.createTextNode(' ');
        progbar.appendChild(theTxt);

        volumeContainer = document.getElementById("volume");

        for (i = 0; i < 11; i++) {
                theImg = document.createElement('IMG');
                theImg.style.height = (i*2 + 4) + "px";
                theImg.style.width = "7px";
                theImg.src = 'html/images/volpixel.png';
                theImg.hspace = 0;
                theImg.volval = i*10;
                theImg.onclick = doVolume;
                theImg.className = "fakelink";
                volumeContainer.appendChild(theImg);
        }

	document.getElementById("playlist").deleteRow(0);
	// XXX ^ that should be in initPlaylist, but it's not worth making another function for

	document.getElementById("playersel").options.length = 0;

	updateCounterPeriodically();
}

///////////////////////////////////////////
//                                       //
//  Status Header -- Update And Display  //
//                                       //
///////////////////////////////////////////

function updateStatus(args) {
	var url = "/ExBrowse2/status_header.xml?player=" + currentPlayer;
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
		document.getElementById("stopbutton").className = "";
		curPlayMode = "play";
        } else {
                document.getElementById("playbutton").className = "";

		if (mode == "pause") {
			document.getElementById("stopbutton").className = "";
			curPlayMode = "pause";
		} else if (mode == "stop") {
			document.getElementById("stopbutton").className = "active";
			curPlayMode = "stop";
		} else {
			document.getElementById("stopbutton").className = "";
			curPlayMode = "none";
		}
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

	if (document.getElementById("song").innerHTML != song) {
        	document.getElementById("song").innerHTML = song;
	}

        if (document.getElementById("artist").innerHTML != artist) {
        	document.getElementById("artist").innerHTML = artist;
	}

	if (document.getElementById("album").innerHTML != album) {
		document.getElementById("album").innerHTML = album;
	}
}

function displayRepeat(mode) {
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
        for (i = 0; i*10 <= volume; i++) {
                document.getElementById("volume").childNodes[i].src = 'html/images/volpixel_s.png';
        }
        for (; i < 11; i++) {
                document.getElementById("volume").childNodes[i].src = 'html/images/volpixel.png';
        }
}

function displayCoverArt(url) {
	if (url != "") {
		document.getElementById("coverart").src = "/music/" + url + "/thumb.jpg";
		document.getElementById("coverart").style.position = "";
		document.getElementById("coverart").style.visibility = "visible";
	} else {
		document.getElementById("coverart").style.position = "absolute";
		document.getElementById("coverart").style.visibility = "hidden";
	}
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
        if (curPlayMode == "play") {
                displayPlayMode("pause");
                updateStatus("&p0=pause");
	} else {
                displayPlayMode("play");
                updateStatus("&p0=play");
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
        displayCurrentSong(playlistNames[currentSong - 1], playlistArtists[currentSong - 1], playlistAlbums[currentSong - 1]);
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
        displayCurrentSong(playlistNames[currentSong - 1], playlistArtists[currentSong - 1], playlistAlbums[currentSong - 1]);
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

function doRepeat(repmode) {
	if (controlLockout) return;
	displayRepeat(repmode);
        cmdstring = "&p0=playlist&p1=repeat&p2=" + repmode;
        updateStatus(cmdstring);
}

function doShuffle(shufmode) {
	if (controlLockout) return;
	displayShuffle(shufmode);
        cmdstring = "&p0=playlist&p1=shuffle&p2=" + shufmode;
        updateStatusCombined(cmdstring);
        updatePlaylist();
}

function songCounterUpdate() {
	var progbar = document.getElementById("progressBar");

	if (curPlayMode == "stop" || curPlayMode == "none") {
		if (clearedLastTime != 1) {
			for (i = 0; i < 50; i++) { 
        			progbar.childNodes[i].src = "html/images/pixel.png";
			}
        		progbar.lastChild.nodeValue = ' ' + timetostr(0) + ' / ' + totalTime;
			clearedLastTime = 1;
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

