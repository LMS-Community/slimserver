Wizard = {
	fileselectors : new Array(),

	init : function(args) {
		
		var mainpanel = new Array();
		var panels = Ext.DomQuery.select('.wz_page');

		for(var i = 0; i < panels.length; i++) {
			mainpanel.push({
				id: panels[i].id,
				contentEl: panels[i],
				canSkip: Ext.get(panels[i]).hasClass('wz_canskip'),
				finish: Ext.get(panels[i]).hasClass('wz_finish')
			});
		}

		this.wizard = new Ext.Panel({
			// panel definition
			region: 'center',
			layout: 'card',
			bodyBorder: false,
			margins: '0 15',
			cls: 'maincontent',
			defaults: {
				border: false
			},
			items: mainpanel,

			// our own handlers
			activeItemPos: 0,
			wizardDone: args.wizardDone,
			useAudioDir: args.useAudioDir,
			useMusicIP: args.useMusicIP,
			useiTunes: args.useiTunes,

			next: function(){
				if (this.items.items[this.activeItemPos].finish && !this.wizardDone) {

					// we have to copy our form values over to the form again,
					// as the Ext.Panel moved them out of the form
					var formValues = Ext.query('input, textarea, select');
					var wzForm = Ext.get('wizardForm');

					for (var x = 0; x < formValues.length; x++) {

						if (!document.forms.wizardForm.elements[formValues[x].name]) {
							Ext.DomHelper.insertFirst(wzForm, {
								tag: 'input',
								name: formValues[x].name,
								value: formValues[x].type == 'checkbox' ? (formValues[x].checked ? 1 : 0) : formValues[x].value,
								style: {
									display: "none"
								}
							})
						}
					}
					
					document.forms.wizardForm.submit();
				}

				else if (this.wizardDone)
					window.open('javascript:window.close();','_self','');

				else if (this.pageconfig[this.getLayout().activeItem.id]
					&& this.pageconfig[this.getLayout().activeItem.id].validator)
					Ext.callback(this.pageconfig[this.getLayout().activeItem.id].validator, this);

				else
					this.jump(1)
			},
			
			previous: function(){ this.jump(-1) },

			jump: function(offset) {
				var current = this.activeItemPos || 0;

				current += offset;

				// check whether we have to skip a page
				while (this.items.items[current].id && this.pageconfig[this.items.items[current].id]
					&& this.pageconfig[this.items.items[current].id].skip) {

					if (this.pageconfig[this.items.items[current].id].skip() && current < this.items.length && current > 0)
						current += (offset > 0 ? 1 : -1);
					else
						break;
				}

				current = Math.max(current, 0);
				current = Math.min(current, this.items.length - 1);

				this.activeItemPos = current;
				this.getLayout().setActiveItem(current);		

				this._setButtons();
			},

			_setButtons: function(){
				this.buttons.skip.setVisible(this.getLayout().activeItem.canSkip);
				this.buttons.back.setDisabled(this.activeItemPos == 0);
				this.buttons.next.setText(
					this.getLayout().activeItem.finish
					? SqueezeJS.string('finish')
					: this.wizardDone
						? SqueezeJS.string('close')
						: SqueezeJS.string('next')
				);
				this.buttons.next.setDisabled(this.activeItemPos > this.items.length - 1);
			},

			pageconfig: {
				sqn_p: {
					validator: function(){
						var email = Ext.get('sn_email').getValue();
						var pw = Ext.get('sn_password_sha').getValue();
						var disable_stats = Ext.get('sn_disable_stats').getValue();
	
						var email_summary = Ext.get('sn_email_summary');
						var result_summary = Ext.get('sn_result_summary');
						var resultEl = Ext.get('sn_result');
						
						resultEl.update('');
						result_summary.update('');
			
						if (email || pw) {
							email_summary.update(email);
			
							Ext.Ajax.request({
								url: '/settings/server/squeezenetwork.html',
								params: {
									pref_sn_email: email,
									pref_sn_password_sha: pw,
									pref_sn_disable_stats: disable_stats,
									pref_sn_sync: 1,
									saveSettings: 1,
									AJAX: 1
								},
								scope: this,
			
								success: function(response, options){
									var result = response.responseText.split('|');
			
									if (result[0] == '0') {
										resultEl.update(result[1]);
										result_summary.update('(' + result[1] + ')');
										Ext.get('sn_email').highlight('ffcccc');
										Ext.get('sn_password_sha').highlight('ffcccc');
									}
			
									else {
										this.jump(1)
									}
								}
							});
						}
			
						else {
							email_summary.update(SqueezeJS.string('summary_none'));
							this.jump(1)
						}
					}
				},

				audiodir_p: {
					//validator: function(){
					//	this._validatePref('server', 'audiodir');
					//},

					skip: function(){
						return !this.useAudioDir;
					},
					
					useAudioDir: args.useAudioDir
				},

				playlistdir_p: {
					validator: function(){
						this._validatePref('server', 'playlistdir');
					},

					skip: function(){
						return !this.useAudioDir;
					},
					
					useAudioDir: args.useAudioDir
				},

				summary_p: {
					skip: function(){
						// just update the summary, ...
						Ext.get('summary').update(
							(!(Ext.get('audiodir').dom.value || this.useiTunes || this.useMusicIP) 
								? '<li>' + SqueezeJS.string('summary_none') + '</li>' 
								: '') +
							(Ext.get('audiodir').dom.value 
								? '<li>' + SqueezeJS.string('summary_audiodir') + ' ' + Ext.get('audiodir').dom.value + '</li>'
								         + ('<li>' + SqueezeJS.string('summary_playlistdir') + ' ' + Ext.get('playlistdir').dom.value + '</li>')
								: '')  +
							(this.useiTunes 
								? '<li>' + SqueezeJS.string('summary_itunes') + '</li>' 
								: '') +
							(this.useMusicIP 
								? '<li>' + SqueezeJS.string('summary_musicip') + '</li>' 
								: '')
						);
						// ...but never skip
						return false;
					},
					useAudioDir: args.useAudioDir,
					useMusicIP: args.useMusicIP,
					useiTunes: args.useiTunes
				}
			},

			_validatePref : function(namespace, myPref) {
				SqueezeJS.Controller.request({
					params: ['', 
						[
							'pref', 
							'validate', 
							namespace + ':' + myPref, 
							Ext.get(myPref).dom.value
						]
					],
					success: function(response) {
						if (response && response.responseText) {
							response = Ext.util.JSON.decode(response.responseText);
				
							// if preference did not validate - highlight the field
							if (response.result && response.result.valid)
								this.jump(1);
							else
								Ext.get(myPref).highlight('ffcccc');
						}
					},
					scope: this
				});
			}
		});

		this.layout = new Ext.Viewport({
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
							height: 16,
							margins: '0 15'
						},
						this.wizard,
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
		});

		this.background = Ext.get('background');
		this.body = Ext.get(document.body);

		// cache the offsets we're going to use to resize the background image
		this.offsets = [
			this.background.getTop() * 2,
			this.background.getLeft() * 2
		];

		if (Ext.get('language'))
			Ext.get('language').on('change', function(){
				document.getElementById("languageForm").submit();
			}, this);

		Ext.apply(this.wizard, {
			buttons: {
				skip: new Ext.Button({
					renderTo: 'skip',
					hidden: true,
					text: SqueezeJS.string('skip'),
					handler: function(){ this.jump(1); },
					scope: this.wizard
				}),

				back: new Ext.Button({
					renderTo: 'back',
					text: SqueezeJS.string('previous'),
					handler: this.wizard.previous,
					scope: this.wizard
				}),

				next: new Ext.Button({
					renderTo: 'next',
					text: SqueezeJS.string('next'),
					handler: this.wizard.next,
					scope: this.wizard
				})
			}
		});

		if (Ext.get('audiodirselector'))
			this.fileselectors['audiodir'] = new SqueezeJS.UI.FileSelector({
				renderTo: 'audiodirselector',
				filter: 'foldersonly',
				input: 'audiodir'
			});

		if (Ext.get('playlistdirselector'))
			this.fileselectors['playlistdir'] = new SqueezeJS.UI.FileSelector({
				renderTo: 'playlistdirselector',
				filter: 'foldersonly',
				input: 'playlistdir'
			});

		this.wizard.jump(0);

		Ext.EventManager.onWindowResize(this.onResize, this);
		this.onResize(this.body.getWidth(), this.body.getHeight());

		Ext.get('loading').hide();
		Ext.get('loading-mask').hide();
	},

	// resize panels, folder selectors etc.
	onResize : function(width, height) {
		this.background.setHeight(height - this.offsets[0]);
		this.background.setWidth(width - this.offsets[1]);

		var selector;
		for (var i in this.fileselectors) {
			if (this.fileselectors[i].container && (selector = this.fileselectors[i].container.id))
				Ext.get(selector).setHeight(height - this.offsets[0] - 190);
		}
	}
}
