var url = "[% statusroot %]";

function ajaxHomeCallback(theData) {
	
	var parsedData = fillDataHash(theData);
	
	if (parsedData['warn']) {
	
		if ($('libraryInfo')) hideElements(['libraryInfo']);
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
		
		var elems = $('scanWarning').getElementsByTagName("span");
		
		for (var i=0; i < elems.length; i++) {
			if (elems[i].className == 'progress') {
				if (parsedData['progressname']) {
					elems[i].style.display = 'inline';
				} else {
					elems[i].style.display = 'none';
				}
			}
		}
		
		setTimeout( "ajaxHomeRefresh()", 5 * 1000);
	} else {
	
		refresh();
		
		var elements = ['songcount', 'albumcount', 'artistcount'];
		
		for (var i=0; i < elements.length; i++) {
			if (parsedData[data[i]]) {
				refreshElement(elements[i], parsedData[data[i]]);
			} 
		}
		
		if ($('scanWarning')) hideElements(['scanWarning']);
		if ($('libraryInfo')) showElements(['libraryInfo'],'inline');
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
