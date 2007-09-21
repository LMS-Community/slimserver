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

			// TODO: these links need to go to the correct pages
			Ext.get('helpLink').on('click', function(){
				window.open(webroot + 'html/docs/quickstart.html', 'settings', 'dependent=yes,resizable=yes');
			});

			Ext.get('settingsLink').on('click', function(){
				window.open('/EN/settings/server/basic.html', 'settings', 'dependent=yes,resizable=yes');
			});

			Ext.get('playerSettingsLink').on('click', function(){
				window.open('/EN/settings/player/basic.html?playerid=' + player, 'playersettings', 'dependent=yes,resizable=yes');
			});

			Ext.get('progressInfo').on('click', function(){
				window.open('progress.html?type=importer', 'dependent=yes,resizable=yes');
			});

			PlayerChooser.init();

			Ext.EventManager.onWindowResize(this.onResize, layout);
			Ext.EventManager.onDocumentReady(this.onResize, layout, true);

			var el;
			if (el = Ext.get('scanWarning'))
				el.setVisibilityMode(Ext.Element.DISPLAY);

			if (el = Ext.get('newVersion'))
				el.setVisibilityMode(Ext.Element.DISPLAY);

			layout.endUpdate();

			Ext.get('leftcontent').dom.src = webroot + 'home.html?player=' + player;

			Ext.QuickTips.init();
			Ext.get('loading').hide();
			Ext.get('loading-mask').hide();

			this.onResize();
		},


		// scan progress status updates
		getScanStatus : function(){
			Ext.Ajax.url = '/jsonrpc.js';

			Ext.Ajax.request({
				params: Ext.util.JSON.encode({
					id: 1,
					method: "slim.request",
					params: [
						'',
						['serverstatus'],
					]
				}),
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

			try { this.layout(); }
			catch(e) {}
		}
	};
}();


PlayerChooser = function(){
	var playerList;
	var playerDiscoveryTimer;

	return {
		init : function(){
			playerList = new Ext.SplitButton('playerChooser', {
				text: player,
				hidden: true,
				handler: function(ev){
					if(this.menu && !this.menu.isVisible()){
						this.menu.show(this.el, this.menuAlign);
					}
					this.fireEvent('arrowclick', this, ev);
				},
				menu: new Ext.menu.Menu()
			});
			playerDiscoveryTimer = new Ext.util.DelayedTask(this.update, this);

			this.update();
		},

		update : function(){
			var el;

			Ext.Ajax.request({
				params: Ext.util.JSON.encode({
					id: 1,
					method: "slim.request",
					params: [
						'',
						[
							"serverstatus",
							0,
							99
						]
					]
				}),

				scope: this,

				success: function(response){
					if (response && response.responseText) {
						var responseText = Ext.util.JSON.decode(response.responseText);

						// let's set the current player to the first player in the list
						if (responseText.result && responseText.result['player count'] > 0) {
							playerList.menu.removeAll();
							var playerInList = false;

							for (x=0; x < responseText.result['player count']; x++) {
								var currentPlayer = false;
								if (responseText.result.players_loop[x].playerid == playerid) {
									currentPlayer = true;
									playerInList = true;
									playerList.setText(responseText.result.players_loop[x].name);
								}

								playerList.menu.add(
									new Ext.menu.CheckItem({
										text: responseText.result.players_loop[x].name,
										value: responseText.result.players_loop[x].playerid,
										cls: 'playerList',
										group: 'playerList',
										checked: responseText.result.players_loop[x].playerid == playerid,
										handler: PlayerChooser.selectPlayer
									})
								);
							}

							playerList.menu.add(
								'-',
								new Ext.menu.Item({
									text: strings['synchronize'] + '...',
									handler: function(){ Ext.MessageBox.alert(strings['synchronize'], 'Imagine some nice looking sync dialog here...'); }
								})
							);

							playerList.setVisible(responseText.result['player count'] > 1 ? true : false);

							if (!playerInList) {
								PlayerChooser.selectPlayer({
									text: responseText.result.players_loop[0].name,
									value: responseText.result.players_loop[0].playerid
								});
							}

							if (el = Ext.get('playerSettingsLink'))
								el.setVisible(playerid ? true : false);

							// display scanning information
							Main.checkScanStatus(responseText);
						}

						else {
							PlayerChooser.selectPlayer({
								text: '',
								value: ''
							});
						}
					}
				}
			});

			// poll more often when there's no player, to show them up as quickly as possible
			playerDiscoveryTimer.delay(player ? 30000 : 10000);
		},

		selectPlayer: function(ev){
			var el;

			playerList.setText(ev.text);
			playerid = ev.value;
			player = encodeURI(playerid);

			// set the browser frame to use the selected player
			if (player && frames.browser) {
				var browseUrl = new String(frames.browser.location.href);

				var rExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;

				if (rExp.exec(browseUrl)) {
					frames.browser.location = browseUrl.replace(rExp, '=' + playerid);
				} else {
					frames.browser.location = frames.browser.location.href + '&player=' + playerid;
				}
			}

			if (el = Ext.get('playerSettingsLink'))
				el.setVisible(playerid ? true : false);

			Playlist.resetUrl();
			Player.getStatus();
		}
	}
}();


