function to_currentsong() {
	if (window.location.hash == '') {
		window.location.hash = 'currentsong';
	}
}

function refreshStatus() {
	for (var i=0; i < parent.frames.length; i++) {
		if (parent.frames[i].name == "status" && parent.frames[i].location.pathname != '') {
			parent.frames[i].location.replace(parent.frames[i].location.pathname);
		}
	}
}

function doLoad(useAjax) {

	if (useAjax == 1) {
		setTimeout( "ajaxRefresh()", refreshtime*1000);
	} else {
		setTimeout( "refresh()", refreshtime*1000);
	}

	try {
		if (parent.playlist.location.host != '') {
			// Putting a time-dependant string in the URL seems to be the only way to make Safari
			// refresh properly. Stitching it together as below is needed to put the salt before
			// the hash (#currentsong).
			var plloc = top.frames.playlist.location;
			var newloc = plloc.protocol + '//' + plloc.host + plloc.pathname
				+ plloc.search.replace(/&d=\d+/, '') + '&d=' + new Date().getTime() + plloc.hash;

			// Bug 3404
			// We also need to make sure the player param in the playlist frame matches ours
			var q = window.location.search;
			var playerExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;
			var player = q.match( playerExp );
			newloc = newloc.replace(playerExp, player);

			plloc.replace(newloc);
		}
	}
	catch (err) {
		// first load can fail, so swallow that initial exception.
	}
}

function refresh() {
	window.location.replace(statusroot + "?player=" + player);
}

function ajaxRefresh() {

	// add a random number to the params as IE loves to cache the heck out of
	var args = 'd=' + Math.random();

	var requesttype = 'post';

	var myAjax = new Ajax.Request(
	'html/ping.html',
	{
		method: requesttype,
		postBody: 'd=' + Math.random(),
		onSuccess: function(t) {
			setTimeout( "ajaxRefresh()", refreshtime*1000);
			refresh();
		},
		onFailure: function(t) {
			setTimeout( "ajaxRefresh()", refreshtime*500);
		},
		onException: function(t) {
			setTimeout( "ajaxRefresh()", refreshtime*500);
		},
		requestHeaders:['Referer', document.location.href]
	});
}

function chooseAlbumOrderBy(value, option)
{
	if (option) {
		orderByUrl = orderByUrl + '&orderBy=' + option;
	}
	setCookie( 'Squeezebox-orderBy', option );
	window.location = orderByUrl;
}

function switchPlayer(player_List) {
	player    = encodeURIComponent(player_List.options[player_List.selectedIndex].value);
	var newPlayer = "=" + player;

	try {
		// change for skins with frames
		doc = parent.frames[browserTarget];

		parent.playlist.location = "playlist.html?player" + newPlayer;
		window.location = "status_header.html?player" + newPlayer;

		if (doc.location.href.indexOf('home')    == -1 &&
		    doc.location.href.indexOf('settings') == -1 &&
		    doc.location.href.indexOf('plugins') == -1) {

			for (var j=0;j < doc.document.links.length; j++) {
				var myString = new String(doc.document.links[j].href);
				var rString = newPlayer;
				var rExp = /(player=(\w\w(:|%3A)){5}(\w\w))|(player=(\d{1,3}\.){3}\d{1,3})/gi;

				doc.document.links[j].href = myString.replace(rExp, rString);
			}

			// deal with form values.
			newValue(doc.document,player);

		} else {

			myString = new String(doc.location.href);
			var rExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;

			doc.location = myString.replace(rExp, newPlayer);

		}
	}  catch(e) {

		myString = new String(this.location.href);

		var rExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;

		if (rExp.exec(myString)) {
			this.location = myString.replace(rExp, newPlayer);
		} else {
			this.location = this.location.href + "?player" + newPlayer;
		}
	}
}

// change form values to correct player
function newValue(doc,plyr) {

	for (var j=0;j < doc.forms.length; j++){

		if (doc.forms[j].player) {
			doc.forms[j].player.value = plyr;
		}
	}
}

function setCookie(name, value) {
	var expires = new Date();
	expires.setTime(expires.getTime() + 1000*60*60*24*365);
	document.cookie =
		name + "=" + encodeURIComponent(value) +
		((expires == null) ? "" : ("; expires=" + expires.toGMTString()));
}

function resize(src,width)
{
	if (!width) {
		// special case for IE (argh)
		if (document.all) //if IE 4+
		{
			width = document.body.clientWidth*0.5;
		}
		else if (document.getElementById) //else if NS6+
		{
			width = window.innerWidth*0.5;
		}
	}

	if (src.width > width || !src.width)
	{
		src.width = width;
	}
}

