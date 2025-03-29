package Protocol::WebSocket::Client;

use strict;
use warnings;

require Carp;
use Protocol::WebSocket::URL;
use Protocol::WebSocket::Handshake::Client;
use Protocol::WebSocket::Frame;

sub new {
    my $class = shift;
    $class = ref $class if ref $class;
    my (%params) = @_;

    my $self = {};
    bless $self, $class;

    Carp::croak('url is required') unless $params{url};
    $self->{url} = Protocol::WebSocket::URL->new->parse($params{url})
      or Carp::croak("Can't parse url");

    $self->{version} = $params{version};

    # User callbacks.  Only write and read are mandatory.
    $self->{on_write} = $params{on_write};
    $self->{on_read} = $params{on_read};

    # Additional callbacks for other WS events
    $self->{on_connect} = $params{on_connect};
    $self->{on_eof}   = $params{on_eof};
    $self->{on_error} = $params{on_error};
    $self->{on_pong} = $params{on_pong};

    # register auto-pong by default
    if (exists $params{on_ping}) {
        $self->{on_ping} = $params{on_ping};
    } else {
        $self->{on_ping} = \&pong;
    }

    $self->{hs} =
      Protocol::WebSocket::Handshake::Client->new(url => $self->{url});

    # optional parameters for the frame buffer
    my %frame_buffer_params;
    $frame_buffer_params{max_fragments_amount} = $params{max_fragments_amount} if exists $params{max_fragments_amount};
    $frame_buffer_params{max_payload_size} = $params{max_payload_size} if exists $params{max_payload_size};

    $self->{frame_buffer} = $self->_build_frame(%frame_buffer_params);

    # Flag indicating current state
    #  0 = not connected yet,
    #  1 = ready,
    # -1 = connection closed.
    $self->{state} = 0;

    return $self;
}

# function stubs around member vars
sub url     { shift->{url} }
sub version { shift->{version} }
sub is_ready { shift->{state} > 0 }

# register callbacks after construction
sub on {
    my $self = shift;
    my (%handlers) = @_;

    foreach my $event (keys %handlers)
    {
        $self->{"on_$event"} = $handlers{$event};
    }

    return $self;
}

sub read {
    my $self = shift;
    my ($buffer) = @_;

    my $hs           = $self->{hs};
    my $frame_buffer = $self->{frame_buffer};

    # handshake is always the beginning of the WS process
    unless ($hs->is_done) {
        if (!$hs->parse($buffer)) {
            $self->{on_error}->($self, $hs->error);
            return $self;
        }

        if ($hs->is_done) {
            $self->{state} = 1;
            $self->{on_connect}->($self) if $self->{on_connect};
        }
    }

    # handshake has been completed, this is user-mode now
    if ($hs->is_done) {
        $frame_buffer->append($buffer);

        while (defined (my $bytes = $frame_buffer->next)) {
            if ($frame_buffer->is_close) {
                # Remote WebSocket close (TCP socket may stay open for a bit)
                $self->disconnect if ($self->is_ready);
                # TODO: see message in disconnect() about error code / reason
                $self->{on_eof}->($self) if $self->{on_eof};
            } elsif ($frame_buffer->is_pong) {
                # Server responded to our ping.
                $self->{on_pong}->($self, $bytes) if $self->{on_pong};
            } elsif ($frame_buffer->is_ping) {
                # Server sent ping request.
                $self->{on_ping}->($self, $bytes) if $self->{on_ping};
            } else {
                $self->{on_read}->($self, $bytes);
            }
        }
    }

    return $self;
}

# Write arbitrary message.
#  Takes either a Protocol::WebSocket::Frame object, or
#  if given a scalar, builds a standard frame around it.
# In either case, calls user on_write function.
sub write {
    my $self = shift;
    my ($buffer) = @_;

    if ($self->is_ready) {
        my $frame =
          ref $buffer
          ? $buffer
          : $self->_build_frame(masked => 1, buffer => $buffer);
        $self->{on_write}->($self, $frame->to_bytes);
    } else {
        warn "Protocol::WebSocket::Client: write() on " . ($self->{state} ? 'closed' : 'unconnected') . " WebSocket.";
    }

    return $self;
}

# Write preformatted messages
# "connect" (initial handshake)
sub connect {
    my $self = shift;

    if ($self->{state} == 0) {
        my $hs = $self->{hs};

        $self->{on_write}->($self, $hs->to_string);
    } else {
        warn "Protocol::WebSocket::Client: connect() on " . ($self->{state} > 0 ? 'already-connected' : 'closed') . " WebSocket.";
    }

    return $self;
}

