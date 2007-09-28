var thumbSize = [% IF thumbSize %][% thumbSize %][% ELSE %]250[% END %];
var thumbHrefTemplate = '/music/COVER/thumb_'+thumbSize+'x'+thumbSize+'_c_000000.jpg';

[% PROCESS html/global.js %]

function chooseAlbumOrderBy(value, option, artwork)
{
	if (!artwork && artwork != 0) {
		artwork = 1;
	}
        var url = '[% webroot %]browsedb.html?hierarchy=[% hierarchy %]&level=[% level %][% attributes %][% IF artwork OR artwork == '0' %]&artwork='+artwork+'[% END %]&player=[% playerURI %]'; 
        if (option) {
                url = url + '&orderBy=' + option;
        }
        setCookie( 'SqueezeCenter-orderBy', option );
        window.location = url;
}

function setCookie(name, value) {
        var expires = new Date();
        expires.setTime(expires.getTime() + 1000*60*60*24*365);
        document.cookie =
                name + "=" + escape(value) +
                ((expires == null) ? "" : ("; expires=" + expires.toGMTString()));
}

// enters message sent to OSD div (typically still needs to be made visible with a different function)
function changeOSD(message) {
	if ($('OSD')) {
		$('OSD').innerHTML = message;
	}
}

// send a message and number of milliseconds duration to the OSD div
function showVolumeOSD(message, duration) {
	var msDuration = parseInt(duration, 10);

	if ($('volumeOSD')) {
		$('volumeOSD').innerHTML = '';
		$('volumeOSD').style.display = 'block';
		$('volumeOSD').innerHTML = message;
	}

	var intervalID = setTimeout(hideVolumeOSD, msDuration);
}

function hideVolumeOSD() {

	if ($('volumeOSD')) {
		$('volumeOSD').style.display = 'none';
	}

}

function showAdded() {

	if ($('OSD')) {
		$('OSD').style.display = 'block';
	}

	var intervalID = setTimeout("hideAdded()", 2000);
}

function hideAdded() {

	if ($('OSD')) {
		$('OSD').style.display = 'none';
	}
}

function resize(src,width) {
	if (!width) {
		// special case for IE (argh)
		if (document.all) {
			width = document.body.clientWidth*0.5;
		} else if (document.getElementById) { //else if NS6+ 
			width = window.innerWidth*0.5;
		}
	}
	if (src.width > width ) {
		src.width = width;
	}
}

function toggleGalleryView(artwork) {
	var thisdoc = document;
	if (thisdoc.location.pathname != '') {
		myString = new String(thisdoc.location.href);
		if (artwork) {
			setCookie( 'SqueezeCenter-albumView', "1" );
			if (thisdoc.location.href.indexOf('start') == -1) {
				thisdoc.location=thisdoc.location.href+"&artwork=1";
			} else {
				myString = new String(thisdoc.location.href);
				var rExp = /\&start=/gi;
				thisdoc.location=myString.replace(rExp, "&artwork=1&start=");
			}
		} else {
			setCookie( 'SqueezeCenter-albumView', "" );
			var rExp = /\&artwork=1/gi;
			thisdoc.location=myString.replace(rExp, "");
		}
	}
}

