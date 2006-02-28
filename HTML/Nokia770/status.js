var alreadyParsed = false;
var player = '[% player %]';
var _progressEnd = [% IF durationseconds %][% durationseconds %]+8[% ELSE %][% refresh %][% END %];
var _progressAt = [% IF songtime %][% songtime %][% ELSE %]0[% END %];
var _progressBarWidth = 788;
var p = 1;
var inc = 0;
var intervalID = false;

// xmlHttpRequest of ajaxRequest.txt through status.html
function getStatusData(params, action) {
	var url = 'status.html';
	var myAjax = new Ajax.Request(
		url, 
		{
			method: 'get', 
			parameters: params, 
			onComplete: action
		});
}

function doRefresh() {
        var args = 'player='+player+'&ajaxRequest=1';
        getStatusData(args, refreshAll);
}

// Update the progress dialog with the current state
function refreshProgressBar(theData) {
	var parsedData = fillDataHash(theData);
	// update duration time
	if ($('duration')) {
		$('duration').innerHTML = '';
		if (parsedData['duration']) {
			$('duration').innerHTML = parsedData['duration'];
		}
	}
	_progressAt = parseInt(parsedData['songtime'], 10);
	_progressEnd = parseInt(parsedData['durationseconds'], 10);
	setProgressBarWidth();
	if (!intervalID) {
		progressUpdate();
	}
}

function progressUpdate() {
	if ($('playtextmode').innerHTML.match('playing')) {
		inc++;
		_progressAt++;
		setProgressBarWidth();
		// do an ajax update every 20 seconds while playing
		if (inc == 20) {
		        var args = 'player='+player+'&ajaxRequest=1';
			getStatusData(args, refreshAll);
			inc = 0;
		}
		// player is playing, therefore run this function again in 1 second
		if (!intervalID) {
			intervalID = setInterval("progressUpdate()", 1000);
		}
	// do not run progressUpdate if the player is not playing
	} else {
		inc = 0;
		clearIntervalCall();
	}
}

function clearIntervalCall() {
	if (intervalID) {
		clearInterval(intervalID);
		intervalID = false;
	}
}

function setProgressBarWidth() {
	if ( _progressAt >= _progressEnd) {
		_progressAt = _progressEnd;
		clearIntervalCall();
		doRefresh();
	}
	p = ( _progressBarWidth / _progressEnd) * _progressAt;
	document.getElementById("progressBar").width=p+" ";
}

// parses the data if it has not been done already
function fillDataHash(theData) {
	var returnData = null;
	if (alreadyParsed) {
		returnData = theData;
	} else {
		var myData = theData.responseText;
		returnData = parseData(myData);
		//alreadyParsed = true;
	}
	return returnData;
}

function refreshNothing() {
	return true;
}

function refreshAll(theData) {
	inc = 0;
	// stop progress bar refreshing for this track
	clearIntervalCall();
	//var parsedData = fillDataHash(theData);
	refreshControls(theData);
	refreshOtherElements(theData);
	refreshProgressBar(theData);
}

function refreshControls(theData) {

	var parsedData = fillDataHash(theData);
	// refresh control_display in songinfo section
	refreshPlayerStatus(theData);

	// refresh player controls
	var selected=null;
	if (parsedData['playmode'] == 0) {
		selected = 'stop';
	} else if (parsedData['playmode'] == 1) {
		selected = 'play';
	} else if (parsedData['playmode'] == 2) {
		selected = 'pause';
	}
	playerButtonControl('player', selected, '', true);
	// refresh shuffle controls
	// refresh repeat controls
	// refresh volume (?)
	refreshVolumeControl(theData);
}

function refreshVolumeControl(theData) {
	var parsedData = fillDataHash(theData);
	var levels = [0, 20, 35, 50, 75, 80, 85, 90, 95, 100];
	for (var i=0; i < levels.length; i++) {
		var key = 'bar_'+levels[i];
		var activeKey = 'bar_active_'+levels[i];
		var turnOn = null;
		var turnOff = null;
		var intVolume = parseInt(parsedData['volume'], 10);
		if (intVolume == 0 && levels[i] == 0) {
			turnOn = activeKey;
			turnOff = key;
		} else if (levels[i] == 0) {
			turnOn = key;
			turnOff = activeKey;
		} else if (intVolume >= levels[i]) {
			turnOn = activeKey;
			turnOff = key;
		} else {
			turnOn = key;
			turnOff = activeKey;
		}
		if ($(turnOff)) {
			document.getElementById(turnOff).style.display = "none";
		}
		if ($(turnOn)) {
			document.getElementById(turnOn).style.display = "block";
		}
	}
}

function refreshPlayerStatus(theData) {
	var parsedData = fillDataHash(theData);
	var controls = ['playtextmode', 'thissongnum', 'songcount'];
	for (var i=0; i < controls.length; i++) {
		var key = controls[i];
		if ($(key)) {
			$(key).innerHTML = parsedData[key];
		}
	}
	if (!intervalID) {
		progressUpdate();
	}
}

