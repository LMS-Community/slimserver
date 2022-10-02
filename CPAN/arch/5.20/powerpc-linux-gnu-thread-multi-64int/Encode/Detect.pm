package Encode::Detect;

# * ***** BEGIN LICENSE BLOCK *****
# Version: MPL 1.1/GPL 2.0/LGPL 2.1
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
# http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.
#
# The Original Code is Encode::Detect wrapper
#
# The Initial Developer of the Original Code is
# Proofpoint, Inc.
# Portions created by the Initial Developer are Copyright (C) 2005
# the Initial Developer. All Rights Reserved.
#
# Contributor(s):
#
# Alternatively, the contents of this file may be used under the terms of
# either the GNU General Public License Version 2 or later (the "GPL"), or
# the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
# in which case the provisions of the GPL or the LGPL are applicable instead
# of those above. If you wish to allow use of your version of this file only
# under the terms of either the GPL or the LGPL, and not to allow others to
# use your version of this file under the terms of the MPL, indicate your
# decision by deleting the provisions above and replace them with the notice
# and other provisions required by the GPL or the LGPL. If you do not delete
# the provisions above, a recipient may use your version of this file under
# the terms of any one of the MPL, the GPL or the LGPL.
#
# ***** END LICENSE BLOCK *****

use strict;
use warnings;
use base qw(Encode::Encoding);
use Encode qw(find_encoding);
use Encode::Detect::Detector;

__PACKAGE__->Define(qw(Detect));

our $VERSION = "1.00";

sub perlio_ok { 0 }

sub decode ($$;$) {
    my ($self, $octets, $check) = @_;
    my $charset = detect($octets) || 'Windows-1252';
    my $e = find_encoding($charset) or die "Unknown encoding: $charset";
    my $decoded = $e->decode($octets, $check || 0);
    $_[1] = $octets if $check;
    return $decoded;
}

1;

__END__

=head1 NAME

Encode::Detect - An Encode::Encoding subclass that detects the encoding of data

=head1 SYNOPSIS

  use Encode;
  require Encode::Detect;
  my $utf8 = decode("Detect", $data);

=head1 DESCRIPTION

This Perl module is an Encode::Encoding subclass that uses
Encode::Detect::Detector to determine the charset of the input data
and then decodes it using the encoder of the detected charset.

It is similar to Encode::Guess, but does not require the configuration
of a set of expected encodings.  Like Encode::Guess, it only supports
decoding--it cannot encode.

=head1 SEE ALSO

L<Encode>, L<Encode::Encoding>, L<Encode::Detect::Detector>

=head1 AUTHOR

John Gardiner Myers <jgmyers@proofpoint.com>

=head1 SUPPORT

For help and thank you notes, e-mail the author directly.  To report a
bug, submit a patch, or add to the wishlist please visit the CPAN bug
manager at: F<http://rt.cpan.org>


