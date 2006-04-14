var player = '[% playerURI %]';
var url = 'status_header.html';

[% PROCESS html/global.js %]

function processState(param) {
	getStatusData(param + "&ajaxRequest=1", refreshState);
}

function refreshState(theData) {
	var parsedData = fillDataHash(theData);
	
	var controls = ['repeat', 'shuffle', 'mode'];
	var power = ['on', 'off'];
	
	for (var i=0; i < controls.length; i++) {
		var obj = controls[i];

		for (var j=0; j <= 2; j++) {
			var objID;
			
			if (i < 2) {
				objID = $('playlist' + controls[i]+j);
			} else {
				objID = $('power' + j);
			}
			
			if (parsedData[obj] == j || parsedData[obj] == power[j]) {
				objID.className = 'button';
			} else {
				objID.className = 'darkbutton';
			}
		}
	}
}

function processVolume(param) {
	getStatusData(param + "&ajaxRequest=1", refreshVolume);
}

function refreshVolume(theData) {

	var parsedData = fillDataHash(theData);
	var vols = [0, 6, 12, 18, 24, 30, 36, 42, 48, 54, 60, 66, 72, 78, 84, 90, 95, 100];

	for (var i=0; i < vols.length; i++) {
		var div = (i + 1) * 2;
		var objID = $('volDiv' + div);
		var intVolume = parseInt(parsedData['volume'], 10);

		if (intVolume < vols[i]) {
			objID.style.backgroundColor = "808080";
		} else {
			objID.style.backgroundColor = "00C000";
		}
	}
}

function processPlayControls(param) {
	getStatusData(param + "&ajaxRequest=1", refreshPlayControls);
}

function refreshPlayControls(theData) {

	var parsedData = fillDataHash(theData);
	var controls = ['stop', 'play', 'pause'];
	var mp = 0;
	var curstyle = getActiveStyleSheet();
	
	for (var i=0; i < controls.length; i++) {
		var obj = 'playmode';
		var objID = $('playCtl' + controls[i]);
		var curstyle = '';
		
		if (curstyle && curstyle.indexOf('Tan')) {
			objID = $('playCtl' + controls[i]+'tan');
			curstyle = '_tan';
		}
		
		if (parsedData['playmode'] == i) {
			objID.src = '[% webroot %]html/images/'+controls[i]+'_s'+curstyle+'.gif';
			
			if (controls[i] !='play') {
				$("progressBar").src ='[% webroot %]html/images/pixel.green_s.gif'
			} else {
				$("progressBar").src = '[% webroot %]html/images/pixel.green.gif'
			}
		} else {
			objID.src = '[% webroot %]html/images/'+controls[i]+curstyle+'.gif';
		}
	}
	
	if (parsedData['mute'] == 1) {
		$('playCtl' + 'mute').src = '[% webroot %]html/images/mute_s'+curstyle+'.gif';
	} else {
		$('playCtl' + 'mute').src = '[% webroot %]html/images/mute'+curstyle+'.gif';
	}
	
	if (parsedData['playmode'] == 1) {
		mp = 1;
	}
	
	updateTime(parsedData['songtime'],parsedData['durationseconds']);
	//DumperPopup(theData.responseText);
}

// refresh song and artwork
function refreshInfo(theData) {
	var parsedData = fillDataHash(theData);
	var hidden = new Array;
	var shown = new Array;
	
	// refresh cover art
	if ($('albumhref')) {
		document.getElementById('albumhref').href = 'browsedb.html?hierarchy=track&level=0&album='+parsedData['albumid']+'&amp;player='+player;
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
	
	// refresh href content
	refreshHrefElement('albumhref',parsedData['albumid'],"album=");
	refreshHrefElement('removealbumhref',parsedData['album'],"p4=");
	refreshHrefElement('removeartisthref',parsedData['artist'],"p4=");
	refreshHrefElement('songtitlehref',parsedData['songtitleid'],"item=");
	refreshHrefElement('zaphref',parsedData['thissongnum']-1,"p2=");

	//refresh text elements
	var elems = ['artisthtml', 'songtitle', 'thissongnum', 'playtextmode', 'songcount', 'album'];
	for (var i=0; i < elems.length; i++) {
		var key = elems[i];
		if ($(key)) {
			refreshElement(key, parsedData[key]);
		}
	}
	var elems = ['duration', 'bitrate', 'year'];
	for (var i=0; i < elems.length; i++) {
		var key = elems[i];
		if ($(key)) {
			showElements([key],'inline');
			refreshElement(key, "("+parsedData[key]+")");
		} else {
			hideElements([key]);
		}
	}
	
	if(parsedData['album']) {
		showElements(['albuminfo']);
		showElements(['album'], 'inline');
	} else {
		hideElements(['albuminfo', 'album']);
	}
	if(parsedData['artist']) {
		showElements(['artistinfo', 'artist']);
	} else {
		hideElements(['artistinfo', 'artist']);
	}
	
	if (parsedData['thissongnum']) {
		hideElements(['notplaying']);
		showElements(['nowplaying']);
	} else {
		hideElements(['nowplaying']);
		showElements(['notplaying']);
	}
}

// reload undock window
function refreshUndock() {
	var args = 'player=[% playerURI %]&ajaxRequest=1';
	getStatusData(args, refreshAll);
	//window.location.replace('status.html?player='+player+'&undock=1');
}

function refreshAll(theData) {
	var parsedData = fillDataHash(theData);

	refreshVolume(parsedData);
	refreshPlayControls(parsedData);
	refreshInfo(parsedData);
	refreshState(parsedData);

}

function fillDataHash(theData) {
	var returnData = null;
	if (theData['player_id']) { 
		return theData;
	} else {
		var myData = theData.responseText;
		returnData = parseData(myData);
	}
	return returnData;
}