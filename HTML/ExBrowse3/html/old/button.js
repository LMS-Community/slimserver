/* JXTK2, copyright (c) 2005 Jacob Potter
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License,
   version 2.
*/

JXTK2.Button = function (element, clickhandler) {
	// Constructor
	var el;
	if (typeof element == "string") {
		el = document.getElementById(element);
	} else {
		el = element;
	}

	if (!el) return false;
	var handlers = { "click" : [ clickhandler ] };
	var self = this;

	var activeClass = "active", inactiveClass = "", controlLockout, state;

	el.onclick = function() { self.doPress(); }


	// Methods
	this.addClickHandler = function (handler) {
		handlers.click.push(handler);
	};

	this.setActiveState = function (activeclass, inactiveclass) {
		activeClass = activeclass;
		inactiveClass = inactiveclass;
		self.setState(false);
	};

	this.doPress = function () {
		if (controlLockout || JXTK2.Button.controlLockout) return; // XXX FIXME shouldn't have to say "JXTK2.Button" there
		for (var i = 0; i < handlers.click.length; i++) {
			handlers.click[i](self);
		}
	};

	this.getState = function () {
		return state;
	};

	this.setState = function (newstate) {
		if (activeClass) {
			state = newstate;
			if (newstate) el.className = activeClass;
			else el.className = inactiveClass;
		}
	};

	this.useKey = function (keycode) {
		JXTK2.Key.registerKey(keycode, function() { self.doPress(); });
	};
};


JXTK2.ButtonBar = function (elementid) {
	// Constructor
	var el = document.getElementById(elementid);
	var buttons = [];
	var value;


	// Methods
	this.addClickHandler = function (handler) {
		for (var i = 0; i < buttons.length; i++) {
			buttons[i].addClickHandler(handler);
		}
	};

	this.populate = function (type, num, src, heightbase, heightinc) {
		for (var i = 0; i < num; i++) {
			var theEl = document.createElement(type);
			theEl.src = src;
			if (heightbase) theEl.style.height = (heightinc*i + heightbase) + "px";
			theEl.index = i;

			this.parent.appendChild(theEl);

			var button = new JXTK.Button(theEl);
			button.allowActiveState("active", "");
			buttons.push(button);
		}
	};

	this.setValue = function (newValue) {
		for (i = 0; i < buttons.length; i++) {
			buttons[i].setState(i <= newValue);
		}
		value = newValue;
	};

	this.getValue = function () {
		return value;
	};
};
