// initialize some strings
Ext.onReady(function(){
	SqueezeJS.loadStrings([
		'POWER', 'PLAY', 'PAUSE', 'NEXT', 'PREVIOUS', 'CONNECTING_FOR', 'BROWSE', 'REPEAT', 'SHUFFLE',
		'BY', 'FROM', 'ON', 'OFF', 'YES', 'NO', 'COLON', 'SQUEEZEBOX_SERVER', 'SQUEEZENETWORK', 'VOLUME',
		'CLOSE', 'CANCEL', 'CHOOSE_PLAYER', 'SYNCHRONIZE'
	]);
});

// some common components for the player control
SqueezeJS.UI = {
	// add some custom events we'll be using to our base class
	Component : Ext.extend(Ext.Component, {
		initComponent : function(config){
			if (typeof config == 'string')
				config = { el: config };

			Ext.apply(this, config);
			SqueezeJS.UI.Component.superclass.initComponent.call(this);
	
			this.el = Ext.get(this.el);
	
			// subscribe to some default events
			SqueezeJS.Controller.on({
				'playlistchange': {
					fn: this.onPlaylistChange,
					scope: this
				},
				'playerstatechange': {
					fn: this.onPlayerStateChange,
					scope: this
				}
			});
		},

		onPlaylistChange : function(){},
		onPlayerStateChange : function(){}
	}),

	progressCursorTimer : new Ext.util.DelayedTask(),
	
	setProgressCursor : function(timeout){
		var el = Ext.get(document.body);
		el.mask();

		this.progressCursorTimer.delay(timeout || 500, function(){
			el.unmask();
		});
	},
	
	Buttons : {}
};


SqueezeJS.UI.ScrollPanel = {
	offset : 0,
	el : null,

	init : function() {
		var el;
		this.offset = 0;

		if (el = Ext.get('infoTab'))
			this.offset += el.getHeight();

		if (el = Ext.get('pageFooterInfo'))
			this.offset += el.getHeight();

		if ((el = Ext.get('browsedbList')) ||
			((el = Ext.get('content')) && el.hasClass('scrollingPanel'))) {

			this.el = el;
			this.offset += this.el.getTop();

			Ext.EventManager.onWindowResize(this.onResize, this);
			this.onResize();
		}
	},

	onResize : function(){
		this.el.setHeight( Ext.fly(document.body).getViewSize().height - this.offset );
	}
};


