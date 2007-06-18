[%- FILTER null %]
	[% BLOCK addSetupCaseLinks %]
		[% IF setuplinks %]
			[% FOREACH setuplink = setuplinks %]
			case "[% setuplink.key %]":
				url = "[% webroot %][% setuplink.value %]"
				page = "[% setuplink.key %]"
				suffix = "page=" + page
				[% IF cookie %]homestring = "[% setuplink.key | string %]"
				cookie = [% cookie %][% END %]
			break;
			[% END %]
		[% END %]
	[% END %]
[% END -%]

function chooseSettings(value,option)
{
	var url;

	switch(option)
	{
		[% IF playerid -%]

			[% PROCESS addSetupCaseLinks setuplinks=additionalLinks.playersetup  %]

		[%- ELSE -%]

			[% PROCESS addSetupCaseLinks setuplinks=additionalLinks.setup   %]

		[%- END %]

		case "HOME":
			url = "[% webroot %]home.html?"
		break
	}

	if (option) {
		// change the mouse cursor so user gets some feedback
		$('settingsForm').setStyle({cursor:'wait'});		
		new Ajax.Updater( { success: 'settingsRegion' }, url, {
			method: 'post',
			postBody: 'ajaxUpdate=1&player=[% playerURI %][% IF playerid %]&playerid=[% playerid | uri %][% END %]',
			evalScripts: true,
			asynchronous: true,
			onFailure: function(t) {
				alert('Error -- ' + t.responseText);
			},
			onComplete: function(t) {
				$('settingsForm').setStyle({cursor:'auto'});
				$('statusarea').update('');		
			}
		} );
		document.forms.settingsForm.action = url;
	}
}

function prefValidate(myPref, sync) {
	new Ajax.Request('/jsonrpc.js', {
		method: 'post',

		postBody: Object.toJSON({
			id: 1, 
			asynchronous: (sync ? false : true),
			method: 'slim.request', 
			params: [
				'', 
				[
					'pref', 
					'validate', 
					myPref.name, 
					myPref.value
				]
			]
		}),

		onSuccess: function(response) {
			var json = response.responseText.evalJSON();

			// preference did not validate - highlight the field
			highlightField(myPref, (json.result.valid == '1'));
		}
	});
}

function resizeSettingsSection() {
	var winHeight = (
		document.documentElement && document.documentElement.clientHeight
		? parseInt(window.innerHeight, 10)
		: parseInt(document.body.offsetHeight, 10)
	);
	var settingsTop = Position.cumulativeOffset($('settingsRegion'))[1];
	var submitHeight = $('prefsSubmit').offsetHeight + 10;

	if ((winHeight - parseInt(settingsTop, 10) - parseInt(submitHeight, 10)) > 0) {
		$('settingsRegion').setStyle({
			'height': (winHeight - parseInt(settingsTop, 10) - parseInt(submitHeight, 10)) + 'px'
		});
	}
}

new Event.observe(window, 'load', function(){
	// add event handlers to all fields which have a validator
	[%- FOREACH pref = validate; IF pref.value %]
	new Event.observe('[% pref.key %]', 'blur', function(){ prefValidate($('[% pref.key %]')); } );
	[%- END; END %]
	
	// try to redirect all form submissions by return key to the default submit button
	// listen for keypress events on all form elements except submit
	$('settingsForm').getElements().each(function(ele) {
		if (ele.type != 'submit') {
			new Event.observe(ele, 'keypress', function(e) {
				var cKeyCode = e.keyCode || e.which;
				if (cKeyCode == Event.KEY_RETURN) {
					Event.stop(e);
					$('saveSettings').activate();
				}
			});
		}
	});

	// resize the scrolling part of the settings page
	new Event.observe(window, 'resize', function(){resizeSettingsSection();});

	new Event.observe('saveSettings', 'click', function(e){
		$('settingsForm').setStyle({cursor:'wait'});		
		Event.stop(e);
		$('settingsForm').request({
			parameters: { useAJAX: 1, rescan: '' },		
			onComplete: function(response) {
				var results = parseData(response.responseText);

				$('statusarea').update(results['warning']);
				resizeSettingsSection();

				// highlight fields
				for (field in results) {
					if ($(field)) {
						highlightField($(field), (results[field] == '1'));
					}
				}

				$('settingsForm').setStyle({cursor:'auto'});		
			}
		});
	});

	resizeSettingsSection();
});

var bgColors = new Array;
function highlightField(field, valid) {
	if (!bgColors[field]) {
		bgColors[field] = field.getStyle('backgroundColor'); 
	}

	if (valid) {
		// restore the background before calling the effect
		// using it as targetcolor didn't work
		field.setStyle({backgroundColor: bgColors[field]});
		new Effect.Highlight(field, {
			duration: 0.5,
			startcolor: '#99ff99'
		});
	}
	else {
		field.setStyle({backgroundColor: '#ffcccc'});
	}
}