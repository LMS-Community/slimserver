Main = function(){
	var layout;

	return {
		init : function(){
			Ext.UpdateManager.defaults.indicatorText = '<div class="loading-indicator">' + strings['loading'] + '</div>';

			layout = new Ext.BorderLayout('mainbody', {
				north: {
					split:false,
					initialSize: 45
				},
				south: {
					split:false,
					initialSize: 40
				},
				center: {
					autoScroll: false
				}
			});

			layout.beginUpdate();
			layout.add('north', new Ext.ContentPanel('header', {fitToFrame:true, fitContainer:true}));
			layout.add('south', new Ext.ContentPanel('footer', {fitToFrame:true, fitContainer:true}));
			layout.add('center', new Ext.ContentPanel('main', {fitToFrame:true, fitContainer:true}));

			Player.init();
			Playlist.init();
			PlayerChooser.init();

			Ext.EventManager.onWindowResize(this.onResize, layout);
			Ext.EventManager.onDocumentReady(this.onResize, layout, true);

			var el;
			if (el = Ext.get('scanWarning'))
				el.setVisibilityMode(Ext.Element.DISPLAY);

			if (el = Ext.get('newVersion'))
				el.setVisibilityMode(Ext.Element.DISPLAY);

			layout.endUpdate();

			// load home page with "random" parameter to prevent caching issues at startup
			Ext.get('leftcontent').dom.src = webroot + 'home.html?player=' + player + '&amp;_dc=' + (new Date().getTime());

			Ext.QuickTips.init();
			Ext.get('loading').hide();
			Ext.get('loading-mask').hide();

			this.onResize();
		},


		// scan progress status updates
		getScanStatus : function(){
			Utils.processCommand({
				params: [ '', ['serverstatus'] ],
				success: this.scanUpdate,
				scope: this
			});
		},

		scanUpdate : function (response){
			var el, total;

			if (response && response.responseText) {
				var responseText = Ext.util.JSON.decode(response.responseText);

				// only continue if we got a result and player
				if (responseText.result) {
					var result = responseText.result;

					if (result.rescan) {
						if (el = Ext.get('scanWarning'))
							el.show();

						if ((el = Ext.get('progressInfo')) && result.progresstotal)
							el.show();

						if (total = Ext.get('progressTotal')) {
							Ext.get('progressName').update(result.progressname);
							Ext.get('progressDone').update(result.progressdone) || 0;
							total.update(result.progresstotal || 0);
						}
					}
					else {
						if (el = Ext.get('scanWarning'))
							el.hide();
					}
				}
			}
		},

		checkScanStatus : function(response){
			var el;

			if (response.result && response.result.rescan) {
				if (el = Ext.get('newVersion'))
					el.hide();
				Main.getScanStatus();
			}
			else {
				if (el = Ext.get('scanWarning'))
					el.hide();
				if (el = Ext.get('progressInfo'))
					el.hide();
			}
		},

		// resize panels, folder selectors etc.
		onResize : function(){
			var offset, dimensions, right, left, pl;

			// some browser dependant offsets... argh...
			offset = new Array();
			offset['bottom'] = 30;
			offset['playlistbottom'] = 34;
			offset['rightpanel'] = 23;

			if (Ext.isIE) {
				if (Ext.isIE7) {
					offset['playlistbottom'] = 41;
				}
				else {
					offset['bottom'] = 27;
				}
			}
			else if (Ext.isOpera) {
				offset['bottom'] = 28;
				offset['playlistbottom'] = 37;
			}

			dimensions = new Array();
			dimensions['maxHeight'] = Ext.get(document.body).getHeight();
			dimensions['footer'] = Ext.get('footer').getHeight();
			dimensions['colWidth'] = Math.floor((Ext.get(document.body).getWidth() - 6*5) / 2);
			dimensions['colHeight'] = dimensions['maxHeight'] - Ext.get('leftpanel').getTop() - dimensions['footer'] - offset['bottom'];

			right = Ext.get('rightcontent');
			left = Ext.get('leftcontent');

			Ext.get('mainbody').setHeight(dimensions['maxHeight'] - 10);

			// left column
			left.setHeight(dimensions['colHeight']);
			left.setWidth(dimensions['colWidth']);

			// IE7 wouldn't overflow without an absolute width
			if (Ext.isIE)
				Ext.get('ctrlCurrentSongInfoCollapsed').setWidth(dimensions['colWidth'] - 165 + (Ext.isIE7 * 5));

			// right column
			right.setHeight(dimensions['colHeight'] - offset['rightpanel']);
			Ext.get('playerControlPanel').setWidth(dimensions['colWidth'] - 15);

			// playlist field
			if (pl = Ext.get('playList')) {
				pl.setHeight(dimensions['colHeight'] - pl.getTop() + offset['playlistbottom']);
			}

			Player.progressBar('ctrlProgress');

			try { this.layout(); }
			catch(e) {}
		}
	};
}();


