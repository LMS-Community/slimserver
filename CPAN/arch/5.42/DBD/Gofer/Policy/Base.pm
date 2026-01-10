package DBD::Gofer::Policy::Base;

#   $Id: Base.pm 10087 2007-10-16 12:42:37Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;
use Carp;

our $VERSION = "0.010088";
our $AUTOLOAD;

my %policy_defaults = (
    # force connect method (unless overridden by go_connect_method=>'...' attribute)
    # if false: call same method on client as on server
    connect_method => 'connect',
    # force prepare method (unless overridden by go_prepare_method=>'...' attribute)
    # if false: call same method on client as on server
    prepare_method => 'prepare',
    skip_connect_check => 0,
    skip_default_methods => 0,
    skip_prepare_check => 0,
    skip_ping => 0,
    dbh_attribute_update => 'every',
    dbh_attribute_list => ['*'],
    locally_quote => 0,
    locally_quote_identifier => 0,
    cache_parse_trace_flags => 1,
    cache_parse_trace_flag => 1,
    cache_data_sources => 1,
    cache_type_info_all => 1,
    cache_tables => 0,
    cache_table_info => 0,
    cache_column_info => 0,
    cache_primary_key_info => 0,
    cache_foreign_key_info => 0,
    cache_statistics_info => 0,
    cache_get_info => 0,
    cache_func => 0,
);

my $base_policy_file = $INC{"DBD/Gofer/Policy/Base.pm"};

__PACKAGE__->create_policy_subs(\%policy_defaults);

sub create_policy_subs {
    my ($class, $policy_defaults) = @_;

    while ( my ($policy_name, $policy_default) = each %$policy_defaults) {
        my $policy_attr_name = "go_$policy_name";
        my $sub = sub {
            # $policy->foo($attr, ...)
            #carp "$policy_name($_[1],...)";
            # return the policy default value unless an attribute overrides it
            return (ref $_[1] && exists $_[1]->{$policy_attr_name})
                ? $_[1]->{$policy_attr_name}
                : $policy_default;
        };
        no strict 'refs';
        *{$class . '::' . $policy_name} = $sub;
    }
}

sub AUTOLOAD {
    carp "Unknown policy name $AUTOLOAD used";
    # only warn once
    no strict 'refs';
    *$AUTOLOAD = sub { undef };
    return undef;
}

sub new {
    my ($class, $args) = @_;
    my $policy = {};
    bless $policy, $class;
}

sub DESTROY { };

1;

=head1 NAME

DBD::Gofer::Policy::Base - Base class for DBD::Gofer policies

=head1 SYNOPSIS

  $dbh = DBI->connect("dbi:Gofer:transport=...;policy=...", ...)

=head1 DESCRIPTION

DBD::Gofer can be configured via a 'policy' mechanism that allows you to
fine-tune the number of round-trips to the Gofer server.  The policies are
grouped into classes (which may be subclassed) and referenced by the name of
the class.

The L<DBD::Gofer::Policy::Base> class is the base class for all the policy
classes and describes all the individual policy items.

The Base policy is not used directly. You should use a policy class derived from it.

=head1 POLICY CLASSES

Three policy classes are supplied with DBD::Gofer:

L<DBD::Gofer::Policy::pedantic> is most 'transparent' but slowest because it
makes more  round-trips to the Gofer server.

L<DBD::Gofer::Policy::classic> is a reasonable compromise - it's the default policy.

L<DBD::Gofer::Policy::rush> is fastest, but may require code changes in your applications.

Generally the default C<classic> policy is fine. When first testing an existing
application with Gofer it is a good idea to start with the C<pedantic> policy
first and then switch to C<classic> or a custom policy, for final testing.

=head1 POLICY ITEMS

These are temporary docs: See the source code for list of policies and their defaults.

In a future version the policies and their defaults will be defined in the pod and parsed out at load-time.

See the source code to this module for more details.

=head1 POLICY CUSTOMIZATION

XXX This area of DBD::Gofer is subject to change.

There are three ways to customize policies:

Policy classes are designed to influence the overall behaviour of DBD::Gofer
with existing, unaltered programs, so they work in a reasonably optimal way
without requiring code changes. You can implement new policy classes as
subclasses of existing policies.

In many cases individual policy items can be overridden on a case-by-case basis
within your application code. You do this by passing a corresponding
C<<go_<policy_name>>> attribute into DBI methods by your application code.
This let's you fine-tune the behaviour for special cases.

The policy items are implemented as methods. In many cases the methods are
passed parameters relating to the DBD::Gofer code being executed. This means
the policy can implement dynamic behaviour that varies depending on the
particular circumstances, such as the particular statement being executed.

=head1 AUTHOR

Tim Bunce, L<http://www.tim.bunce.name>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Tim Bunce, Ireland. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut

