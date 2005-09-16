/* JXTK2, copyright (c) 2005 Jacob Potter
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License,
   version 2.
*/

var JXTK2 = {
	version : function() {
		return '2.0.0';
	}
}

JXTK2.Misc = {
	fixEvent : function(e) {
		if (!e) e = window.event;

		e.targ = e.target;
		if (e.srcElement) e.targ = e.srcElement; // IE
		if (e.targ && e.targ.nodeType == 3) e.targ = e.targ.parentElement; // Safari

		e.key = e.keyCode;
		if (e.which) e.key = e.which;

		return e;
	}
};

JXTK2.Key = {
	attach : function (prop) {
		var key = this;
		eval(prop + "=function(e){key.handleEvent(e);}");
	},

	registerKey : function(kc, handler) {
		this._handlers[kc] = handler;
	},

	handleEvent : function(e) {
		e = JXTK.Misc().fixEvent(e);

		if (this._handlers[e.key]) {
			this._handlers[e.key]();
			return false;
		} else {
			return true;
		}
	},
	
	_handlers : new Array()
};

JXTK2.String = {
	getString : function(str) {
		if (JXTK.String._StringTable[str]) return JXTK._Strings._StringTable[str];
		else return null;
	},
	registerString : function(name, value) {
		JXTK.String._StringTable[name] = value;
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
}