PlayerChooser = function(){
	var playerMenu;
	var playerDiscoveryTimer;
	var playerNeedsUpgrade;
	var playerList = new Ext.util.MixedCollection();

	return {
		init : function(){
			playerMenu = new Ext.SplitButton('playerChooser', {
				handler: function(ev){
					if(this.menu && !this.menu.isVisible()){
						this.menu.show(this.el, this.menuAlign);
					}
					this.fireEvent('arrowclick', this, ev);
				},
				menu: new Ext.menu.Menu({shadow: Ext.isGecko && Ext.isMac ? true : 'sides'}),
				tooltip: strings['choose_player'],
				arrowTooltip: strings['choose_player'],
				tooltipType: 'title'
			});
			playerDiscoveryTimer = new Ext.util.DelayedTask(this.update, this);

			this.update();
		},

		update : function(){
			var el;

			Utils.processCommand({
				params: [ '', [ "serverstatus", 0, 99 ] ],
				scope: this,

				success: function(response){
					if (response && response.responseText) {
						responseText = Ext.util.JSON.decode(response.responseText);

						playerMenu.menu.removeAll();
						playerMenu.menu.add(
							'<span class="menu-title">' + strings['choose_player'] + '</span>'
						);


						// let's set the current player to the first player in the list
						if (responseText.result && 
							(responseText.result['player count'] > 0 || responseText.result.sn_players_loop)) {
							var playerInList = false;
							var el;

							playerList = new Ext.util.MixedCollection();

							for (x=0; x < responseText.result['player count']; x++) {
								var currentPlayer = false;
								var playerInfo = responseText.result.players_loop[x];

								// mark the current player as selected
								if (playerInfo.playerid == playerid) {
									currentPlayer = true;
									playerInList = true;
									playerMenu.setText(playerInfo.name);

									if (el = Ext.get('ctrlPower'))
										el.setVisible(playerInfo.canpoweroff);

									// display information if the player needs a firmware upgrade
									if (playerInfo.player_needs_upgrade || playerNeedsUpgrade) {
										playerNeedsUpgrade = playerInfo.player_needs_upgrade; 
										Playlist.load();
									}
								}

								// add the players to the list to be displayed in the synch dialog
								playerList.add(
									playerInfo.playerid,
									playerInfo.name
								);

								playerMenu.menu.add(
									new Ext.menu.CheckItem({
										text: playerInfo.name,
										value: playerInfo.playerid,
										canpoweroff: playerInfo.canpoweroff,
										cls: 'playerList',
										group: 'playerList',
										checked: playerInfo.playerid == playerid,
										handler: PlayerChooser.selectPlayer
									})
								);
							}

							// add alist of player connected to SQN, if available
							if (responseText.result.sn_players_loop) {
								var first = true;
								
								for (x=0; x < responseText.result.sn_players_loop.length; x++) {
									var playerInfo = responseText.result.sn_players_loop[x];

									// don't display players which are already connected to SC
									// this is to prevent double entries right after a player has switched
									if (! playerList.get(playerInfo.playerid)) {
										if (first) {
											playerMenu.menu.add(
												'-',
												'<span class="menu-title">' + strings['squeezenetwork'] + '</span>'
											);
											first = false;
										}

										playerMenu.menu.add(
											new Ext.menu.Item({
												text: playerInfo.name,
												value: playerInfo.id,
												cls: 'playerList',
												handler: PlayerChooser.switchSQNPlayer
											})
										);
									}
								}
							}

							// if there's more than one player, add the sync option
							playerMenu.menu.add(
								'-',
								new Ext.menu.Item({
									text: strings['synchronize'] + '...',
									// query the currently synced players and show the dialog
									handler: function(){
										Utils.processPlayerCommand({
											params: ['sync', '?'],
											success: PlayerChooser.showSyncDialog,
											failure: PlayerChooser.showSyncDialog
										});	
									},
									disabled: (playerList.getCount() < 2) 
								})
							);

							if (!playerInList) {
								PlayerChooser.selectPlayer({
									text: responseText.result.players_loop[0].name,
									value: responseText.result.players_loop[0].playerid,
									canpoweroff: responseText.result.players_loop[0].canpoweroff
								});
							}
						}

						else {
							playerMenu.menu.add(
								new Ext.menu.Item({
									text: strings['no_player'] + '..',
									handler: function(){
										var dlg = new Ext.BasicDialog('', {
											autoCreate: true,
											title: strings['no_player'],
											modal: true,
											closable: false,
											collapsible: false,
											width: 500,
											height: 250,
											resizeHandles: 'se'
										});
										dlg.addButton(strings['close'], dlg.destroy, dlg);
										dlg.addKeyListener(27, dlg.destroy, dlg);
										dlg.body.update(strings['no_player_details']);
										dlg.show();
									}
								})
							);

							PlayerChooser.selectPlayer({
								text: '',
								value: '',
								canpoweroff: false
							});
						}

						// display scanning information
						Main.checkScanStatus(responseText);
					}
				}
			});

			// poll more often when there's no player, to show them up as quickly as possible
			playerDiscoveryTimer.delay(player ? 30000 : 10000);
		},

		selectPlayer: function(ev){
			var el;

			playerMenu.setText(ev.text);
			playerid = ev.value;
			player = encodeURI(playerid);

			// set the browser frame to use the selected player
			if (player && frames.browser) {
				frames.browser.location = Utils.replacePlayerIDinUrl(frames.browser.location.href, playerid);
			}

			if (ev.canpoweroff != null && (el = Ext.get('ctrlPower')))
				el.setVisible(ev.canpoweroff);

			Playlist.resetUrl();
			Player.getStatus();
		},

		switchSQNPlayer: function(ev){
			Ext.MessageBox.confirm(
				strings['squeezenetwork'],
				strings['sqn_want_switch'],
				function(btn){
					if (btn == 'yes') {
						Utils.processCommand({ params: ['', ['squeezenetwork', 'disconnect', ev.value ]] });
					}
				}
			);
		},

		showSyncDialog: function(response){
			var responseText = Ext.util.JSON.decode(response.responseText);

			var syncedPlayers = new Array();
			if (responseText.result && responseText.result._sync) {
				syncedPlayers = responseText.result._sync;
			}

			var playerSelection = '<p>' + strings['synchronize_desc'] + '</p><form name="syncgroup" id="syncgroup">';
			var tpl = new Ext.Template('<input type="checkbox" id="{id}" value="{id}" {checked}>&nbsp;{name}<br>');
			tpl.compile();

			// create checkboxes for other players and preselect if synced
			playerList.eachKey(function(id, name){
				if (id && name && id != playerid)
					playerSelection += tpl.apply({
						name: name,
						id: id,
						checked: syncedPlayers.indexOf(id) >= 0 ? 'checked' : ''
					});
			});
			playerSelection += '</form>';

			var dlg = new Ext.BasicDialog('', {
				autoCreate: true,
				title: strings['synchronize'],
				modal: true,
				closable: false,
				collapsible: false,
				width: 500,
				height: 200 + playerList.getCount() * 13,
				resizeHandles: 'se'
			});

			dlg.addButton(strings['execute'], function(){ PlayerChooser.sync(syncedPlayers, dlg) }, dlg);
			dlg.addButton(strings['close'], dlg.destroy, dlg);
			dlg.addKeyListener(27, dlg.destroy, dlg);

			dlg.body.update(playerSelection);
			dlg.show();
		},

		sync: function(syncedPlayers, dlg){
			var players = Ext.query('input', Ext.get('syncgroup').dom);

			for(var i = 0; i < players.length; i++) {
				// sync if not synced yet
				if (players[i].checked && syncedPlayers.indexOf(players[i].id) < 0)
					Utils.processCommand({ params: [ players[i].id, [ 'sync', playerid ] ] });

				// unsync if no longer checked
				else if (syncedPlayers.indexOf(players[i].id) >= 0 & !players[i].checked)
					Utils.processCommand({ params: [ players[i].id, [ 'sync', '-' ] ] });
			}

			dlg.destroy();
		}
	}
}();


