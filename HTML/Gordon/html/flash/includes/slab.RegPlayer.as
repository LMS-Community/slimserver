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
_global.slab.RegPlayer =function(cb, cbContext)
{
	this.callbackFunc =cb;
	this.callbackContext =cbContext;
}

// =============================================================
// get player status XML page
// =============================================================
slab.RegPlayer.prototype.mGetPlayerID =function()
{
	this.mSendQuery("status", "", this.mGetPlayerID_CB, this);
}

// =============================================================
// =============================================================
slab.RegPlayer.prototype.mGetPlayerID_CB =function(err)
{
	// error handling
	if (typeof err == "string") {
		_root.report_mc.appendText("Error contacting SlimServer: " + err);
		return;
	}
	
	// get a player count
	var node_array =this.ioXML.mExtractNode("players");
	var tNode =node_array[0];
	var playercount_array =this.ioXML.mGetNodeText("playercount", tNode);
	var playercount =parseInt(playercount_array[0]);
	trace("playercount: " +playercount);
	
	
	// no players
	if (playercount <=0) {
		_root.report_mc.appendText("No players to control");
		return;
	}
	
	if (slab.k.playerID == undef) {
		var node_array =this.ioXML.mExtractNode("player", tNode);
		playerID_array =this.ioXML.mGetNodeText("player_id", node_array[0]);
		slab.k.playerID =playerID_array[0];
		trace("set playerID to: " +playerID_array[0]);
	}
	
	this.callbackFunc.call(this.callbackContext);
	return;
}

// =============================================================
// =============================================================
slab.RegPlayer.prototype.mSendQuery =function(cmd, lv, cbFunc, cbContext, debug)
{
	var cmd =cmd +".xml";
	var url =slab.k.sliMP3server +"/xml/" +cmd;
	if (typeof this.ioXML == "object") this.ioXML = null;
	this.ioXML =new slab.GetXML(url, cbContext);
	if (debug) this.ioXML.mSetDebug(true);
	trace("Trying to load URL: " + url);
	this.ioXML.mLoad(cbFunc);
}

	