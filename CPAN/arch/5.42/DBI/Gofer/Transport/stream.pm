package DBI::Gofer::Transport::stream;

#   $Id: stream.pm 12536 2009-02-24 22:37:09Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;

use DBI qw(dbi_time);
use DBI::Gofer::Execute;

use base qw(DBI::Gofer::Transport::pipeone Exporter);

our $VERSION = "0.012537";

our @EXPORT = qw(run_stdio_hex);

my $executor = DBI::Gofer::Execute->new();

sub run_stdio_hex {

    my $transport = DBI::Gofer::Transport::stream->new();
    local $| = 1;

    DBI->trace_msg("$0 started (pid $$)\n");

    local $\; # OUTPUT_RECORD_SEPARATOR
    local $/ = "\012"; # INPUT_RECORD_SEPARATOR
    while ( defined( my $encoded_request = <STDIN> ) ) {
        my $time_received = dbi_time();
        $encoded_request =~ s/\015?\012$//;

        my $frozen_request = pack "H*", $encoded_request;
        my $request = $transport->thaw_request( $frozen_request );

        my $response = $executor->execute_request( $request );

        my $frozen_response = $transport->freeze_response($response);
        my $encoded_response = unpack "H*", $frozen_response;

        print $encoded_response, "\015\012"; # autoflushed due to $|=1

        # there's no way to access the stats currently
        # so this just serves as a basic test and illustration of update_stats()
        $executor->update_stats($request, $response, $frozen_request, $frozen_response, $time_received, 1);
    }
    DBI->trace_msg("$0 ending (pid $$)\n");
}

1;
__END__

=head1 NAME

DBI::Gofer::Transport::stream - DBD::Gofer server-side transport for stream

=head1 SYNOPSIS

See L<DBD::Gofer::Transport::stream>.

=head1 AUTHOR

Tim Bunce, L<http://www.tim.bunce.name>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Tim Bunce, Ireland. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut
