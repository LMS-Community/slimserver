var MainMenu = function(){
	var url = new Array();

	return {
		init : function(){
			Ext.EventManager.onWindowResize(this.onResize, this);
			Ext.EventManager.onDocumentReady(this.onResize, this, true);

			search = new Ext.form.TextField({
				validationDelay: 50,
				validateOnBlur: false,

				validator: function(value){
					if (value.length > 2) {
						el = Ext.get('search-results')
						
						// don't wait for an earlier update to finish
						um = el.getUpdateManager();
						if (um.isUpdating())
							um.abort();
						
						el.load(
							{
								url: 'search.xml?query=' + value + '&player=' + player,
								method: 'GET',
								timeout: 5000
							}, 
							{},
							function(){
								Utils.addBrowseMouseOver();
								MainMenu.showPanel('search');
								MainMenu.onResize();
							}
						);
					}
					else
						MainMenu.showPanel('my_music');
						
					return true;
				}
			});
			search.applyTo('livesearch');

			anchor = document.location.href.match(/#(.*)\?/)
			if (!(anchor && anchor[1] && this.showPanel(anchor[1].toLowerCase()))) {
				this.showPanel('home');
				this.expandItem(Utils.getCookie('SlimServer-homeMenuExpanded'));
			}
		},
		
		addUrl : function(key, value){
			url[key] = value;
		},
		
		doMenu : function(item){
			switch (item) {
				case 'MY_MUSIC':
					this.showPanel('my_music');
					break;

				case 'RADIO':
					this.showPanel('radio');
					break;

				case 'MUSIC_ON_DEMAND':
					this.showPanel('music_on_demand');
					break;

				case 'OTHER_SERVICES':
					alert('...soon to come');
					break;
					
				default:
					if (url[item]) {
						cat = item.match(/:(.*)$/);
						location.href = url[item] + (cat && cat.length >= 2 && cat[1] != 'browse' ? '&homeCategory=' + cat[1] : '');
					}
					break;
			}
		},

		toggleItem : function(panel){
			if (el = Ext.get(panel)) {
				if (el.hasClass('homeMenuItem_expanded'))
					this.collapseItem(panel, true);
				else
					this.expandItem(panel);
			}
		},

		expandItem : function(panel){
			// we only allow for one open item
			this.collapseAll();

			Utils.setCookie('SlimServer-homeMenuExpanded', panel);

			if (el = Ext.get(panel)) {
				if (icon = el.child('img:first', true)) {
					icon.src =  webroot + 'html/images/triangle-down.gif';
				}
				el.addClass('homeMenuItem_expanded');
				
				subItems = Ext.get(panel.toLowerCase() + 'Menu');
				if ((subPanel = Ext.get(panel + '_expanded')) && subItems){
					subPanel.setVisibilityMode(Ext.Element.DISPLAY);
					subPanel.setVisible(true);
					subPanel.addClass('homeMenuSection_expanded');
					subPanel.update(subItems.dom.innerHTML);
				}
				
			}

			Utils.addBrowseMouseOver();

			this.onResize();
		},

		collapseItem : function(panel, resetState){
			if (resetState)
				Utils.setCookie('SlimServer-homeMenuExpanded', '');

			if (el = Ext.get(panel)) {
				if (icon = el.child('img:first', true)) {
					icon.src =  webroot + 'html/images/triangle-right.gif';
				}

				el.removeClass('homeMenuItem_expanded');

				if (subPanel = Ext.get(panel + '_expanded')){
					subPanel.setVisibilityMode(Ext.Element.DISPLAY);
					subPanel.setVisible(false);
					subPanel.update('');
					subPanel.removeClass('homeMenuSection_expanded');
				}
			}

			Utils.addBrowseMouseOver();

			this.onResize();
		},
		
		collapseAll : function(){
			items = Ext.DomQuery.select('div.homeMenuItem_expanded');
			for(var i = 0; i < items.length; i++) {
				this.collapseItem(items[i].id);
			}
		},

		showPanel : function(panel){
			panelExists = false;
			this.collapseAll();

			items = Ext.DomQuery.select('div.homeMenuSection');
			for(var i = 0; i < items.length; i++) {
				if (el = Ext.get(items[i].id)) {
					el.setVisible(panel + 'Menu' == items[i].id);
					panelExists |= (panel + 'Menu' == items[i].id);
				}
			}

			items = Ext.DomQuery.select('span.overlappingCrumblist');
			for(var i = 0; i < items.length; i++) {
				if (el = Ext.get(items[i].id))
					el.setVisible(panel + 'Crumblist' == items[i].id);
			}

			Ext.get('pagetitle').update(strings[panel] ? strings[panel] : strings['home']);

			Ext.get('livesearch').setVisibilityMode(Ext.Element.DISPLAY);
			if (panel == 'my_music' || panel == 'search')
				Ext.get('livesearch').setVisible(true);
			else
				Ext.get('livesearch').setVisible(false);

			return panelExists;
		},

		onResize : function(){
			items = Ext.DomQuery.select('div.homeMenuSection');
			for(var i = 0; i < items.length; i++) {
				if (el = Ext.get(items[i].id)) {
					contEl = Ext.get('content');
					el.setWidth(contEl.getWidth()-10);
					el.setHeight(contEl.getHeight()-20);
				}
			}
		}
	}
}();