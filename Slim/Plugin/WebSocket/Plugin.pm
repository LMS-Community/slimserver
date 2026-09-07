package Slim::Plugin::WebSocket::Plugin;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024-2026 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use JSON::XS qw(encode_json decode_json);
use Protocol::WebSocket::Handshake::Server;

use Slim::Control::Request;
use Slim::Networking::Select;
use Slim::Utils::Log;
use Slim::Utils::Timers;
use Slim::Web::HTTP;
use Slim::Web::Pages;

# This plugin provides a WebSocket endpoint (/ws) so that clients can send
# CLI-style commands and subscribe to server notifications over a single
# full-duplex connection, similar in spirit to Slim::Plugin::CLI::Plugin but
# framed as JSON over WebSocket instead of newline-terminated text.
#
# Wire format (JSON object per text frame):
#   client -> server
#     {"id":1,"request":["<mac-or-blank>",["cmd","arg1","arg2"]]}
#     {"id":2,"listen":1}                 # 1 = all notifications, 0 = none
#     {"id":3,"subscribe":["playlist"]}   # only these top-level commands
#     {"id":4,"request":["<mac-or-blank>",["status", "-", 1, "subscribe:10"]]}  # subscribe to specific event, get updates every 10 seconds at least
#   server -> client
#     {"id":1,"result":{...}}             # reply to a request
#     {"id":1,"error":"..."}              # request failed
#     {"event":[clientid,["cmd","arg"],{...}]}  # pushed notification

use constant SOURCE => 'WS';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.websocket',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_WEBSOCKET',
});

# one entry per live WebSocket connection, keyed by the http client socket
# .. socket: the socket itself (a hash key is not an object, but the value is)
# .. hs:     Protocol::WebSocket::Handshake::Server, used to build frames
# .. frame:  Protocol::WebSocket::Frame used to accumulate/parse inbound bytes
# .. outbuf: array of pending outbound byte strings
# .. listen: undef (not listening), '*' (all), or [[cmd1,cmd2,...]] filter
our %connections;

# true while we're subscribed to Slim::Control::Request notifications
my $subscribed = 0;

sub initPlugin {
	Slim::Web::Pages->addRawFunction(qr{^/ws$}, \&handleUpgrade);
	Slim::Web::HTTP::addCloseHandler(\&connectionClose);
}

# sub getDisplayName {
# 	return 'PLUGIN_WEBSOCKET';
# }

sub shutdownPlugin {
	foreach my $httpClient (keys %connections) {
		connectionClose($connections{$httpClient}{socket});
	}
}

sub handleUpgrade {
	my ($httpClient, $httpResponse) = @_;

	my $request = $httpResponse->request;
	my $uri = $request->uri;

	if ( lc($request->header('Upgrade') || '') ne 'websocket' ) {
		_rejectUpgrade($httpClient, $httpResponse, 400, 'Expected a WebSocket upgrade request');
		return;
	}

	my $hs = Protocol::WebSocket::Handshake::Server->new_from_psgi({
		HTTP_UPGRADE               => $request->header('Upgrade') || 'websocket',
		HTTP_CONNECTION            => $request->header('Connection') || 'Upgrade',
		HTTP_HOST                  => $request->header('Host'),
		HTTP_ORIGIN                => $request->header('Origin'),
		HTTP_SEC_WEBSOCKET_KEY     => $request->header('Sec-WebSocket-Key'),
		HTTP_SEC_WEBSOCKET_VERSION => $request->header('Sec-WebSocket-Version'),
		SCRIPT_NAME                => '',
		PATH_INFO                  => $uri->path || '/ws',
		QUERY_STRING               => $uri->query || '',
	});

	# new_from_psgi() only parses the headers we already have - feed it an
	# empty body so it finalizes state (and computes Sec-WebSocket-Accept)
	if ( !$hs->parse('') || $hs->error || !$hs->is_done || $hs->version ne 'draft-ietf-hybi-17' ) {
		_rejectUpgrade($httpClient, $httpResponse, 400, 'Unsupported or invalid WebSocket handshake');
		return;
	}

	# disable our normal HTTP timeout handler for this connection, since we're now
	# going to be using our own read/write handlers and the connection will stay
	# open indefinitely until the client closes it or we detect an error
	Slim::Utils::Timers::killTimers($httpClient, \&Slim::Web::HTTP::closeHTTPSocket);

	$httpClient->syswrite($hs->to_string);

	$connections{$httpClient} = {
		socket => $httpClient,
		hs     => $hs,
		frame  => $hs->build_frame,
		outbuf => [],
	};

	# take over the socket - stop the normal HTTP request parser from
	# running on subsequent (non-HTTP) bytes on this connection
	Slim::Networking::Select::addRead($httpClient, \&connectionRead);
	Slim::Networking::Select::addError($httpClient, \&connectionClose);

	main::INFOLOG && $log->info("WebSocket connection established ($httpClient)");
}

