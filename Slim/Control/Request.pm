package Slim::Control::Request;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.


use strict;

use Tie::LLHash;

use Slim::Utils::Misc;
#use Slim::Control::Commands;

# This class implements a generic request, that will be dispatched to the
# correct function by Slim::Control::Dispatch code.

sub new {
	my $class = shift;
	my $client = shift;
	
	tie (my %paramHash, "Tie::LLHash", {lazy => 1});
	tie (my %resultHash, "Tie::LLHash", {lazy => 1});
	
	my $self = {
		'_request' => [],
		'_isQuery' => undef,
		'_client' => $client,
		'_needClient' => 0,
		'_params' => \%paramHash,
		'_curparam' => 0,
		'_status' => 0,
		'_results' => \%resultHash,
		'_func' => undef,
		'_cb_enable' => 1,
		'_cb_func' => undef,
		'_cb_args' => undef,
	};
	# MISSING SOURCE
	
	bless $self, $class;
	
	return $self;
}


################################################################################
# Read/Write basic query attributes
################################################################################

# sets/returns the client
sub client {
	my $self = shift;
	my $client = shift;
	
	if (defined $client) {
		$self->{'_client'} = $client;
		$self->validate();
	}
	
	return $self->{'_client'};
}

# sets/returns the need client state
sub needClient {
	my $self = shift;
	my $needClient = shift;
	
	if (defined $needClient) {
		$self->{'_needClient'} = $needClient;
		$self->validate();
	}

	return $self->{'_needClient'};
}

# sets/returns the query state
sub query {
	my $self = shift;
	my $isQuery = shift;
	
	$self->{'_isQuery'} = $isQuery if defined $isQuery;
	
	return $self->{'_isQuery'};
}

# sets/returns the function that executes the request
sub executeFunction {
	my $self = shift;
	my $newvalue = shift;
	
	if (defined $newvalue) {
		$self->{'_func'} = $newvalue;
		$self->validate();
	}
	
	return $self->{'_func'};
}

# sets/returns the callback enabled state
sub callbackEnabled {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_cb_enable'} = $newvalue if defined $newvalue;
	
	return $self->{'_cb_enable'};
}

# sets/returns the callback function
sub callbackFunction {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_cb_func'} = $newvalue if defined $newvalue;
	
	return $self->{'_cb_func'};
}

# sets/returns the callback arguments
sub callbackArguments {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_cb_args'} = $newvalue if defined $newvalue;
	
	return $self->{'_cb_args'};
}

################################################################################
# Read/Write status
################################################################################
# 0 new,
# 1 dispatchable
# 2 dispatched
# 10 done
# 11 callback done
# 101 bad dispatch
# 102 bad params
# 103 missing client
# 104 unkown in dispatch table

sub validate {
	my $self = shift;

	if (ref($self->executeFunction) ne 'CODE') {

		$self->setStatusNotDispatchable();

	} elsif ($self->needClient() && !$self->client()) {

		$self->setStatusNeedsClient();

	} else {

		$self->setStatusDispatchable();
	}
}

sub isStatusNew {
	my $self = shift;
	return ($self->__status() == 0);
}

sub setStatusDispatchable {
	my $self = shift;
	$self->__status(1);
}

sub isStatusDispatchable {
	my $self = shift;
	return ($self->__status() == 1);
}

sub setStatusDispatched {
	my $self = shift;
	$self->__status(2);
}

sub isStatusDispatched {
	my $self = shift;
	return ($self->__status() == 2);
}

sub wasStatusDispatched {
	my $self = shift;
	return ($self->__status() > 1);
}

sub setStatusDone {
	my $self = shift;
	$self->__status(10);
}

sub isStatusDone {
	my $self = shift;
	return ($self->__status() == 10);
}

sub setStatusCallbackDone {
	my $self = shift;
	$self->__status(11);
}

sub isStatusCallbackDone {
	my $self = shift;
	return ($self->__status() == 11);
}

sub isStatusError {
	my $self = shift;
	return ($self->__status() > 100);
}

sub setStatusBadDispatch {
	my $self = shift;	
	$self->__status(101);
}

sub isStatusBadDispatch {
	my $self = shift;
	return ($self->__status() == 101);
}