# "disconnect" (close frame)
#  also sets state to -1 when called
sub disconnect {
    my $self = shift;

    # TODO: Spec states 'close' messages may contain a uint16 error code, and a utf-8 reason.
    #  Clients are supposed to echo back the error code when receiving close from server.
    # For now, we just send an empty message.
    $self->write( $self->_build_frame(type => 'close', masked => 1) );

    $self->{state} = -1;

    return $self;
}

# "ping" (keep-alive, client to server)
sub ping {
    my $self = shift;
    my ($buffer) = @_;

    $self->write( $self->_build_frame(type => 'ping', masked => 1, buffer => $buffer) );

    return $self;
}

# "pong" (keep-alive, server to client)
sub pong {
    my $self = shift;
    my ($buffer) = @_;

    $self->write( $self->_build_frame(type => 'pong', masked => 1, buffer => $buffer) );

    return $self;
}

# Class-specific internal functions
sub _build_frame {
    my $self = shift;

    return Protocol::WebSocket::Frame->new(version => $self->{version}, @_);
}

1;
__END__

=head1 NAME

Protocol::WebSocket::Client - WebSocket client

=head1 SYNOPSIS

    my $sock = ...get non-blocking socket...;

    my $client = Protocol::WebSocket::Client->new(url => 'ws://localhost:3000');
    $client->on(
        write => sub {
            my $client = shift;
            my ($buf) = @_;

            syswrite $sock, $buf;
        },
        read => sub {
            my $client = shift;
            my ($buf) = @_;

            ...do smth with read data...
        }
    );

    # Sends a correct handshake header
    $client->connect;

    # Register on connect handler
    $client->on(
        connect => sub {
            $client->write('hi there');
        }
    );

    # Parses incoming data and on every frame calls on_read
    $client->read(...data from socket...);

    # Sends correct close header
    $client->disconnect;

=head1 DESCRIPTION

L<Protocol::WebSocket::Client> is a convenient class for writing a WebSocket
client.  It can be used to create the proper handshake to initiate a WebSocket
session with a client, as well as properly encode/decode WS frames from/to
Perl strings.

This class does not implement its own TCP socket handling.  Instead, it
provides callback hooks for the end user to plug in their own read / write
routines.  The user should open a (non-)blocking socket with L<IO::Socket::INET>
or similar, then call C<$client->on()> to attach custom code blocks to handlers
in the object.  Later, when decoding packets, the class will call the
appropriate callback so the application can use the data returned.

=head2 Methods

=over 12

=item C<new>

Returns a new Protocol::WebSocket::Client object.

Parameters should be passed to C<new()> as hash pairs.  The only mandatory
parameter is C<url>, which must be a valid WebSocket URL beginning with
C<ws://> or C<wss://>.  However, if you don't specify C<on_read> and
C<on_write> here, AND you don't provide them later using a call to C<on()>,
the object will not actually be usable.

The list of parameters follows:

=over 12

=item C<url>

URL of the desired WebSocket server endpoint.  This parameter is mandatory,
and is only used to construct the valid handshake for initiating a session.

This URL is parsed by L<Protocol::WebSocket::URL>, refer to that object for
documentation on allowed URL formatting.

=item C<version>

Desired version of the WebSocket protocol to use.  See L<Protocol::WebSocket>
for a list of valid version strings, as well as the default used when this
is not provided.

=item C<on_write>, C<on_read>, C<on_connect>, C<on_eof>, C<on_error>, C<on_pong>, C<on_ping>

Application callback for various WebSocket events.  See C<on()> for details.

Note that C<on_ping> is a special case: if the user does not provide a value,
a default "pong" function will be used automatically.  Users may disable the
auto-pong handler by passing C<on_ping =E<gt> undef>, or supply their own.

=item C<max_fragments_amount>, C<max_payload_size>

These parameters are passed to the underlying WebSocket Frame object and control
behavior of the frame decoding.  Refer to L<Protocol::WebSocket::Frame> for
details on these options.

=back

=item C<on>

Registers a callback with the object, which will be triggered at various points
in the WebSocket control flow.  Mandatory callbacks are C<on_read> and
C<on_write>: the client will (probably) crash if attempting to connect without
supplying something here.

Other handlers can be disabled by passing undef.

C<on()> accepts a hash as input, so it is possible to set multiple handlers with
one call.  Either call this by passing a function reference (as in
C<on( read =E<gt> \&my_read );>) or an anonymous code block (as in
C<on( connect =E<gt> { print "Connected!\n" } );>).

The list of available hooks follows:

=over 12

=item C<write>

