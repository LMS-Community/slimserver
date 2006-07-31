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

window.onload= function() {
	refreshLibraryInfo();
}
