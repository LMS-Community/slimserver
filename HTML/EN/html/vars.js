// useful global vars for javascripts needing info from template toolkit on page loads.
	var webroot       = "[% webroot %]";
	[% IF refresh %]var refreshtime   = "[% refresh %]";[% END %]
	var player        = "[% playerURI %]";
	var url           = "[% statusroot %]";
	var statusroot    = "[% statusroot %]";
	[% IF browserTarget %]var browserTarget = "[% browserTarget %]";[% END %]
	var orderByUrl    = 'browsedb.html?hierarchy=[% hierarchy %]&level=[% level %][% attributes %][% IF artwork %]&artwork=1[% END %]&player=' + player;
