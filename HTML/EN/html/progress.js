const pollingInterval = 2000;

function ajaxProgressCallback(theData) {

	var parsedData = fillDataHash(theData);

	var elems = ['Name', 'Done', 'Total', 'Active', 'Time', 'Bar', 'Info'];

	for (var i=0; i <= 50; i++) {

		// only show the count if it is more than one item
		if (parsedData['Total'+i] > 1) {
			showElements(['Count'+i],'inline');
		} else {
			hideElements(['Count'+i]);
		}

		for (var j=0; j < elems.length; j++) {

			if (parsedData['Name'+i]) {
				showElements(['progress'+i],'inline');
				refreshElement(elems[j]+i, parsedData[elems[j]+i]);
			} else {
				hideElements(['progress'+i]);
			}

			if (parsedData[elems[j]+i]) {
				refreshElement(elems[j]+i, parsedData[elems[j]+i]);
			}
		}
	}

	if (parsedData['message']) {
		if (parsedData['total_time']) {
			refreshElement('message',parsedData['message']+ '<br>' + timestring + ' ' + parsedData['total_time']);
		} else {
			refreshElement('message',parsedData['message']);
		}

		hideElements(['abortscanlink']);
		setTimeout( "ajaxProgressRefresh()", pollingInterval);
	} else {
		refreshElement('message','');
		showElements(['abortscanlink']);
		setTimeout( "ajaxProgressRefresh()", pollingInterval);
	}
}

function ajaxProgressRefresh() {

	// add a random number to the params as IE loves to cache the heck out of
	var args = 'type=' + progresstype + '&barlen=' + progressbarlen + '&ajaxRequest=1&player=' + player + '&d=' + Math.random();
	ajaxProgressUpdate(args, ajaxProgressCallback);
}

function ajaxProgressUpdate(params, action) {
	var requesttype = 'post';

	if (window.XMLHttpRequest) {
		requesttype = 'get';
	}

	var myAjax = new Ajax.Request(
	webroot + 'progress.html',
	{
		method: requesttype,
		postBody: params,
		parameters: params,
		onComplete: action,
		requestHeaders:['Referer', document.location.href]
	});
}
