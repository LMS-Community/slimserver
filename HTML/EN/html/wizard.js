Wizard = function(){
	var page = 0;
	var pages = new Array('welcome', 'proxy', 'sqn', 'source', 'audiodir', 'playlistdir', 'itunes', 'musicip', 'summary');
	var folderselectors = new Array();
	var sqnValidated = false;
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
					initialSize: 45
				},
				south: {
					split:false,
					initialSize: 40
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

				new Ext.Button('sn_verify', {
					text: strings['sn_verify'],
					handler: this.verifySqnAccount,
					scope: this
				});
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
				case 'welcome' :
					this.prevBtn.show();
					break;

				case 'sqn' :
					this.verifySqnAccount();
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
			dimensions = Ext.fly(document.body).getViewSize();
			Ext.get('mainbody').setHeight(dimensions.height-10);
			Ext.get('maincontent').setHeight(dimensions.height-145);

			myHeight = dimensions.height - 245;
			for (var i in folderselectors) {
				if (s = folderselectors[i].id)
					Ext.get(s).setHeight(myHeight);
			}

			this.layout();
		},

		verifySqnAccount : function(){
			var email = Ext.get('sn_email').dom.value;
			var pw = Ext.get('sn_password').dom.value;

			var email_summary = Ext.get('sn_email_summary');
			var result_summary = Ext.get('sn_result_summary');
			var resultEl = Ext.get('sn_result');
			
			resultEl.update('');
			email_summary.update(strings['summary_none']);

			if (email && pw) {
				email_summary.update(email);
				result_summary.update('');

				Ext.Ajax.request({
					url: '/settings/server/squeezenetwork.html',
					params: Ext.urlEncode({
						sn_email: email,
						sn_password: pw,
						saveSettings: 1,
						AJAX: 1
					}),
					scope: this,

					success: function(response, options){
						result = response.responseText.split('|');

						if (result[0] == '0') {
							resultEl.update(result[1]);
							result_summary.update('(' + result[1] + ')');
							this.sqnValidated = false;
						}
						else {
							resultEl.update(strings['sn_success']);
							result_summary.update('');
							this.sqnValidated = true;
						}
					}
				});
			}
		}
	};
}();
