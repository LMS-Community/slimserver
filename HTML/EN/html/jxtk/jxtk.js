/* JXTK, copyright (c) 2005 Jacob Potter
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License,
   version 2.

   Portions copyright (c) 2005 Tim Taylor Consulting; see the files
   "combolist.js" and "toolmanx/core.js" for details.
*/

var JXTK = {
	Backend : function() {
		if (!JXTK._BackendFactory) {
			throw "JXTK Backend module not found";
		}
		return JXTK._BackendFactory;
	},

	Button : function() {
		if (!JXTK._ButtonFactory) {
			throw "JXTK Button module not found";
		}
		return JXTK._ButtonFactory;
	},

	ButtonBar : function() {
		if (!JXTK._ButtonBarFactory) {
			throw "JXTK ButtonBar module not found";
		}
		return JXTK._ButtonBarFactory;
	},

	ComboList : function() {
		if (!JXTK._ComboListFactory) {
			throw "JXTK ComboList module not found";
		}
		return JXTK._ComboListFactory;
	},

	Cookie : function() {
		if (!JXTK._CookieFactory) {
			throw "JXTK Cookie module not found";
		}
		return JXTK._CookieFactory;
	},

	ListBox : function() {
		if (!JXTK._ListBoxFactory) {
			throw "JXTK ListBox module not found";
		}
		return JXTK._ListBoxFactory;
	},

	Misc : function() {
		return JXTK._Misc;
	},

	Strings : function(str) {
		return JXTK._Strings;
	},

	Textbox : function() {
		if (!JXTK._TextboxFactory) {
			throw "JXTK Textbox module not found";
		}
		return JXTK._TextboxFactory;
	},

	version : function() {
		return '0.0.1';
	}
}

JXTK._Misc = {
	fixEvent : function(e) {
		if (!e) e = window.event;

		e.targ = e.target;
		if (e.srcElement) e.targ = e.srcElement; // IE
		if (e.targ.nodeType == 3) e.targ = e.targ.parentElement; // Safari
		return e;
	}
};

JXTK._Strings = {
	getString : function(str) {
		if (JXTK._Strings._StringTable[str]) return JXTK._Strings._StringTable[str];
		else return null;
	},
	registerString : function(name, value) {
		JXTK._Strings._StringTable[name] = value;
	}
};

JXTK._Strings._StringTable = new Array();
