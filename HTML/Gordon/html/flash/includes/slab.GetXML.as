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
_global.slab.GetXML = function(URL, cbContext)
{
	//_root.report_mc.appendText("GetXML: " +URL);
	// Instance properties
	this.URL;
	this.callbackFunc;
	this.callbackContext;
	this.debug =false;
	
	// Initialization
	if (typeof URL == "string") {
		this.mSetURL(URL);
	}
	
	this.mSetCallbackContext(cbContext);
	
}

// =============================================================
// =============================================================
slab.GetXML.prototype.mLoad = function(cbFunc)
{
	//_root.report_mc.appendText("GetXML.mLoad");
	//
	if (typeof cbFunc == "function") {
		this.mSetCallbackFunc(cbFunc);
	}
	
	
	// Store a reference to this object, for use 
	// inside the onLoad callback.
	var me = this;
  
	// Load the XML data.
	this.iXML = new XML();
	this.iXML.ignoreWhite = true;
	
	if (this.debug) {
		this.iXML.onData = this.mDataCallback;
	} else {
		this.iXML.onLoad = loadCallback;
	}
	
	this.loaderID =setInterval(this, "mCheckLoadProgress", 200);
	this.iXML.load(this.URL);
	
	function loadCallback(success) {
		//
		if (success) {
			me.mClearLoadCheck();
			me.mUpdateBar(100);
			me.callbackFunc.call(me.callbackContext, 0);
		} else {
			trace("Error loading XML");
			//_root.report_mc.appendText("Error loading XML");
			me.callbackFunc.call(me.callbackContext, "Error loading XML");
		}
	}
}

// =============================================================
// =============================================================
slab.GetXML.prototype.mCheckLoadProgress = function() 
{
	var kbLoaded =Math.floor(this.iXML.getBytesLoaded()/1024);
	var kbTotal  =Math.floor(this.iXML.getBytesTotal()/1024);
	var percentDone =isNaN(	Math.floor(kbLoaded/kbTotal*100) ) ? 0 :
							Math.floor(kbLoaded/kbTotal*100)
	this.mUpdateBar(percentDone);
	
	if (this.iXML.getBytesLoaded() >5 && 
		this.iXML.getBytesLoaded() ==this.iXML.getBytesTotal()) {
		this.mClearLoadCheck();
	}
}

// =============================================================
// =============================================================
slab.GetXML.prototype.mClearLoadCheck = function() 
{
	//trace("interval cleared");
	if (this.loaderID) {
		clearInterval(this.loaderID);
		this.loaderID =0;
	}
}

// =============================================================
// =============================================================
slab.GetXML.prototype.mUpdateBar = function(percentDone) 
{
	//trace(percentDone);
	_root.progress_mc.bar_mc._xscale =percentDone;
}

// =============================================================
// pass a tag path, get an array of strings.  recursive.
// =============================================================
slab.GetXML.prototype.mGetNodeText = function(path, theNode)
{
	var nodeDepth =0;
	var result_array =[];
	var path_array =path.split(":");
	
	// if node param is undefined, set to root
	if (typeof theNode == "object") {
		scanTree(theNode);
	} else {
		scanTree(this.iXML);
	}
	
	//
	return result_array;
	
	//
	function scanTree(theNode) {
		var nodeLength =theNode.childNodes.length;
		for (var i=0; i<nodeLength; i++) {
			var testNode =theNode.childNodes[i];
			if (testNode.nodeType==1) {
				if (testNode.nodeName==path_array[nodeDepth]) {
					if (nodeDepth==path_array.length-1) {
						result_array.push(testNode.firstChild.nodeValue);
					} else {
						nodeDepth++;
						scanTree(testNode);
					}
				}
			}
		}
		nodeDepth--;
	}
}


// =============================================================
// pass a tag, get an array of nodes.
// non-recursive.
// returns all occurrences or 0.
// =============================================================
slab.GetXML.prototype.mExtractNode = function(tag, theNode) 
{
	// if node param is undefined, set to root
	if (typeof theNode != "object") {
		theNode =this.iXML.firstChild;
	} 

	var nodeLength =theNode.childNodes.length;
	var foundNodes_array =[];
	for (var i=0; i<nodeLength; i++) {
		if (theNode.childNodes[i].nodeType==1) {
			if (theNode.childNodes[i].nodeName==tag) {
				foundNodes_array.push(theNode.childNodes[i]);
			}
		}
	}
	
	if (foundNodes_array.length==0) {
		return 0;
	} else {
		return foundNodes_array;
	}
	
}

// =============================================================
// =============================================================
slab.GetXML.prototype.mDataCallback = function(XML_str)
{
	trace(XML_str);
}


// =============================================================
// GETTERS AND SETTERS
// =============================================================
slab.GetXML.prototype.mSetKey = function(key)
{
	this.key =key;
}
slab.GetXML.prototype.mGetKey = function()
{
	return this.key;
}
slab.GetXML.prototype.mSetURL = function(URL)
{
	this.URL =URL;
}
slab.GetXML.prototype.mGetURL = function()
{
	return this.URL;
}
slab.GetXML.prototype.mSetCallbackFunc = function(cbFunc)
{
	this.callbackFunc =cbFunc;
}
slab.GetXML.prototype.mGetCallbackFunc = function()
{
	return this.callbackFunc;
}
slab.GetXML.prototype.mSetCallbackContext = function(cbContext)
{
	this.callbackContext =cbContext;
}
slab.GetXML.prototype.mGetCallbackContext = function()
{
	return this.callbackObj;
}
slab.GetXML.prototype.mSetDebug = function(flag)
{
	this.debug =flag;
}

