Ext.BLANK_IMAGE_URL = '/html/images/spacer.gif';
	
// hack to fake IE8 into IE7 mode - let's consider them the same
Ext.isIE7 = Ext.isIE7 || Ext.isIE8;

var SqueezeJS = {
	Strings : new Array(),
	string : function(s){ return this.Strings[s]; },
	
	contributorRoles : new Array('artist', 'composer', 'conductor', 'band', 'albumartist', 'trackartist'),
	coverFileSuffix : Ext.isIE && !Ext.isIE7 ? 'gif' : 'png',

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

		if (p.SqueezeJS && p.SqueezeJS.Controller) {
			// proxy to parent Controller
			SqueezeJS.Controller = p.SqueezeJS.Controller;
			return;
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

			this._initPlayerStatus();

			this.player = -1;
			this.events = this.events || {};
			this.addEvents({
				'playerselected'   : true,
				'playerlistupdate' : true,
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
								this.fireEvent('playerlistupdate', response.result);

								if (response.result.rescan || this.playerStatus.rescan) {
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
					if (this.playerStatus.duration > 0 
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
							SqueezeJS.setCookie('SqueezeCenter-player', playerobj.playerid);

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
				index: null,
				duration: null,
				playtime: 0,
				timestamp: null,
				dontUpdate: false,
				player: null,
				rescan: 0,
				canSeek: false
			}
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
				url: config.url || '/jsonrpc.js',
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
					params: [ "status", "-", 1, "tags:gABbehldiqtyrSuoKLN" ],
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

			this.fireEvent('playerstatechange', response);
	
			if (this._needUpdate(response) && Ext.get('playList'))
				this.fireEvent('playlistchange', response);
	
			this.playerStatus = {
				// if power is undefined, set it to on for http clients
				power:     (response.power == null) || response.power,
				mode:      response.mode,
				rate:      response.rate,
				current_title: response.current_title,
				title:     response.playlist_tracks > 0 ? response.playlist_loop[0].title : '',
				track:     response.playlist_tracks > 0 ? response.playlist_loop[0].url : '',
				index:     response.playlist_cur_index,
				duration:  parseInt(response.duration) || 0,
				canSeek:   response.can_seek ? true : false,
				playtime:  parseInt(response.time),
				timestamp: response.playlist_timestamp
			};
	
			if ((response.power != null) && !response.power) {
				this.playerStatus.power = 0;
			}
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
			amount *= 10;
			if (d)
				amount = d + amount;
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
					
					this._initPlayerStatus();
					this.fireEvent('playerselected', playerobj);
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

			activeplayer = activeplayer || SqueezeJS.getCookie('SqueezeCenter-player');
			if (response && response.players_loop) {
				for (var x=0; x < response.players_loop.length; x++) {
					if (response.players_loop[x].playerid == activeplayer || encodeURIComponent(response.players_loop[x].playerid) == activeplayer)
						return response.players_loop[x];
				}
			}		
		},

		getPlayer : function(){
			return SqueezeJS.Controller.player;
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
			coverart : new Ext.Template('<img src="{src}" {width} {height}>')
		},
		linked : {
			title : new Ext.Template('<a href="' + webroot +'{link}?player={player}&amp;item={id}" target="browser">{title}</a>'),
			album : new Ext.Template('<a href="' + webroot + 'browsedb.html?hierarchy=album,track&amp;level=1&amp;album.id={id}&amp;player={player}" target="browser">{album}</a>'),
			contributor : new Ext.Template('<a href="' + webroot + 'browsedb.html?hierarchy=contributor,album,track&amp;contributor.id={id}&amp;level=1&amp;player={player}" target="browser">{contributor}</a>'),
			year : new Ext.Template('<a href="' + webroot + 'browsedb.html?hierarchy=year,album,track&amp;level=1&amp;year.id={year}&amp;player={player}" target="browser">{year}</a>'),
			coverart : new Ext.Template('<a href="' + webroot + '{link}?player={player}&amp;item={id}" target="browser"><img src="{src}" {width} {height}></a>')
		}
	},

	title : function(result, noLink, noRemoteTitle, noTrackNo){
		var title;
		var link;
		var id;

		if (result.playlist_tracks > 0) {
			if (noTrackNo)
				title = result.playlist_loop[0].title;

			else
				title = (result.playlist_loop[0].disc ? result.playlist_loop[0].disc + '-' : '')
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

	album : function(result, noLink){
		var album = '';
		var id = null;

		if (result.playlist_tracks > 0) {
			if (result.playlist_loop[0].album) {
				if (result.playlist_loop[0].album_id)
					id = result.playlist_loop[0].album_id;
	
				album = result.playlist_loop[0].album;
			}
	
			else if (result.current_title) 
				album = result.current_title;
	
			else if (result.playlist_loop[0].remote_title)
				album = result.playlist_loop[0].remote_title;
		}

		return this.tpl[((noLink || id == null) ? 'raw' : 'linked')].album.apply({
			id: id,
			album: album,
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
					var contributors = result.playlist_loop[0][contributorRoles[x]].split(',');
					var ids = result.playlist_loop[0][contributorRoles[x] + '_ids'] ? result.playlist_loop[0][contributorRoles[x] + '_ids'].split(',') : new Array();
	
					for (var i = 0; i < contributors.length; i++) {
						// only add to the list if it's not already in there
						if (!currentContributors[contributors[i]]) {
							currentContributors[contributors[i]] = 1;
	
							if (contributorList)
								contributorList += ', ';

							contributorList += this.tpl[((ids[i] && !noLink) ? 'linked' : 'raw')].contributor.apply({ 
								id: (ids[i] || null),
								contributor: contributors[i],
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
			player: SqueezeJS.getPlayer()
		});
	},

	bitrate : function(result){
		var bitrate = '';

		if (result.playlist_tracks > 0 && result.playlist_loop[0].bitrate && result.remote) {
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
		var id = 0;
		var link;

		if (result.playlist_tracks > 0) {
			coverart = this.coverartUrl(result, width);

			if (result.playlist_loop[0].id) {
				id = result.playlist_loop[0].id;
				link = result.playlist_loop[0].info_link || 'songinfo.html';
			}
		}

		return this.tpl[((noLink || id == null) ? 'raw' : 'linked')].coverart.apply({
			id: id,
			src: coverart,
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
			}
			else {
				coverart = this.defaultCoverart(result.playlist_loop[0].id, width);
			}
		}

		return coverart;
	},
	
	defaultCoverart : function(id, width) {
		return '/music/' + (id || 0) + '/cover' + (width ? '_' + width + 'x' + width + '_p.' : '.') + SqueezeJS.coverFileSuffix;
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
			SqueezeJS.UI.setProgressCursor(250);
			el.getUpdateManager().showLoadIndicator = false;
			el.load({
				url: 'plugins/Favorites/favcontrol.html?url=' + url + '&title=' + title + '&player=' + player,
				method: 'GET'
			});
		}
	}
};

// our own cookie manager doesn't prepend 'ys-' to any cookie
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

SqueezeJS.setCookie = function(name, value) {
	SqueezeJS.CookieManager.set(name, value);
};

SqueezeJS.getCookie = function(name, failover) {
	return SqueezeJS.CookieManager.get(name, failover);
};

SqueezeJS.clearCookie = function(name, failover) {
	return SqueezeJS.CookieManager.clear(name);
};



// XXX some legacy stuff - should eventually go away
// there to be compatible across different skins

function ajaxUpdate(url, params, callback) {
	var el = Ext.get('mainbody');

	if (el) {
		var um = el.getUpdateManager();

		if (um)
			um.loadScripts = true;

		el.load(url, params + '&ajaxUpdate=1&player=' + player, callback || SqueezeJS.UI.ScrollPanel.init);
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

	if (src.width > width || !src.width)
		src.width = width;

}
