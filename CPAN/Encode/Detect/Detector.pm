package Encode::Detect::Detector;

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

our $VERSION = "1.00";

require DynaLoader;
our @ISA=qw(DynaLoader Exporter);
Encode::Detect::Detector->bootstrap($VERSION);
our @EXPORT=qw(detect);


1;

__END__

=head1 NAME

Encode::Detect::Detector - Detects the encoding of data

=head1 SYNOPSIS

  use Encode::Detect::Detector;
  my $charset = detect($octets);

  my $d = new Encode::Detect::Detector;
  $d->handle($octets);
  $d->handle($more_octets);
  $d->end;
  my $charset = $d->getresult;

=head1 DESCRIPTION

This module provides an interface to Mozilla's universal charset
detector, which detects the charset used to encode data.

=head1 METHODS

=head2 $charset = Encode::Detect::Detector->detect($octets)

Detect the charset used to encode the data in $octets and return the
charset's name.  Returns undef if the charset cannot be determined
with sufficient confidence.

=head2 $d = Encode::Detect::Detector->new()

Creates a new C<Encode::Detect::Detector> object and returns it.

=head2 $d->handle($octets)

Provides an additional chunk of data to be examined by the detector.
May be called multiple times.

Returns zero on success, nonzero if a memory allocation failed.

=head2 $d->eof

Informs the detector that there is no more data to be examined.  In
many cases, this is necessary in order for the detector to make a
decision on the charset.

=head2 $d->reset

Resets the detector to its initial state.

=head2 $d->getresult

Returns the name of the detected charset or C<undef> if no charset has
(yet) been decided upon.  May be called at any time.

=head1 SEE ALSO

L<Encode::Detect>

=head1 AUTHOR

John Gardiner Myers <jgmyers@proofpoint.com>

=head1 SUPPORT

For help and thank you notes, e-mail the author directly.  To report a
bug, submit a patch, or add to the wishlist please visit the CPAN bug
manager at: F<http://rt.cpan.org>


