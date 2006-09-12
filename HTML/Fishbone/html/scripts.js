var p = 1;

// track the progress bar update timer state
var timerID = false;

// refresh data interval (1s for progress updates, 10s for only status)
var interval = 1000;

// update timer counter, waits for 10 updates when update interval is 1s
var inc = 0;

// progressBar variables
var _progressEnd = 0;
var _progressAt = 0;
var _curstyle = '';

// regex to match player id, mac and ip format.
var playerExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;

function changePlayer(player_List) {
	player = player_List.options[player_List.selectedIndex].value;
	setCookie('SlimServer-player', '=' + player);
	player = escape(player);
	
	var newPlayer = "=" + player;
	newHref(parent.frames[2].document,newPlayer);
	//parent.playlist.location="playlist.html?player" + newPlayer;
	refreshPlaylist(player);
	//alert([newPlayer,parent.playlist.location])
	
	var args = 'player='+player+'&ajaxRequest=1';
	getStatusData(args, refreshNewPlayer);
	
	if (parent.browser.location.href.indexOf('setup') == -1) {
		newHref(parent.browser.document,newPlayer);
		newHref(parent.header.document,newPlayer);
		newValue(parent.browser.document,newPlayer);

	} else {
		browseURL = new String(parent.browser.location.href);
		parent.browser.location=browseURL.replace(playerExp, newPlayer);
	}

	headerURL = new String(parent.header.location.href);
	//parent.header.location=headerURL.replace(playerExp, newPlayer);
}

// change form values to correct player
function newValue(doc,plyr) {
	for (var j=0;j < doc.forms.length; j++){

		if (doc.forms[j].player) {
			var myString = new String(doc.forms[j].player.value);
			var rString = plyr;
			doc.forms[j].player.value = myString.replace(playerExp, rString);
		}
	}
}

// change browse/plugin/radio hrefs to proper player
function newHref(doc,plyr) {

	for (var j=0;j < doc.links.length; j++){
		var myString = new String(doc.links[j].href);
		var rString = plyr;
		doc.links[j].href = myString.replace(playerExp, rString);
	}
}

function toggleStatus(divs) {

	for (var i=0; i < divs.length; i++) {

		if ($(divs[i]).style.display == "none") {
			$(divs[i]).style.display = "block";
			$('statusImg_up').style.display = "inline";
			$('statusImg_down').style.display = "none";

		} else {
			$(divs[i]).style.display = "none";
			$('statusImg_up').style.display = "none";
			$('statusImg_down').style.display = "inline";
		}
	}
}

function resizePlaylist(page) {
	//$('playlist').height = document.body.clientHeight - $('playlistframe').offsetTop;
	top.document.getElementById('player_frame').rows = $('playlistStatus').offsetTop+20+', *';
}

function openRemote() {
	window.open('status.html?player='+player+'&undock=1', '', 'width=480,height=210,status=no');
}

function setCookie(name, value) {
	var expires = new Date();
	expires.setTime(expires.getTime() + 1000*60*60*24*365);
	document.cookie =
		name + "=" + escape(value) +
		((expires == null) ? "" : ("; expires=" + expires.toGMTString()));
}

function insertProgressBar(mp,end,at) {
	var s = '';
	if (!mp) s = '_s';

	if (document.all||document.getElementById) {
		document.write('<div class="progressBarDiv"><img id="progressBar" name="progressBar" src="html/images/pixel.green'+s+'.gif" width="1" height="4"><\/div>');
	}

	_progressAt = at;
	_progressEnd = end;
	ProgressUpdate(mp)
}

// update at and end times for the next progress update.
function updateTime(at,end, style) {
	_progressAt  = at;
	_progressEnd = end;
	
	if (style != null) {
		_curstyle    = style;
	}
}
	

