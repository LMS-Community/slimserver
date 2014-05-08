Help = {
	init : function(){
		var mainpanel = {
			layout: 'border',
			border: false,
			style: 'z-index: 200;',
			renderHidden: true,
			items: [
				{
					region: 'north',
					contentEl: 'header',
					border: false,
					margins: '5 5 0 5',
					height: 40
				},
				
				{
					region: 'center',
					layout: 'border',
					border: false,
					items: [
						{
							region: 'north',
							contentEl: 'inner_header',
							border: false,
							height: 16,
							margins: '0 15'
						},
						{
							region: 'center',
							contentEl: 'maincontent',
							border: false,
							margins: '0 15'
						},
						{
							region: 'south',
							contentEl: 'inner_footer',
							border: false,
							height: 43,
							margins: '0 15'
						}
					]
				},

				{
					region: 'south',
					contentEl: 'footer',
					border: false,
					margins: '0 5 5 5',
					height: 16
				}
			]
		}

		this.layout = new Ext.Viewport(mainpanel);
		this.background = Ext.get('background');
		this.body = Ext.get(document.body);
		this.maincontent = Ext.get('maincontent');

		// cache the offsets we're going to use to resize the background image
		this.offsets = [
			this.background.getTop() * 2,
			this.background.getLeft() * 2,
			this.maincontent.getTop() + this.body.getHeight() - Ext.get('inner_footer').getTop()
		];

		new Ext.Button({
			renderTo: 'close',
			text: SqueezeJS.string('close'),
			handler: function(){
				window.open('javascript:window.close();','_self','');
			}
		});

		Ext.EventManager.onWindowResize(this.onResize, this);
		this.onResize(this.body.getWidth(), this.body.getHeight());
	},

	// resize panels, folder selectors etc.
	onResize : function(width, height) {
		this.background.setHeight(height - this.offsets[0]);
		this.background.setWidth(width - this.offsets[1]);
		this.maincontent.setHeight(height - this.offsets[2]);
	}
}
