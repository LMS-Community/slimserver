// global.js
// these functions should be generic across all pages that use ajax requests
// the url var needs to be initialized in the page specific javascript file
// and this script is called by a PROCESS global.js

function ajaxRequest(thisurl, params, action) {
	var requesttype = 'post';

	if (typeof params == 'object')
		params = JSON.stringify(params);

	else if (!Prototype.Browser.IE) {
		requesttype = 'get';
	}

	if (!action) {
		action = refreshNothing;
	}

	var myAjax = new Ajax.Request(
	thisurl,
	{
		method: requesttype,
		postBody: params,
		parameters: params,
		onComplete: action,
		requestHeaders:['Referer', document.location.href]
	});
}

// request and update with new list html, requires a 'mainbody' div defined in the document
// templates should use the ajaxUpdate param to block headers and footers.
function ajaxUpdate(url, params) {
	new Ajax.Updater( { success: 'mainbody' }, url, {
		method: 'post',
		postBody: params + '&ajaxUpdate=1&player=' + player,
		evalScripts: true,
		asynchronous: true,
		onFailure: function(t) {
			alert('Error -- ' + t.responseText);
		}
	} );
}

function toggleFavorite(el, url, title, icon) {
	new Ajax.Updater( { success: el }, 'plugins/Favorites/favcontrol.html', {
		method: 'post',
		postBody: 'url=' + url + '&title=' + title + '&icon=' + icon,
		asynchronous: true,
		onFailure: function(t) {
			alert('Error -- ' + t.responseText);
		}
	} );
}

// Parse the raw data and return the requested hash.
// if data is already parsed, just return unprocessed.
function fillDataHash(theData) {
	var returnData = null;

	if (theData['player_id']) {
		return theData;
	} else {
		var myData = theData.responseText;
		returnData = parseData(myData);
	}

	return returnData;
}

// pass an array of div element ids to be hidden on the page
function hideElements(myAry) {

	for (var i = 0; i < myAry.length; i++) {
		var div = myAry[i];

		if ($(div)) {
		//	document.getElementById(div).style.display = "none";
			$(div).style.display = 'none';
		}
	}
}

// pass an array of div element ids to be shown on the page
function showElements(myAry,style) {
	if (!style) style = 'block';

	for (var i = 0; i < myAry.length; i++) {
		var div = myAry[i];

		if ($(div)) {
			//document.getElementByID(div).style.display = 'block';
			$(div).style.display = style;
		}
	}
}

// empty function that can be called when getStatus is called but no elements need be refreshed
function refreshNothing() {
	return true;
}

// changes the innerHTML to 'value' of an element id of 'element'
// if truncate is given, 'value' is reduced to truncate in length, plus a '...'
function refreshElement(element, value, truncate) {

	if (value.length > truncate) {
		var smaller = value.substring(0,truncate);
		value = smaller+'...';
	}

	if ($(element)) {
		$(element).innerHTML = '';
		$(element).innerHTML = value;
	}
}

// thisData is the responseText from ajaxRequest.txt
// this function parses the response into a hash object used in all update functions
function parseData(thisData) {
	var lines = thisData.split("\n");
	var returnData = new Array();

	for (i=0; i<lines.length; i++) {
		var comment = /^#/;
		var blank = /^\s*$/;
		var preTag = /<\\*pre>/;
		var commentLine = lines[i].match(comment);
		var blankLine = lines[i].match(blank);

		if (!commentLine && !blankLine && preTag) {
			var keyValue = lines[i].split('|');
			var key = keyValue[0];
			var value = keyValue[1];
			returnData[key] = value;
		}
	}

	return returnData;
}

function hideAlbumInfo() {
	new Effect.Fade('albumPopup', { duration:0.4 });
	new Effect.Fade('albumBackground', { duration:0.4 });
	new Effect.Appear('viewSelect', { duration:0.4 });
}
