var player = '[% player %]';
var url = 'playlist.html';
var intervalID = false;

[% PROCESS global.js %]

// parses the data if it has not been done already
function fillDataHash(theData) {
	var returnData = null;
	if (theData['player_id']) { 
		return theData;
	} else {
		var myData = theData.responseText;
		returnData = parseData(myData);
		return returnData;
	}
}

function refreshAll(theData) {
	inc = 0;
	var parsedData = fillDataHash(theData);
}

function refreshPlaylistElements(theData) {
	var parsedData = fillDataHash(theData);
}

window.onload= function() {
	var args = 'player='+player+'&ajaxRequest=1';
	getStatusData(args, refreshAll);
	progressUpdate()
}