Playlist = function(){
	var unHighlightTimer = new Ext.util.DelayedTask(Utils.unHighlight);
	var isDragging = false;

	return {
		init : function(){
			// some initialization of the DD class used
			Ext.dd.ScrollManager.register('playList');

			Ext.override(Ext.dd.DDProxy, {

				// highlight a copy of the dragged item to move with the mouse pointer
				startDrag: function(x, y) {
					var dragEl = Ext.get(this.getDragEl());
					var el = Ext.get(this.getEl());
					Utils.unHighlight();

					dragEl.applyStyles({'z-index':2000});
					dragEl.update(el.dom.innerHTML);
					dragEl.addClass(el.dom.className + ' dd-proxy');

					isDragging = true;
				},

				// disable the default behaviour which would place the dragged element
				// we don't need to place it as it will be moved in onDragDrop
				endDrag: function() {},

				onDragEnter: function(ev, id) {
					var source = Ext.get(this.getEl());
					var target = Ext.get(id);

					if (target && source) {
						if (target.dd.config.position < source.dd.config.position)
							Ext.get(id).addClass('dragUp');
						else
							Ext.get(id).addClass('dragDown');
					}
				},

				onDragOut: function(e, id) {
					Ext.get(id).removeClass('dragUp');
					Ext.get(id).removeClass('dragDown');
				},

				// move the item when dropped
				onDragDrop: function(e, id) {
					var source = Ext.get(this.getEl());
					var target = Ext.get(id);

					if (target && source) {
						var sourcePos = -1;
						var targetPos = -1;

						target.removeClass('dragUp');
						target.removeClass('dragDown');

						// get to know where we come from, where we've gone to
						var items = Ext.query('#playList div.draggableSong');
						for(var i = 0; i < items.length; i++) {
							if (items[i].id == this.id)
								sourcePos = i;
							else if (items[i].id == id)
								targetPos = i;
						}
			
						if (sourcePos >= 0 && targetPos >= 0 && (sourcePos != targetPos)) {
							var plPosition, plStart, el;

							if (sourcePos > targetPos) {
								source.insertBefore(target);
								plPosition = parseInt(target.dd.config.position) - targetPos;
								plStart = targetPos;
							}
							else  {
								source.insertAfter(target);
								plPosition = parseInt(source.dd.config.position) - sourcePos;
								plStart = sourcePos;
							}
							Player.playerControl(['playlist', 'move', source.dd.config.position, target.dd.config.position], true);

							// recalculate the item's number within the playlist
							items = Ext.query('#playList div.draggableSong');
							for(var i = plStart; i < items.length; i++) {
								if (el = Ext.get(items[i]))
									el.dd.config.position = plPosition + i;
							}
						}
					}

					isDragging = false;
				}
			});
		},

		load : function(url, showIndicator){
			var el = Ext.get('playlistPanel');

			if (Ext.get('playList'))
				// unregister event handlers
				Ext.dd.ScrollManager.unregister('playList');
	
			// try to reload previous page if no URL is defined
			var um = el.getUpdateManager();

			if (!url)
				url = um.defaultUrl;

			if (showIndicator)
				el.getUpdateManager().showLoadIndicator = true;

			el.load(
				{
					url: url || webroot + 'playlist.html?ajaxRequest=1&player=' + playerid,
					method: 'GET',
					disableCaching: true
				},
				{},
				this.onUpdated
			);

			um.showLoadIndicator = false;
		},

		clear : function(){
			Player.playerControl(['playlist', 'clear']);
			Playlist.load();							// Bug 5709: force playlist to clear
		},

		save : function(){
			frames.browser.location = webroot + 'edit_playlist.html?player=' + player + '&saveCurrentPlaylist=1';
		},

		resetUrl : function(){
			var el = Ext.get('playlistPanel');
			if (el)
				el.getUpdateManager().setDefaultUrl('');
		},

		onUpdated : function(){
			Main.onResize();

			// shortcut if there's no player
			if (!Ext.get('playlistTab'))
				return;

			// make playlist items draggable
			Ext.dd.ScrollManager.register('playList');

			var items = Ext.DomQuery.select('#playList div.draggableSong');
			for(var i = 0; i < items.length; i++) {
				var item = Ext.get(items[i]);

				var itemNo = item.id.replace(/\D*/, '');

				item.dd = new Ext.dd.DDProxy(items[i], 'playlist', {position: itemNo});
				item.dd.setXConstraint(0, 0);
				item.dd.scroll = false;
				item.dd.scrollContainer = true;
			}

			Playlist.highlightCurrent();

			// playlist name is too long to be displayed
			// try to use it as the Save button's tooltip
			var tooltip = null;
			if (el = Ext.get('currentPlaylistName'))
				tooltip = el.dom.innerHTML;

			if (items.length > 0) {
				Ext.get('playlistToggleArtwork').show();

				new Ext.Button('btnPlaylistClear', {
					cls: 'btn-small',
					text: strings['clear_playlist'],
					icon: webroot + 'html/images/icon_playlist_clear.gif',
					handler: Playlist.clear
				});

				new Ext.Button('btnPlaylistSave', {
					cls: 'btn-small',
					text: strings['save'],
					icon: webroot + 'html/images/icon_playlist_save.gif',
					tooltip: tooltip,
					tooltipType: 'title',
					handler: Playlist.save
				});
			} else {
				Ext.get('playlistToggleArtwork').hide();
			}

			// dragging doesn't survive a reload
			isDragging = false;
		},

		highlight : function(target){
			if (!isDragging) {
				Utils.highlight(target);
				unHighlightTimer.delay(2000);	// remove highlighter after x seconds of inactivity
			}
		},

		highlightCurrent : function(){
			if (el = Ext.get('playList')) {
				var plPos = el.getScroll();
				var plView = el.getViewSize();
				var el = Ext.DomQuery.selectNode('div.selectedItem');

				if (el) {
					el = Ext.get(el);
					if (el.getTop() > plPos.top + plView.height
						|| el.getBottom() < plPos.top)
							el.scrollIntoView('playList');
				}
			}
		},

		control : function(cmd, el) {
			el = Ext.get(el);
			if (el.dd && el.dd.config && el.dd.config.position)
				Player.playerControl(['playlist', cmd, el.dd.config.position])
		},

		showCoverArt : function(){
			Utils.setCookie('SqueezeCenter-noPlaylistCover', 0);
			this.load();
		},

		hideCoverArt : function(){
			Utils.setCookie('SqueezeCenter-noPlaylistCover', 1);
			this.load();
		}
	}
}();

