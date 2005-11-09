# Copyright (c) 1999 - 2002                           RIPE NCC
#
# All Rights Reserved
#
# Permission to use, copy, modify, and distribute this software and its
# documentation for any purpose and without fee is hereby granted,
# provided that the above copyright notice appear in all copies and that
# both that copyright notice and this permission notice appear in
# supporting documentation, and that the name of the author not be
# used in advertising or publicity pertaining to distribution of the
# software without specific, written prior permission.
#
# THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE, INCLUDING
# ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS; IN NO EVENT SHALL
# AUTHOR BE LIABLE FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY
# DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
# AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

#------------------------------------------------------------------------------
# Module Header
# Filename          : IP.pm
# Purpose           : Provide functions to manipulate IPv4/v6 addresses
# Author            : Manuel Valente <manuel.valente@gmail.com>
# Date              : 19991124
# Description       :
# Language Version  : Perl 5
# OSs Tested        : BSDI 3.1 - Linux
# Command Line      : ipcount
# Input Files       :
# Output Files      :
# External Programs : Math::BigInt.pm
# Problems          :
# To Do             :
# Comments          : Based on ipv4pack.pm (Monica) and iplib.pm (Lee)
#                     Math::BigInt is only loaded if int functions are used
# $Id$
#------------------------------------------------------------------------------

package Net::IP;

use strict;

# Global Variables definition
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $ERROR $ERRNO
  %IPv4ranges %IPv6ranges $useBigInt
  $IP_NO_OVERLAP $IP_PARTIAL_OVERLAP $IP_A_IN_B_OVERLAP $IP_B_IN_A_OVERLAP $IP_IDENTICAL);

$VERSION = '1.24';

require Exporter;

@ISA = qw(Exporter);

# Functions and variables exported in all cases
@EXPORT = qw(&Error &Errno
  $IP_NO_OVERLAP $IP_PARTIAL_OVERLAP $IP_A_IN_B_OVERLAP $IP_B_IN_A_OVERLAP $IP_IDENTICAL
);

# Functions exported on demand (with :PROC)
@EXPORT_OK = qw(&Error &Errno &ip_iptobin &ip_bintoip &ip_bintoint &ip_inttobin
  &ip_get_version &ip_is_ipv4 &ip_is_ipv6 &ip_expand_address &ip_get_mask
  &ip_last_address_bin &ip_splitprefix &ip_prefix_to_range
  &ip_is_valid_mask &ip_bincomp &ip_binadd &ip_get_prefix_length
  &ip_range_to_prefix &ip_compress_address &ip_is_overlap
  &ip_get_embedded_ipv4 &ip_aggregate &ip_iptype &ip_check_prefix
  &ip_reverse &ip_normalize &ip_normal_range &ip_iplengths
  $IP_NO_OVERLAP $IP_PARTIAL_OVERLAP $IP_A_IN_B_OVERLAP $IP_B_IN_A_OVERLAP $IP_IDENTICAL
);

%EXPORT_TAGS = (PROC => [@EXPORT_OK],);

# Definition of the Ranges for IPv4 IPs
%IPv4ranges = (
    '00000000'                 => 'PRIVATE',     # 0/8
    '00001010'                 => 'PRIVATE',     # 10/8
    '01111111'                 => 'PRIVATE',     # 127.0/8
    '101011000001'             => 'PRIVATE',     # 172.16/12
    '1100000010101000'         => 'PRIVATE',     # 192.168/16
    '1010100111111110'         => 'RESERVED',    # 169.254/16
    '110000000000000000000010' => 'RESERVED',    # 192.0.2/24
    '1110'                     => 'RESERVED',    # 224/4
    '11110'                    => 'RESERVED',    # 240/5
    '11111'                    => 'RESERVED',    # 248/5
);

# Definition of the Ranges for Ipv6 IPs
%IPv6ranges = (
    '00000000'   => 'RESERVED',                  # ::/8
    '00000001'   => 'RESERVED',                  # 0100::/8
    '0000001'    => 'RESERVED',                  # 0200::/7
    '000001'     => 'RESERVED',                  # 0400::/6
    '00001'      => 'RESERVED',                  # 0800::/5
    '0001'       => 'RESERVED',                  # 1000::/4
    '001'        => 'GLOBAL-UNICAST',            # 2000::/3
    '010'        => 'RESERVED',                  # 4000::/3
    '011'        => 'RESERVED',                  # 6000::/3
    '100'        => 'RESERVED',                  # 8000::/3
    '101'        => 'RESERVED',                  # A000::/3
    '110'        => 'RESERVED',                  # C000::/3
    '1110'       => 'RESERVED',                  # E000::/4
    '11110'      => 'RESERVED',                  # F000::/5
    '111110'     => 'RESERVED',                  # F800::/6
    '1111101'    => 'RESERVED',                  # FA00::/7
    '1111110'    => 'UNIQUE-LOCAL-UNICAST',      # FC00::/7
    '111111100'  => 'RESERVED',                  # FE00::/9
    '1111111010' => 'LINK-LOCAL-UNICAST',        # FE80::/10
    '1111111011' => 'RESERVED',                  # FEC0::/10
    '11111111'   => 'MULTICAST',                 # FF00::/8
    '00100000000000010000110110111000' => 'RESERVED',    # 2001:DB8::/32

    '0' x 96 => 'IPV4COMP',                              # ::/96
    ('0' x 80) . ('1' x 16) => 'IPV4MAP',                # ::FFFF:0:0/96

    '0' x 128         => 'UNSPECIFIED',                  # ::/128
    ('0' x 127) . '1' => 'LOOPBACK'                      # ::1/128

);

# Overlap constants
$IP_NO_OVERLAP      = 0;
$IP_PARTIAL_OVERLAP = 1;
$IP_A_IN_B_OVERLAP  = -1;
$IP_B_IN_A_OVERLAP  = -2;
$IP_IDENTICAL       = -3;

# ----------------------------------------------------------
# OVERLOADING

use overload (
    '+'    => 'ip_add_num',
    'bool' => sub { @_ },
);

#------------------------------------------------------------------------------
# Subroutine ip_num_add
# Purpose           : Add an integer to an IP
# Params            : Number to add
# Returns           : New object or undef
# Note              : Used by overloading - returns undef when
#                     the end of the range is reached

sub ip_add_num {
    my $self = shift;

    my ($value) = @_;

    my $ip = $self->intip + $value;

    my $last = $self->last_int;

    # Reached the end of the range ?
    if ($ip > $self->last_int) {
        return;
    }

    my $newb = ip_inttobin($ip, $self->version);
    $newb = ip_bintoip($newb, $self->version);

    my $newe = ip_inttobin($last, $self->version);
    $newe = ip_bintoip($newe, $self->version);

    my $new = new Net::IP("$newb - $newe");

    return ($new);
}

# -----------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Subroutine new
# Purpose           : Create an instance of an IP object
# Params            : Class, IP prefix, IP version
# Returns           : Object reference or undef
# Note              : New just allocates a new object - set() does all the work
sub new {
    my ($class, $data, $ipversion) = (@_);

    # Allocate new object
    my $self = {};

    bless($self, $class);

    # Pass everything to set()
    unless ($self->set($data, $ipversion)) {
        return;
    }

    return $self;
}

