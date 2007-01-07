var url = "[% statusroot %]";

function ajaxProgressCallback(theData) {
	
	var parsedData = fillDataHash(theData);
	
	var elems = ['Name', 'Done', 'Total', 'Active', 'Time', 'Bar', 'Info'];
	
	for (var i=0; i <= 10; i++) {
	
		for (var j=0; j < elems.length; j++) {
		
			if (parsedData['Name'+i]) {
				if ($('progress'+i)) showElements(['progress'+i],'inline');
				refreshElement(elems[j]+i, parsedData[elems[j]+i]);
			} else {
				if ($('progress'+i)) hideElements(['progress'+i]);
			}

			if (parsedData[elems[j]+i]) {
				refreshElement(elems[j]+i, parsedData[elems[j]+i]);
			}
		}
	}
	
	if (parsedData['message']) {
		refreshElement('message',parsedData['message']);
	} else {
		setTimeout( "ajaxProgressRefresh()", 5000);
	}
}

function ajaxProgressRefresh() {

	// add a random number to the params as IE loves to cache the heck out of 
	var args = 'type=[% type %]&barlen=[% barlen %]&ajaxRequest=1&player=[% player | uri %]&d=' + Math.random();
	ajaxProgressUpdate(args, ajaxProgressCallback);
}

function ajaxProgressUpdate(params, action) {
	var requesttype = 'post';

	if (window.XMLHttpRequest) {
		requesttype = 'get';
	}

	var myAjax = new Ajax.Request(
	'progress.html',
	{
		method: requesttype,
		postBody: params,
		parameters: params,
		onComplete: action,
		requestHeaders:['Referer', document.location.href]
	});
}
