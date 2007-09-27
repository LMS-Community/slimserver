/* JXTK2, copyright (c) 2005 Jacob Potter */

Array.prototype['__(JSONArray)__'] = true;

if (!window['$']) {
	window['$'] = function(el) {
		if (typeof el == 'string') {
			return document.getElementById(el);
		} else {
			return el;
		}
	}
}

var JXTK2 = {
	version : function() {
		return '2.0.0';
	}
}

JXTK2.Cookie = function(prefix) {

	// Constructor Code

	var pval = prefix + '=';
	var duration = 60*60*24*365	// 1 year default
	var self = this;

	// Public Functions

	this.getValue = function() {
		var dc = document.cookie;
		var ind = 0;

		var begin = dc.indexOf(pval);

		if (begin >= 0) {
			var end = dc.indexOf(";", begin);
			if (end == -1) {
				end = dc.length;
			}

			var cookie = unescape(dc.substring(begin + pval.length, end));

			return cookie;
		} else {
			return undefined;
		}
	};

	this.setValue = function(value) {
		var expires = new Date();
		expires.setTime(expires.getTime() + duration);
		document.cookie = pval + value + "; expires=" + expires.toGMTString();
	};
	
	this.setDuration = function(newduration) {
		duration = newduration;
	};
};

function _JXTKCookie(prefix) {
	this.prefix = prefix;
}

JXTK2.JSON = {
	serialize : function(obj) {
		var outbuf = [];

		if (obj == undefined) return 'null';

		switch (typeof obj) {
		case 'object':
			if (JXTK2.Misc.isArray(obj)) {
				for (var i = 0; i < obj.length; i++)
					outbuf.push(JXTK2.JSON.serialize(obj[i]));
				return '[' + outbuf.join(',') + ']';
			} else {
				for (var i in obj) 
					outbuf.push(JXTK2.JSON.serialize(i) + ':' + JXTK2.JSON.serialize(obj[i]));
				return '{' + outbuf.join(',') + '}';
			}
		case 'number':
			return isFinite(obj) ? String(obj) : 'null';
		case 'boolean':
			return obj ? 'true' : 'false';
		case 'string':
			var out = '';

			for (var i = 0; i < obj.length; i++) {
				var c = obj.charAt(i);

				if (c == '\\')		out += '\\\\';
				else if (c == '"')	out += '\\"';
				else if (c >= ' ')	out += c;
				else if (c == '\b')	out += '\\b';
				else if (c == '\f')	out += '\\f';
				else if (c == '\n')	out += '\\n';
				else if (c == '\r')	out += '\\r';
				else if (c == '\t')	out += '\\t';
				else {
					var cc = c.charCodeAt();
					var ccl = (cc % 16);
					out += '\\u00' + ((cc-ccl) / 16).toString(16) + (ccl).toString(16);
				}
			}
			
			return '"' + out + '"';
		default:
			return 'null';
		}
	}
};

JXTK2.JSONRPC = {
	_config : {
		contactTimeout : 10000,	// Lost contact after waiting 10 seconds for a response
		errorThresh : 2,	// Lost contact after 2 consecutive XMLHTTPRequest errors
		reloadDelay : 5000	// Reload 5 seconds after losing contact
	},
	_state : {
		reqInProgress : 0,
		requests : new Array(),
		reqTimeout : null,
		reloadTrigger : null,
		lostContact : 0,
		errorCount : 0
	}
};