Player = function(){
	var pollTimer;
	var playTimeTimer;
	var playTime = 0;
	var displayElements = new Ext.util.MixedCollection();

	var playerStatus = {
		power: null,
		mode: null,
		current_title: null,
		title: null,
		track: null,
		index: null,
		duration: null,
		timestamp: null,
		dontUpdate: false,
		player: null
	};

	var coverFileSuffix = 'png';
	if (Ext.isIE && ! Ext.isIE7) {
		coverFileSuffix = 'gif';
	}

	return {
		init : function(){
			displayElements.add(new Slim.RewButton('ctrlPrevious', {
 				cls: 'btn-previous',
				minWidth: 28
			}));

			displayElements.add(new Slim.PlayButton('ctrlTogglePlay', {
				cls: 'btn-play',
				minWidth: 51
			}));

			new Slim.Button('ctrlNext', {
				cls: 'btn-next',
				tooltip: strings['next'],
				minWidth: 28,
				scope: this,
				handler: function(){
					if (playerStatus.power)
						this.playerControl(['playlist', 'index', '+1']);
				}
			});

			displayElements.add(new Slim.RepeatButton('ctrlRepeat', {
				minWidth: 34,
				cls: 'btn-repeat-0'
			}));

			displayElements.add(new Slim.ShuffleButton('ctrlShuffle', {
				minWidth: 34,
				cls: 'btn-shuffle-0'
			}));

			new Slim.Button('ctrlVolumeDown', {
				cls: 'btn-volume-decrease',
				tooltip: strings['volumedown'],
				minWidth: 22,
				scope: this,
				handler: function(){
					if (playerStatus.power)
						this.setVolume(1, '-');
				}
			});

			displayElements.add(new Slim.VolumeBar('ctrlVolume'));

			new Slim.Button('ctrlVolumeUp', {
				cls: 'btn-volume-increase',
				tooltip: strings['volumeup'],
				minWidth: 22,
				scope: this,
				handler: function(){
					if (playerStatus.power)
						this.setVolume(1, '+');
				}
			});

			displayElements.add(new Slim.PowerButton('ctrlPower', {
				cls: 'btn-power',
				minWidth: 22
			}));

			if (Ext.get('ctrlUndock')) {
				new Slim.Button('ctrlUndock', {
					cls: 'btn-undock',
					tooltip: strings['undock'],
					minWidth: 18,
					scope: this,
					handler: function(){
						window.open(webroot + 'status_header.html', 'playerControl', 'width=500,height=100,status=no,menubar=no,location=no,resizable=yes');
					}
				});
			}

			new Slim.Button('ctrlCollapse', {
				cls: 'btn-collapse-player',
				tooltip: strings['collapse'],
				minWidth: 18,
				scope: this,
				handler: this.collapseExpand
			});

			if (el = Ext.get('ctrlCurrentArt'))
				el.setVisibilityMode(Ext.Element.DISPLAY);

			if (el = Ext.get('expandedPlayerPanel'))
				el.setVisibilityMode(Ext.Element.DISPLAY);

			if (el = Ext.get('collapsedPlayerPanel'))
				el.setVisibilityMode(Ext.Element.DISPLAY);

			if (el = Ext.get('ctrlExpand'))
				el.setVisibilityMode(Ext.Element.DISPLAY);

			if (el = Ext.get('ctrlCollapse'))
				el.setVisibilityMode(Ext.Element.DISPLAY);

			// restore player expansion from cookie
			this.collapseExpand({
				doExpand: (Utils.getCookie('SqueezeCenter-expandPlayerControl') != 'false')
			});

			new Slim.Button('ctrlExpand', {
				cls: 'btn-expand-player',
				tooltip: strings['expand'],
				minWidth: 18,
				scope: this,
				handler: this.collapseExpand
			});

			pollTimer = new Ext.util.DelayedTask(this.getStatus, this);
			playTimeTimer = new Ext.util.DelayedTask(this.updatePlayTime, this);

			this.getStatus();
		},

		updatePlayTime : function(time, totalTime){
			// force 0 for current time when stopped
			if (playerStatus.mode == 'stop')
				time = 0;

			if (! isNaN(time))
				playTime = parseInt(time); //force integer type from results

			var shortTime = Utils.formatTime(playTime);
			var remainingTime = shortTime;

			if (!isNaN(playerStatus.duration) && playerStatus.duration > 0) {
				totalTime = playerStatus.duration;

				if (totalTime > 0 && playTime >= totalTime-1) {
					this.getStatus();
					return;
				}

				remainingTime = '-' + Utils.formatTime(totalTime - playTime); 
				shortTime = Utils.formatTime(playTime) + ' / ' + remainingTime;

				this.progressBar('ctrlProgress', playTime, totalTime);
			}
			else {
				this.progressBar('ctrlProgress', playTime, 0);
				totalTime = '';
			}

			Ext.get('ctrlPlaytime').update(Utils.formatTime(playTime));
			Ext.get('ctrlRemainingTime').update(remainingTime);

			Ext.get('ctrlPlaytimeCollapsed').update(shortTime);

			// only increment interim value if playing
			if (playerStatus.mode == 'play')
				playTime += 0.5;

			playTimeTimer.delay(500);
		},

		progressBar : function(el, time, totalTime){
			var left, right, el;

			var progress = Ext.get(el);
			var max = progress.getWidth() - 12; // total of left/right/indicator width

			// if we don't know the total play time, just put the indicator in the middle
			if (!totalTime) {
				left = 0;
			}

			// calculate left/right percentage
			else {
				left = Math.max(
						Math.min(
							Math.floor(time / totalTime * max)
						, max)
					, 1);
			}

			// do the DOM lookups before replacing to reduce flicker
			var remaining = Ext.get(Ext.DomQuery.selectNode('.progressFillRight', progress.dom));
			var playtime = Ext.get(Ext.DomQuery.selectNode('.progressFillLeft', progress.dom));
			remaining.setWidth(max - left);
			playtime.setWidth(left);
		},

		updateStatus : function(response) {
			if (!(response && response.responseText))
				return;

			var responseText = Ext.util.JSON.decode(response.responseText);

			// only continue if we got a result and player
			if (!(responseText.result && responseText.result.player_connected))
				return;

			var el;
			var result = responseText.result;

			// send update signal to all displayed elements and buttons
			// some buttons will change state depending on content (eg. pandora voting, player state etc.)
			displayElements.each(function(item){
				item.fireEvent('dataupdate', result);
			});

			if (this.needUpdate(result) && Ext.get('playList'))
					Playlist.load();

			if (result.playlist_tracks > 0) {
				
				var infoLink = result.playlist_loop[0].info_link || 'songinfo.html';

				var currentArtist, currentAlbum;
				var currentTitle = '<a href="' + webroot + infoLink + '?player=' + player + '&amp;item=' + result.playlist_loop[0].id + '" target="browser">'
					+
					(result.current_title ? result.current_title : (
						(result.playlist_loop[0].disc ? result.playlist_loop[0].disc + '-' : '')
						+
						(result.playlist_loop[0].tracknum ? result.playlist_loop[0].tracknum + ". " : '')
						+
						result.playlist_loop[0].title
					))
					+
					'</a>';

				Ext.get('ctrlCurrentTitle').update(currentTitle);

				Ext.get('ctrlSongCount').update(result.playlist_tracks);
				Ext.get('ctrlPlayNum').update(parseInt(result.playlist_cur_index) + 1);

				if (result.playlist_loop[0].artist) {
					var contributors = result.playlist_loop[0].artist.split(',');
					var ids = result.playlist_loop[0].artist_ids ? result.playlist_loop[0].artist_ids.split(',') : new Array();
					var artist, id;

					currentArtist = '';						

					for (var i = 0; i < contributors.length; i++) {
						artist = contributors[i].replace(/^\w/, '');

						if (currentArtist)
							currentArtist += ', ';

						currentArtist += ids[i]
								? '<a href="' + webroot + 'browsedb.html?hierarchy=contributor,album,track&amp;contributor.id=' + ids[i] + '&amp;level=1&amp;player=' + player + '" target="browser">' + contributors[i] + '</a>'
								: contributors[i];
					}

					Ext.get('ctrlCurrentArtist').update(currentArtist);

					currentTitle += ' ' + strings['by'] + ' ' + currentArtist;
				}
				else {
					Ext.get('ctrlCurrentArtist').update('');
				}

				if (result.playlist_loop[0].album) {
					currentAlbum = (result.playlist_loop[0].album_id
							? '<a href="' + webroot + 'browsedb.html?hierarchy=album,track&amp;level=1&amp;album.id=' + result.playlist_loop[0].album_id + '&amp;player=' + player + '" target="browser">' + result.playlist_loop[0].album + '</a>'
							: result.playlist_loop[0].album
						)
						+ (result.playlist_loop[0].year > 0 ? ' ('
							+ '<a href="' + webroot + 'browsedb.html?hierarchy=year,album,track&amp;level=1&amp;year.id=' + result.playlist_loop[0].year + '&amp;player=' + player + '" target="browser">' + result.playlist_loop[0].year + '</a>'
						+ ')' : '');

					Ext.get('ctrlCurrentAlbum').update(currentAlbum);

					currentTitle += ' ' + strings['from'] + ' ' + currentAlbum;
				}
				else {
					Ext.get('ctrlCurrentAlbum').update('');
				}

				if (result.playlist_loop[0].bitrate && result.remote) {
					Ext.get('ctrlBitrate').update(
						result.playlist_loop[0].bitrate
						+ (result.playlist_loop[0].type
							? ', ' + result.playlist_loop[0].type
							: ''
						)
					);
				}
				else {
					Ext.get('ctrlBitrate').update('');
				}

				Ext.get('ctrlCurrentSongInfoCollapsed').update(currentTitle);

				if (result.playlist_loop[0].id && (el = Ext.get('ctrlCurrentArt'))) {
						
					var coverart = '<a href="' + webroot + 'browsedb.html?hierarchy=album,track&amp;level=1&amp;album.id=' + result.playlist_loop[0].album_id + '&amp;player=' + player + '" target="browser"><img src="/music/' + result.playlist_loop[0].id + '/cover_96x96_p.' + coverFileSuffix + '"></a>';
					// the bg color must match the qtip's background color, as otherwise the image shows white on white
					var popup    = '<img src="/music/' + result.playlist_loop[0].id + '/cover_250xX_f_e0e8f3.jpg" width="250">';

					if (result.playlist_loop[0].artwork_url) {
						coverart = '<img src="' + result.playlist_loop[0].artwork_url + '" height="96" width="96" />';
						popup    = '<img src="' + result.playlist_loop[0].artwork_url + '" width="250" />';
					}

					el.update(coverart);
					el = el.child('img:first');
					Ext.QuickTips.unregister(el);
					Ext.QuickTips.register({
						target: el,
						text: popup,
						minWidth: 250
					});

					el = Ext.get('nowPlayingIcon').child('img:first');
					Ext.QuickTips.unregister(el);
					Ext.QuickTips.register({
						target: el,
						title: currentTitle,
						text: popup,
						minWidth: 250
					});
				}
			}

			// empty playlist
			else {
				Ext.get('ctrlCurrentTitle').update('');
				Ext.get('ctrlSongCount').update('');
				Ext.get('ctrlPlayNum').update('');
				Ext.get('ctrlBitrate').update('');
				Ext.get('ctrlCurrentArtist').update('');
				Ext.get('ctrlCurrentAlbum').update('');
				Ext.get('ctrlCurrentArt').update('<img src="/music/0/cover_96x96_p.' + coverFileSuffix + '">');
				Ext.get('ctrlCurrentSongInfoCollapsed').update('');
			}

			playerStatus = {
				// if power is undefined, set it to on for http clients
				power: (result.power == null) || result.power,
				mode: result.mode,
				current_title: result.current_title,
				title: result.playlist_tracks > 0 ? result.playlist_loop[0].title : '',
				track: result.playlist_tracks > 0 ? result.playlist_loop[0].url : '',
				index: result.playlist_cur_index,
				duration: result['duration'] || 0,
				timestamp: result.playlist_timestamp,
				player: playerid
			};

			this.updatePlayTime(result.time ? result.time : 0);

			if ((result.power != null) && !result.power) {
				playerStatus.power = 0;
				playTimeTimer.cancel();
			}

			pollTimer.delay(5000);
		},

		getUpdate : function(){
			if (player) {
				Utils.processPlayerCommand({
					params: [ "status", "-", 1, "tags:gABbehldiqtyrSuoKL" ],
					failure: this.updateStatus,
					success: this.updateStatus,
					scope: this
				});

				pollTimer.delay(5000);
			}
		},


		// don't request all status info to minimize performance impact on the server
		getStatus : function() {
			// only poll player state if there is a player connected
			if (player) {
				Utils.processPlayerCommand({
					params: [ "status", "-", 1, "tags:uB" ],

					success: function(response){
						if (response && response.responseText) {
							var responseText = Ext.util.JSON.decode(response.responseText);

							// only continue if we got a result and player
							if (responseText.result && responseText.result.player_connected) {
								var result = responseText.result;

								// check whether we need to update our song info & playlist
								if (this.needUpdate(result)){
									this.getUpdate();
								}
								
								if ((result.power == null) || result.power) {
									playerStatus.duration = result.duration;
									this.updatePlayTime(result.time);
								}
								else {
									playerStatus.power = 0;
									playTimeTimer.cancel();
								}

								displayElements.each(function(item){
									item.fireEvent('dataupdate', result);
								});
							}

							// display scanning information
							Main.checkScanStatus(responseText);
						}
					},

					failure: function(){
						playerid = '';
						player = encodeURI(playerid);
						PlayerChooser.update();
					},

					scope: this
				});

				pollTimer.delay(5000);
			}
		},

		needUpdate : function(result) {				
			// the dontUpdate flag allows us to have the timestamp check ignored for one action 
			// used to prevent updates during d'n'd
			if (playerStatus.dontUpdate) {
				playerStatus.timestamp = result.playlist_timestamp;
				playerStatus.dontUpdate = false;
			}

			var needUpdate = (result.power && (result.power != playerStatus.power));
			needUpdate |= (playerStatus.player != playerid);															// changed player
			needUpdate |= (result.mode != null && result.mode != playerStatus.mode);									// play/paus mode
			needUpdate |= (result.playlist_timestamp != null && result.playlist_timestamp > playerStatus.timestamp);	// playlist: time of last change
			needUpdate |= (result.playlist_cur_index != null && result.playlist_cur_index != playerStatus.index);		// the currently playing song's position in the playlist 
			needUpdate |= (result.current_title != null && result.current_title != playerStatus.current_title);			// title (eg. radio stream)
			needUpdate |= (result.playlist_tracks > 0 && result.playlist_loop[0].title != playerStatus.title);			// songtitle?
			needUpdate |= (result.playlist_tracks > 0 && result.playlist_loop[0].url != playerStatus.track);			// track url
			needUpdate |= (result.playlist_tracks < 1 && playerStatus.track);											// there's a player, but no song in the playlist
			needUpdate |= (result.playlist_tracks > 0 && !playerStatus.track);											// track in playlist changed

			return needUpdate;
		},

		playerControl : function(action, dontUpdate){
			Utils.processPlayerCommand({
				params: action,
				success: function(response){
					playerStatus.dontUpdate = dontUpdate;
					this.getUpdate();

					if (response && response.responseText) {
						response = Ext.util.JSON.decode(response.responseText);
						if (response && response.result && response.result.text)
							Utils.msg(response.result.text);
					}
				},
				scope: this
			});
		},

		collapseExpand : function(ev){
			var doExpand = ev.doExpand == null ? !Utils.getCookie('SqueezeCenter-expandPlayerControl') : ev.doExpand;

			var art = Ext.get('ctrlCurrentArt');

			// work around Safari 2 crasher: resize and hide artwork before hiding surrounding DIV
			if (art && !doExpand) {
				art.setHeight(0);
				art.hide();
			}

			if (el = Ext.get('collapsedPlayerPanel'))
				el.setVisible(!doExpand);

			if (el = Ext.get('expandedPlayerPanel'))
				el.setVisible(doExpand);

			if (el = Ext.get('ctrlCollapse'))
				el.setVisible(doExpand);

			if (el = Ext.get('ctrlExpand'))
				el.setVisible(!doExpand);

			if (art && doExpand) {
				art.setHeight(96);
				art.show();
			}

			Utils.setCookie('SqueezeCenter-expandPlayerControl', doExpand);

			// resize the window if in undocked mode
			if (!Ext.get('ctrlUndock')) {
				var width = Ext.get(document.body).getWidth() + 10;
				var height = doExpand ? 178 : 102;

				if (Ext.isGecko && Ext.isWindows) {
					width += 6;
					height += 15;
				}
				else if (Ext.isGecko && Ext.isLinux) {
					height -= 10;
				}
				else if (Ext.isSafari && doExpand) {
					height -= 10;
				}
				else if (Ext.isGecko && Ext.isMac) {
					height -= 15;
				}
				else if (Ext.isIE7) {
					width += 20;
					height += 60;
				}
				else if (Ext.isIE) {
					width -= 2;
					height += 15;
				}

				window.resizeTo(width, height);
			}

			try { Main.onResize(); }
			catch(e) {}
		},

		setVolume : function(amount, d){
			amount *= 10;
			if (d)
				amount = d + amount;
			this.playerControl(['mixer', 'volume', amount]);
		}
	}
}();


