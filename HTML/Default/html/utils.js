// Extensions to ExtJS classes
Slim = {};

Slim.Sortable = function(config){
	Ext.apply(this, config);

	Ext.dd.ScrollManager.register(this.el);

	this.init();
};

Slim.Sortable.prototype = {
	init: function(){
		var items = Ext.DomQuery.select(this.selector);
		this.offset |= 0;

		for(var i = 0; i < items.length; i++) {
			var item = Ext.get(items[i]);

			if (!item.hasClass('dontdrag'))
				item.dd = new Slim.DDProxy(items[i], this.el, {
					position: i + this.offset,
					list: this
				});
		}

		Utils.isDragging = false;
	},

	onDrop: function(source, target) {
		if (target && source) {
			var sourcePos = Ext.get(source.id).dd.config.position;
			var targetPos = Ext.get(target.id).dd.config.position;

			if (sourcePos >= 0 && targetPos >= 0 && (sourcePos != targetPos)) {

				if (sourcePos > targetPos) {
					source.insertBefore(target);
				}
				else  {
					source.insertAfter(target);
				}

				this.onDropCmd(sourcePos, targetPos);
				this.init();
			}
		}
	},

	onDropCmd: function() {}
}


Slim.DDProxy = function(id, sGroup, config){
	Slim.DDProxy.superclass.constructor.call(this, id, sGroup, config);
	this.setXConstraint(0, 0);
	this.scroll = false;
	this.scrollContainer = true;
};

Ext.extend(Slim.DDProxy, Ext.dd.DDProxy, {
	// highlight a copy of the dragged item to move with the mouse pointer
	startDrag: function(x, y) {
		var dragEl = Ext.get(this.getDragEl());
		var el = Ext.get(this.getEl());
		Utils.unHighlight();
		Utils.isDragging = true;

		dragEl.applyStyles({'z-index':2000});
		dragEl.update(el.child('div').dom.innerHTML);
		dragEl.addClass(el.dom.className + ' dd-proxy');
	},

	// disable the default behaviour which would place the dragged element
	// we don't need to place it as it will be moved in onDragDrop
	endDrag: function() {
		Utils.isDragging = false;
	},

	onDragEnter: function(ev, id) {
		var source = Ext.get(this.getEl());
		var target = Ext.get(id);

		if (target && source)
			this.addDropIndicator(target, source.dd.config.position, target.dd.config.position); 
	},

	onDragOut: function(e, id) {
		this.removeDropIndicator(Ext.get(id));
	},

	onDragDrop: function(e, id) {
		Utils.isDragging = false;
		this.removeDropIndicator(Ext.get(id));
		this.config.list.onDrop(Ext.get(this.getEl()), Ext.get(id));
	},

	addDropIndicator: function(el, sourcePos, targetPos) {
		if (parseInt(targetPos) < parseInt(sourcePos))
			el.addClass('dragUp');
		else
			el.addClass('dragDown');
	},

	removeDropIndicator: function(el) {
		el.removeClass('dragUp');
		el.removeClass('dragDown');
	}
});


// our own cookie manager doesn't prepend 'ys-' to any cookie
Slim.CookieManager = function(config){
	Slim.CookieManager.superclass.constructor.call(this, config);
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

	// keep track of the player's power mode
	// assume it's powered on if it's undefined (http client)
	this.on('dataupdate', function(result){ this.power = (result.power == null) || result.power; });
};