JXTK2.JSONRPC.Proxy = function(url) {

	// Constructor Code

	var self = this;
	var proxyurl = url;
	var queue = [];

	// Public Functions

	this.toString = function () {
		return "[object JXTK2.JSONRPC.Proxy " + proxyurl + " ]";
	};

	this.queueCall = function (methodName, methodParams) {
		queue.push({ method : methodName, params : methodParams});
	};

	this.call = function (methodName, methodParams, onResp) {

		if (methodName) {
			if (typeof methodParams != 'object') methodParams = [];
			this.queueCall(methodName, methodParams);
		}

		var json = JXTK2.JSON.serialize(queue.length > 1 ? queue : queue[0]);
		queue = [];

		var xmlreq;

		try {
			if (window.ActiveXObject) {
				xmlreq = new ActiveXObject("Microsoft.XMLHTTP");
			} else {
				xmlreq = new XMLHttpRequest();
			}
		} catch (err) {
			alert('Error creating XMLHttpRequest');
			return;
		}

		var isFunc = (typeof onResp == "function");

		xmlreq.open("POST", proxyurl, (onResp ? true : false));

		try {
			xmlreq.setRequestHeader("Referer", document.location.href);
		} catch (err) {
		}

		if (isFunc) {
			xmlreq.onreadystatechange = function () { handleResp(xmlreq, onResp); };
		}

		xmlreq.send(json);

		if (!onResp) return handleResp(xmlreq, onResp);
	}

	// Private Functions

	function handleResp(xmlreq, onResp) {
		if (xmlreq.readyState != 4) return;

		if (xmlreq.status != 200) {

			// TODO: better error handling
			if (xmlreq.status == 404) {
				alert("Transport Error: 404.\nAre you sure that SqueezeCenter is running and the RPC plugin is enabled?\n\nYou can return to the Default skin at http://<server>:9000/Default/");
			} else {
				alert("Transport Error: " + xmlreq.status);
			}
			return;

		}

		var respobj;
		eval('respobj=' + xmlreq.responseText);

		// For now, only the return value from the last call in the queue is available
		if (JXTK2.Misc.isArray(respobj)) {
			respobj = respobj[respobj.length - 1];
		}

		if (respobj.error) {
			alert("RPC Fault: \"" + respobj.error + "\"");
		}

		if (typeof onResp == "function") {
			onResp(respobj);
		} else {
			return respobj;
		}
	}
};

JXTK2.SubText = {

	Replacer : function(node, defaulturl) {

		if (typeof node == "string") {
			node = document.getElementById(node);
		}

		this.update = function(url) {
			try {
				if (window.ActiveXObject) {
					xmlreq = new ActiveXObject("Microsoft.XMLHTTP");
				} else {
					xmlreq = new XMLHttpRequest();
				}
			} catch (err) {
				alert('Error creating XMLHttpRequest');
				return;
			}

			if (!url) url = defaulturl;

			xmlreq.open("GET", url, false);
			xmlreq.send('');

			node.innerHTML = xmlreq.responseText;
		};

		return this;
	}
};

JXTK2.Key = {
	attach : function (po) {
		po.onkeydown = function (e) {
			JXTK2.Key.handleEvent(e);
		};
	},

	registerKey : function(kc, handler) {
		JXTK2.Key._handlers[kc] = handler;
	},

	handleEvent : function(e) {
		e = JXTK2.Misc.fixEvent(e);

		if (JXTK2.Key._handlers[e.key]) {
			JXTK2.Key._handlers[e.key]();
			return false;
		} else {
			return true;
		}
	},
	
	_handlers : new Array()
};

JXTK2.Misc = {
	fixEvent : function(e) {
		if (!e) e = window.event;

		e.targ = e.target;
		if (e.srcElement) e.targ = e.srcElement; // IE
		if (e.targ && e.targ.nodeType == 3) e.targ = e.targ.parentElement; // Safari

		e.key = e.keyCode;
		if (e.which) e.key = e.which;

		return e;
	},

	isArray : function(obj) {
		return (typeof obj == 'object' && typeof obj['__(JSONArray)__'] == 'boolean');
	}
};

JXTK2.String = {
	getString : function(str) {
		if (JXTK2.String._StringTable[str]) return JXTK2.String._StringTable[str];
		else return null;
	},
	registerString : function(name, value) {
		JXTK2.String._StringTable[name] = value;
	}
};

JXTK2.String._StringTable = new Array();

JXTK2.TimeCounter = function () {
	var times = new Array();
	var oldtime = new Date().getTime();

	this.mark = function() {
		var newtime = new Date().getTime();
		times.push(newtime - oldtime);
		oldtime = newtime;
	}

	this.prettyprint = function() {
		return times.join('ms, ') + "ms";
	}
};