// Update the progress dialog with the current state
function ProgressUpdate(mp) {

	if ($('playCtlplay') != null) {
		if ($('playCtlplay'+ _curstyle).src.indexOf('_s') != -1) {
			mp = 1;
			if ($("progressBar").src.indexOf('_s') != -1) {$("progressBar").src = '[% webroot %]html/images/pixel.green.gif'}

		} else {
			mp = 0;
			if ($("progressBar").src.indexOf('_s') == -1) {$("progressBar").src = '[% webroot %]html/images/pixel.green_s.gif'}
		}
	}
	
	inc++;
	if (mp) _progressAt++;

	if(_progressAt > _progressEnd) _progressAt = _progressAt % _progressEnd;
	
	[% IF undock %]refreshElement('inc',inc);[% END %]

	if (_progressAt == 1) {
		doRefresh();
		inc = 0;
		if (!mp) {
			_progressAt = 0;
			//refreshPlaylist();
		}
	}
	
	if (document.all) {
		p = (document.body.clientWidth / _progressEnd) * _progressAt;
		eval("document.progressBar.width=p");

	} else if (document.getElementById) {
		p = (document.width / _progressEnd) * _progressAt;
		$("progressBar").width=p+" ";
	}
	
	if (inc == 10) {
		doRefresh();
		inc = 0;
	}

	timerID = setTimeout("ProgressUpdate( "+mp+")", interval);
}

function getArgs() {
	var args = new Object();
	var query = location.search.substring(1);
	var pairs = query.split("&");

	for(var i = 0; i < pairs.length; i++) {
		var pos = pairs[i].indexOf('=');

		if (pos == -1) continue;
		var argname = pairs[i].substring(0,pos);
		var value = pairs[i].substring(pos+1);
		args[argname] = unescape(value);
	}

	return args;
}

function getCookie(cookie)
{
	var search = cookie + "=";

	if (document.cookie.length > 0) {
		offset = document.cookie.indexOf(search);

		if (offset != -1) {
			offset += search.length;
			end = document.cookie.indexOf(";", offset);

			if (end == -1)
				end = document.cookie.length;
			return unescape(document.cookie.substring(offset, end));
		}
	}
	return;
}

function getPlayer(Player) 
{
	plyr = getCookie(Player);

	if (!plyr) return "";

	return plyr;
}

function goHome(plyr)
{
	var loc = getHomeCookie('SlimServer-Browserpage')+'&player='+plyr;
	parent.browser.location = loc;
}

function getHomeCookie(Name) 
{
	var url = getCookie(Name);
	// look for old artwork cookie and work around it
	var re  = new RegExp(/artwork,/i);
	var m   = re.exec(url);

	if (!url || m) return "browsedb.html?hierarchy=album,track&level=0&page=BROWSE_BY_ALBUM";


	return url;
}

function getPage() {
	var url = getHomeCookie('SlimServer-Browserpage');

	if (!url) { 
		return "BROWSE_BY_ALBUM"; 
	}

	else {

		if (url.length > 0) {
			offset = url.indexOf('page=');

			if (offset != -1) {
				offset += 5;
				end = url.indexOf(";", offset);

				if (end == -1)
					end = url.length;
				page = unescape(url.substring(offset, end));

				if (!page) return "BROWSE_BY_ALBUM";
				return page;
			}
		}
		return "BROWSE_BY_ALBUM";
	}
}

var selectedLink;
function selectLink(lnk,reset) {

	if (selectedLink) selectedLink.style.fontWeight='normal';

	if (lnk) {
		lnk.style.fontWeight='bold';
		selectedLink=lnk;
	}
	if (reset == 1) {
		document.forms[0].browse.options[0].selected = "true";

	} else {
		if (reset && homestring) {reset = page;}

		for (var i=0;i < document.forms[0].browse.options.length; i++){

			if (document.forms[0].browse.options[i].value == reset) {
				document.forms[0].browse.options[i].selected = "true";
			}
		}
	}
}

function setLink(lnk) {
	lnk.href=getHomeCookie('SlimServer-Browserpage') + "&player" + getPlayer('SlimServer-player');
}

function toggleText(set) {
	for (var i=0; i < document.getElementsByTagName("div").length; i++) {

		var thisdiv = document.getElementsByTagName("div")[i];

		if (thisdiv.className == 'artworkText') {

			if ((set != 1 && thisdiv.style.display ==  '') || (thisdiv.style.display == 'none') 
					|| (set == 1 && getCookie('SlimServer-fishbone-showtext') == 1)) {
				
				thisdiv.style.display = 'inline';
				setCookie('SlimServer-fishbone-showtext',1);
				document.getElementById('showText').style.display = 'none';
				document.getElementById('hideText').style.display = 'inline';

			} else {
				thisdiv.style.display = 'none';
				setCookie('SlimServer-fishbone-showtext',0);
				document.getElementById('hideText').style.display = 'none';
				document.getElementById('showText').style.display = 'inline';
			}
		}
	}
}
