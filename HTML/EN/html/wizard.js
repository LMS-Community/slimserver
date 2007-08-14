Wizard = function(){
	page = 0;
	pages = new Array('welcome', 'proxy', 'sqn', 'source', 'audiodir', 'playlistdir', 'itunes', 'musicip', 'summary');
	folderselectors = new Array();
	sqnValidated = false;
	var nextBtn;

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

			folderselectors['audiodir'] = new FileSelector('audiodirselector', {
				filter: 'foldersonly',
				input: 'audiodir',
				gotoBtn: 'gotoAudiodir'
			});

			folderselectors['playlistdir'] = new FileSelector('playlistdirselector', {
				filter: 'foldersonly',
				input: 'playlistdir',
				gotoBtn: 'gotoPlaylistdir'
			});

			folderselectors['itunes'] = new FileSelector('itunespathselector', {
				input: 'xml_file',
				filter: 'filetype:xml'
			});

			new Ext.Button('previous', {
				text: strings['previous'],
				handler: this.onPrevious,
				scope: this
			});

			this.nextBtn = new Ext.Button('next', {
				text: strings['next'],
				handler: this.onNext,
				scope: this
			});

			Ext.get('language').on('change', this.onLanguageChange, this);

			new Ext.Button('sn_verify', {
				text: strings['sn_verify'],
				handler: this.verifySqnAccount,
				scope: this
			});

			Ext.EventManager.onWindowResize(this.onResize, layout);
			Ext.EventManager.onDocumentReady(this.onResize, layout, true);

			this.flipPages(page);
			layout.endUpdate();
		},

		onNext : function(){
			page = this.whichPage(page, 1);
			this.flipPages();
		},

		onPrevious : function(){
			page = this.whichPage(page, -1);
			this.flipPages();
		},
		
		whichPage : function(oldValue, offset){
			// launch verification in the background
			switch (pages[oldValue]) {
				case 'sqn' :
					this.verifySqnAccount();
					break;
				
				case 'summary' :
					if (offset > 0) {
						document.forms.wizardForm.submit();
						window.close();
					}
					else {
						this.nextBtn.setText(strings['next']);
					}
					
					break;
				
				default :
					break;
			}

			newPage = oldValue + offset;
			if (offset < 0) newPage = Math.max(newPage, 0);
			else newPage = Math.min(newPage, pages.length-1);

			switch (pages[newPage]) {
				case 'proxy' :
					if (!showproxy)
						newPage = this.whichPage(newPage, offset);
					break;

				case 'audiodir' :
					if (el = Ext.get('useAudiodir')) {
						if (!el.dom.checked)
							newPage = this.whichPage(newPage, offset);
					}
					break;

				case 'playlistdir' :
					if (el = Ext.get('useAudiodir')) {
						if (!el.dom.checked)
							newPage = this.whichPage(newPage, offset);
					}
					break;

				case 'itunes' :
					if (el = Ext.get('itunes')) {
						if (! (el.dom.checked && showitunes))
							newPage = this.whichPage(newPage, offset);
					}
					break;

				case 'musicip' :
					if (el = Ext.get('musicmagic')) {
						if (! (el.dom.checked && showmusicip))
							newPage = this.whichPage(newPage, offset);
					}
					break;

				case 'summary' :
					Ext.get('summary').update(
						(!(Ext.get('useAudiodir').dom.checked || Ext.get('itunes').dom.checked || Ext.get('musicmagic').dom.checked) ? '<li>' + strings['summary_none'] + '</li>' : '') +
						(Ext.get('useAudiodir').dom.checked ? '<li>' + strings['summary_audiodir'] + Ext.get('audiodir').dom.value + '</li>' : '') +
						(Ext.get('itunes').dom.checked ? '<li>' + strings['summary_itunes'] + '</li>' : '') +
						(Ext.get('musicmagic').dom.checked ? '<li>' + strings['summary_musicmagic'] + '</li>' : '')
					);

					this.nextBtn.setText(strings['finish']);

					break;

				default :
					break;
			}
			return newPage;
		},

		flipPages : function(){
			for (x = 0; x < pages.length; x++) {
				if (el = Ext.get(pages[x] + '_h')) {
					el.setVisible(page == x, false);
				}
		
				if (el = Ext.get(pages[x] + '_m')) {
					el.setVisible(page == x, false);
				}
				
				// workaround for FF problem: frame would be displayed on wrong page,
				// if class is applied in the HTML code
				if (folderselector = folderselectors[pages[x]]) {
					el = Ext.get(folderselector.id);
					if (el && page == x) {
						el.addClass("folderselector");
					}
					else if (el) {
						el.removeClass("folderselector");
					}
				}
			}
		
		},
		
		onLanguageChange : function(){
			document.forms.languageForm.submit();
		},
		
		// resize panels, folder selectors etc.
		onResize : function(){
			dimensions = Ext.fly(document.body).getViewSize();
			Ext.get('mainbody').setHeight(dimensions.height-35);
			Ext.get('maincontent').setHeight(dimensions.height-195);
			
			myHeight = dimensions.height - 270;
			for (var i in folderselectors) {
				if (s = folderselectors[i].id)
					Ext.get(s).setHeight(myHeight);
			}

			this.layout();
		},

		verifySqnAccount : function(){
			email = Ext.get('sn_email');
			pw = Ext.get('sn_password');
			
			if (email && pw) {
				email = email.dom.value;
				pw = pw.dom.value;

				Ext.get('sn_result').update('');
				Ext.get('sn_email_summary').update(email);
				Ext.get('sn_result_summary').update('');

				Ext.Ajax.request({
					url: '/settings/server/squeezenetwork.html',
					params: 'sn_email=' + email + '&sn_password=' + pw + '&saveSettings=1&AJAX=1',
					scope: this,
	
					success: function(response, options){
						result = response.responseText.split('|');
						
						if (result[0] == '0') {
							Ext.get('sn_result').update(result[1]);
							Ext.get('sn_result_summary').update('(' + result[1] + ')');
							this.sqnValidated = false;
						}
						else {							
							Ext.get('sn_result').update(strings['sn_success']);
							Ext.get('sn_result_summary').update('');
							this.sqnValidated = true;
						}
					}
				});
			}
		}
	};   
}();
Ext.EventManager.onDocumentReady(Wizard.init, Wizard, true);
