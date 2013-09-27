/*!
 * Ext Core Library $version&#xD;&#xA;http://extjs.com/&#xD;&#xA;Copyright(c) 2006-2009, $author.&#xD;&#xA;&#xD;&#xA;The MIT License&#xD;&#xA;&#xD;&#xA;Permission is hereby granted, free of charge, to any person obtaining a copy&#xD;&#xA;of this software and associated documentation files (the &quot;Software&quot;), to deal&#xD;&#xA;in the Software without restriction, including without limitation the rights&#xD;&#xA;to use, copy, modify, merge, publish, distribute, sublicense, and/or sell&#xD;&#xA;copies of the Software, and to permit persons to whom the Software is&#xD;&#xA;furnished to do so, subject to the following conditions:&#xD;&#xA;&#xD;&#xA;The above copyright notice and this permission notice shall be included in&#xD;&#xA;all copies or substantial portions of the Software.&#xD;&#xA;&#xD;&#xA;THE SOFTWARE IS PROVIDED &quot;AS IS&quot;, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR&#xD;&#xA;IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,&#xD;&#xA;FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE&#xD;&#xA;AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER&#xD;&#xA;LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,&#xD;&#xA;OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN&#xD;&#xA;THE SOFTWARE.&#xD;&#xA;
 */
Ext.ns('Ext.ux');

