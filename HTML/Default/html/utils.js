// Extensions to ExtJS classes
Slim = {};

// our own cookie manager doesn't prepend 'ys-' to any cookie
Slim.CookieManager = function(config){
	Slim.CookieManager.superclass.constructor.call(this);
};

Ext.extend(Slim.CookieManager, Ext.state.CookieProvider, {
	readCookies : function(){
		var cookies = {};
		var c = document.cookie + ";";
		var re = /\s?(.*?)=(.*?);/g;
		var matches;
		while((matches = re.exec(c)) != null){
			var name = matches[1];
			var value = matches[2];
			if(name){
				cookies[name] = value;
			}
		}
		return cookies;
	},

	setCookie : function(name, value){
		document.cookie = name + "=" + value +
		((this.expires == null) ? "" : ("; expires=" + this.expires.toGMTString())) +
		((this.path == null) ? "" : ("; path=" + this.path)) +
		((this.domain == null) ? "" : ("; domain=" + this.domain)) +
		((this.secure == true) ? "; secure" : "");
	},

	clearCookie : function(name){
		document.cookie = name + "=null; expires=Thu, 01-Jan-70 00:00:01 GMT" +
			((this.path == null) ? "" : ("; path=" + this.path)) +
			((this.domain == null) ? "" : ("; domain=" + this.domain)) +
			((this.secure == true) ? "; secure" : "");
		}
	});


// graphical button, defined in three element sprite for normal, mouseover, pressed
Slim.Button = function(renderTo, config){
	this.tooltipType = config.tooltipType || 'title';

	this.template = new Ext.Template(
		'<table border="0" cellpadding="0" cellspacing="0"><tbody><tr>',
		'<td></td><td><button type="{1}" style="padding:0">{0}</button></td><td></td>',
		'</tr></tbody></table>');

	Slim.Button.superclass.constructor.call(this, renderTo, config);
};

Ext.extend(Slim.Button, Ext.Button, {
	render: function(renderTo) {
		Slim.Button.superclass.render.call(this, renderTo);
		if (this.minWidth) {
			var btnEl = this.el.child("button:first");
			btnEl.setWidth(this.minWidth);
		}
	}
});



var Utils = function(){
	cookieManager = new Slim.CookieManager({
		expires: new Date(new Date().getTime() + 1000*60*60*24*365)
	});

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

					Utils.unHighlight();

					// always highlight the main selector, not its children
					el = Ext.get(target).findParent('.selectorMarker');
					if (el = Ext.get(el)) {
						el.replaceClass('selectorMarker', 'mouseOver');

						el.on('click', Utils.onSelectorClicked);

						controls = Ext.DomQuery.select('span.browsedbControls, span.browsedbRightControls, span.browsedbLeftControls, div.playlistControls', el.dom);
						for (var i = 0; i < controls.length; i++) {
							Ext.get(controls[i]).show();
						}
					}
				}
			});
		},

		unHighlight: function(){
			// remove highlighting from the other DIVs
			items = Ext.DomQuery.select('div.mouseOver');
			for(var i = 0; i < items.length; i++) {
				el = Ext.get(items[i].id);
				if (el) {
					el.replaceClass('mouseOver', 'selectorMarker');
					el.un('click', Utils.onSelectorClicked);

					controls = Ext.DomQuery.select('span.browsedbControls, span.browsedbRightControls, span.browsedbLeftControls, div.playlistControls', el.dom);
					for (var i = 0; i < controls.length; i++) {
						Ext.get(controls[i]).hide();
					}
				}
			}
		},

		onSelectorClicked : function(ev, target){
			el = Ext.get(target).child('a.browseItemLink');
			if (el && el.dom.href) {
				if (el.dom.target) {
					frames[el.dom.target].location.href = el.dom.href;
				}
				else {
					location.href = el.dom.href;
				}
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

				el.setHeight(myHeight);
			}

			if (el = Ext.get('browsedbList')) {
				el.setHeight(Ext.fly(document.body).getHeight() - el.getTop() - infoHeight);
			}
			if (el = Ext.get('songInfo')) {
				el.setHeight(Ext.fly(document.body).getHeight() - el.getTop() - infoHeight);
			}

		},

		processPlaylistCommand : function(param) {
			this.processRawCommand('/status.html?' + param + 'ajaxRequest=1&force=1', true);
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
		},


		initSearch : function(searchField){
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
								Utils.resizeContent();
								try {
									MainMenu.showPanel('search');
									MainMenu.onResize();
								}
								catch(e){}
							}
						);
					}
					else
						try {
							MainMenu.showPanel('my_music');
						}
						catch(e){}

					return true;
				}
			});
			search.applyTo(searchField || 'livesearch');
		},


		setCookie : function(name, value) {
			cookieManager.set(name, value);
		},

		getCookie : function(name, failover) {
			return cookieManager.get(name, failover);
		}
	};
}();
Ext.EventManager.onDocumentReady(Utils.init, Utils, true);


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

function setCookie(name, value) {
	Utils.setCookie(name, value);
}