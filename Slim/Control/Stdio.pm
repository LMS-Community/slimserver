package Slim::Control::Stdio;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
use URI::Escape;

use Slim::Networking::Select;
use Slim::Utils::Strings qw(string);
use Slim::Utils::OSDetect;
use Slim::Utils::Misc;

use vars qw($stdin);


# This module provides a command-line interface to the server via STDIN/STDOUT.
# see the documentation in Request.pm for details on the commands
# This does not support shell like escaping. See the CLI documentation.


my $stdout;
my $curline = "";

# initialize the stdio interface
sub init {
	$stdin = shift;
	$stdout = shift;

	return if Slim::Utils::OSDetect::OS() eq 'win';

	$::d_stdio && msg("Stdio: init()\n");

	Slim::Networking::Select::addRead($stdin, \&processRequest);

	$stdin->autoflush(1);
	$stdout->autoflush(1);
}

#  handles Stdio I/O
sub processRequest {
	my $clientsock = shift || return;

	my $firstline = <$clientsock>;

	if (defined($firstline)) {

		#process the commands
		chomp $firstline; 
		$::d_stdio && msg("Stdio: Got line: $firstline\n");
		
		my $message = executeCmd($firstline);

		$::d_stdio && msg("Stdio: Response is: $message\n");
		$stdout->print("$message\n");
	}
}

# handles the execution of the stdio request
sub executeCmd {
	my $command = shift;
	
	my ($client, $arrayRef)  = string_to_array($command);
	
	return if !defined $arrayRef;

	#if we don't have a player specified, just pick one
	$client = Slim::Player::Client::clientRandom() if !defined $client;
	
	my @outputParams = Slim::Control::Request::executeLegacy($client, $arrayRef);
		
	return array_to_string($client->id(), \@outputParams);
}


# transforms an escaped string into an array (returned). If the first
# array element is a client, it is removed from the array and returned
# individually.
sub string_to_array {
	my $string = shift;
	
	# Split the command string
	# Space in parameters are to be encoded as %20
	my @elements  = split(" ", $string);

	return if !scalar @elements;
	
	# Unescape
	map { $_ = URI::Escape::uri_unescape($_) } @elements;
		
	# Check if first param is a client...
	my $client = Slim::Player::Client::getClient($elements[0]);

	if (defined $client) {
		# Remove the client from the param array
		shift @elements;
	}
	
	return ($client, \@elements);
}

# transforms an array into an escaped string (returned). If $clientid is
# defined, it is added in the first position in the array.
sub array_to_string {
	my $clientid = shift;
	my $arrayRef = shift;

	# make a copy, we'll change it
	my @elements = @$arrayRef;

	# add clientid if there is a client
	unshift @elements, $clientid if defined $clientid;
	
	# escape all the terms
	map { $_ = URI::Escape::uri_escape($_) } @elements;
	
	# join by space and return!
	return join " ",  @elements;
}




1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
