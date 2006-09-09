package Plugins::RPC;

# $Id$

use strict;
use HTTP::Status;
use JSON::Syck;
use RPC::XML::Parser;
use Scalar::Util qw(blessed);

use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my %rpcFunctions = (
	'system.listMethods' => \&listMethods,
	'slim.doCommand'     => \&doCommand,
	'slim.getPlayers'    => \&getPlayers,
	'slim.getPlaylist'   => \&getPlaylist,
	'slim.getStrings'    => \&getStrings
);

sub listMethods {

	return [ keys %rpcFunctions ];
}

sub doCommand {
	my $reqParams = shift;

	my $commandargs = $reqParams->[1];

	if (!$commandargs || ref($commandargs) ne 'ARRAY') {

		return RPC::XML::fault->new(2, 'invalid arguments');
	}

	my $playername = scalar ($reqParams->[0]);
	my $client     = Slim::Player::Client::getClient($playername);

	return [ Slim::Control::Request::executeLegacy($client, $commandargs) ];
}

sub getPlaylist {
	my $reqParams = shift;

	if (!ref($reqParams) eq 'ARRAY' || @$reqParams < 3) {

		return RPC::XML::fault->new(3, 'insufficient parameters');
	}

	my $playername = scalar ($reqParams->[0]);

	my $client = Slim::Player::Client::getClient($playername);

	if (!$client) {
		return RPC::XML::fault->new(3, 'invalid player') unless $client; 
	}

	my $p1 = scalar($reqParams->[1]);
	my $p2 = scalar($reqParams->[2]);

	my $songCount   = Slim::Player::Playlist::count($client);
	my @returnArray = ();

	if ($songCount == 0 || $p1 >= $songCount) {
		return \@returnArray;
	}

	my ($valid, $start, $end) = Slim::Control::Request::normalize(undef, $p1, $p2, $songCount);

	if (!$valid) {
		return RPC::XML::fault->new(2, 'invalid arguments');
	}

	for (my $idx = $start; $idx <= $end; $idx++) {

		my $track = Slim::Schema->rs('Track')->objectForUrl(Slim::Player::Playlist::song($client, $idx));

		if (!blessed($track)) {
			next;
		}

		my @contribList = ();

		for my $contributor ($track->contributors->all) {

			push @contribList, { $contributor->get_columns };
		}

		my %data  = $track->get_columns;

		$data{'contributors'} = \@contribList;
		$data{'album'}        = { $track->album->get_columns } if $track->album;

		push @returnArray, \%data;
	}

	return \@returnArray;
}

sub getStrings {
	my $reqParams = shift;

	return [ map { string($_) } @$reqParams ];
}

sub getPlayers {
	my @returnArray = ();

	for my $player (Slim::Player::Client::clients()) {

		push @returnArray, {
			'id'        => $player->id,
			'ipport'    => $player->ipport,
			'model'     => $player->model,
			'name'      => $player->name,
			'connected' => $player->connected ? 'true' : 'false',
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
		'rpc.js'  => \&handleReqJSON,
	);

	$Slim::Web::HTTP::dangerousCommands{\&handleReqJSON} = '.';
	$Slim::Web::HTTP::dangerousCommands{\&handleReqXML}  = '.';

	return \%pages;
}

sub handleReqXML {
	my ($client, $params, $prepareResponseForSending, $httpClient, $response) = @_;

	if (!$params->{'content'}) {

		$response->code(RC_BAD_REQUEST);
		$response->content_type('text/html');
		$response->header('Connection' => 'close');

		return Slim::Web::HTTP::filltemplatefile('html/errors/400.html');
	}

	my $P   = RPC::XML::Parser->new();
	my $req = $P->parse($params->{'content'}) || return;

	my $reqname = $req->name;
	my $respobj;

	my @args = map { $_->value } @{$req->args};

	if ($rpcFunctions{$reqname}) {
		$respobj = &{$rpcFunctions{$reqname}}(\@args);
	} else {
		$respobj = RPC::XML::fault->new(1, 'no such method');
	}

	if (!$respobj) {
		$respobj = RPC::XML::fault->new(-1, 'unknown error');
	}

	my $rpcresponse = RPC::XML::response->new($respobj);
	my $output      = $rpcresponse->as_string();

	return \$output;
}

sub handleReqJSON {
	my ($client, $params, $prepareResponseForSending, $httpClient, $response) = @_;
	my $output;
	my $input;

	if ($params->{'json'}) {
		$input = $params->{'json'};
	} elsif ($params->{'content'}) {
		$input = $params->{'content'};
	} else {
		$response->code(RC_BAD_REQUEST);
		$response->content_type('text/html');
		$response->header('Connection' => 'close');

		return Slim::Web::HTTP::filltemplatefile('html/errors/400.html');
	}

	$::d_plugins && msg("JSON request: " . $input . "\n");

	my @resparr = ();

	my $objlist = JSON::Syck::Load($input);
	   $objlist = [ $objlist ] if ref($objlist) eq 'HASH';

	if (ref($objlist) ne 'ARRAY') {

		push @resparr, { 'error' => 'malformed request' };

	} else {

		foreach my $obj (@$objlist) {

			my $reqname = $obj->{'method'};

			if ($rpcFunctions{$reqname}) {

				if (ref($obj->{'params'}) ne 'ARRAY') {

					push @resparr, { 'error' => 'invalid request', 'id' => $obj->{'id'} };

				} else {

					my $freturn = &{$rpcFunctions{$reqname}}($obj->{'params'});

					if (UNIVERSAL::isa($freturn, "RPC::XML::fault")) {

						push @resparr, { 'error' => $freturn->string, 'id' => $obj->{'id'} };

					} else {

						push @resparr, { 'result' => $freturn, 'id' => $obj->{'id'} };
					}
				}

			} else {

				push @resparr, { 'error' => 'no such method', 'id' => $obj->{'id'} };
			}
		}
	}

	my $respobj     = scalar @resparr == 1 ? $resparr[0] : \@resparr;
	my $rpcresponse = JSON::Syck::Dump($respobj);

	if ($params->{'asyncId'}) {
		$rpcresponse = "JXTK2.JSONRPC.asyncDispatch(" . $params->{'asyncId'} . "," . $rpcresponse . ")";
	}

	$::d_plugins && msg("JSON response ready\n");

	return \$rpcresponse;
}

sub strings {
	return "
PLUGIN_RPC
	EN	XML-RPC/JSON-RPC Interface
	ES	Interface XML-RPC/JSON-RPC
	NL	XML-RPC/JSON-RPC interface
";
}

1;
