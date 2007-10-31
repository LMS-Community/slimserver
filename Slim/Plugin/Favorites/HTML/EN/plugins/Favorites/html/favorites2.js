var Favorites = function(){
	return {
		init : function(session){
			// some initialization of the DD class used
			Ext.dd.ScrollManager.register('draglist');

			Ext.override(Ext.dd.DDProxy, {

				// highlight a copy of the dragged item to move with the mouse pointer
				startDrag: function(x, y) {
					var dragEl = Ext.get(this.getDragEl());
					var el = Ext.get(this.getEl());
					Utils.unHighlight();

					dragEl.applyStyles({'z-index':2000});
					dragEl.update(el.dom.innerHTML);
					dragEl.addClass(el.dom.className + ' dd-proxy');
				},

				// disable the default behaviour which would place the dragged element
				// we don't need to place it as it will be moved in onDragDrop
				endDrag: function() {},

				onDragEnter: function(ev, id) {
					var source = Ext.get(this.getEl());
					var target = Ext.get(id);

					if (target && source) {
						if (target.dd.config.position < source.dd.config.position)
							Ext.get(id).addClass('dragUp');
						else
							Ext.get(id).addClass('dragDown');
					}
				},

				onDragOut: function(e, id) {
					Ext.get(id).removeClass('dragUp');
					Ext.get(id).removeClass('dragDown');
				},

				// move the item when dropped
				onDragDrop: function(e, id) {
					var source = Ext.get(this.getEl());
					var target = Ext.get(id);

					if (target && source) {
						var sourcePos = -1;
						var targetPos = -1;

						target.removeClass('dragUp');
						target.removeClass('dragDown');

						// get to know where we come from, where we've gone to
						var items = Ext.query('ol#draglist li');
						for(var i = 0; i < items.length; i++) {
							if (items[i].id == this.id)
								sourcePos = i;
							else if (items[i].id == id)
								targetPos = i;
						}
			
						if (sourcePos >= 0 && targetPos >= 0 && (sourcePos != targetPos)) {
							var plPosition, plStart, el;

							if (sourcePos > targetPos) {
								source.insertBefore(target);
								plPosition = parseInt(target.dd.config.position) - targetPos;
								plStart = targetPos;
							}
							else  {
								source.insertAfter(target);
								plPosition = parseInt(source.dd.config.position) - sourcePos;
								plStart = sourcePos;
							}

							// send the result to the page handler
							Ext.Ajax.request({
								method: 'GET',
								url: 'index.html',
								params: {
									ajaxUpdate: 1,
									action: 'move',
									index: source.dd.config.position,
									to: target.dd.config.position,
									sess: session
								},
								timeout: 5000,
								disableCaching: true
							});

							// recalculate the item's number within the playlist
							items = Ext.query('ol#draglist li');
							for(var i = plStart; i < items.length; i++) {
								if (el = Ext.get(items[i]))
									el.dd.config.position = plPosition + i;
							}

							Utils.init();
						}
					}
				}
			});

			var items = Ext.DomQuery.select('ol#draglist li');
			for(var i = 0; i < items.length; i++) {
				var item = Ext.get(items[i]);

				var itemNo = item.id.replace(/\D*/, '');

				item.dd = new Ext.dd.DDProxy(items[i], 'playlist', {position: itemNo});
				item.dd.setXConstraint(0, 0);
				item.dd.scroll = false;
				item.dd.scrollContainer = true;
			}
		}
	}
}();