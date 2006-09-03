var player = '[% playerURI %]';
var url = 'status_header.html';
var mp = 0;

[% PROCESS html/global.js %]

function processState(param) {
	getStatusData(param + "&player="+player+"&ajaxRequest=1", refreshState);
}

function refreshState(theData) {
	var parsedData = fillDataHash(theData);
	
	var controls = ['repeat', 'shuffle'];
	var power = ['on', 'off'];
	
	for (var i=0; i < controls.length; i++) {
		var obj = controls[i];

		for (var j=0; j <= 2; j++) {
			var objID;
			
			objID = $('playlist' + controls[i]+j);
			
			if (parsedData[obj] == j) {
				objID.className = 'button';
			} else {
				objID.className = 'darkbutton';
			}
		}
	}
	
	for (var j=0;j < power.length; j++) {
		objID = $('power' + j);
		if (parsedData['mode'] == power[j]) {
			objID.className = 'button';
			hideElements(['sleeplink']);
		} else {
			objID.className = 'darkbutton';
			showElements(['sleeplink'],'inline');
		}
	}
	
	if (parsedData['sync']) {
		showElements(['unsync'],'inline');
	} else {
		hideElements(['unsync']);
	}
	
	if (parsedData['cansave']) {
		showElements(['saveplaylist'],'inline');
	} else {
		hideElements(['saveplaylist']);
	}
	
	return true;
}

function processBarClick (num) {
	var pos = parseInt((_progressEnd/20) * (num - 0.5));
	var param = 'p0=time&p1='+pos+'&player='+player;
	getStatusData(param + "&ajaxRequest=1", refreshInfo);
}

function processVolume(param) {
	getStatusData(param + "&player="+player+"&ajaxRequest=1", refreshVolume);
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
	
	return true;
}

function processSleepLink(param) {
	getStatusData(param + "&player="+player+"&ajaxRequest=1", refreshSleepTime);
}

function refreshSleepTime(theData) {
	var parsedData = fillDataHash(theData);

	if (parsedData['sleeptime'] && parsedData['sleeptime'] != 0) {
		refreshElement('sleeptime', parsedData['sleep']);
	} else {
		refreshElement('sleeptime', '[% "SLEEP" | string %]');
	}
}

function processPlayControls(param) {
	getStatusData(param + "&player="+player+"&ajaxRequest=1", refreshPlayControls);
}

function refreshPlayControls(theData,force) {
	var parsedData = fillDataHash(theData);
	
	var controls = ['stop', 'play', 'pause'];

	var activestyle = getActiveStyleSheet();
	var curstyle = '';
	
	if (activestyle != null && activestyle.indexOf('Tan') != -1) {
		objID = $('playCtl' + controls[i]+'tan');
		curstyle = '_tan';
	}

	for (var i=0; i < controls.length; i++) {
		var objID = $('playCtl' + controls[i]);
		
		if (parsedData['playmode'] == i) {
			objID.src = '[% webroot %]html/images/'+controls[i]+'_s'+curstyle+'.gif';
			
			if (controls[i] !='play') {
				if ($("progressBar").src.indexOf('_s') == -1) {$("progressBar").src = '[% webroot %]html/images/pixel.green_s.gif'}
			} else {
				if ($("progressBar").src.indexOf('_s') != -1) {$("progressBar").src = '[% webroot %]html/images/pixel.green.gif'}
			}
		} else {
			objID.src = '[% webroot %]html/images/'+controls[i]+curstyle+'.gif';
		}
	}

	if (parsedData['isplayer']) {
		var controls = ['rew','ffwd'];
		
		for (var i=0; i < controls.length; i++) {
			var objID = $('playCtl' + controls[i]);
			
			if (parsedData['rate'] == controls[i]) {
				objID.src = '[% webroot %]html/images/'+controls[i]+'_s'+curstyle+'.gif';
				
			} else {
				objID.src = '[% webroot %]html/images/'+controls[i]+curstyle+'.gif';
			}
		}
		
		if (parsedData['mute'] == 1) {
			if ($('playCtl' + 'mute').src.indexOf('_s') != -1) {$('playCtl' + 'mute').src = '[% webroot %]html/images/mute_s'+curstyle+'.gif';}
		} else {
			if ($('playCtl' + 'mute').src.indexOf('_s') == -1) {$('playCtl' + 'mute').src = '[% webroot %]html/images/mute'+curstyle+'.gif';}
		}
	}

	if (parsedData['playmode'] == 1) {
		refreshInfo(parsedData,force);
		mp = 1;
	} else {
		mp = 0;
	}
}