Playlist = function(){
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
				},

				// disable the default behaviour which would place the dragged element
				// we don't need to place it as it will be moved in onDragDrop
				endDrag: function() {},

				// move the item when dropped
				onDragDrop: function(e, id) {
					var source = Ext.get(this.getEl());
					var target = Ext.get(id);

					if (target && source) {
						var sourcePos = -1;
						var targetPos = -1;

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
				}
			});

			// reset highlighter when exiting the playlist
			Ext.addBehaviors({
				'#rightpanel div.inner@mouseover': function(ev, target){
					if (target == this)
						Utils.unHighlight();

					var current = Ext.DomQuery.selectNode('div.currentSong');

					if (!(Ext.fly(current) && Ext.fly(current).contains(target))) {
						if (controls = Ext.DomQuery.selectNode('.currentSong div.playlistControls')) {
							Ext.get(controls).hide();
						}
					}
				}
			});

			this.load();
		},

		load : function(url){
			// unregister event handlers
			Utils.removeBrowseMouseOver();
			Ext.select('div.currentSong').un('mouseover', Playlist.showPlaylistControl);
			Ext.dd.ScrollManager.unregister('playList');

			// try to reload previous page if no URL is defined
			var el = Ext.get('playlistPanel');

			if (!url)
				url = el.getUpdateManager().defaultUrl;

			el.load(
				{
					url: url || webroot + 'playlist.html?player=' + playerid,
					method: 'GET',
					disableCaching: true
				},
				{},
				this.onUpdated
			);
		},

		clear : function(){
			Player.playerControl(['playlist', 'clear']);
		},

		save : function(){
			frames.browser.location = webroot + 'edit_playlist.html?player=' + player + '&saveCurrentPlaylist=1';
		},

		resetUrl : function(){
			var el = Ext.get('playlistPanel');
			if (el)
				el.getUpdateManager().setDefaultUrl('');
		},

		showPlaylistControl : function(ev, target){
			var el = Ext.get(target);
			if (el) {
				Ext.select('div.playlistControls', false, el.dom).show();
			}
		},

		onUpdated : function(){
			Main.onResize();

			// shortcut if there's no player
			if (!Ext.get('playlistTab'))
				return;
			
			Utils.addBrowseMouseOver();

			Ext.select('div.currentSong').on('mouseover', Playlist.showPlaylistControl);

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

			new Ext.Button('btnPlaylistClear', {
				cls: 'btn-small',
				text: strings['clear_playlist'],
				icon: webroot + 'html/images/icon_playlist_clear.gif',
				handler: Playlist.clear
			});

			// playlist name is too long to be displayed
			// try to use it as the Save button's tooltip
			var tooltip = null;
			if (el = Ext.get('currentPlaylistName'))
				tooltip = el.dom.innerHTML;

			new Ext.Button('btnPlaylistSave', {
				cls: 'btn-small',
				text: strings['save'],
				icon: webroot + 'html/images/icon_playlist_save.gif',
				tooltip: tooltip,
				tooltipType: 'title',
				handler: Playlist.save
			});
		},

		highlightCurrent : function(){
			if (el = Ext.get('playList')) {
				var plPos = el.getScroll();
				var plView = el.getViewSize();
				var el = Ext.DomQuery.selectNode('div.currentSong');

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
			Utils.setCookie('SlimServer-noPlaylistCover', 0);
			this.load();
		},

		hideCoverArt : function(){
			Utils.setCookie('SlimServer-noPlaylistCover', 1);
			this.load();
		}
	}
}();

