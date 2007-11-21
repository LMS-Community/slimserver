Help = function(){
	return {
		init : function(){
			var layout = new Ext.BorderLayout('mainbody', {
				north: {
					split:false,
					initialSize: 40
				},
				south: {
					split:false,
					initialSize: 16
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

			new Ext.Button('cancel', {
				text: strings['close'],
				handler: function(){
					window.open('javascript:window.close();','_self','');
				}
			});

			this.onResize();
		},

		// resize panels, folder selectors etc.
		onResize : function(){
			var body = Ext.get(document.body);

			var dimensions = new Array();
			dimensions['maxHeight'] = body.getHeight() - body.getMargins('tb');
			dimensions['maxWidth'] = body.getWidth() - body.getMargins('rl')  - (Ext.isIE && !Ext.isIE7 ? body.getMargins('rl') : 0);

			var bg = Ext.get('background');
			bg.setWidth(body.getWidth() - (Ext.isIE && !Ext.isIE7 ? body.getMargins('rl') : 0));
			bg.setHeight(dimensions['maxHeight']);

			Ext.get('mainbody').setHeight(dimensions['maxHeight']);
			Ext.get('maincontent').setHeight(dimensions['maxHeight']-115);

			try { this.layout(); }
			catch(e) {}
		}
	};
}();