Ext.extend(Slim.Button, Ext.Button, {
	power: 0,

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
	var unHighlightTimer;
	var hideSearchTimer;

	return {
		isDragging : false,

		init : function(){
			// make sure all selectable list items have a unique ID
			var items = Ext.DomQuery.select('.selectorMarker');
			for(var i = 0; i < items.length; i++) {
				Ext.id(Ext.get(items[i]));
			}

			if (!unHighlightTimer)
				unHighlightTimer = new Ext.util.DelayedTask(this.unHighlight);

			// don't remove the highlight automatically while we're editing a search term or similar
			Ext.select('.browsedbControls input[type="text"]').on({
				focus: unHighlightTimer.cancel,
				click: unHighlightTimer.cancel
			});

			// initialize search field displayed in some browse pages
			var el = Ext.get('headerSearchInput');
			if (el && (items = Ext.get('headerSearchBtn'))) {
				items.on({
					mouseover: function(){
						el.setDisplayed(true);
						hideSearchTimer.delay(2000);
					}
				});

				if (!hideSearchTimer)
					hideSearchTimer = new Ext.util.DelayedTask(function(){ el.setDisplayed(false); });

				el.on({
					click: hideSearchTimer.cancel,
					focus: hideSearchTimer.cancel,
					blur: function(){ hideSearchTimer.delay(2000); }
				});
			}

			Ext.EventManager.onWindowResize(Utils.resizeContent);
			Ext.EventManager.onDocumentReady(Utils.resizeContent);
		},

		highlight : function(target, onClickCB){
			// don't highlight while dragging elements around
			if (this.isDragging)
				return;

			// return if the target is a child of the main selector
			var el = Ext.get(target.id); 
			if (el != null && el.hasClass('.mouseOver'))
				return;

			// always highlight the main selector, not its children
			if (el != null) {
				Utils.unHighlight();
				highlightedEl = el;

				if (el.hasClass('selectedItem')) {
					el.addClass('mouseOver');
				}
				else {
					el.replaceClass('selectorMarker', 'mouseOver');
				}

				highlightedEl.onClickCB = onClickCB || Utils.onSelectorClicked;
				el.on('click', highlightedEl.onClickCB);
			}

			if (unHighlightTimer)
				unHighlightTimer.delay(2000);	// remove highlighter after x seconds of inactivity
		},

		unHighlight : function(){
			// remove highlighting from the other DIVs
			if (highlightedEl) {
				if (highlightedEl.hasClass('selectedItem')) {
					highlightedEl.removeClass('mouseOver');
				}
				else {
					highlightedEl.replaceClass('mouseOver', 'selectorMarker');
				}
				highlightedEl.un('click', highlightedEl.onClickCB);
			}
		},

		onSelectorClicked : function(ev, target){
			target = Ext.get(target);
			if (target.hasClass('browseItemDetail') || target.hasClass('playlistSongDetail'))
				target = Ext.get(target.findParentNode('div'));

			var el = target.child('a.browseItemLink');
			if (el && el.dom.href) {
				if (el.dom.target) {
					try { parent.frames[el.dom.target].location.href = el.dom.href; }
					catch(e) { location.href = el.dom.href; }
				}
				else {
					location.href = el.dom.href;
				}
			}
		},

		resizeContent : function(){
			var infoHeight = 0;
			var footerHeight = 0;

			if (el = Ext.get('infoTab'))
				infoHeight = el.getHeight();

			if (el = Ext.get('pageFooterInfo'))
				footerHeight = el.getHeight();

			var maxHeight = Ext.fly(document.body).getHeight() - infoHeight - footerHeight;

			var el;

			if (el = Ext.get('browsedbList')) {
				el.setHeight(maxHeight - el.getTop());
			}

			else if (el = Ext.get('songInfo')) {
				el.setHeight(maxHeight - el.getTop());
			}

			else if ((el = Ext.get('content')) && el.hasClass('scrollingPanel')) {
				el.setHeight(maxHeight - el.getTop());
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

		initSearch : function(manual){
			search = new Ext.form.TextField({
				validationDelay: 100,
				validateOnBlur: false,
				selectOnFocus: true,

				validator: manual ? null : function(value){
					if (value.length > 2) {
						var el;

						if (el = Ext.get('browsedbHeader'))
							el.remove();

						if (el = Ext.get('browsedbList'))
							el.remove();

						el = Ext.get('search-results')

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
					else {
						var el = Ext.get('search-results');
						if (el)
							el.update('');
					}

					return true;
				}
			});
			search.applyTo('livesearch');
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
				info.update('<img src="' + webroot + 'html/images/btn_info.gif"/>&nbsp;' + text);
				info.fadeIn().pause(2).fadeOut();
			}
		},

		replacePlayerIDinUrl : function(url, id){
			if (!id)
				return url;

			if (typeof url == 'object' && url.search != null) {
				var args = Ext.urlDecode(url.search.replace(/^\?/, ''));

				args.player = id;

				if (args.playerid)
					args.playerid = id;

				return url.pathname + '?' + Ext.urlEncode(args) + url.hash;
			}

			var rExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;

			if (url.search(/player=/) && ! rExp.exec(url))
				url = url.replace(/player=/ig, '');

			return (rExp.exec(url) ? url.replace(rExp, '=' + id) : url + '&player=' + id);
		},

		toggleFavorite : function(el, url, title) {
			var el = Ext.get(el);
			if (el) {
				el.getUpdateManager().showLoadIndicator = false;
				el.load({
					url: 'plugins/Favorites/favcontrol.html?url=' + url + '&title=' + title + '&player=' + player,
					method: 'GET'
				});
			}
		}
	};
}();
Ext.EventManager.onDocumentReady(Utils.init, Utils, true);


// some scripts for the scanning progress page
var ScannerProgress = function(){
	var progressTimer;

	return {
		init: function(){
			progressTimer = new Ext.util.DelayedTask(this.refresh, this);
			this.refresh();
		},

		refresh: function(){
			Ext.Ajax.request({
				method: 'GET',
				url: webroot + 'progress.html',
				params: {
					type: progresstype,
					barlen: progressbarlen,
					player: playerid,
					ajaxRequest: 1
				},
				timeout: 3000,
				disableCaching: true,
				success: this.updatePage
			});
			
		},

		updatePage: function(result){
			// clean up response to have a correct JSON object
			result = result.responseText;
			result = result.replace(/<[\/]?pre>|\n/g, '');
			result = Ext.decode(result);

			if (result['scans']) {
				var elems = ['Name', 'Done', 'Total', 'Active', 'Time', 'Bar', 'Info'];
				var el, value;

				var scans = result.scans
				for (var i=0; i<scans.length; i++) {
					if (el = Ext.get('Info'+(i-1)))
						el.setDisplayed(false);

					// only show the count if it is more than one item
					Ext.get('Count'+i).setDisplayed(scans[i].Total ? true : false);
					Ext.get('progress'+i).setDisplayed(scans[i].Name ? true : false);

					for (var j=0; j<elems.length; j++) {
						if (value = scans[i][elems[j]])
							Ext.get(elems[j]+i).update(decodeURIComponent(value));

					}
				}
			}

			if (result['message']) {
				if (result['total_time'])
					Ext.get('message').update(result.message + timestring + result.total_time);

				else
					Ext.get('message').update(result.message);
			} 

			else
				progressTimer.delay(5000)
		}
	};
}();


// some prototype JS compatibility classes
var Element = function(){
	return {
		remove: function(el) {
			if (el = Ext.get(el))
				el.remove();
		}
	}
}();

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

		width = Math.min(150, parseInt(width));
	}

	if (src.width > width || !src.width)
		src.width = width;

}

function setCookie(name, value) {
	Utils.setCookie(name, value);
}

function ajaxRequest(myUrl, params, action) {
	Ext.Ajax.request({
		method: 'GET',
		url: myUrl,
		params: params,
		timeout: 5000,
		disableCaching: true,
		callback: action
	});
}

// request and update with new list html, requires a 'mainbody' div defined in the document
// templates should use the ajaxUpdate param to block headers and footers.
function ajaxUpdate(url, params, callback) {
	var el = Ext.get('mainbody');

	if (el) {
		var um = el.getUpdateManager();

		if (um)
			um.loadScripts = true;

		el.load(url, params + '&ajaxUpdate=1&player=' + player, callback || Utils.init);
	}
}

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
