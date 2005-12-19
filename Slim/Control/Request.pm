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
		'_params' => \%paramHash,
		'_curparam' => 0,
		'_status' => 0,
		'_results' => \%resultHash,
		'_func' => undef
	};
	# MISSING SOURCE, CALLBACK
	
	bless $self, $class;
	
	return $self;
}


################################################################################
# Read/Write basic query attributes
################################################################################

# sets/returns the query state of the request
sub query {
	my $self = shift;
	my $isQuery = shift;
	
	$self->{'_isQuery'} = $isQuery if defined $isQuery;
	
	return $self->{'_isQuery'};
}

# sets/returns the client, if any, that applies to the request
sub client {
	my $self = shift;
	my $client = shift;
	
	$self->{'_client'} = $client if defined $client;
	
	return $self->{'_client'};
}

################################################################################
# Read/Write status
################################################################################
# 0 new
# 1 dispatched
# 10 done
# 101 bad dispatch
# 102 bad params
# 103 missing client

sub isStatusNew {
	my $self = shift;
	return ($self->__status() == 0);
}

sub setStatusDispatched {
	my $self = shift;
	$self->__status(1);
}
sub isStatusDispatched {
	my $self = shift;
	return ($self->__status() == 1);
}
sub wasStatusDispatched {
	my $self = shift;
	return ($self->__status() > 0);
}

sub setStatusDone {
	my $self = shift;
	$self->__status(10);
}
sub isStatusDone {
	my $self = shift;
	return ($self->__status() == 10);
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

sub getResult {
	my $self = shift;
	my $key = shift || return;
	
	return ${$self->{'_results'}}{$key};
}



################################################################################
# Compound requests
################################################################################

# accepts a reference to an array containing synonyms for the query name
# and returns 1 if no name match the request. Used by functions implementing
# queries to check the dispatcher did not send them a wrong request.
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

################################################################################
# Other
################################################################################
sub execute {
	my $self = shift;
	
	return if $self->isStatusError();
	
	if (defined (my $funcPtr = $self->{'_func'})) {
		&{$funcPtr}($self);
	} else {
		Slim::Control::Dispatch::dispatch($self);
	}
}

sub callback {
}

sub setFunc {
	my $self = shift;
	my $funcPtr = shift;
	
	$self->{'_func'} = $funcPtr;
}




################################################################################
# Special
################################################################################
sub dump {
	my $self = shift;
	
	my $str = "Request: Dumping ";
	
	if ($self->query()) {
		$str .= 'query ';
	} else {
		$str .= 'command ';
	}
	
	if (my $client = $self->client()){
		my $clientid = $client->id();
		$str .= "[$clientid->" . $self->getRequestString() . "]";
	} else {
		$str .= "[" . $self->getRequestString() . "]";
	}
	
	if ($self->isStatusNew()) {
		$str .= " (New)\n";
	} elsif ($self->isStatusDispatched()) {
		$str .= " (Dispatched)\n";
	} elsif ($self->isStatusDone()) {
		$str .= " (Done)\n";
	} elsif ($self->isStatusBadDispatch()) {
		$str .= " (Bad Dispatch)\n";
	} elsif ($self->isStatusBadParams()) {
		$str .= " (Bad Params)\n";
	} elsif ($self->isStatusNeedsClient()) {
		$str .= " (Needs client)\n";
	}
	
	msg($str);

	while (my ($key, $val) = each %{$self->{'_params'}}) {
    	msg("   Param: [$key] = [$val]\n");
 	}
 	
	while (my ($key, $val) = each %{$self->{'_results'}}) {
    	msg("   Result: [$key] = [$val]\n");
 	}
}

# support for legacy applications
# returns all requests/params/results as an array
sub getArray {
	my $self = shift;
	my @returnArray;
	
	push @returnArray, @{$self->{_request}};
	
	while (my ($key, $val) = each %{$self->{'_params'}}) {
    	if ($key =~ /_*/) {
    		push @returnArray, $val;
    	}
 	}
 	
 	# any client expecting something more sophisticated should not go
 	# through execute but through dispatch directly...
	while (my ($key, $val) = each %{$self->{'_results'}}) {
		if ($key =~ /_p*/) {
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
	
	if ($isQuery == $self->query()){
		my $name = $self->getRequest(0);
		return grep(/$name/, @{$possibleNames});
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