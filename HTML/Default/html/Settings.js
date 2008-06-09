Settings = {
	background : null,
	body : null,
	layout : null,
	tp: null,

	init : function(settingsTabs){
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
							height: 33,
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

		SqueezeJS.clearCookie('SqueezeCenter-playersettings');
		SqueezeJS.clearCookie('SqueezeCenter-advancedsettings');

		// cache the offsets we're going to use to resize the background image
		this.offsets = [
			(Ext.isIE7 ? this.background.getTop() + 3 : this.background.getTop() * 2),
			(Ext.isIE7 ? this.background.getLeft() + 3 : this.background.getLeft() * 2),
			this.maincontent.getTop() + this.body.getHeight() - Ext.get('inner_footer').getTop()
		]

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
			activeTab: 0,
			items: settingsTabs
		});

		this.tp.on('beforetabchange', function(tb, tab, ev){
			var modified = false;

			try { modified = frames.settings.Settings.Page.isModified(); }
			catch(e){}

			if (modified) {
				Ext.Msg.show({
					title: SqueezeJS.string('settings'),
					msg: SqueezeJS.string('settings_changed_confirm'),
					width: 300,
					closable: false,
					buttons: {
						yes: SqueezeJS.string('yes'),
						no: SqueezeJS.string('no'),
						cancel: SqueezeJS.string('cancel')
					},
					fn: function(btn, a, b){
						if (btn == 'yes') {
							if (this.submitSettings()) {
								this._resetModified();
								tb.activate(tab);
							}
						}

						else if (btn == 'no') {
							this._resetModified();
							tb.activate(tab);
						}
					},
					scope: this
				});

				return false;
			}
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
			handler: this.submitSettings,
			scope: this
		});

		Ext.EventManager.onWindowResize(this.onResize, this);
		this.onResize(this.body.getWidth(), this.body.getHeight());
	},

	showSettingsPage : function(page) {
		if (page.id == 'PLAYER' && SqueezeJS.getCookie('SqueezeCenter-playersettings'))
			page = SqueezeJS.getCookie('SqueezeCenter-playersettings');

		else if (page.id == 'ADVANCED_SETTINGS' && SqueezeJS.getCookie('SqueezeCenter-advancedsettings'))
			page = SqueezeJS.getCookie('SqueezeCenter-advancedsettings');

		if (typeof page == 'object' && page.url)
			page = page.url;

		Ext.get('maincontent').dom.src = webroot + page + 'player=' + player + '&playerid=' + playerid;
	},

	activate : function(tab) {
		if (!this.tp)
			parent.Settings.activate(tab);

		else {
			this.tp.activate(tab);
		}
	},

	submitSettings : function() {
		try { frames.settings.Settings.Page.submit() }
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
	}
}

Settings.Page = function(){
	var invalidWarned = false;
	var modified = false;

	return {
		init : function(){
			this.initDescPopup();
			SqueezeJS.UI.FilesystemBrowser.init();
			SqueezeJS.UI.ScrollPanel.init();

			var items = Ext.query('input');
			for(var i = 0; i < items.length; i++) {
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

			this.onResize(0, Ext.lib.Dom.getViewHeight());
			Ext.EventManager.onWindowResize(this.onResize);

			Ext.select('input, textarea, select').on('change', function(ev){
				modified = true;
			});

			this.showWarning();
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

			var playerChooser = new Ext.SplitButton({
				renderTo: 'playerSelector',
				handler: function(ev){
					if(this.menu && !this.menu.isVisible()){
						this.menu.show(this.el, this.menuAlign);
					}
					this.fireEvent('arrowclick', this, ev);
				},
				menu: new Ext.menu.Menu({shadow: Ext.isGecko && Ext.isMac ? true : 'sides'}),
				tooltip: SqueezeJS.string('choose_player'),
				arrowTooltip: SqueezeJS.string('choose_player'),
				tooltipType: 'title'
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
						cls: 'playerList',
						group: 'playerList',
						handler: function(ev){
							location = location.pathname + '?player=' + ev.value + '&playerid=' + ev.value;
						}
					})
				);
			}
		},

		initSettingsList : function(settingsList){
			if (!Ext.get('settingsSelector'))
				return;

			var settingsChooser = new Ext.SplitButton({
				renderTo: 'settingsSelector',
				handler: function(ev){
					if(this.menu && !this.menu.isVisible()){
						this.menu.show(this.el, this.menuAlign);
					}
					this.fireEvent('arrowclick', this, ev);
				},
				menu: new Ext.menu.Menu({shadow: Ext.isGecko && Ext.isMac ? true : 'sides'}),
				tooltip: SqueezeJS.string('advanced_settings'),
				arrowTooltip: SqueezeJS.string('advanced_settings'),
				tooltipType: 'title'
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
						handler: function(ev){
							location = webroot + ev.value + 'player=' + playerid + '&playerid=' + playerid;
						}
					})
				);
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

		submit : function(){
			var items = Ext.query('input.invalid');

			for(var i = 0; i < items.length; i++) {
				var inputEl;

				if (inputEl = Ext.get(items[i])) {
					Settings.Page.highlightField(inputEl.id, false);
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
				Ext.MessageBox.alert(SqueezeJS.string('settings'), 
					Ext.util.Format.stripTags(
						reload.dom.innerHTML.replace(/<br\/?>/ig, ' ')
					)
				);
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

		resetModified : function(){
			modified = false;
		},

		onResize : function(width, height){
			Ext.util.CSS.updateRule('.x-menu-list', 'max-height', (height - 50) + 'px');
		}
	};
}();