#------------------------------------------------------------------------------
# Subroutine set
# Purpose           : Set the IP for an IP object
# Params            : Data, IP type
# Returns           : 1 (success) or undef (failure)
sub set {
    my $self = shift;

    my ($data, $ipversion) = @_;

    # Normalize data as received - this should return 2 IPs
    my ($begin, $end) = ip_normalize($data, $ipversion) or do {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    };

    # Those variables are set when the object methods are called
    # We need to reset everything
    for (
        qw(ipversion errno prefixlen binmask reverse_ip last_ip iptype
        binip error ip intformat mask last_bin last_int prefix is_prefix)
      )
    {
        delete($self->{$_});
    }

    # Determine IP version for this object
    return unless ($self->{ipversion} = $ipversion || ip_get_version($begin));

    # Set begin IP address
    $self->{ip} = $begin;

    # Set Binary IP address
    return
      unless ($self->{binip} = ip_iptobin($self->ip(), $self->version()));

    $self->{is_prefix} = 0;

    # Set end IP address
    # If single IP: begin and end IPs are identical
    $end ||= $begin;
    $self->{last_ip} = $end;

    # Try to determine the IP version
    my $ver = ip_get_version($end) || return;

    # Check if begin and end addresses have the same version
    if ($ver != $self->version()) {
        $ERRNO = 201;
        $ERROR =
          "Begin and End addresses have different IP versions - $begin - $end";
        $self->{errno} = $ERRNO;
        $self->{error} = $ERROR;
        return;
    }

    # Get last binary address
    return
      unless ($self->{last_bin} =
        ip_iptobin($self->last_ip(), $self->version()));

    # Check that End IP >= Begin IP
    unless (ip_bincomp($self->binip(), 'le', $self->last_bin())) {
        $ERRNO = 202;
        $ERROR = "Begin address is greater than End address $begin - $end";
        $self->{errno} = $ERRNO;
        $self->{error} = $ERROR;
        return;
    }

    # Find all prefixes (eg:/24) in the current range
    my @prefixes = $self->find_prefixes() or return;

    # If there is only one prefix:
    if (scalar(@prefixes) == 1) {

        # Get length of prefix
        return
          unless ((undef, $self->{prefixlen}) = ip_splitprefix($prefixes[0]));

        # Set prefix boolean var
        # This value is 1 if the IP range only contains a single /nn prefix
        $self->{is_prefix} = 1;
    }

    # If the range is a single prefix:
    if ($self->{is_prefix}) {

        # Set mask property
        $self->{binmask} = ip_get_mask($self->prefixlen(), $self->version());

        # Check that the mask is valid
        unless (
            ip_check_prefix(
                $self->binip(), $self->prefixlen(), $self->version()
            )
          )
        {
            $self->{error} = $ERROR;
            $self->{errno} = $ERRNO;
            return;
        }
    }

    return ($self);
}

sub print {
    my $self = shift;

    if ($self->{is_prefix}) {
        return ($self->short() . '/' . $self->prefixlen());
    }
    else {
        return (sprintf("%s - %s", $self->ip(), $self->last_ip()));
    }
}

#------------------------------------------------------------------------------
# Subroutine error
# Purpose           : Return the current error message
# Returns           : Error string
sub error {
    my $self = shift;
    return $self->{error};
}

#------------------------------------------------------------------------------
# Subroutine errno
# Purpose           : Return the current error number
# Returns           : Error number
sub errno {
    my $self = shift;
    return $self->{errno};
}

#------------------------------------------------------------------------------
# Subroutine binip
# Purpose           : Return the IP as a binary string
# Returns           : binary string
sub binip {
    my $self = shift;
    return $self->{binip};
}

#------------------------------------------------------------------------------
# Subroutine prefixlen
# Purpose           : Get the IP prefix length
# Returns           : prefix length
sub prefixlen {
    my $self = shift;
    return $self->{prefixlen};
}

#------------------------------------------------------------------------------
# Subroutine version
# Purpose           : Return the IP version
# Returns           : IP version
sub version {
    my $self = shift;
    return $self->{ipversion};
}

#------------------------------------------------------------------------------
# Subroutine version
# Purpose           : Return the IP in quad format
# Returns           : IP string
sub ip {
    my $self = shift;
    return $self->{ip};
}

#------------------------------------------------------------------------------
# Subroutine is_prefix
# Purpose           : Check if range of IPs is a prefix
# Returns           : boolean
sub is_prefix {
    my $self = shift;
    return $self->{is_prefix};
}

#------------------------------------------------------------------------------
# Subroutine binmask
# Purpose           : Return the binary mask of an IP prefix
# Returns           : Binary mask (as string)
sub binmask {
    my $self = shift;
    return $self->{binmask};
}

#------------------------------------------------------------------------------
# Subroutine size
# Purpose           : Return the number of addresses contained in an IP object
# Returns           : Number of addresses
sub size {
    my $self = shift;

    my $compl;

    # Calculate 2's complement of first IP
    foreach (split '', $self->binip()) {
        $compl .= $_ == 1 ? '0' : '1';
    }

    my $one = ('0' x (length($compl) - 1)) . '1';

    return unless ($compl = ip_binadd($compl, $one));

    # Add complemented IP to final IP (same as substraction)
    my $result = ip_binadd($self->last_bin(), $compl) or return;

    # Transform into integer
    return unless ($result = ip_bintoint($result, $self->version()));

    return ($result + 1);
}

# All the following functions work the same way: the method is just a frontend
# to the real function. When the real function is called, the output is cached
# so that next time the same function is called,the frontend function directly
# returns the result.

#------------------------------------------------------------------------------
# Subroutine intip
# Purpose           : Return the IP in integer format
# Returns           : Integer
sub intip {
    my $self = shift;

    return ($self->{intformat}) if defined($self->{intformat});

    my $int = ip_bintoint($self->binip());

    if (!$int) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    $self->{intformat} = $int;

    return ($int);
}

#------------------------------------------------------------------------------
# Subroutine prefix
# Purpose           : Return the Prefix (n.n.n.n/s)
# Returns           : IP Prefix
sub prefix {
    my $self = shift;

    if (not $self->is_prefix()) {
        $self->{error} = "IP range $self->{ip} is not a Prefix.";
        $self->{errno} = 209;
        return;
    }

    return ($self->{prefix}) if defined($self->{prefix});

    my $prefix = $self->ip() . '/' . $self->prefixlen();

    if (!$prefix) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    $self->{prefix} = $prefix;

    return ($prefix);
}

#------------------------------------------------------------------------------
# Subroutine mask
# Purpose           : Return the IP mask in quad format
# Returns           : Mask (string)
sub mask {
    my $self = shift;

    if (not $self->is_prefix()) {
        $self->{error} = "IP range $self->{ip} is not a Prefix.";
        $self->{errno} = 209;
        return;
    }

    return ($self->{mask}) if defined($self->{mask});

    my $mask = ip_bintoip($self->binmask(), $self->version());

    if (!$mask) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    $self->{mask} = $mask;

    return ($mask);
}

#------------------------------------------------------------------------------
# Subroutine short
# Purpose           : Get the short format of an IP address or a Prefix
# Returns           : short format IP or undef
sub short {
    my $self = shift;

    my $r;

    if ($self->version == 6) {
        $r = ip_compress_address($self->ip(), $self->version());
    }
    else {
        $r = ip_compress_v4_prefix($self->ip(), $self->prefixlen());
    }

    if (!defined($r)) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    return ($r);
}

#------------------------------------------------------------------------------
# Subroutine iptype
# Purpose           : Return the type of an IP
# Returns           : Type or undef (failure)
sub iptype {
    my ($self) = shift;

    return ($self->{iptype}) if defined($self->{iptype});

    my $type = ip_iptype($self->binip(), $self->version());

    if (!$type) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    $self->{iptype} = $type;

    return ($type);
}

#------------------------------------------------------------------------------
# Subroutine reverse_ip
# Purpose           : Return the Reverse IP
# Returns           : Reverse IP or undef(failure)
sub reverse_ip {
    my ($self) = shift;

    if (not $self->is_prefix()) {
        $self->{error} = "IP range $self->{ip} is not a Prefix.";
        $self->{errno} = 209;
        return;
    }

    return ($self->{reverse_ip}) if defined($self->{reverse_ip});

    my $rev = ip_reverse($self->ip(), $self->prefixlen(), $self->version());

    if (!$rev) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    $self->{reverse_ip} = $rev;

    return ($rev);
}

#------------------------------------------------------------------------------
# Subroutine last_bin
# Purpose           : Get the last IP of a range in binary format
# Returns           : Last binary IP or undef (failure)
sub last_bin {
    my ($self) = shift;

    return ($self->{last_bin}) if defined($self->{last_bin});

    my $last;

    if ($self->is_prefix()) {
        $last =
          ip_last_address_bin($self->binip(), $self->prefixlen(),
            $self->version());
    }
    else {
        $last = ip_iptobin($self->last_ip(), $self->version());
    }

    if (!$last) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    $self->{last_bin} = $last;

    return ($last);
}

#------------------------------------------------------------------------------
# Subroutine last_int
# Purpose           : Get the last IP of a range in integer format
# Returns           : Last integer IP or undef (failure)
sub last_int {
    my ($self) = shift;

    return ($self->{last_int}) if defined($self->{last_int});

    my $last_bin = $self->last_bin() or return;

    my $last_int = ip_bintoint($last_bin, $self->version()) or return;

    $self->{last_int} = $last_int;

    return ($last_int);
}

