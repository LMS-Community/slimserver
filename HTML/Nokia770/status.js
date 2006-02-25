var alreadyParsed = false;

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

function updateStatus(theData) {
	var parsedData = fillDataHash(theData);
	for (var key in parsedData) {
		if ($(key)) {
			$(key).innerHTML = parsedData[key];
		}
	}
}

function refreshNothing() {
	return true;
}

function fullRefresh(theData) {
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
}

function refreshElement(element, value) {
	if ($(element)) {
		$(element).innerHTML = value;
	}
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
		getStatusData(param, fullRefresh);
	} else if (playerRepeatOrShuffle == 'player') {
		getStatusData(param, refreshPlayerStatus);
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
	// refresh song info
	var songinfoArray = [ 'songtitle', 'artist', 'album', 'genre' ];
	for (var i=0; i < songinfoArray.length; i++) {
		var key = songinfoArray[i];
		refreshElement(key, parsedData[key]);
	}
	// refresh links in song info section
	// refresh playlist
	var playlistArray = ['previoussong', 'currentsong', 'nextsong' ];
	for (var i=0; i < playlistArray.length; i++) {
		var key = playlistArray[i];
		if ($(key)) {
			$(key).innerHTML = '';
			$(key).innerHTML = parsedData[key];
		}
	}
	// refresh player ON/OFF
}

function refreshProgressBar() {
	// update progress bar based on time and elapsed time
	// update time-to-refresh-all based on time left
	return true;
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
	var args = 'player=[% player %]&ajaxRequest=1';
	getStatusData(args, updateStatus);
}
