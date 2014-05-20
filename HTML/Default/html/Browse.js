Browse = {
	init : function(){
		var el;

		// jump to anchor
		var anchor = location.hash.replace(/#/,'');
		if (anchor)
			this.gotoAnchor(anchor);

		// Album view selector
		if (Ext.get('viewSelect')) {
			var viewMode = (SqueezeJS.getCookie('Squeezebox-albumView') 
								&& SqueezeJS.getCookie('Squeezebox-albumView').match(/[012]/) 
								? SqueezeJS.getCookie('Squeezebox-albumView') : '0');

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

				var sortOrder = SqueezeJS.getCookie('Squeezebox-orderBy');
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

			new SqueezeJS.UI.SplitButton({
				renderTo: 'viewSelect',
				icon: webroot + 'html/images/albumlist' + viewMode  + '.gif',
				cls: 'x-btn-icon',
				menu: menu,
				arrowTooltip: SqueezeJS.string('display_options')
			});
		}
		
		if (LiveSearch)
			LiveSearch.init();
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
			SqueezeJS.setCookie( 'Squeezebox-albumView', "1" );
			params += '&artwork=1';
		}

		else if (artwork == 2) {
			SqueezeJS.setCookie( 'Squeezebox-albumView', "2" );
			params += '&artwork=2';
		}

		else {
			SqueezeJS.setCookie( 'Squeezebox-albumView', "" );
			params += '&artwork=0';
		}

		location.search = params;
	},

	chooseAlbumOrderBy: function(option) {
		var params = location.search;
		params = params.replace(/&orderBy=[\w\.,]*/ig, '');

		if (option)
			params += '&orderBy=' + option;

		SqueezeJS.setCookie('Squeezebox-orderBy', option);
		location.search = params;
	},

	initPlaylistEditing: function(id, start){
		new SqueezeJS.UI.Sortable({
			el: 'browsedbList',
			selector: '#browsedbList div.draggableSong',
			highlighter: Highlighter,
			onDropCmd: function(sourcePos, targetPos) {
				sourcePos = sourcePos + start;
				targetPos = targetPos + start;
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

Browse.XMLBrowser = {
	template: new Ext.Template('{query}action={action}&index={index}&player={player}&sess={sess}&start={start}'),
	
	playLink: function(query, index, sess) {
		this._playAddLink('play', query, index, sess, SqueezeJS.string('connecting_for'));
	},
	
	playAllLink: function(query, index, sess) {
		this._playAddLink('playall', query, index, sess, SqueezeJS.string('connecting_for'));
	},
	
	addLink: function(query, index, sess) {
		this._playAddLink('add', query, index, sess);
	},
	
	addAllLink: function(query, index, sess) {
		this._playAddLink('addall', query, index, sess);
	},
	
	insertLink: function(query, index, sess) {
		this._playAddLink('insert', query, index, sess);
	},
	
	removeLink: function(query, index, sess) {
		this._playAddLink('remove', query, index, sess);
	},
	
	_playAddLink: function(action, query, index, sess, showBriefly) {
		this._doRequest(this.template.apply({
				action: action,
				query: query,
				player: encodeURIComponent(SqueezeJS.getPlayer()),
				index: index,
				sess: sess
			}), 
			true,
			showBriefly
		);
	},
		
	toggleFavorite: function(self, index, start, sess) {
		var img = Ext.get(self).child('img');
		var action = 'favadd';
		
		if (img.dom.src.match(/remove/)) {
			img.dom.src = img.dom.src.replace(/_remove/, '');
			action = 'favdel';
		}
		else {
			img.dom.src = img.dom.src.replace(/\.gif/, '_remove.gif');
		}
		
		this._doRequest(this.template.apply({
				action: action,
				player: encodeURIComponent(SqueezeJS.getPlayer()),
				index: index,
				start: start,
				sess: sess
			})
		);
	},

	_doRequest: function(query, refreshStatus, showBriefly) {
		SqueezeJS.UI.setProgressCursor();
		SqueezeJS.Controller.urlRequest(
			location.pathname + '?' + query,
			refreshStatus,
			showBriefly
		);
	}
};