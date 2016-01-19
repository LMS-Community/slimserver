Main = {
	background : Ext.get('background'),
	body : Ext.get(document.body),
	layout : null,

	init : function(){
		// overwrite some default Ext values
		Ext.UpdateManager.defaults.indicatorText = '<div class="loading-indicator">' + SqueezeJS.string('loading') + '</div>';
		SqueezeJS.UI.buttonTemplate = new Ext.Template(
			'<table border="0" cellpadding="0" cellspacing="0"><tbody><tr>',
			'<td></td><td><button type="{0}" style="padding:0" class="x-btn-text {2}"></button></td><td></td>',
			'</tr></tbody></table>'
		);
		SqueezeJS.UI.buttonTemplate.compile();

		SqueezeJS.UI.splitButtonTemplate = new Ext.Template(
			'<table id="{4}" cellspacing="0" class="x-btn {3}"><tbody class="{1}">',
			'<tr><td class="x-btn-ml"><i>&#160;</i></td><td class="x-btn-mc"><em class="{2}" unselectable="on"><button type="{0}"></button></em></td><td class="x-btn-mr"><i>&#160;</i></td></tr>',
			'</tbody></table>'
		);
		SqueezeJS.UI.splitButtonTemplate.compile();

		Ext.state.Manager.setProvider(new Ext.state.CookieProvider({
			expires: new Date(new Date().getTime()+(60*60*24*365*1000))
		}));

		var leftpanel = {
			region: 'center',
			layout: 'border',
			items: [
				{
					region: 'north',
					contentEl: 'leftheader',
					border: false,
					height: 12
				},
				{
					region: 'center',
					border: false,
					contentEl: 'leftcontent'
				},
				{
					region: 'south',
					contentEl: 'leftfooter',
					border: false,
					height: 12
				}
			],
			border: false,
			split: true,
			minSize: 200,
			width: '50%'
		};

		var rightpanel = {
			region: 'east',
			layout: 'border',
			items: [
				{
					region: 'north',
					contentEl: 'rightheader',
					border: false,
					height: 12
				},
				{
					region: 'center',
					border: false,
					contentEl: 'rightcontent'
				},
				{
					region: 'south',
					contentEl: 'rightfooter',
					border: false,
					height: 12
				}
			],
			border: false,
			split: true,
			collapsible: true,
			collapseMode: 'mini',
			minSize: 400,
			listeners: {
				expand: function() {
					this.playlist.onResize();
					new Ext.util.DelayedTask(function(){ this.playlist.onResize(); }, this).delay(250);
				},
				scope: this
			},
			width: '50%',
			stateId: 'Squeezebox-panelWidth',
			stateful: true,
			header: false
		};

		var mainpanel = {
			layout: 'border',
			border: false,
			style: 'z-index: 200;',
			renderHidden: true,
			items: [
				{
					region: 'north',
					contentEl: 'header',
					border: false,
					margins: '5 5 0 5',
					height: 40
				},
				
				{
					region: 'center',
					layout: 'border',
					border: false,
					margins: '0 15',
					items: [leftpanel, rightpanel]
				},

				{
					region: 'south',
					contentEl: 'footer',
					border: false,
					margins: '0 5 5 5',
					height: 40
				}
			]
		};

		this.layout = new Ext.Viewport(mainpanel);

		var el;
		if (el = Ext.get('scanWarning'))
			el.setVisibilityMode(Ext.Element.DISPLAY);

		if (el = Ext.get('newVersion'))
			el.setVisibilityMode(Ext.Element.DISPLAY);


		// initialize global controller, which is responsible for all communication with SC
		SqueezeJS.Controller.init({
			player: playerid
		});

		// initialize player control panel
		this.initPlayerControl();

		new SqueezeJS.UI.Buttons.PlayerDropdown({
			renderTo: 'playerChooser'
		});

		// initialize the playlist (right hand side) panel
		this._playlistInit();

		// initialize message area in footer
		this.showBrieflyArea = new SqueezeJS.UI.ShowBriefly({
			renderTo: 'footerInfoText'
		});


		// initialize scanner progress info in footer
		new SqueezeJS.UI.ScannerInfo({
			renderTo: 'scanWarning',
			name: 'progressName',
			info: 'progressInfo',
			done: 'progressDone',
			total: 'progressTotal'
		});

		// register event handler for left hand side frame: refresh when player is switched
		SqueezeJS.Controller.on({
			playerselected: {
				fn: this.onPlayerSelected
			}
		});

		Ext.get('loading').hide();
		Ext.get('loading-mask').hide();

		// cache the offsets we're going to use to resize the background image
		this.offsets = [
			this.background.getTop() * 2,
			this.background.getLeft() * 2
		];

		Ext.EventManager.onWindowResize(this.onResize, this);
		this.onResize(this.body.getWidth(), this.body.getHeight());
		
		if (!SqueezeJS.cookiesEnabled())
			Ext.MessageBox.alert(SqueezeJS.string('squeezebox_server'), SqueezeJS.string('web_no_cookies_warning'));
	},

	onResize : function(width, height) {
		Ext.util.CSS.updateRule('.x-menu-list', 'max-height', (height - 50) + 'px');
		this.background.setHeight(height - this.offsets[0]);
		this.background.setWidth(width - this.offsets[1]);
	},

	onPlayerSelected : function(playerobj) {
		if (playerobj && playerobj.playerid)
			playerobj = playerobj.playerid
		else
			playerobj = SqueezeJS.getPlayer();

		// set the browser frame to use the selected player
		if (frames.browser && frames.browser.location && frames.browser.location.protocol.match(/^http/)) {
			frames.browser.location = SqueezeJS.Utils.replacePlayerIDinUrl(frames.browser.location, playerobj);
		}

		// make the settings link use the new player ID
		var el;
		if (el = Ext.get('settingsHRef')) {
			el.dom.href = SqueezeJS.Utils.replacePlayerIDinUrl(el.dom.href, playerobj);
		}
		if (el = Ext.get('settingsBtn')) {
			el.dom.href = SqueezeJS.Utils.replacePlayerIDinUrl(el.dom.href, playerobj);
		}		
	},

	initPlayerControl : function(){
		new SqueezeJS.UI.Buttons.Rew({
			renderTo: 'ctrlPrevious',
			noText:   true,
			minWidth: 31
		});

		new SqueezeJS.UI.Buttons.Play({
			renderTo: 'ctrlTogglePlay',
			noText:   true,
			minWidth: 31
		});

		new SqueezeJS.UI.Buttons.Fwd({
			renderTo: 'ctrlNext',
			noText:   true,
			minWidth: 31
		});

		new SqueezeJS.UI.Buttons.Repeat({
			renderTo: 'ctrlRepeat',
			noText:   true,
			minWidth: 31
		});

		new SqueezeJS.UI.Buttons.Shuffle({
			renderTo: 'ctrlShuffle',
			noText:   true,
			minWidth: 31
		});

		new SqueezeJS.UI.Buttons.VolumeDown({
			renderTo: 'ctrlVolumeDown',
			noText:   true,
			minWidth: 27
		});

		new SqueezeJS.UI.Buttons.VolumeUp({
			renderTo: 'ctrlVolumeUp',
			noText:   true,
			minWidth: 27
		});

		new SqueezeJS.UI.VolumeBar({
			el: 'ctrlVolume',
			marginLeft: 7,
			marginRight: 6
		});

		new SqueezeJS.UI.Buttons.Power({
			renderTo: 'ctrlPower',
			noText:   true,
			minWidth: 24
		});

		new SqueezeJS.UI.Title('ctrlCurrentTitle');
		new SqueezeJS.UI.CompoundTitle('ctrlCurrentSongInfoCollapsed');
		new SqueezeJS.UI.Album('ctrlCurrentAlbum');
		new SqueezeJS.UI.Contributors('ctrlCurrentArtist');
		new SqueezeJS.UI.Bitrate('ctrlBitrate');
		new SqueezeJS.UI.CurrentIndex('ctrlPlayNum');
		new SqueezeJS.UI.SongCount('ctrlSongCount');
		
		new SqueezeJS.UI.Playtime('ctrlPlaytime');
		new SqueezeJS.UI.CompoundPlaytime('ctrlPlaytimeCollapsed');
		new SqueezeJS.UI.PlaytimeRemaining('ctrlRemainingTime');
		new SqueezeJS.UI.PlaytimeProgress('ctrlProgress');

		new SqueezeJS.UI.Coverart({
			el: 'ctrlCurrentArt',
			size: 96
		});

		new SqueezeJS.UI.CoverartPopup({
			target: 'ctrlCurrentArt',
			defaultAlign: 'tl-bl'
		});

		// display song information with coverart in the collapsed mode
		new SqueezeJS.UI.CoverartPopup({
			target: 'nowPlayingIcon',
			defaultAlign: 'tl-bl',
			songInfo: true
		});

		new SqueezeJS.UI.Button({
			renderTo: 'ctrlCollapse',
			cls:      'btn-collapse-player',
			tooltip:  SqueezeJS.string('collapse'),
			minWidth: 18,
			noText:   true,
			scope:    this,
			handler:  this.collapseExpand
		});

		if (Ext.get('ctrlUndock')) {
			new SqueezeJS.UI.Button({
				renderTo: 'ctrlUndock',
				cls:      'btn-undock',
				tooltip:  SqueezeJS.string('undock'),
				minWidth: 16,
				noText:   true,
				scope:    this,
				handler:  function(){
					window.open(webroot + 'status_header.html?player=' + SqueezeJS.Controller.getPlayer(), 'playerControl', 'width=500,height=100,status=no,menubar=no,location=no,resizable=yes');
				}
			});
		}

		var el;
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
			doExpand: (SqueezeJS.getCookie('Squeezebox-expandPlayerControl') != 'false')
		});

		new SqueezeJS.UI.Button({
			renderTo: 'ctrlExpand',
			cls:      'btn-expand-player',
			tooltip:  SqueezeJS.string('expand'),
			minWidth: 18,
			noText:   true,
			scope:    this,
			handler:  this.collapseExpand
		});

	},

	_playlistInit : function(){
		this.playlist = new SqueezeJS.UI.Playlist({
			renderTo: 'playlistPanel',			// the panel where the playlist will be displayed
			playlistEl: 'playList',				// the actual playlist (the panel less the navigation bar, buttons etc.)
			currentSelector: 'div.currentSong'	// selector for the current playlist item
		});

		this.playlist.Highlighter = new SqueezeJS.UI.Highlight();

		this.playlist.onUpdated = function(o){
			var items = Ext.DomQuery.select('#' + this.playlistEl + ' div.draggableSong');
			if (items.length > 0) {
				if (Ext.get('btnPlaylistToggleArtwork')) {
					var noCover = SqueezeJS.getCookie('Squeezebox-noPlaylistCover') == '1';
					var menu = new Ext.menu.Menu({
						items: [
							new Ext.menu.CheckItem({
								text: SqueezeJS.string('hide_artwork'),
								cls: 'albumList',
								handler: function(){
									SqueezeJS.setCookie('Squeezebox-noPlaylistCover', 1);
									this.load();
								}.createDelegate(this),
								group: 'noCover',
								checked: noCover
							}),
							new Ext.menu.CheckItem({
								text: SqueezeJS.string('show_artwork'),
								cls: 'albumXList',
								handler: function(){
									SqueezeJS.setCookie('Squeezebox-noPlaylistCover', 0);
									this.load();
								}.createDelegate(this),
								group: 'noCover',
								checked: !noCover
							})
						]
					});
	
					new SqueezeJS.UI.SplitButton({
						renderTo: 'btnPlaylistToggleArtwork',
						icon: webroot + 'html/images/albumlist' + (noCover ? '2' : '0')  + '.gif',
						cls: 'x-btn-icon',
						menu: menu,
						arrowTooltip: SqueezeJS.string('coverart')
					});
				}
	
				new SqueezeJS.UI.Button({
					renderTo: 'btnPlaylistClear',
					cls:      'btn-playlist-clear',
					tooltip:  SqueezeJS.string('clear_playlist'),
					minWidth: 32,
					noText:   true,
					handler:  function(){
						SqueezeJS.Controller.playerControl(['playlist', 'clear']);
						this.load();							// Bug 5709: force playlist to clear
					}.createDelegate(this)
				});

				new SqueezeJS.UI.Button({
					renderTo: 'btnPlaylistSave',
					cls:      'btn-playlist-save',
					tooltip:  SqueezeJS.string('save'),
					minWidth: 32,
					noText:   true,
					handler:  function(){
						frames.browser.location = webroot + 'edit_playlist.html?player=' + SqueezeJS.Controller.getPlayer() + '&saveCurrentPlaylist=1';
					}
				});

				this.Highlighter.init({
					unHighlight : 'playList'
				});
			}
		};

		// IE sucks. It needs a special invitation to load the list.
		if (Ext.isIE)
			this.playlist.load();
	},

	collapseExpand : function(ev){
		var expandCookie = SqueezeJS.getCookie('Squeezebox-expandPlayerControl');
		expandCookie = expandCookie == 'false' ? false : true;
		
		var doExpand = ev.doExpand == null ? !expandCookie : ev.doExpand;

		var art = Ext.get('ctrlCurrentArt');

		// work around Safari 2 crasher: resize and hide artwork before hiding surrounding DIV
		if (art && !doExpand) {
			art.setHeight(0);
			art.hide();
		}

		var el;
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

		SqueezeJS.setCookie('Squeezebox-expandPlayerControl', doExpand);

		// resize the window if in undocked mode
		var el = Ext.get('ctrlUndock');
		if (el && !el.isVisible()) {
			var width = Ext.get(document.body).getWidth();
			var height = doExpand ? 200 : 115

			if (Ext.isOpera && doExpand) {
				height += 15;
			}

			window.resizeTo(width, height);
		}

		try { this.playlist.onResize(); }
		catch(e) {}
	}

};

