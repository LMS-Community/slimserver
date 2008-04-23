var Favorites = function(){
	return {
		init : function(session, offset){
			SqueezeJS.UI.ScrollPanel.init();

			new SqueezeJS.UI.Sortable({
				el: 'draglist',
				selector: 'ol#draglist li',

				highlighter: Highlighter,
				onDropCmd: function(sourcePos, targetPos) {
					var el;

					// send the result to the page handler
					if (el = Ext.get(this.el))
						// unregister event handlers
						Ext.dd.ScrollManager.unregister(el);

					if (el = Ext.get('mainbody')) {
						var um = el.getUpdateManager();						
						el.load(
							webroot + 'plugins/Favorites/index.html', 
							{
								action: 'move',
								index: (offset >= 0 ? offset + '.' : '') + sourcePos,
								to: targetPos,
								sess: session,
								ajaxUpdate: 1,
								player: player
							},
							function(){
								Favorites.init(session, offset);
							}
						);
					}
				}
			});
		}
	}
}();

// XXX some legacy stuff - should eventually go away

// request and update with new list html, requires a 'mainbody' div defined in the document
// templates should use the ajaxUpdate param to block headers and footers.
function ajaxUpdate(url, params, callback) {
	var el = Ext.get('mainbody');

	if (el) {
		var um = el.getUpdateManager();

		if (um)
			um.loadScripts = true;

		el.load(url, params + '&ajaxUpdate=1&player=' + player, callback || SqueezeJS.UI.ScrollPanel.init);
	}
}

// some prototype JS compatibility classes
var Element = function(){
	return {
		remove: function(el) {
			if (el = Ext.get(el))
				el.remove();
			SqueezeJS.UI.ScrollPanel.init();
		}
	}
}();

// pass an array of div element ids to be hidden on the page
function hideElements(elements) {
	showElements(elements, 'none');
}

// pass an array of div element ids to be shown on the page
function showElements(elements, style) {
	var el;

	if (!style)
		style = 'block';

	for (var i = 0; i < elements.length; i++) {
		if (el = Ext.get(elements[i]))
			el.setStyle('display', style);
	}
}
