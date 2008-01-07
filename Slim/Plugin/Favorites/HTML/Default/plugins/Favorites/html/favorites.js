var Favorites = function(){
	return {
		init : function(session, offset){
			new Slim.Sortable({
				el: 'draglist',
				selector: 'ol#draglist li',
				onDropCmd: function(sourcePos, targetPos) {
					var el;

					// send the result to the page handler
					if (el = Ext.get(this.el))
						// unregister event handlers
						Ext.dd.ScrollManager.unregister(el);

					if (el = Ext.get('mainbody')) {
						Utils.unHighlight();
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
								Utils.init();
								Favorites.init(session, offset);
							}
						);
					}
				}
			})
		}
	}
}();