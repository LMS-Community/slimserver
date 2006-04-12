var p = 1;

// track the progress bar update timer state
var timerID = false;

// refresh data interval (1s for progress updates, 10s for only status)
var interval = 1000;

// update timer counter, waits for 10 updates when update interval is 1s
var inc = 0;

function changePlayer(player_List){
	var newPlayer = "=" + player_List.options[player_List.selectedIndex].value;
	setCookie('SlimServer-player',newPlayer);
	
	//parent.playlist.location="playlist.html?player" + newPlayer;
	window.location="status.html?player" + newPlayer;

	var rExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;
	if (parent.browser.location.href.indexOf('setup') == -1) {
		newHref(parent.browser.document,newPlayer);
		newHref(parent.header.document,newPlayer);
		newValue(parent.browser.document,newPlayer);
	} else {
		browseURL = new String(parent.browser.location.href);
		parent.browser.location=browseURL.replace(rExp, newPlayer);
	}
	headerURL = new String(parent.header.location.href);
	parent.header.location=headerURL.replace(rExp, newPlayer);
}

// change form values to correct player
function newValue(doc,plyr) {
	for (var j=0;j < doc.forms.length; j++){
		if (doc.forms[j].player) {
			var myString = new String(doc.forms[j].player.value);
			var rString = plyr;
			var rExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;
			doc.forms[j].player.value = myString.replace(rExp, rString);
		}
	}
}

// change browse/plugin/radio hrefs to proper player
function newHref(doc,plyr) {
	for (var j=0;j < doc.links.length; j++){
		var myString = new String(doc.links[j].href);
		var rString = plyr;
		var rExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;
		doc.links[j].href = myString.replace(rExp, rString);
	}
}

function toggleStatus(div) {
	if (document.getElementById(div).style.display == "none") {
		document.getElementById(div).style.display = "block";
		document.getElementById('statusImg_up').style.display = "inline";
		document.getElementById('statusImg_down').style.display = "none";
	} else {
		document.getElementById(div).style.display = "none";
		document.getElementById('statusImg_up').style.display = "none";
		document.getElementById('statusImg_down').style.display = "inline";
	}
}

function resizePlaylist(page) {

document.getElementById('playlist').height = document.body.clientHeight - document.getElementById('playlistframe').offsetTop;
}

function openRemote(player,playername)
{
	window.open('status.html?player='+player+'&undock=1', playername, 'width=480,height=210,status=no');
}

function setCookie(name, value)
{
	var expires = new Date();
	expires.setTime(expires.getTime() + 1000*60*60*24*365);
	document.cookie =
		name + "=" + escape(value) +
		((expires == null) ? "" : ("; expires=" + expires.toGMTString()));
}

function insertProgressBar(mp,end,at) 
{
	var s = '';
	if (!mp) s = '_s';
	if (document.all||document.getElementById)
	document.write('<div class="progressBarDiv"><img id="progressBar" name="progressBar" src="html/images/pixel.green'+s+'.gif" width="1" height="4"></div>');
	ProgressUpdate(mp,end,at)
}

// Update the progress dialog with the current state
function ProgressUpdate(mp,_progressEnd,_progressAt,curstyle) {
	var playctl = 'playCtlplay';
	//if (style == '_tan') playctl = 'playCtlplay_tan';
	[% IF undock %]
	if ($('playCtlplay') != null) {
		if ($('playCtlplay').src.indexOf('_s') != -1) {
			mp = 1;
			inc++;
			interval = 1000;
			$("progressBar").src ='[% webroot %]html/images/pixel.green.gif'

		} else {
			interval = 10000;
			mp = 0;
			inc = 0;
			$("progressBar").src = '[% webroot %]html/images/pixel.green_s.gif'
		}
	}
	[% END %]

	if (mp) _progressAt++;
	if(_progressAt > _progressEnd) _progressAt = _progressAt % _progressEnd;
	
	[% IF undock %]if ((_progressEnd > 0) && (_progressAt > 10) && (_progressAt == _progressEnd)) refreshUndock();[% END %]
	
	if (document.all) //if IE 4+
	{
		p = (document.body.clientWidth / _progressEnd) * _progressAt;
		eval("document.progressBar.width=p");
	}
	else if (document.getElementById) //else if NS6+
	{
		p = (document.width / _progressEnd) * _progressAt;
		$("progressBar").width=p+" ";
	}
	
	[% IF undock %]
	if ((mp && inc == 10) || interval == 10000) {
		var args = 'player='+player+'&ajaxRequest=1';
		getStatusData(args, refreshAll);
		inc = 0;
	}
	[% END %]
	timerID = setTimeout("ProgressUpdate( "+mp+","+_progressEnd+","+_progressAt+")", interval);
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
	url = getCookie(Name);
	if (!url) return "browsedb.html?hierarchy=album,track&level=0&page=BROWSE_BY_ALBUM";
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
	if (reset) {
		document.forms[0].browse.options[0].selected = "true";
	}
}

function setLink(lnk) {
	lnk.href=getHomeCookie('SlimServer-Browserpage') + "&player=" + getPlayer('SlimServer-player');
}