Slim.RewButton = function(renderTo, config){
	Ext.apply(config, {
		tooltip: strings['previous'],
		scope: this,

		handler: function(){
			if (this.power)
				Player.playerControl(['playlist', 'index', '-1']);
		},

		updateHandler: function(result){
			if (Player.needUpdate(result)) {
				if (result.playlist_loop && result.playlist_loop[0] && result.playlist_loop[0].buttons) {
					try {
						this.setDisabled(!result.playlist_loop[0].buttons.rew)
					}
					catch(e){}
				}
				else if (this.disabled)
					this.enable();
			}
		}
	});

	Slim.RewButton.superclass.constructor.call(this, renderTo, config);
};
Ext.extend(Slim.RewButton, Slim.Button);


Slim.PlayButton = function(renderTo, config){
	Ext.apply(config, {
		tooltip: strings['play'],
		scope: this,

		handler: function(){
			if (this.isPlaying) {
				this.updateState(false);
				Player.playerControl(['pause']);
			}
			else {
				this.updateState(true);
				Player.playerControl(['play']);
			}
		},

		updateHandler: function(result){
			var newState = (result.mode == 'play');

			if (this.isPlaying != newState) {
				this.updateState(newState);
			}
		},

		updateState: function(isPlaying){
			var playEl = Ext.get(Ext.DomQuery.selectNode('table:first', Ext.get('ctrlTogglePlay').dom));

			playEl.removeClass(['btn-play', 'btn-pause']);
			playEl.addClass(isPlaying ? 'btn-pause' : 'btn-play');

			this.setTooltip(isPlaying ? strings['pause'] : strings['play']);
			this.isPlaying = isPlaying;
		},

		isPlaying: null
	});

	Slim.PlayButton.superclass.constructor.call(this, renderTo, config);
};
Ext.extend(Slim.PlayButton, Slim.Button);


