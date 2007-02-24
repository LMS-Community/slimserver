var p = 1;

// regex to match player id, mac and ip format.
var playerExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;

function homelink() {
	if (homestring) {
		document.getElementById('homelink').innerHTML = homestring;
	}
}

function loadBrowser(force) {
	if (force || parent.browser.location.href.match('black.html')) {
		page = getPage();
		chooseBrowser(null,page);
	}
}

function doSearch(value)
{
	selectLink();
	parent.browser.location='search.html?manualSearch=1&query=' + value + '&player' + getPlayer('SlimServer-player');
}

function goHome()
{
	var homepage = getPage();
	chooseBrowser(null,homepage);
}
	
function changePlayer(player_List) {
	player = player_List.options[player_List.selectedIndex].value;
	
	player = escape(player);
	
	var newPlayer = "=" + player;
	newHref(parent.status.document,newPlayer);
	refreshPlaylist(player);
	
	var args = 'player=' + player + '&ajaxRequest=1&s=' + Math.random();
	getStatusData(args, refreshNewPlayer);
	
	if (parent.browser.location.href.indexOf('settings') == -1 &&
	    parent.browser.location.href.indexOf('plugins') == -1) {
		newHref(parent.browser.document,newPlayer);
		newHref(parent.header.document,newPlayer);
		newValue(parent.browser.document,unescape(player));
	} else {
		newpage = '';
		browseURL = new String(parent.browser.location.href);
		parent.browser.location=browseURL.replace(playerExp, newPlayer);
	}

	if (document.all) { //certain versions of IE will just have to reload the header
		parent.header.location = "home.html?player=" + player;
	}
	
	var page = parent.header.document.getElementById('homepage').innerHTML;
	selectLink("", page);
}

// change browse/plugin/radio hrefs to proper player
function newHref(doc,plyr) {

	for (var j=0;j < doc.links.length; j++){
		var myString = new String(doc.links[j].href);
		var rString  = plyr;
		doc.links[j].href = myString.replace(playerExp, rString);
	}
}

function newValue(doc,plyr) {

	for (var j=0;j < doc.forms.length; j++){

		if (doc.forms[j].player) {
			doc.forms[j].player.value = plyr;
		}
	}
}

function toggleStatus(divs) {

	for (var i=0; i < divs.length; i++) {

		if ($(divs[i]).style.display == "none") {
			$(divs[i]).style.display          = "block";
			$('statusImg_up').style.display   = "inline";
			$('statusImg_down').style.display = "none";

		} else {
			$(divs[i]).style.display          = "none";
			$('statusImg_up').style.display   = "none";
			$('statusImg_down').style.display = "inline";
		}
	}
}

function resizePlaylist(page) {
	//$('playlist').height = document.body.clientHeight - $('playlistframe').offsetTop;
	if ($('playlistStatus')) {
		top.document.getElementById('player_frame').rows = $('playlistStatus').offsetTop+20+', *';
	}
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

// grab homepage cookie
function getHomeCookie(Name) 
{
	var url = getCookie(Name);
	// look for old artwork cookie and work around it
	var re  = new RegExp(/artwork,/i);
	var m   = re.exec(url);

	if (!url || m) return "browsedb.html?hierarchy=album,track&level=0";

	return url;
}

// parse the page name token (handles old style full href cookie)
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
		parent.header.document.forms[0].browse.options[0].selected = "true";

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

function setLink(lnk) {
	lnk.href=getHomeCookie('SlimServer-Browserpage') + "&player=" + getPlayer('SlimServer-player');
}

// function to turn off text under album images while in gallery view.
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
