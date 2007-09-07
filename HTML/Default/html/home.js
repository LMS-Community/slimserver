var MainMenu = function(){
	var url = new Array();

	return {
		init : function(){
			Ext.EventManager.onWindowResize(this.onResize, this);
			Ext.EventManager.onDocumentReady(this.onResize, this, true);

			// use "display:none" to hide inactive elements
			items = Ext.DomQuery.select('div.homeMenuSection, span.overlappingCrumblist, div#livesearch, div.expandableHomeMenuItem');
			for(var i = 0; i < items.length; i++) {
				if (el = Ext.get(items[i].id)) {
					el.setVisibilityMode(Ext.Element.DISPLAY);
					if (el.hasClass('expandableHomeMenuItem'))
						el.setVisible(false);
				}
			}

			Utils.initSearch();

			anchor = document.location.href.match(/#(.*)\?/)
			if (!(anchor && anchor[1] && this.showPanel(anchor[1].toLowerCase()))) {
				this.showPanel('home');
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
					this.showPanel('other_services');
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
				if (icon = el.child('img:first', true))
					icon.src =  webroot + 'html/images/triangle-down.gif';

				el.addClass('homeMenuItem_expanded');

				if ((subPanel = Ext.get(panel + '_expanded'))){
					subPanel.setVisible(true);
					subPanel.addClass('homeMenuSection_expanded');
				}
				
			}

			Utils.addBrowseMouseOver();

			this.onResize();
		},

		collapseItem : function(panel, resetState){
			if (resetState)
				Utils.setCookie('SlimServer-homeMenuExpanded', '');

			if (el = Ext.get(panel)) {
				if (icon = el.child('img:first', true))
					icon.src =  webroot + 'html/images/triangle-right.gif';

				el.removeClass('homeMenuItem_expanded');

				if (subPanel = Ext.get(panel + '_expanded')){
					subPanel.setVisible(false);
					subPanel.removeClass('homeMenuSection_expanded');
				}
			}

			Utils.addBrowseMouseOver();

			Utils.resizeContent();
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
			
			// make plugins show up in the "Other Services" panel
			if (panel == 'plugins')
				panel = 'other_services';

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

			if (panel == 'my_music' || panel == 'search')
				Ext.get('livesearch').setVisible(true);
			else
				Ext.get('livesearch').setVisible(false);

			if (panel == 'home')
				this.expandItem(Utils.getCookie('SlimServer-homeMenuExpanded'));
			

			return panelExists;
		},

		onResize : function(){
			items = Ext.DomQuery.select('div.homeMenuSection');
			contW = Ext.get('content').getWidth() - 30;

			for(var i = 0; i < items.length; i++) {
				if (el = Ext.get(items[i].id)) {
					el.setWidth(contW);
				}
			}
		}
	}
}();