var favlist = [];

if (parent.JXTK2) var pJXTK2 = parent.JXTK2;

function favlistXButtonHandler(button) {
        var selIndex = button.getEl().parentNode.parentNode.index;
        if (selIndex < 0) return;

	parent.browseurl('plugins/Favorites/favorites_list.html?p0=delete&p1=' + selIndex);
}

function favlistDragEndHandler(movecount, elementpos) {
        var newpos = elementpos + movecount;
	parent.browseurl('plugins/Favorites/favorites_list.html?p0=move&p1=' + elementpos + '&p2=' + newpos);
}

function doFavSelect(index) {
	parent.doBrowseCommand([ 'playlist', 'play', favlist[i].url ]);
}

function initFavList(newlist) {
	for (var i = 0; i < (newlist.length - 1); i++) {
		favlist.push({
			title : ( newlist[i].name != '' ?
				( "<a onclick='doFavSelect(" + i + ")'>" + newlist[i].name + "</a>" ) :
				pJXTK2.String.getString("EMPTY")
			) , 
			url : newlist[i].url
		});
	}

	var buttonsTemplate = document.createElement('div');
	buttonsTemplate.className = "playlistbuttons";

	var xButton = document.createElement('img');
	xButton.src = webroot + 'html/images/remove.gif';
	xButton.title = pJXTK2.String.getString("DELETE");
	xButton.alt = pJXTK2.String.getString("DELETE");
	buttonsTemplate.appendChild(xButton);

	var dragButton = document.createElement('img');
	dragButton.src = webroot + 'html/images/moveupdown.gif';
	dragButton.className = 'dragbutton';
	dragButton.title = pJXTK2.String.getString("MOVE");
	dragButton.alt = pJXTK2.String.getString("MOVE");
	buttonsTemplate.appendChild(dragButton);

	var favcombo = new JXTK2.ComboList("playlist", buttonsTemplate, function(clist, row) {
		var xButtonObj = new JXTK2.Button(row.firstChild.firstChild);
		xButtonObj.addClickHandler(favlistXButtonHandler);
		clist.makeRowDraggable(row, row.firstChild.childNodes[1], favlistDragEndHandler);
	});

	favcombo.update(favlist);
}
