/* JXTK, copyright (c) 2005 Jacob Potter
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License,
   version 2.
*/

JXTK._CookieFactory = {
	createCookie : function(prefix) {
		var cook = new _JXTKCookie(prefix);
		return cook;
	},
		
	controlLockout : 0
};

_JXTKCookie.prototype = {
	getValue : function() {
		var dc = document.cookie;
		var pval = this.prefix + "=";
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
	},

	setValue : function(value) {
		var expires = new Date();
		expires.setTime(expires.getTime() + this.duration);
		document.cookie = this.prefix + "=" + value + "; expires=" + expires.toGMTString();
	},
	
	setDuration : function(duration) {
		this.duration = duration;
	},

	duration : 60*60*24*365
		// 1 year default
};

function _JXTKCookie(prefix) {
	this.prefix = prefix;
}
