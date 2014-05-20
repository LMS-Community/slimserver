LiveSearch = {
	init: function() {
		var input = Ext.get('headerSearchInput');
		var button = Ext.get('headerSearchBtn');

		if (input && button) {
			button.on({
				mouseover: function(){
					input.setDisplayed(true);
					input.focus();
				}
			});

			if (!hideSearchTimer)
				hideSearchTimer = new Ext.util.DelayedTask();
			
			input.on({
				click: function() { hideSearchTimer.cancel(); },
				focus: function() { hideSearchTimer.cancel(); },
				blur: function(){ hideSearchTimer.delay(2000); }
			});

			sinput = new Ext.form.TextField({
				applyTo: input,
				validationDelay: 100,
				validateOnBlur: false,
				selectOnFocus: true,

				searchMenu: new Ext.menu.Menu({
					width: 200,
					maxHeight: document.height - 300,
					items: [],
					show: function() {
						if (!this.el)
							this.render();

						var xy = [input.getX(), input.getY() + input.getHeight()];

						// set the position so we can figure out the constrain value.
						this.el.setXY(xy);
						//constrain the value, keep the y coordinate the same
						xy[1] = this.constrainScroll(xy[1]);
						xy = [this.el.adjustForConstraints(xy)[0], xy[1]];

						this.el.setXY(xy);
						this.el.show();
						Ext.menu.Menu.superclass.onShow.call(this);
						if(Ext.isIE){
							// internal event, used so we don't couple the layout to the menu
							this.fireEvent('autosize', this);
							if (!Ext.isIE8){
								this.el.repaint();
							}
						}
						this.hidden = false;
						this.fireEvent('show', this);
					},

					links : {
						track : new Ext.Template( webroot + 'songinfo.html?player={player}&item={id}'),
						album : new Ext.Template( webroot + 'clixmlbrowser/clicmd=browselibrary+items&mode=albums&linktitle=' + SqueezeJS.string('album') + '%20({title})&album_id={id}&player={player}/index.html?index=0'),
						contributor : new Ext.Template( webroot + 'clixmlbrowser/clicmd=browselibrary+items&mode=albums&linktitle=' + SqueezeJS.string('artist') + '%20({title})&artist_id={id}&player={player}/'),
						search : new Ext.Template( webroot + 'clixmlbrowser/clicmd=browselibrary+items&linktitle=' + SqueezeJS.string('search') + '&mode=search/index.html?player={player}&index={id}&submit=Search&q={title}')
					},
					
					listeners: {
						click: function(self, menuItem, e) {
							var type;
							if (menuItem.track_id) {
								type = 'track';
							}
							else if (menuItem.album_id) {
								type = 'album';
							}
							else if (menuItem.contributor_id) {
								type = 'contributor';
							}
							else if (menuItem.search_id != null) {
								type = 'search';
							}
							
							if (!type || !self.links[type]) {
								return;
							}
							
							location = self.links[type].apply({
								id: menuItem.track_id || menuItem.album_id || menuItem.contributor_id || menuItem.search_id,
								title: encodeURIComponent(menuItem.search_id != null ? input.dom.value : menuItem.text),
								player: SqueezeJS.getPlayer()
							});
						}
					}
				}),

				validator: function(value){
					if (value.length > 0) {
						SqueezeJS.Controller.request({
							params: [ '', [ 'search', 0, 5, 'term:' + value, 'extended:1' ]],
							success: function(response){
								this.searchMenu.removeAll();
								
								if (response && response.responseText) {
									response = Ext.util.JSON.decode(response.responseText);
									var result = response.result;
									
									if (result.contributors_loop) {
										if (this.searchMenu.items.length > 0)
											this.searchMenu.addItem('-');
										
										this.searchMenu.addItem({
											text: '<b>' + SqueezeJS.string('artists') + '...</b>',
											icon: '/html/images/b_search.gif',
											search_id: 0
										});
										
										Ext.each(result.contributors_loop, function(item, index, allItems) {
											this.searchMenu.addItem({
												text: item.contributor,
												contributor_id: item.contributor_id
											});
										}, this);
									}
									
									if (result.albums_loop) {
										if (this.searchMenu.items.length > 0)
											this.searchMenu.addItem('-');
										
										this.searchMenu.addItem({
											text: '<b>' + SqueezeJS.string('albums') + '...</b>',
											icon: '/html/images/b_search.gif',
											search_id: 1
										});
										
										Ext.each(result.albums_loop, function(item, index, allItems) {
											this.searchMenu.addItem({
												text: item.album,
												icon: '/music/' + (item.artwork || 0) + '/cover_50x50_o',
												album_id: item.album_id
											});
										}, this);
									}
									
									if (result.tracks_loop) {
										if (this.searchMenu.items.length > 0)
											this.searchMenu.addItem('-');
										
										this.searchMenu.addItem({
											text: '<b>' + SqueezeJS.string('songs') + '...</b>',
											icon: '/html/images/b_search.gif',
											search_id: 2
										});
										
										Ext.each(result.tracks_loop, function(item, index, allItems) {
											this.searchMenu.addItem({
												text: item.track,
												icon: '/music/' + (item.coverid || 0) + '/cover_50x50_o',
												track_id: item.track_id
											});
										}, this);
									}
									
									if (this.searchMenu.items.length <= 0) {
										this.searchMenu.addItem({
											text: '<b>' + SqueezeJS.string('no_search_results') + '</b>'
										});
									}

									this.searchMenu.show();
								}
							},
							scope: this
						});
					}

					return true;
				},
				
				scope: this,

				// overwrite default filter to ignore key modifiers
				filterValidation : function(e){
					if ((!e.isNavKeyPress() && !e.isSpecialKey()) || e.getKey() == e.BACKSPACE) {
						this.validationTask.delay(this.validationDelay);
					}
				},
				
				listeners: {
					specialkey: function(field, e) {
						if (e.getKey() == e.DOWN) {
							this.searchMenu.focus();
						}
					}
				}
			});

			hideSearchTimer = new Ext.util.DelayedTask(function(){
				if (sinput && sinput.searchMenu && sinput.searchMenu.isVisible()) {
					hideSearchTimer.delay(2000);
				} 
				else {
					input.setDisplayed(false);
				}
			});
			
			SqueezeJS.loadStrings(['ARTISTS', 'ARTIST', 'ALBUMS', 'ALBUM', 'SONGS', 'NO_SEARCH_RESULTS', 'SEARCH']);
		}
	}
};