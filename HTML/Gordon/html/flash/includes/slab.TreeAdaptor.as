// Define namespace.
if (_global.slab == undefined) {
 	_global.slab = new Object();
}


// =============================================================
// 
// =============================================================

/**
 * 
 *
 * 
 */
_global.slab.TreeAdaptor =function()
{
	
	this.iTreeName;
	this.iQueryPage;
	this.iSearchTag;
	
	this.iPendingNode_array;
	this.ioXML;
	
	this.iLoaderID;
	this.iReg_snd;
	
	
	// define callbacks for various trees and node levels
	this.ioNodeFuncs ={};
	this.ioNodeFuncs.browse_album ={};
	this.ioNodeFuncs.browse_album.toggle ={};
	this.ioNodeFuncs.browse_album.toggle.funcs =[this.mLoadNodeTitles];
	this.ioNodeFuncs.browse_album.toggle.context =this;
	this.ioNodeFuncs.browse_album.field ={};
	this.ioNodeFuncs.browse_album.field.funcs =[slab.oList.mAdd_album, slab.oList.mAdd_song];
	this.ioNodeFuncs.browse_album.field.context =slab.oList;
	this.ioNodeFuncs.browse_album.field_double ={};
	this.ioNodeFuncs.browse_album.field_double.funcs =[slab.oList.mReplace_album, slab.oList.mReplace_song];
	this.ioNodeFuncs.browse_album.field_double.context =slab.oList;
	
	this.ioNodeFuncs.browse_artist ={};
	this.ioNodeFuncs.browse_artist.toggle ={};
	this.ioNodeFuncs.browse_artist.toggle.funcs =[this.mLoadNodeAlbums, this.mLoadNodeTitles];
	this.ioNodeFuncs.browse_artist.toggle.context =this;
	this.ioNodeFuncs.browse_artist.field ={};
	this.ioNodeFuncs.browse_artist.field.funcs =[slab.oList.mAdd_artist, slab.oList.mAdd_album, slab.oList.mAdd_song];
	this.ioNodeFuncs.browse_artist.field.context =slab.oList;		
	this.ioNodeFuncs.browse_artist.field_double ={};
	this.ioNodeFuncs.browse_artist.field_double.funcs =[slab.oList.mReplace_artist, slab.oList.mReplace_album, slab.oList.mReplace_song];
	this.ioNodeFuncs.browse_artist.field_double.context =slab.oList;
	
	this.ioNodeFuncs.browse_genre ={};
	this.ioNodeFuncs.browse_genre.toggle ={};
	this.ioNodeFuncs.browse_genre.toggle.funcs =[this.mLoadNodeArtists, this.mLoadNodeAlbums, this.mLoadNodeTitles];
	this.ioNodeFuncs.browse_genre.toggle.context =this;
	this.ioNodeFuncs.browse_genre.field ={};
	this.ioNodeFuncs.browse_genre.field.funcs =[slab.oList.mAdd_genre, slab.oList.mAdd_artist, slab.oList.mAdd_album, slab.oList.mAdd_song];
	this.ioNodeFuncs.browse_genre.field.context =slab.oList;	
	this.ioNodeFuncs.browse_genre.field_double ={};
	this.ioNodeFuncs.browse_genre.field_double.funcs =[slab.oList.mReplace_genre, slab.oList.mReplace_artist,  slab.oList.mReplace_album, slab.oList.mReplace_song];
	this.ioNodeFuncs.browse_genre.field_double.context =slab.oList;
	
	this.ioNodeFuncs.search_album ={};
	this.ioNodeFuncs.search_album.toggle ={};
	this.ioNodeFuncs.search_album.toggle.funcs =[this.mLoadNodeTitles];
	this.ioNodeFuncs.search_album.toggle.context =this;
	this.ioNodeFuncs.search_album.field ={};
	this.ioNodeFuncs.search_album.field.funcs =[slab.oList.mAdd_album, slab.oList.mAdd_song];
	this.ioNodeFuncs.search_album.field.context =slab.oList;
	this.ioNodeFuncs.search_album.field_double ={};
	this.ioNodeFuncs.search_album.field_double.funcs =[slab.oList.mReplace_album, slab.oList.mReplace_song];
	this.ioNodeFuncs.search_album.field_double.context =slab.oList;
	
	this.ioNodeFuncs.search_artist ={};
	this.ioNodeFuncs.search_artist.toggle ={};
	this.ioNodeFuncs.search_artist.toggle.funcs =[this.mLoadNodeAlbums, this.mLoadNodeTitles];
	this.ioNodeFuncs.search_artist.toggle.context =this;
	this.ioNodeFuncs.search_artist.field ={};
	this.ioNodeFuncs.search_artist.field.funcs =[slab.oList.mAdd_artist, slab.oList.mAdd_album, slab.oList.mAdd_song];
	this.ioNodeFuncs.search_artist.field.context =slab.oList;
	this.ioNodeFuncs.search_artist.field_double ={};
	this.ioNodeFuncs.search_artist.field_double.funcs =[slab.oList.mReplace_artist, slab.oList.mReplace_album, slab.oList.mReplace_song];
	this.ioNodeFuncs.search_artist.field_double.context =slab.oList;
	
	this.ioNodeFuncs.search_song ={};
	this.ioNodeFuncs.search_song.field ={};
	this.ioNodeFuncs.search_song.field.funcs =[slab.oList.mAdd_song];
	this.ioNodeFuncs.search_song.field.context =slab.oList;
	this.ioNodeFuncs.search_song.field_double ={};
	this.ioNodeFuncs.search_song.field_double.funcs =[slab.oList.mReplace_song];
	this.ioNodeFuncs.search_song.field_double.context =slab.oList;
	
}

