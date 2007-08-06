FileTreeLoader = function(filter) {
	this.filter = filter;
	FileTreeLoader.superclass.constructor.call(this);	
};

Ext.extend(FileTreeLoader, Ext.tree.TreeLoader, {
	dataUrl:'/jsonrpc.js',

	getParams: function(node){
		var cliQuery = [
			'filesystem',
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
		text: 'root'
	});
	this.setRootNode(root);

	this.on('click', this.onclick);
	
	// render the tree
	this.render();

	// select the current setting, if available
	input = Ext.get(this.input);
	if (input != null && input.dom.value != null) {
		path = input.dom.value.split('/');
		prev = '';
		target = '|' + root.id;
		for (x=1; x<path.length; x++) {
			prev += '/' + path[x];
			target += '|' + prev;
		}
		this.selectPath(target);
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
		else alert(this.input);
	}
});