function refreshHref (element, value) {
	if ($(element)) {
		document.getElementById(element).href = value;
	}
}

function refreshElement(element, value) {
	if ($(element)) {
		$(element).innerHTML = value;
	}
}

function volumeControl(level, param) {
	getStatusData(param,refreshVolumeControl);
}

// called from onClick on repeat or shuffle controls
function playerButtonControl(playerRepeatOrShuffle, selected, param, noRequest) {
	// make the image selected 'active'
	// make the rest not active
	var controls = ['off', 'song', 'album', 'playlist', 'play', 'pause', 'stop'];
	var turnOn = null;
	var turnOff = null;
	for (var i=0; i < controls.length; i++) {
		if (controls[i] == selected) {
			turnOn = playerRepeatOrShuffle+'control_active_'+controls[i];
			turnOff = playerRepeatOrShuffle+'control_'+controls[i];
		} else {
			turnOn = playerRepeatOrShuffle+'control_'+controls[i];
			turnOff = playerRepeatOrShuffle+'control_active_'+controls[i];
		}
		if ($(turnOff)) {
			document.getElementById(turnOff).style.display = "none";
		}
		if ($(turnOn)) {
			document.getElementById(turnOn).style.display = "block";
		}
	}
	if (noRequest) {
		return true;
	} else if (selected == 'prev' || selected == 'next') {
		document.getElementById('playercontrol_prev').src = 'html/images/smaller/prev.gif';
		document.getElementById('playercontrol_next').src = 'html/images/smaller/next.gif';
		getStatusData(param, refreshAll);
	} else if (playerRepeatOrShuffle == 'player') {
		getStatusData(param, refreshPlayerStatus);
	} else if (playerRepeatOrShuffle == 'shuffle') {
		getStatusData(param, refreshAll);
	} else {
		getStatusData(param, refreshNothing);
	}
}

// called from onClick on play/pause/stop/prev/next controls
function playerControl(selected, param) {
	// make the image selected 'active'
	// make the rest not active
	var imgStub = 'html/images/smaller/';
	var controls = ['play', 'pause', 'stop'];
	for (var i=0; i < controls.length; i++) {
		var imgSrc = null;
		if (controls[i] == selected) {
			imgSrc = imgStub + controls[i] + '_active.gif';
		} else {
			imgSrc = imgStub + controls[i] + '.gif';
		}
		var key = 'playercontrol_'+controls[i];
		if ($(key)) {
			document.getElementById(key).src = imgSrc;
		}
	}
}

function refreshOtherElements(theData) {
	var parsedData = fillDataHash(theData);
	// refresh cover art
	if ($('albumhref')) {
		document.getElementById('albumhref').href = parsedData['albumhref'];
	}
	if ($('coverartpath')) {
		var coverPath = null;
		if (parsedData['coverartpath'].match('cover') || parsedData['coverartpath'].match('radio')) {
			coverPath = parsedData['coverartpath'];
		} else {
			coverPath = '/music/'+parsedData['coverartpath']+'/cover.jpg';
		}
		document.getElementById('coverartpath').src = coverPath;
	}

	// refresh song info
	var songinfoArray = [ 'songtitle', 'artist', 'album', 'genre' ];
	var linkStubs = [
			'songinfo.html?item=', 
			'browsedb.html?hierarchy=album,track&level=0&artist=',
			'browsedb.html?hierarchy=track&level=0&album=',
			'browsedb.html?hierarchy=artist,album,track&level=0&genre='
			];
	for (var i=0; i < songinfoArray.length; i++) {
		var key = songinfoArray[i];
		refreshElement(key, parsedData[key]);
		var linkIdKey = key + '_link';
		var linkKey = key + 'id';
		var newHref = linkStubs[i] + parsedData[linkKey] + '&amp;player=' + player;
		refreshHref(linkIdKey, newHref);
	}
	// refresh links in song info section
	// refresh playlist
	var playlistArray = ['previoussong', 'currentsong', 'nextsong' ];
	for (var i=0; i < playlistArray.length; i++) {
		var key = playlistArray[i];
		if ($(key)) {
			$(key).innerHTML = '';
			if (parsedData[key]) {
				$(key).innerHTML = parsedData[key];
			} else {
				$(key).innerHTML = '(ssh...it\'s a secret)';
			}
		} 
	}
	// refresh player ON/OFF
}


function parseData(thisData) {
	var lines = thisData.split("\n");
	var returnData = new Array();
	for (i=0; i<lines.length; i++) {
		var commentLine = lines[i].match(/^#/);
		var blankLine = lines[i].match(/^\s*$/);
		if (!commentLine && !blankLine) {
			var keyValue = lines[i].split('|');
			var key = keyValue[0];
			var value = keyValue[1];
			returnData[key] = value;
		}
	}
	return returnData;
}

window.onload= function() {
	var args = 'player='+player+'&ajaxRequest=1';
	getStatusData(args, refreshAll);
	progressUpdate()
}
