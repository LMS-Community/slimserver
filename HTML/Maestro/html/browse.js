Browse = function(){
	return {
		init : function(){
			// add highlighter class
			Utils.addBrowseMouseOver();

			Ext.EventManager.onWindowResize(this.onResize, this);
			Ext.EventManager.onDocumentReady(this.onResize, this, true);
			
			// remove the default scrolling panel, we're using our own
			if (el = Ext.get('content'))
				el.removeClass('scrollingPanel');

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
			infoHeight = 0;
			if (el = Ext.get('infoTab'))
				infoHeight = el.getHeight() - 5;

			el = Ext.get('browsedbList');
			el.setHeight(Ext.fly(document.body).getHeight() - el.getTop() - infoHeight);
		}
	};
}();

Ext.EventManager.onDocumentReady(Browse.init, Browse, true);
