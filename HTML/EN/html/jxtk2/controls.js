/* JXTK2, copyright (c) 2005 Jacob Potter */

JXTK2.Button = function (element, clickhandler) {
	// Constructor
	var el;
	if (typeof element == "string") {
		el = document.getElementById(element);
	} else {
		el = element;
	}

	if (!el) {
		return null;
	}
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
			if (handlers.click[i]) handlers.click[i](self);
		}
	};

	this.getEl = function () {
		return el;
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

	return this;
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

			el.appendChild(theEl);

			var button = new JXTK2.Button(theEl);
			button.index = i;
			buttons.push(button);
		}
	};

	this.setValue = function (newValue) {
		for (var i = 0; i < buttons.length; i++) {
			buttons[i].setState(i <= newValue);
		}
		value = newValue;
	};

	this.getValue = function () {
		return value;
	};
};

JXTK2.ComboList = function (element, buttonsDiv, rowInitFunc) {
	// Constructor
	var el;
	if (typeof element == "string") {
		el = document.getElementById(element);
	} else {
		el = element;
	}

	if (!el) return false;

	el.clist = this;
	var list = [ ];
	var self = this;
	var selectedIndex = -1;
	var scrollBase = null;
	
	while (el.firstChild) el.removeChild(el.firstChild);

	// Methods
	this.update = function (newlist) {
		var baselength;

		if (list.length < newlist.length) baselength = list.length;
		else baselength = newlist.length;

		for (var i = 0; i < baselength; i++) {
			if (el.childNodes[i].childNodes[2].innerHTML != newlist[i].title) {
				el.childNodes[i].childNodes[2].innerHTML = newlist[i].title;
			}

			var newNum = i + 1 + "";
			if (el.childNodes[i].childNodes[1].innerHTML != newNum) {
				el.childNodes[i].childNodes[1].innerHTML = newNum;
			}
		}

		if (list.length < newlist.length) {
			for (var i = baselength; i < newlist.length; i++) {
				var theRow = document.createElement('li');

				theRow.index = i;
				theRow.className = (i % 2) ? "odd" : "even";

				var indexD = document.createElement('div');
				indexD.innerHTML = i + 1;
				indexD.className = "comboindex";

				var titleD = document.createElement('div');
				titleD.innerHTML = newlist[i].title;
				titleD.className = "combolisting";

				var buttonsD = buttonsDiv.cloneNode(true);

				theRow.appendChild(buttonsD);
				theRow.appendChild(indexD);
				theRow.appendChild(titleD);

				el.appendChild(theRow);

				rowInitFunc(self, theRow);
			}
		}

		if (newlist.length < list.length) {
			var extras = list.length - baselength;
			for (var i = 0; i < extras; i++) {
				el.removeChild(el.childNodes[baselength]);
			}
		}

		self.highlightSelected();

		list = newlist;
	};

	this.highlightSelected = function() {
		for (var i = 0; i < list.length; i++) {
			if (el.childNodes[i]) {
				el.childNodes[i].className = (i % 2) ? "odd" : "even";
				el.childNodes[i].isSelected = 0;
			}
		}
		if (selectedIndex >= 0 && el.childNodes[selectedIndex]) {
			el.childNodes[selectedIndex].className += " active";
			el.childNodes[selectedIndex].isSelected = 1;
		}
	};

	this.selectIndex = function(index) {
		selectedIndex = index;
		self.highlightSelected();
	};

	this.deleteRow = function(index) {
		if (index < 0 || index >= list.length) return;

		el.removeChild(el.childNodes[index]);
		list.splice(index, 1);

		// Renumber the elements after the removed row
		for (var i = index; i < list.length; i++) {
			var cn = el.childNodes[i];
			cn.childNodes[1].innerHTML = i + 1;
			cn.index = i;
			cn.className = (i % 2) ? "odd" : "even";
			if (cn.isSelected) cn.className += " active";
		}
	};

	this.getEl = function () {
		return el;
	};

	this.makeRowDraggable = function (item, handle, dragEndHandler) {
		var group = ToolMan.drag().createSimpleGroup(item, handle);
		group.clist = this;
		group.dragEndHandler = dragEndHandler;

		group.register('dragstart', function (dragEvent) {
			var coordinates = ToolMan.coordinates();
			dragEvent.group.movecount = 0;
			dragEvent.group.element.parentNode.isDragging = 1;

			var items = dragEvent.group.clist.getEl().getElementsByTagName("li");
			dragEvent.group.min = coordinates.topLeftOffset(items[0]);
			dragEvent.group.max = coordinates.topLeftOffset(items[items.length - 1]);

			return false;
		});

		group.register('dragmove', function (dragEvent) {
			var coordinates = ToolMan.coordinates();
			var oplTop = 0;

			var item = dragEvent.group.element;
			var xmouse = dragEvent.transformedMouseOffset;
			var moveTo = null;

			if (item.parentNode.clist.scrollBase) {
				oplTop = item.parentNode.clist.scrollBase.scrollTop;
			}

			var previous = ToolMan.helpers().previousItem(item, item.nodeName);
			var next = ToolMan.helpers().nextItem(item, item.nodeName);

			if (previous && xmouse.y <= (coordinates.bottomRightOffset(previous).y - oplTop)) {
				while (previous != null) {
					var bottomRight = coordinates.bottomRightOffset(previous);
					if (xmouse.y <= (bottomRight.y - oplTop)) {
						moveTo = previous;
						dragEvent.group.movecount--;
						previous = ToolMan.helpers().previousItem(previous, item.nodeName);
					} else {
						previous = null;
					}
				}
				if (moveTo != null) {
					ToolMan.helpers().moveBefore(item, moveTo);
					return;
				}
			}
	
			if (next && xmouse.y >= (coordinates.topLeftOffset(next).y - oplTop)) {
				while (next != null) {
					var topLeft = coordinates.topLeftOffset(next);
					if ((topLeft.y - oplTop) <= xmouse.y) {
						moveTo = next;
						dragEvent.group.movecount++;
						next = ToolMan.helpers().nextItem(next, item.nodeName);
					} else {
						next = null;
					}
				}
				if (moveTo != null) {
					ToolMan.helpers().moveBefore(item, ToolMan.helpers().nextItem(moveTo, item.nodeName));
					return;
				}
			}

			return false;
		});

		group.register('dragend', function (dragEvent) {
			ToolMan.coordinates().create(0, 0).reposition(dragEvent.group.element);
			var group = dragEvent.group;
			group.element.parentNode.isDragging = 0;

			var elementparent = group.element.parentNode;

			if ((group.movecount >= 1) || (group.movecount <= -1)) {
				group.dragEndHandler(group.movecount, group.element.index);
			}

			for (var i = 0; i < elementparent.childNodes.length; i++) {
				var cn = elementparent.childNodes[i];
				cn.childNodes[1].innerHTML = i + 1;
				cn.index = i;
				cn.className = (i % 2) ? "odd" : "even";
				if (cn.isSelected) cn.className += " active";
			}

			return false;
		});

		group.addTransform(function(coordinate, dragEvent) {
			return coordinate.constrainTo(dragEvent.group.min, dragEvent.group.max);
		});

		group.verticalOnly();
	};

	this.setScrollBase = function(el) {
		this.scrollBase = el;
	};
};