sub setStatusBadParams {
	my $self = shift;	
	$self->__status(102);
}

sub isStatusBadParams {
	my $self = shift;
	return ($self->__status() == 102);
}

sub setStatusNeedsClient {
	my $self = shift;	
	$self->__status(103);
}

sub isStatusNeedsClient {
	my $self = shift;
	return ($self->__status() == 103);
}

sub setStatusNotDispatchable {
	my $self = shift;	
	$self->__status(104);
}

sub isStatusNotDispatchable {
	my $self = shift;
	return ($self->__status() == 104);
}

################################################################################
# Request mgmt
################################################################################

# returns the request name. Read-only
sub getRequestString {
	my $self = shift;
	
	return join " ", @{$self->{_request}};
}

# add a request value to the request array
sub addRequest {
	my $self = shift;
	my $text = shift;

	push @{$self->{'_request'}}, $text;
	++$self->{'_curparam'};
}

sub getRequest {
	my $self = shift;
	my $idx = shift;
	
	return $self->{'_request'}->[$idx];
}

sub getRequestCount {
	my $self = shift;
	my $idx = shift;
	
	return scalar @{$self->{'_request'}};
}

################################################################################
# Param mgmt
################################################################################

sub addParam {
	my $self = shift;
	my $key = shift;
	my $val = shift;

	${$self->{'_params'}}{$key} = $val;
	++$self->{'_curparam'};
}


sub addParamHash {
	my $self = shift;
	my $hashRef = shift || return;
	
	while (my ($key,$value) = each %{$hashRef}) {
        $self->addParam($key, $value);
    }
}

sub addParamPos {
	my $self = shift;
	my $val = shift;
	
	${$self->{'_params'}}{ "_p" . $self->{'_curparam'}++ } = $val;
}

sub getParam {
	my $self = shift;
	my $key = shift || return;
	
	return ${$self->{'_params'}}{$key};
}

################################################################################
# Result mgmt
################################################################################

sub addResult {
	my $self = shift;
	my $key = shift;
	my $val = shift;

	${$self->{'_results'}}{$key} = $val;
}

sub addResultLoop {
	my $self = shift;
	my $loop = shift;
	my $loopidx = shift;
	my $key = shift;
	my $val = shift;

	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (!defined ${$self->{'_results'}}{$loop}) {
		${$self->{'_results'}}{$loop} = [];
	}
	
	if (!defined ${$self->{'_results'}}{$loop}->[$loopidx]) {
		tie (my %paramHash, "Tie::LLHash", {lazy => 1});
		${$self->{'_results'}}{$loop}->[$loopidx] = \%paramHash;
	}
	
	${${$self->{'_results'}}{$loop}->[$loopidx]}{$key} = $val;
}

sub setResultLoopHash {
	my $self = shift;
	my $loop = shift;
	my $loopidx = shift;
	my $hashRef = shift;
	
	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (!defined ${$self->{'_results'}}{$loop}) {
		${$self->{'_results'}}{$loop} = [];
	}
	
	${$self->{'_results'}}{$loop}->[$loopidx] = $hashRef;
}

sub getResult {
	my $self = shift;
	my $key = shift || return;
	
	return ${$self->{'_results'}}{$key};
}

sub getResultLoopCount {
	my $self = shift;
	my $loop = shift;
	
	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (defined ${$self->{'_results'}}{$loop}) {
		return scalar(@{${$self->{'_results'}}{$loop}});
	}
}

sub getResultLoop {
	my $self = shift;
	my $loop = shift;
	my $loopidx = shift;
	my $key = shift || return undef;

	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (defined ${$self->{'_results'}}{$loop} && 
		defined ${$self->{'_results'}}{$loop}->[$loopidx]) {
		
			return ${${$self->{'_results'}}{$loop}->[$loopidx]}{$key};
	}
	return undef;
}



################################################################################
# Compound calls
################################################################################

# accepts a reference to an array containing references to arrays containing
# synonyms for the query names, 
# and returns 1 if no name match the request. Used by functions implementing
# queries to check the dispatcher did not send them a wrong request.
# See Queries.pm for usage examples, for example infoTotalQuery.
sub isNotQuery {
	my $self = shift;
	my $possibleNames = shift;
	
	return !$self->__isCmdQuery(1, $possibleNames);
}

