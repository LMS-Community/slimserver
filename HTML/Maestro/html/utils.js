var Utils = function(){
	return {
		addBrowseMouseOver: function(){
			Ext.addBehaviors({
				'.selectorMarker@mouseover': function(ev, target){
					if (target.tagName != 'DIV' || !Ext.get(target).hasClass('selectorMarker'))
						return;

					// remove highlighting from the other DIVs
					items = Ext.DomQuery.select('div.mouseOver');
					for(var i = 0; i < items.length; i++) {
						el = Ext.get(items[i].id);
						if (el) {
							el.replaceClass('mouseOver', 'selectorMarker');
						
							if (controls = Ext.DomQuery.selectNode('span.browsedbControls', el.dom)) {
								Ext.get(controls).hide();
							}
						}
					}

					el = Ext.get(target);
					if (el) {
						el.replaceClass('selectorMarker', 'mouseOver');
						
						if (controls = Ext.DomQuery.selectNode('span.browsedbControls', el.dom)) {
							Ext.get(controls).show();
						}
					}
				}
			});
		},

		resizeContent : function(){
			infoHeight = 0;
			if (el = Ext.get('infoTab'))
				infoHeight = el.getHeight();

			el = Ext.get('content');
			if (el && el.hasClass('scrollingPanel')) {
				el.setHeight(Ext.fly(document.body).getHeight() - el.getTop() - infoHeight);
			}
		}

	};
}();