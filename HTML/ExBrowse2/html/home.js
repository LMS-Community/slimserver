/////////////////////////////////////////////
//
// Home
//
/////////////////////////////////////////////

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
	document.getElementById("browseframe").src = "/ExBrowse2/" + url + "&player=" + currentPlayer;
}

function loadHome() {
	currentPlayer = document.getElementById("playersel").value;
	updateHome();
}

function updateHome() {
	postback("/ExBrowse2/home.xml", updateHome_handler);
	setTimeout(updateHome, 10000);
}

function updateHome_handler(req, url) {
	resp = req.responseXML;
	players = resp.getElementsByTagName("player");
	playersel = document.getElementById("playersel");

	if (players.length == 1) {
		playersel.style.visibility = "hidden";
	} else {
		playersel.style.visibility = "visible";
	}

	if (playersel.options) {
		olength = playersel.options.length;
	} else {
		olength = 0;
	}

	if (olength < players.length) {
		clength = olength;
	} else {
		clength = players.length;
	}

	indexToSelect = 0;

	for (i = 0; i < clength; i++) {
		pname = players[i].getElementsByTagName("playername")[0].firstChild.data;
		pid = players[i].getElementsByTagName("playerid")[0].firstChild.data;
		playersel.options[i].text = pname;
		playersel.options[i].value = pid;
		if (pid == currentPlayer) indexToSelect = i;
	}

	if (players.length > clength) {
		for (i = clength; i < players.length; i++) {
			pname = players[i].getElementsByTagName("playername")[0].firstChild.data;
			pid = players[i].getElementsByTagName("playerid")[0].firstChild.data;
			newopt = new Option (pname, pid);
			playersel.options[playersel.options.length] = newopt;
			if (pid == currentPlayer) indexToSelect = i;
		}
	}

	if (olength > clength) {
		playersel.options.length = clength;
	}

	playersel.selectedIndex = indexToSelect;

	if (!currentPlayer) currentPlayer = playersel.value;

	if (homeRefs == 0) {
		loadCookie();
		homeRefs++;
		updateStatusCombinedPeriodically();
	}
}

function loadCookie() {
	var dc = document.cookie;
	var prefix = "ExBrowseMode=";
	var begin = dc.indexOf(prefix);

	var browseind = 0;
	var searchind = 0;

	if (begin >= 0) { 
		var end = dc.indexOf(";", begin);
		if (end == -1) { end = dc.length;
		}
		var cookie = unescape(dc.substring(begin + prefix.length, end));
		var delim = cookie.indexOf("/");
		if (delim > 0) {
			browseind = 0;
			searchind = 0;
			browseind = cookie.substring(0, delim) * 1;
			searchind = cookie.substring(delim + 1, cookie.length) * 1;
			try {
				document.getElementById("browsemode").selectedIndex = browseind;
				document.getElementById("searchmode").selectedIndex = searchind;
			} catch(e) {
			}
		}
	}
	gobrowseindex(browseind, searchind);

}

function gobrowse() {
	gobrowseindex(document.getElementById("browsemode").selectedIndex, 0);
}

function resetcookie() {
	resetcookieindex(document.getElementById("browsemode").selectedIndex,
		document.getElementById("searchmode").selectedIndex);
}

function gobrowseindex(browseind, searchind) {
	if (document.getElementById("browsemode").options[browseind]) {
		last_browse_mode = document.getElementById("browsemode").options[browseind].value;
		browseurl(unescape(last_browse_mode));
	}

	resetLinks(document.getElementById("library"));

	resetcookieindex(browseind, searchind);
}

function resetcookieindex(browseind, searchind) {
	var expires = new Date(); 
	expires.setTime(expires.getTime() + (60*24*60*60*1000));
	cookiestring = "ExBrowseMode=" + browseind + "/" + searchind + "; expires=" + expires.toGMTString();
	document.cookie = "ExBrowseMode=" + browseind + "/" + searchind + "; expires=" + expires.toGMTString();
}

function pushpwd(text) {
	document.getElementById("toppwd").innerHTML = text;
}

function dobold(e) {
	if (!e) var e = window.event;
	resetLinks(e.target || e.srcElement);
}

function resetLinks(active) {
	links = document.getElementById("topmenu").getElementsByTagName("A");
	for (i = 0; links[i]; i++) {
		links[i].className = "fakelink";
	}
	active.className = "fakelink activemode";
}

function initBrowse() {
}
