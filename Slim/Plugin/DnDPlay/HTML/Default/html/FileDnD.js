if (window.File && window.FileList) {
	FileDnD = {
		queue: new Array,
		
		// enable file d'n'd handler
		init: function() {
			// Setup the dnd listeners.
			Ext.get('rightcontent').on({
				dragover: this.handleDragOver,
				drop: this.handleFileSelect,
				scope: this
			});
		},
		
		handleFileSelect: function(ev) {
			var evt = ev.browserEvent;
			
			evt.stopPropagation();
			evt.preventDefault();
	
			var files = evt.dataTransfer.files; // FileList object.
			var added = 0;
			var check = new Array();

			for (var i = 0, file; file = files[i]; i++) {
				// only upload audio files
				if (file.type.match('audio')) {
					added++;
					this.queue.push(file);
					check.push({
						name: file.name,
						size: file.size,
						type: file.type,
						timestamp: Math.floor(file.lastModifiedDate.getTime() / 1000)
					});
				}
			}
			
			if (added > 0 && evt.shiftKey) {
				SqueezeJS.Controller.playerControl(['playlist', 'clear']);
			}
			
			Ext.Ajax.request({
				url: SqueezeJS.Controller.getBaseUrl() + '/plugin/dndplay/checkfiles',
				method: 'POST',
				params: Ext.util.JSON.encode(check),
				timeout: 5000,
				success: function(response) {
					if (response && response.responseText) {
						response = Ext.util.JSON.decode(response.responseText);

						if (response && response.actions) {
							for (var i = 0; i < response.actions.length; i++) {
								if (this.queue[i] && !this.queue[i].action) {
									this.queue[i].action = response.actions[i];
								} 
							}
						}

						this.uploadFile();
					}
				},
				scope: this
			});
		},
		
		handleDragOver: function(ev) {
			var evt = ev.browserEvent;
			evt.stopPropagation();
		    evt.preventDefault();
		    evt.dataTransfer.dropEffect = 'copy';
		},
		
		uploadFile: function() {
			var file = this.queue.shift();
			
			if (!file) {
				SqueezeJS.Controller.getStatus();
				return;
			}
			
			// we've received a file URL - play it
			if (file.action && file.action != 'upload') {
				SqueezeJS.Controller.playerRequest({
					params: [ "playlist", "add", file.action ],
					callback: this.uploadFile,
					scope: this
				});
				return;
			}
			
			var xhr = new XMLHttpRequest();    // den AJAX Request anlegen
			xhr.open('POST', '/plugin/dndplay/upload');    // Angeben der URL und des Requesttyps
			
			var scope = this;
			xhr.onreadystatechange = function() {
				if (xhr.readyState == 4) {
					this.uploadFile();
				}
			}.createDelegate(this);
			
			var formdata = new FormData();    // Anlegen eines FormData Objekts zum Versenden unserer Datei
			formdata.append('name', file.name);
			formdata.append('size', file.size);
			formdata.append('type', file.type);
			formdata.append('timestamp', Math.floor(file.lastModifiedDate.getTime() / 1000))
			formdata.append('uploadfile', file);  // Anhängen der Datei an das Objekt
			xhr.send(formdata); 
		} 
	};

	Ext.onReady(function() {
		FileDnD.init();
	}, FileDnD);
}