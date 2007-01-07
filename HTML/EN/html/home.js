var url = "[% statusroot %]";

function ajaxHomeCallback(theData) {
	
	var parsedData = fillDataHash(theData);
	
	if (parsedData['warn']) {
	
		if ($('scanWarning')) showElements(['scanWarning'],'inline');
		
		var elements = ['progressName', 'progressBar', 'progressDone', 'progressTotal'];
		var data = ['progressname', 'progressbar', 'progressdone', 'progresstotal']
		
		for (var i=0; i < elements.length; i++) {
			if (parsedData[data[i]]) {
				if ($(elements[i])) showElements([elements[i]],'inline');
				refreshElement(elements[i], parsedData[data[i]]);
			} else {
				if ($(elements[i])) hideElements([elements[i]]);
			}
		}
		
		setTimeout( "ajaxHomeRefresh()", 5 * 1000);
	} else {
		
		if ($('scanWarning')) hideElements(['scanWarning']);
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
