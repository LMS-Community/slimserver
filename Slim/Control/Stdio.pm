package Slim::Control::Stdio;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);

use Slim::Networking::Select;
use Slim::Utils::Strings qw(string);
use Slim::Utils::OSDetect;
use Slim::Utils::Misc;

use vars qw($stdin);


# This module provides a command-line interface to the server via STDIN/STDOUT.
# see the documentation in Command.pm for details on the command syntax


#$::d_stdio = 1;

my $stdout;
my $curline = "";

# initialize the stdio interface
sub init {
	$stdin = shift;
	$stdout = shift;

	return if Slim::Utils::OSDetect::OS() eq 'win';

	Slim::Networking::Select::addRead($stdin, \&processRequest);

	$stdin->autoflush(1);
	$stdout->autoflush(1);
}

#
#  Handle an Stdio request
#
sub processRequest {
	my $clientsock = shift || return;

	my $firstline = <$clientsock>;

	if (defined($firstline)) {

		#process the commands
		$::d_stdio && msg("Got line: $firstline\n");
		chomp $firstline; 
		my $message = executeCmd($firstline);

		$::d_stdio && msg("response is: $message\n");
		$stdout->print($message . "\n") if $message;
	}
}

# executeCmd - handles the execution of the stdio request
#
#
sub executeCmd {
	my $command = shift;

	my $output  = undef;
	# People wanting spaces need to use %20
	my @params  = split(" ", $command);

	foreach my $param (@params) {
		$param = Slim::Utils::Misc::unescape($param);
	}

	if (defined $params[0]) {

		my $client = Slim::Player::Client::getClient($params[0]);
		my $prefix = "";
		
		if (defined($client)) {
			$prefix = Slim::Utils::Misc::escape($params[0]) . " ";
			shift @params;
		}
		
		#if we don't have a player specified, just pick one if there is one...
		if (!defined($client) && Slim::Player::Client::clientCount > 0) {
			my @allclients = Slim::Player::Client::clients();
			$client = $allclients[0];
		}
	
		my @outputParams = Slim::Control::Command::execute($client, \@params);
		
		foreach my $param (@outputParams) {
			$param = Slim::Utils::Misc::escape($param);
		}

		$output = $prefix . join(" ", @outputParams);

	} else {
		$::d_stdio && msg("No params parsed from stdio!\n");
	}

	return $output;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
