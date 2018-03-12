Ext.BLANK_IMAGE_URL = '/html/images/spacer.gif';

// hack to fake IE8 into IE7 mode - let's consider them the same
Ext.isIE7 = Ext.isIE7 || Ext.isIE8;

var SqueezeJS = {
	Strings : new Array(),
	string : function(s){ return this.Strings[s]; },
	
	contributorRoles : new Array('artist', 'composer', 'conductor', 'band', 'albumartist', 'trackartist'),

	Controller : null
};

_init();

// Initialize SqueezeJS.Controller
// Look whether there's already a Controller running in a parent frame.
// If one does exist, only create a proxy SqueezeJS.Controller hooking to it,
// otherwise create new Controller.
function _init() {
	var p = (window == window.parent ? null : window.parent);
	while (p) {

		try {
			if (p.SqueezeJS && p.SqueezeJS.Controller) {
				// proxy to parent Controller
				SqueezeJS.Controller = p.SqueezeJS.Controller;
				return;
			}
		}
		catch(e) {
			break;
		}
	
		if (p == p.parent)
			break;

		p = p.parent;
	}

	// no parent Controller found - create our new, own instance
	SqueezeJS.Controller = new Ext.util.Observable();
	Ext.apply(SqueezeJS.Controller, {
		observers : null,
		showBrieflyCache : '',
	
		init : function(o){
			Ext.apply(this, o);

			Ext.applyIf(this, {
				'_server': ''
			})
			
			this._initPlayerStatus();

			this.player = -1;
			this.events = this.events || {};
			this.addEvents({
				'playerselected'   : true,
				'serverstatus'     : true,
				'playlistchange'   : true,
				'buttonupdate'     : true,
				'playerstatechange': true,
				'playtimeupdate'   : true,
				'showbriefly'      : true,
				'scannerupdate'    : true
			})

			// return immediately if a window doesn't need default observers
			if (this.noObserver)
				return;

			this.addObserver({
				name : 'playerstatus',
				timeout : 5000,
				fn : function(self){
	
					if (this.player && this.player != -1) {
	
						this.playerRequest({
							params: [ "status", "-", 1, "tags:uB" ],
				
							// set timer
							callback: function(){
								self.timer.delay(self.timeout);
							},
				
							success: function(response){
								if (response && response.responseText) {
									response = Ext.util.JSON.decode(response.responseText);
		
									// only continue if we got a result and player
									if (response.result && response.result.player_connected) {
										this.fireEvent('buttonupdate', response.result);

										if (response.result.time)
											this.playerStatus.playtime = parseInt(response.result.time);
		
										if (response.result.duration)
											this.playerStatus.duration = parseInt(response.result.duration);
		
										// check whether we need to update our song info & playlist
										if (this._needUpdate(response.result)){
											this.getStatus();
											self.timer.delay(self.timeout);
										}

										// display information if the player needs a firmware upgrade
										if (response.player_needs_upgrade && !response.player_is_upgrading) {
											this.fireEvent('playlistchange');
										}
									}

									this.showBriefly(response.result);

									if ( response.result && (this.playerStatus.rescan != response.result.rescan) ) {
										this.playerStatus.rescan = response.result.rescan;
										this.fireEvent('scannerupdate', response.result);
										
										var updater = this.observers.get('serverstatus');
										if (updater)
											updater.timer.delay(750);
									}
								}
							},
				
							scope: this
						})
					}
	
					else {
						self.timer.delay(self.timeout);
					}
			
				}
			});
	
			this.addObserver({
				name : 'serverstatus',
				timeout : 10000,
				fn : function(self){
	
					this.request({
						params: [ '', [ "serverstatus", 0, 999 ] ],
			
						// set timer
						callback: function(){
							self.timer.delay(this.player && !this.playerStatus.rescan ? 30000 : self.timeout);
						},
			
						success: function(response){
							this.selectPlayer(this._parseCurrentPlayerInfo(response));
							
							response = Ext.util.JSON.decode(response.responseText);
							if (response && response.result) {
								this.fireEvent('serverstatus', response.result);

								if (response.result.rescan || this.playerStatus.rescan || this.playerStatus.rescan != response.result.rescan) {
									this.playerStatus.rescan = response.result.rescan;
									this.fireEvent('scannerupdate', response.result);
								}
								
								if (response.result.lastscanfailed) {
									this.showBriefly(response.result.lastscanfailed);
								}
							}
						},
			
						scope: this
					})
			
				}
			});
	
			this.addObserver({
				name : 'playtimeticker',
				timeout : 950,
				fn : function(self){
					if (this.playerStatus.mode == 'play' && this.playerStatus.duration > 0 
						&& this.playerStatus.playtime >= this.playerStatus.duration-1
						&& this.playerStatus.playtime <= this.playerStatus.duration + 2)
						this.getStatus();
	
					// force 0 for current time when stopped
					if (this.playerStatus.mode == 'stop')
						this.playerStatus.playtime = 0;
						
					this.fireEvent('playtimeupdate', {
						current: this.playerStatus.playtime,
						duration: this.playerStatus.duration,
						remaining: this.playerStatus.duration ? parseInt(this.playerStatus.playtime) - this.playerStatus.duration : 0
					})
	
					// only increment interim value if playing and not scanning (FWD/RWD)
					if (this.playerStatus.mode == 'play' && this.playerStatus.rate == 1)
						this.playerStatus.playtime++;
	
					self.timer.delay(self.timeout);
				}
			});

			this.on({
				playerselected: {
					fn: function(playerobj){
						if (!(playerobj && playerobj.playerid))
							playerobj = {
								playerid : ''
							}

						// remember the selected player
						if (playerobj.playerid)
							SqueezeJS.setCookie('Squeezebox-player', playerobj.playerid);

						this.player = playerobj.playerid;

						// legacy global variables for compatibility
						playerid = playerobj.playerid;
						player = encodeURIComponent(playerobj.playerid);

						this.getStatus();
					}
				}
			});
		},

		_initPlayerStatus : function(){
			this.playerStatus = {
				power: null,
				mode: null,
				rate: 0,
				current_title: null,
				title: null,
				track: null,
				playlist_tracks: 0,
				index: null,
				duration: null,
				playtime: 0,
				timestamp: null,
				dontUpdate: false,
				player: null,
				rescan: 0,
				canSeek: false
			}
			this.playerStatus['playlist repeat'] = 0;
		},

		addObserver : function(config){
			if (!this.observers)
				this.observers = new Ext.util.MixedCollection();
	
			config.timer = new Ext.util.DelayedTask(config.fn, this, [ config ]);
			config.timer.delay(0);
			this.observers.add(config.name, config);
		},
		
		updateObserver : function(name, config) {
			var o = this.observers.get(name);
			
			if (o) {
				Ext.apply(o, config);
			}
		},
	
		updateAll : function(){
			if (this.observers){
				this.playerStatus.power = null;
				this.observers.each(function(observer){
					observer.timer.delay(0);
				});
			}
		},
	
		// different kind of requests to the server
		request : function(config){
			// shortcut for .request('http://...') calls
			if (typeof config == 'string')
				config = {
					url: config,
					method: 'GET'
				};

			if (config.showBriefly)
				this.showBriefly(config.showBriefly);
	
			Ext.Ajax.request({
				url: this.getBaseUrl() + (config.url || '/jsonrpc.js'),
				method: config.method ? config.method : 'POST',
				params: config.url ? null : Ext.util.JSON.encode({
					id: 1,
					method: "slim.request",
					params: config.params
				}),
				timeout: config.timeout || 5000,
				callback: config.callback,
				success: config.success,
				failure: config.failure,
				scope: config.scope || this
			});
		},
	
		playerRequest : function(config){
			if (this.getPlayer()) {			
				config.params = [
					this.player,
					config.params
				];
				this.request(config);
			}
		},
	
		togglePause : function(dontUpdate) {
			if (this.isPaused()) {
				this.playerControl(['play'], dontUpdate);
			} else {
				this.playerControl(['pause'], dontUpdate);
			}
		},

		// custom playerRequest which requires a controller update
		// ussually used in player controls
		playerControl : function(action, dontUpdate){
			this.playerRequest({
				success: function(response){
					this.playerStatus.dontUpdate = dontUpdate;
					this.getStatus();
		
					if (response && response.responseText) {
						response = Ext.util.JSON.decode(response.responseText);
						if (response && response.result && response.result.text) {
							this.showBriefly(response.result.text);
						}
					}
				},
				params: action
			});
		},
	
		urlRequest : function(myUrl, updateStatus, showBriefly) {
			this.request({
				url: myUrl,
				method: 'GET',
				callback: function(){
					// try updating the player control in this or the parent document
					if (updateStatus)
						this.getStatus();
				},
				showBriefly: showBriefly
			});
		},
		
		playlistRequest : function(param, reload) {
			this.urlRequest('/status_header.html?' + param + 'ajaxRequest=1&force=1', true);
			if (reload)
				this.getStatus();
		},
	
		getStatus : function(){
			if (this.player) {
				this.playerRequest({
					params: [ "status", "-", 1, "tags:cgABbehldiqtyrSuoKLNJ" ],
					failure: this._updateStatus,
					success: this._updateStatus,
					scope: this
				});
			}
		},

		_updateStatus : function(response) {
			if (!(response && response.responseText))
				return;

			response = Ext.util.JSON.decode(response.responseText);

			// only continue if we got a result and player
			if (!(response.result && response.result.player_connected))
				return;

			response = response.result;
			
			var playlistchange = this._needUpdate(response) && Ext.get('playList');

			this.playerStatus = {
				// if power is undefined, set it to on for http clients
				power:     (response.power == null) || response.power,
				mode:      response.mode,
				rate:      response.rate,
				current_title: response.current_title,
				title:     response.playlist_tracks > 0 ? response.playlist_loop[0].title : '',
				track:     response.playlist_tracks > 0 ? response.playlist_loop[0].url : '',
				playlist_tracks: response.playlist_tracks,
				index:     response.playlist_cur_index,
				duration:  parseInt(response.duration) || 0,
				canSeek:   response.can_seek ? true : false,
				playtime:  parseInt(response.time),
				repeat:    parseInt(response['playlist repeat']) || 0,
				timestamp: response.playlist_timestamp
			};

			if ((response.power != null) && !response.power) {
				this.playerStatus.power = 0;
			}

			this.fireEvent('playerstatechange', response);
			if (playlistchange)
				this.fireEvent('playlistchange', response);
	
		},
	
		_needUpdate : function(result) {
			// the dontUpdate flag allows us to have the timestamp check ignored for one action 
			// used to prevent updates during d'n'd
			if (this.playerStatus.dontUpdate) {
				this.playerStatus.timestamp = result.playlist_timestamp;
				this.playerStatus.dontUpdate = false;
			}
	
			var needUpdate = (result.power != null && (result.power != this.playerStatus.power));
			needUpdate |= (result.mode != null && result.mode != this.playerStatus.mode);                                   // play/paus mode
			needUpdate |= (result.playlist_timestamp != null && result.playlist_timestamp > this.playerStatus.timestamp);   // playlist: time of last change
			needUpdate |= (result.playlist_cur_index != null && result.playlist_cur_index != this.playerStatus.index);      // the currently playing song's position in the playlist 
			needUpdate |= (result.current_title != null && result.current_title != this.playerStatus.current_title);        // title (eg. radio stream)
			needUpdate |= (result.playlist_tracks > 0 && result.playlist_loop[0].title != this.playerStatus.title);         // songtitle?
			needUpdate |= (result.playlist_tracks > 0 && result.playlist_loop[0].url != this.playerStatus.track);           // track url
			needUpdate |= (result.playlist_tracks < 1 && this.playerStatus.track);                                          // there's a player, but no song in the playlist
			needUpdate |= (result.playlist_tracks > 0 && !this.playerStatus.track);                                         // track in playlist changed
			needUpdate |= (result.rate != null && result.rate != this.playerStatus.rate);                                   // song is scanning (ffwd/frwd)
			needUpdate |= (result['playlist repeat'] != null && result['playlist repeat'] != this.playerStatus.repeat);
			needUpdate |= (result.playlist_tracks != this.playerStatus.playlist_tracks);
	
			return needUpdate;
		},

		showBriefly : function(result){
			if (typeof result == 'string')
				result = { showBriefly: [ result ] };
			else if (typeof result == 'array')
				result = { showBriefly: result };

			if (result && result.showBriefly) {
				var text = '';
				for (var x = 0; x < result.showBriefly.length; x++) {
					if (result.showBriefly[x] && result.showBriefly[x].match(/^[\w\s\.;,:()\[\]%]/))
						text += result.showBriefly[x] + ' ';
				}

				if (text && this.showBrieflyCache != text) {
					this.showBrieflyCache = text;
					this.fireEvent('showbriefly', text);
				}
			}
		},

		setVolume : function(amount, d){
			if (d)
				amount = d + (amount * 2);
			else
				amount *= 10;

			this.playerControl(['mixer', 'volume', amount]);
		},
	
		selectPlayer : function(playerobj){
			if (typeof playerobj == 'object') {
				this._firePlayerSelected(playerobj);				
			}
			else {
				this._initPlayerStatus();
				this.request({
					params: [ '', [ "serverstatus", 0, 999 ] ],
	
					success: function(response){
						this._firePlayerSelected(this._parseCurrentPlayerInfo(response, playerobj));
					},
		
					scope: this
				});				
			}
		},

		_firePlayerSelected : function(playerobj){
			if (playerobj && playerobj.playerid) {
				if ((playerobj.playerid != this.player && encodeURIComponent(playerobj.playerid) != this.player) 
					|| this.player == -1) {
					
					var oldPlayer = this.player != -1 ? {
						playerid: this.player
					} : null;
					
					this._initPlayerStatus();
					this.fireEvent('playerselected', playerobj, oldPlayer);
				}
			}
			else {
				this._initPlayerStatus();
				this.player = null;
			}
		},

		_parseCurrentPlayerInfo : function(response, activeplayer) {
			response = Ext.util.JSON.decode(response.responseText);
			if (response && response.result)
				response = response.result;

			activeplayer = activeplayer || SqueezeJS.getCookie('Squeezebox-player');
			return this.parseCurrentPlayerInfo(response, activeplayer);
		},
		
		parseCurrentPlayerInfo: function(result, activeplayer) {
			if (result && result.players_loop) {
				var players_loop = result.players_loop;
				for (var x=0; x < players_loop.length; x++) {
					if (players_loop[x].playerid == activeplayer || encodeURIComponent(players_loop[x].playerid) == activeplayer)
						return players_loop[x];
				}
			}		
		},

		getPlayer : function() {
			if (SqueezeJS.Controller.player == null || SqueezeJS.Controller.player == -1)
				return;
			
			SqueezeJS.Controller.player = String(SqueezeJS.Controller.player).replace(/%3A/gi, ':');
			return SqueezeJS.Controller.player;
		},

		isPaused : function() {
			if (this.player && this.playerStatus.mode == 'pause') {
				return true;
			} 
			return false;
		},

		isPlaying : function() {
			if (this.player && this.playerStatus.mode == 'play') {
				return true;
			} 
			return false;
		},

		isStopped : function() {
			if (this.player && this.playerStatus.mode == 'stop') {
				return true;
			} 
			return false;
		},

		hasPlaylistTracks: function() {
			if (!this.player || !this.playerStatus)
				return;
				
			return parseInt(this.playerStatus.playlist_tracks) > 0 ? true : false;
		},

		getBaseUrl: function() {
			return this._server || '';
		},
		
		setBaseUrl: function(server) {
			if (typeof server == 'object' && server.ip && server.port) {
				this._server = 'http://' + server.ip + ':' + server.port;
			}
			else if (typeof server == 'string') {
				this._server = server;
			}
			else {
				this._server = '';
			}
		}
	});
}

