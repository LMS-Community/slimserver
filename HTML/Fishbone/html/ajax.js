var mp = 0;
var currentID = 0;
var playingstart;
var showingstart;
var DEBUG = 1;
var playlistReordered = false;
var commandInProgress = false;

try { console.log('init console... done'); } catch(e) { console = { log: function() {} } }

function convert(url)
{
	var re = /&amp;/g;
	return url.replace(re, "&");
}

function debug() {
	if (DEBUG) {
		console.log(arguments);
	}
}

function doAjaxRefresh(light) {
	
	//bypass if there is a control command in progress
	if (commandInProgress) return;
	
	var args = 'player=' + getPlayer('SlimServer-player') +'&ajaxRequest=1&s='+Math.random();
	var prev_url = url;
	if (light && light != 'onload' && !isNaN(currentID)) {
		args = args + "&light=1";
	} else {
		url = 'status.html'
	}
	//debug(url);
	if (light == 'onload') {
		debug("new player refresh");
		ajaxRequest('status.html', args, refreshNewPlayer);
	} else {
		ajaxRequest('status.html', args, refreshAll);
	}
	url = prev_url;
}

function processState(param) {
	getStatusData(param + "&player="+ getPlayer('SlimServer-player') +"&ajaxRequest=1&s="+Math.random(), refreshState);
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
	
	if (parseInt(parsedData['songcount']) > 0) {
		showElements(['playlistdownload','playlistclear'],'inline');
	} else {
		hideElements(['playalistdownload','playlistclear']);
	}
		
	return true;
}

function processBarClick (num) {
	var pos = parseInt((_progressEnd/20) * (num - 0.5));
	var param = 'p0=time&p1='+pos+'&player='+ getPlayer('SlimServer-player');
	ajaxRequest(url, param + "&ajaxRequest=1&s="+Math.random(), refreshInfo);
}

function processVolume(param) {
	ajaxRequest(url, param + "&player="+ getPlayer('SlimServer-player') +"&ajaxRequest=1&s="+Math.random(), refreshVolume);
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
	ajaxRequest(url, param + "&player="+ getPlayer('SlimServer-player') +"&ajaxRequest=1&s="+Math.random(), refreshSleepTime);
}

function refreshSleepTime(theData) {
	var parsedData = fillDataHash(theData);

	if (parsedData['sleeptime'] && parsedData['sleeptime'] != 0) {
		refreshElement('sleeptime', parsedData['sleep']);
	} else {
		refreshElement('sleeptime', parsedData['sleepstring']);
	}
}

function processPlayControls(param) {
	ajaxRequest(url, param + "&player="+ getPlayer('SlimServer-player') +"&ajaxRequest=1&s="+Math.random(), refreshPlayControls);
}

function processCommand(param, id) {

	//ajaxRequest('status_header.html', param + "&ajaxRequest=1&s="+Math.random(), null);
	ajaxRequest('status.html', param + "&ajaxRequest=1&force=1&s="+Math.random(), function(theData) {commandResponse(theData,1)});
	commandInProgress = true;
	//console.log(id);
	//getPlaylistData();
	//doAjaxRefresh();
	//playlistChecker();
}

function commandResponse(thedata, force) {
	commandInProgress = false;
	refreshAll(thedata,force);
}

