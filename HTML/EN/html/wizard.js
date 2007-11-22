Wizard = function(){
	var page = 0;
	var pages = new Array('welcome', 'proxy', 'sqn', 'source', 'audiodir', 'playlistdir', 'itunes', 'musicip', 'summary');
	var folderselectors = new Array();
	var validators;
	var nextBtn;
	var prevBtn;
	var windowSize = new Array(top.window.outerWidth, top.window.outerHeight);

	// some MSIE versions won't return a value
	if (windowSize[0] == undefined || windowSize[1] == undefined) {
		windowSize[0] = Ext.lib.Dom.getViewWidth() + 30;
		windowSize[1] = Ext.lib.Dom.getViewHeight() + 130;  // viewport + guessed toolbar size etc...
	}

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

			for (x = 0; x < pages.length; x++) {
				if (el = Ext.get(pages[x] + '_h')) {
					el.enableDisplayMode('block');
					el.hide();
				}

				if (el = Ext.get(pages[x] + '_m')) {
					el.enableDisplayMode('block');
					el.hide();
				}
			}

			if (wizarddone) {
				this.nextBtn = new Ext.Button('next', {
					text: strings['close'],
					handler: function(){
						window.open('javascript:window.close();','_self','');
					},
					scope: this
				});
			}
			else {
				Ext.get('done_h').hide();
				Ext.get('done_m').hide();

				window.resizeTo(800, 700);

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
					filter: 'filetype:xml',
					gotoBtn: 'gotoiTunesDir'
				});

				this.prevBtn = new Ext.Button('previous', {
					text: strings['previous'],
					handler: this.onPrevious,
					scope: this,
					hidden: true
				});

				this.nextBtn = new Ext.Button('next', {
					text: strings['next'],
					handler: this.onNext,
					scope: this
				});

				Ext.get('language').on('change', this.onLanguageChange, this);

				validators = {
					sqn: {
						validator: this.verifySqnAccount,
						valid: false
					},
					audiodir: {
						validator: this.verifyAudiodir,
						valid: false
					},
					playlistdir: {
						validator: this.verifyPlaylistdir,
						valid: false
					},
					xml_file: {
						validator: this.verifyiTunesXML,
						valid: false
					}
				};

				Ext.get('sn_email').on('change', function(){ validators.sqn.valid = false; });
				Ext.get('sn_password').on('change', function(){ validators.sqn.valid = false; });
				Ext.get('audiodir').on('change', function(){ validators.audiodir.valid = false; });
				Ext.get('playlistdir').on('change', function(){ validators.playlistdir.valid = false; });
				Ext.get('xml_file').on('change', function(){ validators.xml_file.valid = false; });

			}

			Ext.EventManager.onWindowResize(this.onResize, layout);
			Ext.EventManager.onDocumentReady(this.onResize, layout, true);

			if (!wizarddone)
				this.flipPages(page);
			layout.endUpdate();

			Ext.get('loading').hide();
			Ext.get('loading-mask').hide();
		},

		onNext : function(){
			// launch verification in the background
			if (validators[pages[page]] != null && !validators[pages[page]].valid) {
				Ext.callback(validators[pages[page]].validator, Wizard);
			}

			else {
				page = this.whichPage(page, 1);
				this.flipPages();
			}
		},

		onPrevious : function(){
			page = this.whichPage(page, -1);
			this.flipPages();
		},

		whichPage : function(oldValue, offset){
			switch (pages[oldValue]) {
				case 'welcome' :
					this.prevBtn.show();
					break;

				case 'summary' :
					if (offset > 0) {
						document.getElementById("wizardForm").submit();

						if (windowSize[0] && windowSize[1]);
							window.resizeTo(windowSize[0], windowSize[1]);

						if (!firsttimerun)
							window.open('javascript:window.close();','_self','');
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
				case 'welcome' :
					this.prevBtn.hide();
					break;

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
						('<li>' + strings['summary_playlistdir'] + Ext.get('playlistdir').dom.value + '</li>') +
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
			document.getElementById("languageForm").submit();
		},

		// resize panels, folder selectors etc.
		onResize : function(){
			var body = Ext.get(document.body);

			var dimensions = new Array();
			dimensions['maxHeight'] = body.getHeight() - body.getMargins('tb');
			dimensions['maxWidth'] = body.getWidth() - body.getMargins('rl')  - (Ext.isIE && !Ext.isIE7 ? body.getMargins('rl') : 0);

			var bg = Ext.get('background');
			bg.setWidth(body.getWidth() - (Ext.isIE && !Ext.isIE7 ? body.getMargins('rl') : 0));
			bg.setHeight(dimensions['maxHeight']);

			Ext.get('mainbody').setHeight(dimensions['maxHeight']);
			Ext.get('maincontent').setHeight(dimensions['maxHeight']-140);

			var myHeight = dimensions['maxHeight'] - 200;
			for (var i in folderselectors) {
				if (s = folderselectors[i].id)
					Ext.get(s).setHeight(myHeight);
			}

			this.layout();
		},

		verifySqnAccount : function(){
			var email = Ext.get('sn_email').dom.value;
			var pw = Ext.get('sn_password').dom.value;
			var disable_stats = Ext.get('sn_disable_stats').dom.value;

			var email_summary = Ext.get('sn_email_summary');
			var result_summary = Ext.get('sn_result_summary');
			var resultEl = Ext.get('sn_result');
			
			resultEl.update('');
			email_summary.update(strings['summary_none']);

			if (email || pw) {
				email_summary.update(email);
				result_summary.update('');

				Ext.Ajax.request({
					url: '/settings/server/squeezenetwork.html',
					params: Ext.urlEncode({
						sn_email: email,
						sn_password: pw,
						sn_disable_stats: disable_stats,
						sn_sync: 1,
						saveSettings: 1,
						AJAX: 1
					}),
					scope: this,

					success: function(response, options){
						result = response.responseText.split('|');

						if (result[0] == '0') {
							resultEl.update(result[1]);
							result_summary.update('(' + result[1] + ')');
							validators.sqn.valid = false;
							Ext.get('sn_email').highlight('ffcccc');
							Ext.get('sn_password').highlight('ffcccc');
						}

						else {
							resultEl.update(strings['sn_success']);
							result_summary.update('');
							validators.sqn.valid = true;
							this.onNext();
						}
					}
				});
			}

			else {
				resultEl.update(strings['sn_success']);
				result_summary.update('');
				validators.sqn.valid = true;
				this.onNext();
			}
		},

		verifyAudiodir : function(){
			this.validatePref('server', 'audiodir');
		},

		verifyPlaylistdir : function(){
			this.validatePref('server', 'playlistdir');
		},

		verifyiTunesXML : function(){
			this.validatePref('itunes', 'xml_file');
		},

		validatePref : function(namespace, myPref) {
			Ext.Ajax.request({
				url: '/jsonrpc.js',
				method: 'POST',
				params: Ext.util.JSON.encode({
					id: 1,
					method: "slim.request",
					params: ['', [
								'pref', 
								'validate', 
								namespace + ':' + myPref, 
								Ext.get(myPref).dom.value
							]]
				}),
				success: function(response) {
					if (response && response.responseText) {
						response = Ext.util.JSON.decode(response.responseText);
			
						// if preference did not validate - highlight the field
						if (response.result && response.result.valid) {
							validators[myPref].valid = true;
							Wizard.onNext();
						}
						else {
							Ext.get(myPref).highlight('ffcccc');
						}
					}
				}
			});
		}
	};
}();
