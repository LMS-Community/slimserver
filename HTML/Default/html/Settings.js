Settings = {
	background : null,
	body : null,
	layout : null,
	tp: null,

	init : function(settingsTabs, activeTab){
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
					items: [
						{
							region: 'north',
							contentEl: 'inner_header',
							border: false,
							height: 32,
							margins: '0 15'
						},
						{
							region: 'center',
							contentEl: 'maincontent',
							border: false,
							margins: '0 15'
						},
						{
							region: 'south',
							contentEl: 'inner_footer',
							border: false,
							height: 43,
							margins: '0 15'
						}
					]
				},

				{
					region: 'south',
					contentEl: 'footer',
					border: false,
					margins: '0 5 5 5',
					height: 16
				}
			]
		}

		this.layout = new Ext.Viewport(mainpanel);
		this.background = Ext.get('background');
		this.body = Ext.get(document.body);
		this.maincontent = Ext.get('maincontent');

		SqueezeJS.clearCookie('Squeezebox-playersettings');
		SqueezeJS.clearCookie('Squeezebox-advancedsettings');

		// cache the offsets we're going to use to resize the background image
		this.offsets = [
			this.background.getTop() * 2,
			this.background.getLeft() * 2,
			this.maincontent.getTop() + this.body.getHeight() - Ext.get('inner_footer').getTop()
		];

		this.tp = new Ext.TabPanel({
			renderTo: 'settingsTabs',
			plain: true,
			enableTabScroll: true,
			animScroll: false,
			defaults: {
				listeners: {
					activate: this.showSettingsPage
				}
			},
			activeTab: activeTab,
			items: settingsTabs
		});

		this.tp.on('beforetabchange', function(tb, tab, ev) {
			var modified = false;
			
			try { modified = frames.settings.Settings.Page.isModified(); }
			catch(e){}
			
			if (!modified)
				return true;
				
			return Settings._confirmPageChange(function(btn, a, b){
				if (btn == 'no' || btn == 'yes') {
					if (btn == 'yes') {
						this.submitSettings(function() {
							tb.activate(tab);
						});

					}

					this._resetModified();

					if (btn == 'no') {
						tb.activate(tab);
					}
				}

			}.createDelegate(this));
		}, this);

		new Ext.Button({
			renderTo: 'cancel',
			text: SqueezeJS.string('close'),
			handler: function(){
				window.open('javascript:window.close();','_self','');
			}
		});

		new Ext.Button({
			renderTo: 'save',
			text: SqueezeJS.string('apply'),
			handler: function() {
				this.submitSettings()
			},
			scope: this
		});

		Ext.EventManager.onWindowResize(this.onResize, this);
		this.onResize(this.body.getWidth(), this.body.getHeight());
	},

	showSettingsPage : function(page) {
		if (page.id == 'PLAYER') {
			var page2 = SqueezeJS.getCookie('Squeezebox-playersettings');

			if (page2 == null || page2 == 'null' || page2 == '')
				page = page.url || 'settings/player/basic.html?';
			else
				page = page2;
		}

		else if (page.id == 'ADVANCED_SETTINGS') {
			page = SqueezeJS.getCookie('Squeezebox-advancedsettings');

			if (page == null || page == 'null' || page == '')
				page = 'settings/server/formatting.html?';
		}

		if (typeof page == 'object' && page.url)
			page = page.url;
			
		if (page == null || page == 'null')
			page = 'settings/server/basic.html?'

		Ext.get('maincontent').dom.src = webroot + page + 'playerid=' + playerid;
	},

	activate : function(tab) {
		if (!this.tp)
			parent.Settings.activate(tab);

		else {
			this.tp.activate(tab);
		}
	},

	submitSettings : function(cb) {
		try { 
			frames.settings.Settings.Page.submit(cb);
		}
		catch(e){ return false; }
		return true;
	},

	onResize : function(width, height) {
		this.background.setHeight(height - this.offsets[0]);
		this.background.setWidth(width - this.offsets[1]);
		this.maincontent.setHeight(height - this.offsets[2]);
		this.tp.autoScrollTabs();
	},

	_resetModified : function() {
		try { frames.settings.Settings.Page.resetModified(); }
		catch(e){}
	},

	_isModified : function() {
		var modified = false;
		try { modified = frames.settings.Settings.Page.isModified(); }
		catch(e){}
		return modified;
	},
	
	_confirmPageChange : function(cb) {
		if (typeof cb == 'string') {
			var url = cb;
			cb = function(btn){
				if (btn == 'no' || btn == 'yes') {
					if (btn == 'yes') {
						this.submitSettings(function() {
							try { frames.settings.location = url; }
							catch(e) { location = url; }
						});
					}
					else if (btn == 'no') {
						try { frames.settings.location = url; }
						catch(e) { location = url; }
					}

					this._resetModified();
				}
			};
		}

		Ext.Msg.show({
			title: SqueezeJS.string('settings'),
			msg: SqueezeJS.string('settings_changed_confirm'),
			width: 300,
			closable: false,
			buttons: Ext.Msg.YESNOCANCEL,
			fn: cb,
			scope: this
		});
		return false;
	},
	
	resetPlayer : function(url) {
		Ext.Msg.show({
			title: SqueezeJS.string('reset_player'),
			msg: SqueezeJS.string('reset_player_confirm'),
			width: 300,
			closable: false,
			buttons: Ext.Msg.YESNO,
			fn: function(btn) {
				if (btn == 'yes') {
					location = url;
				}
			},
			scope: this
		});
	}
}