Player = function(){
	var pollTimer;
	var playTimeTimer;
	var playTime = 0;
	var volumeClicked = 0;
	var displayElements = new Ext.util.MixedCollection();

	var playerStatus = {
		power: null,
		mode: null,
		current_title: null,
		title: null,
		track: null,
		tracks: null,
		index: null,
		duration: null,
		shuffle: null
	};

	return {
		init : function(){
			Ext.Ajax.method = 'POST';
			Ext.Ajax.url = '/jsonrpc.js';

			new Slim.Button('ctrlPrevious', {
				cls: 'btn-previous',
				tooltip: strings['previous'],
				minWidth: 28,
				scope: this,
				handler: function(){ this.playerControl(['playlist', 'index', '-1']) }
			});

			displayElements.add(new Slim.PlayButton('ctrlTogglePlay', {
				cls: 'btn-play',
				minWidth: 51
			}));

			new Slim.Button('ctrlNext', {
				cls: 'btn-next',
				tooltip: strings['next'],
				minWidth: 28,
				scope: this,
				handler: function(){ this.playerControl(['playlist', 'index', '+1']) }
			});

			displayElements.add(new Slim.RepeatButton('ctrlRepeat', {
				minWidth: 34,
				cls: 'btn-repeat'
			}));

			displayElements.add(new Slim.ShuffleButton('ctrlShuffle', {
				minWidth: 34,
				cls: 'btn-shuffle'
			}));

			new Slim.Button('ctrlVolumeDown', {
				cls: 'btn-volume-decrease',
				tooltip: strings['volumedown'],
				minWidth: 22,
				scope: this,
				handler: function(){ this.setVolume(1, '-') }
			});

			displayElements.add(new Slim.VolumeBar('ctrlVolume'));

			new Slim.Button('ctrlVolumeUp', {
				cls: 'btn-volume-increase',
				tooltip: strings['volumeup'],
				minWidth: 22,
				scope: this,
				handler: function(){ this.setVolume(1, '+') }
			});

			displayElements.add(new Slim.PowerButton('ctrlPower', {
				cls: 'btn-power',
				minWidth: 22
			}));

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

			// restore player expansion from cookie
			this.collapseExpand({
				doExpand: (Utils.getCookie('SlimServer-expandPlayerControl') == 'true')
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

			var shortTime = this.formatTime(playTime);

			Ext.get('ctrlPlaytime').update(shortTime);

			if (!isNaN(playerStatus.duration) && playerStatus.duration > 0) {
				totalTime = playerStatus.duration;
				Ext.get('ctrlTotalTime').update('&nbsp;(' + this.formatTime(totalTime) + ')');

				shortTime = '-' + this.formatTime(totalTime - playTime) + '&nbsp;(' + this.formatTime(totalTime) + ')';

				if (totalTime > 0 && playTime >= totalTime-1)
					this.getStatus();
			}

			this.progressBar('ctrlProgress', playTime, totalTime);

			Ext.get('ctrlPlaytimeCollapsed').update(shortTime);

			// only increment interim value if playing
			if (playerStatus.mode == 'play')
				playTime += 0.5;

			playTimeTimer.delay(500);
		},

		progressBar : function(el, time, totalTime){
			var left, right, el;

			var progress = Ext.get(el);
			var max = progress.getWidth() - 6; // total of left/right/indicator width

			// if we don't know the total play time, just put the indicator in the middle
			if (!totalTime) {
				left = Math.floor(max / 2);
			}

			// calculate left/right percentage
			else {
				left = Math.floor(time / totalTime * max);
				left = Math.min(left, max);
			}

			Ext.get(Ext.DomQuery.selectNode('.progressFillRight', progress.dom)).setWidth(max - left);
			Ext.get(Ext.DomQuery.selectNode('.progressFillLeft', progress.dom)).setWidth(left);
		},

		formatTime : function(seconds){
			var hours = Math.floor(seconds / 3600);
			var minutes = Math.floor((seconds - hours*3600) / 60);
			seconds = Math.floor(seconds % 60);

			var formattedTime = (hours ? hours + ':' : '');
			formattedTime += (minutes ? (minutes < 10 && hours ? '0' : '') + minutes : '0') + ':';
			formattedTime += (seconds ? (seconds < 10 ? '0' : '') + seconds : '00');
			return formattedTime;
		},

		updateStatus : function(response) {

			if (response && response.responseText) {
				var responseText = Ext.util.JSON.decode(response.responseText);

				// only continue if we got a result and player
				if (responseText.result && responseText.result.player_connected) {
					var el;
					var result = responseText.result;

					// send signal to all displayed elements and buttons
					displayElements.each(function(item){
						item.fireEvent('dataupdate', result);
					} );

					if (result.power && result.playlist_tracks >= 0) {

						// update the playlist if it's available
						if (Ext.get('playList') && ((result.power && result.power != playerStatus.power) ||
							(result.mode && result.mode != playerStatus.mode) ||
							(result.current_title && result.current_title != playerStatus.current_title) ||
							(result.playlist_tracks > 0 && result.playlist_loop[0].title != playerStatus.title) ||
							(result.playlist_tracks > 0 && result.playlist_loop[0].url != playerStatus.track) ||
							(playerStatus.track && !result.playlist_tracks) ||
							(result.playlist_tracks && !playerStatus.track) ||
							(result.playlist_tracks != null && result.playlist_tracks != playerStatus.tracks) ||
							(result.playlist_cur_index && result.playlist_cur_index != playerStatus.index) ||
							(result['playlist shuffle'] >= 0 && result['playlist shuffle'] != playerStatus.shuffle)
						)){
							Playlist.load();
						}

						if (result.playlist_tracks > 0) {

							var currentArtist, currentAlbum;
							var currentTitle = '<a href="' + webroot + 'songinfo.html?player=' + player + '&amp;item=' + result.playlist_loop[0].id + '" target="browser">'
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
							Ext.get('ctrlPlayNum').update(result.playlist_cur_index + 1);

							if (result.playlist_loop[0].artist) {
								currentArtist = result.playlist_loop[0].artist_id
										? '<a href="' + webroot + 'browsedb.html?hierarchy=contributor,album,track&amp;contributor.id=' + result.playlist_loop[0].artist_id + '&amp;level=1&amp;player=' + player + '" target="browser">' + result.playlist_loop[0].artist + '</a>'
										: result.playlist_loop[0].artist;

								Ext.get('ctrlCurrentArtist').update(currentArtist);
								Ext.get('ctrlArtistTitle').show();

								currentTitle += ' ' + strings['by'] + ' ' + currentArtist;
							}
							else {
								Ext.get('ctrlCurrentArtist').update('');
								Ext.get('ctrlArtistTitle').hide();
							}

							if (result.playlist_loop[0].album) {
								currentAlbum = (result.playlist_loop[0].album_id
										? '<a href="' + webroot + 'browsedb.html?hierarchy=album,track&amp;level=1&amp;album.id=' + result.playlist_loop[0].album_id + '&amp;player=' + player + '" target="browser">' + result.playlist_loop[0].album + '</a>'
										: result.playlist_loop[0].album
									)
									+ (result.playlist_loop[0].year ? ' ('
										+ '<a href="' + webroot + 'browsedb.html?hierarchy=year,album,track&amp;level=1&amp;year.id=' + result.playlist_loop[0].year + '&amp;player=' + player + '" target="browser">' + result.playlist_loop[0].year + '</a>'
									+ ')' : '');

								Ext.get('ctrlCurrentAlbum').update(currentAlbum);
								Ext.get('ctrlAlbumTitle').show();

								currentTitle += ' ' + strings['from'] + ' ' + currentAlbum;
							}
							else {
								Ext.get('ctrlCurrentAlbum').update('');
								Ext.get('ctrlAlbumTitle').hide();
							}

							if (result.playlist_loop[0].bitrate) {
								Ext.get('ctrlBitrate').update(
									result.playlist_loop[0].bitrate
									+ (result.playlist_loop[0].type
										? ', ' + result.playlist_loop[0].type
										: ''
									)
								);
								Ext.get('ctrlBitrateTitle').show();
							}
							else {
								Ext.get('ctrlBitrate').update('');
								Ext.get('ctrlBitrateTitle').hide();
							}

							Ext.get('ctrlCurrentSongInfoCollapsed').update(currentTitle);

							if (result.playlist_loop[0].id && (el = Ext.get('ctrlCurrentArt'))) {
								var coverart = '<a href="' + webroot + 'browsedb.html?hierarchy=album,track&amp;level=1&amp;album.id=' + result.playlist_loop[0].album_id + '&amp;player=' + player + '" target="browser"><img src="/music/' + result.playlist_loop[0].id + '/cover_96x96.jpg"></a>';
								var popup    = '<img src="/music/' + result.playlist_loop[0].id + '/cover_250xX.jpg" width="250">';

								if (result.playlist_loop[0].artwork_url) {
									coverart = '<img src="' + result.playlist_loop[0].artwork_url + '" height="96" />';
									popup    = '<img src="' + result.playlist_loop[0].artwork_url + ' />';
								}

								el.update(coverart);
								el = el.child('img:first');
								Ext.QuickTips.unregister(el);
								Ext.QuickTips.register({
									target: el,
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
							Ext.get('ctrlCurrentArt').update('<img src="/music/0/cover_96xX.jpg">');
						}

						playerStatus = {
							power: result.power,
							mode: result.mode,
							current_title: result.current_title,
							title: result.playlist_tracks > 0 ? result.playlist_loop[0].title : '',
							track: result.playlist_tracks > 0 ? result.playlist_loop[0].url : '',
							tracks: result.playlist_tracks,
							index: result.playlist_cur_index,
							duration: result['duration'] || 0,
							shuffle: result['playlist shuffle']
						};

						this.updatePlayTime(result.time ? result.time : 0);
					}

					else if (!result.power) {
						playerStatus.power = 0;
						playTimeTimer.cancel();
					}
				}
			}
			pollTimer.delay(5000);
		},

		getUpdate : function(){
			if (player) {
				Ext.Ajax.request({
					params: Ext.util.JSON.encode({
						id: 1,
						method: "slim.request",
						params: [
							playerid,
							[
								"status",
								"-",
								1,
								"tags:gabehldiqtyrsuoK"
							]
						]
					}),

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
				Ext.Ajax.request({
					params: Ext.util.JSON.encode({
						id: 1,
						method: "slim.request",
						params: [
							playerid,
							[
								"status",
								"-",
								1,
								"tags:u"
							]
						]
					}),

					success: function(response){
						if (response && response.responseText) {
							var responseText = Ext.util.JSON.decode(response.responseText);

							// only continue if we got a result and player
							if (responseText.result && responseText.result.player_connected) {
								var result = responseText.result;
								if ((result.power && result.power != playerStatus.power) ||
									(result.mode && result.mode != playerStatus.mode) ||
									(result.current_title && result.current_title != playerStatus.current_title) ||
									(result.playlist_tracks > 0 && result.playlist_loop[0].title != playerStatus.title) ||
									(result.playlist_tracks > 0 && result.playlist_loop[0].url != playerStatus.track) ||
									(playerStatus.track && !result.playlist_tracks) ||
									(result.playlist_tracks && !playerStatus.track) ||
									(result.playlist_tracks != null && result.playlist_tracks != playerStatus.tracks) ||
									(result.playlist_cur_index && result.playlist_cur_index != playerStatus.index) ||
									(result['playlist shuffle'] >= 0 && result['playlist shuffle'] != playerStatus.shuffle)
								){
									this.getUpdate();
								}

								playerStatus.duration = result.duration;
								
								if (result.power)
									this.updatePlayTime(result.time);
								else {
									playerStatus.power = 0;
									playTimeTimer.cancel();
								}

								displayElements.each(function(item){
									item.fireEvent('dataupdate', result);
								} );
							}

							// display scanning information
							Main.checkScanStatus(responseText);
						}
					},

					failure: function(){
						playerid = '';
						player = encodeURI(playerid);
						PlayerChooser.update
					},

					scope: this
				});

				pollTimer.delay(5000);
			}
		},

		playerControl : function(action){
			Ext.Ajax.request({
				params: Ext.util.JSON.encode({
					id: 1,
					method: "slim.request",
					params: [
						playerid,
						action
					]
				}),
				success: this.getUpdate,
				scope: this
			});
		},

		collapseExpand : function(ev){
			var doExpand = ev.doExpand == null ? !Utils.getCookie('SlimServer-expandPlayerControl') : ev.doExpand;

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

			if (art && doExpand) {
				art.setHeight(96);
				art.show();
			}

			Utils.setCookie('SlimServer-expandPlayerControl', doExpand);

			try { Main.onResize(); }
			catch(e) {}
		},

		openPlayerControl : function(){
			window.open(webroot + 'status_header.html', 'playerControl', "width=500,height=165");
		},

		setVolume : function(amount, d){
			amount *= 10;
			if (d)
				amount = d + amount;
			this.playerControl(['mixer', 'volume', amount]);
		}
	}
}();


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
		scope: this,

		handler: function(){
			var newState = (this.state + 1) % 3;
			Player.playerControl(['playlist', 'repeat', newState]);
			this.updateState(newState); 
		},

		updateHandler: function(result){
			if (result['playlist repeat'] != null && this.state != result['playlist repeat']) {
				this.updateState(result['playlist repeat']);
			}
		},

		updateState: function(newState){
			this.state = newState;
			this.setTooltip(strings['repeat' + this.state]);
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
			Player.playerControl(['playlist', 'shuffle', (this.state + 1) % 3]); 
		},

		updateHandler: function(result){
			if (result['playlist shuffle'] != null && this.state != result['playlist shuffle']) {
				this.updateState(result['playlist shuffle']);
			}
		},

		updateState: function(newState){
			this.state = newState;
			this.setTooltip(strings['shuffle' + this.state]);
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
	onClick: function(ev, target) {
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
		if (result['mixer volume'])
			this.updateState(result['mixer volume']);
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

	Slim.ShuffleButton.superclass.constructor.call(this, renderTo, config);
};
Ext.extend(Slim.PowerButton, Slim.Button);