Slim.RepeatButton = function(renderTo, config){
	Ext.apply(config, {
		tooltip: strings['repeat0'],
		cmd: null,
		scope: this,

		handler: function(){
			if (this.power) {
				if (this.cmd)
					Player.playerControl(this.cmd);
				else
					Player.playerControl(['playlist', 'repeat', (this.state + 1) % 3]);
			} 
		},

		updateHandler: function(result){
			this.cmd = null;

			// see whether the button should be overwritten
			if (this.customHandler(result, 'repeat'))
				this.state = -1;

			else if (result['playlist repeat'] != null && this.state != result['playlist repeat'])
				this.updateState(result['playlist repeat']);

		},

		updateState: function(newState){
			this.state = newState;
			this.setIcon('');
			this.setTooltip(strings['repeat' + this.state]);
			this.setClass('btn-repeat-' + this.state);
		},

		state: 0
	});

	Slim.RepeatButton.superclass.constructor.call(this, renderTo, config);
};
Ext.extend(Slim.RepeatButton, Slim.Button);


Slim.ShuffleButton = function(renderTo, config){
	Ext.apply(config, {
		tooltip: strings['shuffle0'],
		scope: this,

		handler: function(){
			if (this.power) {
				if (this.cmd)
					Player.playerControl(this.cmd);
				else
					Player.playerControl(['playlist', 'shuffle', (this.state + 1) % 3]); 
			}
		},

		updateHandler: function(result){
			this.cmd = null;

			if (this.customHandler(result, 'shuffle'))
				this.state = -1;
			else if (result['playlist shuffle'] != null && this.state != result['playlist shuffle'])
				this.updateState(result['playlist shuffle']);

		},

		updateState: function(newState){
			this.state = newState;
			this.setIcon('');
			this.setTooltip(strings['shuffle' + this.state]);
			this.setClass('btn-shuffle-' + this.state);
		},

		state: 0
	});

	Slim.ShuffleButton.superclass.constructor.call(this, renderTo, config);
};
Ext.extend(Slim.ShuffleButton, Slim.Button);