Settings.Page = function(){
	var invalidWarned = false;
	var modified = false;

	return {
		init : function(){
			this.initSliders();
			this.showWarning();
			this.initDescPopup();
			this.showRestartMessage();
			this.showRescanMessage();

			SqueezeJS.UI.FilesystemBrowser.init();
			SqueezeJS.UI.ScrollPanel.init();

			var items = Ext.query('input');
			for (var i = 0; i < items.length; i++) {
				var inputEl;

				if (inputEl = Ext.get(items[i])) {
					if (inputEl.dom.type == 'submit')
						continue;

					inputEl.on('keypress', function(ev){
						// on Mac I get 12 instead of 13 (RETURN) on Enter
						if (ev.button == ev.RETURN || ev.button == 12) {
							ev.stopEvent();
							Settings.Page.submit();
						}
					});
				}
			}

			Ext.select('input, textarea, select').on({
				change: {
					fn: this._checkModified
				},
				blur: {
					fn: this._checkModified
				}
			});
		},

		initDescPopup : function(){
			var section, descEl, desc, helpEl, title;

			var tpl = new Ext.Template('<img src="' + webroot + 'html/images/details.gif" class="prefHelp">');
			tpl.compile();

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
						helpEl = Ext.get(helpEl);
						Ext.apply(helpEl, {
							qt: new Ext.ToolTip({
									target: helpEl,
									html: desc,
									title: title,
									dismissDelay: 0,
									hideDelay: 3000,
									maxWidth: 300
								})
						});
						helpEl.on('click', function(){this.qt.show();})
				}
			}
		},

		initPlayerList : function(playerList){
			if (!Ext.get('playerSelector'))
				return;

			var playerChooser = new SqueezeJS.UI.SplitButton({
				renderTo: 'playerSelector',
				menu: new Ext.menu.Menu({shadow: Ext.isGecko && Ext.isMac ? true : 'sides'}),
				arrowTooltip: SqueezeJS.string('choose_player')
			});


			playerList = playerList.sort(function(a, b){
				a = a.name.toLowerCase();
				b = b.name.toLowerCase();
				return a > b ? 1 : (a < b ? -1 : 0);
			});

			for (var x=0; x<playerList.length; x++){
				if (playerList[x].current) {
					playerChooser.setText(playerList[x].name);
				}

				playerChooser.menu.add(
					new Ext.menu.CheckItem({
						text: playerList[x].name,
						value: playerList[x].id,
						checked: playerList[x].current,
						cls: playerList[x].model,
						group: 'playerList',
						handler: function(ev) {
							this._confirmPageChange(
								location.pathname + '?playerid=' + ev.value
							);
						},
						scope: this
					})
				);
			}
		},

		initSettingsList : function(settingsList){
			if (!Ext.get('settingsSelector'))
				return;

			var settingsChooser = new SqueezeJS.UI.SplitButton({
				renderTo: 'settingsSelector',
				menu: new Ext.menu.Menu({shadow: Ext.isGecko && Ext.isMac ? true : 'sides'}),
				arrowTooltip: SqueezeJS.string('settings')
			});

			for (var x=0; x<settingsList.length; x++){
				if (settingsList[x].current) {
					settingsChooser.setText(settingsList[x].name);
				}

				settingsChooser.menu.add(
					new Ext.menu.CheckItem({
						text: settingsList[x].name,
						value: settingsList[x].url,
						checked: settingsList[x].current,
						cls: 'settingsList',
						group: 'settingsList',
						handler: function(ev) {
							this._confirmPageChange(
								webroot + ev.value + 'playerid=' + playerid
							);
						},
						scope: this
					})
				);
			}
		},
		
		initSliders : function() {
			var items = Ext.query('input[class*=sliderInput_]');
			var inputEl;
			
			for(var i = 0; i < items.length; i++) {
	
				if (inputEl = Ext.get(items[i])) {
					var min, max, increment;
					min = 0;
					max = 100;
					increment = 1;

					var params = inputEl.dom.className.match(/sliderInput_([-]?\d+)_(\d+)_(\d+)/);

					if (params == null) {
						params = inputEl.dom.className.match(/sliderInput_([-]?\d+)_(\d+)/);
						min = RegExp.$1;
						max = RegExp.$2;
					}

					else {
						min = RegExp.$1;
						max = RegExp.$2;
						increment = RegExp.$3;
					}
					
					new SqueezeJS.UI.SliderInput({
						width: 200,
						minValue: parseInt(min),
						maxValue: parseInt(max),
						increment: parseInt(increment),
				 		input: inputEl,
				 		cls: 'settingsSlider'
					});
				}
			}			
		},

		validatePref : function(myPref, namespace) {
			SqueezeJS.Controller.request({
				params: ['', [
							'pref', 
							'validate', 
							namespace + ':' + myPref, 
							Ext.get(myPref).getValue()
						]],
				success: function(response) {
					if (response && response.responseText) {
						response = Ext.util.JSON.decode(response.responseText);

						// if preference did not validate - highlight the field
						if (response.result)
							Settings.Page.highlightField(myPref, response.result.valid);
					}
				}
				
			});
		},
		
		submit : function(cb) {
			var items = Ext.query('input.invalid');

			for(var i = 0; i < items.length; i++) {
				var inputEl;

				if (inputEl = Ext.get(items[i])) {
					Settings.Page.highlightField(inputEl.id, false);
				}
			}

			// block first attempt to save if there are invalid values
			if (items.length == 0 || invalidWarned) {
				if (cb) {
					Ext.Ajax.request({
						form: document.forms.settingsForm,
						callback: cb
					});
				}
				else {
					document.forms.settingsForm.submit();
				}
			}
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
				Ext.MessageBox.alert(SqueezeJS.string('settings'), 
					Ext.util.Format.stripTags(
						reload.dom.innerHTML.replace(/<br\/?>/ig, ' ')
					)
				);
				reload.update('');
			}
		},
		
		showRestartMessage : function() {
			var reload = Ext.get('restartWarning');
			if (reload) {
				var restartUrl = reload.child('a').dom.href;
				
				Ext.MessageBox.show({
					title: SqueezeJS.string('settings'),
					msg: Ext.util.Format.stripTags(
						reload.dom.innerHTML.replace(/<br\/?>/ig, ' ')
					),
					buttons: {
						ok: SqueezeJS.string('restart_now'),
						cancel: SqueezeJS.string('restart_later')
					},
					fn: function(btn, text) {
						if (btn == 'ok') {
							location = restartUrl;
						}
					}
				});
				reload.update('');
			}
		},
		
		showRescanMessage : function() {
			var reload = Ext.get('rescanWarning');
			if (reload) {
				var restartUrl = reload.child('a').dom.href;
				
				Ext.MessageBox.show({
					title: SqueezeJS.string('settings'),
					msg: Ext.util.Format.stripTags(
						reload.dom.innerHTML.replace(/<br\/?>/ig, ' ')
					),
					buttons: Ext.Msg.OKCANCEL,
					fn: function(btn, text) {
						if (btn == 'ok') {
							location = restartUrl;
						}
					}
				});
				reload.update('');
			}
		},

		isModified : function(){
			var fields = document.forms.settingsForm.elements;
			for (var x=0; x<fields.length; x++) {
				document.forms['settingsForm'].elements[x].blur();
			}

			return modified;
		},

		_checkModified : function(ev, input){
			modified = modified || (input.value != input.defaultValue);
		},

		setModified : function(){
			modified = true;	
		},
		
		resetModified : function(){
			modified = false;
		},

		onResize : function(width, height){
			Ext.util.CSS.updateRule('.x-menu-list', 'max-height', (height - 50) + 'px');
		},

		_confirmPageChange : function(url) {
			var modified = this.isModified();

			if (modified) {
				try { parent.Settings._confirmPageChange(url); }
				catch(e) {}
				return false;
			}
			else {
				location = url;
			}
			return true;
		},

		initCollapsableItems : function(){
			var el;
			var items = Ext.DomQuery.select('div.collapsableSection');
	
			// collapse/expand items - collapse by default
			for(var i = 0; i < items.length; i++) {
				el = Ext.get(items[i]);
				
				var panel;
				if (el) {
					panel = el.id;
					panel = panel.replace(/_Header/, '');

					if (panel = Ext.get(panel)) {
					
						el.on("click", function(ev, target) {
							// if the triangle image was clicked, get the parent div
							if (target.tagName == 'IMG')
								target = Ext.get(target).parent('div');
							
							var subPanel = target.id;
							subPanel = subPanel.replace(/_Header/, '');

							this.toggleItem(Ext.get(target), subPanel);
						}, this);
	
						panel.enableDisplayMode('block');
	
						if (SqueezeJS.getCookie('Squeezebox-expanded-' + panel.id) == '0')
							this.collapseItem(el, panel);
		
						else
							this.expandItem(el, panel);
					}
				}
			}
		},

		toggleItem : function(heading, panel){
			var el = Ext.get(panel);

			if (el) {
				if (el.isVisible())
					this.collapseItem(heading, el);
				else
					this.expandItem(heading, el);
			}
		},
	
		expandItem : function(heading, panel){
			SqueezeJS.setCookie('Squeezebox-expanded-' + panel.id, '1');

			var icon = heading.child('img:first', true);
			if (icon)
				Ext.get(icon).addClass('disclosure_expanded');

			if (panel) {
				panel.setVisible(true);
			}
		},
	
		collapseItem : function(heading, panel){
			SqueezeJS.setCookie('Squeezebox-expanded-' + panel.id, '0');
	
			if (icon = heading.child('img:first', true))
				Ext.get(icon).removeClass('disclosure_expanded');

			if (panel){
				panel.setVisible(false);
			}
		}
	};
}();

Settings.Alarm = function() {
	return {
		sliders: new Array(),

		init: function(alarmId, alarmCount) {
			var el;
			if (el = Ext.get('alarm_remove_' + alarmId)) {
				el.on({
					click: {
						fn: function() {
							Ext.get('alarmtime' + alarmId).dom.value = '';
							Ext.get('alarm' + alarmId).setDisplayed('none');
							Ext.get('button' + alarmId).show();
						}
					}
				});
			}

			if (el = Ext.get('AddAlarm')) {
				el.on({
					click: {
						fn: function() {
							Ext.get('alarm' + alarmId).show();
							Ext.get('button' + alarmId).setDisplayed('none');
						}
					}
				});
			}
		},	
		
		initTimeControls: function(timeFormat, altFormats) {
			var items = Ext.DomQuery.select('input.timeControl');
			
			for (var i = 0; i < items.length; i++) {

				new Ext.form.TimeField({
					applyTo: items[i],
					altFormats: (altFormats ? '|' + altFormats : '') + "g:iA|g:ia|g:i A|g:i a|h:i|g:i|H:i|ga|ha|gA|h a|g a|g A|gi|hi|gia|hia|g|H",
					increment: 5,
					format: timeFormat,
					width: 50,
					hideTrigger: true
				});
			}
		}
	};
}();