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

			// TODO: these links need to go to the correct page!!!
			Ext.get('helpLink').on('click', function(){ 
				window.open(webroot + 'html/docs/quickstart.html', 'settings', 'dependent=yes,resizable=yes'); 
			});

			Ext.get('settingsLink').on('click', function(){ 
				window.open('/EN/settings/server/basic.html', 'settings', 'dependent=yes,resizable=yes'); 
			});

			Ext.get('playerSettingsLink').on('click', function(){ 
				window.open('/EN/settings/player/basic.html?playerid=' + player, 'playersettings', 'dependent=yes,resizable=yes'); 
			});

			Ext.EventManager.onWindowResize(this.onResize, layout);
			Ext.EventManager.onDocumentReady(this.onResize, layout, true);

			layout.endUpdate();

			Ext.QuickTips.init();
			Ext.get('loading').hide();
			Ext.get('loading-mask').hide();

			this.onResize();
		},

		// resize panels, folder selectors etc.
		onResize : function(){
			// some browser dependant offsets... argh...
			offset = new Array();
			offset['bottom'] = 75;
			offset['playlistbottom'] = 76;
			offset['playlist'] = 5;

			if (Ext.isIE) {
				offset['bottom'] = 55;
				if (Ext.isIE7) {
					offset['playlistbottom'] = 88;
					offset['playlist'] = 9;
				}
				else {
					offset['playlistbottom'] = 97;
					offset['playlist'] = 4;
				}
			}
			else if (Ext.isOpera) {
				offset['bottom'] = 60;
				offset['playlistbottom'] = 79;
			}
			else if (Ext.isSafari) {
				offset['playlistbottom'] = 96;
			}

			if (pager = Ext.get('pagebar'))
				offset['playlist'] += pager.getHeight() + (Ext.isIE ? 0 : 4);
				
			dimensions = new Array();
			dimensions['maxHeight'] = Ext.get(document.body).getHeight();
			dimensions['footer'] = Ext.get('footer').getHeight();
			dimensions['colWidth'] = Math.floor((Ext.get(document.body).getWidth() - 6*20) / 2);
			dimensions['rightHeight'] = dimensions['maxHeight'] - dimensions['footer'] * 2 - 163 - 50 - offset['playlistbottom'];

			right = Ext.get('rightpanel');
			left = Ext.get('leftcontent');

			Ext.get('mainbody').setHeight(dimensions['maxHeight']-35);

			// left column
			left.setHeight(dimensions['maxHeight'] - Ext.get('leftpanel').getTop() - dimensions['footer'] - offset['bottom']);
			left.setWidth(dimensions['colWidth']);

			// right column
			Ext.get('playerControlPanel').setWidth(dimensions['colWidth']);

			right.setHeight(dimensions['rightHeight']);

			if (el = Ext.DomQuery.selectNode('div.inner_content', right.dom))
				Ext.get(el).setHeight(dimensions['rightHeight']);

			// playlist field
			if (pl = Ext.get('playList')) {
				pl.setHeight(dimensions['rightHeight'] - offset['playlist']);
			}

			try { this.layout(); }
			catch(e) {}
		}
	};   
}();


