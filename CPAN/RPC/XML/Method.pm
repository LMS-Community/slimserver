###############################################################################
#
# This file copyright (c) 2001 by Randy J. Ray, all rights reserved
#
# Copying and distribution are permitted under the terms of the Artistic
# License as distributed with Perl versions 5.005 and later. See
# http://www.opensource.org/licenses/artistic-license.php
#
###############################################################################
#
#   $Id: Method.pm,v 1.8 2004/12/09 08:50:17 rjray Exp $
#
#   Description:    This is now an empty sub-class of RPC::XML::Procedure.
#                   It is given its own file to allow for a minimal manual
#                   page redirecting people to the newer class.
#
#   Functions:      None.
#
#   Libraries:      RPC::XML::Procedure
#
#   Global Consts:  $VERSION
#
#   Environment:    None.
#
###############################################################################

package RPC::XML::Method;

use 5.005;
use strict;
use vars qw($VERSION);

require RPC::XML::Procedure;

@RPC::XML::Method::ISA = qw(RPC::XML::Procedure);
$VERSION = do { my @r=(q$Revision: 1.8 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

1;

__END__

=head1 NAME

RPC::XML::Method - Object encapsulation of server-side RPC methods

=head1 SYNOPSIS

    require RPC::XML::Method;

    ...
    $method_1 = RPC::XML::Method->new({ name => 'system.identity',
                                        code => sub { ... },
                                        signature => [ 'string' ] });
    $method_2 = RPC::XML::Method->new('/path/to/status.xpl');

=head1 DESCRIPTION

This package is no longer a distinct, separate entity. It has become an empty
sub-class of B<RPC::XML::Procedure>. Please see L<RPC::XML::Procedure> for
details on the methods and usage.

By the time of 1.0 release of this software package, this file will be removed
completely.

=head1 LICENSE

This module is licensed under the terms of the Artistic License that covers
Perl. See <http://www.opensource.org/licenses/artistic-license.php> for the
license.

=head1 SEE ALSO

L<RPC::XML::Procedure>

=head1 AUTHOR

Randy J. Ray <rjray@blackperl.com>

=cut

__END__