# same for commands
sub isNotCommand {
	my $self = shift;
	my $possibleNames = shift;
	
	return !$self->__isCmdQuery(0, $possibleNames);
}

sub isCommand{
	my $self = shift;
	my $possibleNames = shift;
	
	return $self->__isCmdQuery(0, $possibleNames);
}

# returns true if $param is undefined or not one of the possible values
# not really a method on request data members but defined as such since it is
# useful for command and queries implementation.
sub paramUndefinedOrNotOneOf {
	my $self = shift;
	my $param = shift;
	my $possibleValues = shift;

	return 1 if !defined $param;
	return 1 if !defined $possibleValues;
	return !grep(/$param/, @{$possibleValues});
}

# sets callback parameters (function and arguments) in a single call...
sub callbackParameters {
	my $self = shift;
	my $callbackf = shift;
	my $callbackargs = shift;

	$self->{'_cb_func'} = $callbackf;
	$self->{'_cb_args'} = $callbackargs;	
}

################################################################################
# Other
################################################################################

# execute the request
sub execute {
	my $self = shift;
	
	$::d_command && msg("\n");
	$::d_command && $self->dump("Request");

	# do nothing if something's wrong
	if ($self->isStatusError()) {
		$::d_command && msg('Request: Request in error, exiting');
		return;
	}
	
	# call the execute function
	if (my $funcPtr = $self->executeFunction()) {

		if (defined $funcPtr && ref($funcPtr) eq 'CODE') {

			eval { &{$funcPtr}($self) };

			if ($@) {
				errorMsg("execute: Error when trying to run coderef: [$@]\n");
				$self->dump('Request');
			}

		} else {

			errorMsg("execute: Didn't get a valid coderef from ->executeFunction\n");
			$self->dump('Request');
		}
	}
	
	# if the status is done
	if ($self->isStatusDone()) {

		$::d_command && $self->dump('Request');
		
		# perform the callback
		$self->callback();
		
		# notify for commands
		if (!$self->query()) {
		
			Slim::Control::Dispatch::notify($self);
		}

	} else {

		$::d_command && $self->dump('Request');
	}
}

sub callback {
	my $self = shift;

	# do nothing unless callback is enabled
	if ($self->callbackEnabled()) {
		
		if (defined(my $funcPtr = $self->callbackFunction())) {

			$::d_command && msg("Request: Calling callback function\n");

			my $args = $self->callbackArguments();
		
			# if we have no arg, use the request
			if (!defined $args) {

				eval { &$funcPtr($self) };

				if ($@) { 
					errorMsg("execute: Error when trying to run coderef: [$@]\n");
					$self->dump('Request');
				}
			
			# else use the provided arguments
			} else {

				eval { &$funcPtr(@$args) };

				if ($@) { 
					errorMsg("execute: Error when trying to run coderef: [$@]\n");
					$self->dump('Request');
				}
			}

			$self->setStatusCallbackDone();
		}

	} else {
	
		$::d_command && msg("Request: Callback disabled\n");
	}
}

