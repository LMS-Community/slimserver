Browse = function(){
	return {
		init : function(){
			// jump to anchor
			anchor = document.location.href.match(/#(.*)$/)
			if (anchor && anchor[1]) {
				if (el = Ext.get('anchor' + anchor[1]))
					el.scrollIntoView('browsedbList');
			}

			// Album view selector
			if (Ext.get('viewSelect')) {
				menu = new Ext.menu.Menu({
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
				});
				
				if (orderByList) {
					menu.add(
						'-', 
						{ text: strings['sort_by'] + '...', id: 'sortTitle' }
					);
					menu.items.get('sortTitle').disable();
				
					for (order in orderByList) {
						menu.add({
							text: order,
							handler: function(ev){
								Browse.chooseAlbumOrderBy(orderByList[ev.text]);
							}
						});
					}
				}
			
			
				new Ext.SplitButton('viewSelect', {
					icon: webroot + 'html/images/albumlist' + (Utils.getCookie('SlimServer-albumView') && Utils.getCookie('SlimServer-albumView').match(/[012]/) ? Utils.getCookie('SlimServer-albumView') : '0') + '.png',
					cls: 'x-btn-icon',
					menu: menu,
					handler: function(ev){
						if(this.menu && !this.menu.isVisible()){
							this.menu.show(this.el, this.menuAlign);
						}
						this.fireEvent('arrowclick', this, ev);
					},
					arrowTooltip: strings['sort_by'] + '...',
					tooltipType: 'title'
				});
			}
		},
		
		gotoAnchor : function(anchor){
			if (el = Ext.get('anchor' + anchor))
				el.scrollIntoView('browsedbList');
		},

		toggleGalleryView : function(artwork){
			url = document.location.href;
			url = url.replace(/&artwork=./, '');
			target = url.match(/(#.*)$/);
			url = url.replace(/#.*$/, '');

			if (artwork == 1) {
				Utils.setCookie( 'SlimServer-albumView', "1" );
				url = url + '&artwork=1';
			} 
			
			else if (artwork == 2) {
				Utils.setCookie( 'SlimServer-albumView', "2" );
				url = url + '&artwork=2';
			} 
			
			else {
				Utils.setCookie( 'SlimServer-albumView', "" );
				url = url + '&artwork=0';
			}

			if (target && target[0].match(/^#/))
				url = url + target[0];
			
			window.location.href = url;
		},

		chooseAlbumOrderBy: function(option) {
			Utils.setCookie('SlimServer-orderBy', option);
			window.location.href = orderByUrl + (option ? '&orderBy=' + option : '') ;
		}

	};
}();

Ext.EventManager.onDocumentReady(Browse.init, Browse, true);

// legacy calls for shared code...
function toggleGalleryView(artwork) {
	Browse.toggleGalleryView(artwork)
}

function chooseAlbumOrderBy(value, option) {
	Browse.chooseAlbumOrderBy(option);
}

