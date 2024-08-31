#!/bin/sh
# the menu bar item is expecting the scripts in the parent folder
SCRIPTS=".."

# the pref pane is expecting it next door
if [ ! -e "$SCRIPTS/stop-server.sh" ]; then
	SCRIPTS="../Resources"
fi

# fallback for easy testing
if [ ! -e "$SCRIPTS/stop-server.sh" ]; then
    SCRIPTS="../platforms/osx/Preference Pane"
fi

"$SCRIPTS/stop-server.sh"

# Wait for it to stop

for (( i = 0 ; i < 10 ; i++ ))
do
    SERVER_RUNNING=`ps -axww | grep "slimserver\.pl\|slimserver\|squeezecenter\.pl" | grep -v grep | cat`
    if [ z"$SERVER_RUNNING" == z ] ; then
	break
    fi
    sleep 1
done

"$SCRIPTS/start-server.sh"
