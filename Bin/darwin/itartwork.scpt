#!/usr/bin/osascript

-- Export downloaded iTunes artwork to a given folder
-- ./itartwork.osa /path/to/folder

-- Notes:
-- AppleScript doesn't have any way of printing to stdout, so there is no output from this program
-- until it completes, and then all output is printed at once.
--
-- To improve performance, only one image is exported for each album.
--
-- TODO: check iTunes version?
-- Dialog box telling user we are going to open iTunes?  Hard, requires localization

on run argv
	set linefeed to "\n"
	
	-- What I would give for getopt in AppleScript...
	
	set usage to "Usage: itartwork.scpt PATH [--all | --iter INDEX | --single SEARCH_STRING TRACK_ID | --shutdown ] [ --skip-unchecked ]"
	
	if count of argv < 2 then return usage
	
	set exportDir to item 1 of argv
	set mode to item 2 of argv
	
	-- Add trailing slash if needed
	if exportDir does not end with "/" then
		set exportDir to exportDir & "/"
	end if
	
	set macPath to POSIX file exportDir as text
	
	set skipUnchecked to false
	
	-- If iTunes is not already running, cache the fact in a file
	-- This will be used later if someone calls --shutdown
	set shutdowniTunesCache to macPath & "shutdowniTunes.cache"
	if mode does not equal "--shutdown" then
		try
			tell application "Finder" to set procList to name of processes
			if procList does not contain "iTunes" then
				set fp to open for access shutdowniTunesCache with write permission
				write 1 to fp as integer
				close access fp
			end if
		end try
	end if
	
	if mode equal "--all" then
		if count of argv is 3 then
			if item 3 of argv equal "--skip-unchecked" then
				set skipUnchecked to true
			end if
		end if
		
		return exportDownloadedArtwork(macPath, skipUnchecked, -1)
	else if mode equal "--iter" then
		if count of argv < 3 then return usage
		
		set iterIndex to item 3 of argv as number
		
		if count of argv is 4 then
			if item 4 of argv equal "--skip-unchecked" then
				set skipUnchecked to true
			end if
		end if
		
		return exportDownloadedArtwork(macPath, skipUnchecked, iterIndex)
	else if mode equal "--single" then
		if count of argv < 4 then return usage
		
		set searchString to item 3 of argv
		set pid to item 4 of argv
		
		-- No need for --skip-unchecked in single mode
		
		return exportSingleArtwork(macPath, searchString, pid)
	else if mode equal "--shutdown" then
		-- Shutdown iTunes if the cache file is present
		try
			set sic to open for access shutdowniTunesCache
			set shutdowniTunes to read sic as integer
			close access sic
			if shutdowniTunes equal 1 then
				tell application "iTunes" to quit
			end if
			do shell script "rm " & POSIX path of shutdowniTunesCache
			return "iTunes closed automatically"
		on error errorMessage
			return "iTunes not closed automatically: " & errorMessage
 		end try
	else
		return usage
	end if
end run

