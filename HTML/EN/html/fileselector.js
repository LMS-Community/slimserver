var tree;

FileTree = function(){
	return {
		init: function() {
			tree = new Ext.tree.TreePanel('fileselector', {
				rootVisible:false,
				animate: false,
				pathSeparator: '|',
		
				loader: new Ext.tree.TreeLoader({
					dataUrl:'/jsonrpc.js',
		
					getParams: function(node){
						var cliQuery = [
							'filesystem',
							0,
							99999
						];
		
						cliQuery.push("folder:" + node.id);
				
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
				}),
				containerScroll: true
			});
			
			// set the root node
			var root = new Ext.tree.AsyncTreeNode({
				text: 'root'
			});
			tree.setRootNode(root);
			
			// render the tree
			tree.render();
			root.expand();
			tree.selectPath('|' + tree.root.id + audiodir_tree);
		}
	};
}();