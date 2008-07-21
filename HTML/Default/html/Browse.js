Browse = {
	init : function(){
		var el;

		// jump to anchor
		var anchor = location.hash.replace(/#/,'');
		if (anchor)
			this.gotoAnchor(anchor);

		// Album view selector
		if (Ext.get('viewSelect')) {
			var viewMode = (SqueezeJS.getCookie('SqueezeCenter-albumView') 
								&& SqueezeJS.getCookie('SqueezeCenter-albumView').match(/[012]/) 
								? SqueezeJS.getCookie('SqueezeCenter-albumView') : '0');

			// we don't have gallery view in playlist mode
			if (!SqueezeJS.string('switch_to_gallery'))
				viewMode = (viewMode == 1 ? 0 : viewMode);

			var menu = new Ext.menu.Menu({
				items: [
					new Ext.menu.CheckItem({
						text: SqueezeJS.string('switch_to_list'),
						cls: 'albumList',
						handler: function(){ Browse.toggleGalleryView(2) },
						group: 'viewMode',
						checked: viewMode == 2
					}),
					new Ext.menu.CheckItem({
						text: SqueezeJS.string('switch_to_extended_list'),
						cls: 'albumXList',
						handler: function(){ Browse.toggleGalleryView(0) },
						group: 'viewMode',
						checked: viewMode == 0
					})
				]
			});

			if (SqueezeJS.string('switch_to_gallery'))
				menu.add(new Ext.menu.CheckItem({
					text: SqueezeJS.string('switch_to_gallery'),
					cls: 'albumListGallery',
					handler: function(){ Browse.toggleGalleryView(1) },
					group: 'viewMode',
					checked: viewMode == 1
				}));

			if (orderByList) {
				menu.add(
						'-',
						'<span class="menu-title">' + SqueezeJS.string('sort_by') + '...</span>'
				);

				var sortOrder = SqueezeJS.getCookie('SqueezeCenter-orderBy');
				for (order in orderByList) {
					menu.add(new Ext.menu.CheckItem({
						text: order,
						handler: function(ev){
							this.chooseAlbumOrderBy(orderByList[ev.text]);
						},
						scope: this,
						checked: (orderByList[order] == sortOrder),
						group: 'sortOrder'
					}));
				}
			}

			new Ext.SplitButton({
				renderTo: 'viewSelect',
				icon: webroot + 'html/images/albumlist' + viewMode  + '.gif',
				cls: 'x-btn-icon',
				menu: menu,
				handler: function(ev){
					if(this.menu && !this.menu.isVisible()){
						this.menu.show(this.el, this.menuAlign);
					}
					this.fireEvent('arrowclick', this, ev);
				},
				tooltip: SqueezeJS.string('display_options'),
				arrowTooltip: SqueezeJS.string('display_options'),
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
			SqueezeJS.setCookie( 'SqueezeCenter-albumView', "1" );
			params += '&artwork=1';
		}

		else if (artwork == 2) {
			SqueezeJS.setCookie( 'SqueezeCenter-albumView', "2" );
			params += '&artwork=2';
		}

		else {
			SqueezeJS.setCookie( 'SqueezeCenter-albumView', "" );
			params += '&artwork=0';
		}

		location.search = params;
	},

	chooseAlbumOrderBy: function(option) {
		var params = location.search;
		params = params.replace(/&orderBy=[\w\.,]*/ig, '');

		if (option)
			params += '&orderBy=' + option;

		SqueezeJS.setCookie('SqueezeCenter-orderBy', option);
		location.search = params;
	},

	initPlaylistEditing: function(id){
		new SqueezeJS.UI.Sortable({
			el: 'browsedbList',
			selector: '#browsedbList div.draggableSong',
			highlighter: Highlighter,
			onDropCmd: function(sourcePos, targetPos) {
				SqueezeJS.Controller.request({
					params: [ '', [
						'playlists',
						'edit',
						'playlist_id:' + id,
						'cmd:move',
						'index:' + sourcePos,
						'toindex:' + targetPos
					]]
				});
			}
		})
	}
};

Ext.onReady(Browse.init, Browse, true);

