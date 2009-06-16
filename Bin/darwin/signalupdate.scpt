-- this script will only run on OSX 10.5+, 10.4 would complain about "user interaction not allowed"
on run argv
	
	set msg to ""
	
	if (count of argv) > 0
	
		repeat with arg in argv
			set msg to msg & arg & " "
		end repeat
	
	end if
		
		
	tell application "System Events"
	
		set isRunning to count of (every process whose name is "GrowlHelperApp") > 0
	
	end tell
	
	
	if isRunning and msg is not equal to "" 
	
		
	else
	
		tell application "System Preferences"
		
			set current pane to pane id "com.slimdevices.slim"
		
			activate
		
		end tell
	
	end if

end run
