var p = 1;


function to_currentsong() {
	if (window.location.hash == '' || navigator.appName=="Microsoft Internet Explorer") {
		window.location.hash = 'currentsong';
	}
}

function switchPlayer(player_List){
	var newPlayer = player_List.options[player_List.selectedIndex].value;
	setCookie('SlimServer-player',player_List.options[player_List.selectedIndex].value);
	
	for(var i=0;i < top.frames.length; i++){
		var myString = new String(top.frames[i].location);
		var rString = newPlayer;
		var rExp = /(\w\w(:|%3A)){5}(\w\w)/gi;
		top.frames[i].location = myString.replace(rExp, rString);
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
		fullsize = document.getElementById("fullsize");
		if (fullsize) {

			fullsize.style.display = 'block';
		}
		src.width = width;
	}
}

function checkReload()
{
			if (parent.playlist.location != '') parent.playlist.location.reload(true);
}

function playlistResize(playlist) {
	if (playlist) {
		var header = playlist.getElementById('header');
		
		top.document.getElementById('player_frame').rows = header.clientHeight+', *';
	}
}

function openRemote(player,playername)
{
	window.open('status.html?player='+player+'&undock=1', playername, 'width=480,height=270');
}

function setCookie(name, value)
{
	var expires = new Date();
	expires.setTime(expires.getTime() + 1000*60*60*24*365);
	document.cookie =
		name + "=" + escape(value) +
		((expires == null) ? "" : ("; expires=" + expires.toGMTString()));
}

var p = 1;
// Update the progress dialog with the current state
function ProgressUpdate(mp,_progressEnd,_progressAt) 
{
	if (mp)_progressAt++;
	if(_progressAt > _progressEnd) _progressAt = _progressAt % _progressEnd;
	if (document.all) //if IE 4+
	{
		p = (document.body.clientWidth / _progressEnd) * _progressAt;
		//document.all.progressBar.innerWidth = p+" ";
		eval("document.progressBar.width=p");
	}
	else if (document.getElementById) //else if NS6+
	{
		p = (document.width / _progressEnd) * _progressAt;
		document.getElementById("progressBar").width=p+" ";
		//eval("document.progressBar.width=p");
	}
	setTimeout("ProgressUpdate("+mp+","+_progressEnd+","+_progressAt+")", 1000);
}

function Click(mp,end,at) 
{
	var s = '';
	if (!mp) s = '_s';
	if (document.all||document.getElementById)
	document.write('<table border="0" cellspacing="0" cellpadding="0"><td height="4"><img id="progressBar" name="progressBar" src="html/images/pixel.green'+s+'.gif" width="1" height="4"></td></table>');
	ProgressUpdate(mp,end,at)
}

function getArgs() {
	var args = new Object();
	var query = location.search.substring(1);
	var pairs = query.split("&");
	for(var i = 0; i < pairs.length; i++) {
		var pos = pairs[i].indexOf('=');
		if (pos == -1) continue;
		var argname = pairs[i].substring(0,pos);
		var value = pairs[i].substring(pos+1);
		args[argname] = unescape(value);
	}
	return args;
}

function getPlayer(Player) 
{
	var search = Player + "=";
	if (document.cookie.length > 0) {
		offset = document.cookie.indexOf(search);
		if (offset != -1) {
			offset += search.length;
			end = document.cookie.indexOf(";", offset);
			if (end == -1)
				end = document.cookie.length;
			return unescape(document.cookie.substring(offset, end));
		}
	}
	return "";
}

function goHome(plyr)
{
	var loc = getHomeCookie('SlimServer-Browserpage')+'&player='+plyr;
	parent.browser.location = loc;
}

function getHomeCookie(Name) 
{
	var search = Name + "=";
	if (document.cookie.length > 0) {
		offset = document.cookie.indexOf(search);
		if (offset != -1) {
			offset += search.length;
			end = document.cookie.indexOf(";", offset);
			if (end == -1)
				end = document.cookie.length;
			url = unescape(document.cookie.substring(offset, end));
			if (url == 'undefined') return "browsedb.html?hierarchy=album,track&level=0&page=BROWSE_BY_ALBUM";
			return url;
		}
	}
	return "browsedb.html?hierarchy=album,track&level=0&page=BROWSE_BY_ALBUM";
}

var selectedLink;

function selectLink(lnk) {

	if (selectedLink) selectedLink.style.fontWeight='normal';

	lnk.style.fontWeight='bold';

	selectedLink=lnk;
}

var homeLink;

function setLink(lnk,plyr) {

	lnk.href = getHomeCookie('SlimServer-Browserpage')+'&player='+plyr;

	homeLink=lnk;
}

function replaceSubstring(inputString, fromString, toString) {

	// Goes through the inputString and replaces every occurrence of fromString with toString

	var temp = inputString;

alert(temp);
	if (fromString == "") {

		return inputString;

	}

	if (toString.indexOf(fromString) == -1) { // If the string being replaced is not a part of the replacement string (normal situation)

		while (temp.indexOf(fromString) != -1) {

			var toTheLeft = temp.substring(0, temp.indexOf(fromString));

			var toTheRight = temp.substring(temp.indexOf(fromString)+fromString.length, temp.length);

			temp = toTheLeft + toString + toTheRight;

	}

	} else { // String being replaced is part of replacement string (like "+" being replaced with "++") - prevent an infinite loop

		var midStrings = new Array("~", "`", "_", "^", "#");

		var midStringLen = 1;

		var midString = "";

		// Find a string that doesn't exist in the inputString to be used

		// as an "inbetween" string

	while (midString == "") {

		for (var i=0; i < midStrings.length; i++) {

			var tempMidString = "";

			for (var j=0; j < midStringLen; j++) { tempMidString += midStrings[i]; }

				if (fromString.indexOf(tempMidString) == -1) {

					midString = tempMidString;

					i = midStrings.length + 1;

				}

			}

		} // Keep on going until we build an "inbetween" string that doesn't exist

		// Now go through and do two replaces - first, replace the "fromString" with the "inbetween" string

		while (temp.indexOf(fromString) != -1) {

			var toTheLeft = temp.substring(0, temp.indexOf(fromString));

			var toTheRight = temp.substring(temp.indexOf(fromString)+fromString.length, temp.length);

			temp = toTheLeft + midString + toTheRight;

		}

		// Next, replace the "inbetween" string with the "toString"

		while (temp.indexOf(midString) != -1) {

			var toTheLeft = temp.substring(0, temp.indexOf(midString));

			var toTheRight = temp.substring(temp.indexOf(midString)+midString.length, temp.length);

			temp = toTheLeft + toString + toTheRight;

		}

	} // Ends the check to see if the string being replaced is part of the replacement string or not

	return temp; // Send the updated string back to the user

} // Ends the "replaceSubstring" function