Wizard = function(){
	// we do not always show the language selection page
	page = 0;
	pages = new Array('welcome', 'proxy', 'sqn', 'source', 'audiodir', 'playlistdir', 'itunes', 'musicip', 'summary');
	folderselectors = new Array();
	sqnValidated = false;

	return {
		init : function(){
			var layout = new Ext.BorderLayout(document.body, {
				north: {
					split:false,
					initialSize: 35
				},
				south: {
					split:false,
					initialSize: 20
				},
				west: {
					split:false,
					initialSize: 200,
					collapsible: false
				},
				center: {
					autoScroll: true
				}
			});
			
			layout.beginUpdate();
			layout.add('north', new Ext.ContentPanel('header', {fitToFrame:true}));
			layout.add('south', new Ext.ContentPanel('footer', {fitToFrame:true}));
			layout.add('west', new Ext.ContentPanel('west', {fitToFrame:true}));
			layout.add('center', new Ext.ContentPanel('main'));

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

			Ext.get('previous').on('click', this.onPrevious, this);
			Ext.get('next').on('click', this.onNext, this);
			Ext.get('finish').on('click', this.onFinish, this);
			Ext.get('language').on('change', this.onLanguageChange, this);
			Ext.get('sn_verify').on('click', this.verifySqnAccount, this);

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
			if (pages[oldValue] == 'sqn') {
				this.verifySqnAccount();
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
		
		onFinish : function(){
			document.forms.wizardForm.submit();
//			window.close();
		},
		
		onLanguageChange : function(){
			document.forms.languageForm.submit();
		},
		
		verifySqnAccount : function(){
			email = Ext.get('sn_email');
			pw = Ext.get('sn_password');
			
			if (email && pw) {
				email = email.dom.value;
				pw = pw.dom.value;

				Ext.get('sn_result').update('');

				Ext.Ajax.request({
					url: '/settings/server/squeezenetwork.html',
					params: 'sn_email=' + email + '&sn_password=' + pw + '&saveSettings=1&AJAX=1',
					scope: this,
	
					success: function(response, options){
						result = response.responseText.split('|');
						Ext.get('sn_result').update(result[1]);
						this.sqnValidated = (result[0] == '1');
					}
				});
			}
		}
	};   
}();
Ext.EventManager.onDocumentReady(Wizard.init, Wizard, true);
