var ss = new JXTK2.JSONRPC.Proxy('/plugins/RPC/rpc.js');
var players;
var loadState = 0;

var globalStrings = [ "FROM", "BY", "EMPTY" ];

var loadSteps = [
	{ str : "Initializing Home...",		func : initHome		},
	{ str : "Initializing Status...",	func : initStatus	},
	{ str : "Initializing Playlist...",	func : initPlaylist	},
	{ str : "Downloading Player List...",	func : initPlayerList	},
	{ str : "Downloading Strings...",	func : getStrings	},
	{ str : "Loading Playlist...",		func : getPlaylistInit	},
	{ str : "Loading Status...",		func : getStatusPeriodically	},
	{ str : "Loading Home...",		func : loadHome		}
];

function mainload() {
	if (loadSteps[loadState]) {
		document.getElementById("loading").firstChild.firstChild.data = loadSteps[loadState].str;
		var rv = loadSteps[loadState].func();
		if (rv == true) {
			// abort
			return false;
		}

		loadState++;

		// if the init function returns {async: true}, it'll handle
		// re-calling mainload on its own. getPlaylistInit does this.
		if (!(rv && rv.async)) {
			setTimeout(mainload, 50);
		}
	} else {
		document.getElementsByTagName("body")[0].className = "mainpage";
		document.getElementById("loading").style.display = "none";
		JXTK2.Key.attach(document);
	}
}

function initPlayerList() {
	getPlayerListContinue(ss.call("slim.getPlayers"));

	setInterval(function() {
		ss.call("slim.getPlayers", [], getPlayerListContinue);
	}, 9700);
}

function getPlayerListContinue(res) {
	var players = res.result;

        var indexToSelect = 0;

	for (var i = 0; i < players.length; i++) {
		var pli = players[i];

		pli.value = pli.id;
		if (pli.id == curPlayer) {
               	        indexToSelect = i;
		}
	}

        if (players.length <= 1) {
                playerlistbox.getEl().style.visibility = "hidden";
        } else {
                playerlistbox.getEl().style.visibility = "visible";
        }

        playerlistbox.update(players);
        playerlistbox.selectIndex(indexToSelect);

	if (!curPlayer && players[indexToSelect]) curPlayer = players[indexToSelect].id;
}

function getStrings() {
	var stringlist = ss.call("slim.getStrings", globalStrings).result;

	for (var i = 0; i < globalStrings.length; i++) {
		JXTK2.String.registerString(globalStrings[i], stringlist[i]);
	}
}

function unCLI(arr) {
	var obj = new Object();
	for (var i = 0; i < arr.length; i++) {
		var ti = arr[i].split(':');
		obj[ti[0]] = ti[1];
	}
	return obj;
}

function handlekey(e) {
	JXTK2.Key.handleEvent(e);
}

function abortkey(e) {
}

