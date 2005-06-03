/////////////////////////////////////////////
//
// Home
//
/////////////////////////////////////////////

var strings;

var homebackend;
var homecookie;
var playercookie;

var playerlistbox;

	// XXX FIXME: The browse/settings/help/search links should be JXTK Buttons.

function goplayersettings() {
	browseurl("setup.html?page=player&playerid=" + currentPlayer);
}

function goadvancedsearch() {
	browseurl('advanced_search.html?');
	resetLinks(document.getElementById('library'));
}

function gosearch() {
	browseurl('livesearch.html?');
	resetLinks(document.getElementById('library'));
}

function browseurl(url) {
	document.getElementById("browseframe").src = webroot + url + "&player=" + currentPlayer;
}

function updatePlayer(nosub) {
	currentPlayer = playerlistbox.input.value;

	homebackend.globalArg = '?player=' + currentPlayer;
	statusbackend.globalArg = '?player=' + currentPlayer;

	playercookie.setValue(currentPlayer);

	if(nosub != true) statusbackend.submit();
}

function initHome() {
        homebackend = JXTK.Backend().createBackend(webroot + 'home.xml?page=xml');
	homebackend.addHandler(homeHandler);

	homecookie = JXTK.Cookie().createCookie("ExBrowse2Mode");
	playercookie = JXTK.Cookie().createCookie("ExBrowse2Player");

	playerlistbox = JXTK.ListBox().createListBox("playersel");
	playerlistbox.addHandler(updatePlayer);
}


function loadHome() {
	var loc = window.location.href;
	var qpos = loc.indexOf("?player=");
	if (qpos < 0) qpos = loc.indexOf("&player=");

	if (qpos < 0) {
		currentPlayer = escape(playercookie.getValue());
	} else {
		var pl = loc.substring(qpos + 8);
		var end = pl.indexOf("&");
		if (end > 0) pl = pl.substring(0, end);
		currentPlayer = pl.replace(/:/g,"%3A");
	}

	updateHome();
}

function updateHome() {
	homebackend.submit();
	setTimeout(updateHome, 10000);
}

function homeHandler(resp) {
	var players = resp.xml.getElementsByTagName("player");
	var newPlayerList = new Array();
	var indexToSelect = 0;

	if (players.length == 1) {
		playerlistbox.input.style.visibility = "hidden";
	} else {
		playerlistbox.input.style.visibility = "visible";
	}

	for (var i = 0; i < players.length; i++) {
		var newItem = new Object();
		newItem.name = players[i].getElementsByTagName("playername")[0].firstChild.data;
		pid = players[i].getElementsByTagName("playerid")[0].firstChild.data;
		newItem.value = pid;
		newPlayerList.push(newItem);

		if (pid == currentPlayer) {
			indexToSelect = i;
		}
	};

	playerlistbox.update(newPlayerList);
	playerlistbox.selectIndex(indexToSelect);

	if (!currentPlayer) currentPlayer = playerlistbox.input.value;
	updatePlayer(true);

	// XXX FIXME: Initialize JXTK._Strings{} from homeHandler.
        //strings = resp.getElementsByTagName("strings")[0];
        //FROM = " " + strings.getAttribute("from") + " ";
        //BY = " " + strings.getAttribute("by") + " ";

	if (homeRefs == 0) {
		loadCookie();
		homeRefs++;
		getStatusPeriodically();
	}
}

function loadCookie() {
	var browseind = homecookie.getValue();

	try {
		document.getElementById("browsemode").selectedIndex = browseind;
	} catch(e) {
	}

	gobrowseindex(browseind);
}

function gobrowse() {
	gobrowseindex(document.getElementById("browsemode").selectedIndex, 0);
}

function resetcookie() {
	homecookie.setValue(document.getElementById("browsemode").selectedIndex);
}

function gobrowseindex(browseind) {
	if (!document.getElementById("browsemode").options[browseind]) {
		browseind = 0;
	}

	last_browse_mode = document.getElementById("browsemode").options[browseind].value;
	browseurl(unescape(last_browse_mode));

	resetLinks(document.getElementById("library"));

	homecookie.setValue(browseind);
}

function pushpwd(text) {
	document.getElementById("toppwd").innerHTML = text;
}

function dobold(e) {
	resetLinks(JXTK.Misc().fixEvent(e).targ);
}

function resetLinks(active) {
	links = document.getElementById("topmenu").getElementsByTagName("A");
	for (i = 0; links[i]; i++) {
		links[i].className = "fakelink";
	}
	active.className = "fakelink activemode";
}

