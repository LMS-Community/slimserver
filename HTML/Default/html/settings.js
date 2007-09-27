Settings = function(){
	return {
		init : function(){
			var layout = new Ext.BorderLayout(document.body, {
				north: {
					split:false,
					initialSize: 55
				},
				south: {
					split:false,
					initialSize: 55
				},
				center: {
					autoScroll: false
				}
			});

			layout.beginUpdate();
			layout.add('north', new Ext.ContentPanel('header', {fitToFrame:true, fitContainer:true}));
			layout.add('south', new Ext.ContentPanel('footer', {fitToFrame:true, fitContainer:true}));
			layout.add('center', new Ext.ContentPanel('main', {fitToFrame:true, fitContainer:true}));

			Ext.EventManager.onWindowResize(this.onResize, layout);
			Ext.EventManager.onDocumentReady(this.onResize, layout, true);

			layout.endUpdate();

			Ext.get('settings').dom.src = webroot + 'settings/server/security.html?player=' + player;

			Ext.QuickTips.init();

			this.onResize();
		},


		// resize panels, folder selectors etc.
		onResize : function(){
			var main = Ext.get('main');
			var settings = Ext.get('settings');

			var dimensions = new Array();
			dimensions['maxHeight'] = main.getHeight();
			dimensions['maxWidth'] = main.getWidth() - 10;

			settings.setHeight(dimensions['maxHeight']);
			settings.setWidth(dimensions['maxWidth'] - 20);
			main.setWidth(dimensions['maxWidth']);
		}
	};
}();
