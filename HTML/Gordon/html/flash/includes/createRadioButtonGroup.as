

// ========================================
// ========================================
function createRadioButtonGroup(mc_id, labels_array, format, depth, cbFuncs) {
	
	// create mc
	var main_mc =this.createEmptyMovieClip(mc_id, depth);
	
	//
	var btns_array =[];
	var overall_width =0;
	var spacer_str ="|";
	
	//
	for (var i=0; i<labels_array.length; i++) {
		
		//set label string
		var label_str =labels_array[i];
		
		//create a mc for this button
		var btn_id ="btn_" +(i+1) +"_mc";
		var btn_mc =main_mc.createEmptyMovieClip(btn_id, i);
		btns_array.push(btn_mc);
		
		//create the label for this button
		btn_mc.createTextField("label_txt", 0, overall_width, 0, 0, 0);
		
		//format label
		btn_mc.label_txt.text =label_str;
		btn_mc.label_txt.embedFonts =true;
		btn_mc.label_txt.autoSize =true;
		btn_mc.label_txt.selectable =false;
		btn_mc.label_txt.setTextFormat(format);
		
		//
		overall_width +=btn_mc._width;
		
		//insert a spacer mc
		if (i<labels_array.length-1) {
			var spacer_mc =main_mc.createEmptyMovieClip("spacer_" +(i+1) +"_mc", labels_array.length+i);
			spacer_mc.createTextField("spacer_txt", 0, overall_width, 0, 0, 0);
			
			//format spacer
			spacer_mc.spacer_txt.text =spacer_str;
			spacer_mc.spacer_txt.embedFonts =true;
			spacer_mc.spacer_txt.autoSize =true;
			spacer_mc.spacer_txt.selectable =false;
			spacer_mc.spacer_txt.setTextFormat(format);
		}
		
		//
		overall_width +=spacer_mc._width;
		
		//button script
		btn_mc.idx =i+1;
		btn_mc.useHandCursor =false;
		
		btn_mc.onRelease =function() {
			this._parent.btnClick(this.idx);
		};
		btn_mc.onRollOver =function() {
			//if (this._parent.clickLock) return;
			this.hilite(true);
		};
		btn_mc.onRollOut =function() {
			this.hilite(false);
		};
		btn_mc.hilite =function(isHilited) {
			if (this._parent.curIDX ==this.idx) return;
			if (isHilited) {
				this.label_txt.setTextFormat(new TextFormat(null,null,0xFFFFFF));
			} else {
				this.label_txt.setTextFormat(new TextFormat(null,null,format.color));
			}
		};
	}
	
	//group script
	main_mc.btns_array =btns_array;
	main_mc.cbFuncs =cbFuncs;
	main_mc.cbObj =this;
	main_mc.curIDX =null;
	main_mc.clickLock =false;
	

	main_mc.btnClick =function(idx, force) {
		//trace(this +" btnClick: " +idx);
		if (this.clickLock) return;
		if (this.curIDX==idx && !force) return;
		this.select(idx);
		if (typeof this.cbFuncs == "function") {
			this.cbFuncs.call(this.cbObj, idx);
		} else if (typeof this.cbFuncs == "object") {
			this.cbFuncs[idx-1].call(this.cbObj, idx);
		}
	};
	main_mc.select =function(idx, force) {
		if (idx==this.curIDX && !force) return;
		this.curIDX =null;
		for (var i=0; i<this.btns_array.length; i++) {
			this.btns_array[i].hilite(false);
		}
		this.btns_array[idx-1].hilite(true);
		this.curIDX =idx;
	};
	main_mc.hilite =function(idx) {
		this.curIDX =null;
		for (var i=0; i<this.btns_array.length; i++) {
			this.btns_array[i].hilite(false);
		}
		this.btns_array[idx-1].hilite(true);
	};
	main_mc.setClickLock =function(isLocked) {
		this.clickLock =isLocked;
	};
	
	return overall_width;
}

