var url = 'status.html';

[% PROCESS html/global.js %]

function addItem(args) {
	getStatusData(args, showAdded);
}

function showAdded() {
	if ($(addedToPlaylist)) {
		$(addedToPlaylist).style.display = 'block';
	}
	var intervalID = setTimeout("hideAdded()", 2000);
}

function hideAdded() {
	if ($(addedToPlaylist)) {
		$(addedToPlaylist).style.display = 'none';
	}
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

function chooseAlbumOrderBy(value, option)
{
        var url = '[% webroot %]browsedb.html?hierarchy=[% hierarchy %]&level=[% level %][% attributes %][% IF artwork %]&artwork=1[% END %]&player=[% playerURI %]'; 
        if (option) {
                url = url + '&orderBy=' + option;
        }
        setCookie( 'SlimServer-orderBy', option );
        window.location = url;
}

function setCookie(name, value) {
        var expires = new Date();
        expires.setTime(expires.getTime() + 1000*60*60*24*365);
        document.cookie =
                name + "=" + escape(value) +
                ((expires == null) ? "" : ("; expires=" + expires.toGMTString()));
}

window.onload= function() {
	refreshLibraryInfo();
}

