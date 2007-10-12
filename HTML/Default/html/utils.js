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

	if (typeof config.updateHandler == 'function') {
		this.on('dataupdate', config.updateHandler);
	}
};

Ext.extend(Slim.Button, Ext.Button, {
	render: function(renderTo) {
		Slim.Button.superclass.render.call(this, renderTo);
		if (this.minWidth) {
			var btnEl = this.el.child("button:first");
			btnEl.setWidth(this.minWidth);
		}
	},

	setTooltip: function(tooltip){
		if (this.tooltip == tooltip)
			return;

		this.tooltip = tooltip;
		
		var btnEl = this.el.child("button:first");

		if(typeof this.tooltip == 'object'){
			Ext.QuickTips.tips(Ext.apply({
				target: btnEl.id
			}, this.tooltip));
		} 
		else {
			btnEl.dom[this.tooltipType] = this.tooltip;
		}
	},

	setClass: function(newClass) {
		this.el.removeClass(this.cls);
		this.cls = newClass
		this.el.addClass(this.cls);
	},

	setIcon: function(newIcon) {
		var btnEl = this.el.child("button:first");
		if (btnEl)
			btnEl.setStyle('background-image', newIcon ? 'url(' + webroot + newIcon + ')' : '');
	},

	// see whether the button should be overwritten
	customHandler: function(result, id) {
		if (result.playlist_loop && result.playlist_loop[0] 
			&& result.playlist_loop[0].buttons && result.playlist_loop[0].buttons[id]) {

			var btn = result.playlist_loop[0].buttons[id];

			if (btn.cls)
				this.setClass(btn.cls);
			else if (btn.icon)
				this.setIcon(btn.icon);

			if (btn.tooltip)
				this.setTooltip(btn.tooltip);

			if (btn.command)
				this.cmd = btn.command;

			return true;
		}

		return false;
	}
});



var Utils = function(){
	var cookieManager = new Slim.CookieManager({
		expires: new Date(new Date().getTime() + 1000*60*60*24*365)
	});
	var highlightedEl;

	return {
		init : function(){
			// make sure all selectable list items have a unique ID
			var items = Ext.DomQuery.select('.selectorMarker');
			for(var i = 0; i < items.length; i++) {
				Ext.id(Ext.get(items[i]));
			}

			Ext.EventManager.onWindowResize(Utils.resizeContent);
			Ext.EventManager.onDocumentReady(Utils.resizeContent);
		},

		highlight : function(target){
			// return if the target is a child of the main selector
			var el = Ext.get(target.id); 
			if (el != null && el.hasClass('.mouseOver'))
				return;

			// always highlight the main selector, not its children
			if (el != null) {
				Utils.unHighlight();
				highlightedEl = el;

				if (el.hasClass('currentSong')) {
					el.addClass('mouseOver');
				}
				else {
					el.replaceClass('selectorMarker', 'mouseOver');
				}

				el.on('click', Utils.onSelectorClicked);
			}
		},

		unHighlight : function(){
			// remove highlighting from the other DIVs
			if (highlightedEl) {
				if (highlightedEl.hasClass('currentSong')) {
					highlightedEl.removeClass('mouseOver');
				}
				else {
					highlightedEl.replaceClass('mouseOver', 'selectorMarker');
				}
				highlightedEl.un('click', Utils.onSelectorClicked);
			}
		},

		onSelectorClicked : function(ev, target){
			var el = Ext.get(target).child('a.browseItemLink');
			if (el && el.dom.href) {
				if (el.dom.target) {
					frames[el.dom.target].location.href = el.dom.href;
				}
				else {
					location.href = el.dom.href;
				}
			}
		},

		resizeContent : function(){
			var infoHeight = 0;
			if (el = Ext.get('infoTab'))
				infoHeight = el.getHeight();

			var el = Ext.get('content');

			if (el && el.hasClass('scrollingPanel')) {
				var myHeight = Ext.fly(document.body).getHeight() - el.getTop() - infoHeight;
				el.setHeight(myHeight);
			}

			if (el = Ext.get('browsedbList')) {
				el.setHeight(Ext.fly(document.body).getHeight() - el.getTop() - infoHeight);
			}
			if (el = Ext.get('songInfo')) {
				el.setHeight(Ext.fly(document.body).getHeight() - el.getTop() - infoHeight);
			}

		},

		processPlaylistURL : function(param, reload) {
			this.processCommandURL('/status_header.html?' + param + 'ajaxRequest=1&force=1', true);
			if (reload) {
				try { Playlist.load(null, true); }
				catch(e) {
					try { parent.Playlist.load(null, true); }
					catch(e) {}
				}
			}
		},

		processCommandURL : function(myUrl, updateStatus) {
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

		processCommand : function(config){
			Ext.Ajax.request({
				url: '/jsonrpc.js',
				method: 'POST',
				params: Ext.util.JSON.encode({
					id: 1,
					method: "slim.request",
					params: config.params
				}),
				success: config.success,
				failure: config.failure,
				scope: config.scope || this
			});
		},

		processPlayerCommand : function(config){
			config.params = [
				playerid,
				config.params
			];
			this.processCommand(config);
		},

		initSearch : function(searchField, callback){
			search = new Ext.form.TextField({
				validationDelay: 50,
				validateOnBlur: false,

				validator: function(value){
					if (value.length > 2) {
						var el = Ext.get('search-results')

						// don't wait for an earlier update to finish
						var um = el.getUpdateManager();
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
								Utils.init();
							}
						);
					}
					else if (typeof callback == 'function') { 
						try { eval(callback(value)); }
						catch(e){}
					}

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
		},

		formatTime : function(seconds){
			var hours = Math.floor(seconds / 3600);
			var minutes = Math.floor((seconds - hours*3600) / 60);
			seconds = Math.floor(seconds % 60);

			var formattedTime = (hours ? hours + ':' : '');
			formattedTime += (minutes ? (minutes < 10 && hours ? '0' : '') + minutes : '0') + ':';
			formattedTime += (seconds ? (seconds < 10 ? '0' : '') + seconds : '00');
			return formattedTime;
		},

		msg : function(text){
			var info = Ext.get('footerInfoText');
			if (info) {
				info.update('<img src="' + webroot + 'html/images/info.png"/>&nbsp;' + text);
				info.fadeIn().pause(2).fadeOut();
			}
		}
	};
}();
Ext.EventManager.onDocumentReady(Utils.init, Utils, true);


// some legacy scripts

// update the status if the Player is available
function refreshStatus() {
	try { Player.getUpdate(); }
	catch(e) {
		try { parent.Player.getUpdate(); }
		catch(e) {}
	}
}

function resize(src, width) {
	if (!width) {
		// special case for IE (argh)
		if (document.all) //if IE 4+
			width = document.body.clientWidth*0.5;

		else if (document.getElementById) //else if NS6+
			width = window.innerWidth*0.5;

	}

	if (src.width > width || !src.width)
		src.width = width;

}

function setCookie(name, value) {
	Utils.setCookie(name, value);
}