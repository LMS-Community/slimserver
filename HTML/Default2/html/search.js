var searchInProgress = 0;

function searchhandler(req, url) {
	searchInProgress = 0;
	document.getElementById("activesearch").style.display = "block";
	rxml = req.responseXML;

	var resultsets = rxml.getElementsByTagName("searchresults");

	var output = "";
	for (i = 0; i < resultsets.length; i++) {
		results = resultsets[i].getElementsByTagName("livesearchitem");

		output += "<p>" + resultsets[i].getAttribute("mstring") + "</p><table>";
		type = resultsets[i].getAttribute("type"); 
		hierarchy = resultsets[i].getAttribute("hierarchy"); 

		for (j = 0; j < results.length; j++) {
			id = results[j].getAttribute("id");

			// Isn't this what XSLT is for?
			// Unfortunately, Safari doesn't support XSLTProcessor, so I'll do this the hard way...

			output += '<tr><td class="browselistbuttons">';
			output += '<img onclick="parent.updateStatusCombined(&quot;&amp;command=playlist&amp;subcommand=addtracks';
			output += '&amp;' + type + '=' + id + '&quot;)" src="html/images/add.gif" width="8" height="8"/>';
			output += '<img src="html/images/play.this.gif" width="5" height="9" onclick="parent.updateStatus';
			output += 'Combined(&quot;&amp;command=playlist&amp;';
			output += 'subcommand=loadtracks&amp;' + type + '=' + id + '&quot;)"/> </td><td class="browselisting">';
			output += '<a onclick="parent.browseurl(&quot;browsedb.html?hierarchy=' + hierarchy + '&amp;';
			output += 'level=0&amp;' + type + '=' + id + '&quot;)">' + results[j].firstChild.data + '</a>';
			output += '</td></tr>';

		}
		output += "</table>";

	}

	document.getElementById("activesearchdiv").innerHTML = output;
}

function searchsend() {
	try {
		searchtext = document.getElementById('searchquery').value;
		if (searchtext.length > 2) {
			postback("search.xml?xmlmode=1&query=" + searchtext, searchhandler);
		} else {
			searchInProgress = 0;
			document.getElementById("activesearch").style.display = "none";
		}
	} catch (err) {
	}
	return false;
}

function searchkey() {
	if (searchInProgress == 0) {
		setTimeout(searchsend, 250);
		searchInProgress = 1;
	}
	return true;
}

