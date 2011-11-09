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
	
		tell application "GrowlHelperApp"
			set the allNotificationsList to {"Squeezebox Notification"}
			set the enabledNotificationsList to {"Squeezebox Notification"}
			
			register as application "Logitech Media Server" all notifications allNotificationsList default notifications enabledNotificationsList
		
			notify with name "Squeezebox Notification" title "Logitech Media Server" description msg application name "Logitech Media Server" image from location "file:///Library/PreferencePanes/Squeezebox.prefPane/Contents/Resources/icon.icns"
		end tell
		
		return "1"
	
	end if

end run
