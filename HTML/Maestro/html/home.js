var MainMenu = function(){
	url = new Array();

	return {
		init : function(){
			Ext.EventManager.onWindowResize(this.onResize, this);
			Ext.EventManager.onDocumentReady(this.onResize, this, true);

			menuItems = Ext.DomQuery.select('div.homeMenuItem');
			for(var i = 0; i < menuItems.length; i++) {
				el = Ext.get(menuItems[i].id);
				if (el) {
					el.on('click', function(e, item){
						this.doMenu(item.id);
					}, this);
				}
			};
			
			this.showPanel('main');
		},
		
		addUrl : function(key, value){
			url[key] = value;
		},
		
		doMenu : function(item){
			switch (item) {
				case 'MY_MUSIC':
					this.showPanel('music');
					break;

				case 'RADIO':
					this.showPanel('radio');
					break;

				case 'MUSIC_ON_DEMAND':
					alert('...soon to come');
					break;

				case 'OTHER_SERVICES':
					alert('...soon to come');
					break;
					
				default:
					if (url[item]) {
						location.href = url[item];
					}
					break;
			}
		},
		
		showPanel : function(panel){
			items = Ext.DomQuery.select('div.homeMenuSection');
			for(var i = 0; i < items.length; i++) {
				if (el = Ext.get(items[i].id))
					el.setVisible(panel + 'Menu' == items[i].id);
			}

			items = Ext.DomQuery.select('span.overlappingCrumblist');
			for(var i = 0; i < items.length; i++) {
				if (el = Ext.get(items[i].id))
					el.setVisible(panel + 'Crumblist' == items[i].id);
			}
		},
		
		onResize : function(){
			items = Ext.DomQuery.select('div.homeMenuSection');
			for(var i = 0; i < items.length; i++) {
				if (el = Ext.get(items[i].id)) {
					el.setWidth(Ext.get('content').getWidth()-10);
				}
			}
		}
	}
}();