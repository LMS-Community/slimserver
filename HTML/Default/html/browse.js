Browse = function(){
	return {
		init : function(){
			// jump to anchor
			anchor = document.location.href.match(/#(.*)$/)
			if (anchor && anchor[1]) {
				if (el = Ext.get('anchor' + anchor[1]))
					el.scrollIntoView('browsedbList');
			}

			new Ext.SplitButton('toggleGallery', {
				icon: webroot + 'html/images/albumlist' + (Utils.getCookie('SlimServer-albumView') || '0') + '.png',
				cls: 'x-btn-icon',
				menu: new Ext.menu.Menu({
					items: [
						{
							text: strings['switch_to_list'],
							cls: 'albumList',
							handler: function(){ Browse.toggleGalleryView(2) }
						},
						{
							text: strings['switch_to_extended_list'],
							cls: 'albumXList',
							handler: function(){ Browse.toggleGalleryView(0) }
						},
						{
							text: strings['switch_to_gallery'],
							cls: 'albumListGallery',
							handler: function(){ Browse.toggleGalleryView(1) }
						}
					]
				})
			});
		},
		
		gotoAnchor : function(anchor){
			if (el = Ext.get('anchor' + anchor))
				el.scrollIntoView('browsedbList');
		},

		toggleGalleryView : function(artwork){
			var thisdoc = document;

			if (browserTarget && parent.frames[browserTarget]) {
				thisdoc = parent.frames[browserTarget];
			}

			if (thisdoc.location.pathname != '') {
				url = new String(thisdoc.location.href);
				url = url.replace(/&artwork=./, '');

				if (artwork == 1) {
					Utils.setCookie( 'SlimServer-albumView', "1" );

					if (thisdoc.location.href.indexOf('start') == -1) {
						thisdoc.location = url + '&artwork=1';
					} else {
						thisdoc.location = url + '&artwork=1&start=';
					}

				} else if (artwork == 2) {
					Utils.setCookie( 'SlimServer-albumView', "2" );

					if (thisdoc.location.href.indexOf('start') == -1) {
						thisdoc.location = url + '&artwork=2';
					} else {
						thisdoc.location = url + '&artwork=2&start=';
					}

				} else {
					Utils.setCookie( 'SlimServer-albumView', "" );

					if (thisdoc.location.href.indexOf('start') == -1) {
						thisdoc.location = url + '&artwork=0';
					} else {
						thisdoc.location = url + '&artwork=0&start=';
					}
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

