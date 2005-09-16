/* JXTK, copyright (c) 2005 Jacob Potter
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License,
   version 2.
*/

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
