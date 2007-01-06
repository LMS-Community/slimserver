var url = "[% statusroot %]";

function ajaxHomeCallback(theData) {
	
	var parsedData = fillDataHash(theData);
	
	if (parsedData['warn']) {
	
		//showElements(['scanWarning']);
	
		if (parsedData['progressname']) {
			showElements(['progressName']);
			refreshElement('progressName', parsedData['progressname']);
		} else {
			hideElements(['progressName']);
		}
		
		if (parsedData['progressbar']) {
			showElements(['progressBar']);
			refreshElement('progressBar', parsedData['progressbar']);
		} else {
			hideElements(['progressBar']);
		}
		
		setTimeout( "ajaxHomeRefresh()", 5 * 1000);
	} else {
		//hideElements(['scanWarning']);
		refresh();
	}
}

function ajaxHomeRefresh() {

	// add a random number to the params as IE loves to cache the heck out of 
	var args = 'ajaxRequest=1&d=' + Math.random();
	ajaxHomeUpdate(args, ajaxHomeCallback);
}


[% IF warn %]
	function doLoad(useAjax) {
		
		if (useAjax == 1) {
			setTimeout( "ajaxHomeRefresh()", 1000);
		} else {
			setTimeout( "refresh()", 300*1000);
		}
	}
		
	function refresh() {
		window.location.replace("home.html?player=[% player | uri %]");
	}
[% END %]
