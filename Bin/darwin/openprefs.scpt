#!/usr/bin/osascript


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
			
			register as application "Squeezebox Server" all notifications allNotificationsList default notifications enabledNotificationsList icon of application "SqueezeCenter"
		
			notify with name "Squeezebox Notification" title "Squeezebox Server" description msg application name "Squeezebox Server" sticky true
		end tell
		
	else
	
		tell application "System Preferences"
		
			set current pane to pane id "com.slimdevices.slim"
		
			activate
		
		end tell
	
	end if

end run
