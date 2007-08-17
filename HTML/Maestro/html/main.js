Main = function(){
	return {
		init : function(){
			var layout = new Ext.BorderLayout('mainbody', {
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

			Ext.EventManager.onWindowResize(this.onResize, layout);
			Ext.EventManager.onDocumentReady(this.onResize, layout, true);

			layout.endUpdate();
		},

		// resize panels, folder selectors etc.
		onResize : function(){
			dimensions = Ext.fly(document.body).getViewSize();
			Ext.get('mainbody').setHeight(dimensions.height-35);

			colWidth = Math.floor((dimensions.width - 168) / 2);
			colHeight = dimensions.height-210;

			left = Ext.get('leftcontent');
			left.setWidth(colWidth);
			left.setHeight(colHeight);

			right = Ext.get('rightcontent');
			right.setWidth(colWidth);
			right.setHeight(colHeight-165);

			Ext.get('leftpanel').setHeight(colHeight + 10);
			Ext.get('rightpanel').setHeight(colHeight - 155);

			this.layout();
		}
	};   
}();


Player = function(){
	var pollTimer;

	var playerStatus = {
		power: null,
		modus: null,
		title: null,
		track: null,
		volume: null
	};

	return {
		init : function(){
			Ext.Ajax.method = 'POST';
			Ext.Ajax.url = '/jsonrpc.js'; 
			Ext.Ajax.timeout = 4000;

			pollTimer = new Ext.util.DelayedTask(Player.getStatus, this);
			this.getStatus();
		},

		updateStatus : function(response) {

			if (response && response.responseText) {
				var responseText = Ext.util.JSON.decode(response.responseText);
				
				// only continue if we got a result and player
				if (responseText.result && responseText.result.player_connected) {
					var result = responseText.result;
					if (result.power && result.playlist_tracks > 0) {
						Ext.get('ctrlCurrentTitle').update(
							result.current_title ? result.current_title :
							result.playlist_loop[0].tracknum + ". " + result.playlist_loop[0].title
						);
//						Ext.get('statusSongCount').update(result.playlist_tracks);
//						Ext.get('statusPlayNum').update(result.playlist_cur_index + 1);
//						Ext.get('statusBitrate').update(result.playlist_loop[0].bitrate);
						Ext.get('ctrlCurrentArtist').update(result.playlist_loop[0].artist);
						Ext.get('ctrlCurrentAlbum').update(result.playlist_loop[0].album);
//						Ext.get('statusYear').update(result.playlist_loop[0].year);
		
/*						var playlistUpdater = Ext.get('playlist').getUpdateManager();
						playlistUpdater.setDefaultUrl(webroot + 'playlist.html');
						playlistUpdater.showLoadIndicator = false;
						playlistUpdater.refresh();
*/		
						if (result.playlist_loop[0].id) {
							Ext.get('ctrlCurrentArt').update('<img src="/music/' + result.playlist_loop[0].id + '/cover_96x96.jpg">');
						}
		
						modeImg = '<img src="' + webroot + 'html/images/' + (result.mode=='play' ? 'btn_pause_normal.png' : 'btn_pause_normal.png') + '">';
						el = Ext.get('ctrlMode');
						el.update(modeImg);
						Ext.get('ctrlMode').update('<img src="' + webroot + 'html/images/' + (result.mode=='play' ? 'btn_play_normal.png' : 'btn_pause_normal.png') + '">');

						playerStatus = {
							power: result.power,
							mode: result.mode,
							title: result.current_title,
							track: result.playlist_loop[0].url,
							volume: result['mixer volume']
						};
					}
		
/*					else if (playerStatus.name) {
							var playlistUpdater = Ext.get('playlist').getUpdateManager();
							playlistUpdater.setDefaultUrl(webroot + 'playlist.html');
							playlistUpdater.showLoadIndicator = false;
							playlistUpdater.refresh();
							
							playerStatus = {
								power: null,
								mode: null,
								title: null,
								track: null
							};
					}
*/				}
			}
			pollTimer.delay(5000);
		},

		getUpdate : function(response){
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
							"tags:gabehldiqtyru"
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
								(result.playlist_tracks > 0 && result.playlist_loop[0].url != playerStatus.track))
							{
								this.getUpdate();
							}
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

		openPlayerControl : function(){
			window.open(webroot + 'status_header.html', "gaasd", "width=500,height=165");
		}
	}
}();