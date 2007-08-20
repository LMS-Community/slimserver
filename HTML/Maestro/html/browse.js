Browse = function(){
	return {
		init : function(){
			// add highlighter class
			Utils.addBrowseMouseOver();
							
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