#------------------------------------------------------------------------------
# Subroutine last_ip
# Purpose           : Get the last IP of a prefix in IP format
# Returns           : IP or undef (failure)
sub last_ip {
    my ($self) = shift;

    return ($self->{last_ip}) if defined($self->{last_ip});

    my $last = ip_bintoip($self->last_bin(), $self->version());

    if (!$last) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    $self->{last_ip} = $last;

    return ($last);
}

#------------------------------------------------------------------------------
# Subroutine find_prefixes
# Purpose           : Get all prefixes in the range defined by two IPs
# Params            : IP
# Returns           : List of prefixes or undef (failure)
sub find_prefixes {
    my ($self) = @_;

    my @list =
      ip_range_to_prefix($self->binip(), $self->last_bin(), $self->version());

    if (!scalar(@list)) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    return (@list);
}

#------------------------------------------------------------------------------
# Subroutine bincomp
# Purpose           : Compare two IPs
# Params            : Operation, IP to compare
# Returns           : 1 (True), 0 (False) or undef (problem)
# Comments          : Operation can be lt, le, gt, ge
sub bincomp {
    my ($self, $op, $other) = @_;

    my $a = ip_bincomp($self->binip(), $op, $other->binip());

    unless (defined $a) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    return ($a);
}

#------------------------------------------------------------------------------
# Subroutine binadd
# Purpose           : Add two IPs
# Params            : IP to add
# Returns           : New IP object or undef (failure)
sub binadd {
    my ($self, $other) = @_;

    my $ip = ip_binadd($self->binip(), $other->binip());

    if (!$ip) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    my $new = new Net::IP(ip_bintoip($ip, $self->version())) or return;

    return ($new);
}

#------------------------------------------------------------------------------
# Subroutine aggregate
# Purpose           : Aggregate (append) two IPs
# Params            : IP to add
# Returns           : New IP object or undef (failure)
sub aggregate {
    my ($self, $other) = @_;

    my $r = ip_aggregate(
        $self->binip(),  $self->last_bin(),
        $other->binip(), $other->last_bin(),
        $self->version()
    );

    if (!$r) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    return (new Net::IP($r));
}

#------------------------------------------------------------------------------
# Subroutine overlaps
# Purpose           : Check if two prefixes overlap
# Params            : Prefix to compare
# Returns           : $NO_OVERLAP         (no overlap)
#                     $IP_PARTIAL_OVERLAP (overlap)
#                     $IP_A_IN_B_OVERLAP  (range1 is included in range2)
#                     $IP_B_IN_A_OVERLAP  (range2 is included in range1)
#                     $IP_IDENTICAL       (range1 == range2)
#                     or undef (problem)

sub overlaps {
    my ($self, $other) = @_;

    my $r = ip_is_overlap(
        $self->binip(),  $self->last_bin(),
        $other->binip(), $other->last_bin()
    );

    if (!defined($r)) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    return ($r);
}

#------------------------------------------------------------------------------
# Subroutine auth
# Purpose           : Return Authority information from IP::Authority
# Params            : IP object
# Returns           : Authority Source

sub auth {
    my ($self) = shift;

    return ($self->{auth}) if defined($self->{auth});

    my $auth = ip_auth($self->ip, $self->version);

    if (!$auth) {
        $self->{error} = $ERROR;
        $self->{errno} = $ERRNO;
        return;
    }

    $self->{auth} = $auth;

    return ($self->{auth});
}

#------------------------------ PROCEDURAL INTERFACE --------------------------
#------------------------------------------------------------------------------
# Subroutine Error
# Purpose           : Return the ERROR string
# Returns           : string
sub Error {
    return ($ERROR);
}

#------------------------------------------------------------------------------
# Subroutine Error
# Purpose           : Return the ERRNO value
# Returns           : number
sub Errno {
    return ($ERRNO);
}

#------------------------------------------------------------------------------
# Subroutine ip_iplengths
# Purpose           : Get the length in bits of an IP from its version
# Params            : IP version
# Returns           : Number of bits

sub ip_iplengths {
    my ($version) = @_;

    if ($version == 4) {
        return (32);
    }
    elsif ($version == 6) {
        return (128);
    }
    else {
        return;
    }
}

#------------------------------------------------------------------------------
# Subroutine ip_iptobin
# Purpose           : Transform an IP address into a bit string
# Params            : IP address, IP version
# Returns           : bit string on success, undef otherwise
sub ip_iptobin {
    my ($ip, $ipversion) = @_;

    # v4 -> return 32-bit array
    if ($ipversion == 4) {
        return unpack('B32', pack('C4C4C4C4', split(/\./, $ip)));
    }

    # Strip ':'
    $ip =~ s/://g;

    # Check size
    unless (length($ip) == 32) {
        $ERROR = "Bad IP address $ip";
        $ERRNO = 102;
        return;
    }

    # v6 -> return 128-bit array
    return unpack('B128', pack('H32', $ip));
}

#------------------------------------------------------------------------------
# Subroutine ip_bintoip
# Purpose           : Transform a bit string into an IP address
# Params            : bit string, IP version
# Returns           : IP address on success, undef otherwise
sub ip_bintoip {
    my ($binip, $ip_version) = @_;

    # Define normal size for address
    my $len = ip_iplengths($ip_version);

    if ($len < length($binip)) {
        $ERROR = "Invalid IP length for binary IP $binip\n";
        $ERRNO = 189;
        return;
    }

    # Prepend 0s if address is less than normal size
    $binip = '0' x ($len - length($binip)) . $binip;

    # IPv4
    if ($ip_version == 4) {
        return join '.', unpack('C4C4C4C4', pack('B32', $binip));
    }

    # IPv6
    return join(':', unpack('H4H4H4H4H4H4H4H4', pack('B128', $binip)));
}

#------------------------------------------------------------------------------
# Subroutine ip_bintoint
# Purpose           : Transform a bit string into an Integer
# Params            : bit string
# Returns           : BigInt
sub ip_bintoint {
    my $binip = shift;

    require Math::BigInt;

    # $n is the increment, $dec is the returned value
    my ($n, $dec) = (Math::BigInt->new(1), Math::BigInt->new(0));

    # Reverse the bit string
    foreach (reverse(split '', $binip)) {

        # If the nth bit is 1, add 2**n to $dec
        $_ and $dec += $n;
        $n *= 2;
    }

    # Strip leading + sign
    $dec =~ s/^\+//;
    return $dec;
}

#------------------------------------------------------------------------------
# Subroutine ip_inttobin
# Purpose           : Transform a BigInt into a bit string
# Comments          : sets warnings (-w) off.
#                     This is necessary because Math::BigInt is not compliant
# Params            : BigInt, IP version
# Returns           : bit string
sub ip_inttobin {
    require Math::BigInt;

    my $dec = Math::BigInt->new(shift);

    # Find IP version
    my $ip_version = shift;

    unless ($ip_version) {
        $ERROR = "Cannot determine IP version for $dec";
        $ERRNO = 101;
        return;
    }

    # Number of bits depends on IP version
    my $maxn = ip_iplengths($ip_version);

    my ($n, $binip);

    # Set warnings off, use integers only (loathe Math::BigInt)
    local $^W = 0;
    use integer;

    for ($n = 0 ; $n < $maxn ; $n++) {

        # Bit is 1 if $dec cannot be divided by 2
        $binip .= $dec % 2;

        # Divide by 2, without fractional part
        $dec /= 2;
    }

    no integer;

    # Strip + signs
    $binip =~ s/\+//g;

    # Reverse bit string
    return scalar reverse $binip;
}

#------------------------------------------------------------------------------
# Subroutine ip_get_version
# Purpose           : Get an IP version
# Params            : IP address
# Returns           : 4, 6, 0(don't know)
sub ip_get_version {
    my $ip = shift;

    # If the address does not contain any ':', maybe it's IPv4
    $ip !~ /:/ and ip_is_ipv4($ip) and return '4';

    # Is it IPv6 ?
    ip_is_ipv6($ip) and return '6';

    return;
}

