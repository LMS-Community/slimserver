package DBD::Gofer::Transport::stream;

#   $Id: stream.pm 14598 2010-12-21 22:53:25Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;

use Carp;

use base qw(DBD::Gofer::Transport::pipeone);

our $VERSION = "0.014599";

__PACKAGE__->mk_accessors(qw(
    go_persist
));

my $persist_all = 5;
my %persist;


sub _connection_key {
    my ($self) = @_;
    return join "~", $self->go_url||"", @{ $self->go_perl || [] };
}


sub _connection_get {
    my ($self) = @_;

    my $persist = $self->go_persist; # = 0 can force non-caching
    $persist = $persist_all if not defined $persist;
    my $key = ($persist) ? $self->_connection_key : '';
    if ($persist{$key} && $self->_connection_check($persist{$key})) {
        $self->trace_msg("reusing persistent connection $key\n",0) if $self->trace >= 1;
        return $persist{$key};
    }

    my $connection = $self->_make_connection;

    if ($key) {
        %persist = () if keys %persist > $persist_all; # XXX quick hack to limit subprocesses
        $persist{$key} = $connection;
    }

    return $connection;
}


sub _connection_check {
    my ($self, $connection) = @_;
    $connection ||= $self->connection_info;
    my $pid = $connection->{pid};
    my $ok = (kill 0, $pid);
    $self->trace_msg("_connection_check: $ok (pid $$)\n",0) if $self->trace;
    return $ok;
}


sub _connection_kill {
    my ($self) = @_;
    my $connection = $self->connection_info;
    my ($pid, $wfh, $rfh, $efh) = @{$connection}{qw(pid wfh rfh efh)};
    $self->trace_msg("_connection_kill: closing write handle\n",0) if $self->trace;
    # closing the write file handle should be enough, generally
    close $wfh;
    # in future we may want to be more aggressive
    #close $rfh; close $efh; kill 15, $pid
    # but deleting from the persist cache...
    delete $persist{ $self->_connection_key };
    # ... and removing the connection_info should suffice
    $self->connection_info( undef );
    return;
}


sub _make_connection {
    my ($self) = @_;

    my $go_perl = $self->go_perl;
    my $cmd = [ @$go_perl, qw(-MDBI::Gofer::Transport::stream -e run_stdio_hex)];

    #push @$cmd, "DBI_TRACE=2=/tmp/goferstream.log", "sh", "-c";
    if (my $url = $self->go_url) {
        die "Only 'ssh:user\@host' style url supported by this transport"
            unless $url =~ s/^ssh://;
        my $ssh = $url;
        my $setup_env = join "||", map { "source $_ 2>/dev/null" } qw(.bash_profile .bash_login .profile);
        my $setup = $setup_env.q{; exec "$@"};
        # don't use $^X on remote system by default as it's possibly wrong
        $cmd->[0] = 'perl' if "@$go_perl" eq $^X;
        # -x not only 'Disables X11 forwarding' but also makes connections *much* faster
        unshift @$cmd, qw(ssh -xq), split(' ', $ssh), qw(bash -c), $setup;
    }

    $self->trace_msg("new connection: @$cmd\n",0) if $self->trace;

    # XXX add a handshake - some message from DBI::Gofer::Transport::stream that's
    # sent as soon as it starts that we can wait for to report success - and soak up
    # and report useful warnings etc from ssh before we get it? Increases latency though.
    my $connection = $self->start_pipe_command($cmd);
    return $connection;
}


sub transmit_request_by_transport {
    my ($self, $request) = @_;
    my $trace = $self->trace;

    my $connection = $self->connection_info || do {
        my $con = $self->_connection_get;
        $self->connection_info( $con );
        $con;
    };

    my $encoded_request = unpack("H*", $self->freeze_request($request));
    $encoded_request .= "\015\012";

    my $wfh = $connection->{wfh};
    $self->trace_msg(sprintf("transmit_request_by_transport: to fh %s fd%d\n", $wfh, fileno($wfh)),0)
        if $trace >= 4;

    # send frozen request
    local $\;
    $wfh->print($encoded_request) # autoflush enabled
        or do {
            my $err = $!;
            # XXX could/should make new connection and retry
            $self->_connection_kill;
            die "Error sending request: $err";
        };
    $self->trace_msg("Request sent: $encoded_request\n",0) if $trace >= 4;

    return undef; # indicate no response yet (so caller calls receive_response_by_transport)
}


sub receive_response_by_transport {
    my $self = shift;
    my $trace = $self->trace;

    $self->trace_msg("receive_response_by_transport: awaiting response\n",0) if $trace >= 4;
    my $connection = $self->connection_info || die;
    my ($pid, $rfh, $efh, $cmd) = @{$connection}{qw(pid rfh efh cmd)};

    my $errno = 0;
    my $encoded_response;
    my $stderr_msg;

    $self->read_response_from_fh( {
        $efh => {
            error => sub { warn "error reading response stderr: $!"; $errno||=$!; 1 },
            eof   => sub { warn "eof reading efh" if $trace >= 4; 1 },
            read  => sub { $stderr_msg .= $_; 0 },
        },
        $rfh => {
            error => sub { warn "error reading response: $!"; $errno||=$!; 1 },
            eof   => sub { warn "eof reading rfh" if $trace >= 4; 1 },
            read  => sub { $encoded_response .= $_; ($encoded_response=~s/\015\012$//) ? 1 : 0 },
        },
    });

    # if we got no output on stdout at all then the command has
    # probably exited, possibly with an error to stderr.
    # Turn this situation into a reasonably useful DBI error.
    if (not $encoded_response) {
        my @msg;
        push @msg, "error while reading response: $errno" if $errno;
        if ($stderr_msg) {
            chomp $stderr_msg;
            push @msg, sprintf "error reported by \"%s\" (pid %d%s): %s",
                $self->cmd_as_string,
                $pid, ((kill 0, $pid) ? "" : ", exited"),
                $stderr_msg;
        }
        die join(", ", "No response received", @msg)."\n";
    }

    $self->trace_msg("Response received: $encoded_response\n",0)
        if $trace >= 4;

    $self->trace_msg("Gofer stream stderr message: $stderr_msg\n",0)
        if $stderr_msg && $trace;

    my $frozen_response = pack("H*", $encoded_response);

    # XXX need to be able to detect and deal with corruption
    my $response = $self->thaw_response($frozen_response);

    if ($stderr_msg) {
        # add stderr messages as warnings (for PrintWarn)
        $response->add_err(0, $stderr_msg, undef, $trace)
            # but ignore warning from old version of blib
            unless $stderr_msg =~ /^Using .*blib/ && "@$cmd" =~ /-Mblib/;
    }

    return $response;
}

sub transport_timedout {
    my $self = shift;
    $self->_connection_kill;
    return $self->SUPER::transport_timedout(@_);
}

1;

__END__

=head1 NAME

DBD::Gofer::Transport::stream - DBD::Gofer transport for stdio streaming

=head1 SYNOPSIS

  DBI->connect('dbi:Gofer:transport=stream;url=ssh:username@host.example.com;dsn=dbi:...',...)

or, enable by setting the DBI_AUTOPROXY environment variable:

  export DBI_AUTOPROXY='dbi:Gofer:transport=stream;url=ssh:username@host.example.com'

=head1 DESCRIPTION

Without the C<url=> parameter it launches a subprocess as

  perl -MDBI::Gofer::Transport::stream -e run_stdio_hex

and feeds requests into it and reads responses from it. But that's not very useful.

With a C<url=ssh:username@host.example.com> parameter it uses ssh to launch the subprocess
on a remote system. That's much more useful!

It gives you secure remote access to DBI databases on any system you can login to.
Using ssh also gives you optional compression and many other features (see the
ssh manual for how to configure that and many other options via ~/.ssh/config file).

The actual command invoked is something like:

  ssh -xq ssh:username@host.example.com bash -c $setup $run

where $run is the command shown above, and $command is

  . .bash_profile 2>/dev/null || . .bash_login 2>/dev/null || . .profile 2>/dev/null; exec "$@"

which is trying (in a limited and fairly unportable way) to setup the environment
(PATH, PERL5LIB etc) as it would be if you had logged in to that system.

The "C<perl>" used in the command will default to the value of $^X when not using ssh.
On most systems that's the full path to the perl that's currently executing.


=head1 PERSISTENCE

Currently gofer stream connections persist (remain connected) after all
database handles have been disconnected. This makes later connections in the
same process very fast.

Currently up to 5 different gofer stream connections (based on url) can
persist.  If more than 5 are in the cache when a new connection is made then
the cache is cleared before adding the new connection. Simple but effective.

=head1 TO DO

Document go_perl attribute

Automatically reconnect (within reason) if there's a transport error.

Decide on default for persistent connection - on or off? limits? ttl?

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
