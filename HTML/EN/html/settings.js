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
		case "BASIC_PLAYER_SETTINGS":
			url = "[% webroot %]setup.html?page=BASIC_PLAYER_SETTINGS&amp;playerid=[% playerid | uri %]"
		break
		case "BASIC_SERVER_SETTINGS":
			url = "[% webroot %]setup.html?page=BASIC_SERVER_SETTINGS&amp;"
		break
	}

	if (option) {
		window.location = url + 'player=[% playerURI %][% IF playerid %]&playerid=[% playerid | uri %][% END %]';
	}
}

var validateAll = true;
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
			if (json.result.valid == '0') {
				myPref.style.background = '#ffcccc';
				validateAll = false;
			}
			else {
				new Effect.Highlight(myPref.name, {
				duration: 0.5,
					startcolor: '#99ff99',
					endcolor: '#ffffff',
					restorecolor: '#ffffff'
				});
			}
		}
	});
}

function resizeSettingsSection() {
	// if there's no div for the submit botton, don't resize the region (eg. Nokia, Handheld)
	if (!$('prefsSubmit')) { return; }

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
	[%- FOREACH item = validate %]
	new Event.observe('[% item %]', 'blur', function(){ prefValidate($('[% item %]')); } );
	[%- END %]
	
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
		[%- FOREACH item = validate %]
		prefValidate($('[% item %]'), true);
		[%- END %]

		// if validation fails and user doesn't force the submit, cancel
		if (!validateAll && !confirm("[% "SETUP_VALIDATION_FAILED" | string %]")) {
			Event.stop(e);
			validateAll = true;
		}
	});

	resizeSettingsSection();
});

