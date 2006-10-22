##################################################
package Log::Log4perl::Appender::Socket;
##################################################
our @ISA = qw(Log::Log4perl::Appender);

use warnings;
use strict;

use IO::Socket::INET;

##################################################
sub new {
##################################################
    my($class, @options) = @_;

    my $self = {
        name            => "unknown name",
        silent_recovery => 0,
        PeerAddr        => "localhost",
        Proto           => 'tcp',
        Timeout         => 5,
        @options,
    };

    bless $self, $class;

    unless($self->connect(@options)) {
        if($self->{silent_recovery}) {
            warn "Connect to $self->{PeerAddr}:$self->{PeerPort} failed: $!";
            return $self;
        }
        die "Connect to $self->{PeerAddr}:$self->{PeerPort} failed: $!";
    }

    $self->{socket}->autoflush(1);

    return $self;
}
    
##################################################
sub connect {
##################################################
    my($self, @options) = @_;

    $self->{socket} = IO::Socket::INET->new(@options);

    return $self->{socket};
}

##################################################
sub log {
##################################################
    my($self, %params) = @_;

    {
            # If we were never able to establish
            # a connection, try to establish one 
            # here. If it fails, return.
        if($self->{silent_recovery} and 
           !defined $self->{socket}) {
            if(! $self->connect(%$self)) {
                return undef;
            }
        }
  
            # Try to send the message across
        eval { $self->{socket}->send($params{message}); 
             };

        if($@) {
            warn "Send to " . ref($self) . " failed ($@)";
            if($self->connect(%$self)) {
                redo;
            }
            if($self->{silent_recovery}) {
                return undef;
            }
            warn "Reconnect to $self->{PeerAddr}:$self->{PeerPort} " .
                 "failed: $!";
            return undef;
        }
    };

    return 1;
}

##################################################
sub DESTROY {
##################################################
    my($self) = @_;

    undef $self->{socket};
}

1;

__END__

=head1 NAME

Log::Log4perl::Appender::Socket - Log to a socket

=head1 SYNOPSIS

    use Log::Log4perl::Appender::Socket;

    my $appender = Log::Log4perl::Appender::Socket->new(
      PeerAddr => "server.foo.com",
      PeerPort => 1234,
    );

    $appender->log(message => "Log me\n");

=head1 DESCRIPTION

This is a simple appender for writing to a socket. It relies on
L<IO::Socket::INET> and offers all parameters this module offers.

Upon destruction of the object, pending messages will be flushed
and the socket will be closed.

If the appender cannot contact the server during the initialization
phase (while running the constructor C<new>), it will C<die()>.

If the appender fails to log a message because the socket's C<send()>
method fails (most likely because the server went down), it will
try to reconnect once. If it succeeds, the message will be sent.
If the reconnect fails, a warning is sent to STDERR and the C<log()>
method returns, discarding the message.

If the option C<silent_recovery> is given to the constructor and
set to a true value, the behaviour is different: If the socket connection
can't be established at initialization time, a single warning is issued.
Every log attempt will then try to establish the connection and 
discard the message silently if it fails.

=head1 EXAMPLE

Write a server quickly using the IO::Socket::INET module:

    use IO::Socket::INET;

    my $sock = IO::Socket::INET->new(
        Listen    => 5,
        LocalAddr => 'localhost',
        LocalPort => 12345,
        Proto     => 'tcp');

    while(my $client = $sock->accept()) {
        print "Client connected\n";
        while(<$client>) {
            print "$_\n";
        }
    }

Start it and then run the following script as a client:

    use Log::Log4perl qw(:easy);

    my $conf = q{
        log4perl.category                  = WARN, Socket
        log4perl.appender.Socket           = Log::Log4perl::Appender::Socket
        log4perl.appender.Socket.PeerAddr  = localhost
        log4perl.appender.Socket.PeerPort  = 12345
        log4perl.appender.Socket.layout    = SimpleLayout
    };

    Log::Log4perl->init(\$conf);

    sleep(2);

    for(1..10) {
        ERROR("Quack!");
        sleep(5);
    }

=head1 AUTHOR

Mike Schilli <log4perl@perlmeister.com>, 2003

=cut
