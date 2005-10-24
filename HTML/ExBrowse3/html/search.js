var ss = parent.ss;
var sub;

var searchInProgress = 0;
var xslp, searchreq;

var forcejs = 0;

function searchhandler(req) {
	searchInProgress = 0;
	document.getElementById("activesearch").style.display = "block";
	rxml = req.xml;

	asearchdiv = document.getElementById("activesearch");

	if (xslp && !forcejs) {
		var fragment = xslp.transformToFragment(rxml, document);
		asearchdiv.replaceChild(fragment, asearchdiv.firstChild);
		timestr = "XSLT ";
	} else {
		var output = doTransform(rxml)
		asearchdiv.innerHTML = output;
		timestr = "JS ";
	}
}

function searchsend() {
	try {
		if (!sub) sub = new JXTK2.SubText.Replacer("activesearch");

		searchtext = document.getElementById('searchquery').value;
		if (searchtext.length > 2) {
			sub.update(webroot + "search.html?liveDiv=1&manualSearch=1&query=" + searchtext);
			document.getElementById("activesearch").style.display = "block";
			searchInProgress = 0;
		} else {
			searchInProgress = 0;
			document.getElementById("activesearch").style.display = "none";
		}
	} catch (err) {
		alert(err);
	}
	return false;
}

function searchkey() {
	if (searchInProgress == 0) {
		setTimeout(searchsend, 250);
		searchInProgress = 1;
	}
	return true;
}
