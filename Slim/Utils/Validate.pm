package Slim::Utils::Validate;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Utils::Validate

=head1 DESCRIPTION

L<Slim::Utils::Validate> provides validation checks for web ui preference inputs.
 All functions take the user input as the first argument, $val

=head1 SYNOPSIS

 'validate' => \&Slim::Utils::Validate::trueFalse,
 
 return Slim::Utils::Validate::isInt($arg);

=cut

use strict;

use Slim::Utils::Misc;
use Slim::Utils::Network;

######################################################################
# Validation Functions
######################################################################

=head1 METHODS

=head2 acceptAll( $val)

 Very simple, return the input $val every time.

=cut

sub acceptAll {
	my $val = shift;

	return $val;
}

=head2 trueFalse( $val)

 Boolean test on $val,  return 1 if true, 0 otherwise.

=cut

sub trueFalse {
	# use the perl idea of true and false.
	my $val = shift;

	if ($val) {
		return 1;

	} else {
		return 0;
	}
}

=head2 isInt( $val, [ $low ], [ $high ], [ $setLow ], [ $setHigh ])

 Return $val if $val is an integer. Return nothing if not.
 Caller can optionall set integer limits of $low and $high.

 If $val is below $low then function will return undef, or the value of $low if the argument $setLow is 1
 If $val is above $high then function will return undef, or the value of $high if the argument $setHigh is 1

=cut

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

=head2 port( $val)

Returns the integer $val only if it is an integer in the range of valid TCPIP ports (1024-65535), or 0
Any other value for $val will return undefined.

=cut

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

=head2 hostNameOrIPAndPort( $val)

 Accepts any  string that matches the format of an IP and Port, or a hostname and port
 ie 127.0.0.1:9000, or slimdevices.com:9000
 
 empty entry validates as empty value

=cut

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

=head2 IPPort( $val)

 Accepts any  string that matches the format of an IP and Port
 ie 127.0.0.1:9000

=cut

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

=head2 number( $val, [ $low ], [ $high ], [ $setLow ], [ $setHigh ])

 Return $val if $val is  real number. Return nothing if not.
 Caller can optionally set limits of $low and $high.

 If $val is below $low then function will return undef, or the value of $low if the argument $setLow is 1
 If $val is above $high then function will return undef, or the value of $high if the argument $setHigh is 1

 Scientific notation is not supported by this function.

=cut

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

=head2 inList( $val, @valList)

 Determine if the input $val is contained within a list of valid choices given by the @valList argument
 
=cut

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

=head2 isTime( $val)

 determine if the input string, $val matches known valid Time formats.
 
=cut

sub isTime {
	my $val = shift;

	if ($val =~ m/^([0\s]?[0-9]|1[0-9]|2[0-4]):([0-5][0-9])\s*(P|PM|A|AM)?$/isg) {
		return $val;

	} else {
		return undef;
	}
}

=head2 isHash( $val, $ref, $codereturnsref, $client)

 determines if the value is one of the keys of the supplied hash
 the hash is supplied in the form of a reference either to a hash, or to code which returns a hash

 $codereturnsref should be set to 1 if $ref is to code that returns a hash reference

=cut

sub inHash {
	my $val = shift;
	my $ref = shift;
	my $codereturnsref = shift; #should be set to 1 if $ref is to code that returns a hash reference
	my $client = shift;
	my %hash = ();

	if (ref($ref)) {
		if (ref($ref) eq 'HASH') {
			%hash = %{$ref}

		} elsif (ref($ref) eq 'CODE') {

			if ($codereturnsref) {
				%hash = %{&{$ref}($client)};

			} else {
				%hash = &{$ref}($client);
			}
		}
	}

	if (exists $hash{$val}) {
		return $val;
	} else {
		return undef;
	}
}

=head2 isFile( $val)

 Validate that input $val the string refering to a valid file.
 Otherwise, return a localized error string.
 Optional $allowEmpty agrument will return valid for blank input if set.

=cut

sub isFile {
	return _isValidPath('file', @_, 'SETUP_BAD_FILE');
}

=head2 isAudioDir( $val)

 Validate that input $val the string refering to a valid directory.
 Otherwise, return a localized error string.
 Optional $allowEmpty agrument will return valid for blank input if set.

=cut

sub isAudioDir {
	return _isValidPath('dir', @_, 'SETUP_BAD_DIRECTORY');
}

=head2 isDir( $val)

 Validate that input $val the string refering to a valid directory
 Otherwise, return a localized error string.
 Optional $allowEmpty agrument will return valid for blank input if set.

=cut

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

=head2 hasText( $val, [ $defaultText ])

 If the input $val is an alphanumeric string, return the value.
 In all other cases, return undefined or an optional $defaultText string

=cut

sub hasText {
	my $val = shift; # value to validate
	my $defaultText = shift; #value to use if nothing in the $val param

	if (defined($val) && $val ne '') {
		return $val;
	} else {
		return $defaultText;
	}
}

=head2 password( $val)

 Validate password input and obscure all else.

=cut

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

=head2 allowedHosts( $val)

 Verify allowed hosts is in somewhat proper format, always prepend 127.0.0.1 if not there

=cut

sub allowedHosts {
	my $val = shift;

	$val =~ s/\s+//g;

	if (!defined($val) || $val eq '') {
		return join(',', Slim::Utils::Network::hostAddr());
	} else {
		return $val;
	}
}

=head1 SEE ALSO

L<Slim::Web::Setup>

=cut

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
