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
_global.slab.ListAdaptor =function()
{
	this.ioXML;
	this.iInfoCallbackFunc;
	this.iInfoCallbackContext;
	
	this.iPLtitle_array;
	this.iPLalbum_array;
	this.iPLartist_array;
	this.iPLsongCnt;
	
	this.ioCurSong;
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mGetPlaylist =function()
{
	var q =this.mFormQuery();
	this.mSendQuery("status", q, this.mUpdate, this);
	
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mJump =function(idx)
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("playlist", "jump", idx);
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mPlayNext =function()
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("playlist", "jump", "+1");
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mPlay = function()
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("play");
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mStop = function()
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("stop");
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mPause = function()
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("pause");
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mAdd_song =function(node_array)
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("playlist", "add", node_array[3]);
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mReplace_song =function(node_array)
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("playlist", "play", node_array[3]);
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mAdd_album =function(node_array)
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("playlist", "addalbum", "*", "*", node_array[0]);
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mReplace_album =function(node_array)
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("playlist", "loadalbum", "*", "*", node_array[0]);
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mAdd_artist =function(node_array)
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("playlist", "addalbum", "*", node_array[0], "*");
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mReplace_artist =function(node_array)
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("playlist", "loadalbum", "*", node_array[0], "*");
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mAdd_genre =function(node_array)
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("playlist", "addalbum", node_array[0], "*", "*");
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mReplace_genre =function(node_array)
{
	_root.nav_mc.lockMenus(true);
	var q =this.mFormQuery("playlist", "loadalbum", node_array[0], "*", "*");
	this.mSendQuery("status", q, this.mUpdate, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mUpdate =function(err)
{
	// error handling
	if (typeof err == "string") {
		return;
	}
	
	// get playlist title, album, and artist
	var node_array =this.ioXML.mExtractNode("playlist");
	var tNode =node_array[0];
	
	var path ="status_entry:song:"
	this.iPLtitle_array =this.ioXML.mGetNodeText(path +"title", tNode);
	this.iPLalbum_array =this.ioXML.mGetNodeText(path +"album", tNode);
	this.iPLartist_array =this.ioXML.mGetNodeText(path +"artist", tNode);
	this.iPLsongCnt =this.iPLtitle_array.length
	
	// update current song info object
	var node_array =this.ioXML.mExtractNode("player_status");
	var tNode =node_array[0];
	
	var path ="current_song:song:"
	var title_array =this.ioXML.mGetNodeText(path +"title", tNode);
	var album_array =this.ioXML.mGetNodeText(path +"album", tNode);
	var artist_array =this.ioXML.mGetNodeText(path +"artist", tNode);
	var path_array =this.ioXML.mGetNodeText(path +"download_url", tNode);
	
	var path ="current_song:"
	var idx_array =this.ioXML.mGetNodeText(path +"playlist_offset", tNode);
	var totalSecs_array =this.ioXML.mGetNodeText(path +"seconds_total", tNode);
	var songtime_array = this.ioXML.mGetNodeText(path +"seconds_elapsed", tNode);
	
	this.ioCurSong ={}
	this.ioCurSong["title"] =title_array[0];
	this.ioCurSong["album"] =album_array[0];
	this.ioCurSong["artist"] =artist_array[0];
	this.ioCurSong["path"] =path_array[0];
	this.ioCurSong["idx"] =parseInt(idx_array[0])+1;
	this.ioCurSong["totalSecs"] =parseInt(totalSecs_array[0]);
	this.ioCurSong["currentSecs"] =parseInt(songtime_array[0]);

	var playmode_array = this.ioXML.mGetNodeText("transport:playmode", tNode);
	this.playmode = playmode_array[0];

	_root.player_mc.update();
	_root.nav_mc.lockMenus(false);
	
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mStopSlimp3Stream =function()
{
	var lv =new LoadVars();
	lv.p0 ="stop";
	this.mSendQuery("status", lv);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mSendQuery =function(cmd, lv, cbFunc, cbContext, debug)
{
	var cmd =cmd +".xml";
	var url =slab.k.sliMP3server +"/xml/" +cmd;
	if (typeof this.ioXML == "object") this.ioXML = null;
	this.ioXML =new slab.GetXML(url  +"?" +lv, cbContext);
	if (debug) this.ioXML.mSetDebug(true);
	this.ioXML.mLoad(cbFunc);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mFormQuery =function(p0, p1, p2, p3, p4)
{
	var lv =new LoadVars();
	
	if (typeof p0 == "string") {
		lv.p0 =p0;
	}
	if (typeof p1 == "string") {
		lv.p1 =p1;
	}
	if (typeof p2 == "string") {
		lv.p2 =p2;
	}
	if (typeof p3 == "string") {
		lv.p3 =p3;
	}
	if (typeof p4 == "string") {
		lv.p4 =p4;
	}
	
	lv.player =slab.k.playerID;
	lv.itemsPerPage =slab.k.itemsPerPage;
	
	//
	return lv;
}

/*
// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mGetSongInfo =function(songPath, cbFunc, cbContext)
{
	var lv =new LoadVars();
	lv.songurl =songPath;
	this.iInfoCallbackFunc =cbFunc;
	this.iInfoCallbackContext =cbContext;
	this.mSendQuery("songinfo", lv, this.mUpdateSongInfo, this);
}

// =============================================================
// =============================================================
slab.ListAdaptor.prototype.mUpdateSongInfo =function(err)
{
	// error handling
	if (typeof err == "string") {
		return;
	}
	
	var infoFields_array  =["title", "genre", "artist", "album", "track", "type",
							"duration", "year", "filelength", "bitrate", "tagversion",
							"modtime", "song_url", "path"];
	var info_obj ={};
	for (var i=0; i<infoFields_array.length; i++) {
		var t_array =this.ioXML.mGetNodeText("songinfo:" +infoFields_array[i]);
		info_obj[infoFields_array[i]] =t_array[0];
	}
	
	this.iInfoCallbackFunc.call(this.iInfoCallbackContext, info_obj);
	
}
*/