#------------------------------------------------------------------------------
# Subroutine ip_is_ipv4
# Purpose           : Check if an IP address is version 4
# Params            : IP address
# Returns           : 1 (yes) or 0 (no)
sub ip_is_ipv4 {
    my $ip = shift;

    # Check for invalid chars
    unless ($ip =~ m/^[\d\.]+$/) {
        $ERROR = "Invalid chars in IP $ip";
        $ERRNO = 107;
        return 0;
    }

    if ($ip =~ m/^\./) {
        $ERROR = "Invalid IP $ip - starts with a dot";
        $ERRNO = 103;
        return 0;
    }

    if ($ip =~ m/\.$/) {
        $ERROR = "Invalid IP $ip - ends with a dot";
        $ERRNO = 104;
        return 0;
    }

    # Single Numbers are considered to be IPv4
    if ($ip =~ m/^(\d+)$/ and $1 < 256) { return 1 }

    # Count quads
    my $n = ($ip =~ tr/\./\./);

    # IPv4 must have from 1 to 4 quads
    unless ($n >= 0 and $n < 4) {
        $ERROR = "Invalid IP address $ip";
        $ERRNO = 105;
        return 0;
    }

    # Check for empty quads
    if ($ip =~ m/\.\./) {
        $ERROR = "Empty quad in IP address $ip";
        $ERRNO = 106;
        return 0;
    }

    foreach (split /\./, $ip) {

        # Check for invalid quads
        unless ($_ >= 0 and $_ < 256) {
            $ERROR = "Invalid quad in IP address $ip - $_";
            $ERRNO = 107;
            return 0;
        }
    }
    return 1;
}

#------------------------------------------------------------------------------
# Subroutine ip_is_ipv6
# Purpose           : Check if an IP address is version 6
# Params            : IP address
# Returns           : 1 (yes) or 0 (no)
sub ip_is_ipv6 {
    my $ip = shift;

    # Count octets
    my $n = ($ip =~ tr/:/:/);
    return (0) unless ($n > 0 and $n < 8);

    # $k is a counter
    my $k;

    foreach (split /:/, $ip) {
        $k++;

        # Empty octet ?
        next if ($_ eq '');

        # Normal v6 octet ?
        next if (/^[a-f\d]{1,4}$/i);

        # Last octet - is it IPv4 ?
        if ($k == $n + 1) {
            next if (ip_is_ipv4($_));
        }

        $ERROR = "Invalid IP address $ip";
        $ERRNO = 108;
        return 0;
    }

    # Does the IP address start with : ?
    if ($ip =~ m/^:[^:]/) {
        $ERROR = "Invalid address $ip (starts with :)";
        $ERRNO = 109;
        return 0;
    }

    # Does the IP address finish with : ?
    if ($ip =~ m/[^:]:$/) {
        $ERROR = "Invalid address $ip (ends with :)";
        $ERRNO = 110;
        return 0;
    }

    # Does the IP address have more than one '::' pattern ?
    if ($ip =~ s/:(?=:)//g > 1) {
        $ERROR = "Invalid address $ip (More than one :: pattern)";
        $ERRNO = 111;
        return 0;
    }

    return 1;
}

#------------------------------------------------------------------------------
# Subroutine ip_expand_address
# Purpose           : Expand an address from compact notation
# Params            : IP address, IP version
# Returns           : expanded IP address or undef on failure
sub ip_expand_address {
    my ($ip, $ip_version) = @_;

    unless ($ip_version) {
        $ERROR = "Cannot determine IP version for $ip";
        $ERRNO = 101;
        return;
    }

    # v4 : add .0 for missing quads
    if ($ip_version == 4) {
        my @quads = split /\./, $ip;

        my @clean_quads = (0, 0, 0, 0);

        foreach my $q (reverse @quads) {
            unshift(@clean_quads, $q + 1 - 1);
        }

        return (join '.', @clean_quads[ 0 .. 3 ]);
    }

    # Keep track of ::
    $ip =~ s/::/:!:/;

    # IP as an array
    my @ip = split /:/, $ip;

    # Number of octets
    my $num = scalar(@ip);

    foreach (0 .. (scalar(@ip) - 1)) {

        # Embedded IPv4
        if ($ip[$_] =~ /\./) {

            # Expand Ipv4 address
            # Convert into binary
            # Convert into hex
            # Keep the last two octets

            $ip[$_] =
              substr(
                ip_bintoip(ip_iptobin(ip_expand_address($ip[$_], 4), 4), 6),
                -9);

            # Has an error occured here ?
            return unless (defined($ip[$_]));

            # $num++ because we now have one more octet:
            # IPv4 address becomes two octets
            $num++;
            next;
        }

        # Add missing trailing 0s
        $ip[$_] = ('0' x (4 - length($ip[$_]))) . $ip[$_];
    }

    # Now deal with '::' ('000!')
    foreach (0 .. (scalar(@ip) - 1)) {

        # Find the pattern
        next unless ($ip[$_] eq '000!');

        # @empty is the IP address 0
        my @empty = map { $_ = '0' x 4 } (0 .. 7);

        # Replace :: with $num '0000' octets
        $ip[$_] = join ':', @empty[ 0 .. 8 - $num ];
        last;
    }

    return (lc(join ':', @ip));
}

#------------------------------------------------------------------------------
# Subroutine ip_get_mask
# Purpose           : Get IP mask from prefix length.
# Params            : Prefix length, IP version
# Returns           : Binary Mask
sub ip_get_mask {
    my ($len, $ip_version) = @_;

    unless ($ip_version) {
        $ERROR = "Cannot determine IP version";
        $ERRNO = 101;
        return;
    }

    my $size = ip_iplengths($ip_version);

    # mask is $len 1s plus the rest as 0s
    return (('1' x $len) . ('0' x ($size - $len)));
}

#------------------------------------------------------------------------------
# Subroutine ip_last_address_bin
# Purpose           : Return the last binary address of a range
# Params            : First binary IP, prefix length, IP version
# Returns           : Binary IP
sub ip_last_address_bin {
    my ($binip, $len, $ip_version) = @_;

    unless ($ip_version) {
        $ERROR = "Cannot determine IP version";
        $ERRNO = 101;
        return;
    }

    my $size = ip_iplengths($ip_version);

    # Find the part of the IP address which will not be modified
    $binip = substr($binip, 0, $len);

    # Fill with 1s the variable part
    return ($binip . ('1' x ($size - length($binip))));
}

#------------------------------------------------------------------------------
# Subroutine ip_splitprefix
# Purpose           : Split a prefix into IP and prefix length
# Comments          : If it was passed a simple IP, it just returns it
# Params            : Prefix
# Returns           : IP, optionnaly length of prefix
sub ip_splitprefix {
    my $prefix = shift;

    # Find the '/'
    return unless ($prefix =~ m!^([^/]+?)(/\d+)?$!);

    my ($ip, $len) = ($1, $2);

    defined($len) and $len =~ s!/!!;

    return ($ip, $len);
}

#------------------------------------------------------------------------------
# Subroutine ip_prefix_to_range
# Purpose           : Get a range from a prefix
# Params            : IP, Prefix length, IP version
# Returns           : First IP, last IP
sub ip_prefix_to_range {
    my ($ip, $len, $ip_version) = @_;

    unless ($ip_version) {
        $ERROR = "Cannot determine IP version";
        $ERRNO = 101;
        return;
    }

    # Expand the first IP address
    $ip = ip_expand_address($ip, $ip_version);

    # Turn into a binary
    # Get last address
    # Turn into an IP
    my $binip = ip_iptobin($ip, $ip_version) or return;

    return unless (ip_check_prefix($binip, $len, $ip_version));

    my $lastip = ip_last_address_bin($binip, $len, $ip_version) or return;
    return unless ($lastip = ip_bintoip($lastip, $ip_version));

    return ($ip, $lastip);
}

#------------------------------------------------------------------------------
# Subroutine ip_is_valid_mask
# Purpose           : Check the validity of an IP mask (11110000)
# Params            : Mask
# Returns           : 1 or undef (invalid)
sub ip_is_valid_mask {
    my ($mask, $ip_version) = @_;

    unless ($ip_version) {
        $ERROR = "Cannot determine IP version for $mask";
        $ERRNO = 101;
        return;
    }

    my $len = ip_iplengths($ip_version);

    if (length($mask) != $len) {
        $ERROR = "Invalid mask length for $mask";
        $ERRNO = 150;
        return;
    }

    # The mask should be of the form 111110000000
    unless ($mask =~ m/^1*0*$/) {
        $ERROR = "Invalid mask $mask";
        $ERRNO = 151;
        return;
    }

    return 1;
}

