/*
Copyright (c) 2005 Tim Taylor Consulting <http://tool-man.org/>

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.


Trimmed by Jacob Potter for use with JXTK
*/

var ToolMan = {
	events : function() {
		if (!ToolMan._eventsFactory) throw "ToolMan Events module isn't loaded";
		return ToolMan._eventsFactory
	},

	css : function() {
		if (!ToolMan._cssFactory) throw "ToolMan CSS module isn't loaded";
		return ToolMan._cssFactory
	},

	coordinates : function() {
		if (!ToolMan._coordinatesFactory) throw "ToolMan Coordinates module isn't loaded";
		return ToolMan._coordinatesFactory
	},

	drag : function() {
		if (!ToolMan._dragFactory) throw "ToolMan Drag module isn't loaded";
		return ToolMan._dragFactory
	},

	helpers : function() {
		return ToolMan._helpers
	}
}

ToolMan._helpers = {
	map : function(array, func) {
		for (var i = 0, n = array.length; i < n; i++) func(array[i])
	},

	nextItem : function(item, nodeName) {
		if (item == null) return
		var next = item.nextSibling
		while (next != null) {
			if (next.nodeName == nodeName) return next
			next = next.nextSibling
		}
		return null
	},

	previousItem : function(item, nodeName) {
		var previous = item.previousSibling
		while (previous != null) {
			if (previous.nodeName == nodeName) return previous
			previous = previous.previousSibling
		}
		return null
	},

	moveBefore : function(item1, item2) {
		var parent = item1.parentNode
		parent.removeChild(item1)
		parent.insertBefore(item1, item2)
	},

	moveAfter : function(item1, item2) {
		var parent = item1.parentNode
		parent.removeChild(item1)
		parent.insertBefore(item1, item2 ? item2.nextSibling : null)
	}
}

