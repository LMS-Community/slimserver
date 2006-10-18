var url = 'status.html';

[% PROCESS html/global.js %]
[% PROCESS skin_global.js %]

function addItem(args) {
	getStatusData(args, showAdded);
}

function toggleGalleryView(artwork) {
	//var thisdoc = parent.browser;
	var thisdoc = document;
	if (thisdoc.location.pathname != '') {
		myString = new String(thisdoc.location.href);
		if (artwork) {
			setCookie( 'SlimServer-albumView', "1" );
			if (thisdoc.location.href.indexOf('start') == -1) {
				thisdoc.location=thisdoc.location.href+"&artwork=1";
			} else {
				myString = new String(thisdoc.location.href);
				var rExp = /\&start=/gi;
				thisdoc.location=myString.replace(rExp, "&artwork=1&start=");
			}
		} else {
			setCookie( 'SlimServer-albumView', "" );
			var rExp = /\&artwork=1/gi;
			thisdoc.location=myString.replace(rExp, "");
		}
	}
}

window.onload= function() {
	refreshLibraryInfo();
}

