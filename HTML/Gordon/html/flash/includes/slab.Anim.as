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
_global.slab.Anim = function(mc, accel)
{
	this.mc =mc;
	if (typeof accel=="number") {
		this.accel =accel;
	} else {
		this.accel =3;
	}
}


// =============================================================
// =============================================================
slab.Anim.prototype.mEaseIn =function(bgnPos, endPos, cbFunc, cbContext, cbParams_array)
{
	this.mc.pos =bgnPos;
	this.mc.posNew =endPos;
	this.mc.callbackFunc =cbFunc;
	this.mc.callbackContext =cbContext;
	this.mc.callbackParams_array =cbParams_array;
	this.mc.accel =this.accel;
	
	this.mc.onEnterFrame =function() {
		with (this) {
			if (Math.abs(posNew-pos)>1) { 
				pos += (posNew-pos)/accel;
				_x =pos;
			} else {
				_x =posNew;
				delete onEnterFrame;
				if (typeof callbackFunc=="function") {
					callbackFunc.apply(callbackContext, callbackParams_array);
				}
			}
		}
	}
}

// =============================================================
// =============================================================
slab.Anim.prototype.mEaseOut =function(bgnPos, endPos, cbFunc, cbContext, cbParams_array)
{
	this.mc.pos =bgnPos;
	this.mc.posNew =endPos;
	this.mc.callbackFunc =cbFunc;
	this.mc.callbackContext =cbContext;
	this.mc.callbackParams_array =cbParams_array;
	
	//
	this.mc.span =Math.abs(endPos-bgnPos);
	if (this.mc.posNew >this.mc.pos) {
		this.mc.accel =this.accel;
	} else {
		this.mc.accel =-this.accel;
	}
	
	//ease-out anim
	this.mc.onEnterFrame =function() {
		with (this) {
			accel +=accel;
			pos +=accel;
			if (Math.abs(posNew-pos)<span) {
				_x =pos;
			} else {
				_x =posNew;
				delete onEnterFrame;
				if (typeof callbackFunc=="function") {
					callbackFunc.apply(callbackContext, callbackParams_array);
				}
			}
			
		}
	}
}

