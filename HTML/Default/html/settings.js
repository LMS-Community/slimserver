Settings = function(){
	var tp;

	return {
		init : function(){
			var layout = new Ext.BorderLayout('mainbody', {
				north: {
					split:false,
					initialSize: 40
				},
				south: {
					split:false,
					initialSize: 16
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

			// IE6 needs two tries...
			if (Ext.isIE && !Ext.isIE7)
				Ext.EventManager.onDocumentReady(this.onResize, layout, true);

			Ext.QuickTips.init();

			tp = new Ext.TabPanel('settingsTabs', {
				// overwriting default activate method:
				// don't check whether the clicked tab is already active 
				activate : function(id){
					var tab = this.items[id];
					if(!tab){
						return null;
					}
					var e = {};
					this.fireEvent("beforetabchange", this, e, tab);
					if(e.cancel !== true && !tab.disabled){
						if(this.active){
							this.active.hide();
						}
						this.active = this.items[id];
						this.active.show();
						this.fireEvent("tabchange", this, this.active);
					}
					return tab;
				}			
			});

			tp.on('beforetabchange', function(tb, ev, tab){
				var modified = false;

				try { modified = frames.settings.subSettings.SettingsPage.isModified(); }
				catch(e){
					try { modified = frames.settings.SettingsPage.isModified(); }
					catch(e){}
				}

				if (modified) {
					Ext.Msg.show({
						title: strings['settings'],
						msg: strings['settings_changed_confirm'],
						width: 300,
						closable: false,
						buttons: {
							yes: strings['yes'],
							no: strings['no'],
							cancel: strings['cancel']
						},
						fn: function(btn, a, b){
							if (btn == 'yes') {
								if (!Settings.submitSettings()) {
									// dirty hack to give Opera a second to finish the submit...
									if (Ext.isOpera) {
										var date = new Date();
										var curDate = null;
										do { curDate = new Date(); } 
										while(curDate-date < 500);
									}

									Settings.resetModified();
									Settings.activateTab(tab.id);
								}
							}

							else if (btn == 'no') {
								Settings.resetModified();
								Settings.activateTab(tab.id);
							}
						}
					});

					ev.cancel = true;
				}
			});

			tp.addTab('BASIC_SERVER_SETTINGS', strings['basic']).on('activate', Settings.showSettingsPage);
			tp.addTab('players', strings['players']).on('activate', Settings.showSettingsPage);
			tp.addTab('BEHAVIOR_SETTINGS', strings['mymusic']).on('activate', Settings.showSettingsPage);
			tp.addTab('SQUEEZENETWORK_SETTINGS', strings['squeezenetwork']).on('activate', Settings.showSettingsPage);

			if (iTunesEnabled)
				tp.addTab('ITUNES', strings['itunes']).on('activate', Settings.showSettingsPage);

			tp.addTab('INTERFACE_SETTINGS', strings['interface']).on('activate', Settings.showSettingsPage);
			tp.addTab('SETUP_GROUP_PLUGINS', strings['plugins']).on('activate', Settings.showSettingsPage);

			if (podcastEnabled)
				tp.addTab('PLUGIN_PODCAST', strings['podcasts']).on('activate', Settings.showSettingsPage);

			tp.addTab('advanced', strings['advanced']).on('activate', Settings.showSettingsPage);
			tp.addTab('SERVER_STATUS', strings['status']).on('activate', Settings.showSettingsPage);

			tp.activate('BASIC_SERVER_SETTINGS');

			new Ext.Button('cancel', {
				text: strings['close'],
				handler: function(){
					window.open('javascript:window.close();','_self','');
				}
			});

			new Ext.Button('save', {
				text: strings['apply'],
				handler: this.submitSettings,
				scope: this
			});

			layout.endUpdate();

			this.onResize();
		},

		submitSettings : function() {
			try { frames.settings.subSettings.SettingsPage.submit() }
			catch(e){
				try { frames.settings.SettingsPage.submit() }
				catch(e){}
			}
		},

		resetModified : function() {
			try { frames.settings.subSettings.SettingsPage.resetModified(); }
			catch(e){
				try { frames.settings.SettingsPage.resetModified(); }
				catch(e){}
			}
		},

		showSettingsPage : function(page) {
			if (page && tabLinks[page])
				page = tabLinks[page];
			else if (typeof page == 'object' && page.el != null)
				page = tabLinks[this.id];

			Ext.get('maincontent').dom.src = webroot + page + (page.search(/\?/) >= 0 ? '&' : '?') + 'player=' + player;
		},

		// resize panels, folder selectors etc.
		onResize : function(){
			var body = Ext.get(document.body);

			var dimensions = new Array();
			dimensions['maxHeight'] = body.getHeight() - body.getMargins('tb');

			var bg = Ext.get('background');
			bg.setWidth(body.getWidth() - (Ext.isIE && !Ext.isIE7 ? body.getMargins('rl') : 0));
			bg.setHeight(dimensions['maxHeight']);

			Ext.get('mainbody').setHeight(dimensions['maxHeight']);
			Ext.get('maincontent').setHeight(dimensions['maxHeight']-140);

			try { this.layout(); }
			catch(e){}
		},

		activateTab : function(tab){
			tp.activate(tab);
		}
	};
}();


var SettingsPage = function(){
	var unHighlightTimer;
	var invalidWarned = false;
	var modified = false;

	return {
		init : function(){
			this.initDescPopup();
			FilesystemBrowser.init();

			var items = Ext.query('input');
			for(var i = 0; i < items.length; i++) {

				if (inputEl = Ext.get(items[i])) {
					if (inputEl.dom.type == 'submit')
						continue;

					inputEl.on('keypress', function(ev){
						// on Mac I get 12 instead of 13 (RETURN) on Enter
						if (ev.button == ev.RETURN || ev.button == 12) {
							ev.stopEvent();
							SettingsPage.submit();
						}
					});
				}
			}

			Ext.select('input, textarea, select').on('change', function(ev){
				modified = true;
			});

			this.showWarning();
		},

		initDescPopup : function(){
			var section, descEl, desc, helpEl, title;

			var tpl = new Ext.Template('<img src="' + webroot + 'html/images/details.gif" class="prefHelp">');
			tpl.compile();

			Ext.QuickTips.init();

			var items = Ext.query('div.hiddenDesc');
			for(var i = 0; i < items.length; i++) {
				descEl = Ext.get(items[i]);

				if (descEl)
					section = descEl.up('div.settingGroup', 1) || Ext.get(items[i]).up('div.settingSection', 1);
				else
					continue;

				title = section.child('div.prefHead');
				if (title)
					title = title.dom.innerHTML;

				if (section && (desc = descEl.dom.innerHTML)) {
						helpEl = tpl.insertAfter(descEl);
						Ext.QuickTips.register({
							target: helpEl,
							text: desc,
							title: title,
							maxWidth: 600,
							autoHide: false
						});
				}
			}
		},

		// remove sticky highlight from previously selected item
		onClicked : function(target){
			var el = Ext.get(target);
			if (el && el.hasClass('mouseOver')) {
				if (el = Ext.get(Ext.DomQuery.selectNode('div.selectedItem')))
					el.removeClass('selectedItem');
	
				if (el = Ext.get(target.id))
					el.addClass('selectedItem');
			}
		},

		highlight : function(target){
			if (Utils) {
				if (unHighlightTimer == null)
					unHighlightTimer = new Ext.util.DelayedTask(Utils.unHighlight);
					
				Utils.highlight(target);
				unHighlightTimer.delay(1000);	// remove highlighter after x seconds of inactivity
			}
		},

		initPlayerList : function(){
			if (!Ext.get('playerSelector'))
				return;

			var playerChooser = new Ext.SplitButton('playerSelector', {
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

			for (x=0; x<playerList.length; x++){
				if (playerList[x].id == playerid || playerList[x].id == player) {
					playerChooser.setText(playerList[x].name);
				}

				playerChooser.menu.add(
					new Ext.menu.Item({
						text: playerList[x].name,
						value: playerList[x].id,
						cls: 'playerList',
						handler: function(ev){
							location = Utils.replacePlayerIDinUrl(location, ev.value);
						}
					})
				);
			}
		},

		initSettingsList : function(){
			if (!Ext.get('settingsSelector'))
				return;

			var settingsChooser = new Ext.SplitButton('settingsSelector', {
				handler: function(ev){
					if(this.menu && !this.menu.isVisible()){
						this.menu.show(this.el, this.menuAlign);
					}
					this.fireEvent('arrowclick', this, ev);
				},
				menu: new Ext.menu.Menu({shadow: Ext.isGecko && Ext.isMac ? true : 'sides'}),
				tooltip: strings['settings'],
				arrowTooltip: strings['settings'],
				tooltipType: 'title'
			});

			for (x=0; x<settingsList.length; x++){
				if (settingsList[x].id == page) {
					settingsChooser.setText(settingsList[x].name);
				}

				settingsChooser.menu.add(
					new Ext.menu.Item({
						text: settingsList[x].name,
						value: settingsList[x].url,
						cls: 'settingsList',
						handler: function(ev){
							location.href = webroot + ev.value + 'player=' + playerid + '&playerid=' + playerid;
						}
					})
				);
			}
		},

		validatePref : function(myPref, namespace) {
			Utils.processCommand({
				params: ['', [
							'pref', 
							'validate', 
							namespace + ':' + myPref, 
							Ext.get(myPref).dom.value
						]],
				success: function(response) {
					if (response && response.responseText) {
						response = Ext.util.JSON.decode(response.responseText);

						// if preference did not validate - highlight the field
						if (response.result)
							SettingsPage.highlightField(myPref, response.result.valid);
					}
				}
				
			});
		},

		submit : function(){
			var items = Ext.query('input.invalid');

			for(var i = 0; i < items.length; i++) {
				if (inputEl = Ext.get(items[i])) {
					SettingsPage.highlightField(inputEl.id, false);
				}
			}

			// block first attempt to save if there are invalid values
			if (items.length == 0 || invalidWarned)
				document.forms.settingsForm.submit();
			else
				invalidWarned = true;

			return invalidWarned;
		},

		highlightField : function(myPref, valid){
			var el = Ext.get(myPref);
			
			if (el) {
				el.highlight(valid ? '99ff99' : 'ffcccc');

				if (valid)
					el.replaceClass('invalid', 'valid');
				else
					el.replaceClass('valid', 'invalid');
			}
		},

		showWarning : function(){
			var reload;
			if (reload = Ext.get('popupWarning')) {
				Ext.Msg.alert(strings['settings'], 
					Ext.util.Format.stripTags(
						reload.dom.innerHTML.replace(/<br\/?>/ig, ' ')
					)
				);
				reload.update('');
			}
		},

		isModified : function(){
			var fields = document.forms.settingsForm.elements;
			for (x=0; x<fields.length; x++) {
				document.forms['settingsForm'].elements[x].blur();
			}

			return modified;
		},

		resetModified : function(){
			modified = false;
		}
	};
}();
