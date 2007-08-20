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
						}
					}

					el = Ext.get(target);
					if (el) {
						el.replaceClass('selectorMarker', 'mouseOver');
					}
				}
			});
		}
	};
}();