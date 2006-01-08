package Slim::Control::Command;

# $Id$
#
# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Misc qw(msg errorMsg);

our %executeCallbacks = ();

#############################################################################
# execute - does all the hard work.  Use it.
# takes:
#   a client reference
#   a reference to an array of parameters
#   a reference to a callback function
#   a list of callback function args
#
# returns an array containing the given parameters

# currently patched to process all commands and queries through Dispatch
# and Request(s) objects.



sub execute {
	my($client, $parrayref, $callbackf, $callbackargs) = @_;

	my $p0 = $parrayref->[0];
	my $p1 = $parrayref->[1];
	my $p2 = $parrayref->[2];
	my $p3 = $parrayref->[3];
	my $p4 = $parrayref->[4];
	my $p5 = $parrayref->[5];
	my $p6 = $parrayref->[6];
	my $p7 = $parrayref->[7];

	my $callcallback = 1;
	my @returnArray = ();

	$::d_command && msg("Command: Executing command " . ($client ? $client->id() : "no client") . ": $p0 (" .
			(defined $p1 ? $p1 : "") . ") (" .
			(defined $p2 ? $p2 : "") . ") (" .
			(defined $p3 ? $p3 : "") . ") (" .
			(defined $p4 ? $p4 : "") . ") (" .
			(defined $p5 ? $p5 : "") . ") (" .
			(defined $p6 ? $p6 : "") . ") (" .
			(defined $p7 ? $p7 : "") . ")\n");

	# Try and go through dispatch

	# create a request from the array
	my $request = Slim::Control::Dispatch::requestFromArray($client, $parrayref);
	
	if (defined $request && $request->isStatusDispatchable()) {
		
		# add callback stuff, even if for now this will be handled here below
#		$request->callbackParameters($callbackf, $callbackargs);
		
		$request->execute();

		if ($request->wasStatusDispatched()){
			
			# make sure we don't execute again if ever dispatch knows
			# about a command still below
			$p0 .= "(was dispatched)";
			
			# patch the return array so that callbacks function as before
			@returnArray = $request->renderAsArray();
			
			# correct callback enable status
			$callcallback = $request->callbackEnabled();
		}
	}
		
	$callcallback && $callbackf && (&$callbackf(@$callbackargs, \@returnArray));

	executeCallback($client ? $client:undef, \@returnArray);
	
	$::d_command && msg("Command: Returning array: " . $returnArray[0] . " (" .
			(defined $returnArray[1] ? $returnArray[1] : "") . ") (" .
			(defined $returnArray[2] ? $returnArray[2] : "") . ") (" .
			(defined $returnArray[3] ? $returnArray[3] : "") . ") (" .
			(defined $returnArray[4] ? $returnArray[4] : "") . ") (" .
			(defined $returnArray[5] ? $returnArray[5] : "") . ") (" .
			(defined $returnArray[6] ? $returnArray[6] : "") . ") (" .
			(defined $returnArray[7] ? $returnArray[7] : "") . ")\n");
	
	return @returnArray;
}

sub setExecuteCallback {
	my $callbackRef = shift;
	$executeCallbacks{$callbackRef} = $callbackRef;
	errorMsg("Slim::Control::Command::setExecuteCallback() has been deprecated!\n");
	errorMsg("Please use Slim::Control::Dispatch::subscribe() instead!\n");
}

sub clearExecuteCallback {
	my $callbackRef = shift;
	delete $executeCallbacks{$callbackRef};
	errorMsg("Slim::Control::Command::clearExecuteCallback() has been deprecated!\n");
	errorMsg("Please use Slim::Control::Dispatch::unsubscribe() instead!\n");
}

sub executeCallback {
	my $client = shift;
	my $paramsRef = shift;
	my $dontcallDispatch = shift;

	$::d_command && msg("Command: executeCallback()\n");

	no strict 'refs';
		
	for my $executecallback (keys %executeCallbacks) {
		$executecallback = $executeCallbacks{$executecallback};
		&$executecallback($client, $paramsRef);
	}
	
	Slim::Control::Dispatch::notifyFromArray($client, $paramsRef, "no no no") if !defined $dontcallDispatch;
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
