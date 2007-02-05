// track the progress bar update timer state
var timerID = false;

// refresh data interval (1s for progress updates, 10s for only status)
var interval = 1000;

// update timer counter, waits for 10 updates when update interval is 1s
var inc = 0;

// progressBar variables
var _progressEnd = 0;
var _progressAt = 0;
var _curstyle = '';

function insertProgressBar(mp,end,at) {
	var s = '';
	if (!mp) s = '_s';

	if (document.all||document.getElementById) {
		document.write('<div class="progressBarDiv"><img id="progressBar" name="progressBar" src="html/images/pixel.green'+s+'.gif" width="1" height="4"><\/div>');
	}

	_progressAt = at;
	_progressEnd = end;
	ProgressUpdate(mp)
}

// update at and end times for the next progress update.
function updateTime(at,end, style) {
	_progressAt  = at;
	_progressEnd = end;
	
	if (style != null) {
		_curstyle    = style;
	}
}
	

// Update the progress dialog with the current state
function ProgressUpdate(mp) {

	if ($('playCtlplay') != null) {
		if ($('playCtlplay'+ _curstyle).src.indexOf('_s') != -1) {
			mp = 1;
			if ($("progressBar").src.indexOf('_s') != -1) {$("progressBar").src = 'html/images/pixel.green.gif'}

		} else {
			mp = 0;
			if ($("progressBar").src.indexOf('_s') == -1) {$("progressBar").src = 'html/images/pixel.green_s.gif'}
		}
	}
	
	timerID = setTimeout("ProgressUpdate( "+mp+")", interval);

	inc++;
	if (mp) _progressAt++;

	if(_progressAt > _progressEnd) _progressAt = _progressAt % _progressEnd;
	
	if ($(inc)) {
		refreshElement('inc',inc);
	}

	if (_progressAt == 1) {
		doAjaxRefresh();
		inc = 0;
		if (!mp) {
			_progressAt = 0;
			//refreshPlaylist();
		}
	}
	
	if (document.all) {
		p = (document.body.clientWidth / _progressEnd) * _progressAt;
		eval("document.progressBar.width=p");

	} else if (document.getElementById) {
		p = (document.width / _progressEnd) * _progressAt;
		$("progressBar").width=p+" ";
	}
	
	if (inc == 10) {
		doAjaxRefresh(1);
		inc = 0;
	}

}

