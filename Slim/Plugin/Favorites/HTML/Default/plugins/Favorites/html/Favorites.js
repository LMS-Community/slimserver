var Favorites = function(){
	return {
		init : function(session, index){
			SqueezeJS.UI.ScrollPanel.init();

			var favlist = new SqueezeJS.UI.Sortable({
				el: 'draglist',
				selector: 'ol#draglist li',
				index: index,

				highlighter: Highlighter,

				onDrop: function(source, target, position) {
					if (target && source) {
						var sourcePos = Ext.get(source.id).dd.config.position;
						target = Ext.get(target.id);
						var targetPos = target.dd.config.position;
			
						if (sourcePos >= 0 && targetPos >= 0 && targetPos < 10000) {
							if ((sourcePos > targetPos && position > 0) || (sourcePos < targetPos && position < 0)) {
								targetPos += position;
							}
						}

						if (sourcePos >= 0 && targetPos >= 0 && (sourcePos != targetPos)) {	
							var el;
		
							// send the result to the page handler
							if (el = Ext.get(this.el))
								// unregister event handlers
								Ext.dd.ScrollManager.unregister(el);
		
							var params = {
								action: 'move',
								index: (this.index != null ? this.index+ '.' : '') + sourcePos,
								sess: session,
								ajaxUpdate: 1,
								player: player
							};
		
							// drop into parent level
							if (targetPos > 10000) {
								targetPos = (targetPos % 10000) - 1;
								params.tolevel = target.dd.config.index != null ? target.dd.config.index : '';
							}
		
							// drop to sub-folder
							else if (position == 0)
								params.into = targetPos;
		
							// move within current level
							else
								params.to = targetPos;
		
							if (el = Ext.get('mainbody')) {
								var um = el.getUpdateManager();						
								el.load(
									webroot + 'plugins/Favorites/index.html', 
									params,
									function(){
										Favorites.init(session, new String(this.index));
									}.createDelegate(this)
								);
							}

							this.init(session, new String(this.index));
						}
					}
				}
			});

			// add upper levels in crumb list as drop targets
			// but don't add first (home) and last (current) level
			var items = Ext.DomQuery.select('div#crumblist a');
			for(var i = 1; i < items.length-1; i++) {
				var item = Ext.get(items[i]);
				var index = item.dom.href.match(/index=([\d\.,]+)/i);

				Ext.id(item);
				item.dd = new Ext.dd.DDTarget(items[i], 'draglist', {
					position: i + 10000,
					index: index && index.length > 1 ? index[1] : ''
				});
			}
		},

		initHotkeyList : function(hotkeys, current, el, input){
			var menu = new Ext.menu.Menu({
				items: [
					new Ext.menu.CheckItem({
						text: '',
						handler: this.selectHotkey,
						group: 'hotkeys',
						checked: current == ''
					})
				]
			});

			var title = '';
			for (var i = 1; i <= hotkeys.length; i++){
				var hotkey = new String(i % 10);
				menu.add(new Ext.menu.CheckItem({
					text: hotkeys[i-1],
					group: 'hotkeys',
					checked: current == hotkey
				}));

				if (current == hotkey)
					title = i;
			}

			new Ext.SplitButton({
				renderTo: el,
				text: title,
				menu: menu,
				handler: function(ev){
					if(this.menu && !this.menu.isVisible()){
						this.menu.show(this.el, this.menuAlign);
					}
					this.fireEvent('arrowclick', this, ev);
				},
				listeners: {
					menuhide: function(btn, menu){
						menu.items.each(function(item, i){
							if (item.checked){
								var el = Ext.get(input)

								if (i == 0)
									el.dom.value = ''; 

								else
									el.dom.value = i % 10;

								this.setText(el.dom.value)
							}
						}, btn);
					}
				},
				tooltip: SqueezeJS.string('favorites_hotkeys'),
				arrowTooltip: SqueezeJS.string('favorites_hotkeys'),
				tooltipType: 'title'
			});
		}
	}
}();

// XXX some legacy stuff - should eventually go away

// request and update with new list html, requires a 'mainbody' div defined in the document
// templates should use the ajaxUpdate param to block headers and footers.
function ajaxUpdate(url, params, callback) {
	var el = Ext.get('mainbody');

	if (el) {
		var um = el.getUpdateManager();

		if (um)
			um.loadScripts = true;

		el.load(url, params + '&ajaxUpdate=1&player=' + player, callback || SqueezeJS.UI.ScrollPanel.init);
	}
}

function ajaxRequest(url, params, callback) {
	Ext.Ajax.request({
		method: 'GET',
		url: url,
		params: params,
		timeout: 5000,
		disableCaching: true,
		callback: callback || function(){}
	});
}

// some prototype JS compatibility classes
var Element = function(){
	return {
		remove: function(el) {
			if (el = Ext.get(el))
				el.remove();
			SqueezeJS.UI.ScrollPanel.init();
		}
	}
}();

// pass an array of div element ids to be hidden on the page
function hideElements(elements) {
	showElements(elements, 'none');
}

// pass an array of div element ids to be shown on the page
function showElements(elements, style) {
	var el;

	if (!style)
		style = 'block';

	for (var i = 0; i < elements.length; i++) {
		if (el = Ext.get(elements[i]))
			el.setStyle('display', style);
	}
}
