var searchInProgress = 0;
var xslp;

var forcejs = 0;

function loadxslhandler(req, url) {
	if (XSLTProcessor) {
		xslp = new XSLTProcessor();
		xslp.importStylesheet(req.responseXML);
	}
}

function doTransform(rxml) {
	var resultsets = rxml.getElementsByTagName("searchresults");

	var output = "";
	for (i = 0; i < resultsets.length; i++) {
		results = resultsets[i].getElementsByTagName("livesearchitem");

		output += "<p>" + resultsets[i].getAttribute("mstring") + "</p><table>";
		type = resultsets[i].getAttribute("type"); 
		hierarchy = resultsets[i].getAttribute("hierarchy"); 

		for (j = 0; j < results.length; j++) {
			id = results[j].getAttribute("id");
			output += '<tr><td class="browselistbuttons">';
			output += '<img onclick="parent.updateStatusCombined(&quot;&amp;command=playlist&amp;sub=addtracks';
			output += '&amp;' + type + '=' + id + '&quot;)" src="html/images/add.gif" width="8" height="8"/>';
			output += '<img src="html/images/play.this.gif" width="5" height="9" onclick="parent.updateStatus';
			output += 'Combined(&quot;&amp;command=playlist&amp;';
			output += 'sub=loadtracks&amp;' + type + '=' + id + '&quot;)"/> </td><td class="browselisting">';
			output += '<a onclick="parent.browseurl(&quot;browsedb.html?hierarchy=' + hierarchy + '&amp;';
			output += 'level=0&amp;' + type + '=' + id + '&quot;)">' + results[j].firstChild.data + '</a>';
			output += '</td></tr>';

		}
		output += "</table>";
	}
	return output;
}

function searchhandler(req, url) {
	searchInProgress = 0;
	document.getElementById("activesearch").style.display = "block";
	rxml = req.responseXML;

	asearchdiv = document.getElementById("activesearch");

	if (xslp && !forcejs) {
		var fragment = xslp.transformToFragment(rxml, document);
		asearchdiv.replaceChild(fragment, asearchdiv.firstChild);
		timestr = "XSLT ";
	} else {
		var output = doTransform(rxml)
		asearchdiv.innerHTML = output;
		timestr = "JS ";
	}
}

function searchsend() {
	try {
		searchtext = document.getElementById('searchquery').value;
		if (searchtext.length > 2) {
			postback("livesearch.xml?xmlmode=1&query=" + searchtext, searchhandler);
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

postback("html/search.xsl", loadxslhandler);
