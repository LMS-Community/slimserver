/* JXTK, copyright (c) 2005 Jacob Potter
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License,
   version 2.
*/

JXTK._TextboxFactory = {
	createTextbox : function(elname) {
		el = document.getElementById(elname);
		if (!el) return false;

		var textbox = new _JXTKTextbox(this, el);
		return textbox;
	}
}

_JXTKTextbox.prototype = {
	setText : function (newtext) {
		if (newtext != this._text) {
			this._text = newtext;
			this.el.innerHTML = newtext;
		}
	},

	useXMLValue : function (backend, xmlfunc) {
		var textbox = this;
		backend.addHandler(function(resp) {
			textbox.setText(xmlfunc(resp));
		});
	},

	_text : null
};

function _JXTKTextbox(factory, el) {
	this.factory = factory;
	this.el = el;
}
