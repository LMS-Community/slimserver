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

		toggleGalleryView: function(artwork){

			var thisdoc = document;

			if (browserTarget && parent.frames[browserTarget]) {
				thisdoc = parent.frames[browserTarget];
			}

			if (thisdoc.location.pathname != '') {
				myString = new String(thisdoc.location.href);

				if (artwork) {
					Utils.setCookie( 'SlimServer-albumView', "1" );

					if (thisdoc.location.href.indexOf('start') == -1) {
						thisdoc.location=thisdoc.location.href+"&artwork=1";
					} else {
						myString = new String(thisdoc.location.href);

						var rExp = /\&start=/gi;
						thisdoc.location=myString.replace(rExp, "&artwork=1&start=");
					}
				} else {

					Utils.setCookie( 'SlimServer-albumView', "" );

					var rExp = /\&artwork=1/gi;
					thisdoc.location=myString.replace(rExp, "");
				}
			}
		},

		chooseAlbumOrderBy: function(value, option) {
			if (option) {
				orderByUrl = orderByUrl + '&orderBy=' + option;
			}
			Utils.setCookie( 'SlimServer-orderBy', option );
			window.location = orderByUrl;
		}

	};
}();

Ext.EventManager.onDocumentReady(Browse.init, Browse, true);

// legacy calls for shared code...
function toggleGalleryView(artwork) {
	Browse.toggleGalleryView(artwork)
}

function chooseAlbumOrderBy(value, option) {
	Browse.chooseAlbumOrderBy(value, option);
}