// graphical button, defined in three element sprite for normal, mouseover, pressed
if (Ext.Button) {
	
	SqueezeJS.UI.Button = Ext.extend(Ext.Button, {
		power: 0,
		cmd : null,
		cmd_id : null,
		cls : '',
		config: {},
	
		initComponent : function(){
			this.tooltipType = this.initialConfig.tooltipType || 'title';
	
			if (this.initialConfig.template)
				this.template = this.initialConfig.template;
			else if (SqueezeJS.UI.buttonTemplate)
				this.template = SqueezeJS.UI.buttonTemplate;
	
			// if we want a pure graphical button, overwrite text and setText method
			if (this.noText) {
				this.text = '';
				this.setText = function(){};
			}
	
			SqueezeJS.UI.Button.superclass.initComponent.call(this);
	
			SqueezeJS.Controller.on({
				'playerstatechange': {
					fn: this._beforePlayerStateChange,
					scope: this
				},
				'buttonupdate': {
					fn: this._beforePlayerStateChange,
					scope: this
				}
			});
	
	
			this.on({
				'render': {
					fn: function() {
						if (this.minWidth) {
							var btnEl = this.el.child("button:first");
							Ext.get(btnEl).setWidth(this.minWidth);
						}
					},
					scope: this
				}
			});
		},
	
		_beforePlayerStateChange : function(result){
			this.power = (result.power == null) || result.power; 
	
			if (this.cmd_id) {
	
				// update custom handler for stations overwriting default behavior
				if (result.playlist_loop && result.playlist_loop[0] 
					&& result.playlist_loop[0].buttons && result.playlist_loop[0].buttons[this.cmd_id]) {
		
					var btn = result.playlist_loop[0].buttons[this.cmd_id];
		
					if (btn.cls)
						this.setClass(btn.cls);
					else if (btn.icon)
						this.setIcon(btn.icon);
		
					if (btn.tooltip)
						this.setTooltip(btn.tooltip);
	
					if (this.textOnly && btn.tooltip)
						this.setText(btn.tooltip);
	
					if (btn.command)
						this.cmd = btn.command;
				}
				else {
					// reset button
					this.cmd   = '';
					this.state = -1;
				}
			}
	
			this.onPlayerStateChange(result);
		},
	
		onPlayerStateChange : function(result){},
	
		setTooltip: function(tooltip){
			this.tooltip = tooltip;
	
			if (this.textOnly)
				this.setText(this.tooltip);
			
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
	
		setText : function(text){
			this.text = text;
	
			if (this.el)
				this.el.child(this.buttonSelector).update(text);
		},
	
		setClass: function(newClass) {
			this.el.removeClass(this.cls);
			this.cls = newClass
			this.el.addClass(this.cls);
		},
	
		setIcon: function(newIcon) {
			var btnEl = this.el.child("button:first");
			if (btnEl)
				btnEl.setStyle('background-image', newIcon ? 'url(' + SqueezeJS.Controller.getBaseUrl() + webroot + newIcon + ')' : '');
		}
	});


	// common button and label components, automatically updated on player events
	SqueezeJS.UI.Buttons.Play = Ext.extend(SqueezeJS.UI.Button, {
		isPlaying: false,
	
		initComponent : function(){
			this.cls = this.cls || 'btn-play'; 
			this.tooltip = this.tooltip || SqueezeJS.string('play');
			this.text = this.text || SqueezeJS.string('play');
			SqueezeJS.UI.Buttons.Play.superclass.initComponent.call(this);
		},
	
		handler: function(){
			if (this.isPlaying) {
				this.updateState(false);
				SqueezeJS.Controller.playerControl(['pause']);
			}
			else {
				this.updateState(true);
				SqueezeJS.Controller.playerControl(['play']);
			}
		},
	
		onPlayerStateChange: function(result){
			var newState = (result.mode == 'play');
	
			if (this.isPlaying != newState) {
				this.updateState(newState);
			}
		},
	
		updateState: function(isPlaying){
			var playEl = Ext.get(Ext.DomQuery.selectNode('table:first', Ext.get(this.initialConfig.renderTo).dom));
	
			playEl.removeClass(['btn-play', 'btn-pause']);
			playEl.addClass(isPlaying ? 'btn-pause' : 'btn-play');
	
			this.setTooltip(isPlaying ? SqueezeJS.string('pause') : SqueezeJS.string('play'));
			this.setText(isPlaying ? SqueezeJS.string('pause') : SqueezeJS.string('play'));
			this.isPlaying = isPlaying;
		}
	});
	
	SqueezeJS.UI.Buttons.Rew = Ext.extend(SqueezeJS.UI.Button, {
		initComponent : function(){
			this.cls = this.cls || 'btn-previous'; 
			this.tooltip = this.tooltip || SqueezeJS.string('previous');
			this.text = this.text || SqueezeJS.string('previous');
			this.skipCmd = ['button', 'jump_rew'];
	
			SqueezeJS.UI.Buttons.Rew.superclass.initComponent.call(this);
			
			SqueezeJS.Controller.on({
				'playerselected': {
					fn: function(playerobj) {
						if (playerobj.isplayer)
							this.skipCmd = ['button', 'jump_rew'];
						else
							this.skipCmd = ['playlist', 'index', '-1'];
					},
					scope: this
				}
			});
		},
	
		handler: function(){
			if (this.power)
				SqueezeJS.Controller.playerControl(this.skipCmd);
		},
	
		onPlayerStateChange: function(result){
			if (result.playlist_loop && result.playlist_loop[0] && result.playlist_loop[0].buttons) {
				try { this.setDisabled(!result.playlist_loop[0].buttons.rew) }
				catch(e){}
			}
			else if (this.disabled)
				this.enable();
		}
	});
	
	SqueezeJS.UI.Buttons.Fwd = Ext.extend(SqueezeJS.UI.Button, {
		initComponent : function(){
			this.cls = this.cls || 'btn-next';
			this.tooltip = this.tooltip || SqueezeJS.string('next');
			this.text = this.text || SqueezeJS.string('next');
			this.skipCmd = ['button', 'jump_fwd'];
			
			SqueezeJS.UI.Buttons.Fwd.superclass.initComponent.call(this);
			
			SqueezeJS.Controller.on({
				'playerselected': {
					fn: function(playerobj) {
						// http clients don't know IR commands
						if (playerobj.isplayer)
							this.skipCmd = ['button', 'jump_fwd'];
						else
							this.skipCmd = ['playlist', 'index', '+1'];
					},
					scope: this
				}
			});
		},
	
		handler: function(){
			if (this.power)
				SqueezeJS.Controller.playerControl(this.skipCmd);
		}
	});
	
	SqueezeJS.UI.Buttons.Repeat = Ext.extend(SqueezeJS.UI.Button, {
		cmd_id: 'repeat',
		state: -1,
	
		initComponent : function(){
			this.cls = this.initialConfig.cls || 'btn-repeat-0';
			SqueezeJS.UI.Buttons.Repeat.superclass.initComponent.call(this);
		},
	
		handler: function(){
			if (this.power) {
				if (this.cmd)
					SqueezeJS.Controller.playerControl(this.cmd);
				else
					SqueezeJS.Controller.playerControl(['playlist', 'repeat', (this.state + 1) % 3]);
			} 
		},
	
		onPlayerStateChange: function(result){
			if (this.cmd) {}
			else if (this.state == -1 || (result['playlist repeat'] != null && this.state != result['playlist repeat']))
				this.updateState(result['playlist repeat']);
	
		},
	
		updateState: function(newState){
			this.state = newState || 0;
			this.setIcon('');
			this.setTooltip(SqueezeJS.string('repeat') + ' - ' + SqueezeJS.string('repeat' + this.state));
			this.setText(SqueezeJS.string('repeat') + ' - ' + SqueezeJS.string('repeat' + this.state));
			this.setClass('btn-repeat-' + this.state);
		}
	});
	
	SqueezeJS.UI.Buttons.Shuffle = Ext.extend(SqueezeJS.UI.Button, {
		cmd_id: 'shuffle',
		state: -1,
	
		initComponent : function(){
			this.cls = this.initialConfig.cls || 'btn-shuffle-0';
			this.tooltip = this.tooltip || SqueezeJS.string('shuffle');
			this.text = this.text || SqueezeJS.string('shuffle');
			SqueezeJS.UI.Buttons.Shuffle.superclass.initComponent.call(this);
		},
	
		handler: function(){
			if (this.power) {
				if (this.cmd)
					SqueezeJS.Controller.playerControl(this.cmd);
				else
					SqueezeJS.Controller.playerControl(['playlist', 'shuffle', (this.state + 1) % 3]);
			} 
		},
	
		onPlayerStateChange: function(result){
			if (this.cmd) {}
			else if (this.state == -1 || (result['playlist shuffle'] != null && this.state != result['playlist shuffle']))
				this.updateState(result['playlist shuffle']);
	
		},
	
		updateState: function(newState){
			this.state = newState || 0;
			this.setIcon('');
			this.setTooltip(SqueezeJS.string('shuffle') + ' - ' + SqueezeJS.string('shuffle' + this.state));
			this.setText(SqueezeJS.string('shuffle') + ' - ' + SqueezeJS.string('shuffle' + this.state));
			this.setClass('btn-shuffle-' + this.state);
		}
	});
	
	SqueezeJS.UI.Buttons.Power = Ext.extend(SqueezeJS.UI.Button, {
		initComponent : function(){
			this.cls = this.cls || 'btn-power';
			this.tooltip = this.tooltip || SqueezeJS.string('power');
			this.text = this.text || SqueezeJS.string('power') + ' ' + SqueezeJS.string(this.power ? 'on' : 'off');
			SqueezeJS.UI.Buttons.Power.superclass.initComponent.call(this);
	
			SqueezeJS.Controller.on({
				playerselected: {
					fn: function(playerobj) {
						this.setVisible(playerobj && playerobj.canpoweroff)
					},
					scope: this
				}
			});
		},
	
		handler: function(){
			var newState = (this.power ? '0' : '1');
			this.power = !this.power;
			this.onPlayerStateChange();
			SqueezeJS.Controller.playerControl(['power', newState]);
		},
	
		onPlayerStateChange: function(result){
			this.setTooltip(SqueezeJS.string('power') + SqueezeJS.string('colon') + ' ' + SqueezeJS.string(this.power ? 'on' : 'off'));
			this.setText(SqueezeJS.string('power') + SqueezeJS.string('colon') + ' ' + SqueezeJS.string(this.power ? 'on' : 'off'));
	
			if (this.power)
				this.el.removeClass('btn-power-off');
			else
				this.el.addClass('btn-power-off');
		}
	});
	
	SqueezeJS.UI.Buttons.VolumeDown = Ext.extend(SqueezeJS.UI.Button, {
		initComponent : function(){
			this.cls = this.cls || 'btn-volume-decrease';
			this.tooltip = this.tooltip || SqueezeJS.string('volumedown');
			this.text = this.text || SqueezeJS.string('volumedown');
			SqueezeJS.UI.Buttons.VolumeUp.superclass.initComponent.call(this);
		},
	
		handler : function(){
			if (this.power)
				SqueezeJS.Controller.setVolume(1, '-');
		}
	});
	
	SqueezeJS.UI.Buttons.VolumeUp = Ext.extend(SqueezeJS.UI.Button, {
		initComponent : function(){
			this.cls = this.cls || 'btn-volume-increase';
			this.tooltip = this.tooltip || SqueezeJS.string('volumeup');
			this.text = this.text || SqueezeJS.string('volumeup');
			SqueezeJS.UI.Buttons.VolumeUp.superclass.initComponent.call(this);
		},
	
		handler : function(){
			if (this.power)
				SqueezeJS.Controller.setVolume(1, '+');
		}
	});

}


if (Ext.SplitButton) {

	SqueezeJS.UI.SplitButton = Ext.extend(Ext.SplitButton, {
		initComponent : function(){
			Ext.apply(this, {
				tooltipType: 'title',
				template: SqueezeJS.UI.splitButtonTemplate || null,
				handler: function(ev){
					if(this.menu && !this.menu.isVisible()){
						this.menu.show(this.el, this.menuAlign);
					}
					this.fireEvent('arrowclick', this, ev);
				}
			});

			SqueezeJS.UI.SplitButton.superclass.initComponent.call(this);
		}
	});

}



// specialised TreeLoader to create folder trees
if (Ext.tree && Ext.tree.TreeLoader) {

	SqueezeJS.UI.FileTreeLoader = function(filter) {
		Ext.apply(this, {
			dataUrl: '/jsonrpc.js',
			filter: filter
		});
		SqueezeJS.UI.FileTreeLoader.superclass.constructor.call(this);	
	};
	
	Ext.extend(SqueezeJS.UI.FileTreeLoader, Ext.tree.TreeLoader, {
		getParams: function(node){
			var cliQuery = [ 'readdirectory', 0, 99999 ];
	
			cliQuery.push("folder:" + node.id);
	
			if (this.filter)
				cliQuery.push("filter:" + this.filter);
	
			return Ext.util.JSON.encode({ 
				id: 1,
				method: "slim.request",
				params: [ "", cliQuery ]
			});
		},
	
		createNode : function(attr){
			Ext.apply(attr, {
				id: attr.path,
				text: attr.name,
				leaf: (!attr.isfolder > 0),
				iconCls: (attr.isfolder > 0 ? 'x-tree-node-alwayscollapsed' : '')
			});
	
			return SqueezeJS.UI.FileTreeLoader.superclass.createNode.call(this, attr);
		},
	
		// we have to extract the result ourselves as IE/Opera can't handle multi-node data roots
		processResponse : function(response, node, callback){
			try {
				var o = eval("(" + response.responseText + ")");
				o = eval('o.result');
	
				SqueezeJS.UI.FileTreeLoader.superclass.processResponse.call(
					this, { responseText: Ext.util.JSON.encode(o.fsitems_loop) }, node, callback);
			} catch(e){
				this.handleFailure(response);
			}
		}
	});
	
	// the FileSelector panel component
	SqueezeJS.UI.FileSelector = Ext.extend(Ext.tree.TreePanel, {
		initComponent : function(config){
			Ext.apply(this, config);
	
			Ext.apply(this, {
				rootVisible: false,
				animate: false,
				pathSeparator: '|',
				containerScroll: true,
				loader: new SqueezeJS.UI.FileTreeLoader(this.filter),
				root: new Ext.tree.AsyncTreeNode({
					text: 'root',
					id: '/'
				})
			});
	
			SqueezeJS.UI.FileSelector.superclass.initComponent.call(this);
	
			// workaround for IE7's inability to overflow unless position:relative is set
			if (Ext.isIE7) {
				var parentEl = Ext.get(this.renderTo).parent();
				parentEl.setStyle('position', 'relative');
			}
			
			this.on({
				click: this.onClick,
				collapse: this.onCollapse
			});
	
			this.selectMyPath();
	
			// activate button to add path to the selector box
			var gotoBtn;
			if (this.gotoBtn && (gotoBtn = Ext.get(this.gotoBtn))) {
				new Ext.Button({
					renderTo: gotoBtn,
					text: '>',
					handler: this.showPath,
					scope: this
				});
			}
		},
	
		onClick: function(node, e){
			var input = Ext.get(this.input);
	
			if (input != null && input.getValue() != null) {
				input.dom.value = node.id;
			}
		},
	
		// clean up collapsed nodes so we can refresh a view
		onCollapse: function(node){
			while(node.firstChild){
				node.removeChild(node.firstChild);
			}
	
			node.childrenRendered = false;
			node.loaded = false;
	
			// add dummy node to prevent file icon instead of folder
			node.appendChild([]);
		},
	
		selectMyPath: function(){
			// select the current setting, if available
			var input = Ext.get(this.input);
	
			if (input == null || input.getValue() == null || input.getValue() == '')
				return;
	
			var path = input.getValue();
			var separator = '/';
			var result;
	
			if (path.match(/^[a-z]:\\/i))
				separator = '\\';
	
			// only open the first level of UNC paths (\\server\share)
			else if (result = path.match(/^\\\\[\_\w\-]+\\[\-\_\w ]+[^\\]/))
				path = result[0];
	
			path = path.split(separator);
	
			var prev = '';
			var target = this.pathSeparator + this.root.id;
	
			// we don't need the root element on *X systems, but on Windows...
			for (var x=(path[0]=='/' ? 1 : 0); x<path.length; x++) {
				if (path[x] == '') continue;
	
				prev += (x==0 ? '' : separator) + path[x];
				target += this.pathSeparator + prev;
			}
	
			this.selectPath(target, null, function(success, selNode){
				if (!success) {
					// if that path is a Windows share, try adding it to the tree
					var result = input.getValue().match(/^\\\\[\_\w\-]+\\[\-\_\w ]+[^\\]/);
					if (result) {
						var root = this.getRootNode();
						root.appendChild(new Ext.tree.AsyncTreeNode({
							id: result[0],
							text: result[0],
							iconCls: 'x-tree-node-alwayscollapsed'
						}));
						this.selectMyPath();
					}
				}
			}.createDelegate(this));
		},
	
		// select path (if available) or try to add it to the tree if it's a network share
		showPath: function(){
			var input = Ext.get(this.input);
			if (input == null || input.getValue() == null)
				return;
	
			SqueezeJS.Controller.request({
				params: ["",
					[
						'pref',
						'validate',
						'audiodir',
						input.getValue()
					]
				],
	
				scope: this,
	
				success: function(response, options){
					var result = Ext.util.JSON.decode(response.responseText);
	
					if (result.result.valid == '1')
						this.selectMyPath();
	
					else
						input.highlight('#ff8888');
	
				}
			});
		}
	});

}



if (Ext.Window && SqueezeJS.UI.FileSelector) {

	SqueezeJS.UI.FilesystemBrowser = {
		init: function(){
			var inputEl, btnEl, filter, classes, start;
	
			var tpl = new Ext.Template('&nbsp;<input type="button" value="' + SqueezeJS.string('browse') + '" onclick="SqueezeJS.UI.FilesystemBrowser.show(\'{inputField}\', \'{filter}\')">');
			tpl.compile();
	
			// try to get the filter expression from the input fields CSS class
			// selectFolder - only display folders
			// selectFile   - display any filetype
			// selectFile_X - only show files of the type X (eg. selectFile_xml -> .xml only)
			var items = Ext.query('input.selectFolder, input[class*=selectFile]');
			for(var i = 0; i < items.length; i++) {
	
				if (inputEl = Ext.get(items[i])) {
					filter = '';
	
					if (inputEl.hasClass('selectFolder'))
						filter = 'foldersonly'
	
					else {
						classes = items[i].className.split(' ');
	
						for (var x=0; x<classes.length; x++) {
	
							if (classes[x].search(/selectFile_/) > -1) {
								filter += (filter ? '|' : '') + classes[x].replace(/selectFile_/, '');
							}
						}
						if (filter)
							filter = "filetype:" + filter;
					}
	
					btnEl = tpl.insertAfter(inputEl, {
						inputField: inputEl.id,
						filter: filter
					});
				}
			}
		},
	
		show: function(inputField, filter){
			var filesystemDlg = new Ext.Window({
				modal: true,
				collapsible: false,
				width: 350,
				height: 400,
				resizeHandles: 'se',
				html: '<div id="filesystembrowser"></div>',
				buttons: [{
					text: SqueezeJS.string('close'),
					handler: function(){
						filesystemDlg.close()
					},
					scope: filesystemDlg,
					template: SqueezeJS.UI.buttonTemplate
				}],
				listeners: {
					resize: this.onResize
				}
			});
	
			filesystemDlg.setTitle(SqueezeJS.string(filter == 'foldersonly' ? 'choose_folder' : 'choose_file'));
			filesystemDlg.show();
	
			new SqueezeJS.UI.FileSelector({
				renderTo: 'filesystembrowser',
				input: inputField,
				filter: filter
			});
		},
		
		onResize: function() {
			var el = Ext.get('filesystembrowser');
			if (el && (el = el.parent())) {
				el.setWidth(el.getWidth()-12);
				el.setStyle({ overflow: 'auto' })
			}
		}
	};

}



// menu highlighter helper classes 
SqueezeJS.UI.Highlight = function(config){
	this.init(config);
};

SqueezeJS.UI.Highlight.prototype = {
	highlightedEl : null,
	unHighlightTimer : null,
	isDragging : false,

	init : function(config) {
		// make sure all selectable list items have a unique ID
		var items = Ext.DomQuery.select('.selectorMarker');
		for(var i = 0; i < items.length; i++) {
			Ext.id(Ext.get(items[i]));
		}

		if (!this.unHighlightTimer)
			this.unHighlightTimer = new Ext.util.DelayedTask(this.unHighlight, this);

		var el;
		if (config && config.unHighlight && (el = Ext.get(config.unHighlight))) {
			el.on({
				mouseout: {
					fn: function(){
						this.unHighlightTimer.delay(2000);
					},
					scope: this
				},
				mouseover: {
					fn: function(){
						this.unHighlightTimer.cancel();
					},
					scope: this
				}
			});			
		}
	},

	highlight : function(target, onClickCB){
		// don't highlight while dragging elements around
		if (this.isDragging)
			return;

		// return if the target is a child of the main selector
		var el = Ext.get(target.id); 
		if (el == this.highlightedEl)
			return;

		// always highlight the main selector, not its children
		if (el != null) {
			this.unHighlight();
			this.highlightedEl = el;

			el.replaceClass('selectorMarker', 'mouseOver');

			this.highlightedEl.onClickCB = onClickCB || this.onSelectorClicked;
			el.on('click', this.highlightedEl.onClickCB);
		}
	},

	unHighlight : function(){
		// remove highlighting from the other DIVs
		if (this.highlightedEl) {
			this.highlightedEl.replaceClass('mouseOver', 'selectorMarker');
			this.highlightedEl.un('click', this.highlightedEl.onClickCB);
			this.highlightedEl = null;
		}
	},

	onSelectorClicked : function(ev, target){
		target = Ext.get(target);
		
		if (target.hasClass('browseItemDetail') || target.hasClass('playlistSongDetail'))
			target = Ext.get(target.findParentNode('div'));
		
		else if (target.dom.localName = 'img' && !target.findParentNode('span.browsedbControls', 3) && !target.findParentNode('div.playlistControls', 3) 
				&& (target.findParentNode('div.thumbArtwork', 5) || target.findParentNode('div.itemWithCover', 5)))
			target = Ext.get(target.findParentNode('div'));
			
		var el;
		
		if ( (el = target.child('a.browseItemLink')) && el.dom.href ) {
			if (el.dom.target) {
				try {
					if (parent.frames[el.dom.target]) {
						parent.frames[el.dom.target].location.href = el.dom.href;
					}

					else if (frames[el.dom.target]) {
						parent.frames[el.dom.target].location.href = el.dom.href;
					}
				}
				catch(e) {
					location.href = el.dom.href;
				}
			}
			else {
				location.href = el.dom.href;
			}
		}
		
		else if ( target.hasClass('slideImage') || (el = target.child('a.slideImage')) ) {
			if (target.hasClass('slideImage'))
				el = Ext.get(target);

			// we need different selectors depending on the artwork browse mode chosen
			var selector = 'div.browseItemDetail a.slideImage';                  // small artwork
			if (SqueezeJS.getCookie( 'Squeezebox-albumView') == 1)
				selector = 'div.artworkText a.slideImage';                       // large artwork
			else if (SqueezeJS.getCookie( 'Squeezebox-albumView') == 2)
				selector = 'a.slideImage';                                       // text only

			if (Ext.ux.Lightbox)
				Ext.ux.Lightbox.open(el.dom, selector, true, window);
			else if (parent.Ext.ux.Lightbox)
				parent.Ext.ux.Lightbox.open(el.dom, selector, true, window);
		}
	}
}


if (Ext.dd && Ext.dd.ScrollManager && Ext.dd.DDProxy) {
	
	// create d'n'd sortable panel
	SqueezeJS.UI.Sortable = function(config){
		Ext.apply(this, config);
	
		Ext.dd.ScrollManager.register(this.el);
	
		this.init();
	};
	
	SqueezeJS.UI.Sortable.prototype = {
		init: function(){
			var items = Ext.DomQuery.select(this.selector);
			this.offset |= 0;
	
			for(var i = 0; i < items.length; i++) {
				var item = Ext.get(items[i]);
	
				if (!item.hasClass('dontdrag'))
					item.dd = this.addDDProxy(items[i], this.el, {
						position: i + this.offset,
						list: this,
						droptarget: item.hasClass('droptarget')
					});
			}
	
			if (this.highlighter)
				this.highlighter.isDragging = false;
		},
		
		addDDProxy: function(item, el, config){
			return new SqueezeJS.DDProxy(item, el, config);
		},
	
		onDrop: function(source, target, position) {
			if (target && source) {
				var sourcePos = Ext.get(source.id).dd.config.position;
				var targetPos = Ext.get(target.id).dd.config.position;
	
				if (sourcePos >= 0 && targetPos >= 0) {
					if ((sourcePos > targetPos && position > 0) || (sourcePos < targetPos && position < 0)) {
						targetPos += position;
					}
				}
	
				if (target && sourcePos >= 0 && targetPos >= 0 && (sourcePos != targetPos)) {
					if (position == 0)
						source.remove();
	
					else if (position < 0)
						source.insertBefore(target);
	
					else
						source.insertAfter(target);
	
					this.onDropCmd(sourcePos, targetPos, position);
					this.init();
				}
			}
		},
	
		onDropCmd: function() {}
	}
	
	SqueezeJS.DDProxy = function(id, sGroup, config){
		SqueezeJS.DDProxy.superclass.constructor.call(this, id, sGroup, config);
		this.setXConstraint(0, 0);
		this.scroll = false;
		this.scrollContainer = true;
		this.position = 0;
	};
	
	Ext.extend(SqueezeJS.DDProxy, Ext.dd.DDProxy, {
		// highlight a copy of the dragged item to move with the mouse pointer
		startDrag: function(x, y) {
			var dragEl = Ext.get(this.getDragEl());
			var el = Ext.get(this.getEl());
			if (this.config.list.highlighter) {
				this.config.list.highlighter.unHighlight();
				this.config.list.highlighter.isDragging = true;
			}
	
			dragEl.applyStyles({'z-index':2000});
			dragEl.update(el.dom.innerHTML);
			dragEl.addClass(el.dom.className + ' dd-proxy');
		},
	
		// disable the default behaviour which would place the dragged element
		// we don't need to place it as it will be moved in onDragDrop
		endDrag: function() {
			if (this.config.list.highlighter)
				this.config.list.highlighter.isDragging = false;
		},
	
		onDragOver: function(ev, id){
			var el = Ext.get(id);
			var oldPosition = this.position;
	
			this.calculatePosition(el.getHeight(), ev.getPageY() - el.getY(), el.dd.config.droptarget);
	
			if (oldPosition != this.position) {
				this.removeDropIndicator(el);
				this.addDropIndicator(el)
			}
		},
	
		onDragOut: function(e, id) {
			this.removeDropIndicator(Ext.get(id));
		},
	
		onDragDrop: function(e, id) {
			SqueezeJS.UI.Highlight.isDragging = false;
			this.removeDropIndicator(Ext.get(id));
			this.config.list.onDrop(Ext.get(this.getEl()), Ext.get(id), this.position);
		},
	
		calculatePosition: function(height, top, droptarget){
			// target can be dropped on - make it selectable
			if (droptarget)
				if (top <= 0.33*height)
					this.position = -1;
				else if (top >= 0.6*height)
					this.position = 1;
				else
					this.position = 0;		
	
			// target can't be dropped on - only drop below/beneath
			else
				if (top <= 0.5*height)
					this.position = -1;
				else
					this.position = 1;		
		},
	
		addDropIndicator: function(el) {
			if (this.position < 0)
				el.addClass('dragUp');
			else if (this.position > 0)
				el.addClass('dragDown');
			else
				el.addClass('dragOver');
		},
	
		removeDropIndicator: function(el) {
			if (!el)
				return;
	
			el.removeClass('dragUp');
			el.removeClass('dragDown');
			el.removeClass('dragOver');
		}
	});

}


if (SqueezeJS.UI.SplitButton && Ext.MessageBox && Ext.Window) {
	
	SqueezeJS.UI.Buttons.PlayerDropdown = Ext.extend(SqueezeJS.UI.SplitButton, {
		playerList : null,
	
		initComponent : function(){
			Ext.apply(this, {
				menu: new Ext.menu.Menu(),
				arrowTooltip: SqueezeJS.string('choose_player')
			})
			SqueezeJS.UI.Buttons.PlayerDropdown.superclass.initComponent.call(this);
	
			SqueezeJS.Controller.on({
				serverstatus: {
					fn: this.onPlayerlistUpdate,
					scope: this
				},
	
				playerselected: {
					fn: function(playerobj) {
						if (playerobj && playerobj.name)
							this.setText(playerobj.name)
					},
					scope: this
				}
			});
		},
	
		onPlayerlistUpdate : function(response){
			this.menu.removeAll();
			this.menu.add(
				'<span class="menu-title">' + SqueezeJS.string('choose_player') + '</span>'
			);
	
			// let's set the current player to the first player in the list
			if (response['player count'] > 0 || response['sn player count'] > 0 || response['other player count'] > 0) {
				var el;
	
				this.playerList = new Ext.util.MixedCollection();
	
				this._addPlayerlistMenu(response);
				this._addSNPlayerlistMenu(response);
				this._addOtherPlayerlistMenu(response);
	
				if (!this.noSync) {
					// add the sync option menu item
					this.menu.add(
						'-',
						new Ext.menu.Item({
							text: SqueezeJS.string('synchronize') + '...',
							// query the currently synced players and show the dialog
							handler: function(){
								SqueezeJS.Controller.request({
									params: ['', ['syncgroups', '?']],
									success: this.showSyncDialog,
									failure: this.showSyncDialog,
									scope: this
								});	
							},
							scope: this,
							disabled: (this.playerList.getCount() < 2) 
						})
					);
				}
			}
	
			else {
				this.menu.add(
					new Ext.menu.Item({
						text: SqueezeJS.string('no_player') + '..',
						handler: function(){
							var dlg = new Ext.BasicDialog('', {
								autoCreate: true,
								title: SqueezeJS.string('no_player'),
								modal: true,
								closable: false,
								collapsible: false,
								width: 500,
								height: 250,
								resizeHandles: 'se'
							});
							dlg.addButton(SqueezeJS.string('close'), dlg.destroy, dlg);
							dlg.addKeyListener(27, dlg.destroy, dlg);
							dlg.body.update(SqueezeJS.string('no_player_details'));
							dlg.show();
						}
					})
				);
			}
	
		},
	
		_addPlayerlistMenu : function(response){
			if (response.players_loop) {
				response.players_loop = response.players_loop.sort(this._sortPlayer);
	
				for (var x=0; x < response.players_loop.length; x++) {
					var playerInfo = response.players_loop[x];
					
					if (!playerInfo.connected)
						continue;
	
					// mark the current player as selected
					if (playerInfo.playerid == SqueezeJS.Controller.getPlayer()) {
						this.setText(playerInfo.name);
					}
	
					// add the players to the list to be displayed in the synch dialog
					this.playerList.add(playerInfo.playerid, {
						name: playerInfo.name,
						isplayer: playerInfo.isplayer
					});
	
					var tpl = new Ext.Template( '<div>{title}<span class="browsedbControls"><img src="' + webroot + 'html/images/{powerImg}.gif" id="{powerId}">&nbsp;<img src="' + webroot + 'html/images/{playPauseImg}.gif" id="{playPauseId}"></span></div>')
					
					this.menu.add(
						new Ext.menu.CheckItem({
							text: tpl.apply({
								title: playerInfo.name,
								playPauseImg: playerInfo.isplaying ? 'b_pause' : 'b_play',
								playPauseId: playerInfo.playerid + ' ' + (playerInfo.isplaying ? 'pause' : 'play'),
								powerImg: playerInfo.power ? 'b_poweron' : 'b_poweroff',
								powerId: playerInfo.playerid + ' power ' + (playerInfo.power ? '0' : '1')
							}),
							value: playerInfo.playerid,
							cls: playerInfo.model,
							group: 'playerList',
							checked: playerInfo.playerid == playerid,
							hideOnClick: false,
							listeners: {
								click: function(self, ev) {
									var target = ev ? ev.getTarget() : null;
									
									// check whether user clicked one of the playlist controls
									if ( target && Ext.id(target).match(/^([a-f0-9:]+ (?:power|play|pause)\b.*)/i) ) {
										var cmd = RegExp.$1.split(' ');
										
										Ext.Ajax.request({
											url: SqueezeJS.Controller.getBaseUrl() + '/jsonrpc.js',
											method: 'POST',
											params: Ext.util.JSON.encode({
												id: 1,
												method: "slim.request",
												params: [cmd.shift(), cmd]
											}),
											callback: function() {
												SqueezeJS.Controller.updateAll();
											}
										});
										return false;
									}
								}
							},
							scope: this,
							handler: this._selectPlayer
						})
					);
				}
			}
		},
	
		_addSNPlayerlistMenu : function(response){
			// add a list of players connected to SQN, if available
			if (response.sn_players_loop) {
				var first = true;
				response.sn_players_loop = response.sn_players_loop.sort(this._sortPlayer);
								
				for (var x=0; x < response.sn_players_loop.length; x++) {
					var playerInfo = response.sn_players_loop[x];
	
					// don't display players which are already connected to SC
					// this is to prevent double entries right after a player has switched
					if (! this.playerList.get(playerInfo.playerid)) {
						if (first) {
							this.menu.add(
								'-',
								new Ext.menu.Item({
									text: SqueezeJS.string('squeezenetwork'),
									cls: 'menu-title',
									scope: this,
									handler: function(ev){
										location = 'http://www.mysqueezebox.com/';
									}
								})
							);
							first = false;
						}
	
						this.menu.add(
							new Ext.menu.Item({
								text: playerInfo.name,
								playerid: playerInfo.playerid,
								server: 'www.mysqueezebox.com',
								cls: playerInfo.model,
								scope: this,
								dlgTitle: SqueezeJS.string('squeezenetwork'),
								dlgServer: SqueezeJS.string('squeezenetwork'),
								handler: this._confirmSwitchPlayer
							})
						);
					}
				}
			}
		},
	
		_addOtherPlayerlistMenu : function(response){
			// add a list of players connected to other servers, if available
			if (response.other_players_loop) {
				var playersByServer = this._groupPlayersByServer(response.other_players_loop);
	
				playersByServer._servers.each(function(item){
					var first = true;
					var players = playersByServer[item].players.sort(this._sortPlayer);
	
					for (var x = 0; x < players.length; x++) {
						var playerInfo = players[x];
						
						// don't display players which are already connected to SC
						// this is to prevent double entries right after a player has switched
						if (playerInfo && !this.playerList.get(playerInfo.playerid)) {
							if (first) {
								this.menu.add(
									'-',
									new Ext.menu.Item({
										text: item,
										url: playerInfo.serverurl,
										cls: 'menu-title',
										scope: this,
										handler: function(ev){
											location = ev.url;
										}
									})
								);
								first = false;
							}
		
							this.menu.add(
								new Ext.menu.Item({
									text: playerInfo.name,
									playerid: playerInfo.playerid,
									server: playerInfo.server,
									cls: playerInfo.model,
									scope: this,
									dlgTitle: SqueezeJS.string('squeezebox_server'),
									dlgServer: playerInfo.server,
									handler: this._confirmSwitchPlayer
								})
							);
						}
					}
					
					return 1;
				}, this);
	
			}
		},
	
		_sortPlayer : function(a, b){
			a = a.name.toLowerCase();
			b = b.name.toLowerCase();
			return a > b ? 1 : (a < b ? -1 : 0);
		},
	
		_groupPlayersByServer : function(players) {
			var playersByServer = {};
			playersByServer._servers = new Ext.util.MixedCollection();
	
			// group players by server
			for (var x=0; x < players.length; x++) {
				// some players can't be switched, as they don't know the SERV command
				if (players[x].model.match(/http|slimp3|softsqueeze|squeezeslave|squeezebox$/i))
					continue;
				
				var server = players[x].server;
	
				if (playersByServer[server] == null) {
					playersByServer[server] = {
						players: new Array(),
						url: players[x].serverurl
					}
	
					playersByServer._servers.add(server, server);
				}
	
				playersByServer[server].players.push(players[x]);
			}
	
			playersByServer._servers.sort('ASC');
	
			return playersByServer;
		},
	
		_selectPlayer: function(item, ev){
			if (item) {
				this.setText(item.text || '');
				SqueezeJS.Controller.selectPlayer(item.value);

				// local players have hideOnClick disabled - but we want them to hide anyway
				if (!item.hideOnClick) {
					var pm = item.parentMenu;
					if (pm.floating) {
						this.clickHideDelayTimer = pm.hide.defer(item.clickHideDelay, pm, [true]);
					} else {
						pm.deactivateActive();
					}
				}
			}
			else
				this.setText('');		
		},
	
		_confirmSwitchPlayer: function(ev){
			var msg = SqueezeJS.string('sc_want_switch');
			msg.replace(/%s/, ev.dlgServer);
	
			Ext.MessageBox.confirm(
				ev.dlgTitle,
				SqueezeJS.string('sc_want_switch').replace(/%s/, ev.dlgServer),
				function(btn){
					if (btn == 'yes') {
						this._switchPlayer(ev);
					}
				},
				this
			);
		},
	
		_switchPlayer: function(ev){
			SqueezeJS.Controller.request({ params: ['', ['disconnect', ev.playerid, ev.server ]] });
				
			// switch player in a few seconds, to give the player time to connect
			var update = new Ext.util.DelayedTask(function(ev){
				SqueezeJS.Controller.updateAll();
				this._selectPlayer({ value: ev.playerid });
			}, this, new Array(ev));
			update.delay(3000); 
		},
	
		showSyncDialog: function(response){
			var responseText = Ext.util.JSON.decode(response.responseText);
	
			var syncedPlayers = new Array();
			if (responseText.result && responseText.result.syncgroups_loop) {
				syncedPlayers = responseText.result.syncgroups_loop;
			}
	
			// make sure any previous syncgroup form is deleted; seems not to happen in on dlg.destroy() in some browsers
			var playerSelection = Ext.get('syncgroup');
			if (playerSelection)
				playerSelection.remove();
	
			playerSelection = '<p style="margin-right:25px">' + SqueezeJS.string('setup_synchronize_desc') + '</p>';
			playerSelection += '<form name="syncgroup" id="syncgroup">';
			var tpl = new Ext.Template('<input type="radio" id="{id}" value="{id}" {checked} {disabled} name="synctarget">&nbsp;<label for="{id}">{name}</label><br>');
			tpl.compile();
	
			var syncedPlayersList = '';
			
			// add sync groups first in the menu
			for (var i = 0; i < syncedPlayers.length; i++) {
				
				var sync_group = syncedPlayers[i].sync_members;
	
				if (sync_group) {
					var members = sync_group.split(',');
					syncedPlayersList += sync_group;
	
					playerSelection += tpl.apply({
						name: syncedPlayers[i].sync_member_names.replace(/,/g, ",&nbsp;") || sync_group,
						id: members[0],
						checked: sync_group.indexOf(playerid) > -1 ? 'checked="checked"' : '',
						disabled: ''
					});
				}
			}
	
			
			// create checkboxes for other players and preselect if synced
			this.playerList.eachKey(function(id, data){
	
				if (id && data.name && id != playerid && syncedPlayersList.indexOf(id) == -1) {
					
					// unsynced player
					playerSelection += tpl.apply({
						name: data.name,
						id: id,
						checked: '',
						disabled: data.isplayer ? '' : 'disabled'
					});
				}
	
			});
	
			// "Don't sync" item
			playerSelection += tpl.apply({
				name: SqueezeJS.string('setup_no_synchronization'),
				id: '-',
				checked: syncedPlayers.length == 0 || syncedPlayers[0] == '-' ? 'checked="checked"' : '',
				disabled: ''
			});
	
			playerSelection += '</form>';
	
			var dlg = new Ext.Window({
				title: SqueezeJS.string('synchronize'),
				modal: true,
				collapsible: false,
				width: 400,
				height: 250 + this.playerList.getCount() * 13,
				autoScroll: true,
				resizeHandles: 'se',
				html: playerSelection
			});
	
			dlg.addButton(SqueezeJS.string('synchronize'), function() {
				var targets = document.forms.syncgroup.synctarget;
				
				for (var i = 0; i < targets.length; i++) {
	
					if (targets[i].checked) {
						if (targets[i].value == '-')
							SqueezeJS.Controller.playerRequest({ params: [ 'sync', '-' ]});
						else
							SqueezeJS.Controller.request({ params: [ targets[i].value, [ 'sync', playerid ] ] });
						break;
					}
				}
	
				dlg.destroy();
			}, dlg);
	
			dlg.addButton(SqueezeJS.string('cancel'), dlg.destroy, dlg);
	
			dlg.show();
		}
	});

}



SqueezeJS.UI.VolumeBar = Ext.extend(SqueezeJS.UI.Component, {
	power: null,
	volume : 0,

	initComponent : function(){
		SqueezeJS.UI.VolumeBar.superclass.initComponent.call(this);

		SqueezeJS.Controller.on({
			'buttonupdate': {
				fn: this.onPlayerStateChange,
				scope: this
			}
		});

		this.marginLeft = this.initialConfig.marginLeft || 0;
		this.marginLeft = this.initialConfig.marginRight || 0;

		if (this.el && (this.el = Ext.get(this.el))) {
			var el;
			if (el = this.el.child('img:first'))
				el.on('click', this.onClick, this);
		}		
	},

	onClick: function(ev, target) {
		if (!this.power)
			return;

		var el = Ext.get(target);
		if (el) {
			var minX = el.getX() + this.marginLeft + 1;
			var maxX = el.getX() + el.getWidth() - this.marginRight + 1;

			// clicking outside the valid range
			if (ev.xy[0] <= minX || ev.xy[0] >= maxX)
				return;

			if (!this.maxWidth)
				this.maxWidth = maxX - minX;

			if (!this.myStep)
				this.myStep = this.maxWidth/11;

			var myX = ev.xy[0] - minX;

			myX = Math.max(myX, 1);
			myX = Math.min(myX, this.maxWidth);

			myX = Math.ceil(myX / this.myStep) - 1;
			this.updateState(myX*10);
			SqueezeJS.Controller.setVolume(myX);
		}
	},

	// update volume bar
	onPlayerStateChange: function(result){
		if (result['mixer volume'] != null)
			this.updateState(parseInt(result['mixer volume']));

		this.power = result.power;
	},

	updateState: function(newVolume){
		if (newVolume != this.volume) {
			var volEl;
			var volVal = Math.ceil(newVolume / 9.9); 

			if (newVolume <= 0)
				volVal = 0;
			else if (newVolume >= 100)
				volVal = 11;

			this.el.removeClass([ 'ctrlVolume0', 'ctrlVolume1', 'ctrlVolume2', 'ctrlVolume3', 'ctrlVolume4', 'ctrlVolume5', 'ctrlVolume6', 'ctrlVolume7', 'ctrlVolume8', 'ctrlVolume9', 'ctrlVolume10' ]);
			this.el.addClass('ctrlVolume' + String(Math.max(volVal-1, 0)));
	
			if (volEl = this.el.child('img:first'))
				volEl.dom.title = SqueezeJS.string('volume') + ' ' + parseInt(newVolume);

			this.volume = newVolume;
		}
	}
});


SqueezeJS.UI.Title = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		this.el.update(SqueezeJS.SonginfoParser.title(result, this.noLink));
	}
});

// title without disc/track numbers
SqueezeJS.UI.RawTitle = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		this.el.update(SqueezeJS.SonginfoParser.title(result, this.noLink, true));
	}
});

SqueezeJS.UI.TrackNo = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		this.el.update(result.playlist_loop[0].tracknum ? result.playlist_loop[0].tracknum + '. ' : '');
	}
});

SqueezeJS.UI.CompoundTitle = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		var title = SqueezeJS.SonginfoParser.title(result, this.noLink);
		var contributors = SqueezeJS.SonginfoParser.contributors(result, this.noLink);
		var album = SqueezeJS.SonginfoParser.album(result, this.noLink, true);

		this.el.update(title
			+ (contributors ? '&nbsp;' + SqueezeJS.string('by') + '&nbsp;' + contributors : '')
			+ (album ? '&nbsp;' + SqueezeJS.string('from') + '&nbsp;' + album : '')
		);
	}
});

SqueezeJS.UI.Album = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		var year = SqueezeJS.SonginfoParser.year(result, this.noLink);
		this.el.update(SqueezeJS.SonginfoParser.album(result, this.noLink)
			+ (year ? '&nbsp;(' + year + ')' : ''));
	}
});

SqueezeJS.UI.AlbumTitle = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		this.el.update(SqueezeJS.SonginfoParser.album(result, this.noLink));
	}
});

SqueezeJS.UI.AlbumYear = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		this.el.update(SqueezeJS.SonginfoParser.year(result, this.noLink));
	}
});

SqueezeJS.UI.Contributors = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		this.el.update(SqueezeJS.SonginfoParser.contributors(result, this.noLink));
	}
});


SqueezeJS.UI.CurrentIndex = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		this.el.update(result.playlist_cur_index == null ? '0' : (parseInt(result.playlist_cur_index) + 1));
	}
});

SqueezeJS.UI.SongCount = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		this.el.update(parseInt(result.playlist_tracks) || '0');
	}
});

SqueezeJS.UI.Bitrate = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		this.el.update(SqueezeJS.SonginfoParser.bitrate(result, this.noLink));
	}
});

SqueezeJS.UI.Playtime = Ext.extend(SqueezeJS.UI.Component, {
	initComponent : function(config){
		if (typeof config == 'string')
			config = { el: config };

		Ext.apply(this, config);
		SqueezeJS.UI.Playtime.superclass.initComponent.call(this);
	
		SqueezeJS.Controller.on({
			playtimeupdate: {
				fn: this.onPlaytimeUpdate,
				scope: this
			}
		});
	},

	onPlaytimeUpdate : function(playtime){
		if (this.el && playtime)
			this.el.update(SqueezeJS.Utils.formatTime(playtime.current));
	}
});

SqueezeJS.UI.PlaytimeRemaining = Ext.extend(SqueezeJS.UI.Playtime, {
	onPlaytimeUpdate : function(playtime){
		if (this.el && playtime)
			this.el.update(SqueezeJS.Utils.formatTime(playtime.remaining));
	}
});

SqueezeJS.UI.Duration = Ext.extend(SqueezeJS.UI.Playtime, {
	onPlaytimeUpdate : function(playtime){
		if (this.el && playtime)
			this.el.update(SqueezeJS.Utils.formatTime(playtime.duration));
	}
});

SqueezeJS.UI.CompoundPlaytime = Ext.extend(SqueezeJS.UI.Playtime, {
	onPlaytimeUpdate : function(playtime){
		if (this.el && playtime)
			this.el.update(SqueezeJS.Utils.formatTime(playtime.current) + '&nbsp;/&nbsp;' + SqueezeJS.Utils.formatTime(playtime.remaining));
	}
});

SqueezeJS.UI.PlaytimeProgress = Ext.extend(SqueezeJS.UI.Playtime, {
	initComponent : function(config){
		SqueezeJS.UI.PlaytimeProgress.superclass.initComponent.call(this);

		var el = Ext.get(this.applyTo);
		el.update( '<img src="/html/images/spacer.gif" class="progressLeft"/><img src="/html/images/spacer.gif" class="progressFillLeft"/>'
			+ '<img src="/html/images/spacer.gif" class="progressIndicator"/><img src="/html/images/spacer.gif" class="progressFillRight"/>'
			+ '<img src="/html/images/spacer.gif" class="progressRight"/>' );	

		// store the DOM elements to reduce flicker
		this.remaining = Ext.get(Ext.DomQuery.selectNode('.progressFillRight', el.dom));
		this.playtime = Ext.get(Ext.DomQuery.selectNode('.progressFillLeft', el.dom));
		
		// calculate width of elements which won't be scaled
		this.fixedWidth = el.child('img.progressLeft').getWidth();
		this.fixedWidth += el.child('img.progressRight').getWidth();
		this.fixedWidth += el.child('img.progressIndicator').getWidth();

		Ext.get(this.applyTo).on('click', this.onClick);

		if (Ext.ToolTip) {
			this.tooltip = new Ext.ToolTip({
				target: 'ctrlProgress',
				anchor: 'bottom',
				dismissDelay: 30000,
				hideDelay: 0,
				showDelay: 0,
				trackMouse: true,
				listeners: {
					'move': {
						fn: function(tooltip, x, y) {
							// don't know why we need the additional 10px offset...
							var pos = Math.max(x - this.el.getX() + this.fixedWidth + this.offset + 10, 0);
							pos = pos / Math.max(this.el.getWidth(), pos);

							tooltip.update(SqueezeJS.Utils.formatTime(pos * SqueezeJS.Controller.playerStatus.duration));
						},
						scope: this
					}
				}
			});
		}
	},

	onPlaytimeUpdate : function(playtime){
		if (this.el && playtime) {
			var left;
			var max = this.el.getWidth() - this.fixedWidth;

			if (isNaN(this.offset))
				this.offset = max > 0 ? 1 : 11;

			if (max == 0)
				return;
			
			max -= this.offset; // total of left/right/indicator width

			// if we don't know the total play time, just put the indicator in the middle
			if (!playtime.duration) {
				left = 0;
				if (this.tooltip)
					this.tooltip.disable();
			}
			// calculate left/right percentage
			else {
				left = Math.max(
						Math.min(
							Math.floor(playtime.current / playtime.duration * max)
						, max)
					, 1);

				if (this.tooltip)
					this.tooltip.enable();
			}

			this.remaining.setWidth(max - left);
			this.playtime.setWidth(left);
		}
	},

	onClick : function(ev) {
		if (! (SqueezeJS.Controller.playerStatus.duration && SqueezeJS.Controller.playerStatus.canSeek))
			return;
 
		var pos = Math.max(ev.xy[0] - this.getX(), 0);
		pos = pos / Math.max(this.getWidth(), pos);
		
		SqueezeJS.Controller.playerControl(['time', pos * SqueezeJS.Controller.playerStatus.duration]);
	}
});

SqueezeJS.UI.Coverart = Ext.extend(SqueezeJS.UI.Component, {
	onPlayerStateChange : function(result){
		this.el.update(SqueezeJS.SonginfoParser.coverart(result, this.noLink, this.size));
	}
});



if (Ext.ToolTip) {

	SqueezeJS.UI.CoverartPopup = Ext.extend(Ext.ToolTip, {
		initComponent : function(){
			if (this.songInfo)
				this.title = '&nbsp;';
	 
			this.dismissDelay = 0;
			this.hideDelay = 500;
				
			SqueezeJS.UI.CoverartPopup.superclass.initComponent.call(this);
	
			// let's try to size the width at a maximum of 80% of the current screen size or 500 (as the background image is only 500)
			this.maxWidth = Math.min(Ext.lib.Dom.getViewWidth(), Ext.lib.Dom.getViewHeight()) * 0.8;
			this.maxWidth = Math.min(this.maxWidth, 500);
	
			SqueezeJS.Controller.on({
				playerstatechange: {
					fn: this.onPlayerStateChange,
					scope: this
				}
			});
	
			this.on({
				show: {
					fn: function(el){
						if (el && el.body 
							&& (el = el.body.child('img:first', true)) 
							&& (el = Ext.get(el))
							&& (el.getWidth() > this.maxWidth))
								el.setWidth(this.maxWidth - 10);
					}
				}
			});
	
			Ext.EventManager.onWindowResize(function(){
				this.maxWidth = Math.min(Ext.lib.Dom.getViewWidth(), Ext.lib.Dom.getViewHeight()) * 0.8;
				this.maxWidth = Math.min(this.maxWidth, 500);
			}, this);
		},
	
		onPlayerStateChange : function(result){
			if (this.songInfo) {
				var title = SqueezeJS.SonginfoParser.title(result, true);
				var contributors = SqueezeJS.SonginfoParser.contributors(result, true);
				var album = SqueezeJS.SonginfoParser.album(result, true, true);
		
				this.setTitle(title
					+ (contributors ? '&nbsp;/ ' + contributors : '')
					+ (album ? '&nbsp;/ ' + album : ''));
			}
	
			var el = this.body;
			if (el) {
				if (el = el.child('img:first', true))
					el.src = SqueezeJS.SonginfoParser.coverartUrl(result);
			}
			else {
				this.html = SqueezeJS.SonginfoParser.coverart(result, true);
			}
		}
	});

}



