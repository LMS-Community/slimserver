Browse = function(){
	return {
		init : function(){
			var el;

			// jump to anchor
			var anchor = document.location.href.match(/#(.*)$/)
			if (anchor && anchor[1]) {
				if (el = Ext.get('anchor' + anchor[1]))
					el.scrollIntoView('browsedbList');
			}

			// Album view selector
			if (Ext.get('viewSelect')) {
				var viewMode = (Utils.getCookie('SqueezeCenter-albumView') && Utils.getCookie('SqueezeCenter-albumView').match(/[012]/) ? Utils.getCookie('SqueezeCenter-albumView') : '0');
				var menu = new Ext.menu.Menu({
					items: [
						new Ext.menu.CheckItem({
							text: strings['switch_to_list'],
							cls: 'albumList',
							handler: function(){ Browse.toggleGalleryView(2) },
							group: 'viewMode',
							checked: viewMode == 2
						}),
						new Ext.menu.CheckItem({
							text: strings['switch_to_extended_list'],
							cls: 'albumXList',
							handler: function(){ Browse.toggleGalleryView(0) },
							group: 'viewMode',
							checked: viewMode == 0
						}),
						new Ext.menu.CheckItem({
							text: strings['switch_to_gallery'],
							cls: 'albumListGallery',
							handler: function(){ Browse.toggleGalleryView(1) },
							group: 'viewMode',
							checked: viewMode == 1
						})
					],
					shadow: Ext.isGecko && Ext.isMac ? true : 'sides'
				});

				if (orderByList) {
					menu.add(
							'-',
							'<span class="menu-title">' + strings['sort_by'] + '...</span>'
					);

					var sortOrder = Utils.getCookie('SqueezeCenter-orderBy');
					for (order in orderByList) {
						menu.add(new Ext.menu.CheckItem({
							text: order,
							handler: function(ev){
								Browse.chooseAlbumOrderBy(orderByList[ev.text]);
							},
							checked: (orderByList[order] == sortOrder),
							group: 'sortOrder'
						}));
					}
				}


				new Ext.SplitButton('viewSelect', {
					icon: webroot + 'html/images/albumlist' + viewMode  + '.gif',
					cls: 'x-btn-icon',
					menu: menu,
					handler: function(ev){
						if(this.menu && !this.menu.isVisible()){
							this.menu.show(this.el, this.menuAlign);
						}
						this.fireEvent('arrowclick', this, ev);
					},
					tooltip: strings['display_options'],
					arrowTooltip: strings['display_options'],
					tooltipType: 'title'
				});
			}
		},

		gotoAnchor : function(anchor){
			var el = Ext.get('anchor' + anchor);
			if (el)
				el.scrollIntoView('browsedbList');
		},

		toggleGalleryView : function(artwork){
			var url = document.location.href;
			url = url.replace(/&artwork=\w*/gi, '');
			var target = url.match(/(#.*)$/);
			url = url.replace(/#.*$/, '');

			if (artwork == 1) {
				Utils.setCookie( 'SqueezeCenter-albumView', "1" );
				url = url + '&artwork=1';
			}

			else if (artwork == 2) {
				Utils.setCookie( 'SqueezeCenter-albumView', "2" );
				url = url + '&artwork=2';
			}

			else {
				Utils.setCookie( 'SqueezeCenter-albumView', "" );
				url = url + '&artwork=0';
			}

			if (target && target[0].match(/^#/))
				url = url + target[0];

			window.location.href = url;
		},

		chooseAlbumOrderBy: function(option) {
			var url = document.location.href;
			url = url.replace(/&orderBy=[\w\.,]*/ig, '');
			var target = url.match(/(#.*)$/);
			url = url.replace(/#.*$/, '');

			if (option)
				url = url + '&orderBy=' + option;

			if (target && target[0].match(/^#/))
				url = url + target[0];

			Utils.setCookie('SqueezeCenter-orderBy', option);
			window.location.href = url;
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