function refreshPlayControls(theData,force) {
	var parsedData = fillDataHash(theData);
	
	var controls = ['stop', 'play', 'pause'];
	//debug("playcontrols " + parsedData['playmode']);
	var activestyle = getActiveStyleSheet();
	var curstyle = '';
	
	if (activestyle != null && activestyle.indexOf('Tan') != -1) {
		curstyle = '_tan';
	}

	for (var i=0; i < controls.length; i++) {
		var objID = $('playCtl' + controls[i] + curstyle);
		
		if (parsedData['playmode'] == i) {
			objID.src = parsedData['webroot'] + 'html/images/'+controls[i]+'_s'+curstyle+'.gif';
			
			if (controls[i] !='play') {
				if ($("progressBar").src.indexOf('_s') == -1) {$("progressBar").src = parsedData['webroot'] + 'html/images/pixel.green_s.gif'}
			} else {
				if ($("progressBar").src.indexOf('_s') != -1) {$("progressBar").src = parsedData['webroot'] + 'html/images/pixel.green.gif'}
			}
		} else {
			objID.src = parsedData['webroot'] + 'html/images/'+controls[i]+curstyle+'.gif';
		}
	}

	if (parsedData['isplayer']) {
		var controls = ['rew','ffwd'];
		
		for (var i=0; i < controls.length; i++) {
			var objID = $('playCtl' + controls[i] + curstyle);
			
			if (parsedData['rate'] == controls[i]) {
				objID.src = parsedData['webroot'] + 'html/images/'+controls[i]+'_s'+curstyle+'.gif';
				
			} else {
				objID.src = parsedData['webroot'] + 'html/images/'+controls[i]+curstyle+'.gif';
			}
		}
		
		if (parsedData['mute'] == 1) {
			if ($('playCtl' + 'mute').src.indexOf('_s') != -1) {$('playCtl' + 'mute').src = parsedData['webroot'] + 'html/images/mute_s'+curstyle+'.gif';}
		} else {
			if ($('playCtl' + 'mute').src.indexOf('_s') == -1) {$('playCtl' + 'mute').src = parsedData['webroot'] + 'html/images/mute'+curstyle+'.gif';}
		}
	}

	if (parsedData['playmode'] == 1) {
		mp = 1;
	} else {
		mp = 0;
	}
	
	//debug("now do info");
	refreshInfo(parsedData, force, curstyle);
}