sub _rejectUpgrade {
	my ($httpClient, $httpResponse, $code, $message) = @_;

	$httpResponse->code($code);
	$httpResponse->content_type('text/plain');
	$httpResponse->content_ref(\$message);
	$httpResponse->header('Connection' => 'close');

	$httpClient->send_response($httpResponse);
	Slim::Web::HTTP::closeHTTPSocket($httpClient);
}

sub connectionRead {
	my $httpClient = shift;
	my $conn = $connections{$httpClient} || return;

	use bytes;

	my $indata = '';
	my $bytesRead = $httpClient->sysread($indata, 65536);

	if ( !defined($bytesRead) || $bytesRead == 0 ) {
		connectionClose($httpClient);
		return;
	}

	my $frame = $conn->{frame};
	$frame->append($indata);

	while ( defined(my $message = $frame->next) ) {
		if ( $frame->is_close ) {
			sendBytes($httpClient, $conn->{hs}->build_frame(type => 'close', masked => 0)->to_bytes);
			connectionClose($httpClient);
			return;
		}
		elsif ( $frame->is_ping ) {
			sendBytes($httpClient, $conn->{hs}->build_frame(type => 'pong', buffer => $message, masked => 0)->to_bytes);
		}
		elsif ( $frame->is_pong ) {
			# keep-alive acknowledgement, nothing to do
		}
		elsif ( $frame->is_text ) {
			my $obj = eval { decode_json($message) };

			if ( $@ || ref $obj ne 'HASH' ) {
				$log->warn("Ignoring malformed WebSocket message: $message");
				next;
			}

			dispatchMessage($httpClient, $obj);
		}
	}
}

# push raw already-framed bytes (ping/pong/close) to a connection
sub sendBytes {
	my ($httpClient, $bytes) = @_;
	my $conn = $connections{$httpClient} || return;

	push @{ $conn->{outbuf} }, $bytes;
	Slim::Networking::Select::addWrite($httpClient, \&connectionFlush);
}

# JSON-encode $obj, frame it and queue it for sending
sub sendMessage {
	my ($httpClient, $obj) = @_;
	my $conn = $connections{$httpClient} || return;

	my $json = eval { encode_json($obj) };

	if ( $@ ) {
		logError("Failed to encode WebSocket message: $@");
		return;
	}

	sendBytes($httpClient, $conn->{hs}->build_frame(buffer => $json, type => 'text', masked => 0)->to_bytes);
}

sub connectionFlush {
	my $httpClient = shift;
	my $conn = $connections{$httpClient} || return;

	my $bytes = shift @{ $conn->{outbuf} };
	return unless defined $bytes;

	my $sent = $httpClient->syswrite($bytes);

	if ( !defined $sent ) {
		connectionClose($httpClient);
		return;
	}

	if ( $sent < length($bytes) ) {
		unshift @{ $conn->{outbuf} }, substr($bytes, $sent);
	}

	Slim::Networking::Select::removeWrite($httpClient) unless @{ $conn->{outbuf} };
}

