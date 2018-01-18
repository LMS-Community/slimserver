[%
	PROCESS jsString id='PLUGIN_DNDPLAY_NO_ITEMS' jsId='';
	PROCESS jsString id='PLAYLIST_NO_ITEMS_FOUND' jsId='noItemsFound';
	PROCESS jsString id='ADDING_TO_PLAYLIST' jsId='';
%]

SqueezeJS.Strings['fileTooLarge'] = "[% fileTooLarge | html | replace('"', '\"') %]";
	
SqueezeJS.DnD = {
	maxUploadSize: [% maxUploadSize %],
	validTypeExtensions: '[% validTypeExtensions %]'
};
	
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
			
			var error;

			// create a list of the files we want to play - we create an Array, as we can't pop items from the FileList object
			for (var i = 0, file; file = files[i]; i++) {
				// only upload audio files
				if (file.type.match('audio') || file.name.match(SqueezeJS.DnD.validTypeExtensions)) {
					added++;
					this.queue.push(file);
				}
			}

			if (added > 0) {
				var action = 'add';
				
				if (evt.shiftKey && SqueezeJS.Controller.playerStatus.playlist_tracks > 0) {
					SqueezeJS.Controller.playerControl(['playlist', 'clear']);
					action = 'play';
				}
				else if (SqueezeJS.Controller.playerStatus.playlist_tracks == 0) {
					action = 'play';
				}
				
				this.handleFile(action);
			}
			else {
				Ext.Msg.alert(SqueezeJS.string('noItemsFound'), SqueezeJS.string('plugin_dndplay_no_items'));
			}
		},
		
		handleDragOver: function(ev) {
			var evt = ev.browserEvent;
			evt.stopPropagation();
		    evt.preventDefault();
		    evt.dataTransfer.dropEffect = 'copy';
		},
		
		handleFile: function(action) {
			var file = this.queue.shift();
			
			if (!file) {
				// nothing left to do - stop the status update task
				Ext.TaskMgr.stop(this.statusUpdater);
				this.statusUpdater = null;
				SqueezeJS.Controller.getStatus();
				return;
			}

			if (file.name)
				this.showBriefly(SqueezeJS.string('adding_to_playlist') + ' ' + file.name);

			SqueezeJS.Controller.playerRequest({
				params: ['playlist', (action || 'add') + 'match', 'name:' + file.name, 'size:' + (file.size || 0), 'timestamp:' + Math.floor(file.lastModified / 1000), 'type:' + (file.type || 'unk')],
				success: function(response){
					if (!this.statusUpdater) {
						SqueezeJS.Controller.getStatus();
						this.statusUpdater = {
							run: SqueezeJS.Controller.getStatus,
							interval: 2000
						};
						Ext.TaskMgr.start(this.statusUpdater);
					}

					if (response && response.responseText) {
						response = Ext.util.JSON.decode(response.responseText);

						if (response && response.result) {
							if ( response.result.maxUploadSize && Number.isInteger(response.result.maxUploadSize) ) {
								SqueezeJS.DnD.maxUploadSize = response.result.maxUploadSize;
							}
							
							if (response.result.upload) {
								if (file.size && file.size > SqueezeJS.DnD.maxUploadSize) {
									Ext.Msg.alert(
										file.name, 
										String.format(
											SqueezeJS.string('fileTooLarge'), 
											Math.floor(file.size / 1024 / 1024) + 'MB', 
											Math.floor(SqueezeJS.DnD.maxUploadSize / 1024 / 1024) + 'MB'
										)
									);
								}
								else {
									file.key = response.result.upload;
									this.uploadFile(file, action);
									return;
								}
							}
							else if (response.result.error) {
								Ext.Msg.alert(
									file.name, 
									response.result.error
								);
							}
						}
					}

					this.handleFile();
				},
				scope: this
			});
		},
		
		uploadFile: function(file, action) {
			var xhr = new XMLHttpRequest();    // den AJAX Request anlegen
			xhr.open('POST', '/plugins/dndplay/upload');    // Angeben der URL und des Requesttyps
			
			var scope = this;
			xhr.onreadystatechange = function() {
				if (xhr.readyState == 4) {
					if (xhr.responseText) {
						var response = Ext.util.JSON.decode(xhr.responseText);
						if (response && response.error) {
							Ext.Msg.alert(SqueezeJS.string('noItemsFound'), response.error);
						}
					}
					this.handleFile();
				}
			}.createDelegate(this);
			
			var progress = -1;
			xhr.upload.addEventListener("progress", function(e) {
				var p = parseInt(e.loaded / e.total * 100);
				// only update progress information when the value has changed
				if (p > progress) {
					this.showBriefly(String.format(SqueezeJS.string('adding_to_playlist') + ' {0} ({1}%)', file.name, p));
					progress = p;
				}
			}.createDelegate(this), false);
			
			var formdata = new FormData();    // Anlegen eines FormData Objekts zum Versenden unserer Datei
			formdata.append('action', action || 'add');
			formdata.append('name', file.name);
			formdata.append('size', file.size);
			formdata.append('type', file.type);
			formdata.append('timestamp', Math.floor(file.lastModified / 1000))
			
			if (file.key)
				formdata.append('key', file.key);
			
			formdata.append('uploadfile', file);  // Anhängen der Datei an das Objekt
			xhr.send(formdata); 
		},
		
		// use main status area, but don't use showBriefly to get more frequent updates without the flicker
		showBriefly: function(text) {
			var statusArea = Main.showBrieflyArea;
			var statusAreaEl = statusArea ? statusArea.getEl() : null;
			if (statusAreaEl && statusAreaEl.hasActiveFx()) {
				statusAreaEl.stopFx();
				statusArea.template.overwrite(statusAreaEl, { msg: text });
				statusAreaEl.pause(2).fadeOut();
			}
			else {
				SqueezeJS.Controller.showBriefly(text);
			}
		}
	};

	Ext.onReady(function() {
		FileDnD.init();
	}, FileDnD);
}