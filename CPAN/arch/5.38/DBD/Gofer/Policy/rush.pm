package DBD::Gofer::Policy::rush;

#   $Id: rush.pm 10087 2007-10-16 12:42:37Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;

our $VERSION = "0.010088";

use base qw(DBD::Gofer::Policy::Base);

__PACKAGE__->create_policy_subs({

    # always use connect_cached on server
    connect_method => 'connect_cached',

    # use same methods on server as is called on client
    # (because code not using placeholders would bloat the sth cache)
    prepare_method => '',

    # Skipping the connect check is fast, but it also skips
    # fetching the remote dbh attributes!
    # Make sure that your application doesn't need access to dbh attributes.
    skip_connect_check => 1,

    # most code doesn't rely on sth attributes being set after prepare
    skip_prepare_check => 1,

    # we're happy to use local method if that's the same as the remote
    skip_default_methods => 1,

    # ping is almost meaningless for DBD::Gofer and most transports anyway
    skip_ping => 1,

    # don't update dbh attributes at all
    # XXX actually we currently need dbh_attribute_update for skip_default_methods to work
    # and skip_default_methods is more valuable to us than the cost of dbh_attribute_update
    dbh_attribute_update => 'none', # actually means 'first' currently
    #dbh_attribute_list => undef,

    # we'd like to set locally_* but can't because drivers differ

    # in a rush assume metadata doesn't change
    cache_tables => 1,
    cache_table_info => 1,
    cache_column_info => 1,
    cache_primary_key_info => 1,
    cache_foreign_key_info => 1,
    cache_statistics_info => 1,
    cache_get_info => 1,
});


1;

=head1 NAME

DBD::Gofer::Policy::rush - The 'rush' policy for DBD::Gofer

=head1 SYNOPSIS

  $dbh = DBI->connect("dbi:Gofer:transport=...;policy=rush", ...)

=head1 DESCRIPTION

The C<rush> policy tries to make as few round-trips as possible.
It's the opposite end of the policy spectrum to the C<pedantic> policy.

Temporary docs: See the source code for list of policies and their defaults.

In a future version the policies and their defaults will be defined in the pod and parsed out at load-time.

=head1 AUTHOR

Tim Bunce, L<http://www.tim.bunce.name>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Tim Bunce, Ireland. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut

