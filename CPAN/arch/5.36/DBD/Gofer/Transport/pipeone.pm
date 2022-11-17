package DBD::Gofer::Transport::pipeone;

#   $Id: pipeone.pm 10087 2007-10-16 12:42:37Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;
use warnings;

use Carp;
use Fcntl;
use IO::Select;
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

use base qw(DBD::Gofer::Transport::Base);

our $VERSION = "0.010088";

__PACKAGE__->mk_accessors(qw(
    connection_info
    go_perl
));


sub new {
    my ($self, $args) = @_;
    $args->{go_perl} ||= do {
        ($INC{"blib.pm"}) ? [ $^X, '-Mblib' ] : [ $^X ];
    };
    if (not ref $args->{go_perl}) {
        # user can override the perl to be used, either with an array ref
        # containing the command name and args to use, or with a string
        # (ie via the DSN) in which case, to enable args to be passed,
        # we split on two or more consecutive spaces (otherwise the path
        # to perl couldn't contain a space itself).
        $args->{go_perl} = [ split /\s{2,}/, $args->{go_perl} ];
    }
    return $self->SUPER::new($args);
}


# nonblock($fh) puts filehandle into nonblocking mode
sub nonblock {
  my $fh = shift;
  my $flags = fcntl($fh, F_GETFL, 0)
        or croak "Can't get flags for filehandle $fh: $!";
  fcntl($fh, F_SETFL, $flags | O_NONBLOCK)
        or croak "Can't make filehandle $fh nonblocking: $!";
}


sub start_pipe_command {
    my ($self, $cmd) = @_;
    $cmd = [ $cmd ] unless ref $cmd eq 'ARRAY';

    # if it's important that the subprocess uses the same
    # (versions of) modules as us then the caller should
    # set PERL5LIB itself.

    # limit various forms of insanity, for now
    local $ENV{DBI_TRACE}; # use DBI_GOFER_TRACE instead
    local $ENV{DBI_AUTOPROXY};
    local $ENV{DBI_PROFILE};

    my ($wfh, $rfh, $efh) = (gensym, gensym, gensym);
    my $pid = open3($wfh, $rfh, $efh, @$cmd)
        or die "error starting @$cmd: $!\n";
    if ($self->trace) {
        $self->trace_msg(sprintf("Started pid $pid: @$cmd {fd: w%d r%d e%d, ppid=$$}\n", fileno $wfh, fileno $rfh, fileno $efh),0);
    }
    nonblock($rfh);
    nonblock($efh);
    my $ios = IO::Select->new($rfh, $efh);

    return {
        cmd=>$cmd,
        pid=>$pid,
        wfh=>$wfh, rfh=>$rfh, efh=>$efh,
        ios=>$ios,
    };
}


sub cmd_as_string {
    my $self = shift;
    # XXX meant to return a properly shell-escaped string suitable for system
    # but its only for debugging so that can wait
    my $connection_info = $self->connection_info;
    return join " ", map { (m/^[-:\w]*$/) ? $_ : "'$_'" } @{$connection_info->{cmd}};
}


sub transmit_request_by_transport {
    my ($self, $request) = @_;

    my $frozen_request = $self->freeze_request($request);

    my $cmd = [ @{$self->go_perl}, qw(-MDBI::Gofer::Transport::pipeone -e run_one_stdio)];
    my $info = $self->start_pipe_command($cmd);

    my $wfh = delete $info->{wfh};
    # send frozen request
    local $\;
    print $wfh $frozen_request
        or warn "error writing to @$cmd: $!\n";
    # indicate that there's no more
    close $wfh
        or die "error closing pipe to @$cmd: $!\n";

    $self->connection_info( $info );
    return;
}


sub read_response_from_fh {
    my ($self, $fh_actions) = @_;
    my $trace = $self->trace;

    my $info = $self->connection_info || die;
    my ($ios) = @{$info}{qw(ios)};
    my $errors = 0;
    my $complete;

    die "No handles to read response from" unless $ios->count;

    while ($ios->count) {
        my @readable = $ios->can_read();
        for my $fh (@readable) {
            local $_;
            my $actions = $fh_actions->{$fh} || die "panic: no action for $fh";
            my $rv = sysread($fh, $_='', 1024*31);  # to fit in 32KB slab
            unless ($rv) {              # error (undef) or end of file (0)
                my $action;
                unless (defined $rv) {  # was an error
                    $self->trace_msg("error on handle $fh: $!\n") if $trace >= 4;
                    $action = $actions->{error} || $actions->{eof};
                    ++$errors;
                    # XXX an error may be a permenent condition of the handle
                    # if so we'll loop here - not good
                }
                else {
                    $action = $actions->{eof};
                    $self->trace_msg("eof on handle $fh\n") if $trace >= 4;
                }
                if ($action->($fh)) {
                    $self->trace_msg("removing $fh from handle set\n") if $trace >= 4;
                    $ios->remove($fh);
                }
                next;
            }
            # action returns true if the response is now complete
            # (we finish all handles
            $actions->{read}->($fh) && ++$complete;
        }
        last if $complete;
    }
    return $errors;
}


sub receive_response_by_transport {
    my $self = shift;

    my $info = $self->connection_info || die;
    my ($pid, $rfh, $efh, $ios, $cmd) = @{$info}{qw(pid rfh efh ios cmd)};

    my $frozen_response;
    my $stderr_msg;

    $self->read_response_from_fh( {
        $efh => {
            error => sub { warn "error reading response stderr: $!"; 1 },
            eof   => sub { warn "eof on stderr" if 0; 1 },
            read  => sub { $stderr_msg .= $_; 0 },
        },
        $rfh => {
            error => sub { warn "error reading response: $!"; 1 },
            eof   => sub { warn "eof on stdout" if 0; 1 },
            read  => sub { $frozen_response .= $_; 0 },
        },
    });

    waitpid $info->{pid}, 0
        or warn "waitpid: $!"; # XXX do something more useful?

    die ref($self)." command (@$cmd) failed: $stderr_msg"
        if not $frozen_response; # no output on stdout at all

    # XXX need to be able to detect and deal with corruption
    my $response = $self->thaw_response($frozen_response);

    if ($stderr_msg) {
        # add stderr messages as warnings (for PrintWarn)
        $response->add_err(0, $stderr_msg, undef, $self->trace)
            # but ignore warning from old version of blib
            unless $stderr_msg =~ /^Using .*blib/ && "@$cmd" =~ /-Mblib/;
    }

    return $response;
}


1;

__END__

=head1 NAME

DBD::Gofer::Transport::pipeone - DBD::Gofer client transport for testing

=head1 SYNOPSIS

  $original_dsn = "...";
  DBI->connect("dbi:Gofer:transport=pipeone;dsn=$original_dsn",...)

or, enable by setting the DBI_AUTOPROXY environment variable:

  export DBI_AUTOPROXY="dbi:Gofer:transport=pipeone"

=head1 DESCRIPTION

Connect via DBD::Gofer and execute each request by starting executing a subprocess.

This is, as you might imagine, spectacularly inefficient!

It's only intended for testing. Specifically it demonstrates that the server
side is completely stateless.

It also provides a base class for the much more useful L<DBD::Gofer::Transport::stream>
transport.

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