// refresh song and artwork
function refreshInfo(theData, force, curstyle) {
	var parsedData = fillDataHash(theData);
	
	if (parsedData['player_id']) {
		hideElements(['waiting']);
	}
	debug("refreshinfo "+ parsedData['player_id']);
	if (curstyle == null) {
		var activestyle = getActiveStyleSheet();
		var curstyle = '';
		
		if (activestyle != null && activestyle.indexOf('Tan') != -1) {
			curstyle = '_tan';
		}
	}

	refreshSleepTime(parsedData);

	var myString = new String($('songtitlehref').innerHTML);
	var rExp     = new RegExp("item=(.+?)&amp;player","i");

	if (rExp.exec(myString) == null) {rExp = new RegExp("item=(.+?)&player","i");}

	var a = rExp.exec(myString);
	var newsong = 1;
	
	debug(force, a, parsedData['songtitleid'], $('nowplaying').style.display);
	if (force != 1 && !(parsedData['songtitleid'] && $('nowplaying').style.display == 'none')) {
		if (a == null || a[1] == parsedData['songtitleid']) {newsong = 0;}
	}
	//if (!parsedData['songtitleid'] && $('nowplaying').style.display == 'none' || parsedData['songtitleid']) {
	//	if ((!parsedData['songtitleid'] && a == null) || (a != null && a[1] == parsedData['songtitleid'])) {newsong = 0;}
	//}
	
	//if (force) {
	//	newsong = force;
	//}
	
	//if (newsong && !parsedData['artisthtml']) {
		//doAjaxRefresh();
		//return true;
	//}

	debug([newsong,parsedData['songtitleid']]);
	var elems = ['thissongnum', 'playtextmode', 'songcount'];
	if (newsong) {
		elems.push('songtitle');
		refreshElement('songtitle', parsedData['songtitle']);
		//playlistChecker();
	}
	
	if (parsedData['streamtitle']) {
		refreshElement('songtitle', parsedData['streamtitle']);
	}
	
	if (parsedData['durationseconds']) {
		updateTime(parsedData['songtime'],parsedData['durationseconds'], curstyle);
	}

	if (parsedData['thissongnum']) {
		hideElements(['notplaying']);
		showElements(['nowplaying']);
		$('coverarthref').href = convert(parsedData['albumhref']);
	} else {
		hideElements(['nowplaying']);
		showElements(['notplaying']);
		$('coverarthref').href = "javascript:void(1);";
	}

	//debug("update player state\n");
	var playeronly = ['playCtlffwd', 'playCtlrew', 'playCtlmute', 'volumeControl'];
	for (var i=0; i < playeronly.length; i++) {
		var key = playeronly[i];
		if (i < (playeronly.length -1) && curstyle == '_tan') {
			key = playeronly[i] + 'tan';
		}
		
		if (parsedData['isplayer']) {
			showElements([key]);
		} else {
			showElements([key]);
		}
	}
	
	// refresh cover art
	if ($('coverartpath') && newsong) {
		debug("update covers");
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
		debug("update hrefs");
		if (parsedData['albumid']) {
			refreshHrefElement('albumhref', parsedData['albumid'],"album.id=");
			refreshHrefElement('coverhref', parsedData['albumid'],"album.id=");
			refreshHrefElement('removealbumhref', parsedData['albumid'],"album.id=");
		}
		refreshHrefElement('removeartisthref', parsedData['artistid'],"contributor.id=");
		refreshHrefElement('songtitlehref', parsedData['songtitleid'],"item=");
		refreshHrefElement('yearhref', parsedData['year'],"year.id=");
		refreshHrefElement('zaphref', parsedData['thissongnum']-1,"p2=");
	}
	
	if (parsedData['songtitleid']) {
		debug("setting current song "+parsedData['songtitleid']);
		currentID = parsedData['songtitleid'];
	} else {
		debug("no songid found!");
	}

	//refresh text elements
	for (var i=0; i < elems.length; i++) {
		var key = elems[i];
		if ($(key)) {
			refreshElement(key, parsedData[key]);
		}
	}
	
	if (newsong) {
		debug("last block");
		var elems = ['duration', 'bitrate'];
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
			if (parsedData['year'] && parsedData['year'] != 0) {
				showElements(['yearinfo'],'inline');
				refreshElement('year', parsedData['year']);
			} else {
				hideElements(['yearinfo']);
			}
		} else {
			hideElements(['albuminfo', 'albumhref']);
		}
		
		if(parsedData['artist']) {
			showElements(['artistinfo']);
			showElements(['artisthtml'], 'inline');
			if (parsedData['artisthtml']) { refreshElement('artisthtml', parsedData['artisthtml']);}
		} else {
			hideElements(['artistinfo', 'artisthtml']);
		}
		
		if(parsedData['playermodel']) {
			$('logoimage' + curstyle).src = parsedData['webroot'] + 'html/images/' + parsedData['playermodel'] + '_logo.small' + curstyle + '.gif';
		}
		debug("check playlist");

		playlistChecker(parsedData);
		
		//also do a secondary check 1s into songs.
		//setTimeout( "playlistChecker()", 1000);
	}
	return true;
}

// reload undock window
function refreshUndock() {
	var player = getPlayer('SlimServer-player')

	var args = 'player=' + player + '&ajaxRequest=1&s='+Math.random();
	getStatusData(args, refreshAll);
}

