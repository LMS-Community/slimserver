var Utils = function(){
	return {
		init : function(){
			Ext.EventManager.onWindowResize(Utils.resizeContent);
			Ext.EventManager.onDocumentReady(Utils.resizeContent);

			// add highlighter class
			this.addBrowseMouseOver();

		},

		addBrowseMouseOver: function(){
			Ext.addBehaviors({
				'.selectorMarker, .currentSong@mouseover': function(ev, target){
					// return if the target is a child of the main selector
					if (Ext.get(target).findParent('.mouseOver'))
						return;

					// remove highlighting from the other DIVs
					items = Ext.DomQuery.select('div.mouseOver');
					for(var i = 0; i < items.length; i++) {
						el = Ext.get(items[i].id);
						if (el) {
							el.replaceClass('mouseOver', 'selectorMarker');
							el.un('click', Utils.onSelectorClicked);

							if (controls = Ext.DomQuery.selectNode('span.browsedbControls, div.playlistControls', el.dom)) {
								Ext.get(controls).hide();
							}
						}
					}

					// always highlight the main selector, not its children
					el = Ext.get(target).findParent('.selectorMarker');
					if (el = Ext.get(el)) {
						el.replaceClass('selectorMarker', 'mouseOver');
						
						el.on('click', Utils.onSelectorClicked);
						
						if (controls = Ext.DomQuery.selectNode('span.browsedbControls, div.playlistControls', el.dom)) {
							Ext.get(controls).show();
						}
					}
				}
			});
		},
		
		onSelectorClicked : function(ev, target){
			el = Ext.get(target).child('a.browseItemLink');
			if (el && el.dom.href) {
				location.href = el.dom.href;
			}
			else if (Ext.get(target).is('div.homeMenuItem')) {
				MainMenu.doMenu(Ext.get(target).id);
			}
			else if (el = Ext.get(target).child('div.homeMenuItem')) {
				MainMenu.doMenu(Ext.get(el).id);
			}
		},

		resizeContent : function(){
			infoHeight = 0;
			if (el = Ext.get('infoTab'))
				infoHeight = el.getHeight();

			el = Ext.get('content');

			if (el && el.hasClass('scrollingPanel')) {

				myHeight = Ext.fly(document.body).getHeight() - el.getTop() - infoHeight;
				myHeight = Math.max(300, myHeight);

				el.setHeight(myHeight);
			}

			if (el = Ext.get('browsedbList')) {	
				el.setHeight(Ext.fly(document.body).getHeight() - el.getTop() - infoHeight);
			}
		},

		processPlaylistCommand : function(param) {
			this.processRawCommand('status.html?' + param + 'ajaxRequest=1&force=1', true);
		},

		processRawCommand : function(myUrl, updateStatus) {
			Ext.Ajax.request({
				method: 'GET',
				url: myUrl,
				timeout: 5000,
				disableCaching: true,
				callback: function(){
					// try updating the player control in this or the parent document
					if (updateStatus) {
						try { Player.getUpdate(); }
						catch(e) {
							try { parent.Player.getUpdate(); }
							catch(e) {}
						}
					}
				}
			});
		}

	};
}();
Ext.EventManager.onDocumentReady(Utils.init, Utils, true);


// Extensions to ExtJS classes
Slim = {};

// graphical button, defined in three element sprite for normal, mouseover, pressed
Slim.Button = function(renderTo, config){
	this.tooltipType = config.tooltipType || 'title';

	// I've given up on IE6 - don't animate those buttons :-(
	if (Ext.isIE && !Ext.isIE7)
		this.template = new Ext.Template('<img src="html/images/spacer.gif" height="{0}" width="{1}">');
	else
		this.template = new Ext.Template('<span><button><img src="html/images/spacer.gif"></button></span>');

	Slim.Button.superclass.constructor.call(this, renderTo, config);	
};

Ext.extend(Slim.Button, Ext.Button, {
	render: function(renderTo){
		if (Ext.isIE && !Ext.isIE7) {
			this.el = Ext.get(renderTo);
			this.el.setStyle({
				'background': 'url(' + this.icon + ') no-repeat 0px 0px'
			});
			this.el.on({
				'click': {
					fn: function(e){
						if (this.handler)
							this.handler.call(this.scope || this, this, e)
					},
					scope: this
				}
			});

			this.template.append(renderTo, [this.height, this.width]);
		}
		else {
			Slim.Button.superclass.render.call(this, renderTo);
			var btnFrm = this.el.child("button:first");
			btnFrm.setStyle({
				'width': this.width + 'px',
				'height': this.height + 'px',
				'padding': '0',
				'margin': '0'
			});
		}
	},

	onClick : function(e){
		if(e){
			e.preventDefault();
		}
		if(e.button != 0){
			return;
		}
		if(!this.disabled){
			if(this.enableToggle){
				this.toggle();
			}
			if(this.menu && !this.menu.isVisible()){
				this.menu.show(this.el, this.menuAlign);
			}
			this.fireEvent("click", this, e);
			if(this.handler){
				this.onMouseUp();
				this.handler.call(this.scope || this, this, e);
			}
		}
	},

	onMouseOver: function(e){
		if(!this.disabled && (myEl = this.el.child("button:first"))) {
			myEl.setStyle('background', 'url(' + this.icon + ') no-repeat 0px -' + String(this.height) + 'px');
			this.fireEvent('mouseover', this, e);
		}
	},

	onMouseOut : function(e){
		if(!e.within(this.el,  true) && (myEl = this.el.child("button:first"))) {
			myEl.setStyle('background', 'url(' + this.icon + ') no-repeat 0px 0px');
			this.fireEvent('mouseout', this, e);
		}
	},

	onFocus : function(e){
		if(!this.disabled && (myEl = this.el.child("button:first"))) {
			myEl.setStyle('background', 'url(' + this.icon + ') no-repeat 0px -' + String(this.height) + 'px');
		}
	},

	onBlur : function(e){
		if (myEl = this.el.child('button:first')) {
			myEl.setStyle('background', 'url(' + this.icon + ') no-repeat 0px 0px');
		}
		else if (Ext.isIE && !Ext.isIE7) {
			this.el.setStyle('background', 'url(' + this.icon + ') no-repeat 0px 0px');
		}
	},

	onMouseDown : function(e){
		if(!this.disabled && e.button == 0 && (myEl = this.el.child("button:first"))) {
			myEl.setStyle('background', 'url(' + this.icon + ') no-repeat 0px -' + String(this.height * 2) + 'px');
		}
	},

	onMouseUp : function(e){
		if (myEl = this.el.child('button:first')) {
			myEl.setStyle('background', 'url(' + this.icon + ') no-repeat 0px 0px');
		}
	}
});

// some legacy scripts

// update the status if the Player is available
function refreshStatus() {
	try { Player.getUpdate() }
	catch(e) {}
}

function resize(src,width)
{
	if (!width) {
		// special case for IE (argh)
		if (document.all) //if IE 4+
		{
			width = document.body.clientWidth*0.5;
		}
		else if (document.getElementById) //else if NS6+
		{
			width = window.innerWidth*0.5;
		}
	}

	if (src.width > width || !src.width)
	{
		src.width = width;
	}
}
