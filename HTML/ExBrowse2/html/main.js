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

var currentPlayer;

function displayreload() {
	document.getElementById("loading").style.display = "block";
	document.getElementById("loading").firstChild.innerHTML = "Lost connection, reloading...";
}

function mainload() {
	JXTK.Backend().reloadTrigger = displayreload;
	document.getElementById("loading").style.display = "block";
	setTimeout(continueload, 100);
}

function continueload() {
	initHome();
	initStatus();
	initPlaylist();
	document.getElementById("loading").firstChild.innerHTML = "Connecting...";
	loadHome();
}

function maybeDoneLoading() {
        // if (statusRefs > 0 && playlistRefs > 0 && homeRefs > 0) {
        if (statusRefs > 0 && homeRefs > 0) {
		setTimeout(hideLoadingScreen, 100);
        }
}

function hideLoadingScreen() {
	document.getElementById("loading").style.display = "none";
	document.getElementById("browsemode").style.display = "inline";
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
		try { document.getElementById(scrollbase).focus();
		} catch(e) {}
		div.scrollTop = s;
	}
	scrollcurrent = divname;
}

function handlekey() {
	// XXX FIXME: the iframe's onkeypress event will call this. Just a stub until keyboard shortcuts are done.
}

function abortkey() {
	return true;
}
