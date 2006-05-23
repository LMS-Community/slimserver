package Plugins::RPC;

# $Id$

use strict;
use HTTP::Status;
use JSON;
use RPC::XML::Parser;
use Scalar::Util qw(blessed);

use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my %rpcFunctions = (
	'system.listMethods'	=>	\&listMethods,
	'slim.doCommand'	=>	\&doCommand,
	'slim.getPlayers'	=> 	\&getPlayers,
	'slim.getPlaylist'	=>	\&getPlaylist,
	'slim.getStrings'	=>	\&getStrings
);

sub listMethods {
	my @resp = keys %rpcFunctions;
	return \@resp;
}

sub doCommand {
	my $reqParams = shift;
	my $client = undef;

	my $commandargs = $reqParams->[1];

	return RPC::XML::fault->new(2, 'invalid arguments') unless ($commandargs && ref($commandargs) eq 'ARRAY');

	my $playername = scalar ($reqParams->[0]);
	$client = Slim::Player::Client::getClient($playername);

	my @resp = Slim::Control::Request::executeLegacy($client, $commandargs);

	return \@resp;
}

sub getPlaylist {
	my $reqParams = shift;
	my @returnArray;

	return RPC::XML::fault->new(3, 'insufficient parameters') unless (ref($reqParams) eq 'ARRAY' && @$reqParams >= 3); 

	my $playername = scalar ($reqParams->[0]);

	my $client = Slim::Player::Client::getClient($playername);

	if (!$client) {
		return RPC::XML::fault->new(3, 'invalid player') unless $client; 
	}

	my $p1 = scalar($reqParams->[1]);
	my $p2 = scalar($reqParams->[2]);

	my $songCount = Slim::Player::Playlist::count($client);

	return \@returnArray if ($songCount == 0);

	my ($valid, $start, $end) = Slim::Control::Request::normalize(undef, $p1, $p2, $songCount);

	if ($valid) {

		my $idx;

		for ($idx = $start; $idx <= $end; $idx++) {

			my $track = Slim::Schema->objectForUrl(Slim::Player::Playlist::song($client, $idx));

			if (blessed($track)) {

				push @returnArray, $track;
			}
		}

	} else {
		return RPC::XML::fault->new(2, 'invalid arguments');
	}

	return \@returnArray;
}

sub getStrings {
	my $reqParams = shift;
	my @returnArray;

	for (my $i = 0; $i < @$reqParams; $i++) {
		push @returnArray, string($reqParams->[$i]);
	}

	return \@returnArray;
}

sub getPlayers {
	my @players = Slim::Player::Client::clients();
	my @returnArray;

	for my $player (@players) {
		push @returnArray, {
			"id" => $player->id(),
			"ipport" => $player->ipport(),
			"model" => $player->model(),
			"name" => $player->name(),
			"connected" => $player->connected() ? 'true' : 'false',
		}
	}

	return \@returnArray;
}

sub getDisplayName {    
        return 'PLUGIN_RPC';
}               
                
sub getFunctions {      
        return {};      
}                       

sub webPages {
	my %pages = (
		'rpc.xml' => \&handleReqXML,
		'rpc.js' => \&handleReqJSON,
	);

	$Slim::Web::HTTP::dangerousCommands{\&handleReqJSON} = ".";
	$Slim::Web::HTTP::dangerousCommands{\&handleReqXML} = ".";

	return (\%pages);
}

sub handleReqXML {
	my ($client, $params, $prepareResponseForSending, $httpClient, $response) = @_;
	my $output;

	if (!$params->{content}) {
		$response->code(RC_BAD_REQUEST);
		$response->content_type('text/html');
		$response->header('Connection' => 'close');

		return Slim::Web::HTTP::filltemplatefile('html/errors/400.html');
	}

	my $P = RPC::XML::Parser->new();
	my $req = $P->parse($params->{content});

	return unless $req;

	my $reqname = $req->name();
	my $respobj;

	my @args = map { $_->value() } @{$req->args()};

	if ($rpcFunctions{$reqname}) {
		$respobj = &{$rpcFunctions{$reqname}}(\@args);
	} else {
		$respobj = RPC::XML::fault->new(1, 'no such method');
	}

	if (!$respobj) {
		$respobj = RPC::XML::fault->new(-1, 'unknown error');
	}
	
	my $rpcresponse = RPC::XML::response->new($respobj);
	$output = $rpcresponse->as_string();

	return \$output;
}

sub handleReqJSON {
	my ($client, $params, $prepareResponseForSending, $httpClient, $response) = @_;
	my $output;
	my $input;

	if ($params->{json}) {
		$input = $params->{json};
	} elsif ($params->{content}) {
		$input = $params->{content};
	} else {
		$response->code(RC_BAD_REQUEST);
		$response->content_type('text/html');
		$response->header('Connection' => 'close');

		return Slim::Web::HTTP::filltemplatefile('html/errors/400.html');
	}

	$::d_plugins && msg("JSON request: " . $input . "\n");

	my @resparr;

	my $objlist = jsonToObj($input);
	$objlist = [ $objlist ] if ref($objlist) eq 'HASH';

	if (ref($objlist) ne 'ARRAY') {
		push @resparr, { 'error' => 'malformed request' };
	} else {
		foreach my $obj (@$objlist) {

			my $reqname = $obj->{method};
			if ($rpcFunctions{$reqname}) {
				if (ref($obj->{params}) ne 'ARRAY') {
					push @resparr, { 'error' => 'invalid request', 'id' => $obj->{id} };
				} else {
					my $freturn = &{$rpcFunctions{$reqname}}($obj->{params});
					if (UNIVERSAL::isa($freturn, "RPC::XML::fault")) {
						push @resparr, { 'error' => $freturn->string, 'id' => $obj->{id} };
					} else {
						push @resparr, { 'result' => $freturn, 'id' => $obj->{id} };
					}
				}
			} else {
				push @resparr, { 'error' => 'no such method', 'id' => $obj->{id} };
			}
		}
	}

	my $respobj;

	if (@resparr == 1) {
		$respobj = $resparr[0];
	} else {
		$respobj = \@resparr;
	}

	my $rpcresponse = objToJson($respobj);

	if ($params->{asyncId}) {
		$rpcresponse = "JXTK2.JSONRPC.asyncDispatch(" . $params->{asyncId} . "," . $rpcresponse . ")";
	}

	$::d_plugins && msg("JSON response ready\n");

	return \$rpcresponse;
}

sub strings {
	return "
PLUGIN_RPC
	EN	XML-RPC/JSON-RPC Interface
	ES	Interface XML-RPC/JSON-RPC
";
}

1;