// refresh song and artwork
function refreshInfo(theData,force) {
	var parsedData = fillDataHash(theData);

	refreshSleepTime(parsedData);
	var myString = new String($('songtitlehref').innerHTML);
	var rExp= new RegExp("item=(.+?)&amp;player","i");
	if (rExp.exec(myString) == null) {rExp= new RegExp("item=(.+?)&player","i");}
	var a = rExp.exec(myString);
	var newsong = 1;

	if (force != 1) {
		if (a == null || a[1] == parsedData['songtitleid']) {newsong = 0;}
	}
	
	var elems = ['thissongnum', 'playtextmode', 'songcount'];
	if (newsong) {
		elems.push('songtitle');
		refreshElement('songtitle', parsedData['songtitle']);
		refreshPlaylist();
		//playlistChecker();
	}
	
	if (parsedData['streamtitle']) {
		refreshElement('songtitle', parsedData['streamtitle']);
	}
	
	if (parsedData['durationseconds']) updateTime(parsedData['songtime'],parsedData['durationseconds']);

	if (parsedData['thissongnum']) {
		hideElements(['notplaying']);
		showElements(['nowplaying']);
	} else {
		hideElements(['nowplaying']);
		showElements(['notplaying']);
	}

	var playeronly = ['playCtlffwd', 'playCtlrew', 'playCtlmute', 'volumeControl'];
	for (var i=0; i < playeronly.length; i++) {
		var key = playeronly[i];
		if (parsedData['isplayer']) {
			showElements([key]);
		} else {
			showElements([key]);
		}
	}
	
	// refresh cover art
	if ($('coverartpath') && newsong) {
		var coverPath = null;
		if (parsedData['coverartpath'].match('cover') || parsedData['coverartpath'].match('radio')) {
			coverPath = parsedData['coverartpath'];
		} else {
			coverPath = '/music/'+parsedData['coverartpath']+'/cover_100x100_f_000000.jpg';
		}
		$('coverartpath').src   = coverPath;
		
		var tooltip = "";
		if (parsedData['album']) {
			tooltip = parsedData['album'];
			if (parsedData['artist']) {
				tooltip += " " + parsedData['by'] + " " + parsedData['artist'];
			}
			if (parsedData['year'] && parsedData['year'] != 0) {
				tooltip += " (" + parsedData['year'] + ")";
			}
		}
		
		$('coverartpath').title = tooltip;
		$('coverartpath').alt   = tooltip;
	}
	
	// refresh href content
	if (newsong) {
		refreshHrefElement('albumhref',parsedData['albumid'],"album.id=");
		refreshHrefElement('coverhref',parsedData['albumid'],"album.id=");
		refreshHrefElement('removealbumhref',parsedData['album'],"p4=");
		refreshHrefElement('removeartisthref',parsedData['artist'],"p3=");
		refreshHrefElement('songtitlehref',parsedData['songtitleid'],"item=");
		refreshHrefElement('zaphref',parsedData['thissongnum']-1,"p2=");
	}

	//refresh text elements
	for (var i=0; i < elems.length; i++) {
		var key = elems[i];
		if ($(key)) {
			refreshElement(key, parsedData[key]);
		}
	}
	
	if (newsong) {
		var elems = ['duration', 'bitrate', 'year'];
		for (var i=0; i < elems.length; i++) {
			var key = elems[i];
			if (parsedData[key] && parsedData[key] != 0) {
				showElements([key],'inline');
				refreshElement(key, "("+parsedData[key]+")");
			} else {
				hideElements([key]);
			}
		}
		
		if(parsedData['album']) {
			showElements(['albuminfo']);
			showElements(['albumhref'], 'inline');
			refreshElement('album', parsedData['album']);
		} else {
			hideElements(['albuminfo', 'albumhref']);
		}
		
		if(parsedData['artist']) {
			showElements(['artistinfo', 'artisthtml']);
			refreshElement('artisthtml', parsedData['artisthtml']);
		} else {
			hideElements(['artistinfo', 'artisthtml']);
		}
		
		var activestyle = getActiveStyleSheet();
		var curstyle = '';
	
		if (activestyle != null && activestyle.indexOf('Tan') != -1) {
			objID = $('playCtl' + controls[i]+'tan');
			curstyle = '_tan';
		}
		
		if(parsedData['playermodel']) {
			$('logoimage' + curstyle).src = '[% webroot %]html/images/' + parsedData['playermodel'] + '_logo.small' + curstyle + '.gif';
		}
		playlistChecker();
	}
	return true;
}

