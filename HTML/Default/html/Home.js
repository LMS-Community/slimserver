var Home = {
	init : function(){
		// use "display:none" to hide inactive elements
		var el;
		var items = Ext.DomQuery.select('div.homeMenuSection, div.expandableHomeMenuItem');
		for(var i = 0; i < items.length; i++) {
			if (el = Ext.get(items[i].id)) {
				el.enableDisplayMode('block');
			}
		}

		// collapse/expand items - collapse by default
		items = Ext.DomQuery.select('div.expandableHomeMenuItem');
		for(var i = 0; i < items.length; i++) {
			if (el = Ext.get(items[i].id)) {
				var panel = items[i].id.replace(/_expanded/, '');

				if (SqueezeJS.getCookie('Squeezebox-expanded-' + panel) != '1')
					this.collapseItem(panel);

				else
					this.expandItem(panel);
			}
		}
		
		new Ext.KeyNav('tuneinurl', {
			'enter': function(e) {
				Home.tuneInUrl('play')
			}
		});
		
		if (LiveSearch)
			LiveSearch.init();
	},

	onSelectorClicked : function(ev, target){
		var target = Ext.get(target);
		var el;

		if (target.hasClass('browsedbControls'))
			return;

		el = target;
		if (el.hasClass('homeMenuItem') || (el = target.child('.homeMenuItem')) || (el = target.up('div.homeMenuItem', 1)))
			Home.toggleItem(el.id);
	},

	toggleItem : function(panel){
		var el = Ext.get(panel);
		if (el) {
			if (el.hasClass('homeMenuItem_expanded'))
				this.collapseItem(panel);
			else
				this.expandItem(panel);
		}
	},

	expandItem : function(panel){
		SqueezeJS.setCookie('Squeezebox-expanded-' + panel, '1');

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
	},

	collapseItem : function(panel){
		SqueezeJS.setCookie('Squeezebox-expanded-' + panel, '0');

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
	},

	tuneInUrl : function(mode) {
		var url = Ext.get('tuneinurl').getValue();

		SqueezeJS.Controller.playerRequest({
			params: ['playlist', mode, url],
			showBriefly: SqueezeJS.string('connecting_for') + ' ' + url
		});
	},

	setLineIn: function(msg){
		SqueezeJS.UI.setProgressCursor();
		SqueezeJS.Controller.playerRequest({
			params: [ 'setlinein', 'linein' ],
			showBriefly: msg
		});
	}
};