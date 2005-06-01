/* JXTK, copyright (c) 2005 Jacob Potter
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License,
   version 2.
*/

JXTK._ListBoxFactory = {
	createListBox : function(inputid) {
		var input = document.getElementById(inputid);
		if (!input) return;

		var listbox = new _JXTKListBox(input);
		return listbox;
	},
		
	controlLockout : 0
};

_JXTKListBox.prototype = {
	update : function (newlist) {
		var listbox = this.input;
		var baselength;

		if (this.list.length < newlist.length) baselength = this.list.length;
		else baselength = newlist.length;

		for (i = 0; i < baselength; i++) {
			listbox.options[i].text = newlist[i].name;
			listbox.options[i].value = newlist[i].value;
		}

		if (this.list.length < newlist.length) {
			for (i = baselength; i < newlist.length; i++) {
				var newopt = new Option (newlist[i].name, newlist[i].value);
				listbox.options[listbox.options.length] = newopt;
			}
		}

		if (newlist.length < this.list.length) {
			listbox.options.length = newlist.length;
		}

		this.list = newlist;
	},

	addHandler : function (handler) {
		this.changeHandlers.push(handler);
	},

	selectIndex : function (index) {
		this.input.selectedIndex = index;
	}
};

function _JXTKListBox(input) {
	this.input = input;
	this.list = new Array();
	this.changeHandlers = new Array();

	input.options.length = 0;

	var listbox = this;

	input.onchange = function(event) {
		for (i = 0; i < listbox.changeHandlers.length; i++) {
			listbox.changeHandlers[i](listbox);
		}
	}; 
}
