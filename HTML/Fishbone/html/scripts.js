var p = 1;

// regex to match player id, mac and ip format.
var playerExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;

function homelink() {
	if (homestring) {
		$('homelink').innerHTML = homestring;
	}
}

function loadBrowser(force) {
	if (force || parent.browser.location.href.match('black.html')) {
		page = getPage();
		chooseBrowser(null,page);
	}
}

function changePlayer(player_List) {
	player = player_List.options[player_List.selectedIndex].value;
	//setCookie('SlimServer-player', player);
	player = escape(player);
	
	var newPlayer = "=" + player;
	console.log("new player"+player);
	newHref(this.document,newPlayer);
	getPlaylistData(null,null,player);
	
	var args = 'player='+player+'&ajaxRequest=1&s='+Math.random();
	ajaxRequest('status.html', args, refreshNewPlayer);
	
	//var newpage = '';
	//var rExp= new RegExp("&page=(.*?)$");
	
	if (parent.browser.location.href.indexOf('settings') == -1 &&
	    parent.browser.location.href.indexOf('plugins') == -1) {
		newHref(parent.browser.document,newPlayer);
		newHref(parent.header.document,newPlayer);
		newValue(parent.browser.document,unescape(player));
	} else {
		//newpage = '';
		browseURL = new String(parent.browser.location.href);
		parent.browser.location=browseURL.replace(playerExp, newPlayer);
	}

	//var myString = getHomeCookie('SlimServer-Browserpage');
	//if (rExp.exec(myString)) newpage = "&page=" + rExp.exec(myString)[1];

	//headerURL = new String(parent.header.location.href);
	//newloc = headerURL.replace(playerExp, newPlayer);
	
	if (document.all) { //certain versions of IE will just have to reload the header
		parent.header.location = "home.html?player=" + player;
	}
	
	var page = parent.header.document.getElementById('homepage').innerHTML;
	selectLink("",page);
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

function resizePlaylist() {

	if (! $$('playlistframe')) {
		return;
	}

	$('playlistframe').style.height = document.body.clientHeight - $('playlistframe').offsetTop - 5;

	initSortable('playlist_draglist');
}

function openRemote() {
	window.open('status.html?player='+player+'&undock=1', '', 'width=480,height=210,status=no');
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
	if (plyr.indexOf("=") == -1) plyr = plyr;

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

				if (!page) return url;
				return page;
			}
		}
		return url;
	}
}

var selectedLink;
function selectLink(lnk,reset) {

	parent.header.document.getElementById('homelink').style.fontWeight = 'normal';
	if (selectedLink) selectedLink.style.fontWeight = 'normal';

	if (lnk) {
		lnk.style.fontWeight='bold';
		selectedLink=lnk;
	}
	if (reset == 1) {
		document.forms[0].browse.options[0].selected = "true";

	} else {
		if (reset) {
			for (var i=0;i < parent.header.document.forms[0].browse.options.length; i++){
	
				if (parent.header.document.forms[0].browse.options[i].value == reset) {
					parent.header.document.forms[0].browse.options[i].selected = "true";
				}
			}
		}
	}
}

function setLink(lnk, player) {
	lnk.href=getHomeCookie('SlimServer-Browserpage') + "&player" + player;
}

function toggleText(set) {
	for (var i=0; i < document.getElementsByTagName("div").length; i++) {

		var thisdiv = document.getElementsByTagName("div")[i];

		if (thisdiv.className == 'artworkText') {

			if ((set != 1 && thisdiv.style.display ==  '') || (thisdiv.style.display == 'none') 
					|| (set == 1 && getCookie('SlimServer-fishbone-showtext') == 1)) {
				
				thisdiv.style.display = 'inline';
				setCookie('SlimServer-fishbone-showtext',1);
				$('showText').style.display = 'none';
				$('hideText').style.display = 'inline';

			} else {
				thisdiv.style.display = 'none';
				setCookie('SlimServer-fishbone-showtext',0);
				$('hideText').style.display = 'none';
				$('showText').style.display = 'inline';
			}
		}
	}
}

function showSongInfo (args) {
	//console.log("showsonginfo", args[1]);
	var webroot = args[0];
	var item = args[1];
	var player = args[2];
	
	parent.browser.location = webroot + 'songinfo.html?item='+ item +'&amp;player=' + player;
}

var dcTime=250;    // doubleclick time
var dcDelay=100;   // no clicks after doubleclick
var dcAt=0;        // time of doubleclick
var savEvent=null; // save Event for handling doClick().
var savAction = null;
var savArgs = null;
var savEvtTime=0;  // save time of click event.
var savTO=null;    // handle of click setTimeOut

function hadDoubleClick() {
	var d = new Date();
	var now = d.getTime();
	if ((now - dcAt) < dcDelay) {
		return true;
	}
	return false;
}

function handleClick(which, action, args) {
	switch (which) {
		case "click": 
			// If we've just had a doubleclick then ignore it
			if (hadDoubleClick()) return false;
			// Otherwise set timer to act.  It may be preempted by a doubleclick.
			savEvent = which;
			savAction = action;
			savArgs = args;
			d = new Date();
			savEvtTime = d.getTime();
			savTO = setTimeout("doClick(savEvent, savAction, savArgs)", dcTime);
			break;
		case "dblclick":
			doDoubleClick(which, action, args);
			break;
		default:
	}
}

function doClick(which, action, args) {
	 // preempt if DC occurred after original click.

	if (savEvtTime - dcAt <= 0) {
		return false;
	}
	action(args);
	//console.log("click", action);
}

function doDoubleClick(which, action, args) {
	var d = new Date();
	dcAt = d.getTime();

	if (savTO != null) {
		clearTimeout( savTO );          // Clear pending Click  
		savTO = null;
	}
	action(args);
	//console.log("double click", action);
}