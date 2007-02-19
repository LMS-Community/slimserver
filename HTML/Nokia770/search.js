function Change(Key) {		
	document.FormSong.query.value = document.FormSong.query.value+Key;
}

function Mode(typ) {
	document.FormSong.type.value=typ;
}

function Activate(mode) {
	if (mode=='Song') {
		document.ButtonSong.src="html/images/active.gif";
		document.ButtonArtist.src="html/images/inactive.gif";
		document.ButtonAlbum.src="html/images/inactive.gif";
	}

	if (mode=='Artist') {
		document.ButtonArtist.src="html/images/active.gif";
		document.ButtonSong.src="html/images/inactive.gif";
		document.ButtonAlbum.src="html/images/inactive.gif";
	}
	if (mode=='Album') {
		document.ButtonAlbum.src="html/images/active.gif";
		document.ButtonSong.src="html/images/inactive.gif";
		document.ButtonArtist.src="html/images/inactive.gif";
	}
	mode='';
	return true;
}
