// +----------------------------------------------------------------------+
// | Copyright (c) 2004 Bitflux GmbH                                      |
// +----------------------------------------------------------------------+
// | Licensed under the Apache License, Version 2.0 (the "License");      |
// | you may not use this file except in compliance with the License.     |
// | You may obtain a copy of the License at                              |
// | http://www.apache.org/licenses/LICENSE-2.0                           |
// | Unless required by applicable law or agreed to in writing, software  |
// | distributed under the License is distributed on an "AS IS" BASIS,    |
// | WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or      |
// | implied. See the License for the specific language governing         |
// | permissions and limitations under the License.                       |
// +----------------------------------------------------------------------+
// | Author: Bitflux GmbH <devel@bitflux.ch>                              |
// +----------------------------------------------------------------------+

var liveSearchReq = false;
var t = null;
var liveSearchLast = "";
	
var isIE = false;
// on !IE we only have to initialize it once
if (window.XMLHttpRequest) {
	liveSearchReq = new XMLHttpRequest();
}

function getElementDimensions(elemID) {

	var base = document.getElementById(elemID);
	var offsetTrail = base;
	var offsetLeft = 0;
	var offsetTop = 0;

	while (offsetTrail) {
		offsetLeft += offsetTrail.offsetLeft;
		offsetTop += offsetTrail.offsetTop;
		offsetTrail = offsetTrail.offsetParent;
	}

	if (navigator.userAgent.indexOf("Mac") != -1 && typeof document.body.leftMargin != "undefined") {
		offsetLeft += document.body.leftMargin;
		offsetTop += document.body.topMargin;
	}

	return {left:offsetLeft, top:offsetTop, 
		width:base.offsetWidth, height: base.offsetHeight,
		bottom: offsetTop + base.offsetHeight, 
		right : offsetLeft + base.offsetWidth};
}

function liveSearchInit() {

	searchInput = document.getElementById('livesearch');

	if (searchInput == null || searchInput == undefined) {
		return;
	}

	if (navigator.userAgent.indexOf("Safari") > 0) {
		searchInput.addEventListener("keydown",liveSearchKeyPress,false);
		searchInput.addEventListener("focus",liveSearchDoSearch,false);
//		searchInput.addEventListener("blur",liveSearchHide,false);
	} else if (navigator.product == "Gecko") {
		
		searchInput.addEventListener("keypress",liveSearchKeyPress,false);
		searchInput.addEventListener("blur",liveSearchHideDelayed,false);
		
	} else {
		searchInput.attachEvent('onkeydown',liveSearchKeyPress);
//		searchInput.attachEvent("onblur",liveSearchHide,false);
		isIE = true;
	}
	
	searchInput.setAttribute("autocomplete","off");

	var pos = getElementDimensions('livesearch');	
	result = document.getElementById('LSResult');
	result.style.position="absolute";
	result.style.top = pos.bottom + "px";
	result.style.left = pos.left + "px";	
	result.style.width = pos.width + "px";
}

function liveSearchHideDelayed() {
	window.setTimeout("liveSearchHide()", 400);
}
	
function liveSearchHide() {
	document.getElementById("LSResult").style.display = "none";
	var highlight = document.getElementById("LSHighlight");

	if (highlight) {
		highlight.removeAttribute("id");
	}
}

function findNext(object, specifier) {
	var cur = object;
	try {
		while (cur != undefined) {
			cur = cur.nextSibling;
			if (specifier(cur) == true) return cur
		}
	} catch(e) {};

	return null;
}

function findPrev(object, specifier) {
	var cur = object;
	try {
		while (cur != undefined) {
			cur = cur.previousSibling;
			if (specifier(cur) == true) return cur
		}
	} catch(e) {};

	return null;
}

function liveSearchKeyPress(event) {
	
	highlight = document.getElementById("LSHighlight");

	if (event.keyCode == 40 )
	//KEY DOWN
	{
		if (!highlight) {
			highlight = document.getElementById("LSShadow").getElementsByTagName('li')[0];
		} else {
			highlight.removeAttribute("id");
			highlight = findNext(highlight, function (o) {return o.nodeName.toLowerCase()=='li';});
		}

		if (highlight) {
			highlight.setAttribute("id","LSHighlight");
		} 

		if (!isIE) { event.preventDefault(); }
	} 
	//KEY UP
	else if (event.keyCode == 38 ) {

		if (!highlight) {
			var set = document.getElementById("LSShadow").getElementsByTagName('li');
			highlight = set[set.length];
		} else {
			highlight.removeAttribute("id");
			highlight = findPrev(highlight, function (o) {return o.nodeName.toLowerCase()=='li';});
		}

		if (highlight) {
			highlight.setAttribute("id","LSHighlight");
		}

		if (!isIE) { event.preventDefault(); }
	} 
	//ESC
	else if (event.keyCode == 27) {

		if (highlight) {
			highlight.removeAttribute("id");
		}

		document.getElementById("LSResult").style.display = "none";
	} 
}

function liveSearchStart() {
	if (t) {
		window.clearTimeout(t);
	}

	t = window.setTimeout("liveSearchDoSearch()", 250);
}

function liveSearchDoSearch() {

	if (typeof liveSearchParams == "undefined") {
		liveSearchParams = "";
	}

	value = document.forms.searchForm.query.value;

	if (liveSearchLast != value) {

		if (liveSearchReq && liveSearchReq.readyState < 3) {
			liveSearchReq.abort();
		}

		if (value == "") {
			liveSearchHide();
			return false;
		}

		if (window.XMLHttpRequest) {
			// branch for IE/Windows ActiveX version
		} else if (window.ActiveXObject) {
			liveSearchReq = new ActiveXObject("Microsoft.XMLHTTP");
		}

		liveSearchReq.onreadystatechange= liveSearchProcessReqChange;
		liveSearchReq.open("GET", "/livesearch.xml?query=" + value);
		liveSearchLast = value;
		liveSearchReq.send(null);
	}
}

function liveSearchProcessReqChange() {
	
	if (liveSearchReq.readyState == 4) {
		var  res = document.getElementById("LSResult");

		if (liveSearchReq.status > 299 || liveSearchReq.status < 200  ||
			liveSearchReq.responseText.length < 10) return;	

		res.style.display = "block";
		//var  sh = document.getElementById("LSShadow");
		//sh.innerHTML = liveSearchReq.responseText;
		res.innerHTML = liveSearchReq.responseText;
	}
}

function liveSearchSubmit() {
	var highlight = document.getElementById("LSHighlight");

	if (highlight) {
		target = highlight.getElementsByTagName('a')[0];
		window.location = liveSearchRoot + liveSearchRootSubDir + target;
		return false;
	} else {
		return true;
	}
}
