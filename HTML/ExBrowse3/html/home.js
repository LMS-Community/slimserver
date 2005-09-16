var homecookie;
var playercookie;
var homelinks;

var playerlistbox;

var curbrowse, lastbrowseurl;

function browseurl(loc, clink, isreplace) {
	if (curbrowse && curbrowse.style) curbrowse.style.visibility = "hidden";

	if (typeof loc == "object") {
		curbrowse = loc;
		if (clink == undefined) clink = "0";
		top.frames.browseframe.location.href = webroot + "/html/blank.html?pwd=" + escape(loc.getAttribute('pwd')) + "&clink=" + clink;
	} else {
		var newurl = webroot + loc + "&player=" + escape(curPlayer);

		if (isreplace) {
			top.frames.browseframe.location.replace(newurl);
		} else {
			top.frames.browseframe.location.href = newurl;
		}
	}
}

function pullpwd(clink, isfake) {
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
	document.getElementById("toppwd").innerHTML = text;
}

function updatePlayer(nosub) {
	curPlayer = playerlistbox.getValue();
	playercookie.setValue(curPlayer);

	if(nosub != true) {
		getPlaylist();
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
	homecookie = new JXTK2.Cookie("ExBrowse2Mode");
	playercookie = new JXTK2.Cookie("ExBrowse2Player");

	homelinks = new Array(
		new JXTK2.Button("homebrowse", gobrowse),
		new JXTK2.Button("homessettings", function() {
			browseurl("setup.html?page=server");
		}),
		new JXTK2.Button("homepsettings", function() {
			browseurl("setup.html?page=player&playerid=" + escape(curPlayer));
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

	playerlistbox = new JXTK2.ListBox("playersel");
	playerlistbox.addHandler(updatePlayer);
}

function loadHome() {
	gobrowseindex(homecookie.getValue(), 0, true);
}
