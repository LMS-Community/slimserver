var homecookie;
var playercookie;
var homelinks;
var curPlayer;

var playerlistbox;

var curbrowse, lastbrowseurl;

function browseurl(loc, clink, isreplace) {
	if (curbrowse && curbrowse.style) curbrowse.style.visibility = "hidden";

	if (typeof loc == "object") {
		curbrowse = loc;
		if (clink == undefined) clink = "0";
		top.frames.browseframe.location.href = webroot + "html/blank.html?pwd=" + escape(loc.getAttribute('pwd')) + "&clink=" + clink;
	} else {
		var newurl = loc + "&player=" + escape(curPlayer);

		if (loc.substr(0, 7) != "http://") {
			newurl = webroot + newurl;
		}

		if (isreplace) {
			top.frames.browseframe.location.replace(newurl);
		} else {
			top.frames.browseframe.location.href = newurl;
		}
	}
}

function browse_href_fix(tdoc, sourceUrl) {
	/* Updates all <a href> tags to use browseurl() */
	if (!tdoc) tdoc = document;

	if (!sourceUrl) sourceUrl = tdoc.location.href;
	var pluginMatch = sourceUrl.match(/\/plugins\/[a-zA-Z]*\//);

	var aList = tdoc.getElementsByTagName("a");
	var aListLen = aList.length;
	for (var i = 0; i < aListLen; i++) {
		var el = aList[i];
		if (!el.getAttribute("href")) continue;

		if (pluginMatch) {
			var href = el.getAttribute("href");
			if (href.substr(0, 7) != "http://" && href[0] != "/") {
				href = webroot + pluginMatch + href;
			}
			el.setAttribute("href", href);
		}

		el.onclick = function() {
			browseurl(this.getAttribute("href"));
			return false;
		}
	}
}

function pullpwd(clink, isfake, tdoc) {

	if (tdoc) browse_href_fix(tdoc);

	if (typeof clink == "number") {
		for (var j = 0; j < homelinks.length; j++) {
			homelinks[j].setState(clink == j);
		}
	}

	if (isfake) {
		document.getElementById("browseframe").style.visibility = "hidden";
		if (curbrowse) curbrowse.style.visibility = "visible";
	} else {
		document.getElementById("browseframe").style.visibility = "visible";
		if (curbrowse) curbrowse.style.visibility = "hidden";
	}

	var text = top.frames.browseframe.document.getElementById("pwd").innerHTML;
	$("toppwd").innerHTML = text;
	if (tdoc) {
		browse_href_fix($("toppwd"), tdoc.location.href);
	}
}

function updatePlayer(nosub) {
	curPlayer = playerlistbox.getValue();
	playercookie.setValue(curPlayer);

	if(nosub != true) {
		playlistObj = null;
		getStatus();
	}
}

function gobrowseindex(browseind, isreplace) {
	if (!browseind || !document.getElementById("browsemode").options[browseind]) {
		browseind = 0;
	}

	document.getElementById("browsemode").selectedIndex = browseind;
	browseurl(unescape(document.getElementById("browsemode").options[browseind].value), isreplace);

	for (var j = 0; j < homelinks.length; j++) homelinks[j].setState(j == 0);

	homecookie.setValue(browseind);
}

function gobrowse() {
	gobrowseindex(document.getElementById("browsemode").selectedIndex, 0);
}

function gohelp() {
	browseurl(document.getElementById("helpframe"), 3);
}

function goradio() {
	browseurl(document.getElementById("radioframe"), 4);
}

function initHome() {
	browse_href_fix();

	playercookie = new JXTK2.Cookie("ExBrowse2Player");

	curPlayer = playercookie.getValue();

	playerlistbox = new JXTK2.ListBox("playersel");
	playerlistbox.addHandler(updatePlayer);

	if (document.getElementById("homeblock")) {
		homecookie = new JXTK2.Cookie("ExBrowse2Mode");

		homelinks = new Array(
			new JXTK2.Button("homebrowse", gobrowse),
			new JXTK2.Button("homessettings", function() {
				browseurl("setup.html?page=BASIC_SERVER_SETTINGS");
			}),
			new JXTK2.Button("homepsettings", function() {
				browseurl("setup.html?page=BASIC_PLAYER_SETTINGS&playerid=" + escape(curPlayer));
			}),
			new JXTK2.Button("homehelp", gohelp)
		);
	
		var radiobutton = new JXTK2.Button("homeradio", goradio);
		if (radiobutton.getEl) {
			homelinks.push(radiobutton);
		}

		for (var i = 0; i < homelinks.length; i++) {
			homelinks[i].addClickHandler(function (button) {
				for (var j = 0; j < homelinks.length; j++) {
				homelinks[j].setState(button == homelinks[j]);
				}
			});
		}

		new JXTK2.Button("searchbasic", function() {
			for (var j = 0; j < homelinks.length; j++) homelinks[j].setState(j == 0);
			browseurl('search.html?liveSearch=1');
		});

		new JXTK2.Button("searchadv", function() {
			for (var j = 0; j < homelinks.length; j++) homelinks[j].setState(j == 0);
			browseurl('advanced_search.html?');
		});
	}
}

function loadHome() {
	if (homecookie) gobrowseindex(homecookie.getValue(), 0, true);
}


function chooseSettings(option, value) {
	browseurl("setup.html?page=" + value + "&playerid=" + escape(curPlayer));
}
