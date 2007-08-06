Wizard = function(){
	// we do not always show the language selection page
	page = firstpage;
	pages = new Array('welcome', 'proxy', 'sqn', 'source', 'audiodir', 'playlistdir', 'itunes', 'musicip', 'summary');

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
			layout.endUpdate();
			flipPages(page);

			Ext.get('previous').on('click', this.onPrevious);
			Ext.get('next').on('click', this.onNext);
			Ext.get('finish').on('click', this.onFinish);
			Ext.get('language').on('change', this.onLanguageChange);
		},

		onNext : function(){
			switch (pages[page]) {
				// don't display proxy page, except if showproxy is set
				case 'welcome' :
					page += 2 - showproxy
					break;
				default:
					page++;
					break;
			}

			page = Math.min(page, pages.length-1);
			flipPages(page);
		},

		onPrevious : function(){
			switch (pages[page]) {
				// don't display proxy page, except if showproxy is set
				case 'sqn' :
					page -= 2 - showproxy
					break;
				default:
					page--;
					break;
			}

			page = Math.max(page, firstpage);
			flipPages(page);
		},
		
		onFinish : function(){
			document.forms.wizardForm.submit();
//			window.close();
		},
		
		onLanguageChange : function(){
			document.forms.languageForm.submit();
		}
	};   
}();
Ext.EventManager.onDocumentReady(Wizard.init, Wizard, true);

function flipPages(newPage) {

	for (x = 0; x < pages.length; x++) {
		if (el = Ext.get(pages[x] + '_h')) {
			el.setVisible(newPage == x, false);
		}

		if (el = Ext.get(pages[x] + '_m')) {
			el.setVisible(newPage == x, false);
		}
	}
	
	// update buttons
	if (newPage == pages.length-1) {
	}
}