SqueezeJS.getPlayer = SqueezeJS.Controller.getPlayer;

Ext.apply(SqueezeJS, {
	loadStrings : function(strings) {
		var newStrings = '';
		for (var x = 0; x < strings.length; x++) {
			if (!this.Strings[strings[x].toLowerCase()] > '') {
				newStrings += strings[x] + ',';
			}
		}
		
		if (newStrings > '') {
			newStrings = newStrings.replace(/,$/, '');
			this.Controller.request({
				params: [ '', [ 'getstring', newStrings ] ],
				scope: this,
				
				success: function(response) {
					if (response && response.responseText) {
						response = Ext.util.JSON.decode(response.responseText);
						for (x in response.result) {
							this.Strings[x.toLowerCase()] = response.result[x]; 
						}
					}
				}
			})
		}
	},

	loadString : function(string) {
		this.loadStrings([string]);
	}
});

SqueezeJS.SonginfoParser = {
	tpl : {
		raw : {
			title : new Ext.Template('{title}'),
			album : new Ext.Template('{album}'),
			contributor : new Ext.Template('{contributor}'),
			year : new Ext.Template('{year}'),
			coverart : new Ext.Template('<img src="{src}" srcset="{srcset}" {width} {height}>')
		},
		linked : {
			title : new Ext.Template('<a href="' + webroot +'{link}?player={player}&amp;item={id}" target="browser">{title}</a>'),
			album : new Ext.Template('<a href="' + webroot + 'clixmlbrowser/clicmd=browselibrary+items&amp;mode=albums&amp;linktitle={title}&amp;album_id={id}&amp;player={player}/index.html?index=0" target="browser">{album}</a>'),
			contributor : new Ext.Template('<a href="' + webroot + 'clixmlbrowser/clicmd=browselibrary+items&amp;mode=albums&amp;linktitle={title}&amp;artist_id={id}&amp;player={player}/" target="browser">{contributor}</a>'),
			year : new Ext.Template('<a href="' + webroot + 'clixmlbrowser/clicmd=browselibrary+items&amp;mode=albums&amp;linktitle={title}&amp;year={year}&amp;player={player}/" target="browser">{year}</a>'),
			coverart : new Ext.Template('<a href="' + webroot + '{link}?player={player}&amp;item={id}" target="browser"><img src="{src}" srcset="{srcset}" {width} {height}></a>')
		}
	},

	title : function(result, noLink, noTrackNo){
		var title;
		var link;
		var id;

		if (result.playlist_tracks > 0) {
			if (noTrackNo)
				title = result.playlist_loop[0].title;

			else
				title = (result.playlist_loop[0].disc && result.playlist_loop[0].disccount > 1 ? result.playlist_loop[0].disc + '-' : '')
						+ (result.playlist_loop[0].tracknum ? result.playlist_loop[0].tracknum + ". " : '')
						+ result.playlist_loop[0].title;

			link = result.playlist_loop[0].info_link || 'songinfo.html';
			id = result.playlist_loop[0].id;
		}

		return this.tpl[(noLink ? 'raw' : 'linked')].title.apply({
			link: link,
			id: id,
			title: title,
			player: SqueezeJS.getPlayer()
		});
	},

	album : function(result, noLink, noRemoteTitle){
		var album = '';
		var id = null;

		if (result.playlist_tracks > 0) {
			if (result.playlist_loop[0].album) {
				if (result.playlist_loop[0].album_id)
					id = result.playlist_loop[0].album_id;
	
				album = result.playlist_loop[0].album;
			}
	
			else if (result.playlist_loop[0].remote_title && !noRemoteTitle)
				album = result.playlist_loop[0].remote_title;
	
			else if (result.current_title) 
				album = result.current_title;
		}

		return this.tpl[((noLink || id == null) ? 'raw' : 'linked')].album.apply({
			id: id,
			album: album,
			title: encodeURIComponent(SqueezeJS.string("album") + ' (' + album + ')'),
			player: SqueezeJS.getPlayer()
		});
	},

	contributors : function(result, noLink){
		var currentContributors = new Array();
		var contributorRoles = SqueezeJS.contributorRoles;

		var contributorList = '';
		if (result.playlist_tracks > 0) {
			for (var x = 0; x < contributorRoles.length; x++) {
				if (result.playlist_loop[0][contributorRoles[x]]) {
					var ids = result.playlist_loop[0][contributorRoles[x] + '_ids'] ? result.playlist_loop[0][contributorRoles[x] + '_ids'].split(', ') : new Array();

					// Don't split the artist name if we only have a single id. Or Earth would no longer play with Wind & Fire.
					var contributors = ids.length != 1
						? result.playlist_loop[0][contributorRoles[x]].split(', ')
						: new Array(result.playlist_loop[0][contributorRoles[x]]);

					for (var i = 0; i < contributors.length; i++) {
						// only add to the list if it's not already in there
						if (!currentContributors[contributors[i]]) {
							currentContributors[contributors[i]] = 1;
	
							if (contributorList)
								contributorList += ', ';

							contributorList += this.tpl[((ids[i] && !noLink) ? 'linked' : 'raw')].contributor.apply({ 
								id: (ids[i] || null),
								contributor: contributors[i],
								title: encodeURIComponent(SqueezeJS.string("artist") + ' (' + contributors[i] + ')'),
								player: SqueezeJS.getPlayer()
							});
						}
					}
				}
			}
		}

		return contributorList;
	},

	year : function(result, noLink){
		var year;

		if (result.playlist_tracks > 0 && parseInt(result.playlist_loop[0].year) > 0)
				year = parseInt(result.playlist_loop[0].year);

		return this.tpl[(noLink || !year ? 'raw' : 'linked')].year.apply({
			year: year,
			title: encodeURIComponent(SqueezeJS.string("year") + ' (' + year + ')'),
			player: SqueezeJS.getPlayer()
		});
	},

	bitrate : function(result){
		var bitrate = '';

		if (result.playlist_tracks > 0 && result.playlist_loop[0].bitrate) {
			bitrate = result.playlist_loop[0].bitrate
				+ (result.playlist_loop[0].type
					? ', ' + result.playlist_loop[0].type
					: ''
				);
		}

		return bitrate;
	},

	coverart : function(result, noLink, width){
		var coverart = this.defaultCoverart(0, width);
		var id = -1;
		var link;

		if (result.playlist_tracks > 0) {
			coverart = this.coverartUrl(result, width);

			if (result.playlist_loop[0].id) {
				id = result.playlist_loop[0].id;
				link = result.playlist_loop[0].info_link || 'songinfo.html';
			}
		}
		
		if (coverart.search(/^http/) == -1 && coverart.search(/^\//) == -1)
			coverart = webroot + coverart;
		
		return this.tpl[((noLink || id == null || id < 0) ? 'raw' : 'linked')].coverart.apply({
			id: id,
			src: coverart,
			srcset: coverart.replace(width + 'x' + width, width*2 +'x' + width*2) + ' 2x',
			width: width ? 'width="' + width + '"' : '',
			height: width ? 'height="' + width + '"' : '',
			link: link
		});
	},

	coverartUrl : function(result, width){
		var coverart = this.defaultCoverart(0, width);
		var link;
		if (result.playlist_tracks > 0) {
			if (result.playlist_loop[0].artwork_url) {
				coverart = result.playlist_loop[0].artwork_url;

				var publicURL = (coverart.search(/^http:/) != -1);
				
				if (publicURL) {
					var parts = coverart.match(/^http:\/\/(.+)/);
					
					// don't use image proxy when dealing with private IP addresses
					if (parts && parts[1].match(/^\d+/) && (
						parts[1].match(/^192\.168\./) || parts[1].match(/^172\.(?:1[6-9]|2\d|3[01])\./) || parts[1].match(/^10\./)
					)) {
						publicURL = false;
					}
				}
				
				// SqueezeJS.externalImageProxy must be a template accepting url and size values
				if (coverart && width && SqueezeJS.externalImageProxy && publicURL) {
					coverart = SqueezeJS.externalImageProxy.apply({
						url: encodeURIComponent(coverart),
						size: width
					});
				}

				// some internal logos come without resizing parameters - add them here if size is defined
				else if (coverart && width && !publicURL) {
					coverart = coverart.replace(/(icon|image|cover)(\.\w+)$/, "$1_" + width + 'x' + width + "_p$2");
				}
			}
			else {
				coverart = this.defaultCoverart(result.playlist_loop[0].coverid || result.playlist_loop[0].artwork_track_id || result.playlist_loop[0].id, width);
			}
		}
		
		if (coverart.match(/^imageproxy/))
			coverart = '/' + coverart;

		return coverart;
	},
	
	defaultCoverart : function(coverid, width) {
		return SqueezeJS.Controller.getBaseUrl() + '/music/' + (coverid || 0) + '/cover' + (width ? '_' + width + 'x' + width + '_p.png' : '');
	}
};

SqueezeJS.Utils = {
	replacePlayerIDinUrl : function(url, id){
		if (!id)
			return url;

		if (typeof url == 'object' && url.search != null) {
			var args = Ext.urlDecode(url.search.replace(/^\?/, ''));

			args.player = id;

			if (args.playerid)
				args.playerid = id;

			return url.pathname + '?' + Ext.urlEncode(args) + url.hash;
		}

		var rExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;

		if (url.search(/player=/) && ! rExp.exec(url))
			url = url.replace(/player=/ig, '');

		return (rExp.exec(url) ? url.replace(rExp, '=' + id) : url + '&player=' + id);
	},

	formatTime : function(seconds){
		var remaining;

		if (seconds < 0) {
			remaining = true;
			seconds = Math.abs(seconds);
		}
		
		var hours = Math.floor(seconds / 3600);
		var minutes = Math.floor((seconds - hours*3600) / 60);
		seconds = Math.floor(seconds % 60);

		var formattedTime = (hours ? hours + ':' : '');
		formattedTime += (minutes ? (minutes < 10 && hours ? '0' : '') + minutes : '0') + ':';
		formattedTime += (seconds ? (seconds < 10 ? '0' : '') + seconds : '00');
		return (remaining ? '-' : '') + formattedTime;
	},

	toggleFavorite : function(el, url, title) {
		var el = Ext.get(el);
		if (el) {
			if (SqueezeJS.UI)
				SqueezeJS.UI.setProgressCursor(250);
				
			el.getUpdateManager().showLoadIndicator = false;
			el.load({
				url: 'plugins/Favorites/favcontrol.html?url=' + url + '&title=' + title + '&player=' + player,
				method: 'GET'
			});
		}
	},
	
	parseURI: function(uri) {
		var	parsed = uri.match(/^(?:(?![^:@]+:[^:@\/]*@)([^:\/?#.]+):)?(?:\/\/)?((?:(([^:@]*)(?::([^:@]*))?)?@)?([^:\/?#]*)(?::(\d*))?)(((\/(?:[^?#](?![^?#\/]*\.[^?#\/.]+(?:[?#]|$)))*\/?)?([^?#\/]*))(?:\?([^#]*))?(?:#(.*))?)/);
		var keys   = [
			"source",
			"protocol", 
			"authority", 
			"userInfo", 
			"user", 
			"password", 
			"host", 
			"port", 
			"relative", 
			"path", 
			"directory", 
			"file", 
			"query", 
			"anchor"
		];
		var parts = {};
		
		for (var i = keys.length; i--;) {
			parts[keys[i]] = parsed[i] || '';
		}

		parts.queryKey = {};

		parts.query.replace(/(?:^|&)([^&=]*)=?([^&]*)/g, function ($0, $1, $2) {
			if ($1) parts.queryKey[$1] = $2;
		});

		return parts;
	}
};

// our own cookie manager doesn't prepend 'ys-' to any cookie
if (Ext.state.CookieProvider) {
	SqueezeJS.CookieManager = new Ext.state.CookieProvider({
		expires : new Date(new Date().getTime() + 1000*60*60*24*365),
	
		readCookies : function(){
			var cookies = {};
			var c = document.cookie + ";";
			var re = /\s?(.*?)=(.*?);/g;
			var matches;
			while((matches = re.exec(c)) != null){
				var name = matches[1];
				var value = matches[2];
				if(name){
					cookies[name] = value;
				}
			}
			return cookies;
		},
	
		setCookie : function(name, value){
			document.cookie = name + "=" + value +
			((this.expires == null) ? "" : ("; expires=" + this.expires.toGMTString())) +
			((this.path == null) ? "" : ("; path=" + this.path)) +
			((this.domain == null) ? "" : ("; domain=" + this.domain)) +
			((this.secure == true) ? "; secure" : "");
		},
	
		clearCookie : function(name){
			document.cookie = name + "=null; expires=Thu, 01-Jan-70 00:00:01 GMT" +
				((this.path == null) ? "" : ("; path=" + this.path)) +
				((this.domain == null) ? "" : ("; domain=" + this.domain)) +
				((this.secure == true) ? "; secure" : "");
		}
	});
}

SqueezeJS.cookieExpiry = new Date(new Date().getTime() + 1000*60*60*24*365);

SqueezeJS.setCookie = function(name, value, expiry) {
	Ext.util.Cookies.set(name, value, expiry != null ? expiry : SqueezeJS.cookieExpiry);
};

SqueezeJS.getCookie = function(name) {
	return Ext.util.Cookies.get(name);
};

SqueezeJS.clearCookie = function(name) {
	this.setCookie(name, null);
	return Ext.util.Cookies.clear(name);
};

SqueezeJS.cookiesEnabled = function(){
	Ext.util.Cookies.set('_SqueezeJS-cookietest', true);
	
	if (Ext.util.Cookies.get('_SqueezeJS-cookietest')) {
		Ext.util.Cookies.clear('_SqueezeJS-cookietest');
		return true;
	}
	
	return false;
};


// XXX some legacy stuff - should eventually go away
// there to be compatible across different skins

function ajaxUpdate(url, params, callback) {
	var el = Ext.get('mainbody');

	if (el) {
		var um = el.getUpdateManager();

		if (um)
			um.loadScripts = true;

		if (!callback && SqueezeJS.UI)
			callback = SqueezeJS.UI.ScrollPanel.init;
			
		el.load(url, params + '&ajaxUpdate=1&player=' + player, callback);
	}
}

function ajaxRequest(url, params, callback) {
	if (typeof params == 'object')
		params = Ext.util.JSON.encode(params);

	Ext.Ajax.request({
		method: 'POST',
		url: url,
		params: params,
		timeout: 5000,
		disableCaching: true,
		callback: callback || function(){}
	});
}

// update the status if the Player is available
function refreshStatus() {
	try { SqueezeJS.Controller.getStatus();	}
	catch(e) {
		try { parent.SqueezeJS.Controller.getStatus(); }
		catch(e) {}
	}
}

function setCookie(name, value) {
	SqueezeJS.setCookie(name, value);
}

function resize(src, width) {
	if (!width) {
		// special case for IE (argh)
		if (document.all) //if IE 4+
			width = document.body.clientWidth*0.5;

		else if (document.getElementById) //else if NS6+
			width = window.innerWidth*0.5;

		width = Math.min(150, parseInt(width));
	}

	if (src.height > width && src.height > src.width)
		src.height = width;
	else if (src.width > width || !src.width)
		src.width = width;
}