#------------------------------------------------------------------------------
# Subroutine ip_bincomp
# Purpose           : Compare binary Ips with <, >, <=, >=
# Comments          : Operators are lt(<), le(<=), gt(>), and ge(>=)
# Params            : First binary IP, operator, Last binary Ip
# Returns           : 1 (yes), 0 (no), or undef (problem)
sub ip_bincomp {
    my ($begin, $op, $end) = @_;

    my ($b, $e);

    if ($op =~ /^l[te]$/)    # Operator is lt or le
    {
        ($b, $e) = ($end, $begin);
    }
    elsif ($op =~ /^g[te]$/)    # Operator is gt or ge
    {
        ($b, $e) = ($begin, $end);
    }
    else {
        $ERROR = "Invalid Operator $op\n";
        $ERRNO = 131;
        return;
    }

    # le or ge -> return 1 if IPs are identical
    return (1) if ($op =~ /e/ and ($begin eq $end));

    # Check IP sizes
    unless (length($b) eq length($e)) {
        $ERROR = "IP addresses of different length\n";
        $ERRNO = 130;
        return;
    }

    my $c;

    # Foreach bit
    for (0 .. length($b) - 1) {

        # substract the two bits
        $c = substr($b, $_, 1) - substr($e, $_, 1);

        # Check the result
        return (1) if ($c == 1);
        return (0) if ($c == -1);
    }

    # IPs are identical
    return 0;
}

#------------------------------------------------------------------------------
# Subroutine ip_binadd
# Purpose           : Add two binary IPs
# Params            : First binary IP, Last binary Ip
# Returns           : Binary sum or undef (problem)
sub ip_binadd {
    my ($b, $e) = @_;

    # Check IP length
    unless (length($b) eq length($e)) {
        $ERROR = "IP addresses of different length\n";
        $ERRNO = 130;
        return;
    }

    # Reverse the two IPs
    $b = scalar(reverse $b);
    $e = scalar(reverse $e);

    my ($carry, $result, $c) = (0);

    # Foreach bit (reversed)
    for (0 .. length($b) - 1) {

        # add the two bits plus the carry
        $c     = substr($b, $_, 1) + substr($e, $_, 1) + $carry;
        $carry = 0;

        # sum = 0 => $c = 0, $carry = 0
        # sum = 1 => $c = 1, $carry = 0
        # sum = 2 => $c = 0, $carry = 1
        # sum = 3 => $c = 1, $carry = 1
        if ($c > 1) {
            $c -= 2;
            $carry = 1;
        }

        $result .= $c;
    }

    # Reverse result
    return scalar(reverse($result));
}

#------------------------------------------------------------------------------
# Subroutine ip_get_prefix_length
# Purpose           : Get the prefix length for a given range of IPs
# Params            : First binary IP, Last binary IP
# Returns           : Length of prefix or undef (problem)
sub ip_get_prefix_length {
    my ($bin1, $bin2) = @_;

    # Check length of IPs
    unless (length($bin1) eq length($bin2)) {
        $ERROR = "IP addresses of different length\n";
        $ERRNO = 130;
        return;
    }

    # reverse IPs
    $bin1 = scalar(reverse $bin1);
    $bin2 = scalar(reverse $bin2);

    # foreach bit
    for (0 .. length($bin1) - 1) {

        # If bits are equal it means we have reached the longest prefix
        return ("$_") if (substr($bin1, $_, 1) eq substr($bin2, $_, 1));

    }

    # Return 32 (IPv4) or 128 (IPv6)
    return length($bin1);
}

#------------------------------------------------------------------------------
# Subroutine ip_range_to_prefix
# Purpose           : Return all prefixes between two IPs
# Params            : First IP, Last IP, IP version
# Returns           : List of Prefixes or undef (problem)
sub ip_range_to_prefix {
    my ($binip, $endbinip, $ip_version) = @_;

    unless ($ip_version) {
        $ERROR = "Cannot determine IP version";
        $ERRNO = 101;
        return;
    }

    unless (length($binip) eq length($endbinip)) {
        $ERROR = "IP addresses of different length\n";
        $ERRNO = 130;
        return;
    }

    my ($len, $nbits, $current, $add, @prefix);

    # 1 in binary
    my $one = ('0' x (ip_iplengths($ip_version) - 1)) . '1';

    # While we have not reached the last IP
    while (ip_bincomp($binip, 'le', $endbinip) == 1) {

        # Find all 0s at the end
        if ($binip =~ m/(0+)$/) {

            # nbits = nb of 0 bits
            $nbits = length($1);
        }
        else {
            $nbits = 0;
        }

        do {
            $current = $binip;
            $add     = '1' x $nbits;

            # Replace $nbits 0s with 1s
            $current =~ s/0{$nbits}$/$add/;
            $nbits--;

            # Decrease $nbits if $current >= $endbinip
        } while (ip_bincomp($current, 'le', $endbinip) != 1);

        # Find Prefix length
        $len =
          (ip_iplengths($ip_version)) - ip_get_prefix_length($binip, $current);

        # Push prefix in list
        push(@prefix, ip_bintoip($binip, $ip_version) . "/$len");

        # Add 1 to current IP
        $binip = ip_binadd($current, $one);

        # Exit if IP is 32/128 1s
        last if ($current =~ m/^1+$/);
    }

    return (@prefix);
}

#------------------------------------------------------------------------------
# Subroutine ip_compress_v4_prefix
# Purpose           : Compress an IPv4 Prefix
# Params            : IP, Prefix length
# Returns           : Compressed IP - ie: 194.5
sub ip_compress_v4_prefix {
    my ($ip, $len) = @_;

    my @quads = split /\./, $ip;

    my $qlen = int(($len - 1) / 8);

    $qlen = 0 if ($qlen < 0);

    my $newip = join '.', @quads[ 0 .. $qlen ];

    return ($newip);
}

#------------------------------------------------------------------------------
# Subroutine ip_compress_address
# Purpose           : Compress an IPv6 address
# Params            : IP, IP version
# Returns           : Compressed IP or undef (problem)
sub ip_compress_address {
    my ($ip, $ip_version) = @_;

    unless ($ip_version) {
        $ERROR = "Cannot determine IP version for $ip";
        $ERRNO = 101;
        return;
    }

    # Just return if IP is IPv4
    return ($ip) if ($ip_version == 4);

    # Remove leading 0s: 0034 -> 34; 0000 -> 0
    $ip =~ s/
	(^|:)        # Find beginning or ':' -> $1
	0+           # 1 or several 0s
	(?=          # Look-ahead
	[a-fA-F\d]+  # One or several Hexs
	(?::|$))     # ':' or end
	/$1/gx;

    my $reg = '';

    # Find the longuest :0:0: sequence
    while (
        $ip =~ m/
	((?:^|:)     # Find beginning or ':' -> $1
	0(?::0)+     # 0 followed by 1 or several ':0'
	(?::|$))     # ':' or end
	/gx
      )
    {
        $reg = $1 if (length($reg) < length($1));
    }

    # Replace sequence by '::'
    $ip =~ s/$reg/::/ if ($reg ne '');

    return $ip;
}

#------------------------------------------------------------------------------
# Subroutine ip_is_overlap
# Purpose           : Check if two ranges overlap
# Params            : Four binary IPs (begin of range 1,end1,begin2,end2)
# Returns           : $NO_OVERLAP         (no overlap)
#                     $IP_PARTIAL_OVERLAP (overlap)
#                     $IP_A_IN_B_OVERLAP  (range1 is included in range2)
#                     $IP_B_IN_A_OVERLAP  (range2 is included in range1)
#                     $IP_IDENTICAL       (range1 == range2)
#                     or undef (problem)

