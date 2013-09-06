package DBI::Gofer::Transport::Base;

#   $Id: Base.pm 12536 2009-02-24 22:37:09Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;

use DBI;

use base qw(DBI::Util::_accessor);

use DBI::Gofer::Serializer::Storable;
use DBI::Gofer::Serializer::DataDumper;

our $VERSION = "0.012537";

__PACKAGE__->mk_accessors(qw(
    trace
    keep_meta_frozen
    serializer_obj
));


# see also $ENV{DBI_GOFER_TRACE} in DBI::Gofer::Execute
sub _init_trace { (split(/=/,$ENV{DBI_GOFER_TRACE}||0))[0] }


sub new {
    my ($class, $args) = @_;
    $args->{trace} ||= $class->_init_trace;
    $args->{serializer_obj} ||= DBI::Gofer::Serializer::Storable->new();
    my $self = bless {}, $class;
    $self->$_( $args->{$_} ) for keys %$args;
    $self->trace_msg("$class->new({ @{[ %$args ]} })\n") if $self->trace;
    return $self;
}

my $packet_header_text  = "GoFER1:";
my $packet_header_regex = qr/^GoFER(\d+):/;


sub _freeze_data {
    my ($self, $data, $serializer, $skip_trace) = @_;
    my $frozen = eval {
        $self->_dump("freezing $self->{trace} ".ref($data), $data)
            if !$skip_trace and $self->trace;

        local $data->{meta}; # don't include meta in serialization
	$serializer ||= $self->{serializer_obj};
        my ($data, $deserializer_class)  = $serializer->serialize($data);

        $packet_header_text . $data;
    };
    if ($@) {
        chomp $@;
        die "Error freezing ".ref($data)." object: $@";
    }

    # stash the frozen data into the data structure itself
    # to make life easy for the client caching code in DBD::Gofer::Transport::Base
    $data->{meta}{frozen} = $frozen if $self->keep_meta_frozen;

    return $frozen;
}
# public aliases used by subclasses
*freeze_request  = \&_freeze_data;
*freeze_response = \&_freeze_data;


sub _thaw_data {
    my ($self, $frozen_data, $serializer, $skip_trace) = @_;
    my $data;
    eval {
        # check for and extract our gofer header and the info it contains
        (my $frozen = $frozen_data) =~ s/$packet_header_regex//o
            or die "does not have gofer header\n";
        my ($t_version) = $1;
	$serializer ||= $self->{serializer_obj};
        $data = $serializer->deserialize($frozen);
        die ref($serializer)."->deserialize didn't return a reference"
            unless ref $data;
        $data->{_transport}{version} = $t_version;

        $data->{meta}{frozen} = $frozen_data if $self->keep_meta_frozen;
    };
    if ($@) {
        chomp(my $err = $@);
        # remove extra noise from Storable
        $err =~ s{ at \S+?/Storable.pm \(autosplit into \S+?/Storable/thaw.al\) line \d+(, \S+ line \d+)?}{};
        my $msg = sprintf "Error thawing: %s (data=%s)", $err, DBI::neat($frozen_data,50);
        Carp::cluck("$msg, pid $$ stack trace follows:"); # XXX if $self->trace;
        die $msg;
    }
    $self->_dump("thawing $self->{trace} ".ref($data), $data)
        if !$skip_trace and $self->trace;

    return $data;
}
# public aliases used by subclasses
*thaw_request  = \&_thaw_data;
*thaw_response = \&_thaw_data;


# this should probably live in the request and response classes
# and the tace level passed in
sub _dump {
    my ($self, $label, $data) = @_;

    # don't dump the binary
    local $data->{meta}{frozen} if $data->{meta} && $data->{meta}{frozen};

    my $trace_level = $self->trace;
    my $summary;
    if ($trace_level >= 4) {
        require Data::Dumper;
        local $Data::Dumper::Indent    = 1;
        local $Data::Dumper::Terse     = 1;
        local $Data::Dumper::Useqq     = 0;
        local $Data::Dumper::Sortkeys  = 1;
        local $Data::Dumper::Quotekeys = 0;
        local $Data::Dumper::Deparse   = 0;
        local $Data::Dumper::Purity    = 0;
        $summary = Data::Dumper::Dumper($data);
    }
    elsif ($trace_level >= 2) {
        $summary = eval { $data->summary_as_text } || $@ || "no summary available\n";
    }
    else {
        $summary = eval { $data->outline_as_text."\n" } || $@ || "no summary available\n";
    }
    $self->trace_msg("$label: $summary");
}


sub trace_msg {
    my ($self, $msg, $min_level) = @_;
    $min_level = 1 unless defined $min_level;
    # transport trace level can override DBI's trace level
    $min_level = 0 if $self->trace >= $min_level;
    return DBI->trace_msg("gofer ".$msg, $min_level);
}

1;

=head1 NAME

DBI::Gofer::Transport::Base - Base class for Gofer transports

=head1 DESCRIPTION

This is the base class for server-side Gofer transports.

It's also the base class for the client-side base class L<DBD::Gofer::Transport::Base>.

This is an internal class.

=head1 AUTHOR

Tim Bunce, L<http://www.tim.bunce.name>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Tim Bunce, Ireland. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut

