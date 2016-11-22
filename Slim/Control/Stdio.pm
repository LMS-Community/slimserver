package Slim::Control::Stdio;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use URI::Escape;

use Slim::Networking::Select;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

=head1 NAME

Slim::Control::Stdio

=head1 DESCRIPTION

L<Slim::Control::Stdio> provides a command-line interface to the server via STDIN/STDOUT.
	see the documentation in Request.pm for details on the commands
	This does not support shell like escaping. See the CLI documentation.

=cut

my ($stdin, $stdout);

my $log = logger('control.stdio');

# initialize the stdio interface
sub init {
	$stdin = shift;
	$stdout = shift;

	if (main::ISWINDOWS) {
		return;
	}

	main::INFOLOG && $log->info("Adding \$stdin to select loop");

	Slim::Networking::Select::addRead($stdin, \&processRequest);

	$stdin->autoflush(1);
	$stdout->autoflush(1);
}

#  handles Stdio I/O
sub processRequest {
	my $clientsock = shift || return;

	my $firstline = <$clientsock>;

	if (defined($firstline)) {

		# process the commands
		chomp $firstline; 

		main::INFOLOG && $log->info("Got line: $firstline");

		my $message = executeCmd($firstline) || '';

		main::INFOLOG && $log->info("Response is: $message");

		$stdout->print("$message\n");
	}
}

# handles the execution of the stdio request
sub executeCmd {
	my $command = shift;

	my ($client, $arrayRef) = string_to_array($command);
	
	if (!defined $arrayRef) {
		return;
	}

	# If we don't have a player specified, just pick one
	if (!defined $client) {

		$client = Slim::Player::Client::clientRandom();
	}

	my @outputParams = Slim::Control::Request::executeLegacy($client, $arrayRef);

	return array_to_string($client ? $client->id : undef, \@outputParams);
}

# transforms an escaped string into an array (returned). If the first
# array element is a client, it is removed from the array and returned
# individually.
sub string_to_array {
	my $string = shift;

	# Split the command string
	# Space in parameters are to be encoded as %20
	my @elements  = split(" ", $string);

	if (!scalar @elements) {
		return;
	}

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
	map { $_ = URI::Escape::uri_escape_utf8($_) } @elements;
	
	# join by space and return!
	return join " ",  @elements;
}

=head1 SEE ALSO

L<Slim::Control::Request>

=cut

1;

__END__
