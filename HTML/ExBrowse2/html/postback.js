var reqInProgress;
var reqTimeout;
var requests = new Array();
var handlers = new Array();

var currentPlayer; 
var playerList; // Array(); but allocated in updateHome_handler() rather than here

var contactTimeout = 10000;
var lostContact = 0;

var postbackDelay = 0; // Set this to 0 for normal operations, 500 or so for delayed parsing

function postback(url, handler) {
	try {
		var req;
		if (window.ActiveXObject) {
			req = new ActiveXObject("Microsoft.XMLHTTP");
		} else {
			req = new XMLHttpRequest();
		}
	} catch (err) {
		alert('Error creating XMLHttpRequest');
		return;
	}

	req.open("GET",  url);
	req.onreadystatechange = function() { postback_handler(req, url, handler); } ;

	try {
		req.setRequestHeader("Referer", document.location.href);
	} catch (err) {
		// Don't worry about it... the only browser that doesn't
		// spport setRequestHeader is Opera, and it puts in the
		// correct Referer: header anyway.
	}

	if (!reqInProgress) {
		reqInProgress = 1;
		reqTimeout = setTimeout(postback_timeout, contactTimeout);
		try {
			req.send('');
		} catch (err) {
			alert('Error sending request: ' + err);
			return false;
		}
	} else {
		requests.push(req);
		handlers.push(handler);
	}
}

function postback_handler(req, url, handler) {
	if (req.readyState == 4) {
		if (req.status != 200) {
			alert('Error loading postback: ' + req.status);
			return false;
		}
		clearTimeout(reqTimeout);
		if (lostContact) window.location.reload(true);
		
		if (requests.length > 0) {
			var isunique = 1;
			for (i = 0; i < handlers.length; i++) {
				if (handlers[i] == handler) {
					isunique = 0;
					break;
				}
			}
			
			if (isunique) {
				if (postbackDelay) {
					setTimeout(function () { handler(req, url); }, postbackDelay);
				} else {
					handler(req, url);
				}
			}
			
			newreq = requests.shift(); 
			handlers.shift(); 
			try {
				newreq.send('');
			} catch (err) {
				alert('Error sending queued request: ' + err);
			}
		} else {
			reqInProgress = 0;
			if (postbackDelay) {
				setTimeout(function () { handler(req, url); }, postbackDelay);
			} else {
				handler(req, url);
			}
		}
	}
}

function postback_timeout() {
//	document.getElementById('maindeck').selectedIndex = 2;
	lostContact = 1;
	postback("/ExBrowse2/home.xml", updateHome_handler);
}

