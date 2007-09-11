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
					offset['rightpanel'] = 39;
					offset['bottom'] = 27;
					offset['playlistbottom'] = 30;
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

			// right column
			right.setHeight(dimensions['colHeight'] - offset['rightpanel']);
			Ext.get('playerControlPanel').setWidth(dimensions['colWidth'] - 20);

			// playlist field
			if (pl = Ext.get('playList')) {
				pl.setHeight(dimensions['colHeight'] - pl.getTop() + offset['playlistbottom']);
			}

			try { this.layout(); }
			catch(e) {}
		}
	};   
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
		
		clear : function(){ Player.playerControl(['playlist', 'clear']); },

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
		title: null,
		track: null,
		tracks: null,
		index: null,
		volume: null,
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

			Ext.get('ctrlVolume').on('click', function(ev, target){
				
				if (el = Ext.get(target)) {
					x = el.getX();
					x = Ext.fly(target).getX();
					
					// factor in the body margin for FF
					x = 100 * (ev.getPageX() - el.getX() - (Ext.isGecko * 20)) / el.getWidth();
					Player.playerControl(['mixer', 'volume', x]);
				}
			});

			new Slim.Button('ctrlPower', {
				cls: 'btn-power',
				tooltip: strings['power'],
				minWidth: 22,
				scope: this,
				handler: this.ctrlPower
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
				
			Ext.get('ctrlPlaytime').update(this.formatTime(playTime));
			
			// only increment interim value if playing
			if (playerStatus.mode == 'play') 
				playTime += 0.5;

			if (! isNaN(totalTime)) {
				Ext.get('ctrlTotalTime').update(' (' + this.formatTime(totalTime) + ')');

				if (totalTime > 0 && playTime >= totalTime-1)
					this.getStatus();
			}
			
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
							(result.current_title && result.current_title != playerStatus.title) ||
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
							
							Ext.get('ctrlCurrentTitle').update(
								'<a href="' + webroot + 'songinfo.html?player=' + player + '&amp;item=' + result.playlist_loop[0].id + '" target="browser">'
								+ 
								(result.current_title ? result.current_title : (
									(result.playlist_loop[0].disc ? result.playlist_loop[0].disc + '-' : '')
									+ 
									(result.playlist_loop[0].tracknum ? result.playlist_loop[0].tracknum + ". " : '')
									+
									result.playlist_loop[0].title
								))
								+
								'</a>'
							);
							Ext.get('ctlSongCount').update(result.playlist_tracks);
							Ext.get('ctlPlayNum').update(result.playlist_cur_index + 1);

							if (result.playlist_loop[0].artist) {
								Ext.get('ctrlCurrentArtist').update(
									result.playlist_loop[0].artist_id
										? '<a href="' + webroot + 'browsedb.html?hierarchy=contributor,album,track&amp;contributor.id=' + result.playlist_loop[0].artist_id + '&amp;level=1&amp;player=' + player + '" target="browser">' + result.playlist_loop[0].artist + '</a>'
										: result.playlist_loop[0].artist
								);
								Ext.get('ctrlArtistTitle').show();
							}
							else {
								Ext.get('ctrlCurrentArtist').update('');
								Ext.get('ctrlArtistTitle').hide();
							}
							
							if (result.playlist_loop[0].album) {
								Ext.get('ctrlCurrentAlbum').update(
									(result.playlist_loop[0].album_id
										? '<a href="' + webroot + 'browsedb.html?hierarchy=album,track&amp;level=1&amp;album.id=' + result.playlist_loop[0].album_id + '&amp;player=' + player + '" target="browser">' + result.playlist_loop[0].album + '</a>'
										: result.playlist_loop[0].album
									)
									+ (result.playlist_loop[0].year ? ' (' 
										+ '<a href="' + webroot + 'browsedb.html?hierarchy=year,album,track&amp;level=1&amp;year.id=' + result.playlist_loop[0].year + '&amp;player=' + player + '" target="browser">' + result.playlist_loop[0].year + '</a>' 
									+ ')' : '')
								);
								Ext.get('ctrlAlbumTitle').show();
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

						this.updatePlayTime(result.time ? result.time : 0, result.duration ? result.duration : 0);

						// update play/pause button
						btnTogglePlay.icon = webroot + 'html/images/' + (result.mode=='play' ? 'btn_pause.gif' : 'btn_play.gif');
						if (el = btnTogglePlay.getEl().child('button:first'))
							el.dom.title = (result.mode=='play' ? strings['pause'] : strings['play']);
						btnTogglePlay.onBlur();

						// update volume button
						volVal = 5;
						if (result['mixer volume'] <= 0)
							volVal = 0;
						else if (result['mixer volume'] >= 100)
							volVal = 11;
						else {
							volVal = Math.ceil(result['mixer volume']/9.9);
						}
						volEl = Ext.get('ctrlVolume');
						volVal = Math.max(volVal-1, 0);
						volEl.setStyle('background-position', '0px -' + String(volVal * 22) + 'px');
						if (volEl = volEl.child('img:first'))
							volEl.dom.title = strings['volume'] + ' ' + parseInt(result['mixer volume']);

						playerStatus = {
							power: result.power,
							mode: result.mode,
							title: result.current_title,
							track: result.playlist_tracks > 0 ? result.playlist_loop[0].url : '',
							tracks: result.playlist_tracks,
							index: result.playlist_cur_index,
							volume: result['mixer volume'],
							shuffle: result['playlist shuffle']
						};
					}
					
					else if (!result.power)
						playerStatus.power = 0;
				}
			}
			pollTimer.delay(5000);
		},

		getUpdate : function(){
			Ext.Ajax.request({
				failure: this.updateStatus,
				success: this.updateStatus,

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
				scope: this
			});
		},
		
		
		// only poll a minimum of information to see whether the currently playing song has changed
		// don't request all status info to minimize performance impact on the server
		getStatus : function() {
			// only poll player state if there is one
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
									(result.current_title && result.current_title != playerStatus.title) ||
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
								else
									this.updatePlayTime(result.time, result.duration);

								if (el = Ext.get('playerSettingsLink'))
									el.show();
							}

							// display scanning information
							Main.checkScanStatus(responseText);
						}
					},
					
					failure: function(){
						player = '';
						playerid = '';
						if (el = Ext.get('playerSettingsLink'))
							el.hide();
					},
	
					scope: this
				});
			}

			// no player available - check for new players
			else {
				Ext.Ajax.request({
					params: Ext.util.JSON.encode({
						id: 1, 
						method: "slim.request", 
						params: [ 
							'',
							[ 
								"serverstatus",
								1
							]
						]
					}),
	
					success: function(response){
						if (response && response.responseText) {
							var responseText = Ext.util.JSON.decode(response.responseText);

							// display scanning information
							Main.checkScanStatus(responseText);

							// let's set the current player to the first player in the list
							if (responseText.result && responseText.result['player count']) {
								Ext.Ajax.request({
									params: Ext.util.JSON.encode({
										id: 1, 
										method: "slim.request", 
										params: [ 
											'',
											[ 
												"players",
												0,
												99
											]
										]
									}),
					
									success: function(response){
										if (response && response.responseText) {
											var responseText = Ext.util.JSON.decode(response.responseText);
				
											// let's set the current player to the first player in the list
											if (responseText.result && responseText.result.count && responseText.result.players_loop[0]) {
												playerid = responseText.result.players_loop[0].playerid;
												player = encodeURI(playerid);
												if (el = Ext.get('playerSettingsLink'))
													el.show();
											}

											Main.checkScanStatus(responseText);		
										}
									}
								});
							}
						}
					}
				});
			}

			pollTimer.delay(5000);
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
