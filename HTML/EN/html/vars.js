// useful global vars for javascripts needing info from template toolkit on page loads.
	var webroot       = "[% webroot %]";
	[% IF refresh %]var refreshtime   = "[% refresh %]";[% END %]
	var player        = "[% playerURI %]";
	var playerid      = "[% player %]";
	var url           = "[% statusroot %]";
	var statusroot    = "[% statusroot %]";
	var browserTarget;
	[% IF browserTarget %]browserTarget = "[% browserTarget %]";[% END %]
	var orderByUrl    = '';