################################################################################
# Utility function to dump state of the request object to stdout
################################################################################
sub dump {
	my $self = shift;
	my $introText = shift || '?';
	
	my $str = $introText . ": ";
	
	if ($self->query()) {
		$str .= 'Query ';
	} else {
		$str .= 'Command ';
	}
	
	if (my $client = $self->client()) {
		my $clientid = $client->id();
		$str .= "[$clientid->" . $self->getRequestString() . "]";
	} else {
		$str .= "[" . $self->getRequestString() . "]";
	}

	if ($self->callbackFunction()) {

		if ($self->callbackEnabled()) {
			$str .= " cb+ ";
		} else {
			$str .= " cb- ";
		}
	}
	
	if ($self->isStatusNew()) {
		$str .= " (New)\n";
	} elsif ($self->isStatusDispatchable()) {
		$str .= " (Dispatchable)\n";
	} elsif ($self->isStatusDispatched()) {
		$str .= " (Dispatched)\n";
	} elsif ($self->isStatusDone()) {
		$str .= " (Done)\n";
	} elsif ($self->isStatusBadDispatch()) {
		$str .= " (Bad Dispatch!)\n";
	} elsif ($self->isStatusBadParams()) {
		$str .= " (Bad Params!)\n";
	} elsif ($self->isStatusNeedsClient()) {
		$str .= " (Needs client!)\n";
	} elsif ($self->isStatusNotDispatchable()) {
		$str .= " (Not dispatchable!)\n";
	}

	msg($str);

	while (my ($key, $val) = each %{$self->{'_params'}}) {

    		msg("   Param: [$key] = [$val]\n");
 	}
 	
	while (my ($key, $val) = each %{$self->{'_results'}}) {
    	
		if ($key =~ /^@/) {

			my $count = scalar @{${$self->{'_results'}}{$key}};

			msg("   Result: [$key] is loop with $count elements:\n");
			
			# loop over each elements
			for (my $i = 0; $i < $count; $i++) {

				my $hash = ${$self->{'_results'}}{$key}->[$i];

				while (my ($key2, $val2) = each %{$hash}) {
					msg("   Result:   $i. [$key2] = [$val2]\n");
				}	
			}

		} else {
			msg("   Result: [$key] = [$val]\n");
		}
 	}
}

# support for legacy applications
# returns the request as an array
sub renderAsArray {
	my $self = shift;
	my $encoding = shift;
	
	my @returnArray;
	
	# conventions: 
	# -- parameter or result with key starting with "_": value outputted
	# -- parameter or result with key starting with "__": no output TODO
	# -- result starting with "@": is a loop
	# -- anything else: output "key:value"
	
	# push the request terms
	push @returnArray, @{$self->{'_request'}};
	
	# push the parameters
	while (my ($key, $val) = each %{$self->{'_params'}}) {

		$val = Encode::encode($encoding, $val) if $encoding;

		if ($key =~ /^__/) {
			# no output
		} elsif ($key =~ /^_/) {
			push @returnArray, $val;
		} else {
			push @returnArray, ($key . ":" . $val);
		}
 	}
 	
 	# push the results
	while (my ($key, $val) = each %{$self->{'_results'}}) {

		$val = Encode::encode($encoding, $val) if $encoding;

		if ($key =~ /^@/) {

			# loop over each elements
			foreach my $hash (@{${$self->{'_results'}}{$key}}) {

				while (my ($key2, $val2) = each %{$hash}) {

					$val2 = Encode::encode($encoding, $val2) if $encoding;

					if ($key2 =~ /^__/) {
						# no output
					} elsif ($key2 =~ /^_/) {
						push @returnArray, $val2;
					} else {
						push @returnArray, ($key2 . ':' . $val2);
					}
				}	
			}

		} elsif ($key =~ /^__/) {
			# no output
		} elsif ($key =~ /^_/) {
			push @returnArray, $val;
		} else {
			push @returnArray, ($key . ':' . $val);
		}
 	}
	
	return @returnArray;
}

################################################################################
# Private methods
################################################################################
sub __isCmdQuery {
	my $self = shift;
	my $isQuery = shift;
	my $possibleNames = shift;
	
	# the query state must match
	if ($isQuery == $self->{'_isQuery'}) {
	
		my $possibleNamesCount = scalar (@{$possibleNames});

		# we must have the same number (or more) of request terms
		# than of passed names
		if ((scalar(@{$self->{'_request'}})) >= $possibleNamesCount) {

#			my $match = 1; #assume it works
			
			# now check each request term matches one of the passed params
			for (my $i = 0; $i < $possibleNamesCount; $i++) {
				
				my $name = $self->{'_request'}->[$i];;
#				$match = $match && grep(/$name/, @{$possibleNames->[$i]});

				# return as soon we fail
				return 0 if !grep(/$name/, @{$possibleNames->[$i]});
			
#				return 0 if !$match; # return as soon we fail
			}
			
			# everything matched
			return 1;
		}
	}
	return 0;
}

# sets/returns the status state of the request
sub __status {
	my $self = shift;
	my $status = shift;
	
	$self->{'_status'} = $status if defined $status;
	
	return $self->{'_status'};
}

1;

__END__