JXTK2.ListBox = function (element) {
	// Constructor
	var el;
	if (typeof element == "string") {
		el = document.getElementById(element);
	} else {
		el = element;
	}

	if (!el) return;

	var curList = [ ];
	var changeHandlers = [ ];
	var self = this;

	el.options.length = 0;

	el.onchange = function(event) {
		for (var i = 0; i < changeHandlers.length; i++) {
			changeHandlers[i](self);
		}
	}; 

	// Methods

	this.update = function (newlist) {
		var baselength;

		if (curList.length < newlist.length) baselength = curList.length;
		else baselength = newlist.length;

		for (var i = 0; i < baselength; i++) {
			el.options[i].text = newlist[i].name;
			el.options[i].value = newlist[i].value;
		}

		if (curList.length < newlist.length) {
			for (var i = baselength; i < newlist.length; i++) {
				var newopt = new Option (newlist[i].name, newlist[i].value);
				el.options[el.options.length] = newopt;
			}
		}

		if (newlist.length < curList.length) {
			el.options.length = newlist.length;
		}

		curList = newlist;
	};

	this.addHandler = function (handler) {
		changeHandlers.push(handler);
	};

	this.getValue = function() {
		return el.value;
	};

	this.getEl = function () {
		return el;
	};

	this.selectIndex = function (index) {
		el.selectedIndex = index;
	};
};

JXTK2.Textbox = function(elname) {
	// Constructor
	var el = document.getElementById(elname);
	if (!el) return false;
	var text;


	// Methods
	this.setText = function (newtext) {
		if (newtext != text) {
			text = newtext;
			el.innerHTML = newtext;
		}
	};
};
