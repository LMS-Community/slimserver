///////////////////////////////////////////
//
// Main 
//
///////////////////////////////////////////

var statusRefs = 0;
var playlistRefs = 0;
var browseRefs = 0;
var homeRefs = 0;

var scrollcurrent = "";

function mainload() {
	document.getElementById("loading").style.display = "block";
	setTimeout(continueload, 100);
}

function continueload() {
	initStatus();
	initBrowse();
	loadHome();
}

function maybeDoneLoading() {
        if (statusRefs > 0 && playlistRefs > 0 && homeRefs > 0) {
		setTimeout(hideLoadingScreen, 100);
        }
}

function hideLoadingScreen() {
	document.getElementById("loading").style.display = "none";
	document.getElementById("browsemode").style.display = "inline";
	document.getElementById("searchmode").style.display = "inline";
	document.getElementById("searchquery").style.display = "inline";
	document.getElementById("playersel").style.display = "inline";
	document.getElementById("browseframe").style.display = "block";
}

function scrollfix(divname, scrollbase) {
	if (!divname) {
		divname = "noscroll";
		scrollbase = "noscroll";
	}

	if (scrollcurrent != divname && divname != "browsescroll") {	
		var div = document.getElementById(divname);
		var s = div.scrollTop;
		document.getElementById(scrollbase).focus();
		div.scrollTop = s;
	}
	scrollcurrent = divname;
}

function pwd() {
	pwd = document.getElementById("pwd").innerHTML;
	if (parent && parent.browsehead && parent.browsehead.document.getElementById("toppwd")) {
		parent.browsehead.document.getElementById("toppwd").innerHTML = pwd;
	} else {
		document.getElementById("pwd").style.display = "block";
	}
}

var browseCache = new Object();

////////////////////////////////////////////
//
//  Status
//
///////////////////////////////////////////

function updateStatusCombinedPeriodically() {
	updateStatusCombined();
	setTimeout(updateStatusCombinedPeriodically, 5000);
}

function updateStatusCombined(args) {
	var url = "/ExBrowse2/status.xml?player=" + currentPlayer;
	if (args) {
		url = url + args;
	}
	postback(url, updateStatus_handler);
}
