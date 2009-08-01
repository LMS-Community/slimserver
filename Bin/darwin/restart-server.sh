#! /bin/sh
SCRIPTS="../platforms/osx/Preference Pane"

if [ ! -e "$SCRIPTS/stop-server.sh" ]; then
	SCRIPTS="../Resources"
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
