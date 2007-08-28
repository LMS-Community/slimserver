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
						MainMenu.showPanel('music');
						
					return true;
				}
			});
			search.applyTo('livesearch');

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
					this.showPanel('music_on_demand');
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

			Ext.get('livesearch').setVisibilityMode(Ext.Element.DISPLAY);
			if (panel == 'music' || panel == 'search')
				Ext.get('livesearch').setVisible(true);
			else
				Ext.get('livesearch').setVisible(false);
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