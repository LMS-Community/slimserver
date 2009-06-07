var url = 'status.html';

[% PROCESS skin_global.js %]

function changeThumbSize (action, albumArtDOMId, albumArtId) {
	if (action == 'shrink' ) {
		if (thumbSize == 50) {
			return;
		}
		thumbSize = thumbSize - 50;
	} else if (action == 'enlarge') {
		if (thumbSize == 700) {
			return;
		}
		thumbSize = thumbSize + 50;
	}
	thumbHrefTemplate = '/music/COVER/cover_'+thumbSize+'x'+thumbSize+'_p.png';
	var thumbHref = thumbHrefTemplate.replace('COVER', albumArtId);
	if ($(albumArtDOMId)) {
		$(albumArtDOMId).src = thumbHref;
	}
	setCookie( 'Squeezebox-thumbSize', thumbSize );
}

function addItem(args) {
	getStatusData(args, showAdded);
}

window.onload= function() {
	refreshLibraryInfo();
}

