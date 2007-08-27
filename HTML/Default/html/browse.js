Browse = function(){
	return {
		init : function(){
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
		
		hideInfoPopup : function(){
			Ext.get('infoPopup').fadeOut({ duration: 0.4});
			Ext.get('popupBackground').fadeOut({ duration: 0.4});
			Ext.get('popupList').setStyle('overflow', 'hidden');
			//new Effect.Appear('viewSelect', { duration:0.4 });
		},

		popUpInfo : function(attributes) {
			
			// here we go-- get the album track details via an ajax call
			// pop up a list of the tracks in an inline div, including play/add buttons next to tracks
			// add a close button for the div to hide it
			if (Ext.get('infoPopup')) {
				Ext.get('popupBackground').fadeIn({ endOpacity: 0.5, duration: 0.4});
				
				Ext.get('infoPopup').setStyle('border', '1px solid white');
				
				Ext.get("popupcontent").load({
					url: webroot + 'browsedb.html',
					params: 'ajaxUpdate=1&player=' + player + '&' + attributes,
					callback: this.onInfoUpdated
					//text: "Loading Foo..."
				});
			}
		},
	
		onInfoUpdated : function(){
			
			Ext.get('infoPopup').fadeIn({ endOpacity: 1, duration: 0.4});
			Utils.init();
		}
	};
}();

Ext.EventManager.onDocumentReady(Browse.init, Browse, true);