sub ip_is_overlap {
    my ($b1, $e1, $b2, $e2) = (@_);

    my $swap;
    $swap = 0;

    unless ((length($b1) eq length($e1))
        and (length($b2) eq length($e2))
        and (length($b1) eq length($b2)))
    {
        $ERROR = "IP addresses of different length\n";
        $ERRNO = 130;
        return;
    }

    # begin1 <= end1 ?
    unless (ip_bincomp($b1, 'le', $e1) == 1) {
        $ERROR = "Invalid range	$b1 - $e1";
        $ERRNO = 140;
        return;
    }

    # begin2 <= end2 ?
    unless (ip_bincomp($b2, 'le', $e2) == 1) {
        $ERROR = "Invalid range	$b2 - $e2";
        $ERRNO = 140;
        return;
    }

    # b1 == b2 ?
    if ($b1 eq $b2) {

        # e1 == e2
        return ($IP_IDENTICAL) if ($e1 eq $e2);

        # e1 < e2 ?
        return (
            ip_bincomp($e1, 'lt', $e2)
            ? $IP_A_IN_B_OVERLAP
            : $IP_B_IN_A_OVERLAP
        );
    }

    # e1 == e2 ?
    if ($e1 eq $e2) {

        # b1 < b2
        return (
            ip_bincomp($b1, 'lt', $b2)
            ? $IP_B_IN_A_OVERLAP
            : $IP_A_IN_B_OVERLAP
        );
    }

    # b1 < b2
    if ((ip_bincomp($b1, 'lt', $b2) == 1)) {

        # e1 < b2
        return ($IP_NO_OVERLAP) if (ip_bincomp($e1, 'lt', $b2) == 1);

        # e1 < e2 ?
        return (
            ip_bincomp($e1, 'lt', $e2)
            ? $IP_PARTIAL_OVERLAP
            : $IP_B_IN_A_OVERLAP
        );
    }
    else    # b1 > b2
    {

        # e2 < b1
        return ($IP_NO_OVERLAP) if (ip_bincomp($e2, 'lt', $b1) == 1);

        # e2 < e1 ?
        return (
            ip_bincomp($e2, 'lt', $e1)
            ? $IP_PARTIAL_OVERLAP
            : $IP_A_IN_B_OVERLAP
        );
    }
}

#------------------------------------------------------------------------------
# Subroutine get_embedded_ipv4
# Purpose           : Get an IPv4 embedded in an IPv6 address
# Params            : IPv6
# Returns           : IPv4 or undef (not found)
sub ip_get_embedded_ipv4 {
    my $ipv6 = shift;

    my @ip = split /:/, $ipv6;

    # Bugfix by Norbert Koch
    return unless (@ip);

    # last octet should be ipv4
    return ($ip[-1]) if (ip_is_ipv4($ip[-1]));

    return;
}

#------------------------------------------------------------------------------
# Subroutine aggregate
# Purpose           : Aggregate 2 ranges
# Params            : 1st range (1st IP, Last IP), last range (1st IP, last IP),
#                     IP version
# Returns           : prefix or undef (invalid)
sub ip_aggregate {
    my ($binbip1, $bineip1, $binbip2, $bineip2, $ip_version) = @_;

    unless ($ip_version) {
        $ERROR = "Cannot determine IP version for $binbip1";
        $ERRNO = 101;
        return;
    }

    # Bin 1
    my $one = (('0' x (ip_iplengths($ip_version) - 1)) . '1');

    # $eip1 + 1 = $bip2 ?
    unless (ip_binadd($bineip1, $one) eq $binbip2) {
        $ERROR = "Ranges not contiguous - $bineip1 - $binbip2";
        $ERRNO = 160;
        return;
    }

    # Get ranges
    my @prefix = ip_range_to_prefix($binbip1, $bineip2, $ip_version);

    # There should be only one range
    return if scalar(@prefix) < 1;

    if (scalar(@prefix) > 1) {
        $ERROR = "$binbip1 - $bineip2 is not a single prefix";
        $ERRNO = 161;
        return;
    }
    return ($prefix[0]);

}

#------------------------------------------------------------------------------
# Subroutine _iptype
# Purpose           : Return the type of an IP (Public, Private, Reserved)
# Params            : IP to test, IP version
# Returns           : type or undef (invalid)
sub ip_iptype {
    my ($ip, $ip_version) = @_;

    # Find IP version

    if ($ip_version == 4) {
        foreach (sort { length($b) <=> length($a) } keys %IPv4ranges) {
            return ($IPv4ranges{$_}) if ($ip =~ m/^$_/);
        }

        # IP is public
        return 'PUBLIC';
    }

    foreach (sort { length($b) <=> length($a) } keys %IPv6ranges) {
        return ($IPv6ranges{$_}) if ($ip =~ m/^$_/);
    }

    $ERROR = "Cannot determine type for $ip";
    $ERRNO = 180;
    return;
}

#------------------------------------------------------------------------------
# Subroutine ip_check_prefix
# Purpose           : Check the validity of a prefix
# Params            : binary IP, length of prefix, IP version
# Returns           : 1 or undef (invalid)
sub ip_check_prefix {
    my ($binip, $len, $ipversion) = (@_);

    # Check if len is longer than IP
    if ($len > length($binip)) {
        $ERROR =
          "Prefix length $len is longer than IP address ("
          . length($binip) . ")";
        $ERRNO = 170;
        return;
    }

    my $rest = substr($binip, $len);

    # Check if last part of the IP (len part) has only 0s
    unless ($rest =~ /^0*$/) {
        $ERROR = "Invalid prefix $binip/$len";
        $ERRNO = 171;
        return;
    }

    # Check if prefix length is correct
    unless (length($rest) + $len == ip_iplengths($ipversion)) {
        $ERROR = "Invalid prefix length /$len";
        $ERRNO = 172;
        return;
    }

    return 1;
}

