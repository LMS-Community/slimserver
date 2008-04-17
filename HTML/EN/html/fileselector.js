FileTreeLoader = function(filter) {
	this.filter = filter;
	FileTreeLoader.superclass.constructor.call(this);	
};

Ext.extend(FileTreeLoader, Ext.tree.TreeLoader, {
	dataUrl:'/jsonrpc.js',

	getParams: function(node){
		var cliQuery = [
			'readdirectory',
			0,
			99999
		];

		cliQuery.push("folder:" + node.id);

		if (this.filter) {
			cliQuery.push("filter:" + this.filter);
		}

		return Ext.util.JSON.encode({ 
			id: 1,
			method: "slim.request",
			params: [
				"",
				cliQuery
			]
		});
	},

	createNode : function(attr){
		if(this.applyLoader !== false){
			attr.loader = this;
		}
		if(typeof attr.uiProvider == 'string'){
			attr.uiProvider = this.uiProviders[attr.uiProvider] || eval(attr.uiProvider);
		}
		return ((attr.isfolder > 0) ?
					new Ext.tree.AsyncTreeNode({
						id: attr.path,
						text: attr.name,
						iconCls: 'x-tree-node-alwayscollapsed'
					}) :

					new Ext.tree.TreeNode({
						id: attr.path,
						text: attr.name,
						leaf: true
					}));
	},

	processResponse : function(response, node, callback){
		var json = response.responseText;
		try {
			var o = eval("("+json+")");
	
			// we have to extract the result as IE/Opera can't handle multi-node data roots
			o = eval('o.result');
			len = o.count;
			o = eval('o.fsitems_loop');
	
			for(var i = 0; i < len; i++){
				var n = this.createNode(o[i]);
				if(n){
					node.appendChild(n); 
				}
			}
			if(typeof callback == "function"){
				callback(this, node);
			}
		} catch(e){
			this.handleFailure(response);
		}
	}
});

FileSelector = function(container, config){
	Ext.apply(this, config);
	FileSelector.superclass.constructor.call(this, container);

	this.loader = new FileTreeLoader(this.filter);

	// set the root node
	var root = new Ext.tree.AsyncTreeNode({
		text: 'root',
		id: '/'
	});
	this.setRootNode(root);

	this.on('click', this.onclick);

	// clean up collapsed nodes so we can refresh a view
	this.on('collapse', function(node){
		while(node.firstChild){
			node.removeChild(node.firstChild);
		}
		node.childrenRendered = false;
		node.loaded = false;
		// add dummy node to prevent file icon instead of folder
		node.appendChild([]);
	});


	// render the tree
	this.render();
	this.selectMyPath();	
	// activate button to add path to the selector box
	gotoBtn = Ext.get(this.gotoBtn);
	if (gotoBtn != null) {
		new Ext.Button(gotoBtn, {
			text: '>',
			handler: this.showPath,
			scope: this
		});
	}
};


Ext.extend(FileSelector, Ext.tree.TreePanel, {
	rootVisible: false,
	animate: false,
	pathSeparator: '|',
	containerScroll: true,

	onclick: function(node, e){
		input = Ext.get(this.input);
		if (input != null && input.dom.value != null) {
			input.dom.value = node.id;
		}
	},
	
	selectMyPath: function(){
		// select the current setting, if available
		input = Ext.get(this.input);
		if (input != null && input.dom.value != null && input.dom.value != '') {
			var path = input.dom.value;
			var separator = '/';
			if (path.match(/^[a-z]:\\/i)){
				separator = '\\';
			}
			// only open the first level of UNC paths (\\server\share)
			else if (result = path.match(/^\\\\[\_\w\-]+\\[\-\_\w ]+[^\\]/))
				path = result[0];

			path = path.split(separator);
			var prev = '';
			var target = this.pathSeparator + this.root.id;

			// we don't need the root element on *X systems, but on Windows...
			for (x=(path[0]=='/' ? 1 : 0); x<path.length; x++) {
				if (path[x] == '') continue;

				prev += (x==0 ? '' : separator) + path[x];
				target += this.pathSeparator + prev;
			}

			this.selectPath(target, null, function(success, selNode){
				if (!success) {
					// if that path is a Windows share, try adding it to the tree
					var result = input.dom.value.match(/^\\\\[\_\w\-]+\\[\-\_\w ]+[^\\]/);
					if (result) {
						root = this.getRootNode();
						root.appendChild(new Ext.tree.AsyncTreeNode({
							id: result[0],
							text: result[0],
							iconCls: 'x-tree-node-alwayscollapsed'
						}));
						this.selectMyPath();
					}
				}
			}.createDelegate(this));
		}
	},

	// select path (if available) or try to add it to the tree if it's a network share
	showPath: function(){
		input = Ext.get(this.input);
		if (input != null && input.dom.value != null) {
			Ext.Ajax.request({
				url: '/jsonrpc.js',

				params: Ext.util.JSON.encode({ 
					id: 1,
					method: "slim.request",
					params: [
						"",
						[
							'pref',
							'validate',
							'audiodir',
							input.dom.value
						]
					]
				}),

				scope: this,

				success: function(response, options){
					result = Ext.util.JSON.decode(response.responseText);
					if (result.result.valid == '1') {
						this.selectMyPath();
					}
					else {
						input.highlight('#ff8888');
					}
				}
			});
		}
	}
});


var FilesystemBrowser = function(){
	var filesystemDlg, filesystemBrowser;

	return {
		init: function(){
			var inputEl, btnEl, filter, classes, start;

			var tpl;
			if (SqueezeJS && SqueezeJS.strings && SqueezeJS.strings('browse'))
				tpl = new Ext.Template('&nbsp;<input type="button" value="' + SqueezeJS.strings('browse') + '" onclick="FilesystemBrowser.show(\'{inputField}\', \'{filter}\')">');
			else
				tpl = new Ext.Template('<img src="/html/images/spacer.gif" class="filesystemBrowseBtn" onclick="FilesystemBrowser.show(\'{inputField}\', \'{filter}\')">');

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
								filter = "filetype:" + classes[x].replace(/selectFile_/, '');
								break;
							}
						}
					}

					btnEl = tpl.insertAfter(inputEl, {
						inputField: inputEl.id,
						filter: filter
					});
				}
			}
		},

		show: function(inputField, filter){
			if (filesystemDlg == null) {
				filesystemDlg = new Ext.BasicDialog('', {
					autoCreate: true,
					modal: true,
					closable: false,
					collapsible: false,
					width: 350,
					height: 400,
					resizeHandles: 'se'
				});

				filesystemDlg.addButton(SqueezeJS.strings('close'), filesystemDlg.hide, filesystemDlg);
				filesystemDlg.addKeyListener(27, filesystemDlg.hide, filesystemDlg);
				filesystemDlg.body.setStyle('background', 'white');
			}

			filesystemDlg.body.update('<div id="filesystembrowser"></div>');

			filesystemBrowser = new FileSelector('filesystembrowser', {
				input: inputField,
				filter: filter
			});

			filesystemDlg.setTitle(SqueezeJS.strings(filter == 'foldersonly' ? 'choose_folder' : 'choose_file'));
			filesystemDlg.show();
		}
	}
}();