on exportDownloadedArtwork(macPath, skipUnchecked, iterIndex)
	set output to ""
	set albumList to {}
	set albumListCache to macPath & "albumList.cache"
	set endIter to false
	set linefeed to "\n"
	
	tell application "iTunes"
		set totalCount to count of every track in library playlist 1
		set trackCount to 1
		
		if iterIndex >= 1 then
			set trackCount to iterIndex
			
			-- Load albumList cache if present
			try
				set alc to open for access albumListCache
				set albumList to read alc as list
				close access alc
			end try
		end if
		
		repeat while trackCount <= totalCount
			-- Skip unchecked tracks if requested
			set shouldSkip to false
			
			if skipUnchecked is true then
				if enabled of track trackCount of library playlist 1 is false
					set shouldSkip to true
				end if
			end if
			
			if shouldSkip is false
				-- Avoid tracks of an album we already processed (matches on album name + artist name)
				set theAlbum to album of track trackCount of library playlist 1 as string
				set theAlbum to theAlbum & " - " & artist of track trackCount of library playlist 1 as string
			
				if albumList does not contain theAlbum then
					try
						set theArtwork to artwork 1 of track trackCount of library playlist 1
						if downloaded of theArtwork is true then
							set trackId to the (persistent ID of track trackCount)
							set theFormat to the (format of theArtwork) as text
							log "Exporting downloaded artwork for ID " & trackId & ": " & theAlbum
							set output to output & "Exporting downloaded artwork for ID " & trackId & ": " & theAlbum
							set thePic to the (raw data of theArtwork)
							set exportOutput to my exportArtwork(thePic, trackId, theFormat, macPath)
							set output to output & exportOutput
						
							-- This needs to be inside the check for downloaded, because
							-- albums may only store downloaded artwork with some tracks on
							-- an album
							copy theAlbum to the end of albumList
							
							-- return after each downloaded artwork is found, if iterating
							set endIter to true
						end if
					on error errorMessage
						log "Error getting artwork for track " & trackCount & ": " & errorMessage
						set output to output & "Error getting artwork for track " & trackCount & ": " & errorMessage & linefeed
					end try
				end if
			else
				log "Skipping unchecked track " & (name of track trackCount of library playlist 1) as string
				set output to output & "Skipping unchecked track " & (name of track trackCount of library playlist 1) as string & linefeed
			end if
					
			if iterIndex >= 1 then
				-- End anyway after 100 items so caller can update progress in a reasonable amount of time
				if trackCount - iterIndex > 100 then
					set endIter to true
				end if
				
				-- End if we processed the last item
				if trackCount equal totalCount then
					set endIter to true
				end if
				
				if endIter is true then
					-- Save albumList to cache file, needed to avoid the next iter run
					-- exporting duplicate albums
					try
						set fp to open for access albumListCache with write permission
						write albumList to fp as list
						close access fp
					on error errorMessage
						log "Error: Unable to write " & albumListCache & ": " & errorMessage
						set output to output & "  Error: Unable to write " & albumListCache & ": " & errorMessage & linefeed
					end try
					
					-- Cleanup cache file when done
					if trackCount equal totalCount then
						try
							do shell script "rm " & POSIX path of albumListCache
						end try
					end if
					
					set counter to (trackCount & "/" & totalCount) as string
					return counter & " " & output
				end if
			end if
			
			set trackCount to trackCount + 1
		end repeat
	end tell	
	return output
end exportDownloadedArtwork

on exportSingleArtwork(macPath, searchString, pid)
	set output to ""
	set linefeed to "\n"
	
	tell application "iTunes"
		-- You can't directly search for a persistent ID, so do a name search first to narrow it down
		set searchResults to (search library playlist 1 for searchString)
		set totalCount to count of searchResults
		set searchCount to 1
		repeat while searchCount <= totalCount
			set theTrack to item searchCount of searchResults
			if persistent ID of theTrack equal pid then
				try
					set theAlbum to album of theTrack as string
					set theAlbum to theAlbum & " - " & artist of theTrack as string
					set theArtwork to artwork 1 of theTrack
					set theFormat to the (format of theArtwork) as text
										
					set thePic to the (raw data of theArtwork)
					set exportOutput to my exportArtwork(thePic, pid, theFormat, macPath)
					set output to "OK " & exportOutput
					return output
				on error errorMessage
					log "Error getting artwork: " & errorMessage
					set output to output & "Error getting artwork: " & errorMessage & linefeed
					return output
				end try
			end if
			set searchCount to searchCount + 1
		end repeat
	end tell
	return "No results found"
end exportSingleArtwork

on exportArtwork(thePic, trackId, theFormat, macPath)
	set ext to ".png"
	set linefeed to "\n"

	if theFormat contains "JPEG" then set ext to ".jpg"
	set exportFile to macPath & trackId & ext

	try
		set fp to open for access file exportFile with write permission
		write thePic to fp
		close access fp
		set output to trackId & ext & linefeed
	on error errorMessage
		log "Error: Unable to write " & exportFile & ": " & errorMessage
		set output to "Unable to write " & POSIX path of exportFile & ": " & errorMessage & linefeed
	end try
	return output
end exportArtwork