#------------------------------------------------------------------------------
# Subroutine ip_reverse
# Purpose           : Get a reverse name from a prefix
# Comments          : From Lee's iplib.pm
# Params            : IP, length of prefix, IP version
# Returns           : Reverse name or undef (error)
sub ip_reverse {
    my ($ip, $len, $ip_version) = (@_);

    $ip_version ||= ip_get_version($ip);
    unless ($ip_version) {
        $ERROR = "Cannot determine IP version for $ip";
        $ERRNO = 101;
        return;
    }

    if ($ip_version == 4) {
        my @quads    = split /\./, $ip;
        my $no_quads = ($len / 8);

        my @reverse_quads = reverse @quads;

        while (@reverse_quads and $reverse_quads[0] == 0) {
            shift(@reverse_quads);
        }

        return join '.', @reverse_quads, 'in-addr', 'arpa.';
    }
    elsif ($ip_version == 6) {
        my @rev_groups = reverse split /:/, $ip;
        my @result;

        foreach (@rev_groups) {
            my @revhex = reverse split //;
            push @result, @revhex;
        }

        # This takes the zone above if it's not exactly on a nibble
        my $first_nibble_index = $len ? 32 - (int($len / 4)) : 0;
        return join '.', @result[ $first_nibble_index .. $#result ], 'ip6',
          'arpa.';
    }
}

#------------------------------------------------------------------------------
# Subroutine ip_normalize
# Purpose           : Normalize data to a range of IP addresses
# Params            : IP or prefix or range
# Returns           : ip1, ip2 (if range) or undef (error)
sub ip_normalize {
    my ($data) = shift;

    my $ipversion;

    my ($len, $ip, $ip2, $real_len, $first, $last, $curr_bin, $addcst, $clen);

    # Prefix
    if ($data =~ m!^(\S+?)(/\S+)$!) {
        ($ip, $len) = ($1, $2);

        return unless ($ipversion = ip_get_version($ip));
        return unless ($ip        = ip_expand_address($ip, $ipversion));
        return unless ($curr_bin  = ip_iptobin($ip, $ipversion));

        my $one = '0' x (ip_iplengths($ipversion) - 1) . '1';

        while ($len) {
            last unless ($len =~ s!^/(\d+)(\,|$)!!);

            $clen   = $1;
            $addcst = length($2) > 0;

            return unless (ip_check_prefix($curr_bin, $clen, $ipversion));

            return
              unless ($curr_bin =
                ip_last_address_bin($curr_bin, $clen, $ipversion));

            if ($addcst) {
                return unless ($curr_bin = ip_binadd($curr_bin, $one));
            }
        }

        return ($ip, ip_bintoip($curr_bin, $ipversion));
    }

    # Range
    elsif ($data =~ /^(.+?)\s*\-\s*(.+)$/) {
        ($ip, $ip2) = ($1, $2);

        return unless ($ipversion = ip_get_version($ip));

        return unless ($ip  = ip_expand_address($ip,  $ipversion));
        return unless ($ip2 = ip_expand_address($ip2, $ipversion));

        return ($ip, $ip2);
    }

    # IP + Number
    elsif ($data =~ /^(.+?)\+(.+)$/) {
        ($ip, $len) = ($1, $2);

        return unless ($ipversion = ip_get_version($ip));
        return unless ($ip        = ip_expand_address($ip, $ipversion));

        my ($bin_ip);
        return unless ($bin_ip = ip_iptobin($ip, $ipversion));

        return unless ($len = ip_inttobin($len, $ipversion));

        return unless ($ip2 = ip_binadd($bin_ip, $len));
        return unless ($ip2 = ip_bintoip($ip2,   $ipversion));

        return ($ip, $ip2);
    }

    # Single IP
    else {
        $ip = $data;

        return unless ($ipversion = ip_get_version($ip));

        return unless ($ip = ip_expand_address($ip, $ipversion));

        return $ip;
    }
}

#------------------------------------------------------------------------------
# Subroutine normal_range
# Purpose           : Return the normalized format of a range
# Params            : IP or prefix or range
# Returns           : "ip1 - ip2" or undef (error)
sub ip_normal_range {
    my ($data) = shift;

    my ($ip1, $ip2) = ip_normalize($data);

    return unless ($ip1);

    $ip2 ||= $ip1;

    return ("$ip1 - $ip2");
}

#------------------------------------------------------------------------------
# Subroutine ip_auth
# Purpose           : Get Authority information from IP::Authority Module
# Comments          : Requires IP::Authority
# Params            : IP, length of prefix
# Returns           : Reverse name or undef (error)
sub ip_auth {
    my ($ip, $ip_version) = (@_);

    unless ($ip_version) {
        $ERROR = "Cannot determine IP version for $ip";
        $ERRNO = 101;
        die;
        return;
    }

    if ($ip_version != 4) {

        $ERROR = "Cannot get auth information: Not an IPv4 address";
        $ERRNO = 308;
        die;
        return;
    }

    require IP::Authority;

    my $reg = new IP::Authority;

    return ($reg->inet_atoauth($ip));
}

1;

__END__

=head1 NAME

Net::IP - Perl extension for manipulating IPv4/IPv6 addresses

=head1 SYNOPSIS

  use Net::IP;
  
  my $ip = new Net::IP ('193.0.1/24') or die (Net::IP::Error());
  print ("IP  : ".$ip->ip()."\n");
  print ("Sho : ".$ip->short()."\n");
  print ("Bin : ".$ip->binip()."\n");
  print ("Int : ".$ip->intip()."\n");
  print ("Mask: ".$ip->mask()."\n");
  print ("Last: ".$ip->last_ip()."\n");
  print ("Len : ".$ip->prefixlen()."\n");
  print ("Size: ".$ip->size()."\n");
  print ("Type: ".$ip->iptype()."\n");
  print ("Rev:  ".$ip->reverse_ip()."\n");

=head1 DESCRIPTION

This module provides functions to deal with B<IPv4/IPv6> addresses. The module
can be used as a class, allowing the user to instantiate IP objects, which can
be single IP addresses, prefixes, or ranges of addresses. There is also a 
procedural way of accessing most of the functions. Most subroutines can take 
either B<IPv4> or B<IPv6> addresses transparently.

=head1 OBJECT-ORIENTED INTERFACE

=head2 Object Creation

A Net::IP object can be created from a single IP address:
  
  $ip = new Net::IP ('193.0.1.46') || die ...
  
Or from a Classless Prefix (a /24 prefix is equivalent to a C class):

  $ip = new Net::IP ('195.114.80/24') || die ...

Or from a range of addresses:

  $ip = new Net::IP ('20.34.101.207 - 201.3.9.99') || die ...
  
Or from a address plus a number:

  $ip = new Net::IP ('20.34.10.0 + 255') || die ...
  
The new() function accepts IPv4 and IPv6 addresses:

  $ip = new Net::IP ('dead:beef::/32') || die ...

Optionnaly, the function can be passed the version of the IP. Otherwise, it
tries to guess what the version is (see B<_is_ipv4()> and B<_is_ipv6()>).

  $ip = new Net::IP ('195/8',4); # Class A

=head1 OBJECT METHODS

Most of these methods are front-ends for the real functions, which use a 
procedural interface. Most functions return undef on failure, and a true
value on success. A detailed description of the procedural interface is 
provided below.

=head2 set

Set an IP address in an existing IP object. This method has the same 
functionality as the new() method, except that it reuses an existing object to
store the new IP.

C<$ip-E<gt>set('130.23.1/24',4);>

Like new(), set() takes two arguments - a string used to build an IP address,
prefix, or range, and optionally, the IP version of the considered address.

It returns an IP object on success, and undef on failure.

=head2 error

Return the current object error string. The error string is set whenever one 
of the methods produces an error. Also, a global, class-wide B<Error()> 
function is avaliable.

C<warn ($ip-E<gt>error());>

=head2 errno

Return the current object error number. The error number is set whenever one 
of the methods produces an error. Also, a global B<$ERRNO> variable is set
when an error is produced.

C<warn ($ip-E<gt>errno());>

=head2 ip

Return the IP address (or first IP of the prefix or range) in quad format, as
a string.

C<print ($ip-E<gt>ip());>

=head2 binip

Return the IP address as a binary string of 0s and 1s.

C<print ($ip-E<gt>binip());>

=head2 prefixlen

Return the length in bits of the current prefix.

C<print ($ip-E<gt>prefixlen());>

=head2 version

Return the version of the current IP object (4 or 6).

C<print ($ip-E<gt>version());>

=head2 size

Return the number of IP addresses in the current prefix or range.
Use of this function requires Math::BigInt.

C<print ($ip-E<gt>size());>

=head2 binmask

Return the binary mask of the current prefix, if applicable.

C<print ($ip-E<gt>binmask());>

=head2 mask

Return the mask in quad format of the current prefix.

C<print ($ip-E<gt>mask());>

=head2 prefix

Return the full prefix (ip+prefix length) in quad (standard) format.

C<print ($ip-E<gt>prefix());>

=head2 print

Print the IP object (IP/Prefix or First - Last)

C<print ($ip-E<gt>print());>

=head2 intip

Convert the IP in integer format and return it as a Math::BigInt object.

C<print ($ip-E<gt>intip());>

=head2 short

Return the IP in short format:  
	IPv4 addresses: 194.5/16
	IPv6 addresses: ab32:f000::


C<print ($ip-E<gt>short());>

=head2 iptype

Return the IP Type - this describes the type of an IP (Public, Private, 
Reserved, etc.)

C<print ($ip-E<gt>iptype());>

=head2 reverse_ip

Return the reverse IP for a given IP address (in.addr. format).

C<print ($ip-E<gt>reserve_ip());>

=head2 last_ip

Return the last IP of a prefix/range in quad format.

C<print ($ip-E<gt>last_ip());>

=head2 last_bin

Return the last IP of a prefix/range in binary format.

C<print ($ip-E<gt>last_bin());>

=head2 last_int

Return the last IP of a prefix/range in integer format.

C<print ($ip-E<gt>last_int());>

=head2 find_prefixes

This function finds all the prefixes that can be found between the two 
addresses of a range. The function returns a list of prefixes.

C<@list = $ip-E<gt>find_prefixes($other_ip));>

=head2 bincomp

Binary comparaison of two IP objects. The function takes an operation 
and an IP object as arguments. It returns a boolean value.

The operation can be one of:
lt: less than (smaller than)
le: smaller or equal to
gt: greater than
ge: greater or equal to

