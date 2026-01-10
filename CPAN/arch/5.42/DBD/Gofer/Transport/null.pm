package DBD::Gofer::Transport::null;

#   $Id: null.pm 10087 2007-10-16 12:42:37Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;

use base qw(DBD::Gofer::Transport::Base);

use DBI::Gofer::Execute;

our $VERSION = "0.010088";

__PACKAGE__->mk_accessors(qw(
    pending_response
    transmit_count
));

my $executor = DBI::Gofer::Execute->new();


sub transmit_request_by_transport {
    my ($self, $request) = @_;
    $self->transmit_count( ($self->transmit_count()||0) + 1 ); # just for tests

    my $frozen_request = $self->freeze_request($request);

    # ...
    # the request is magically transported over to ... ourselves
    # ...

    my $response = $executor->execute_request( $self->thaw_request($frozen_request, undef, 1) );

    # put response 'on the shelf' ready for receive_response()
    $self->pending_response( $response );

    return undef;
}


sub receive_response_by_transport {
    my $self = shift;

    my $response = $self->pending_response;

    my $frozen_response = $self->freeze_response($response, undef, 1);

    # ...
    # the response is magically transported back to ... ourselves
    # ...

    return $self->thaw_response($frozen_response);
}


1;
__END__

=head1 NAME

DBD::Gofer::Transport::null - DBD::Gofer client transport for testing

=head1 SYNOPSIS

  my $original_dsn = "..."
  DBI->connect("dbi:Gofer:transport=null;dsn=$original_dsn",...)

or, enable by setting the DBI_AUTOPROXY environment variable:

  export DBI_AUTOPROXY="dbi:Gofer:transport=null"

=head1 DESCRIPTION

Connect via DBD::Gofer but execute the requests within the same process.

This is a quick and simple way to test applications for compatibility with the
(few) restrictions that DBD::Gofer imposes.

It also provides a simple, portable way for the DBI test suite to be used to
test DBD::Gofer on all platforms with no setup.

Also, by measuring the difference in performance between normal connections and
connections via C<dbi:Gofer:transport=null> the basic cost of using DBD::Gofer
can be measured. Furthermore, the additional cost of more advanced transports can be
isolated by comparing their performance with the null transport.

The C<t/85gofer.t> script in the DBI distribution includes a comparative benchmark.

=head1 AUTHOR

Tim Bunce, L<http://www.tim.bunce.name>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Tim Bunce, Ireland. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=head1 SEE ALSO

L<DBD::Gofer::Transport::Base>

L<DBD::Gofer>

=cut