sub connectionClose {
	my $httpClient = shift;

	# fires for every HTTP connection close (registered globally), so
	# only act on sockets we actually took over
	my $conn = delete $connections{$httpClient} || return;

	Slim::Networking::Select::removeRead($httpClient);
	Slim::Networking::Select::removeWrite($httpClient);
	Slim::Networking::Select::removeError($httpClient);

	Slim::Control::Request::unregisterAutoExecute($httpClient);

	_manageSubscription();

	close $httpClient;

	main::INFOLOG && $log->info("WebSocket connection closed ($httpClient)");
}

################################################################################
# COMMAND DISPATCH
################################################################################

sub dispatchMessage {
	my ($httpClient, $obj) = @_;
	my $conn = $connections{$httpClient} || return;
	my $id = $obj->{id};

	if ( exists $obj->{listen} ) {
		$conn->{listen} = $obj->{listen} ? '*' : undef;
		_manageSubscription();
		return;
	}

	if ( exists $obj->{subscribe} ) {
		my $terms = $obj->{subscribe};
		$conn->{listen} = (ref $terms eq 'ARRAY' && @$terms) ? [ $terms ] : undef;
		_manageSubscription();
		return;
	}

	if ( my $req = $obj->{request} ) {
		my ($clientid, $cmdArgs) = @$req;
		undef $clientid unless defined $clientid && length $clientid;

		if ( ref $cmdArgs ne 'ARRAY' ) {
			sendMessage($httpClient, { id => $id, error => 'missing request command array' });
			return;
		}

		my $request = Slim::Control::Request->new($clientid, $cmdArgs, 1);

		if ( !defined $request ) {
			sendMessage($httpClient, { id => $id, error => 'unable to create request' });
			return;
		}

		$request->source(SOURCE);
		$request->connectionID($httpClient);
		$request->privateData($id);
		# lets Slim::Control::Request re-invoke us for "subscribe:<n>" style requests
		$request->autoExecuteCallback(\&requestWrite);

		$request->execute();

		if ( $request->isStatusError() ) {
			sendMessage($httpClient, { id => $id, error => $request->getStatusText });
			return;
		}

		if ( $request->isStatusProcessing() ) {
			$request->callbackParameters(\&requestWrite);
			return;
		}

		requestWrite($request);
		return;
	}

	sendMessage($httpClient, { id => $id, error => 'unrecognized message' });
}

# writes the result of a request back to its connection; used both as an
# immediate reply and as the async/subscribe callback (which passes the
# connectionID as a 2nd arg, see Slim::Control::Request::__autoexecute)
sub requestWrite {
	my $request = shift;
	my $httpClient = shift || $request->connectionID();

	return unless $httpClient && $connections{$httpClient};

	sendMessage($httpClient, {
		id     => $request->privateData(),
		result => $request->getResults,
	});
}


# subscribes or unsubscribes to the Request notification system, depending
# on whether any connection still wants to listen
sub _manageSubscription {
	my $needed = 0;

	foreach my $httpClient (keys %connections) {
		if ( defined $connections{$httpClient}{listen} ) {
			$needed = 1;
			last;
		}
	}

	if ( $needed && !$subscribed ) {
		Slim::Control::Request::subscribe(\&notificationCallback);
		$subscribed = 1;
	}
	elsif ( !$needed && $subscribed ) {
		Slim::Control::Request::unsubscribe(\&notificationCallback);
		$subscribed = 0;
	}
}

# single global notification handler, fans out to every listening connection
sub notificationCallback {
	my $request = shift;

	foreach my $httpClient (keys %connections) {
		my $conn = $connections{$httpClient};

		next unless defined $conn->{listen};

		my $socket = $conn->{socket};

		# don't echo a command back to the connection that issued it
		next if $request->source() && $request->source() eq SOURCE && $request->connectionID() eq $socket;

		if ( ref $conn->{listen} eq 'ARRAY' ) {
			next unless $request->isCommand($conn->{listen});
		}

		sendMessage($socket, {
			event => [ $request->clientid, _requestTerms($request), $request->getResults ],
		});
	}
}

sub _requestTerms {
	my $request = shift;
	my @terms;

	for ( my $i = 0; $i < $request->getRequestCount(); $i++ ) {
		push @terms, $request->getRequest($i);
	}

	return \@terms;
}

1;
