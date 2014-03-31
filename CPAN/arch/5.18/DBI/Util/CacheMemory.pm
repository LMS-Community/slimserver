package DBI::Util::CacheMemory;

#   $Id: CacheMemory.pm 10314 2007-11-26 22:25:33Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;

=head1 NAME

DBI::Util::CacheMemory - a very fast but very minimal subset of Cache::Memory

=head1 DESCRIPTION

Like Cache::Memory (part of the Cache distribution) but doesn't support any fancy features.

This module aims to be a very fast compatible strict sub-set for simple cases,
such as basic client-side caching for DBD::Gofer.

Like Cache::Memory, and other caches in the Cache and Cache::Cache
distributions, the data will remain in the cache until cleared, it expires,
or the process dies. The cache object simply going out of scope will I<not>
destroy the data.

=head1 METHODS WITH CHANGES

=head2 new

All options except C<namespace> are ignored.

=head2 set

Doesn't support expiry.

=head2 purge

Same as clear() - deletes everything in the namespace.

=head1 METHODS WITHOUT CHANGES

=over

=item clear

=item count

=item exists

=item remove

=back

=head1 UNSUPPORTED METHODS

If it's not listed above, it's not supported.

=cut

our $VERSION = "0.010315";

my %cache;

sub new {
    my ($class, %options ) = @_;
    my $namespace = $options{namespace} ||= 'Default';
    #$options{_cache} = \%cache; # can be handy for debugging/dumping
    my $self =  bless \%options => $class;
    $cache{ $namespace } ||= {}; # init - ensure it exists
    return $self;
}

sub set {
    my ($self, $key, $value) = @_;
    $cache{ $self->{namespace} }->{$key} = $value;
}

sub get {
    my ($self, $key) = @_;
    return $cache{ $self->{namespace} }->{$key};
}

sub exists {
    my ($self, $key) = @_;
    return exists $cache{ $self->{namespace} }->{$key};
}

sub remove {
    my ($self, $key) = @_;
    return delete $cache{ $self->{namespace} }->{$key};
}

sub purge {
    return shift->clear;
}

sub clear {
    $cache{ shift->{namespace} } = {};
}

sub count {
    return scalar keys %{ $cache{ shift->{namespace} } };
}

sub size {
    my $c = $cache{ shift->{namespace} };
    my $size = 0;
    while ( my ($k,$v) = each %$c ) {
        $size += length($k) + length($v);
    }
    return $size;
}

1;
