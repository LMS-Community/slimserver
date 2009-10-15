var Favorites = function(){
	return {
		init : function(session, index){

			if (index == 'undefined' || index == 'null')
				index = null;

			SqueezeJS.UI.ScrollPanel.init();

			var favlist = new SqueezeJS.UI.Sortable({
				el: 'draglist',
				selector: 'ol#draglist li',
				index: index,

				highlighter: Highlighter,

				onDrop: function(source, target, position) {
					if (target && source) {
						var sourcePos = Ext.get(source.id).dd.config.position;
						target = Ext.get(target.id);
						var targetPos = target.dd.config.position;
			
						if (sourcePos >= 0 && targetPos >= 0 && targetPos < 10000) {
							if ((sourcePos > targetPos && position > 0) || (sourcePos < targetPos && position < 0)) {
								targetPos += position;
							}
						}

						if (sourcePos >= 0 && targetPos >= 0 && (sourcePos != targetPos)) {	
							var el;
		
							// send the result to the page handler
							if (el = Ext.get(this.el))
								// unregister event handlers
								Ext.dd.ScrollManager.unregister(el);
		
							var params = {
								action: 'move',
								index: (this.index != null ? this.index+ '.' : '') + sourcePos,
								sess: session,
								ajaxUpdate: 1,
								player: player
							};
		
							// drop into parent level
							if (targetPos > 10000) {
								targetPos = (targetPos % 10000) - 1;
								params.tolevel = target.dd.config.index != null ? target.dd.config.index : '';
							}
		
							// drop to sub-folder
							else if (position == 0)
								params.into = targetPos;
		
							// move within current level
							else
								params.to = targetPos;
		
							if (el = Ext.get('mainbody')) {
								var um = el.getUpdateManager();						
								el.load(
									webroot + 'plugins/Favorites/index.html', 
									params,
									function(){
										Favorites.init(session, new String(this.index));
									}.createDelegate(this)
								);
							}

							this.init(session, new String(this.index));
						}
					}
				}
			});

			// add upper levels in crumb list as drop targets
			// but don't add first (home) and last (current) level
			var items = Ext.DomQuery.select('div#crumblist a');
			for(var i = 1; i < items.length-1; i++) {
				var item = Ext.get(items[i]);
				var index = item.dom.href.match(/index=([\d\.,]+)/i);

				Ext.id(item);
				item.dd = new Ext.dd.DDTarget(items[i], 'draglist', {
					position: i + 10000,
					index: index && index.length > 1 ? index[1] : ''
				});
			}
		}
	}
}();

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
