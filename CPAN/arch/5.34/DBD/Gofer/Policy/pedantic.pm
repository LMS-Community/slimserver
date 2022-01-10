package DBD::Gofer::Policy::pedantic;

#   $Id: pedantic.pm 10087 2007-10-16 12:42:37Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;

our $VERSION = "0.010088";

use base qw(DBD::Gofer::Policy::Base);

# the 'pedantic' policy is the same as the Base policy

1;

=head1 NAME

DBD::Gofer::Policy::pedantic - The 'pedantic' policy for DBD::Gofer

=head1 SYNOPSIS

  $dbh = DBI->connect("dbi:Gofer:transport=...;policy=pedantic", ...)

=head1 DESCRIPTION

The C<pedantic> policy tries to be as transparent as possible. To do this it
makes round-trips to the server for almost every DBI method call.

This is the best policy to use when first testing existing code with Gofer.
Once it's working well you should consider moving to the C<classic> policy or defining your own policy class.

Temporary docs: See the source code for list of policies and their defaults.

In a future version the policies and their defaults will be defined in the pod and parsed out at load-time.

=head1 AUTHOR

Tim Bunce, L<http://www.tim.bunce.name>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Tim Bunce, Ireland. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut

