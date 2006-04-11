package Slim::Utils::Validate;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Misc;
use Slim::Utils::Network;

######################################################################
# Validation Functions
######################################################################
sub acceptAll {
	my $val = shift;

	return $val;
}

sub trueFalse {
	# use the perl idea of true and false.
	my $val = shift;

	if ($val) {
		return 1;

	} else {
		return 0;
	}
}

sub isInt {
	my ($val,$low,$high,$setLow,$setHigh) = @_;

	if ($val !~ /^-?\d+$/) { #not an integer
		return undef;

	} elsif (defined($low) && $val < $low) { # too low, equal to $low is acceptable

		if ($setLow) {
			return $low;

		} else {
			return undef;
		}

	} elsif (defined($high) && $val > $high) { # too high, equal to $high is acceptable

		if ($setHigh) {
			return $high;

		} else {
			return undef;
		}
	}

	return $val;
}

sub port {
	my $val = shift;

	# not an integer
	if (!defined $val || $val !~ /^-?\d+$/) {
		return undef;
	}

	if ($val == 0) {
		return $val;
	}

	if ($val < 1024) {
		return undef;
	}

	if ($val > 65535) {
		return undef;
	}

	return $val;
}

sub hostNameOrIPAndPort {
	my $val = shift || return '';

	# If we're just an IP:Port - hand off
	if ($val =~ /^[\d\.:]+$/) {
		return IPPort($val);
	}

	my ($host, $port) = split /:/, $val;

	# port is bogus - return here.
	unless (port($port)) {
		return undef;
	}

	# Otherwise - try to make sure it has at least valid chars
	return undef if $host !~ /^[\w\d\._-]+$/;

	return $val;
}

sub IPPort {
	my $val = shift;

	if (length($val) == 0) {
		return $val;
	}
	
	if ($val !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+):(\d+)$/) { 
		#not formatted properly
		return undef;
	}

	if (
		($1 < 0) || ($2 < 0) || ($3 < 0) || ($4 < 0) || ($5 < 0) ||
		($1 > 255) || ($2 > 255) || ($3 > 255) || ($4 > 255) || ($5 > 65535)
		) {
		# bad number
		return undef;
	}

	return $val;
}

sub number {
	my ($val,$low,$high,$setLow,$setHigh) = @_;

	if ($val !~ /^-?\.?\d+\.?\d*$/) { # this doesn't recognize scientific notation

		return undef;

	} elsif (defined($low) && $val < $low) { # too low, equal to $low is acceptable

		if ($setLow) {
			return $low;

		} else {
			return undef;
		}

	} elsif (defined($high) && $val > $high) { # too high, equal to $high is acceptable

		if ($setHigh) {
			return $high;

		} else {
			return undef;
		}
	}

	return $val;
}

sub inList {
	my ($val,@valList) = @_;
	my $inList = 0;

	foreach my $valFromList (@valList) {
		$inList = ($valFromList eq $val);
		last if $inList;
	}

	if ($inList) {
		return $val;

	} else {
		return undef;
	}
}

sub isTime {
	my $val = shift;

	if ($val =~ m/^([0\s]?[0-9]|1[0-9]|2[0-4]):([0-5][0-9])\s*(P|PM|A|AM)?$/isg) {
		return $val;

	} else {
		return undef;
	}
}

# determines if the value is one of the keys of the supplied hash
# the hash is supplied in the form of a reference either to a hash, or to code which returns a hash
sub inHash {
	my $val = shift;
	my $ref = shift;
	my $codereturnsref = shift; #should be set to 1 if $ref is to code that returns a hash reference
	my %hash = ();

	if (ref($ref)) {
		if (ref($ref) eq 'HASH') {
			%hash = %{$ref}

		} elsif (ref($ref) eq 'CODE') {

			if ($codereturnsref) {
				%hash = %{&{$ref}};

			} else {
				%hash = &{$ref};
			}
		}
	}

	if (exists $hash{$val}) {
		return $val;
	} else {
		return undef;
	}
}

sub isFile {
	return _isValidPath('file', @_, 'SETUP_BAD_FILE');
}

sub isAudioDir {
	return _isValidPath('dir', @_, 'SETUP_BAD_DIRECTORY');
}

sub isDir {
	return _isValidPath('dir', @_, 'SETUP_BAD_DIRECTORY');
}

sub _isValidPath {
	my ($type, $val, $allowEmpty, $invalidString) = @_;

	if ($val) {
		$val = Slim::Utils::Misc::pathFromFileURL( Slim::Utils::Misc::fixPath($val) );
	}
	
	if ($type eq 'dir' && -d $val) {

		return $val;

	} elsif ($type eq 'file' && -r $val) {

		return $val;

	} elsif ($allowEmpty && defined($val) && $val eq '') {

		return $val;

	} else {

		errorMsg("_isValidPath: Couldn't find directory: [$val] on disk: [$!]\n");

		return (undef, $invalidString) ;
	}
}

sub hasText {
	my $val = shift; # value to validate
	my $defaultText = shift; #value to use if nothing in the $val param

	if (defined($val) && $val ne '') {
		return $val;
	} else {
		return $defaultText;
	}
}

sub password {
	my $val = shift;
	my $currentPassword = Slim::Utils::Prefs::get('password');

	if (defined($val) && $val ne '' && $val ne $currentPassword) {
		srand (time());
		my $randletter = "(int (rand (26)) + (int (rand (1) + .5) % 2 ? 65 : 97))";
		my $salt = sprintf ("%c%c", eval $randletter, eval $randletter);
		return crypt($val, $salt);
	} else {
		return $currentPassword;
	}
}

# TODO make this actually check to see if the format is valid
sub isFormat {
	my $val = shift;

	if (!defined($val)) {
		return undef;
	} elsif ($val eq '') {
		return $val;
	} else {
		return $val;
	}
}

# Verify allowed hosts is in somewhat proper format, always prepend 127.0.0.1 if not there
sub allowedHosts {
	my $val = shift;

	$val =~ s/\s+//g;

	if (!defined($val) || $val eq '') {
		return join(',', Slim::Utils::Network::hostAddr());
	} else {
		return $val;
	}
}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
