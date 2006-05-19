var url = 'status.html';

[% PROCESS html/global.js %]

function addItem(args) {
	getStatusData(args, refreshNothing);
}

window.onload= function() {
	refreshLibraryInfo();
}
