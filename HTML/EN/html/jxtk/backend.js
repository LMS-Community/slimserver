/* JXTK, copyright (c) 2005 Jacob Potter
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License,
   version 2.
*/

JXTK._BackendFactory = {
	createBackend : function(url) {
		var backend = new _JXTKBackend(this, url);

		return backend;
	},

	reqInProgress : 0,
	requests : new Array(),
	reqTimeout : null,
	lostContact : 0,
	contactTimeout : 10000
}

_JXTKBackend.prototype = {
	addHandler : function (handler) {
		this.handlers.push(handler);
	},

	removeHandler : function (handler) {
		for (i = 0; i < this.handlers.length; i++) {
			if (this.handlers[i] == handler) {
				this.handlers.splice(i, 1);
			}
		}
		return false;
	},

	submit : function (args) {
		var backend = this;
		var request = new _JXTKBackendRequest(backend, args);

		if (!this.factory.reqInProgress) {
			this.factory.reqInProgress = 1;
			this.factory.reqTimeout = setTimeout(_JXTKBackendTimeout, this.factory.contactTimeout);
			try {
				request.submit();
			} catch (err) {
				alert('Error sending request: ' + err);
				return false;
			}
		} else {
			this.factory.requests.push(request);
		}
	},

	globalArg : ""
};

function _JXTKBackend(factory, baseurl) {
	this.factory = factory;
	this.baseurl = baseurl;
	this.handlers = new Array();
}

function _JXTKBackendRequestHandler(request) {
	var backend = request.backend;
	var factory = backend.factory;

	if (request.xmlreq.readyState == 4) {
		if (request.xmlreq.status != 200) {
			alert('Error loading postback: ' + request.xmlreq.status);
			return false;
		}

		clearTimeout(backend.factory.reqTimeout);
		if (backend.factory.lostContact) {
// XXX FIXME: Do something better than a dumb reload when we lose contact with the server.
			window.location.reload(true);
		}
		
		if (factory.requests.length > 0) {

			// Check to see if there are more requests from this backend
			var isunique = 1;
			for (i = 0; i < factory.requests.length; i++) {
				if (factory.requests[i].backend == backend) {
					isunique = 0;
					break;
				}
			}
			
			if (isunique) {
				_JXTKBackendCallHandlers(request);
			}
			
			var newreq = backend.factory.requests.shift(); 
			try {
				newreq.submit();
			} catch (err) {
				alert('Error sending queued request: ' + err);
			}
		} else {
			backend.factory.reqInProgress = 0;
			_JXTKBackendCallHandlers(request);
		}
	}
}

function _JXTKBackendRequest(backend, args) {
	this.backend = backend;
	this.args = args;
	this.url = backend.baseurl + backend.globalArg;
	if (args) this.url += args;

	try {
		if (window.ActiveXObject) {
			this.xmlreq = new ActiveXObject("Microsoft.XMLHTTP");
		} else {
			this.xmlreq = new XMLHttpRequest();
		}
	} catch (err) {
		alert('Error creating XMLHttpRequest');
		return;
	}

	this.xmlreq.open("GET", this.url);

	try {
		this.xmlreq.setRequestHeader("Referer", document.location.href);
	} catch (err) {
		// Don't worry about it... the only browser that doesn't
		// spport setRequestHeader is Opera, and it puts in the
		// correct Referer: header anyway.
	}

	var request = this;

	this.submit = function () {
		request.xmlreq.send('');
	};

	this.xmlreq.onreadystatechange = function() { _JXTKBackendRequestHandler(request); } ;
}


function _JXTKBackendCallHandlers(request) {
	var resp = new _JXTKBackendResponse(request);

	for (handlercount = 0; handlercount < request.backend.handlers.length; handlercount++) {
		var thehandler = request.backend.handlers[handlercount];
		thehandler(resp);
		if (thehandler != request.backend.handlers[handlercount]) {
			handlercount--;
		}
	}
}


function _JXTKBackendTimeout() {
	lostContact = 1;
}


_JXTKBackendResponse.prototype = {
	getTag : function (tagname) {
		tags = this.xml.getElementsByTagName(tagname);
		if (tags && tags[0] && tags[0].firstChild) {
			return tags[0].firstChild.data;
		} else {
			return null;
		}
	}
};

function _JXTKBackendResponse(request) {
	this.xml = request.xmlreq.responseXML;
	return this;
}

