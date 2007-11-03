var url = 'status.html';
var _progressEnd = [% IF durationseconds %][% durationseconds %]+8[% ELSE %][% refresh %][% END %];
var _progressAt = [% IF songtime %][% songtime %][% ELSE %]0[% END %];
var _progressBarWidth = 788;
var p = 1;
var inc = 0;
var intervalID = false;
var incr;

[% PROCESS skin_global.js %]

var args = 'player='+player+'&ajaxRequest=1';

// Update the progress dialog with the current state
function refreshProgressBar(theData) {
	var parsedData = fillDataHash(theData);
	var elements = [ 'duration', 'elapsed' ];
	elements.each(function(key) {
		if ($(key)) {
			if (parsedData[key]) {
				refreshElement(key, parsedData[key]);
			}
		}
	});
	_progressAt = parseInt(parsedData['songtime'], 10);
	_progressEnd = parseInt(parsedData['durationseconds'], 10);
	setProgressBarWidth();
	if (!intervalID) {
		progressUpdate();
	}
}

function progressUpdate() {
	if ($('playercontrol_active_play').style.display == 'block') {
		inc++;
		_progressAt++;
		setProgressBarWidth();
		// do an ajax update every 10 seconds while playing
		if (inc == 10) {
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

function setProgressBarWidth() {
	if ( _progressAt >= _progressEnd) {
		_progressAt = _progressEnd;
		clearIntervalCall();
		doRefresh();
	}
	p = ( _progressBarWidth / _progressEnd) * _progressAt;
	$("progressBar").width=p+" ";
}

function resetProgressBar() {
	if ($('progressBar')) {
		$('progressBar').width=0+" ";
		_progressAt = 0;
		clearIntervalCall();
	}
}
// parses the data if it has not been done already
function fillDataHash(theData) {
	var returnData = null;
	if (theData['player_id']) { 
		return theData;
	} else {
		var myData = theData.responseText;
		returnData = parseData(myData);
	}

	// make the correct divs be shown; this is a good spot for this because fillDataHash is called first by all refreshFunctions()
	var hideDivs;
	var showDivs;
	// radio
	if (returnData['streamtitle']) {
		showDivs = [ 'radioinfo', 'radioart', 'streaminfo', 'playliststatus', 'playlistbox' ];
		hideDivs = [ 'songinfo', 'progressbar', 'progressbar_overlay', 'coverart', 'emptyplayer' ];
	// track
	} else if (returnData['songcount'] > 0) {
		hideDivs = [ 'radioinfo', 'radioart', 'streaminfo', 'emptyplayer'  ];
		showDivs = [ 'playliststatus', 'playlistbox', 'songinfo', 'progressbar', 'progressbar_overlay', 'coverart' ];
	// empty playlist
	} else {
		showDivs = [ 'emptyplayer'  ];
		hideDivs = [ 'playliststatus', 'playlistbox', 'songinfo', 'progressbar', 'progressbar_overlay', 'coverart', 'radioinfo', 'radioart', 'streaminfo' ];
	}
	hideElements(hideDivs);
	showElements(showDivs);
	return returnData;
}

function refreshAll(theData) {
	inc = 0;
	// stop progress bar refreshing for this track
	clearIntervalCall();
	var parsedData = fillDataHash(theData);
	refreshControls(parsedData);
	refreshOtherElements(parsedData);
	refreshProgressBar(parsedData);
	url = 'home.html';
	getStatusData(args, refreshPlugins);
	url = 'status.html';
}

[%-
	biography   = "PLUGIN_BIOGRAPHY" | getstring;
	albumReview = "PLUGIN_ALBUMREVIEW" | getstring;
-%]
function refreshPlugins(theData) {
	var myData = theData.responseText;
	var homeParsedData = parseData(myData);
	// create Plugin links, if applicable
	var pluginDivs = [ [% IF biography != "PLUGIN_BIOGRAPHY"; "'"; biography | replace('\s+', '_'); "',"; END; %] [% IF albumReview != "PLUGIN_ALBUMREVIEW"; "'"; albumReview | replace('\s+', '_'); "'"; END; %] ];
	pluginDivs.each( function (thisDiv) {
		if (homeParsedData[thisDiv].match(/\w/)) {
			var linkName = thisDiv.replace('_',' ');
			var streamDiv = "Stream"+thisDiv;
			if ($(thisDiv)) {
				$(thisDiv).innerHTML = '<a href = "[% webroot %]'+homeParsedData[thisDiv]+'player='+player+'">('+linkName+')</a>';
			}
			if ($(streamDiv)) {
				$(streamDiv).innerHTML = '<a href = "[% webroot %]'+homeParsedData[thisDiv]+'player='+player+'">('+linkName+')</a>';
			}
		}
	});
}

function refreshControls(theData) {

	var parsedData = fillDataHash(theData);
	// refresh control_display in songinfo section
	refreshPlayerStatus(parsedData);

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
	refreshVolumeControl(parsedData, 1);
}

function refreshVolumeControl(theData, suppressOSD) {
	var parsedData = fillDataHash(theData);
	var levels = [0, 15, 30, 40, 50, 60, 70, 80, 90, 100];
	levels.each( function(thisLevel) {
		var key = 'bar_'+thisLevel;
		var activeKey = 'bar_active_'+thisLevel;
		var turnOn = null;
		var turnOff = null;
		var intVolume = parseInt(parsedData['volume'], 10);
		if (intVolume == 0 && thisLevel == 0) {
			turnOn = activeKey;
			turnOff = key;
		} else if (thisLevel == 0) {
			turnOn = key;
			turnOff = activeKey;
		} else if (intVolume >= thisLevel) {
			turnOn = activeKey;
			turnOff = key;
		} else {
			turnOn = key;
			turnOff = activeKey;
		}
		if ($(turnOff)) {
			Element.hide(turnOff);
		}
		if ($(turnOn)) {
			Element.show(turnOn);
		}
	});
	var level = parseInt(parsedData['volume']);
	if (!suppressOSD) {
		showVolumeOSD(level, 500);
	}
}

function adjustVolume(level) {
	incr = level;
	var param = 'ajaxRequest=1&player=[% playerURI %]';
	getStatusData(param,volumeMicroControl);
}

function volumeMicroControl(theData) {
	var parsedData = fillDataHash(theData);
	var level = parseInt(parsedData['volume']) + parseInt(incr);
	if (level > 100) {
		level = 100;
	} else if (level < 0) {
		level = 0;
	}
	showVolumeOSD(level, 500);
	var param = 'p0=mixer&p1=volume&p2='+level+'&player=[% playerURI %]&start=[% start %]&ajaxRequest=1';
	getStatusData(param,refreshVolumeControl);
}

function refreshPlayerStatus(theData) {
	var parsedData = fillDataHash(theData);
	var controls = ['playtextmode', 'thissongnum', 'songcount'];
	controls.each(function(key) {
		if ($(key)) {
			refreshElement(key, parsedData[key]);
		}
	});
	if (!intervalID) {
		progressUpdate();
	}
}

function volumeControl(level) {
	var param = 'p0=mixer&p1=volume&p2='+level+'&player=[% playerURI %]&start=[% start %]&ajaxRequest=1';
	getStatusData(param,refreshVolumeControl);
}

// called from onClick on repeat or shuffle controls
function playerButtonControl(playerRepeatOrShuffle, selected, param, noRequest) {
	// make the image selected 'active'
	// make the rest not active
	var controls = ['off', 'song', 'album', 'playlist', 'play', 'pause', 'stop'];
	var turnOn = null;
	var turnOff = null;
	controls.each(function(thisControl) {
		if (thisControl == selected) {
			turnOn = playerRepeatOrShuffle+'control_active_'+thisControl;
			turnOff = playerRepeatOrShuffle+'control_'+thisControl;
		} else {
			turnOn = playerRepeatOrShuffle+'control_'+thisControl;
			turnOff = playerRepeatOrShuffle+'control_active_'+thisControl;
		}
		if ($(turnOff)) {
			Element.hide(turnOff);
		}
		if ($(turnOn)) {
			// still haven't figured this out, but prototype's Element.show here kills the progress bar. Bizarre
			//Element.show(turnOn);
			// go with this instead
			document.getElementById(turnOn).style.display = "block";
		}
	});
	if (selected == 'stop') {
		resetProgressBar();
	}
	if (noRequest) {
		return true;
	} else if (selected == 'prev' || selected == 'next') {
		$('playercontrol_prev').src = 'html/images/larger/prev.gif';
		$('playercontrol_next').src = 'html/images/larger/next.gif';
		getStatusData(param, refreshAll);
	} else if (playerRepeatOrShuffle == 'player') {
		getStatusData(param, refreshAll);
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
	var imgStub = 'html/images/larger/';
	var controls = ['play', 'pause', 'stop'];
	controls.each(function(thisControl) {
		var imgSrc = null;
		if (thisControl == selected) {
			imgSrc = imgStub + thisControl + '_active.gif';
		} else {
			imgSrc = imgStub + thisControl + '.gif';
		}
		var key = 'playercontrol_'+thisControl;
		if ($(key)) {
			$(key).src = imgSrc;
		}
	});
}

function refreshOtherElements(theData) {
	var parsedData = fillDataHash(theData);
	// refresh cover art
	if ($('albumhref')) {
		$('albumhref').href = 'browsedb.html?hierarchy=album,track&level=2&album.id='+parsedData['albumid']+'&amp;player='+player;
	}
	if ($('coverartpath')) {
		var coverPath = null;
		if (parsedData['coverartpath'].match('cover') || parsedData['coverartpath'].match('radio')) {
			coverPath = parsedData['coverartpath'];
		} else {
			coverPath = '/music/'+parsedData['coverartpath']+'/cover_190x190_p.png';
		}
		$('coverartpath').src = coverPath;
	}

	// refresh song info
	var songinfoArray = new Array();
	songinfoArray[songinfoArray.length] = {name: 'songtitle', stub:'songinfo.html?item='};
	//songinfoArray[songinfoArray.length] = {name: 'artist', stub:'browsedb.html?hierarchy=album,track&level=1&contributor.id='};
	songinfoArray[songinfoArray.length] = {name: 'album', stub:'browsedb.html?hierarchy=album,track&level=2&album.id='};
	//songinfoArray[songinfoArray.length] = {name: 'genre', stub:'browsedb.html?hierarchy=genre,contributor,album,track&level=1&genre.id='};
	refreshElement('genre',parsedData['genrehtml']);
	refreshElement('artist',parsedData['artisthtml']);

	songinfoArray.each(function(key) {
		var thisName = key.name;
		var thisStub = key.stub;
		refreshElement(thisName, parsedData[thisName], 50);
		var linkIdKey = thisName + '_link';
		var linkKey = thisName + 'id';
		var newHref = thisStub + parsedData[linkKey] + '&amp;player=' + player;
		refreshHref(linkIdKey, newHref);
	});
	if (parsedData['streamtitle']) {
		refreshElement('streamtitle', parsedData['streamtitle'], 50);
	}
	// refresh links in song info section
	// refresh playlist
	var playlistArray = ['previoussong', 'currentsong', 'nextsong' ];
	playlistArray.each(function(key) {
		if ($(key)) {
			var value;
			if (parsedData[key]) {
				value = parsedData[key];
			} else {
				value = '(ssh...it\'s a secret)';
			}
			refreshElement(key, value, 40);
		} 
	});
	// refresh player ON/OFF
}

window.onload= function() {
	getStatusData(args, refreshAll);
	progressUpdate();
	globalOnload();
}