// reload undock window
function refreshUndock() {
	var args = 'player=[% playerURI %]&ajaxRequest=1';
	getStatusData(args, refreshAll);
	//window.location.replace('status.html?player='+player+'&undock=1');
}

function refreshPlaylist(newPlayer) {
	if (newPlayer == null) newPlayer = player;
	try {
		if (parent.playlist.location.host != '') {
			// Putting a time-dependant string in the URL seems to be the only way to make Safari
			// refresh properly. Stitching it together as below is needed to put the salt before
			// the hash (#currentsong).
			var plloc = top.frames.playlist.location;
			
			var newloc = plloc.protocol + '//' + plloc.host + plloc.pathname
				+ plloc.search.replace(/&d=\d+/, '') + '&d=' + new Date().getTime();
			
			newloc=newloc.replace(playerExp, '=' + newPlayer);
			newloc=newloc.replace(/&start=\d+&/, '&');
			newloc=newloc + '#currentsong';
			plloc.replace(newloc);
			//DumperPopup([plloc,plloc.search.replace(playerExp, '='+newPlayer),plloc.search.replace(/&d=\d+/, '')]);
		}
	}
	catch (err) {
		// first load can fail, so swallow that initial exception.
	}
}

var last;
var first;
function currentSong(theData) {
	var parsedData = fillDataHash(theData);

	var doc = parent.playlist.document;
	var found = 1;
	
	if (first == null || first == parsedData['first_item']) {
		first = parsedData['first_item'];
		
		for (var i = parsedData['first_item']; i <= parsedData['last_item']; i++) {
				
				if (i == parsedData['currentsongnum']) {
					doc.getElementById('playlistitem' + i).className = "currentListItem";
					found = 0;
				} else {
					doc.getElementById('playlistitem' + i).className = "browsedbListItem";
				}
		}
	} else {
		first = parsedData['first_item'];
		playlistChecker(first);
	}
	
	doc.location.hash = parsedData['currentsongnum'];
}

function refreshAll(theData,force) {
	var parsedData = fillDataHash(theData);
	
	if (parsedData['isplayer']) {
		refreshVolume(parsedData);
	}
	
	refreshPlayControls(parsedData,force);
	refreshInfo(parsedData,force);
	refreshState(parsedData);
}

// handle the player change, force a new set of info
function refreshNewPlayer(theData) {
	var parsedData = fillDataHash(theData);
	refreshAll(parsedData,1);
	refreshInfo(parsedData,force);
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

function playlistChecker(start) {
	var prev_url = url;
	url = 'playlist.html';
	var args = 'player='+player+'&ajaxRequest=1';
	
	if(start != null && start != '') {
		//alert([start != '', start == null]);
		refreshPlaylist();
		args = args + "&start="+start;
	}
	getStatusData(args, currentSong);
	url = prev_url;
}
