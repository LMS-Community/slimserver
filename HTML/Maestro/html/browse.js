Browse = function(){
	return {
		init : function(){
			// add highlighter class
			Ext.addBehaviors({
				'div.browsedbListItem@mouseover': function(ev, target){
					if (target.tagName != 'DIV')
						return;

					// remove highlighting from the other DIVs
					items = Ext.DomQuery.select('div.mouseOver');
					for(var i = 0; i < items.length; i++) {
						el = Ext.get(items[i].id);
						if (el) {
							el.removeClass('mouseOver');
						}
					}

					Ext.get(target).addClass('mouseOver');
				}
			});
							
			Ext.EventManager.onWindowResize(this.onResize, this);
			Ext.EventManager.onDocumentReady(this.onResize, this, true);

			// jump to anchor
			anchor = document.location.href.match(/#(.*)$/)
			if (anchor && anchor[1]) {
				if (el = Ext.get('anchor' + anchor[1]))
					el.scrollIntoView('browsedbList');
			}
		},
		
		gotoAnchor : function(anchor){
			if (el = Ext.get('anchor' + anchor))
				el.scrollIntoView('browsedbList');
		},

		onResize : function(){
			el = Ext.get('browsedbList');
			el.setHeight(Ext.fly(document.body).getHeight() - el.getTop());
		}
	};
}();

Ext.EventManager.onDocumentReady(Browse.init, Browse, true);