SqueezeJS.UI.Playlist = Ext.extend(SqueezeJS.UI.Component, {
	_resizeTask: null,
	
	initComponent : function(){
		SqueezeJS.UI.Playlist.superclass.initComponent.call(this);

		this.container = Ext.get(this.renderTo);
		this.onResize();
		
		this._resizeTask = new Ext.util.DelayedTask(function(){ this.onResize(); }, this);

		Ext.EventManager.onWindowResize(function(){
			this._resizeTask.delay(100);
		}, this);
		
		SqueezeJS.Controller.on({
			playerselected: {
				fn: this.onPlayerSelected,
				scope: this
			}
		});
	},

	load : function(url, showIndicator){
		if (this.getPlEl() && SqueezeJS.UI.Sortable)
			// unregister event handlers
			Ext.dd.ScrollManager.unregister(this.playlistEl);

		// try to reload previous page if no URL is defined
		var um = this.container.getUpdateManager();

		if (showIndicator)
			this.container.getUpdateManager().showLoadIndicator = true;

		this.container.load(
			{ url: (url || this.url || webroot + 'playlist.html?ajaxRequest=1&player=' + SqueezeJS.getPlayer()) + '&uid=' + Date.parse(Date()) },
			{},
			this._onUpdated.createDelegate(this),
			true
		);

		um.showLoadIndicator = false;
	},

	getPlEl : function(){
		return Ext.get(this.playlistEl);
	},

	onUpdated : function(){},
	
	_onUpdated : function(o){
		this.onResize();

		var el = this.getPlEl();
		if (el && (el = el.child('div.noPlayerPanel')))
			el.setDisplayed(true);			

		// shortcut if there's no player
		if (!this.getPlEl())
			return;

		this.Highlighter.unHighlight();
		this._initSortable();
		this.highlightCurrent();

		this.onUpdated(o);
	},

	_initSortable : function(){
		if (!SqueezeJS.UI.Sortable)
			return;
		
		var offset = 0;
		if (offset = Ext.get('offset'))
			offset = parseInt(offset.dom.innerHTML);

		new SqueezeJS.UI.Sortable({
			el: this.playlistEl,
			offset: offset,
			selector: '#' + this.playlistEl + ' div.draggableSong',
			highlighter: this.Highlighter,
			onDropCmd: function(sourcePos, targetPos) {
				SqueezeJS.Controller.playerControl(
					[
						'playlist',
						'move',
						sourcePos, targetPos
					],
				true);
			}
		});
	},

	onPlaylistChange : function() {
		this.load();
	},

	onPlayerSelected : function() {
		this.load();
	},

	onResize : function(){
		var el = this.container.parent().parent();
		var plEl = this.getPlEl();
		
		if (el == null || plEl == null)
			return;
		
		var height = el.getHeight() + el.getTop() - plEl.getTop();
		if (el = Ext.get('playlistTab'))
			height -= el.getHeight();

		plEl.setHeight(height);
	},

	highlightCurrent : function(){
		var el;
		if (el = this.getPlEl()) {
			var plPos = el.getScroll();
			var plView = el.getViewSize();
			var el = Ext.DomQuery.selectNode(this.currentSelector);

			if (el) {
				el = Ext.get(el);
				if (el.getTop() > plPos.top + plView.height
					|| el.getBottom() < plPos.top)
						this.scrollIntoView(el);
			}
		}
	},

	// overwriting Element.scrollIntoView
	// to have the element centered, not at the top/bottom border
	scrollIntoView : function(el) {
		var c = Ext.getDom(this.playlistEl);
		var elDom = el.dom;
		
		var o = el.getOffsetsTo(c),
		    t = o[1] + c.scrollTop,
		    b = t + elDom.offsetHeight;

		c.scrollTop = b - c.clientHeight + this.container.dom.scrollHeight / 2;;
		c.scrollTop = c.scrollTop; // corrects IE, other browsers will ignore
	},
			
	request : function(cmd, el) {
		// don't accept new commands while the playlist is updating
		var um = this.getPlEl().getUpdateManager();

		if (um && um.isUpdating())
			return;

		el = Ext.get(el);
		if (el.dd && el.dd.config && parseInt(el.dd.config.position) >= 0)
			SqueezeJS.Controller.playerControl(['playlist', cmd, el.dd.config.position])
	}
});


