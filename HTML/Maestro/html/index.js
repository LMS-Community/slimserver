Main = function(){
	return {
		init : function(){
			var layout = new Ext.BorderLayout('mainbody', {
				north: {
					split:false,
					initialSize: 45
				},
				south: {
					split:false,
					initialSize: 38
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
		},
		
		// resize panels, folder selectors etc.
		onResize : function(){
			dimensions = Ext.fly(document.body).getViewSize();
			Ext.get('mainbody').setHeight(dimensions.height-35);

			colWidth = Math.floor((dimensions.width - 168) / 2);
			colHeight = dimensions.height-210;

			left = Ext.get('leftcontent');
			left.setWidth(colWidth);
			left.setHeight(colHeight);

			right = Ext.get('rightcontent');
			right.setWidth(colWidth);
			right.setHeight(colHeight);

			Ext.get('leftpanel').setHeight(colHeight + 10);
			Ext.get('rightpanel').setHeight(colHeight + 10);

			this.layout();
		}
	};   
}();
Ext.EventManager.onDocumentReady(Main.init, Main, true);