// =============================================================
// =============================================================
slab.TreeAdaptor.prototype.mLoad =function(treeName)
{
	switch (treeName) {
		case("browse_album"):
			this.iSearchTag ="album";
			var q =this.mFormQuery(null,"*",null,"*");
			break;
		case("browse_artist"):
			this.iSearchTag ="artist"; 
			var q =this.mFormQuery(null,null,null,"*");
			break;
		case("browse_genre"): 
			this.iSearchTag ="genre"; 
			var q =this.mFormQuery(null,null,null,null);
	}
	this.iTreeName =treeName;
	this.mSendQuery("browseid3", q, this.mAddTree, this);
}
// =============================================================
slab.TreeAdaptor.prototype.mLoadNodeArtists =function (node_array)
{
	this.iPendingNode_array =node_array;
	this.iSearchTag ="artist";
	var q =this.mFormQuery("","","",node_array[0]);
	this.mSendQuery("browseid3", q, this.mUpdateTree, this);
}
// =============================================================
slab.TreeAdaptor.prototype.mLoadNodeAlbums =function (node_array, parentLabels_array)
{
	this.iPendingNode_array =node_array;
	this.iSearchTag ="album";
	var genre ="*";
	if (parentLabels_array.length) {
		genre =parentLabels_array[0];
	}
	var q =this.mFormQuery("",node_array[0],"",genre);
	this.mSendQuery("browseid3", q, this.mUpdateTree, this);
}
// =============================================================
slab.TreeAdaptor.prototype.mLoadNodeTitles =function (node_array, parentLabels_array)
{
	this.iPendingNode_array =node_array;
	this.iSearchTag ="title";
	var artist ="*";
	var genre ="*";
	switch (parentLabels_array.length) {
		case 1: 
			artist =parentLabels_array[0];
			break;
		case 2:
			artist =parentLabels_array[0];
			genre  =parentLabels_array[1];
	}
	var q =this.mFormQuery("",artist,node_array[0],genre);
	this.mSendQuery("browseid3", q, this.mUpdateTree, this);
}

// =============================================================
// callback when creating a new tree
// =============================================================
slab.TreeAdaptor.prototype.mAddTree =function(err)
{
	// error handling
	if (typeof err == "string") {
		_root.nav_mc.lockMenus(false);
		return;
	}
	
	var path =this.mGetSearchPath();
	var label_array =this.ioXML.mGetNodeText(path +this.iSearchTag);
	
	if (label_array.length==0 && this.iQueryPage=="search") {
		_root.nav_mc.reportNoMatches();
		return;
	}
	
	if (this.iSearchTag=="title") {
		var path_array =this.ioXML.mGetNodeText(path +"song_url");
		var content_array =this.mFormatForTree(label_array, true, path_array);
	} else {
		var content_array =this.mFormatForTree(label_array);
	}
	
	_root.tree_mc.addTree(this.iTreeName, content_array, this.ioNodeFuncs[this.iTreeName]);
	_root.tree_mc.switchTree(this.iTreeName);
	_root.nav_mc.switchListType("tree");
	_root.nav_mc.lockMenus(false);
}

