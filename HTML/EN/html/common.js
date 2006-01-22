<script language="JavaScript" type="text/javascript">
<!-- Start Hiding the Script

function to_currentsong() {
	if (window.location.hash == '' || navigator.appName=="Microsoft Internet Explorer") {
		window.location.hash = 'currentsong';
	}
}

[% IF refresh %]function doLoad() {

	setTimeout( "refresh()", [% refresh %]*1000);
	try {
		if (parent.playlist.location.host != '') {
			// Putting a time-dependant string in the URL seems to be the only way to make Safari
			// refresh properly. Stitching it together as below is needed to put the salt before
			// the hash (#currentsong).
			var plloc = top.frames.playlist.location;
			var newloc = plloc.protocol + '//' + plloc.host + plloc.pathname
				+ plloc.search.replace(/&d=\d+/, '') + '&d=' + new Date().getTime() + plloc.hash;
			plloc.replace(newloc);
		}
	}
	catch (err) {
		// first load can fail, so swallow that initial exception.
	}
}

function refresh() {
	window.location.replace("[% statusroot %]?player=[% player | uri %]&amp;start=[% start %]&amp;refresh=1");
}
[% END %]

[% BLOCK addCaseLinks %]
	[% IF links %]
		[% FOREACH link = links %]
		case "[% link.key %]":
			url = "[% link.value %]"
			page = "[% link.key %]"
			suffix = "page=" + page
			[% IF cookie %]homestring = "[% link.key | string %]"
			cookie = [% cookie %][% END %]
		break
		[% END %]
	[% END %]
[% END %]

function chooseSettings(value,option)
{
	var url;

	switch(option)
	{
		[% IF playerid %][% PROCESS addCaseLinks links=additionalLinks.playersetup  %]
						 [%# PROCESS addCaseLinks links=additionalLinks.playerplugin %]
		[% ELSE %][% PROCESS addCaseLinks links=additionalLinks.setup   %]
				  [%# PROCESS addCaseLinks links=additionalLinks.plugin %][% END %]
		case "HOME":
			url = "[% webroot %]home.html?"
		break
		case "PLAYER_SETTINGS":
			url = "[% webroot %]setup.html?page=PLAYER_SETTINGS&"
		break
		case "SERVER_SETTINGS":
			url = "[% webroot %]setup.html?page=SERVER_SETTINGS&"
		break
	}

	if (option) {
		window.location = url + 'player=[% playerURI %][% IF playerid %]&playerid=[% playerid %][% END %]';
	}
}

function switchPlayer(player_List) {
	var newPlayer = "=" + player_List.options[player_List.selectedIndex].value;
	parent.playlist.location="playlist.html?player"+newPlayer;
	window.location="status_header.html?player"+newPlayer;
	if (parent.browser.location.href.indexOf('setup') == -1) {
		for (var j=0;j < parent.browser.document.links.length; j++) {
			var myString = new String(parent.browser.document.links[j].href);
			var rString = newPlayer;
			var rExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;

			parent.browser.document.links[j].href = myString.replace(rExp, rString);
		}
	} else {
		myString = new String(parent.browser.location.href);
		var rExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;

		parent.browser.location=myString.replace(rExp, newPlayer);
	}
}

function resize(src,width)
	{
		if (!width) {
			// special case for IE (argh)
			if (document.all) //if IE 4+
			{
				width = document.body.clientWidth*0.95;
			}
			else if (document.getElementById) //else if NS6+
			{
				width = window.innerWidth*0.95;
			}
		}
	
		if (src.width > width )
		{
			src.width = width;
		}
	}

[% IF warn %]
function doLoad() {
	setTimeout( "refresh()", 300*1000);
}
	
function refresh() {
	window.location.replace("home.html?player=[% player | uri %]");
}
[% END %]	

// Stop Hiding script --->
</script>
