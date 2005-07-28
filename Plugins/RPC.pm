package Plugins::RPC;

use RPC::XML::Parser;

use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Scan;

my %rpcFunctions = (
	'system.listMethods'	=>	\&listMethods,
	'slim.doCommand'	=>	\&doCommand,
);

sub listMethods {
	return RPC::XML::array->new(keys %rpcFunctions);
}

sub doCommand {
	my $reqParams = shift;
	my $client = undef;

	my $commandargs = $reqParams->[1];

	return RPC::XML::fault->new(2, 'invalid arguments') unless $commandargs;
	return RPC::XML::fault->new(2, 'invalid arguments') unless $commandargs->isa("RPC::XML::array");

	if ($reqParams->[0] && $reqParams->[0]->isa("RPC::XML::string")) {
		$client = Slim::Player::Client::getClient($reqParams->[0]->value());
	} 

	my @resp = Slim::Control::Command::execute($client, $commandargs->value(), undef, undef);

	return RPC::XML::array->new(@resp);
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

	if ($rpcFunctions{$reqname}) {
		$respobj = &{$rpcFunctions{$reqname}}($req->args());
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


sub strings {
	return "
PLUGIN_RPC
	EN	XML-RPC Interface
";
}

1;
