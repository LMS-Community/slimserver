package DBI::Gofer::Transport::pipeone;

#   $Id: pipeone.pm 12536 2009-02-24 22:37:09Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;

use DBI::Gofer::Execute;

use base qw(DBI::Gofer::Transport::Base Exporter);

our $VERSION = "0.012537";

our @EXPORT = qw(run_one_stdio);

my $executor = DBI::Gofer::Execute->new();

sub run_one_stdio {

    my $transport = DBI::Gofer::Transport::pipeone->new();

    my $frozen_request = do { local $/; <STDIN> };

    my $response = $executor->execute_request( $transport->thaw_request($frozen_request) );

    my $frozen_response = $transport->freeze_response($response);

    print $frozen_response;

    # no point calling $executor->update_stats(...) for pipeONE
}

1;
__END__

=head1 NAME

DBI::Gofer::Transport::pipeone - DBD::Gofer server-side transport for pipeone

=head1 SYNOPSIS

See L<DBD::Gofer::Transport::pipeone>.

=head1 AUTHOR

Tim Bunce, L<http://www.tim.bunce.name>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Tim Bunce, Ireland. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut

