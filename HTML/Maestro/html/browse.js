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
				infoHeight = el.getHeight();

			el = Ext.get('browsedbList');
			el.setHeight(Ext.fly(document.body).getHeight() - el.getTop() - infoHeight);
		},
		
		hideAlbumInfo : function(){
			Ext.get('albumPopup').fadeOut({ duration: 0.4});
			Ext.get('albumBackground').fadeOut({ duration: 0.4});
			Ext.get('browsedbList').setStyle('overflow', 'hidden');
			//new Effect.Appear('viewSelect', { duration:0.4 });
		},

		popUpAlbumInfo : function(attributes) {
			
			// here we go-- get the album track details via an ajax call
			// pop up a list of the tracks in an inline div, including play/add buttons next to tracks
			// add a close button for the div to hide it
			if (Ext.get('albumPopup')) {
				Ext.get('albumBackground').fadeIn({ endOpacity: 0.5, duration: 0.4});
				
				Ext.get('albumPopup').setStyle('border', '1px solid white');
				
				Ext.get("trackInfo").load({
					url: webroot + 'browsedb.html',
					params: 'ajaxUpdate=1&player=' + player + '&' + attributes,
					callback: this.onAlbumUpdated
					//text: "Loading Foo..."
				});
			}
		},
	
		onAlbumUpdated : function(){
			Ext.get('albumPopup').show();
		},
	};
}();

Ext.EventManager.onDocumentReady(Browse.init, Browse, true);
