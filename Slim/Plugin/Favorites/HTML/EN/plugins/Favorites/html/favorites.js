// track if sortable effect in use.
var sortableReordered = false;

var movefromHTML;
var movetoHTML;

// parse new order for source and target indices
function reorderlist(order, offset, from) {
	var params;
	
	for (var i=0; i < order.length; i++) {
		var rexp = new RegExp("\\d+$");
		var id = rexp.exec(order[i]);
		
		if (id == from) {
			
			// format level offset for url params
			if (offset) {
				offset = offset + ".";
			} else {
				offset = "";
			}
			
			// pull a background result of the move command
			updateList("action=move&index=" + offset + from + "&to=" + i);
			
			break;
		}
	}
}

// request and update with new list html
//TODO target something more appropriate than document.body since we're retrieving the entire html, head and all.
function updateList(params) {
	new Ajax.Updater( { success: document.body }, webroot + 'plugins/Favorites/index.html', {
		method: 'post',
		postBody: params,
		evalScripts: true,
		asynchronous: true,
		onFailure: function(t) {
			alert('Error -- ' + t.responseText);
		}
	} );
}

// swallow click event if sortable in progress
function checkSortable(event) {
	if (sortableReordered) {
		Event.stop(event);
		sortableReordered = false;
	}
}

// drag and dropfavorites list, scrolling window when needed.
var activeElem = null;
function initListSortable(element, offset) {

	if (! $(element)) {
		return;
	}
	
	Position.includeScrollOffsets = true;
	
	var activeElem = null;
	//<![CDATA[
	Sortable.create(element, {
		onChange: function(item) {
			var rexp = new RegExp("\\d+$");
			var id = rexp.exec(item.id);
			activeElem = parseInt(id);
			sortableReordered = true;
		},
		onUpdate: function() {
			reorderlist(Sortable.sequence(element), offset, activeElem);
		},
		scroll: window,
		revert: true
	});
	//]]>
}

var editHTML = new Array();
function edit(id) {
	var element = $('dragitem_' + id);
	
	// backup copy of line item in case of cancel
	editHTML[id] = element.innerHTML;
	
	// pull an edit form via Ajax
	new Ajax.Updater( { success: element }, webroot + 'plugins/Favorites/index.html?action=edit&index=' + id, {
		method: 'get',
		asynchronous: true,
		onFailure: function(t) {
			alert('Error -- ' + t.responseText);
		}
	} );
}

function editCancel(id, remove) {
	var element = $('dragitem_' + id);
	
	element.innerHTML = editHTML[id];
	delete editHTML[id];
	showElements(['defaultform']);

	// handle the remove on cancel case
	if (remove == '1') {
		Element.remove(element);
		ajaxRequest(webroot + 'plugins/Favorites/index.html','action=editset&index=' + id + '&cancel=1&removeoncancel=1');
	}
}

function editSave(id) {
	var element = document.getElementById('dragitem_' + id);
	
	var newTitle = $('edit_title_' + id);
	var params = 'action=editset&index=' + id + '&entrytitle=' + escape(newTitle.value);
	
	if ($('edit_url_'   + id)) {
		var newURL = escape($('edit_url_'   + id));
		params     = params + '&entryurl=' + newURL
	}
	
	showElements(['defaultform']);
	
	// get an update of the edited line item
	new Ajax.Updater( { success: element }, webroot + 'plugins/Favorites/index.html', {
		method: 'post',
		postBody: params,
		asynchronous: true,
		onSuccess: function(t) {
			delete editHTML[id];
			new Effect.Highlight('dragitem_' + id, { endcolor: "#d5d5d5" });
		},
		onFailure: function(t) {
			delete editHTML[id];
			alert('Error -- ' + t.responseText);
		}
	} );
}

function showControls(id) {
	if (document.getElementById(id)) {
		document.getElementById(id).style.display = 'inline';
	}
}

function hideControls(id) {
	if (document.getElementById(id)) {
		document.getElementById(id).style.display = 'none';
	}
}