Called when the Object wants to write data to the socket.  The function receives
a reference to the object, and a buffer (string) to write.  For example:

    write => sub {
        my $client = shift;
        my ($buf) = @_;

        syswrite $sock, $buf;
    }

=item C<read>

Called when the Object has finished parsing a Frame and has data to return
to the application.  The function receives a reference to the object, and
a buffer containing the received data.  For example:

    read => sub {
        my $client = shift;
        my ($buf) = @_;

        print "Received from remote: '$buf'\n";
    }

=item C<connect>

Called when the Object has completed the handshake with the remote server.
The callback receives a reference to the object.

    connect => sub {
        my $client = shift;

        print "Client has finished handshake and is ready to talk!\n";
    }

=item C<eof>

Called when the Object has terminated the WebSocket connection.  This can
happen either at the request of the Server, or because the Client has called
C<disconnect()>.  The callback function receives a reference to the object.

A closed WebSocket connection cannot send or receive further packets, though
the TCP socket remains open.  In practice, it's wise to close that here.

    eof => sub {
        my $client = shift;

        print "WebSocket connection is terminated.\n";
        $sock->close;
    }

=item C<error>

Called when the Object fails to complete a handshake.  The callback function
receives a reference to the object, and a buffer (string) containing any
error info that might be useful.

    error => sub {
        my $client = shift;
        my ($buf) = @_;

        say "Error establishing WebSocket: $buf";
        $sock->close;
        exit;
    }

=item C<ping>

Called when the Object decodes a "ping" request from the server.  A built-in
handler for this is supplied by default, but users may wish to provide their
own.  The callback function receives a reference to the object, and a buffer
containing any data in the Ping message.  The WebSocket spec suggests that
the buffer should simply be returned in the pong response.

    ping => sub {
        my $client = shift;
        my ($buf) = @_;

        say "Ping?  PONG!\n";
        $client->pong($buf);
    }

=item C<pong>

Called when the Object decodes a "pong" response from the server.  Because
this can only be triggered by the application sending a "ping", it is probably
safe to ignore this function.

The callback function receives a reference to the object, and a buffer
containing any data in the Pong message (which, in turn, should be a copy
of the data sent in the initial Ping message).

    pong => sub {
        my $client = shift;
        my ($buf) = @_;

        say "Good news, everyone!  The server is alive.\n";
    }

=back

=item C<write>

Send data to the remote WebService.

This function takes either a scalar (which will be packaged in correct
WebSocket framing) or a reference to a L<Protocol::WebSocket::Frame> object
(in case you need to build a frame yourself).  It then calls the user-provided
C<on_write> method with the encoded data.

This function tries to B<warn> when sending at a time that isn't valid (e.g.
during the connection or after disconnect).  See C<is_ready()> to determine
if now is an OK time to C<write()>.

=item C<read>

Decode data retrieved from the remote socket as WebSocket frames.

This function accepts a scalar containing bytes that should be appended to
the internal object buffer.  Because WebSockets is a Frame protocol atop a TCP
stream, data may be retrieved piecemeal until an entire frame is collected.

If no complete frame is ready after the call, this function will simply return.
However, if a complete frame is ready and decoded, the object will send decoded
data to the appropriate callback hook at this time.

In other words, call C<sysread()>, and pass the resulting buffer to this
function for parsing.

=item C<connect>

Initiate a WebSocket connection to the remote service.  This will send the
handshake (using the C<on_write> callback).

This function tries to B<warn> when connecting while a connection already
exists, so don't do that.

=item C<disconnect>

Send a Close frame to the remote service, and mark the connection as Closed
internally.  Assuming a well-behaved remote service, this should result in a
callback to C<on_eof> fairly quickly.

This function tries to B<warn> when closing an already-closed or not-yet-open
connection, so don't do that either.

=item C<ping>

Send a Ping frame to the remote service.  Accepts a buffer of data to send
with the message (e.g. a timestamp, monotonically increasing ID, etc).

As with C<write()> above, this is only valid in an established connection.

=item C<pong>

Send a Pong frame to the remote service.  Accepts a buffer of data to send
with the message - you should really just reply with whatever was in the
original Ping frame.

As with C<write()> above, this is only valid in an established connection.

=item C<url>

Returns / sets the L<Protocol::WebSocket::URL> associated with this object.

=item C<version>

Returns / sets the WebSocket protocol version being used by this object.

=item C<is_ready>

Returns 1 if the object is ready to accept C<write()> / C<ping()> / C<pong()>,
0 otherwise.

=back

=head1 AUTHOR

See L<Protocol::WebSocket> for author details.

=head1 COPYRIGHT

See L<Protocol::WebSocket> for copyright info.