var last;
var first;
function currentSong(theData) {
	var parsedData = fillDataHash(theData);
	
	var doc = document;
	var currentsong;
	
	if (parent.playlist) {doc = parent.playlist.document };
	
	if (parsedData['currentsongnum']) {
		currentsong = parsedData['currentsongnum'];
	} else if (parsedData['thissongnum']) {
		currentsong = parsedData['thissongnum'] - 1;
	}
	debug("playlist now at: "+currentsong);
	var found = 0;
	var refresh = 0;
	
	if (parsedData['playlistsize'] == 0 || parsedData['songcount'] == 0) {
		// playlist is empty, should refresh
		debug("shortcut currentsong");
		
		getPlaylistData();
		return;
	} else if (!$('playlist_draglist')) {
		//playlist is new, refresh
		debug("new playlist");
		getPlaylistData();
		return;
	}
	
	if (showingstart == parsedData['first_item'] || showingstart == playingstart) {

		for (var i = showingstart; i <= parsedData['last_item']; i++) {
			
			// make sure we have matching item counts, refresh if not.
			var item = doc.getElementById('playlistitem' + i);
			debug([i, item, item.className]);
			if (item) {
				
				if (i == currentsong) {
					item.className = "currentListItem";
					found = parsedData['item_'+i];
					debug("found: "+found+" "+i);
				} else {
					item.className = "playListItem";
				}
				
				// Check the id's of each item, refresh if any don't match.
				var myString = new String(doc.getElementById('playlistitem' + i).innerHTML);
				var rExp     = new RegExp("trackid_(\\d+)","i");
				var a = rExp.exec(myString);
				
				if (a == null || a[1] != parsedData['item_'+i]) {
					//debug(a[1], parsedData['item_'+i]);
					refresh = 1;
				}
				
			} else {
				debug('missing item: must refresh');
				refresh = 1;
			}
		}

		// refresh the playlist if we're not finding the current song
		if (currentID != found) {
			debug('missing current id '+currentID+': must refresh');
			refresh = 1;
		} 
	} else {
		debug("not showing current page");
		if (showingstart != parsedData['first_item'] && showingstart == playingstart) {
			playlistChecker(parsedData['first_item']);
		}
	}

	if (refresh != 0) {
		getPlaylistData();
	} else {
		debug("current: "+ currentsong);
		if (!isNaN(currentsong)) {
			doc.location.hash = 'playlistitem'+currentsong;
			//console.log('scrolling');
			//Element.scrollTo('playlistitem'+currentsong);
		}
	}
}

function refreshAll(theData,force) {
	var parsedData = fillDataHash(theData);
	
	if (parsedData['player_id']) {
		if ($('waiting').style.display == 'inline') {
			hideElements(['waiting']);
			force = 1;
		}
		
		if (parsedData['isplayer']) {
			refreshVolume(parsedData);
		}

		refreshPlayControls(parsedData,force);
		refreshState(parsedData);
		
		if (!document.location.hash && parsedData['thissongnum']) {
			currentSong(parsedData);
		}
	} else {
		showElements(['waiting'],'inline');
		updateTime(0,0);
	}

}

var homeloc;
var playerExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;

// handle the player change, force a new set of info
function refreshNewPlayer(theData) {
	var parsedData = fillDataHash(theData);
	refreshAll(parsedData,1);
	
	var headerURL = new String(parent.header.location.href);
	homeloc = headerURL.replace(playerExp, parsedData['player_id']);
	
	if (!document.all) { // some versions of IE just dont like div's being filled :(
		//parent.header.document.getElementById('browseForm').innerHTML = ' Fetching data...';
		getOptionData("&optionOnly=1"+ '&d=' + Math.random(), optionDone);
	}
}

function optionDone(req) {
	
	if (req.readyState == 4) { // only if req is "loaded"

		if (req.responseText) { // only if "OK"
			parent.header.document.getElementById('browseForm').innerHTML = req.responseText;
		} else {
			//parent.header.document.getElementById('browseForm').innerHTML = " Error:\n"+ req.status + "\n" +req.statusText;
		}
	}
	
	var page = parent.header.document.getElementById('homepage').innerHTML;
	selectLink("", page);
}

function getOptionData(params, action) {
	ajaxRequest(homeloc, params, action);
}

