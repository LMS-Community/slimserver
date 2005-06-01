/* JXTK, copyright (c) 2005 Jacob Potter
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License,
   version 2.
*/

JXTK._ButtonFactory = {
	createButton : function(elname) {
		el = document.getElementById(elname);
		if (!el) return false;

		var button = new _JXTKButton(this, el);
		return button;
	},

	createButtonFromTag : function(el) {
		var button = new _JXTKButton(this, el);
		return button;
	},

	createSimpleButton : function(backend, elname, xmltag, xmlvalue, clickhandler) {
		el = document.getElementById(elname);
		if (!el) return false;

		var button = new _JXTKButton(this, el);

		button.allowActiveState("active", "");
		button.useXMLSelect(backend, xmltag, xmlvalue);
		button.addClickHandler(clickhandler);

		return button;
	},
		
	controlLockout : 0
}

_JXTKButton.prototype = {
	addClickHandler : function (handler) {
		this._handlers['click'].push(handler);
	},

	useXMLSelect : function (backend, xmltag, xmlvalue) {
		var button = this;
		backend.addHandler(function(resp) {
			if (resp.getTag(xmltag) == xmlvalue) {
				button.setState(true);
			} else {
				button.setState(false);
			}
		});
	},

	allowActiveState : function (activeclass, inactiveclass) {
		this._activeClass = activeclass;
		this._inactiveClass = inactiveclass;
		this.setState(false);
	},

	getState : function () {
		return this._state;
	},

	setState : function (newstate) {
		if (this._activeClass) {
			this._state = newstate;
			if (newstate) this.el.className = this._activeClass;
			else this.el.className = this._inactiveClass;
		}
	},

	_controlLockout : 0,
	_activeClass : null,
	_inactiveClass : null,
	_state : null
};

function _JXTKButton(factory, el) {
	this.factory = factory;
	this.el = el;
	this._handlers = new Array();
	this._handlers['click'] = new Array();

	var button = this;

	el.onclick = function(e) {
		// pres butan
		e = JXTK.Misc().fixEvent(e);
		if (button._controlLockout || factory.controlLockout) return;
		var clickhandlers = button._handlers['click'];
		for (var i = 0; i < clickhandlers.length; i++) {
			clickhandlers[i](button);
		}
	}
}


JXTK._ButtonBarFactory = {
	createButtonBar : function(parentid) {
		var parent = document.getElementById(parentid);
		if (!parent) return;

		var bbar = new _JXTKButtonBar(parent);
		return bbar;
	},
		
	controlLockout : 0
};

_JXTKButtonBar.prototype = {
	addClickHandler : function (handler) {
		for (var i = 0; i < this.buttons.length; i++) {
			this.buttons[i].addClickHandler(handler);
		}
	},

	populate : function (type, num, src, heightbase, heightinc) {
		for (var i = 0; i < num; i++) {
			var theEl = document.createElement(type);
			theEl.src = src;
			if (heightbase) theEl.style.height = (heightinc*i + heightbase) + "px";
			theEl.index = i;

			this.parent.appendChild(theEl);

			var button = JXTK.Button().createButtonFromTag(theEl);
			button.allowActiveState("active", "");
			this.buttons.push(button);
		}
	},

	setValue : function (value) {
		for (i = 0; i < this.buttons.length; i++) {
			this.buttons[i].setState(i <= value);
		}
	},

	useXMLValue : function (backend, respfunc) {
		var bbar = this;
		backend.addHandler(function(resp) {
			bbar.setValue(respfunc(resp));
		});
	}
};

function _JXTKButtonBar(parent) {
	this.parent = parent;
	this.buttons = new Array();
}
