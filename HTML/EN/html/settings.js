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