function playlistChecker(theData) {
	var parsedData = fillDataHash(theData);
	debug(parsedData['first_item'], parseInt(parsedData['start']), playingstart, showingstart);
	if (isNaN(parsedData['first_item']) || ((parseInt(parsedData['start']) != playingstart) && (playingstart == showingstart))) {
		debug("get new playlist data");
		showingstart = parsedData['start'];
		playingstart = parsedData['start'];
		getPlaylistData(parsedData['start']);
	} else {
		debug("parse current song info");
		currentSong(theData);
		//var prev_url = url;
	
		//url = 'playlist.html';
	
		//var args = 'player=' + getPlayer('SlimServer-player') +'&ajaxRequest=1&s='+Math.random();
		
		//if(!isNaN(start)) {
		//	debug('getplaylist');
		//	getPlaylistData(start);
		//	args = args + "&start="+start;
		//} else if (!isNaN(playingstart)){
		//	debug("playlist check at "+ playingstart);
		//	args = args + "&start=" + playingstart;
		//}
		//debug('set current song');
		//ajaxRequest(url, args, currentSong);
		//url = prev_url;
	}
}


function getPlaylistData(start, params, player) {
	var requesttype = 'get';
	var thisplayer;

	if (player) {
		thisplayer = player;
	} else {
		thisplayer = getPlayer('SlimServer-player');
	}
	
	var args = 'player='+ thisplayer +'&s='+Math.random();

	if(params != null && params != '') {
		args = params + "&" + args;
	}

	if(!isNaN(start)) {
		debug("playlist page override "+start);
		args = args + "&start=" + start;
		showingstart = start;
	} else if (!isNaN(showingstart)) {
		if (showingstart == null) showingstart = 0;
		debug("playlist refresh at "+showingstart);
		args = args + "&start=" + showingstart;
	}
	

	var myAjax = new Ajax.Updater(
	'playlistframe',
	'playlist.html',
	{
		asynchronous:true,
		evalScripts:true,
		method: requesttype,
		postBody: args,
		parameters: args,
		onComplete: function(req) {playlistDone(start,req)},
		requestHeaders:['Referer', document.location.href]
	});
}

function playlistDone(start,req) {
	$('playlistframe').innerHTML = req.responseText;
	initSortable('playlist_draglist');
}

function setStart(start) {
	if (isNaN(showingstart)) showingstart = start;
	if (isNaN(playingstart)) playingstart = start;
	debug("init: showing"+showingstart+", playing"+playingstart);
}

function reorderplaylist(order, start, from) {
	var params;
	
	for (var i=0; i < order.length; i++) {
		if (order[i] == from) {

			if(start != null && start != '') {
				from = from + start;
				i = i + start;
			}
			
			params = "p0=playlist&p1=move&p2=" + from + "&p3=" + i;
			break;
		}
	}
	
	debug("move "+from+" to "+i);
	getPlaylistData(start,params);
}

function initSortable(element) {

	if (! $(element)) {
		return;
	}
	
	Position.includeScrollOffsets = true;
	
	var activeElem = null;
	//<![CDATA[
	Sortable.create(element, {
		onChange: function(item) {
			var rexp = new RegExp("\\d+$");
			var id = rexp.exec(item.id);
			activeElem = parseInt(id);
			debug(activeElem, showingstart);
		},
		onUpdate: function() {
			new Effect.Highlight(element, { endcolor: "#d50000" });
			reorderplaylist(Sortable.sequence(element), showingstart, activeElem);
		},
		endeffect: function() {
			Effect.Shrink('deleteitem');
			$('playlistStatus').style.backgroundColor = null;
		},
		starteffect: function() {
			Effect.Grow('deleteitem');
			$('deleteitem').style.backgroundColor = 'maroon';
			playlistReordered = true;
		},
		scroll:'playlistframe',
		revert: true
	});
	//]]>
}

// swallow click event if sortable in progress
function checkPlaylistSortable(event) {
	if (playlistReordered) {
		Event.stop(event);
		playlistReordered = false;
	}
}



function deletePlaylistItem(element, start) {

	var rexp = /\d+$/;
	var id = rexp.exec(element.id);
	var args;
	
	if(start != null && showingstart != '') {
		id = id + showingstart;
		args = "start=" + showingstart + "&";
	}

	params = "p0=playlist&p1=delete&p2=" + id;
	getPlaylistData(start,params);
}
