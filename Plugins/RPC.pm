package Plugins::RPC;

use RPC::XML::Parser;
use JSON;

use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Scan;
use Slim::Utils::Strings qw(string);

my %rpcFunctions = (
	'system.listMethods'	=>	\&listMethods,
	'slim.doCommand'	=>	\&doCommand,
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

	my @resp = Slim::Control::Command::execute($client, $commandargs, undef, undef);

	return \@resp;
}

sub getPlaylist {
	my $reqParams = shift;
	my $client, $p0, $p1;
	my @returnArray;

	return RPC::XML::fault->new(3, 'insufficient parameters') unless (ref($reqParams) eq 'ARRAY' && @$reqParams >= 3); 

	my $playername = scalar ($reqParams->[0]);

	$client = Slim::Player::Client::getClient($playername);

	if (!$client) {
		return RPC::XML::fault->new(3, 'invalid player') unless $client; 
	}

	$p1 = scalar($reqParams->[1]);
	$p2 = scalar($reqParams->[2]);

	my $songCount = Slim::Player::Playlist::count($client);

	return \@returnArray if ($songCount == 0);

	my ($valid, $start, $end) = Slim::Control::Command::normalize($p1, $p2, $songCount);

	if ($valid) {
		my $ds = Slim::Music::Info::getCurrentDataStore();

		for ($idx = $start; $idx <= $end; $idx++) {
			my $track = Slim::Player::Playlist::song($client, $idx);

			# place the contributors all in an array for easy access
			my @contribs = $track->contributors();
			$track->{contributors} = \@contribs;
			$_->name() foreach @contribs;

			# make sure to read the track and album data from the db as well
			$track->album()->title();
			$track->title();

			push @returnArray, $track;
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

sub getDisplayName {    
        return 'PLUGIN_RPC';
}               
                
sub getFunctions {      
        return {};      
}                       

sub webPages {
	my %pages = (
		'rpc.xml' => sub { handleReqXML(@_)},
		'rpc.js' => sub { handleReqJSON(@_)},
	);

	return (\%pages);
}

sub handleReqXML {
	my ($client, $params, $prepareResponseForSending, $httpClient, $response) = @_;
	my $output;

	if (!$params->{content}) {
		$response->code(RC_BADREQUEST);
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

	if (!$params->{content}) {
		$response->code(RC_BADREQUEST);
		$response->content_type('text/html');
		$response->header('Connection' => 'close');

		return Slim::Web::HTTP::filltemplatefile('html/errors/400.html');
	}

	my $obj = jsonToObj($params->{content});

	my $reqname = $obj->{method};
	my $respobj;

	if ($rpcFunctions{$reqname}) {
		my $freturn = &{$rpcFunctions{$reqname}}($obj->{params});
		if (UNIVERSAL::isa($freturn, "RPC::XML::fault")) {
			$respobj = { 'error' => $freturn->string, 'id' => $obj->{id} };
		} else {
			$respobj = { 'result' => $freturn, 'id' => $obj->{id} };
		}
	} else {
		$respobj = { 'error' => 'no such method', 'id' => $obj->{id} };
	}

	if (!$respobj) {
		$respobj = { 'error' => 'unknown error', 'id' => $obj->{id} };
	}

	my $rpcresponse = objToJson($respobj);

	return \$rpcresponse;
}

sub strings {
	return "
PLUGIN_RPC
	EN	XML-RPC/JSON-RPC Interface
";
}

1;
