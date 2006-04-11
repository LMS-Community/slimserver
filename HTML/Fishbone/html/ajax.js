var player = '[% player %]';
var url = 'status_header.html';

// progress bar temp variable
var p = 1;

// track the progress bar update timer state
var timer;

// update timer counter, waits for 10 updates when update interval is 1s
var inc = 0;

// refresh data interval (1s for progress updates, 10s for only status)
var interval = 1;

// track the last play control pressed.
var lastControl = '';

[% PROCESS html/global.js %]
[%# PROCESS datadumper.js %]

function processState(param) {
	getStatusData(param + "&ajaxRequest=1", refreshState);
}

function refreshState(theData) {

	var parsedData = fillDataHash(theData);
	// refresh control_display in songinfo section
	
	var controls = ['repeat', 'shuffle', 'mode'];
	var power = ['on', 'off'];
	
	for (var i=0; i < controls.length; i++) {
		var obj = controls[i];

		for (var j=0; j <= 2; j++) {
			var objID;
			
			if (i < 2) {
				objID = $('playlist' + controls[i]+j);
			} else {
				objID = $('power' + j);
			}
			
			if (parsedData[obj] == j || parsedData[obj] == power[j]) {
				objID.className = 'button';
			} else {
				objID.className = 'darkbutton';
			}
		}
	}
	//DumperPopup(theData.responseText);
}

function processVolume(param) {
	getStatusData(param + "&ajaxRequest=1", refreshVolume);
}

function refreshVolume(theData) {

	var parsedData = fillDataHash(theData);
	var vols = [0, 6, 12, 18, 24, 30, 36, 42, 48, 54, 60, 66, 72, 78, 84, 90, 95, 100];

	for (var i=0; i < vols.length; i++) {
		var div = (i + 1) * 2;
		var objID = $('volDiv' + div);
		var intVolume = parseInt(parsedData['volume'], 10);

		if (intVolume < vols[i]) {
			//alert(objID.style.background-color);
			objID.style.backgroundColor = "808080";
		} else {
			objID.style.backgroundColor = "00C000";
		}
	}
	//DumperPopup(theData.responseText);
}

function processPlayControls(param,button) {
	getStatusData(param + "&ajaxRequest=1", refreshPlayControls);
	lastControl = button;
}

function refreshPlayControls(theData) {

	var parsedData = fillDataHash(theData);
	var controls = ['stop', 'play', 'pause'];
	
	for (var i=0; i < controls.length; i++) {
		var obj = 'playmode';
		var objID = $('playCtl' + controls[i]);
		var style = '';
		
		if (objID.style.display == 'hidden') {
			objID = $('playCtl' + controls[i]+'_tan');
			style = '_tan';
		}
		
		//DumperPopup([i,parsedData['playmode']]);
		if (parsedData['playmode'] == i) {
			objID.src = '[% webroot %]html/images/'+controls[i]+'_s'+style+'.gif';
			if (timer) {clearTimeout(timer);}
			interval = 10;
			if (controls[i] !='stop') {
				interval = 1;
			}
			
		} else {
			objID.src = '[% webroot %]html/images/'+controls[i]+style+'.gif';
		}
	}
	
	if (parsedData['mute'] == 1) {
		$('playCtl' + 'mute').src = '[% webroot %]html/images/mute_s'+style+'.gif';
	} else {
		$('playCtl' + 'mute').src = '[% webroot %]html/images/mute'+style+'.gif';
	}
	
	var mp = 0;
	if (lastControl == 'play') {
		mp = 1;
		inc = 10;
		ProgressUpdate(1,parsedData['durationseconds'],parsedData['songtime'],style);
	} else {
		timer = setTimeout("ProgressUpdate( "+mp+","+parsedData['durationseconds']+","+parsedData['songtime']+")", interval * 1000);
	}
	//DumperPopup(theData.responseText);
}


// Update the progress dialog with the current state
function ProgressUpdate(mp,_progressEnd,_progressAt,style) {
	var playctl = 'playCtlplay';
	//if (style == '_tan') playctl = 'playCtlplay_tan';
	if ($('playCtlplay') != null) {
		if ($('playCtlplay').src.indexOf('_s') != -1) {
			mp = 1;
			inc++;
			interval = 1;
			$("progressBar").src ='[% webroot %]html/images/pixel.green.gif'

		} else {
			interval = 10;
			inc = 10;
			mp = 0;
			$("progressBar").src = '[% webroot %]html/images/pixel.green_s.gif'
		}
	}

	if (mp) _progressAt++;
	if(_progressAt > _progressEnd) _progressAt = _progressAt % _progressEnd;
	
	[% IF undock %]if ((_progressEnd > 0) && (_progressAt > 10) && (_progressAt == _progressEnd)) refreshUndock();[% END %]
	
	if (document.all) //if IE 4+
	{
		p = (document.body.clientWidth / _progressEnd) * _progressAt;
		//document.all.progressBar.innerWidth = p+" ";
		eval("document.progressBar.width=p");
	}
	else if (document.getElementById) //else if NS6+
	{
		p = (document.width / _progressEnd) * _progressAt;
		$("progressBar").width=p+" ";
		//eval("document.progressBar.width=p");
	}
	
	if (inc == 10 || interval == 10) {
		var args = 'player='+player+'&ajaxRequest=1';
		//alert(interval);
		getStatusData(args, refreshAll);
		inc = 0;
	} else {
		//alert(['off',interval]);
		timer = setTimeout("ProgressUpdate( "+mp+","+_progressEnd+","+_progressAt+")", interval*1000);
	}
}

function refreshUndock() {
	window.location.replace('status.html?player='+player+'&undock=1');
}

function refreshAll(theData) {
	inc = 0;
	// stop progress bar refreshing for this track
	if (timer) clearTimeout(timer);
	var parsedData = fillDataHash(theData);
	refreshVolume(parsedData);
	refreshPlayControls(parsedData);
	refreshState(parsedData);
}

function fillDataHash(theData) {
	var returnData = null;
	if (theData['player_id']) { 
		return theData;
	} else {
		var myData = theData.responseText;
		returnData = parseData(myData);
	}

	return returnData;
}