#!/bin/bash

SERVER_LOG=$HOME/server.log
TIMEOUT=30

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

echo $STATUS | jq -e '.result.version | strings' > /dev/null || exit 1

DATE=$(curl -m1 -sX POST -d '{"id":1,"params":["",["date"]],"method":"slim.request"}' http://localhost:9000/jsonrpc.js)

echo $DATE | jq .

echo $DATE | jq -e '
	.result.date_epoch as $epoch |
	.result.utc_offset_minutes as $offset |
	.result.is_dst as $dst |
	.result.timezone as $timezone |
	($epoch | type == "number" and floor == .) and
	($offset | type == "number" and floor == . and . >= -720 and . <= 840) and
	($dst == 0 or $dst == 1) and
	($timezone | type == "string")
' > /dev/null
