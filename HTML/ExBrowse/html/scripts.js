var totalTime, progressAt, progressEnd;

function timetostr(t) {
	mins = Math.floor(t / 60);
	secs = (t % 60);
	if (secs == 0)
		return mins + ':00';
	else if (secs < 10)
		return mins + ':0' + secs;
	else
		return mins + ':' + secs;
}

// Update the progress dialog with the current state
function ProgressUpdate() {
	setTimeout("ProgressUpdate()", 1000);

        progressAt++;

        if(progressAt > progressEnd) progressAt = progressAt % progressEnd;

	p = Math.floor((50 / progressEnd) * progressAt);

	if (p > 50) p = p % 50;

	document.getElementById("progressBar").childNodes[p].src = "html/images/pixel_s.png";
	document.getElementById("progressBar").lastChild.nodeValue = ' ' + timetostr(progressAt) + ' / ' + totalTime;
}

function statusheader_load(mp, at, end) {
	parent.playlist.location.reload();

	progressAt = at / 10;
	progressEnd = end / 10;

	if (!mp) { 
		p = -1;
	} else {
		p = Math.floor((50 / progressEnd) * progressAt);
	}

	progbar = document.getElementById("progressBar");

	for (i = 0; i < 50; i++) {
		theImg = document.createElement('IMG');
		theImg.height = 8;
		theImg.width = 4;
		theImg.hspace = 1;
		theImg.border = 0;
		theImg.src = 'html/images/pixel' + (i <= p ? '_s' : '') + '.png';
		progbar.appendChild(theImg);
	}

	totalTime = ' ' + timetostr(progressEnd);
	theTxt = document.createTextNode(' ' + timetostr(progressAt) + ' / ' + totalTime);
	progbar.appendChild(theTxt);

        if (mp) ProgressUpdate();
}

function resetcookie() {
	var expires = new Date(); 
	expires.setTime(expires.getTime() + (60*24*60*60*1000));
	browseind = document.forms[0].browsemode.selectedIndex;
	searchind = document.forms[0].searchmode.selectedIndex;
	document.cookie = "ExBrowseMode=" + browseind + "/" + searchind + "; expires=" + expires.toGMTString();
}

function gobrowse() {
	box = document.forms[0].browsemode;
	dest = box.options[box.selectedIndex].value;

	if (dest) {
		last_browse_mode = dest;
		parent.browser.location.href = unescape(dest);
	}

	resetLinks(document.getElementById("library"));
	resetcookie();
}

function dobold(e) {
	if (!e) var e = window.event;
	resetLinks(e.target || e.srcElement);
}

function resetLinks(active) {
	links = document.getElementById("topmenu").getElementsByTagName("A");
	for (i = 0; links[i]; i++) {
		links[i].className = "";
	}
	active.className = "activemode";
}

function pwd() {
	pwd = document.getElementById("pwd").innerHTML;
	if (parent && parent.browsehead && parent.browsehead.document.getElementById("toppwd")) {
		parent.browsehead.document.getElementById("toppwd").innerHTML = pwd;
	} else {
		document.getElementById("pwd").style.display = "block";
	}
}

function doSearchSubmit() {
	searchbox = document.forms[0].searchmode;
	searchtext = document.forms[0].searchquery.value;
	resetLinks(document.getElementById('library'));
	parent.browser.location.href = unescape(searchbox.options[searchbox.selectedIndex].value) + '&query=' + searchtext;
	document.forms[0].searchquery.value = "";
	return false;
}

function browseload() {
	var dc = document.cookie;
	var prefix = "ExBrowseMode=";
	var begin = dc.indexOf("; " + prefix);
	if (begin == -1) {
		begin = dc.indexOf(prefix);
		if (begin != 0) begin = -1;
	} else {
		begin += 2;
	}
	
	if (begin >= 0) { 
		var end = dc.indexOf(";", begin);
		if (end == -1) {
			end = dc.length;
		}
		var cookie = unescape(dc.substring(begin + prefix.length, end));
		var delim = cookie.indexOf("/");
		if (delim > 0) {
			browseind = cookie.substring(0, delim) * 1;
			searchind = cookie.substring(delim + 1, cookie.length) * 1;
			document.forms[0].browsemode.selectedIndex = cookie.substring(0, delim);
			document.forms[0].searchmode.selectedIndex = cookie.substring(delim + 1, cookie.length);
		}
	}

	gobrowse();
}
