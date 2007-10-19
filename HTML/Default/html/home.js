var MainMenu = function(){
	return {
		init : function(){
			Ext.EventManager.onWindowResize(this.onResize, this);
			Ext.EventManager.onDocumentReady(this.onResize, this, true);

			// use "display:none" to hide inactive elements
			var items = Ext.DomQuery.select('div.homeMenuSection, div.expandableHomeMenuItem');
			for(var i = 0; i < items.length; i++) {
				if (el = Ext.get(items[i].id)) {
					el.setVisibilityMode(Ext.Element.DISPLAY);
					if (el.hasClass('expandableHomeMenuItem'))
						el.setVisible(false);
				}
			}

			this.expandItem(Utils.getCookie('SqueezeCenter-homeMenuExpanded'));

			new Ext.KeyMap('search', {
				key: Ext.EventObject.ENTER,
				fn: function(){
					var query = Ext.get('search').dom.value;

					if (query)
						location.href = webroot + 'search.html?manualSearch=1&livesearch=1&player=' + playerid + '&query=' + Ext.encode(query);
				},
				scope: this
			});
		},

		toggleItem : function(panel){
			var el = Ext.get(panel);
			if (el) {
				if (el.hasClass('homeMenuItem_expanded'))
					this.collapseItem(panel, true);
				else
					this.expandItem(panel);
			}
		},

		expandItem : function(panel){
			// we only allow for one open item
			this.collapseAll();

			Utils.setCookie('SqueezeCenter-homeMenuExpanded', panel);

			var el = Ext.get(panel);
			if (el) {
				var icon = el.child('img:first', true);
				if (icon)
					Ext.get(icon).addClass('disclosure_expanded');

				el.addClass('homeMenuItem_expanded');

				var subPanel = Ext.get(panel + '_expanded');
				if (subPanel) {
					subPanel.setVisible(true);
					subPanel.addClass('homeMenuSection_expanded');
				}

			}

			this.onResize();
		},

		collapseItem : function(panel, resetState){
			if (resetState)
				Utils.setCookie('SqueezeCenter-homeMenuExpanded', '');

			var el = Ext.get(panel);
			if (el) {
				if (icon = el.child('img:first', true))
					Ext.get(icon).removeClass('disclosure_expanded');

				el.removeClass('homeMenuItem_expanded');

				var subPanel = Ext.get(panel + '_expanded');
				if (subPanel){
					subPanel.setVisible(false);
					subPanel.removeClass('homeMenuSection_expanded');
				}
			}

			Utils.resizeContent();
			this.onResize();
		},

		collapseAll : function(){
			var items = Ext.DomQuery.select('div.homeMenuItem_expanded');
			for(var i = 0; i < items.length; i++) {
				this.collapseItem(items[i].id);
			}
		},

		showSearchResults : function(value){
			Ext.get('my_musicMenu').setVisible(value.length <= 2);
			Ext.get('searchMenu').setVisible(value.length > 2);
		},

		onResize : function(){
			var contW = Ext.get(document.body).getWidth() - 30
			Ext.select('div.homeMenuSection').setWidth(contW);

			var el;
			if (Ext.isIE && !Ext.isIE7 && (el = Ext.DomQuery.selectNode('div.inner_content')))
				Ext.get(el).setWidth(contW+25);

		}
	}
}();