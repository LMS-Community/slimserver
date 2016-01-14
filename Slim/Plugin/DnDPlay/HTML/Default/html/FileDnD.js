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

			for (var i = 0, f; f = files[i]; i++) {
				// only upload audio files
				if (f.type.match('audio')) {
					added++;
					this.queue.push(f);
				}
			}
			
			if (added > 0 && evt.shiftKey) {
				SqueezeJS.Controller.playerControl(['playlist', 'clear']);
			}

			this.uploadFile();
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
			
			var xhr = new XMLHttpRequest();    // den AJAX Request anlegen
			xhr.open('POST', '/plugin/dndplay/upload');    // Angeben der URL und des Requesttyps
			
			var scope = this;
			xhr.onreadystatechange = function() {
				if (xhr.readyState == 4) {
					this.uploadFile();
				}
			}.createDelegate(this);
			
			var formdata = new FormData();    // Anlegen eines FormData Objekts zum Versenden unserer Datei
			formdata.append('uploadfile', file);  // Anhängen der Datei an das Objekt
			xhr.send(formdata); 
		} 
	};

	Ext.onReady(function() {
		FileDnD.init();
	}, FileDnD);
}