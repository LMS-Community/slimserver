var player = '[% playerURI %]';
// global.js
// these functions should be generic across all pages that use ajax requests
// the url var needs to be initialized in the page specific javascript file
// and this script is called by a PROCESS global.js

// getStatusData
// params is a list of args to send to url
// action is the function to be called after the ajaxRequest.txt file is spit back
function getStatusData(params, action) {
	var requesttype = 'post';
	if (window.XMLHttpRequest) {
		requesttype = 'get';
	}
	var myAjax = new Ajax.Request(
	url,
	{
		method: requesttype,
		postBody: params,
		parameters: params,
		onComplete: action,
		requestHeaders:['Referer', document.location.href]
	});
}

// doRefresh
// refreshes all elements on the page with ajaxRequest
// refreshAll needs to be defined in the page specific javascript file 
function doRefresh() {
        var args = 'player='+player+'&ajaxRequest=1';
        getStatusData(args, refreshAll);
}

// clears setInterval() defined by intervalID
function clearIntervalCall() {
	if (intervalID) {
		clearInterval(intervalID);
		intervalID = false;
	}
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

// changes the href attribute to 'value' of an anchor id of 'element'
function refreshHref (element, value) {
	if ($(element)) {
		document.getElementById(element).href = value;
	}
}

// changes some part of a query in an href of id 'item', finding based on 'rpl', and replacing with 'data'
function refreshHrefElement (item,data,rpl) {
	
	var myString = new String($(item).innerHTML);
	var rString = rpl + data + "&amp;player";
	var rExp= new RegExp(rpl + ".+?&amp;player","i");
	//safari hack
	if (rExp.exec(myString) == null) rExp= new RegExp(rpl + ".+?&player","i");
	$(item).innerHTML = myString.replace(rExp, rString);
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

// METHOD:  truncateAt: truncate specified tableId at specified length
function truncateAt(tableId, lastRow) {
	var tableObj, oTr;
	if ( ! $(tableId) ) { 
		return null;    
	}
	tableObj = $(tableId);
	if ( ! (oTr = tableObj.rows[lastRow]) ) {
		return null;
	}
	if (tableObj.rows.length >= lastRow) {
		var startRow = lastRow;
		for (var r=startRow; r <= tableObj.rows.length; r++ ) {
			tableObj.deleteRow(r);
		}
        }
}
