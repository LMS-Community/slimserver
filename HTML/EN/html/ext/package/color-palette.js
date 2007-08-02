/*
 * Ext JS Library 1.1
 * Copyright(c) 2006-2007, Ext JS, LLC.
 * licensing@extjs.com
 * 
 * http://www.extjs.com/license
 */


Ext.ColorPalette=function(_1){Ext.ColorPalette.superclass.constructor.call(this,_1);this.addEvents({select:true});if(this.handler){this.on("select",this.handler,this.scope,true);}};Ext.extend(Ext.ColorPalette,Ext.Component,{itemCls:"x-color-palette",value:null,clickEvent:"click",ctype:"Ext.ColorPalette",allowReselect:false,colors:["000000","993300","333300","003300","003366","000080","333399","333333","800000","FF6600","808000","008000","008080","0000FF","666699","808080","FF0000","FF9900","99CC00","339966","33CCCC","3366FF","800080","969696","FF00FF","FFCC00","FFFF00","00FF00","00FFFF","00CCFF","993366","C0C0C0","FF99CC","FFCC99","FFFF99","CCFFCC","CCFFFF","99CCFF","CC99FF","FFFFFF"],onRender:function(_2,_3){var t=new Ext.MasterTemplate("<tpl><a href=\"#\" class=\"color-{0}\" hidefocus=\"on\"><em><span style=\"background:#{0}\" unselectable=\"on\">&#160;</span></em></a></tpl>");var c=this.colors;for(var i=0,_7=c.length;i<_7;i++){t.add([c[i]]);}var el=document.createElement("div");el.className=this.itemCls;t.overwrite(el);_2.dom.insertBefore(el,_3);this.el=Ext.get(el);this.el.on(this.clickEvent,this.handleClick,this,{delegate:"a"});if(this.clickEvent!="click"){this.el.on("click",Ext.emptyFn,this,{delegate:"a",preventDefault:true});}},afterRender:function(){Ext.ColorPalette.superclass.afterRender.call(this);if(this.value){var s=this.value;this.value=null;this.select(s);}},handleClick:function(e,t){e.preventDefault();if(!this.disabled){var c=t.className.match(/(?:^|\s)color-(.{6})(?:\s|$)/)[1];this.select(c.toUpperCase());}},select:function(_d){_d=_d.replace("#","");if(_d!=this.value||this.allowReselect){var el=this.el;if(this.value){el.child("a.color-"+this.value).removeClass("x-color-palette-sel");}el.child("a.color-"+_d).addClass("x-color-palette-sel");this.value=_d;this.fireEvent("select",this,_d);}}});