// =============================================================
// callback when adding a node to an existing tree
// =============================================================
slab.TreeAdaptor.prototype.mUpdateTree =function(err)
{
	// error handling
	if (typeof err == "string") {
		return;
	}
	
	var path =this.mGetSearchPath();
	var label_array =this.ioXML.mGetNodeText(path +this.iSearchTag);
	var path_array =this.ioXML.mGetNodeText(path +"song_url");
	
	this.iPendingNode_array[1] =1; //open node
	var isLeaf =(_root.tree_mc.iNodeDepth+1 == _root.tree_mc.iLeafDepth);
	this.iPendingNode_array[2] =this.mFormatForTree(label_array, isLeaf, path_array);
	
	_root.tree_mc.updateThumb();
	_root.tree_mc.update();
	
	_root.tree_mc.setPendingNetData(false);
	this.iPendingNode_array =[];
}

// =============================================================
// =============================================================
slab.TreeAdaptor.prototype.mGetSongInfoCB =function(err)
{
	// error handling
	if (typeof err == "string") {
		return;
	}
}

// =============================================================
// =============================================================
slab.TreeAdaptor.prototype.mSendQuery =function(cmd, lv, cbFunc, cbContext, debug)
{
	this.iQueryPage =cmd;
	var cmd =cmd +".xml";
	var url =slab.k.sliMP3server +"/xml/" +cmd;
	if (typeof this.ioXML == "object") this.ioXML = null;
	this.ioXML =new slab.GetXML(url  +"?" +lv, cbContext);
	if (debug) this.ioXML.mSetDebug(true);
	this.ioXML.mLoad(cbFunc);
}

// =============================================================
// =============================================================
slab.TreeAdaptor.prototype.mFormatForTree =function(label_array, isLeaf, data_array)
{
	var formatted_array =[];
	for (var i=0; i<label_array.length; i++) {
		var temp_array =new Array(4)
		temp_array[0] =label_array[i]; 		//label
		temp_array[1] =0;					//open or closed state of node
		if (isLeaf) {
			temp_array[2] =[];				//empty array indicates leaf node
		} else {
			temp_array[2] =0; 				//indeterminate data: must retrieve from server
		}
		if (typeof data_array=="object") {
			temp_array[3] =data_array[i];	//url
		} else {
			temp_array[3] =null;			//no data associated with this node
		}
		formatted_array.push(temp_array);
	}
	return formatted_array;
}

// =============================================================
// =============================================================
slab.TreeAdaptor.prototype.mFormQuery =function(song, artist, album, genre)
{
	var lv =new LoadVars();
	if (typeof song == "string") {
		lv.song =song;
	}
	if (typeof artist == "string") {
		lv.artist =artist;
	}
	if (typeof album == "string") {
		lv.album =album;
	}
	if (typeof genre == "string") {
		lv.genre =genre;
	}
	
	lv.player =slab.k.playerID;
	//lv.itemsPerPage =slab.k.itemsPerPage;
	
	//
	return lv;
}

// =============================================================
// =============================================================
slab.TreeAdaptor.prototype.mGetSearchPath =function()
{
	switch (this.iQueryPage) {
		case "browseid3":
			var root ="browse:";
			break
		case "search":
			var root ="search:";
			break
	}

	if (this.iSearchTag=="title") {
		var path =root +"browse_entry:";
	} else {
		var path =root +"browse_entry:dir:";
	}
	
	return path;
}

// =============================================================
// =============================================================
slab.TreeAdaptor.prototype.mFormatSongPath =function(info_array)
{
	var path_array =[];
	var query_str ="xml/songinfo.xml?songurl=";
	var queryStrLength =query_str.length;
	
	for (var i=0; i<info_array.length; i++) {
		var url_str =unescape(info_array[i]);
		var url_str =url_str.slice(queryStrLength); 
		path_array.push(url_str);
	}
	
	return path_array;
}

// =============================================================
// =============================================================
slab.TreeAdaptor.prototype.mSetTreeName =function(treeName)
{
	this.iTreeName =treeName;
}
// =============================================================
// =============================================================
slab.TreeAdaptor.prototype.mSetSearchTag =function(tag)
{
	this.iSearchTag =tag;
}

