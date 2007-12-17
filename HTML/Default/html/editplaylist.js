EditPlaylist = function(){
	return {
		init: function(){
			new Slim.Sortable({
				el: 'browsedbList',
				selector: '#browsedbList div.draggableSong',
				onDropCmd: function(sourcePos, targetPos) {
					Utils.processCommand({
						params: [ '', [
							'playlists',
							'edit',
							'playlist_id:' + playlistId,
							'cmd:move',
							'index:' + sourcePos,
							'toindex:' + targetPos
						]]
					});
				}
			})
		}
	};
}();