Playlist = function(){
	return {
		load : function(url){
			Ext.get('rightcontent').load(
				{
					url: url || webroot + 'playlist.html?playerid=' + player,
					method: 'GET'
				},
				{},
				this.onUpdated
			);
		},
		
		clear : function(){ Player.playerControl(['playlist', 'clear']); },

		onUpdated : function(){
			Main.onResize();
			Utils.addBrowseMouseOver();

			Ext.addBehaviors({
				'.currentSong@mouseover': function(ev, target){
					el = Ext.get(target);
					if (el) {
						if (controls = Ext.DomQuery.selectNode('div.playlistControls', el.dom)) {
							Ext.get(controls).show();
						}
					}
				},

				'.currentSong@mouseout': function(ev, target){
					if (Ext.get(target).findParent('.currentSong'))
						return;

					el = Ext.get(target);
					if (el) {
						if (controls = Ext.DomQuery.selectNode('div.playlistControls', el.dom)) {
							Ext.get(controls).hide();
						}
					}
				}
			});
			
/*			Ext.dd.ScrollManager.register('playList');
			items = Ext.DomQuery.select('div.selectorMarker');
			for(var i = 0; i < items.length; i++) {
				var dd = new Ext.dd.DD(items[i], 'playlist', {
					containerScroll: true,
					scroll: false
				});
				dd.setXConstraint(0, 0);
				dd.onDragDrop = function(e, id) {
					alert("dd was dropped on " + id);
				}
			}
			
//			Ext.dd.DragZone('playList', {containerScroll:true});
*/
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
				icon: 'html/images/btn_previous.gif',
				tooltip: strings['previous'],
				width: 28,
				height: 22,
				scope: this,
				handler: this.ctrlPrevious
			});

			btnTogglePlay = new Slim.Button('ctrlTogglePlay', {
				icon: 'html/images/btn_play.gif',
				tooltip: strings['play'],
				width: 51,
				height: 22,
				scope: this,
				handler: this.ctrlTogglePlay
			});

			new Slim.Button('ctrlNext', {
				icon: 'html/images/btn_next.gif',
				tooltip: strings['next'],
				width: 28,
				height: 22,
				scope: this,
				handler: this.ctrlNext
			});

			new Slim.Button('ctrlRepeat', {
				icon: 'html/images/btn_repeat.gif',
				tooltip: strings['repeat0'],
				width: 34,
				height: 22,
				scope: this,
				handler: this.ctrlRepeat
			});

			new Slim.Button('ctrlShuffle', {
				icon: 'html/images/btn_shuffle.gif',
				tooltip: strings['shuffle0'],
				width: 34,
				height: 22,
				scope: this,
				handler: this.ctrlShuffle
			});

			new Slim.Button('ctrlVolumeDown', {
				icon: 'html/images/btn_volume_decrease.gif',
				tooltip: strings['volumedown'],
				width: 22,
				height: 22,
				scope: this,
				handler: this.volumeDown
			});

			new Slim.Button('ctrlVolumeUp', {
				icon: 'html/images/btn_volume_increase.gif',
				tooltip: strings['volumeup'],
				width: 22,
				height: 22,
				scope: this,
				handler: this.volumeUp
			});

			volumeUp = new Ext.util.ClickRepeater('ctrlVolumeUp', {
				accelerate: true
			});

			// volume buttons can be held
			volumeUp.on({
				'click': {
					fn: function(){
						volumeClicked++;
						if (volumeClicked > 4) {
							this.setVolume(volumeClicked, '+');
							volumeClicked = 0;
						}
					},
					scope: this
				},
				'mouseup': {
					fn: function(){
						this.setVolume(volumeClicked, '+');
						volumeClicked = 0;
					},
					scope: this
				}
			});

			volumeDown = new Ext.util.ClickRepeater('ctrlVolumeDown', {
				accelerate: true
			});
			
			volumeDown.on({
				'click': {
					fn: function(){
						volumeClicked++;
						if (volumeClicked > 4) {
							this.setVolume(volumeClicked, '-');
							volumeClicked = 0;
						}
					},
					scope: this
				},
				'mouseup': {
					fn: function(){
						this.setVolume(volumeClicked, '-');
						volumeClicked = 0;
					},
					scope: this
				}
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
				icon: 'html/images/btn_power.gif',
				tooltip: strings['power'],
				width: 24,
				height: 24,
				scope: this,
				handler: this.ctrlPower
			});

			pollTimer = new Ext.util.DelayedTask(this.getStatus, this);
			playTimeTimer = new Ext.util.DelayedTask(this.updatePlayTime, this);
			this.getStatus();
		},

		updatePlayTime : function(time, totalTime){
			if (playerStatus.mode == 'play') {
				if (! isNaN(time))
					playTime = parseInt(time); //force integer type from results
					
				Ext.get('ctrlPlaytime').update(this.formatTime(playTime));
				playTime += 0.5;
	
				if (! isNaN(totalTime)) {
					Ext.get('ctrlTotalTime').update(' (' + this.formatTime(totalTime) + ')');

					if (playTime >= totalTime-1)
						this.getStatus();
				}
			}
			else
				Ext.get('ctrlPlaytime').update(this.formatTime(0));
			
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
							
							// Handle plugin-specific metadata, i.e. Pandora
							if (result.current_meta) {
								result.playlist_loop[0].id     = null;
								result.playlist_loop[0].title  = result.current_meta.title;
								result.playlist_loop[0].artist = result.current_meta.artist;
								result.playlist_loop[0].album  = result.current_meta.album;
								if (result.current_meta.cover) {
									Ext.get('ctrlCurrentArt').update('<img src="' + result.current_meta.cover + '" height="96">');
								}
							}

							Ext.get('ctrlCurrentTitle').update(
								'<a href="' + webroot + 'songinfo.html?player=' + player + '&amp;item=' + result.playlist_loop[0].id + '" target="browser">'
								+ 
								((result.current_title && !result.current_meta) ? result.current_title : (
									(result.playlist_loop[0].disc ? result.playlist_loop[0].disc + '-' : '')
									+ 
									(result.playlist_loop[0].tracknum ? result.playlist_loop[0].tracknum + ". " : '')
									+
									result.playlist_loop[0].title
								))
								+
								'</a>'
							);
	//						Ext.get('statusSongCount').update(result.playlist_tracks);
	//						Ext.get('statusPlayNum').update(result.playlist_cur_index + 1);
							Ext.get('ctrlBitrate').update(result.playlist_loop[0].bitrate);
							
							if (result.playlist_loop[0].artist) {
								Ext.get('ctrlCurrentArtist').update('<a href="' + webroot + 'browsedb.html?hierarchy=contributor,album,track&amp;contributor.id=' + result.playlist_loop[0].artist_id + '&amp;artwork=1&amp;level=1&amp;player=' + player + '" target="browser">' + result.playlist_loop[0].artist + '</a>');
							}
							
							if (result.playlist_loop[0].album) {
								Ext.get('ctrlCurrentAlbum').update(
									'<a href="' + webroot + 'browsedb.html?hierarchy=album,track&amp;level=1&amp;album.id=' + result.playlist_loop[0].album_id + '&amp;player=' + player + '" target="browser">' + result.playlist_loop[0].album + '</a>' 
									+ (result.playlist_loop[0].year ? ' (' 
										+ '<a href="' + webroot + 'browsedb.html?hierarchy=year,album,track&amp;artwork=1&amp;level=1&amp;year.id=' + result.playlist_loop[0].year + '&amp;player=' + player + '" target="browser">' + result.playlist_loop[0].year + '</a>' 
									+ ')' : '')
								);
							}

							if (result.playlist_loop[0].id && (el = Ext.get('ctrlCurrentArt'))) {
								coverart = '<a href="' + webroot + 'browsedb.html?hierarchy=album,track&amp;level=1&amp;album.id=' + result.playlist_loop[0].album_id + '&amp;player=' + player + '" target="browser"><img src="/music/' + result.playlist_loop[0].id + '/cover_96xX.jpg"></a>';
								el.update(coverart);
								el = el.child('img:first');
								Ext.QuickTips.unregister(el);
								Ext.QuickTips.register({
									target: el,
									text: '<img src="/music/' + result.playlist_loop[0].id + '/cover_250xX.jpg" width="250">',
									minWidth: 250
								});
							}
						}

						// empty playlist
						else {
							Ext.get('ctrlCurrentTitle').update('');
	//						Ext.get('statusSongCount').update('');
	//						Ext.get('statusPlayNum').update('');
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
						volEl.setStyle('background', 'url(html/images/volume_levels.gif) no-repeat 0px -' + String(volVal * 22) + 'px');
						if (volEl = volEl.child('img:first'))
							volEl.dom.title = strings['volume'] + ' ' + parseInt(result['mixer volume']);

						playerStatus = {
							power: result.power,
							mode: result.mode,
							title: result.current_title,
							track: result.playlist_tracks ? result.playlist_loop[0].url : '',
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
							"tags:gabehldiqtyrsu"
						]
					]
				}),
				scope: this
			});
		},
		
		
		// only poll to see whether the currently playing song has changed
		// don't request all status info to minimize performance impact on the server
		getStatus : function() {
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

							else if (result['mixer volume'] && result['mixer volume'] != playerStatus.volume) {
								this.updateStatus(response)
							}
							else
								this.updatePlayTime(result.time, result.duration);
						}
					}
				},

				scope: this
			});
			
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
			amount *= 2.5;
			if (d)
				amount = d + amount;
			this.playerControl(['mixer', 'volume', amount]);
		},
		
		// TODO: first ask, then change
		ctrlRepeat : function(){ this.playerControl(['playlist', 'repeat', '?']); },
		ctrlShuffle : function(){ this.playerControl(['playlist', 'shuffle', '?']); }
	}
}();