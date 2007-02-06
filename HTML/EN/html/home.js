function ajaxHomeCallback(theData) {
	
	var parsedData = fillDataHash(theData);
	
	if (parsedData['warn']) {
	
		if ($('libraryInfo')) hideElements(['libraryInfo']);
		if ($('scanWarning')) showElements(['scanWarning'],'inline');
		
		var elements = ['progressName', 'progressBar', 'progressDone', 'progressTotal'];
		
		for (var i=0; i < elements.length; i++) {
		
			if (parsedData[elements[i].toLowerCase()]) {
				if ($(elements[i])) {
					showElements([elements[i]],'inline');
					refreshElement(elements[i], parsedData[elements[i].toLowerCase()]);
				}
			} else {
				if ($(elements[i])) hideElements([elements[i]]);
			}
		}
		
		var elems = $('scanWarning').getElementsByTagName("span");
		
		for (var i=0; i < elems.length; i++) {
			if (elems[i].className == 'progress') {
				if (parsedData['progresstotal']) {
					elems[i].style.display = 'inline';
				} else {
					elems[i].style.display = 'none';
				}
			}
		}
		
		setTimeout( "ajaxHomeRefresh()", 5 * 1000);
	} else {
	
		if ($('scanWarning'))  hideElements(['scanWarning']);
		if ($('progressName')) hideElements(['progressName']);
		if ($('progressBar'))  hideElements(['progressBar']);
		
		if ($('libraryInfo'))  showElements(['libraryInfo'],'inline');
		
		var elements = ['songcount', 'albumcount', 'artistcount'];
		
		for (var i=0; i < elements.length; i++) {
			if (parsedData[elements[i]]) {
				refreshElement(elements[i], parsedData[elements[i]]);
			} 
		}
		
	}
}

function ajaxHomeRefresh() {

	// add a random number to the params as IE loves to cache the heck out of 
	var args = 'ajaxRequest=1&d=' + Math.random();
	ajaxRequest('home.html', args, ajaxHomeCallback);
}

function doLoad(useAjax) {
	
	if (useAjax == 1) {
		setTimeout( "ajaxHomeRefresh()", 1000);
	}
}

