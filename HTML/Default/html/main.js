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
					initialSize: 38
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
							playerInList = false;

							for (x=0; x < responseText.result['player count']; x++) {
								currentPlayer = false;
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
			playerList.setText(ev.text);
			playerid = ev.value;
			player = encodeURI(playerid);

			// set the browser frame to use the selected player
			if (player && frames.browser) {
				browseUrl = new String(frames.browser.location.href);

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
		load : function(url){
			// try to reload previous page if no URL is defined
			el = Ext.get('playlistPanel');

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
			if(el = Ext.get('playlistPanel'))
				el.getUpdateManager().setDefaultUrl('');
		},

		onUpdated : function(){
			Main.onResize();
			Utils.addBrowseMouseOver();

			current = Ext.DomQuery.selectNode('div.currentSong');

			Ext.addBehaviors({
				'.currentSong@mouseover': function(ev, target){
					el = Ext.get(target);
					if (el) {
						if (controls = Ext.DomQuery.selectNode('div.playlistControls', el.dom)) {
							Ext.get(controls).show();
						}
					}
				},

				// reset highlighter when exiting the playlist
				'#rightpanel div.inner@mouseover': function(ev, target){
					if (target == this)
						Utils.unHighlight();

					if (!(Ext.fly(current) && Ext.fly(current).contains(target))) {
						if (controls = Ext.DomQuery.selectNode('.currentSong div.playlistControls')) {
							Ext.get(controls).hide();
						}
					}
				}				
			});


			Playlist.highlightCurrent();

			new Ext.Button('btnPlaylistClear', {
				cls: 'btn-small',
				text: strings['clear_playlist'],
				icon: webroot + 'html/images/icon_playlist_clear.gif',
				handler: Playlist.clear
			});

			// playlist name is too long to be displayed
			// try to use it as the Save button's tooltip
			tooltip = null;
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
				plPos = el.getScroll();
				plView = el.getViewSize();

				if (el = Ext.DomQuery.selectNode('div.currentSong')) {
					el = Ext.get(el);
					if (el.getTop() > plPos.top + plView.height
						|| el.getBottom() < plPos.top)
							el.scrollIntoView('playList');
				}
			}
		},

		showCoverArt: function(){
			Utils.setCookie('SlimServer-noPlaylistCover', 0);
			this.load();
		},

		hideCoverArt: function(){
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
	var btnTogglePlay;

	var playerStatus = {
		power: null,
		mode: null,
		current_title: null,
		title: null,
		track: null,
		tracks: null,
		index: null,
		volume: null,
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
				handler: this.ctrlPrevious
			});

			btnTogglePlay = new Slim.Button('ctrlTogglePlay', {
				cls: 'btn-play',
				tooltip: strings['play'],
				minWidth: 51,
				scope: this,
				handler: this.ctrlTogglePlay
			});

			new Slim.Button('ctrlNext', {
				cls: 'btn-next',
				tooltip: strings['next'],
				minWidth: 28,
				scope: this,
				handler: this.ctrlNext
			});

			new Slim.Button('ctrlRepeat', {
				cls: 'btn-repeat',
				tooltip: strings['repeat0'],
				minWidth: 34,
				scope: this,
				handler: this.ctrlRepeat
			});

			new Slim.Button('ctrlShuffle', {
				cls: 'btn-shuffle',
				tooltip: strings['shuffle0'],
				minWidth: 34,
				scope: this,
				handler: this.ctrlShuffle
			});

			new Slim.Button('ctrlVolumeDown', {
				cls: 'btn-volume-decrease',
				tooltip: strings['volumedown'],
				minWidth: 22,
				scope: this,
				handler: this.volumeDown
			});

			new Slim.Button('ctrlVolumeUp', {
				cls: 'btn-volume-increase',
				tooltip: strings['volumeup'],
				minWidth: 22,
				scope: this,
				handler: this.volumeUp
			});

			if (el = Ext.get('ctrlVolume').child('img:first'))
				el.on('click', function(ev, target) {
					
					if (el = Ext.get(target)) {
						myStep = el.getWidth()/11;
						myWidth = el.getWidth() - 2*myStep;
						myX = ev.getPageX() - el.getX() - (Ext.isGecko * 8) - (Ext.isSafari * 5);

						if (myX <= myStep + (Ext.isSafari * 3))
							volVal = 0;

						else if (myX >= el.getWidth() - myStep)
							volVal = 10;

						else
							volVal = Math.ceil(myX / myStep) - 1;

						Player.playerControl(['mixer', 'volume', volVal*10]);
					}
				});

			new Slim.Button('ctrlPower', {
				cls: 'btn-power',
				tooltip: strings['power'],
				minWidth: 22,
				scope: this,
				handler: this.ctrlPower
			});

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

			shortTime = this.formatTime(playTime);

			Ext.get('ctrlPlaytime').update(shortTime);

			if (! isNaN(playerStatus.duration) && playerStatus.duration > 0) {
				totalTime = playerStatus.duration;
				Ext.get('ctrlTotalTime').update('&nbsp;(' + this.formatTime(totalTime) + ')');

				shortTime = '-' + this.formatTime(totalTime - playTime) + '&nbsp;(' + this.formatTime(totalTime) + ')'; 

				if (totalTime > 0 && playTime >= totalTime-1)
					this.getStatus();
			}

			Ext.get('ctrlPlaytimeCollapsed').update(shortTime);

			// only increment interim value if playing
			if (playerStatus.mode == 'play') 
				playTime += 0.5;

			playTimeTimer.delay(500);
		},

		formatTime : function(seconds){
			hours = Math.floor(seconds / 3600);
			minutes = Math.floor((seconds - hours*3600) / 60);
			seconds = Math.floor(seconds % 60);

			formattedTime = (hours ? hours + ':' : '');
			formattedTime += (minutes ? (minutes < 10 && hours ? '0' : '') + minutes : '0') + ':';
			formattedTime += (seconds ? (seconds < 10 ? '0' : '') + seconds : '00');
			return formattedTime;
		},

		updateStatus : function(response) {

			if (response && response.responseText) {				
				var responseText = Ext.util.JSON.decode(response.responseText);
				
				// only continue if we got a result and player
				if (responseText.result && responseText.result.player_connected) {
					var result = responseText.result;
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

							currentTitle = '<a href="' + webroot + 'songinfo.html?player=' + player + '&amp;item=' + result.playlist_loop[0].id + '" target="browser">'
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

							Ext.get('ctlSongCount').update(result.playlist_tracks);
							Ext.get('ctlPlayNum').update(result.playlist_cur_index + 1);

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
								coverart = '<a href="' + webroot + 'browsedb.html?hierarchy=album,track&amp;level=1&amp;album.id=' + result.playlist_loop[0].album_id + '&amp;player=' + player + '" target="browser"><img src="/music/' + result.playlist_loop[0].id + '/cover_96x96.jpg"></a>';
								popup    = '<img src="/music/' + result.playlist_loop[0].id + '/cover_250xX.jpg" width="250">';
								
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
							Ext.get('ctlSongCount').update('');
							Ext.get('ctlPlayNum').update('');
							Ext.get('ctrlBitrate').update('');
							Ext.get('ctrlCurrentArtist').update('');
							Ext.get('ctrlCurrentAlbum').update('');
							Ext.get('ctrlCurrentArt').update('<img src="/music/0/cover_96xX.jpg">');
						}

						// update play/pause button
						playEl = Ext.DomQuery.selectNode('table:first', Ext.get('ctrlTogglePlay').dom);
						playEl = Ext.get(playEl);
						playEl.removeClass(['btn-play', 'btn-pause']);
						playEl.addClass(result.mode=='play' ? 'btn-pause' : 'btn-play');

						if (el = btnTogglePlay.getEl().child('button:first'))
							el.dom.title = (result.mode=='play' ? strings['pause'] : strings['play']);
						btnTogglePlay.onBlur();

						// update volume button
						if (result['mixer volume'] <= 0)
							volVal = 0;
						else if (result['mixer volume'] >= 100)
							volVal = 11;
						else {
							volVal = Math.ceil(result['mixer volume'] / 9.9);
						}

						volEl = Ext.get('ctrlVolume');
						volEl.removeClass([ 'ctrlVolume0', 'ctrlVolume1', 'ctrlVolume2', 'ctrlVolume3', 'ctrlVolume4', 'ctrlVolume5', 'ctrlVolume6', 'ctrlVolume7', 'ctrlVolume8', 'ctrlVolume9', 'ctrlVolume10' ]);
						volEl.addClass('ctrlVolume' + String(Math.max(volVal-1, 0)));

						if (volEl = volEl.child('img:first'))
							volEl.dom.title = strings['volume'] + ' ' + parseInt(result['mixer volume']);

						playerStatus = {
							power: result.power,
							mode: result.mode,
							current_title: result.current_title,
							title: result.playlist_tracks > 0 ? result.playlist_loop[0].title : '',
							track: result.playlist_tracks > 0 ? result.playlist_loop[0].url : '',
							tracks: result.playlist_tracks,
							index: result.playlist_cur_index,
							volume: result['mixer volume'],
							duration: result['duration'] || 0,
							shuffle: result['playlist shuffle']
						};

						this.updatePlayTime(result.time ? result.time : 0);
					}
					
					else if (!result.power)
						playerStatus.power = 0;
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
	
								else if (result['mixer volume'] != null  && result['mixer volume'] != playerStatus.volume) {
									this.updateStatus(response)
								}
	
								playerStatus.duration = result.duration;
								this.updatePlayTime(result.time);
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
			doExpand = ev.doExpand == null ? !Utils.getCookie('SlimServer-expandPlayerControl') : ev.doExpand;

			art = Ext.get('ctrlCurrentArt');

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

		ctrlNext : function(){ this.playerControl(['playlist', 'index', '+1']) },
		ctrlPrevious : function(){ this.playerControl(['playlist', 'index', '-1']) },

		ctrlTogglePlay : function(){
			if (playerStatus.power == '0' || playerStatus.mode == 'stop')
				this.playerControl(['play']);
			else
				this.playerControl(['pause']);
		},

		ctrlPower : function(){
			this.playerControl(['power', (playerStatus.power == '1' ? '0' : '1')]);
		},

		openPlayerControl : function(){
			window.open(webroot + 'status_header.html', 'playerControl', "width=500,height=165");
		},

		// values could be adjusted if not enough
		volumeUp : function(){ this.setVolume(1, '+') },
		volumeDown : function(){ this.setVolume(1, '-') },
		setVolume : function(amount, d){
			amount *= 10;
			if (d)
				amount = d + amount;
			this.playerControl(['mixer', 'volume', amount]);
		},
		
		// TODO: first ask, then change
		ctrlRepeat : function(){ this.playerControl(['playlist', 'repeat', '?']); },
		ctrlShuffle : function(){ this.playerControl(['playlist', 'shuffle', '?']); }
	}
}();