C<if ($ip-E<gt>bincomp('lt',$ip2) {...}>

=head2 binadd

Binary addition of two IP objects. The value returned is an IP object.

C<my $sum = $ip-E<gt>binadd($ip2);>

=head2 aggregate

Aggregate 2 IPs - Append one range/prefix of IPs to another. The last address
of the first range must be the one immediately preceding the first address of 
the second range. A new IP object is returned.

C<my $total = $ip-E<gt>aggregate($ip2);>

=head2 overlaps

Check if two IP ranges/prefixes overlap each other. The value returned by the 
function should be one of:
	$IP_PARTIAL_OVERLAP (ranges overlap) 
	$IP_NO_OVERLAP      (no overlap)
	$IP_A_IN_B_OVERLAP  (range2 contains range1)
	$IP_B_IN_A_OVERLAP  (range1 contains range2)
	$IP_IDENTICAL       (ranges are identical)
	undef               (problem)

C<if ($ip-E<gt>overlaps($ip2)==$IP_A_IN_B_OVERLAP) {...};>


=head2 looping

The C<+> operator is overloaded in order to allow looping though a whole 
range of IP addresses:

  my $ip = new Net::IP ('195.45.6.7 - 195.45.6.19') || die;
  # Loop
  do {
      print $ip->ip(), "\n";
  } while (++$ip);



The ++ operator returns undef when the last address of the range is reached.


=head2 auth

Return IP authority information from the IP::Authority module

C<$auth = ip->auth ();>

Note: IPv4 only


=head1 PROCEDURAL INTERFACE

These functions do the real work in the module. Like the OO methods, 
most of these return undef on failure. In order to access error codes
and strings, instead of using $ip-E<gt>error() and $ip-E<gt>errno(), use the
global functions C<Error()> and C<Errno()>.

The functions of the procedural interface are not exported by default. In
order to import these functions, you need to modify the use statement for
the module:

C<use Net::IP qw(:PROC);>

=head2 Error

Returns the error string corresponding to the last error generated in the 
module. This is also useful for the OO interface, as if the new() function 
fails, we cannot call $ip-E<gt>error() and so we have to use Error().

warn Error();

=head2 Errno

Returns a numeric error code corresponding to the error string returned by 
Error.

=head2 ip_iptobin

Transform an IP address into a bit string. 

    Params  : IP address, IP version
    Returns : binary IP string on success, undef otherwise

C<$binip = ip_iptobin ($ip,6);>

=head2 ip_bintoip

Transform a bit string into an IP address

    Params  : binary IP, IP version
    Returns : IP address on success, undef otherwise

C<$ip = ip_bintoip ($binip,6);>

=head2 ip_bintoint

Transform a bit string into a BigInt.

    Params  : binary IP
    Returns : BigInt

C<$bigint = new Math::BigInt (ip_bintoint($binip));>

=head2 ip_inttobin

Transform a BigInt into a bit string.
I<Warning>: sets warnings (C<-w>) off. This is necessary because Math::BigInt 
is not compliant.

    Params  : BigInt, IP version
    Returns : binary IP

C<$binip = ip_inttobin ($bigint);>

=head2 ip_get_version

Try to guess the IP version of an IP address.

    Params  : IP address
    Returns : 4, 6, undef(unable to determine)

C<$version = ip_get_version ($ip)>

=head2 ip_is_ipv4

Check if an IP address is of type 4.

    Params  : IP address
    Returns : 1 (yes) or 0 (no)

C<ip_is_ipv4($ip) and print "$ip is IPv4";>

=head2 ip_is_ipv6

Check if an IP address is of type 6.

    Params            : IP address
    Returns           : 1 (yes) or 0 (no)

C<ip_is_ipv6($ip) and print "$ip is IPv6";>

=head2 ip_expand_address

Expand an IP address from compact notation.

    Params  : IP address, IP version
    Returns : expanded IP address or undef on failure

C<$ip = ip_expand_address ($ip,4);>

=head2 ip_get_mask

Get IP mask from prefix length.

    Params  : Prefix length, IP version
    Returns : Binary Mask

C<$mask = ip_get_mask ($len,6);>

=head2 ip_last_address_bin

Return the last binary address of a prefix.

    Params  : First binary IP, prefix length, IP version
    Returns : Binary IP

C<$lastbin = ip_last_address_bin ($ip,$len,6);>

=head2 ip_splitprefix

Split a prefix into IP and prefix length.
If it was passed a simple IP, it just returns it.

    Params  : Prefix
    Returns : IP, optionnaly length of prefix

C<($ip,$len) = ip_splitprefix ($prefix)>

=head2 ip_prefix_to_range

Get a range of IPs from a prefix.

    Params  : Prefix, IP version
    Returns : First IP, last IP

C<($ip1,$ip2) = ip_prefix_to_range ($prefix,6);>

=head2 ip_bincomp

Compare binary Ips with <, >, <=, >=.
 Operators are lt(<), le(<=), gt(>), and ge(>=) 
 
    Params  : First binary IP, operator, Last binary IP
    Returns : 1 (yes), 0 (no), or undef (problem)

C<ip_bincomp ($ip1,'lt',$ip2) == 1 or do {}>

=head2 ip_binadd

Add two binary IPs.

    Params  : First binary IP, Last binary IP
    Returns : Binary sum or undef (problem)

C<$binip = ip_binadd ($bin1,$bin2);>

=head2 ip_get_prefix_length

Get the prefix length for a given range of 2 IPs.

    Params  : First binary IP, Last binary IP
    Returns : Length of prefix or undef (problem)

C<$len = ip_get_prefix_length ($ip1,$ip2);>

=head2 ip_range_to_prefix

Return all prefixes between two IPs.

    Params  : First IP, Last IP, IP version
    Returns : List of Prefixes or undef (problem)

The prefixes returned have the form q.q.q.q/nn.

C<@prefix = ip_range_to_prefix ($ip1,$ip2,6);>


=head2 ip_compress_v4_prefix

Compress an IPv4 Prefix.

    Params  : IP, Prefix length
    Returns : Compressed Prefix

C<$ip = ip_compress_v4_prefix ($ip, $len);>


=head2 ip_compress_address

Compress an IPv6 address. Just returns the IP if it is an IPv4.

    Params  : IP, IP version
    Returns : Compressed IP or undef (problem)

C<$ip = ip_compress_adress ($ip, $version);>

=head2 ip_is_overlap

Check if two ranges of IPs overlap.

    Params  : Four binary IPs (begin of range 1,end1,begin2,end2), IP version
	$IP_PARTIAL_OVERLAP (ranges overlap) 
	$IP_NO_OVERLAP      (no overlap)
	$IP_A_IN_B_OVERLAP  (range2 contains range1)
	$IP_B_IN_A_OVERLAP  (range1 contains range2)
	$IP_IDENTICAL       (ranges are identical)
	undef               (problem)

C<(ip_is_overlap($rb1,$re1,$rb2,$re2,4) eq $IP_A_IN_B_OVERLAP) and do {};>

=head2 ip_get_embedded_ipv4

Get an IPv4 embedded in an IPv6 address

    Params  : IPv6
    Returns : IPv4 string or undef (not found)

C<$ip4 = ip_get_embedded($ip6);>

=head2 ip_check_mask

Check the validity of a binary IP mask

    Params  : Mask
    Returns : 1 or undef (invalid)

C<ip_check_mask($binmask) or do {};>

Checks if mask has only 1s followed by 0s.

=head2 ip_aggregate

Aggregate 2 ranges of binary IPs

    Params  : 1st range (1st IP, Last IP), last range (1st IP, last IP), IP version
    Returns : prefix or undef (invalid)

C<$prefix = ip_aggregate ($bip1,$eip1,$bip2,$eip2) || die ...>

=head2 ip_iptype

Return the type of an IP (Public, Private, Reserved)

    Params  : IP to test, IP version
    Returns : type or undef (invalid)

C<$type = ip_iptype ($ip);>    

=head2 ip_check_prefix

Check the validity of a prefix

    Params  : binary IP, length of prefix, IP version
    Returns : 1 or undef (invalid)

Checks if the variant part of a prefix only has 0s, and the length is correct.

C<ip_check_prefix ($ip,$len,$ipv) or do {};>

=head2 ip_reverse

Get a reverse name from a prefix

    Params  : IP, length of prefix, IP version
    Returns : Reverse name or undef (error)

C<$reverse = ip_reverse ($ip);>

=head2 ip_normalize

Normalize data to a range/prefix of IP addresses

    Params  : Data String (Single IP, Range, Prefix)
    Returns : ip1, ip2 (if range/prefix) or undef (error)

C<($ip1,$ip2) = ip_normalize ($data);>

=head2 ip_auth

Return IP authority information from the IP::Authority module

    Params  : IP, version
    Returns : Auth info (RI for RIPE, AR for ARIN, etc)

C<$auth = ip_auth ($ip,4);>

Note: IPv4 only


=head1 BUGS

The Math::BigInt library is needed for functions that use integers. These are
ip_inttobin, ip_bintoint, and the size method. In a next version, 
Math::BigInt will become optionnal.

=head1 AUTHORS

Manuel Valente <manuel.valente@gmail.com>.

Original IPv4 code by Monica Cortes Sack <mcortes@ripe.net>.

Original IPv6 code by Lee Wilmot <lee@ripe.net>.

=head1 BASED ON

ipv4pack.pm, iplib.pm, iplibncc.pm.

=head1 SEE ALSO

perl(1), IP::Authority

=cut
