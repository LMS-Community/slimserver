/* JXTK, copyright (c) 2005 Jacob Potter
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License,
   version 2.

   The _Drag* and makeRowDraggable functions within this file
   are based on Tim Taylor's Tool-Man library, under the MIT license;
   details are at the head of the file "toolmanx/core.js".
*/

JXTK._ComboListFactory = {
	createComboList : function(parentid, buttonsDiv, rowInitFunc) {
		var parent = document.getElementById(parentid);
		if (!parent) return;

		var clist = new _JXTKComboList(parent, buttonsDiv, rowInitFunc);
		return clist;
	},

	_DragStart : function(dragEvent) {
		var coordinates = ToolMan.coordinates();
		dragEvent.group.movecount = 0;
		dragEvent.group.element.parentNode.isDragging = 1;

		var items = dragEvent.group.clist.parent.getElementsByTagName("li");
		dragEvent.group.min = coordinates.topLeftOffset(items[0]);
		dragEvent.group.max = coordinates.topLeftOffset(items[items.length - 1]);
	},

	_DragMove : function(dragEvent) {
		var helpers = ToolMan.helpers();
		var coordinates = ToolMan.coordinates();
		var oplTop = 0;

		var item = dragEvent.group.element;
		var xmouse = dragEvent.transformedMouseOffset;
		var moveTo = null;

		if (item.parentNode.clist.scrollBase) {
			oplTop = item.parentNode.clist.scrollBase.scrollTop;
		}

		var previous = helpers.previousItem(item, item.nodeName);
		while (previous != null) {
			var bottomRight = coordinates.bottomRightOffset(previous);
			if (xmouse.y <= (bottomRight.y - oplTop) && xmouse.x <= bottomRight.x) {
				moveTo = previous;
				dragEvent.group.movecount--;
			}
			previous = helpers.previousItem(previous, item.nodeName);
		}
		if (moveTo != null) {
			helpers.moveBefore(item, moveTo);
			return;
		}

		var next = helpers.nextItem(item, item.nodeName);
		while (next != null) {
			var topLeft = coordinates.topLeftOffset(next);
			if ((topLeft.y - oplTop) <= xmouse.y && topLeft.x <= xmouse.x) {
				moveTo = next;
				dragEvent.group.movecount++;
			}
			next = helpers.nextItem(next, item.nodeName);
		}
		if (moveTo != null) {
			helpers.moveBefore(item, helpers.nextItem(moveTo, item.nodeName));
			return;
		}
	},

	_DragEnd : function(dragEvent) {
		ToolMan.coordinates().create(0, 0).reposition(dragEvent.group.element);
		var group = dragEvent.group;
		group.element.parentNode.isDragging = 0;

		var elementparent = group.element.parentNode;

		if ((group.movecount >= 1) || (group.movecount <= -1)) {
			group.dragEndHandler(group.movecount, group.element.index);
		}

		for (i = 0; i < elementparent.childNodes.length; i++) {
			elementparent.childNodes[i].index = i;
			elementparent.childNodes[i].childNodes[1].innerHTML = i + 1;
		}
	},

	controlLockout : 0
};

_JXTKComboList.prototype = {
	populate : function () {

	},

	update : function (newlist) {
		var listbox = this.parent;
		var baselength;

		if (this.list.length < newlist.length) baselength = this.list.length;
		else baselength = newlist.length;

		for (i = 0; i < baselength; i++) {
			if (listbox.childNodes[i].childNodes[2].innerHTML != newlist[i].title) {
				listbox.childNodes[i].childNodes[2].innerHTML = newlist[i].title;
			}

			newNum = i + 1 + "";
			if (listbox.childNodes[i].childNodes[1].innerHTML != newNum) {
				listbox.childNodes[i].childNodes[1].innerHTML = newNum;
			}
		}

		if (this.list.length < newlist.length) {
			for (i = baselength; i < newlist.length; i++) {
				var theRow = document.createElement('li');

				theRow.index = i;

				var indexD = document.createElement('div');
				indexD.innerHTML = i + 1;
				indexD.className = "playlistindex";

				var titleD = document.createElement('div');
				titleD.innerHTML = newlist[i].title;
				titleD.className = "playlistlisting";

				var buttonsD = this.buttonsDiv.cloneNode(true);

				theRow.appendChild(buttonsD);
				theRow.appendChild(indexD);
				theRow.appendChild(titleD);

				listbox.appendChild(theRow);

				this.rowInitFunc(theRow);
			}
		}

		if (newlist.length < this.list.length) {
			extras = this.list.length - baselength;
			for (i = 0; i < extras; i++) {
				listbox.removeChild(listbox.childNodes[baselength]);
			}
		}

		this.highlightSelected();

		this.list = newlist;
	},

	highlightSelected : function() {
		for (i = 0; i < this.list.length; i++) {
			if (this.parent.childNodes[i]) {
				this.parent.childNodes[i].className = "";
			}
		}
		if (this.selectedIndex >= 0 && this.parent.childNodes[this.selectedIndex]) {
			this.parent.childNodes[this.selectedIndex].className = "active";
		}
	},

	selectIndex : function(index) {
		this.selectedIndex = index;
		this.highlightSelected();
	},

	deleteRow : function(index) {
		if (index < 0 || index >= this.list.length) return;

		this.parent.removeChild(this.parent.childNodes[index]);
		this.list.splice(index, 1);

		// Renumber the elements after the removed row
		for (i = index; i < this.list.length; i++) {
			this.parent.childNodes[i].childNodes[1].innerHTML = i + 1;
			this.parent.childNodes[i].index = i;
		}
	},

	makeRowDraggable : function (item, handle, dragEndHandler) {
		listbox = this.parent;

		var group = ToolMan.drag().createSimpleGroup(item, handle);
		group.clist = this;
		group.dragEndHandler = dragEndHandler;

		group.register('dragstart', JXTK._ComboListFactory._DragStart);
		group.register('dragmove', JXTK._ComboListFactory._DragMove);
		group.register('dragend', JXTK._ComboListFactory._DragEnd);

		group.addTransform(function(coordinate, dragEvent) {
			return coordinate.constrainTo(dragEvent.group.min, dragEvent.group.max);
		});

		group.verticalOnly();
	},

	setScrollBase : function(el) {
		this.scrollBase = el;
	},

	selectedIndex : -1,
	scrollBase : null
};

function _JXTKComboList(parent, buttonsDiv, rowInitFunc) {
	this.parent = parent;
	parent.clist = this;
	this.list = new Array();
	this.buttonsDiv = buttonsDiv;
	this.rowInitFunc = rowInitFunc;

	while (parent.firstChild) parent.removeChild(parent.firstChild);
}
