/* JXTK2, copyright (c) 2005 Jacob Potter
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License,
   version 2.
*/

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

	// Public Functions

	this.toString = function () {
		return "[object JXTK2.JSONRPC.Proxy " + proxyurl + " ]";
	};

	this.call = function (methodName, methodParams, onResp) {
		//alert("calling " + methodName + "(" + methodParams.join(", ") + ") via " + proxyurl);

		if (onResp == true) {
			// "Fork" into background
			setTimeout(function() { self.call(methodName, methodParams); }, 0);
			return;
		}

		var json = JSON.stringify({ method : methodName, params : methodParams });

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

		xmlreq.open("POST", proxyurl, isFunc);
		if (isFunc) {
			xmlreq.onreadystatechange = function () { handleResp(xmlreq, onResp); };
		}

		xmlreq.send(json);

		if (!isFunc) return handleResp(xmlreq, onResp);
	}

	// Private Functions

	function handleResp(xmlreq, onResp) {
		if (xmlreq.readyState != 4) return;

		if (xmlreq.status != 200) {

			// TODO: error handling
			alert("Transport Error " + xmlreq.status);
			return;

		}

		var respobj;
		eval('respobj=' + xmlreq.responseText);

		if (respobj.error) {
			alert("RPC Fault: \"" + respobj.error + "\"");
		}

		if (typeof onResp == "function") {
			onResp(respobj);
		} else {
			return respobj;
		}
	}

	// Constructor Code

	var self = this;
	var proxyurl = url;
}