Ext.ux.Lightbox = (function(){
    var els = {},
        images = [],
        activeImage,
        initialized = false,
        selectors = [];

    return {
        overlayOpacity: 0.85,
        animate: true,
        resizeSpeed: 8,
        borderSize: 10,
        labelImage: "Image",
        labelOf: "of",

        init: function() {
            this.resizeDuration = this.animate ? ((11 - this.resizeSpeed) * 0.15) : 0;
            this.overlayDuration = this.animate ? 0.2 : 0;

            if(!initialized) {
                Ext.apply(this, Ext.util.Observable.prototype);
                Ext.util.Observable.constructor.call(this);
                this.addEvents('open', 'close');
                this.initMarkup();
                this.initEvents();
                initialized = true;
            }
        },

        initMarkup: function() {
            els.shim = Ext.DomHelper.append(document.body, {
                tag: 'iframe',
                id: 'ux-lightbox-shim'
            }, true);
            els.overlay = Ext.DomHelper.append(document.body, {
                id: 'ux-lightbox-overlay'
            }, true);
            
            var lightboxTpl = new Ext.Template(this.getTemplate());
            els.lightbox = lightboxTpl.append(document.body, {}, true);

            var ids =
                ['outerImageContainer', 'imageContainer', 'image', 'hoverNav', 'navPrev', 'navNext', 'loading', 'loadingLink',
                'outerDataContainer', 'dataContainer', 'data', 'details', 'caption', 'imageNumber', 'bottomNav', 'navClose'];

            Ext.each(ids, function(id){
                els[id] = Ext.get('ux-lightbox-' + id);
            });

            Ext.each([els.overlay, els.lightbox, els.shim], function(el){
                el.setVisibilityMode(Ext.Element.DISPLAY)
                el.hide();
            });

            var size = (this.animate ? 250 : 1) + 'px';
            els.outerImageContainer.setStyle({
                width: size,
                height: size
            });
        },

        getTemplate : function() {
            return [
                '<div id="ux-lightbox">',
                    '<div id="ux-lightbox-outerImageContainer">',
                        '<div id="ux-lightbox-imageContainer">',
                            '<img id="ux-lightbox-image">',
                            '<div id="ux-lightbox-hoverNav">',
                                '<a href="#" id="ux-lightbox-navPrev"></a>',
                                '<a href="#" id="ux-lightbox-navNext"></a>',
                            '</div>',
                            '<div id="ux-lightbox-loading">',
                                '<a id="ux-lightbox-loadingLink"></a>',
                            '</div>',
                        '</div>',
                    '</div>',
                    '<div id="ux-lightbox-outerDataContainer">',
                        '<div id="ux-lightbox-dataContainer">',
                            '<div id="ux-lightbox-data">',
                                '<div id="ux-lightbox-details">',
                                    '<span id="ux-lightbox-caption"></span>',
                                    '<span id="ux-lightbox-imageNumber"></span>',
                                '</div>',
                                '<div id="ux-lightbox-bottomNav">',
                                    '<a href="#" id="ux-lightbox-navClose"></a>',
                                '</div>',
                            '</div>',
                        '</div>',
                    '</div>',
                '</div>'
            ];
        },

        initEvents: function() {
            var close = function(ev) {
                ev.preventDefault();
                this.close();
            };

            els.overlay.on('click', close, this);
            els.loadingLink.on('click', close, this);
            els.navClose.on('click', close, this);

            els.lightbox.on('click', function(ev) {
                if(ev.getTarget().id == 'ux-lightbox') {
                    this.close();
                }
            }, this);

            els.navPrev.on('click', function(ev) {
                ev.preventDefault();
                this.setImage(activeImage - 1);
            }, this);

            els.navNext.on('click', function(ev) {
                ev.preventDefault();
                this.setImage(activeImage + 1);
            }, this);
        },

        register: function(sel, group) {
            if(selectors.indexOf(sel) === -1) {
                selectors.push(sel);

                Ext.fly(document).on('click', function(ev){
                    var target = ev.getTarget(sel);

                    if (target) {
                    	ev.preventDefault();
                        this.open(target, sel, group);
                    }
                }, this);
            }
        },

        open: function(image, sel, group, slideWindow) {
            group = group || false;
            this.setViewSize();
            els.overlay.fadeIn({
                duration: this.overlayDuration,
                endOpacity: this.overlayOpacity,
                callback: function() {
                    images = [];

                    var index = 0;
                    if(!group) {
                        images.push([image.href, image.title || image.text]);
                    }
                    else {
                        var setItems = slideWindow ? slideWindow.Ext.query(sel) : Ext.query(sel);
                        Ext.each(setItems, function(item) {
                            if(item.href) {
                                images.push([item.href, item.title || item.text]);
                            }
                        });

                        while (images[index][0] != image.href) {
                            index++;
                        }
                    }

                    // calculate top and left offset for the lightbox
                    var pageScroll = Ext.fly(document).getScroll();

                    var lightboxTop = Math.min(pageScroll.top + (Ext.lib.Dom.getViewportHeight() / 10), 40);
                    var lightboxLeft = pageScroll.left;
                    els.lightbox.setStyle({
                        top: lightboxTop + 'px',
                        left: lightboxLeft + 'px'
                    }).show();

                    this.setImage(index);
                    
                    this.fireEvent('open', images[index]);                                        
                },
                scope: this
            });
        },
        
        setViewSize: function(){
            var viewSize = this.getViewSize();
            els.overlay.setStyle({
                width: viewSize[0] + 'px',
                height: viewSize[1] + 'px'
            });
            els.shim.setStyle({
                width: viewSize[0] + 'px',
                height: viewSize[1] + 'px'
            }).show();
        },

        setImage: function(index){
            activeImage = index;
                      
            this.disableKeyNav();            
            if (this.animate) {
                els.loading.show();
            }

            els.image.hide();
            els.hoverNav.hide();
            els.navPrev.hide();
            els.navNext.hide();
            els.dataContainer.setOpacity(0.0001);
            els.imageNumber.hide();

            var preload = new Image();
            preload.onload = (function(){
                els.image.dom.src = images[activeImage][0];
                this.resizeImage(preload.width, preload.height);
            }).createDelegate(this);
            preload.src = images[activeImage][0];
        },

        resizeImage: function(w, h){
            var wCur = els.outerImageContainer.getWidth();
            var hCur = els.outerImageContainer.getHeight();
            
            var viewSize = this.getViewSize();        
            var closeHeight = 100;

            var wNew = (w + this.borderSize * 2);
            var hNew = (h + this.borderSize * 2);
            
            var ratio = h/w;
            
            if (wNew > viewSize[0]) {
            	wNew = viewSize[0];
            	h = wNew * ratio;
            	hNew = h + this.borderSize * 2;
	            w = wNew - this.borderSize * 2;
            }
            
            if (hNew > viewSize[1] - closeHeight) {
            	hNew = viewSize[1] - closeHeight;
            	wNew = hNew / ratio;
	            w = wNew - this.borderSize * 2;
	            h = hNew - this.borderSize * 2;
            }

            var wDiff = wCur - wNew;
            var hDiff = hCur - hNew;

            var afterResize = function(){
                els.hoverNav.setWidth(els.imageContainer.getWidth() + 'px');

                els.navPrev.setHeight(h + 'px');
                els.navNext.setHeight(h + 'px');

                els.outerDataContainer.setWidth(wNew + 'px');

                els.image.setWidth(w);
                els.image.setHeight(h);
                this.showImage();
            };
            
            if (hDiff != 0 || wDiff != 0) {
                els.outerImageContainer.shift({
                    height: hNew,
                    width: wNew,
                    duration: this.resizeDuration,
                    scope: this,
                    callback: afterResize,
                    delay: 50
                });
            }
            else {
                afterResize.call(this);
            }
        },

        showImage: function(){
            els.loading.hide();
            els.image.fadeIn({
                duration: this.resizeDuration,
                scope: this,
                callback: function(){
                    this.updateDetails();
                }
            });
            this.preloadImages();
        },

        updateDetails: function(){
            var detailsWidth = els.data.getWidth(true) - els.navClose.getWidth() - 10;
            els.details.setWidth((detailsWidth > 0 ? detailsWidth : 0) + 'px');
            
            els.caption.update('<a href="' + images[activeImage][0] + '" target="_blank">' + images[activeImage][1] + '</a>');

            els.caption.show();
            if (images.length > 1) {
                els.imageNumber.update(this.labelImage + ' ' + (activeImage + 1) + ' ' + this.labelOf + '  ' + images.length);
                els.imageNumber.show();
            }

            els.dataContainer.fadeIn({
                duration: this.resizeDuration/2,
                scope: this,
                callback: function() {
                    var viewSize = this.getViewSize();
                    els.overlay.setHeight(viewSize[1] + 'px');
                    this.updateNav();
                }
            });
        },

        updateNav: function(){
            this.enableKeyNav();

            els.hoverNav.show();

            // if not first image in set, display prev image button
            if (activeImage > 0)
                els.navPrev.show();

            // if not last image in set, display next image button
            if (activeImage < (images.length - 1))
                els.navNext.show();
        },

        enableKeyNav: function() {
            Ext.fly(document).on('keydown', this.keyNavAction, this);
        },

        disableKeyNav: function() {
            Ext.fly(document).un('keydown', this.keyNavAction, this);
        },

        keyNavAction: function(ev) {
            var keyCode = ev.getKey();

            if (
                keyCode == 88 || // x
                keyCode == 67 || // c
                keyCode == 27
            ) {
                this.close();
            }
            else if (keyCode == 80 || keyCode == 37){ // display previous image
                if (activeImage != 0){
                    this.setImage(activeImage - 1);
                }
            }
            else if (keyCode == 78 || keyCode == 39){ // display next image
                if (activeImage != (images.length - 1)){
                    this.setImage(activeImage + 1);
                }
            }
        },

        preloadImages: function(){
            var next, prev;
            if (images.length > activeImage + 1) {
                next = new Image();
                next.src = images[activeImage + 1][0];
            }
            if (activeImage > 0) {
                prev = new Image();
                prev.src = images[activeImage - 1][0];
            }
        },

        close: function(){
            this.disableKeyNav();
            els.lightbox.hide();
            els.overlay.fadeOut({
                duration: this.overlayDuration
            });
            els.shim.hide();
            this.fireEvent('close', activeImage);
        },

        getViewSize: function() {
            return [Ext.lib.Dom.getViewWidth(), Ext.lib.Dom.getViewHeight()];
        }
    }
})();

Ext.onReady(Ext.ux.Lightbox.init, Ext.ux.Lightbox);