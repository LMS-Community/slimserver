Browse = function(){
	return {
		init : function(){
			var el;

			// jump to anchor
			var anchor = location.hash.replace(/#/,'');
			if (anchor) {
				this.gotoAnchor(anchor);
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
			var pel = Ext.get('browsedbList');

			if (el && pel){
				pel.scroll('down', 10000, false);
				el.scrollIntoView(pel);
			}
		},

		toggleGalleryView : function(artwork){
			var params = location.search;
			params = params.replace(/&artwork=\w*/gi, '');

			if (artwork == 1) {
				Utils.setCookie( 'SqueezeCenter-albumView', "1" );
				params += '&artwork=1';
			}

			else if (artwork == 2) {
				Utils.setCookie( 'SqueezeCenter-albumView', "2" );
				params += '&artwork=2';
			}

			else {
				Utils.setCookie( 'SqueezeCenter-albumView', "" );
				params += '&artwork=0';
			}

			location.search = params;
		},

		chooseAlbumOrderBy: function(option) {
			var params = location.search;
			params = params.replace(/&orderBy=[\w\.,]*/ig, '');

			if (option)
				params += '&orderBy=' + option;

			Utils.setCookie('SqueezeCenter-orderBy', option);
			location.search = params;
		}

	};
}();

Ext.EventManager.onDocumentReady(Browse.init, Browse, true);