if (Ext.slider && Ext.slider.SingleSlider) {
	
	SqueezeJS.UI.SliderInput = Ext.extend(Ext.slider.SingleSlider, {
		tpl: new Ext.Template('<span></span>'),
	
		initComponent : function(){
			this.input = Ext.get(this.initialConfig.input);
	
			this.renderTo = this.tpl.insertBefore(this.input, {}, true);
			
			// if no initial value has been configured,
			// try reading it from our input field
			if (this.initialConfig.value == null) {
				this.values = [ isNaN(parseInt(this.input.dom.value)) ? this.minValue : parseInt(this.input.dom.value) ];
			}
			else {
				this.values = [ parseInt(this.initialConfig.value) ]
			}
			
			SqueezeJS.UI.SliderInput.superclass.initComponent.call(this);
			
			this.on({
				dragstart: {
					fn: this.onSlide
				},
				drag: {
					fn: this.onSlide
				},
				change: {
					fn: this.onSlide
				},
				dragend: {
					fn: function(){
						// trigger validation for settings
						this.input.focus();
						this.input.blur();
					}
				}
			});
			
			this.input.on({
				change: {
					fn: this._onChange,
					scope: this
				},
				keyup: {
					fn: this._onChange,
					scope: this
				}
			});
		},
		
		inputChangeDelay: new Ext.util.DelayedTask(),
	
		_onChange: function(ev, input) {
			this.inputChangeDelay.delay(500, function(input){
				// sanity check input values, don't accept non-numerical values
				if (input.value != '' && input.value != '-' && isNaN(parseInt(input.value)))
					input.value = input.defaultValue;
				else if (input.value != '' && input.value != '-')
					input.value = parseInt(input.value);
		
				this.setInputValue(input.value);
		
			}, this, [input]);
		},
	
		setInputValue: function(v){
			v = parseInt(v);
			if (isNaN(v))
				v = 0;
				
			this.setValue(v);
		},
		
		onSlide : function(){
			this.input.dom.value = this.getValue();
		}
	});

}


SqueezeJS.UI.ShowBriefly = Ext.extend(Ext.Component, {
	initComponent : function(){
		SqueezeJS.UI.ShowBriefly.superclass.initComponent.call(this);

		this.template = (this.template ? new Ext.Template(this.template) : new Ext.Template('{msg}'));

		// subscribe to some default events
		SqueezeJS.Controller.on({
			showbriefly: {
				fn: this.onShowBriefly,
				scope: this
			}
		});
	},

	onShowBriefly : function(text){
		if (!this.el)
			this.el = Ext.get(this.initialConfig.renderTo);
		
		if (!this.el)
			return;

		if (text && !this.el.hasActiveFx()) {
			this.template.overwrite(this.el, { msg: text });
			this.animate();
		}
		else if (!text) {
			this.el.update('');
		}
	},

	animate : function() {
		this.el.fadeIn().pause(3).fadeOut();
	}
});


// simple one line scanner information
SqueezeJS.UI.ScannerInfo = Ext.extend(Ext.Component, {
	initComponent : function(config){
		Ext.apply(this, config);
		SqueezeJS.UI.ScannerInfo.superclass.initComponent.call(this);

		// subscribe to some default events
		SqueezeJS.Controller.on({
			scannerupdate: {
				fn: this.onScannerUpdate,
				scope: this
			}
		});
	},

	onScannerUpdate : function(result){
		if (!this.progressEl)
			this.progressEl = Ext.get(this.initialConfig.renderTo);
		
		if (!this.progressEl)
			return;

		if (result.rescan) {
			if (!this.progressEl.isVisible())
				this.showNow();

			var el;
			if ((el = Ext.get(this.info)) && result.progresstotal)
				el.show();
			else if (el)
				el.hide();

			if (el = Ext.get(this.total)) {
				Ext.get(this.name).update(result.progressname);
				Ext.get(this.done).update(result.progressdone || 0);
				el.update(result.progresstotal || 0);
			}
		}
		else if (this.progressEl.isVisible()) {
			this.hideNow();
		}
	},

	showNow : function(){
		this.progressEl.fadeIn();
	},

	hideNow : function(){
		this.progressEl.fadeOut();
	}
});


// page oriented scanner information - not configurable nor inheritable
SqueezeJS.UI.ScannerInfoExtended = function(){
	var progressTimer;

	return {
		init: function(config){
			Ext.apply(this, config);

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
				success: this._updatePage,
				failure: function() {
					progressTimer.delay(5000);
				},
				scope: this
			});
			
		},

		onUpdate : function(){},

		_updatePage: function(result){
			// clean up response to have a correct JSON object
			result = result.responseText;
			result = result.replace(/<[\/]?pre>|\n/g, '');
			result = Ext.decode(result);

			// dummy function which can be overwritten by the calling page
			this.onUpdate(result);

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
					Ext.get('Info'+i).setDisplayed(scans[i].Info ? true : false);

					for (var j=0; j<elems.length; j++) {
						if (value = scans[i][elems[j]])
							Ext.get(elems[j]+i).update(decodeURIComponent(value));

					}
					
					// if we don't really have a progress value (eg. done != total) then let's hide the total value
					if (scans[i]['isActive'] && scans[i]['Done'] && scans[i]['Total'] && parseInt(scans[i]['Done']) >= parseInt(scans[i]['Total'])) {
						Ext.get('XofY' + i).setDisplayed(false);
						Ext.get('Total' + i).setDisplayed(false);
						Ext.get('Bar' + i).setDisplayed(false);
					}
					else {
						Ext.get('XofY' + i).setDisplayed(true);
						Ext.get('Total' + i).setDisplayed(true);
						Ext.get('Bar' + i).setDisplayed(true);
					}
				}
				
				// hide results from previous scans
				for (var i=scans.length; i<=50; i++) {
					Ext.get('progress'+i).setDisplayed(false);
				}
			}

			if (result.message && result['total_time']) {
				Ext.get('message').update(decodeURIComponent(result.message) + '<br>' + SqueezeJS.string('total_time') + '&nbsp;' + result.total_time);
				
				if (Ext.get('abortscanlink'))
					Ext.get('abortscanlink').hide();
			}

			else
				Ext.get('message').update(decodeURIComponent(result.message));

			progressTimer.delay(5000)
		}
	};
}();


// only load the following if Ext.grid is available
if (Ext.grid && Ext.grid.GridView && Ext.grid.GridPanel) {

	// create sortable table from HTML table, basically a copy of the TableGrid sample
	// http://extjs.com/deploy/dev/examples/grid/from-markup.html
	SqueezeJS.UI.SortableTable = function(table, config) {
		config = config || {};
	
		// a few defaults
		Ext.applyIf(config, {
			stripeRows: true,
			enableColumnHide: false,
			enableHdMenu: false,
			disableSelection: true,
			border: false
		});
	
		Ext.apply(this, config);
		var cf = config.fields || [], ch = config.columns || [];
		table = Ext.get(table);
		
		var ct = table.insertSibling();
		
		var fields = [], cols = [];
		var headers = table.query("thead th");
		for (var i = 0, h; h = headers[i]; i++) {
			var text = h.innerHTML;
			var name = 'tcol-'+i;
		
			fields.push(Ext.applyIf(cf[i] || {}, {
				name: name,
				mapping: 'td:nth('+(i+1)+')/@innerHTML'
			}));
		
			cols.push(Ext.applyIf(ch[i] || {}, {
				'header': text,
				'dataIndex': name,
				'width': h.offsetWidth,
				'tooltip': h.title,
				'sortable': Ext.get(h).hasClass('sortable')
			}));
		}
		
		var ds  = new Ext.data.Store({
			reader: new Ext.data.XmlReader({
				record:'tbody tr'
			}, fields)
		});
		
		ds.loadData(table.dom);
		
		var cm = new Ext.grid.ColumnModel(cols);
		
		if (config.width || config.height) {
			ct.setSize(config.width || 'auto', config.height || 'auto');
		} else {
			ct.setWidth(table.getWidth());
		}
		
		if (config.remove !== false) {
			table.remove();
		}
		
		Ext.applyIf(this, {
			'ds': ds,
			'cm': cm,
			autoHeight: true,
			autoWidth: true
		});
		
		SqueezeJS.UI.SortableTable.superclass.constructor.call(this, ct, {});
	};
	Ext.extend(SqueezeJS.UI.SortableTable, Ext.grid.GridPanel);
}