Slim.VolumeBar = function(renderTo){
	Slim.VolumeBar.superclass.constructor.call(this);

	this.addEvents();
	if (renderTo && (this.el = Ext.get(renderTo))) {
		if (renderTo = this.el.child('img:first'))
			Ext.get(renderTo).on('click', this.onClick, this);
	}

	this.on('dataupdate', this.update, this);
	this.volume = 0
};

Ext.extend(Slim.VolumeBar, Ext.util.Observable, {
	power: 0,

	onClick: function(ev, target) {
		if (!this.power)
			return;

		var el = Ext.get(target);
		if (el) {
			var myStep = el.getWidth()/11;
			var myWidth = el.getWidth() - 2*myStep;
			var myX = ev.getPageX() - el.getX() - (Ext.isGecko * 8) - (Ext.isSafari * 5);

			if (myX <= myStep + (Ext.isSafari * 3))
				volVal = 0;

			else if (myX >= el.getWidth() - myStep)
				volVal = 10;

			else
				volVal = Math.ceil(myX / myStep) - 1;

			this.updateState(volVal*10);
			Player.playerControl(['mixer', 'volume', volVal*10]);
		}
	},

	// update volume bar
	update: function(result){
		if (result['mixer volume'] != null)
			this.updateState(result['mixer volume']);

		this.power = result.power;
	},

	updateState: function(newVolume){
		if (newVolume != this.volume) {
			var volEl;
			var volVal = Math.ceil(newVolume / 9.9); 

			if (newVolume <= 0)
				volVal = 0;
			else if (newVolume >= 100)
				volVal = 11;

			this.el.removeClass([ 'ctrlVolume0', 'ctrlVolume1', 'ctrlVolume2', 'ctrlVolume3', 'ctrlVolume4', 'ctrlVolume5', 'ctrlVolume6', 'ctrlVolume7', 'ctrlVolume8', 'ctrlVolume9', 'ctrlVolume10' ]);
			this.el.addClass('ctrlVolume' + String(Math.max(volVal-1, 0)));
	
			if (volEl = this.el.child('img:first'))
				volEl.dom.title = strings['volume'] + ' ' + parseInt(newVolume);

			this.volume = newVolume;
		}
	}
});


Slim.PowerButton = function(renderTo, config){
	Ext.apply(config, {
		tooltip: strings['power'],
		scope: this,

		handler: function(){
			var newState = (this.state ? '0' : '1');
			this.updateState(newState == '1');
			Player.playerControl(['power', newState]);
		},

		updateHandler: function(result){
			if (result['power'] != null && this.state != result['power']) {
				this.updateState(result['power']);
			}
		},

		updateState: function(newState){
			this.state = newState;
			this.setTooltip(strings['power'] + strings['colon'] + ' ' + strings[this.state ? 'on' : 'off']);

			if (this.state)
				this.el.removeClass('btn-power-off');
			else
				this.el.addClass('btn-power-off');
		},

		state: null
	});

	Slim.PowerButton.superclass.constructor.call(this, renderTo, config);
};
Ext.extend(Slim.PowerButton, Slim.Button);
