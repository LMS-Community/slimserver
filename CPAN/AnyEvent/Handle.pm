package AnyEvent::Handle;

use Scalar::Util ();
use Carp ();
use Errno qw(EAGAIN EINTR);

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util qw(WSAEWOULDBLOCK);

=head1 NAME

AnyEvent::Handle - non-blocking I/O on file handles via AnyEvent

=cut

our $VERSION = 4.86;

=head1 SYNOPSIS

   use AnyEvent;
   use AnyEvent::Handle;

   my $cv = AnyEvent->condvar;

   my $hdl; $hdl = new AnyEvent::Handle
      fh => \*STDIN,
      on_error => sub {
         my ($hdl, $fatal, $msg) = @_;
         warn "got error $msg\n";
         $hdl->destroy;
         $cv->send;
      );

   # send some request line
   $hdl->push_write ("getinfo\015\012");

   # read the response line
   $hdl->push_read (line => sub {
      my ($hdl, $line) = @_;
      warn "got line <$line>\n";
      $cv->send;
   });

   $cv->recv;

=head1 DESCRIPTION

This module is a helper module to make it easier to do event-based I/O on
filehandles. For utility functions for doing non-blocking connects and accepts
on sockets see L<AnyEvent::Util>.

The L<AnyEvent::Intro> tutorial contains some well-documented
AnyEvent::Handle examples.

In the following, when the documentation refers to of "bytes" then this
means characters. As sysread and syswrite are used for all I/O, their
treatment of characters applies to this module as well.

All callbacks will be invoked with the handle object as their first
argument.

=head1 METHODS

=over 4

=item $handle = B<new> AnyEvent::TLS fh => $filehandle, key => value...

The constructor supports these arguments (all as C<< key => value >> pairs).

=over 4

=item fh => $filehandle [MANDATORY]

The filehandle this L<AnyEvent::Handle> object will operate on.

NOTE: The filehandle will be set to non-blocking mode (using
C<AnyEvent::Util::fh_nonblocking>) by the constructor and needs to stay in
that mode.

=item on_eof => $cb->($handle)

Set the callback to be called when an end-of-file condition is detected,
i.e. in the case of a socket, when the other side has closed the
connection cleanly, and there are no outstanding read requests in the
queue (if there are read requests, then an EOF counts as an unexpected
connection close and will be flagged as an error).

For sockets, this just means that the other side has stopped sending data,
you can still try to write data, and, in fact, one can return from the EOF
callback and continue writing data, as only the read part has been shut
down.

If an EOF condition has been detected but no C<on_eof> callback has been
set, then a fatal error will be raised with C<$!> set to <0>.

=item on_error => $cb->($handle, $fatal, $message)

This is the error callback, which is called when, well, some error
occured, such as not being able to resolve the hostname, failure to
connect or a read error.

Some errors are fatal (which is indicated by C<$fatal> being true). On
fatal errors the handle object will be destroyed (by a call to C<< ->
destroy >>) after invoking the error callback (which means you are free to
examine the handle object). Examples of fatal errors are an EOF condition
with active (but unsatisifable) read watchers (C<EPIPE>) or I/O errors.

AnyEvent::Handle tries to find an appropriate error code for you to check
against, but in some cases (TLS errors), this does not work well. It is
recommended to always output the C<$message> argument in human-readable
error messages (it's usually the same as C<"$!">).

Non-fatal errors can be retried by simply returning, but it is recommended
to simply ignore this parameter and instead abondon the handle object
when this callback is invoked. Examples of non-fatal errors are timeouts
C<ETIMEDOUT>) or badly-formatted data (C<EBADMSG>).

On callback entrance, the value of C<$!> contains the operating system
error code (or C<ENOSPC>, C<EPIPE>, C<ETIMEDOUT>, C<EBADMSG> or
C<EPROTO>).

While not mandatory, it is I<highly> recommended to set this callback, as
you will not be notified of errors otherwise. The default simply calls
C<croak>.

=item on_read => $cb->($handle)

This sets the default read callback, which is called when data arrives
and no read request is in the queue (unlike read queue callbacks, this
callback will only be called when at least one octet of data is in the
read buffer).

To access (and remove data from) the read buffer, use the C<< ->rbuf >>
method or access the C<< $handle->{rbuf} >> member directly. Note that you
must not enlarge or modify the read buffer, you can only remove data at
the beginning from it.

When an EOF condition is detected then AnyEvent::Handle will first try to
feed all the remaining data to the queued callbacks and C<on_read> before
calling the C<on_eof> callback. If no progress can be made, then a fatal
error will be raised (with C<$!> set to C<EPIPE>).

Note that, unlike requests in the read queue, an C<on_read> callback
doesn't mean you I<require> some data: if there is an EOF and there
are outstanding read requests then an error will be flagged. With an
C<on_read> callback, the C<on_eof> callback will be invoked.

=item on_drain => $cb->($handle)

This sets the callback that is called when the write buffer becomes empty
(or when the callback is set and the buffer is empty already).

To append to the write buffer, use the C<< ->push_write >> method.

This callback is useful when you don't want to put all of your write data
into the queue at once, for example, when you want to write the contents
of some file to the socket you might not want to read the whole file into
memory and push it into the queue, but instead only read more data from
the file when the write queue becomes empty.

=item timeout => $fractional_seconds

If non-zero, then this enables an "inactivity" timeout: whenever this many
seconds pass without a successful read or write on the underlying file
handle, the C<on_timeout> callback will be invoked (and if that one is
missing, a non-fatal C<ETIMEDOUT> error will be raised).

Note that timeout processing is also active when you currently do not have
any outstanding read or write requests: If you plan to keep the connection
idle then you should disable the timout temporarily or ignore the timeout
in the C<on_timeout> callback, in which case AnyEvent::Handle will simply
restart the timeout.

Zero (the default) disables this timeout.

=item on_timeout => $cb->($handle)

Called whenever the inactivity timeout passes. If you return from this
callback, then the timeout will be reset as if some activity had happened,
so this condition is not fatal in any way.

=item rbuf_max => <bytes>

If defined, then a fatal error will be raised (with C<$!> set to C<ENOSPC>)
when the read buffer ever (strictly) exceeds this size. This is useful to
avoid some forms of denial-of-service attacks.

For example, a server accepting connections from untrusted sources should
be configured to accept only so-and-so much data that it cannot act on
(for example, when expecting a line, an attacker could send an unlimited
amount of data without a callback ever being called as long as the line
isn't finished).

=item autocork => <boolean>

When disabled (the default), then C<push_write> will try to immediately
write the data to the handle, if possible. This avoids having to register
a write watcher and wait for the next event loop iteration, but can
be inefficient if you write multiple small chunks (on the wire, this
disadvantage is usually avoided by your kernel's nagle algorithm, see
C<no_delay>, but this option can save costly syscalls).

When enabled, then writes will always be queued till the next event loop
iteration. This is efficient when you do many small writes per iteration,
but less efficient when you do a single write only per iteration (or when
the write buffer often is full). It also increases write latency.

=item no_delay => <boolean>

When doing small writes on sockets, your operating system kernel might
wait a bit for more data before actually sending it out. This is called
the Nagle algorithm, and usually it is beneficial.

In some situations you want as low a delay as possible, which can be
accomplishd by setting this option to a true value.

The default is your opertaing system's default behaviour (most likely
enabled), this option explicitly enables or disables it, if possible.

=item read_size => <bytes>

The default read block size (the amount of bytes this module will
try to read during each loop iteration, which affects memory
requirements). Default: C<8192>.

=item low_water_mark => <bytes>

Sets the amount of bytes (default: C<0>) that make up an "empty" write
buffer: If the write reaches this size or gets even samller it is
considered empty.

Sometimes it can be beneficial (for performance reasons) to add data to
the write buffer before it is fully drained, but this is a rare case, as
the operating system kernel usually buffers data as well, so the default
is good in almost all cases.

=item linger => <seconds>

If non-zero (default: C<3600>), then the destructor of the
AnyEvent::Handle object will check whether there is still outstanding
write data and will install a watcher that will write this data to the
socket. No errors will be reported (this mostly matches how the operating
system treats outstanding data at socket close time).

This will not work for partial TLS data that could not be encoded
yet. This data will be lost. Calling the C<stoptls> method in time might
help.

=item peername => $string

A string used to identify the remote site - usually the DNS hostname
(I<not> IDN!) used to create the connection, rarely the IP address.

Apart from being useful in error messages, this string is also used in TLS
peername verification (see C<verify_peername> in L<AnyEvent::TLS>). This
verification will be skipped when C<peername> is not specified or
C<undef>.

=item tls => "accept" | "connect" | Net::SSLeay::SSL object

When this parameter is given, it enables TLS (SSL) mode, that means
AnyEvent will start a TLS handshake as soon as the conenction has been
established and will transparently encrypt/decrypt data afterwards.

All TLS protocol errors will be signalled as C<EPROTO>, with an
appropriate error message.

TLS mode requires Net::SSLeay to be installed (it will be loaded
automatically when you try to create a TLS handle): this module doesn't
have a dependency on that module, so if your module requires it, you have
to add the dependency yourself.

Unlike TCP, TLS has a server and client side: for the TLS server side, use
C<accept>, and for the TLS client side of a connection, use C<connect>
mode.

You can also provide your own TLS connection object, but you have
to make sure that you call either C<Net::SSLeay::set_connect_state>
or C<Net::SSLeay::set_accept_state> on it before you pass it to
AnyEvent::Handle. Also, this module will take ownership of this connection
object.

At some future point, AnyEvent::Handle might switch to another TLS
implementation, then the option to use your own session object will go
away.

B<IMPORTANT:> since Net::SSLeay "objects" are really only integers,
passing in the wrong integer will lead to certain crash. This most often
happens when one uses a stylish C<< tls => 1 >> and is surprised about the
segmentation fault.

See the C<< ->starttls >> method for when need to start TLS negotiation later.

=item tls_ctx => $anyevent_tls

Use the given C<AnyEvent::TLS> object to create the new TLS connection
(unless a connection object was specified directly). If this parameter is
missing, then AnyEvent::Handle will use C<AnyEvent::Handle::TLS_CTX>.

Instead of an object, you can also specify a hash reference with C<< key
=> value >> pairs. Those will be passed to L<AnyEvent::TLS> to create a
new TLS context object.

=item on_starttls => $cb->($handle, $success[, $error_message])

This callback will be invoked when the TLS/SSL handshake has finished. If
C<$success> is true, then the TLS handshake succeeded, otherwise it failed
(C<on_stoptls> will not be called in this case).

The session in C<< $handle->{tls} >> can still be examined in this
callback, even when the handshake was not successful.

TLS handshake failures will not cause C<on_error> to be invoked when this
callback is in effect, instead, the error message will be passed to C<on_starttls>.

Without this callback, handshake failures lead to C<on_error> being
called, as normal.

Note that you cannot call C<starttls> right again in this callback. If you
need to do that, start an zero-second timer instead whose callback can
then call C<< ->starttls >> again.

=item on_stoptls => $cb->($handle)

When a SSLv3/TLS shutdown/close notify/EOF is detected and this callback is
set, then it will be invoked after freeing the TLS session. If it is not,
then a TLS shutdown condition will be treated like a normal EOF condition
on the handle.

The session in C<< $handle->{tls} >> can still be examined in this
callback.

This callback will only be called on TLS shutdowns, not when the
underlying handle signals EOF.

=item json => JSON or JSON::XS object

This is the json coder object used by the C<json> read and write types.

If you don't supply it, then AnyEvent::Handle will create and use a
suitable one (on demand), which will write and expect UTF-8 encoded JSON
texts.

Note that you are responsible to depend on the JSON module if you want to
use this functionality, as AnyEvent does not have a dependency itself.

=back

=cut

sub new {
   my $class = shift;
   my $self = bless { @_ }, $class;

   $self->{fh} or Carp::croak "mandatory argument fh is missing";

   AnyEvent::Util::fh_nonblocking $self->{fh}, 1;

   $self->{_activity} = AnyEvent->now;
   $self->_timeout;

   $self->no_delay (delete $self->{no_delay}) if exists $self->{no_delay};

   $self->starttls (delete $self->{tls}, delete $self->{tls_ctx})
      if $self->{tls};

   $self->on_drain (delete $self->{on_drain}) if $self->{on_drain};

   $self->start_read
      if $self->{on_read};

   $self->{fh} && $self
}

#sub _shutdown {
#   my ($self) = @_;
#
#   delete @$self{qw(_tw _rw _ww fh wbuf on_read _queue)};
#   $self->{_eof} = 1; # tell starttls et. al to stop trying
#
#   &_freetls;
#}

sub _error {
   my ($self, $errno, $fatal, $message) = @_;

   $! = $errno;
   $message ||= "$!";

   if ($self->{on_error}) {
      $self->{on_error}($self, $fatal, $message);
      $self->destroy if $fatal;
   } elsif ($self->{fh}) {
      $self->destroy;
      Carp::croak "AnyEvent::Handle uncaught error: $message";
   }
}

=item $fh = $handle->fh

This method returns the file handle used to create the L<AnyEvent::Handle> object.

=cut

sub fh { $_[0]{fh} }

=item $handle->on_error ($cb)

Replace the current C<on_error> callback (see the C<on_error> constructor argument).

=cut

sub on_error {
   $_[0]{on_error} = $_[1];
}

=item $handle->on_eof ($cb)

Replace the current C<on_eof> callback (see the C<on_eof> constructor argument).

=cut

sub on_eof {
   $_[0]{on_eof} = $_[1];
}

=item $handle->on_timeout ($cb)

Replace the current C<on_timeout> callback, or disables the callback (but
not the timeout) if C<$cb> = C<undef>. See the C<timeout> constructor
argument and method.

=cut

sub on_timeout {
   $_[0]{on_timeout} = $_[1];
}

=item $handle->autocork ($boolean)

Enables or disables the current autocork behaviour (see C<autocork>
constructor argument). Changes will only take effect on the next write.

=cut

sub autocork {
   $_[0]{autocork} = $_[1];
}

=item $handle->no_delay ($boolean)

Enables or disables the C<no_delay> setting (see constructor argument of
the same name for details).

=cut

sub no_delay {
   $_[0]{no_delay} = $_[1];

   eval {
      local $SIG{__DIE__};
      setsockopt $_[0]{fh}, &Socket::IPPROTO_TCP, &Socket::TCP_NODELAY, int $_[1];
   };
}

=item $handle->on_starttls ($cb)

Replace the current C<on_starttls> callback (see the C<on_starttls> constructor argument).

=cut

sub on_starttls {
   $_[0]{on_starttls} = $_[1];
}

=item $handle->on_stoptls ($cb)

Replace the current C<on_stoptls> callback (see the C<on_stoptls> constructor argument).

=cut

sub on_starttls {
   $_[0]{on_stoptls} = $_[1];
}

#############################################################################

=item $handle->timeout ($seconds)

Configures (or disables) the inactivity timeout.

=cut

sub timeout {
   my ($self, $timeout) = @_;

   $self->{timeout} = $timeout;
   $self->_timeout;
}

# reset the timeout watcher, as neccessary
# also check for time-outs
sub _timeout {
   my ($self) = @_;

   if ($self->{timeout}) {
      my $NOW = AnyEvent->now;

      # when would the timeout trigger?
      my $after = $self->{_activity} + $self->{timeout} - $NOW;

      # now or in the past already?
      if ($after <= 0) {
         $self->{_activity} = $NOW;

         if ($self->{on_timeout}) {
            $self->{on_timeout}($self);
         } else {
            $self->_error (Errno::ETIMEDOUT);
         }

         # callback could have changed timeout value, optimise
         return unless $self->{timeout};

         # calculate new after
         $after = $self->{timeout};
      }

      Scalar::Util::weaken $self;
      return unless $self; # ->error could have destroyed $self

      $self->{_tw} ||= AnyEvent->timer (after => $after, cb => sub {
         delete $self->{_tw};
         $self->_timeout;
      });
   } else {
      delete $self->{_tw};
   }
}

#############################################################################

=back

=head2 WRITE QUEUE

AnyEvent::Handle manages two queues per handle, one for writing and one
for reading.

The write queue is very simple: you can add data to its end, and
AnyEvent::Handle will automatically try to get rid of it for you.

When data could be written and the write buffer is shorter then the low
water mark, the C<on_drain> callback will be invoked.

=over 4

=item $handle->on_drain ($cb)

Sets the C<on_drain> callback or clears it (see the description of
C<on_drain> in the constructor).

=cut

sub on_drain {
   my ($self, $cb) = @_;

   $self->{on_drain} = $cb;

   $cb->($self)
      if $cb && $self->{low_water_mark} >= (length $self->{wbuf}) + (length $self->{_tls_wbuf});
}

=item $handle->push_write ($data)

Queues the given scalar to be written. You can push as much data as you
want (only limited by the available memory), as C<AnyEvent::Handle>
buffers it independently of the kernel.

=cut

sub _drain_wbuf {
   my ($self) = @_;

   if (!$self->{_ww} && length $self->{wbuf}) {

      Scalar::Util::weaken $self;

      my $cb = sub {
         my $len = syswrite $self->{fh}, $self->{wbuf};

         if (defined $len) {
            substr $self->{wbuf}, 0, $len, "";

            $self->{_activity} = AnyEvent->now;

            $self->{on_drain}($self)
               if $self->{low_water_mark} >= (length $self->{wbuf}) + (length $self->{_tls_wbuf})
                  && $self->{on_drain};

            delete $self->{_ww} unless length $self->{wbuf};
         } elsif ($! != EAGAIN && $! != EINTR && $! != WSAEWOULDBLOCK) {
            $self->_error ($!, 1);
         }
      };

      # try to write data immediately
      $cb->() unless $self->{autocork};

      # if still data left in wbuf, we need to poll
      $self->{_ww} = AnyEvent->io (fh => $self->{fh}, poll => "w", cb => $cb)
         if length $self->{wbuf};
   };
}

our %WH;

sub register_write_type($$) {
   $WH{$_[0]} = $_[1];
}

sub push_write {
   my $self = shift;

   if (@_ > 1) {
      my $type = shift;

      @_ = ($WH{$type} or Carp::croak "unsupported type passed to AnyEvent::Handle::push_write")
           ->($self, @_);
   }

   if ($self->{tls}) {
      $self->{_tls_wbuf} .= $_[0];

      &_dotls ($self);
   } else {
      $self->{wbuf} .= $_[0];
      $self->_drain_wbuf;
   }
}

=item $handle->push_write (type => @args)

Instead of formatting your data yourself, you can also let this module do
the job by specifying a type and type-specific arguments.

Predefined types are (if you have ideas for additional types, feel free to
drop by and tell us):

=over 4

=item netstring => $string

Formats the given value as netstring
(http://cr.yp.to/proto/netstrings.txt, this is not a recommendation to use them).

=cut

register_write_type netstring => sub {
   my ($self, $string) = @_;

   (length $string) . ":$string,"
};

=item packstring => $format, $data

An octet string prefixed with an encoded length. The encoding C<$format>
uses the same format as a Perl C<pack> format, but must specify a single
integer only (only one of C<cCsSlLqQiInNvVjJw> is allowed, plus an
optional C<!>, C<< < >> or C<< > >> modifier).

=cut

register_write_type packstring => sub {
   my ($self, $format, $string) = @_;

   pack "$format/a*", $string
};

=item json => $array_or_hashref

Encodes the given hash or array reference into a JSON object. Unless you
provide your own JSON object, this means it will be encoded to JSON text
in UTF-8.

JSON objects (and arrays) are self-delimiting, so you can write JSON at
one end of a handle and read them at the other end without using any
additional framing.

The generated JSON text is guaranteed not to contain any newlines: While
this module doesn't need delimiters after or between JSON texts to be
able to read them, many other languages depend on that.

A simple RPC protocol that interoperates easily with others is to send
JSON arrays (or objects, although arrays are usually the better choice as
they mimic how function argument passing works) and a newline after each
JSON text:

   $handle->push_write (json => ["method", "arg1", "arg2"]); # whatever
   $handle->push_write ("\012");
 
An AnyEvent::Handle receiver would simply use the C<json> read type and
rely on the fact that the newline will be skipped as leading whitespace:

   $handle->push_read (json => sub { my $array = $_[1]; ... });

Other languages could read single lines terminated by a newline and pass
this line into their JSON decoder of choice.

=cut

register_write_type json => sub {
   my ($self, $ref) = @_;

   require JSON;

   $self->{json} ? $self->{json}->encode ($ref)
                 : JSON::encode_json ($ref)
};

=item storable => $reference

Freezes the given reference using L<Storable> and writes it to the
handle. Uses the C<nfreeze> format.

=cut

register_write_type storable => sub {
   my ($self, $ref) = @_;

   require Storable;

   pack "w/a*", Storable::nfreeze ($ref)
};

=back

=item $handle->push_shutdown

Sometimes you know you want to close the socket after writing your data
before it was actually written. One way to do that is to replace your
C<on_drain> handler by a callback that shuts down the socket (and set
C<low_water_mark> to C<0>). This method is a shorthand for just that, and
replaces the C<on_drain> callback with:

   sub { shutdown $_[0]{fh}, 1 }    # for push_shutdown

This simply shuts down the write side and signals an EOF condition to the
the peer.

You can rely on the normal read queue and C<on_eof> handling
afterwards. This is the cleanest way to close a connection.

=cut

sub push_shutdown {
   my ($self) = @_;

   delete $self->{low_water_mark};
   $self->on_drain (sub { shutdown $_[0]{fh}, 1 });
}

=item AnyEvent::Handle::register_write_type type => $coderef->($handle, @args)

This function (not method) lets you add your own types to C<push_write>.
Whenever the given C<type> is used, C<push_write> will invoke the code
reference with the handle object and the remaining arguments.

The code reference is supposed to return a single octet string that will
be appended to the write buffer.

Note that this is a function, and all types registered this way will be
global, so try to use unique names.

=cut

#############################################################################

=back

=head2 READ QUEUE

AnyEvent::Handle manages two queues per handle, one for writing and one
for reading.

The read queue is more complex than the write queue. It can be used in two
ways, the "simple" way, using only C<on_read> and the "complex" way, using
a queue.

In the simple case, you just install an C<on_read> callback and whenever
new data arrives, it will be called. You can then remove some data (if
enough is there) from the read buffer (C<< $handle->rbuf >>). Or you cna
leave the data there if you want to accumulate more (e.g. when only a
partial message has been received so far).

In the more complex case, you want to queue multiple callbacks. In this
case, AnyEvent::Handle will call the first queued callback each time new
data arrives (also the first time it is queued) and removes it when it has
done its job (see C<push_read>, below).

This way you can, for example, push three line-reads, followed by reading
a chunk of data, and AnyEvent::Handle will execute them in order.

Example 1: EPP protocol parser. EPP sends 4 byte length info, followed by
the specified number of bytes which give an XML datagram.

   # in the default state, expect some header bytes
   $handle->on_read (sub {
      # some data is here, now queue the length-header-read (4 octets)
      shift->unshift_read (chunk => 4, sub {
         # header arrived, decode
         my $len = unpack "N", $_[1];

         # now read the payload
         shift->unshift_read (chunk => $len, sub {
            my $xml = $_[1];
            # handle xml
         });
      });
   });

Example 2: Implement a client for a protocol that replies either with "OK"
and another line or "ERROR" for the first request that is sent, and 64
bytes for the second request. Due to the availability of a queue, we can
just pipeline sending both requests and manipulate the queue as necessary
in the callbacks.

When the first callback is called and sees an "OK" response, it will
C<unshift> another line-read. This line-read will be queued I<before> the
64-byte chunk callback.

   # request one, returns either "OK + extra line" or "ERROR"
   $handle->push_write ("request 1\015\012");

   # we expect "ERROR" or "OK" as response, so push a line read
   $handle->push_read (line => sub {
      # if we got an "OK", we have to _prepend_ another line,
      # so it will be read before the second request reads its 64 bytes
      # which are already in the queue when this callback is called
      # we don't do this in case we got an error
      if ($_[1] eq "OK") {
         $_[0]->unshift_read (line => sub {
            my $response = $_[1];
            ...
         });
      }
   });

   # request two, simply returns 64 octets
   $handle->push_write ("request 2\015\012");

   # simply read 64 bytes, always
   $handle->push_read (chunk => 64, sub {
      my $response = $_[1];
      ...
   });

=over 4

=cut

sub _drain_rbuf {
   my ($self) = @_;

   local $self->{_in_drain} = 1;

   if (
      defined $self->{rbuf_max}
      && $self->{rbuf_max} < length $self->{rbuf}
   ) {
      $self->_error (Errno::ENOSPC, 1), return;
   }

   while () {
      # we need to use a separate tls read buffer, as we must not receive data while
      # we are draining the buffer, and this can only happen with TLS.
      $self->{rbuf} .= delete $self->{_tls_rbuf} if exists $self->{_tls_rbuf};

      my $len = length $self->{rbuf};

      if (my $cb = shift @{ $self->{_queue} }) {
         unless ($cb->($self)) {
            if ($self->{_eof}) {
               # no progress can be made (not enough data and no data forthcoming)
               $self->_error (Errno::EPIPE, 1), return;
            }

            unshift @{ $self->{_queue} }, $cb;
            last;
         }
      } elsif ($self->{on_read}) {
         last unless $len;

         $self->{on_read}($self);

         if (
            $len == length $self->{rbuf} # if no data has been consumed
            && !@{ $self->{_queue} }     # and the queue is still empty
            && $self->{on_read}          # but we still have on_read
         ) {
            # no further data will arrive
            # so no progress can be made
            $self->_error (Errno::EPIPE, 1), return
               if $self->{_eof};

            last; # more data might arrive
         }
      } else {
         # read side becomes idle
         delete $self->{_rw} unless $self->{tls};
         last;
      }
   }

   if ($self->{_eof}) {
      if ($self->{on_eof}) {
         $self->{on_eof}($self)
      } else {
         $self->_error (0, 1, "Unexpected end-of-file");
      }
   }

   # may need to restart read watcher
   unless ($self->{_rw}) {
      $self->start_read
         if $self->{on_read} || @{ $self->{_queue} };
   }
}

=item $handle->on_read ($cb)

This replaces the currently set C<on_read> callback, or clears it (when
the new callback is C<undef>). See the description of C<on_read> in the
constructor.

=cut

sub on_read {
   my ($self, $cb) = @_;

   $self->{on_read} = $cb;
   $self->_drain_rbuf if $cb && !$self->{_in_drain};
}

=item $handle->rbuf

Returns the read buffer (as a modifiable lvalue).

You can access the read buffer directly as the C<< ->{rbuf} >>
member, if you want. However, the only operation allowed on the
read buffer (apart from looking at it) is removing data from its
beginning. Otherwise modifying or appending to it is not allowed and will
lead to hard-to-track-down bugs.

NOTE: The read buffer should only be used or modified if the C<on_read>,
C<push_read> or C<unshift_read> methods are used. The other read methods
automatically manage the read buffer.

=cut

sub rbuf : lvalue {
   $_[0]{rbuf}
}

=item $handle->push_read ($cb)

=item $handle->unshift_read ($cb)

Append the given callback to the end of the queue (C<push_read>) or
prepend it (C<unshift_read>).

The callback is called each time some additional read data arrives.

It must check whether enough data is in the read buffer already.

If not enough data is available, it must return the empty list or a false
value, in which case it will be called repeatedly until enough data is
available (or an error condition is detected).

If enough data was available, then the callback must remove all data it is
interested in (which can be none at all) and return a true value. After returning
true, it will be removed from the queue.

=cut

our %RH;

sub register_read_type($$) {
   $RH{$_[0]} = $_[1];
}

sub push_read {
   my $self = shift;
   my $cb = pop;

   if (@_) {
      my $type = shift;

      $cb = ($RH{$type} or Carp::croak "unsupported type passed to AnyEvent::Handle::push_read")
            ->($self, $cb, @_);
   }

   push @{ $self->{_queue} }, $cb;
   $self->_drain_rbuf unless $self->{_in_drain};
}

sub unshift_read {
   my $self = shift;
   my $cb = pop;

   if (@_) {
      my $type = shift;

      $cb = ($RH{$type} or Carp::croak "unsupported type passed to AnyEvent::Handle::unshift_read")
            ->($self, $cb, @_);
   }


   unshift @{ $self->{_queue} }, $cb;
   $self->_drain_rbuf unless $self->{_in_drain};
}

=item $handle->push_read (type => @args, $cb)

=item $handle->unshift_read (type => @args, $cb)

Instead of providing a callback that parses the data itself you can chose
between a number of predefined parsing formats, for chunks of data, lines
etc.

Predefined types are (if you have ideas for additional types, feel free to
drop by and tell us):

=over 4

=item chunk => $octets, $cb->($handle, $data)

Invoke the callback only once C<$octets> bytes have been read. Pass the
data read to the callback. The callback will never be called with less
data.

Example: read 2 bytes.

   $handle->push_read (chunk => 2, sub {
      warn "yay ", unpack "H*", $_[1];
   });

=cut

register_read_type chunk => sub {
   my ($self, $cb, $len) = @_;

   sub {
      $len <= length $_[0]{rbuf} or return;
      $cb->($_[0], substr $_[0]{rbuf}, 0, $len, "");
      1
   }
};

=item line => [$eol, ]$cb->($handle, $line, $eol)

The callback will be called only once a full line (including the end of
line marker, C<$eol>) has been read. This line (excluding the end of line
marker) will be passed to the callback as second argument (C<$line>), and
the end of line marker as the third argument (C<$eol>).

The end of line marker, C<$eol>, can be either a string, in which case it
will be interpreted as a fixed record end marker, or it can be a regex
object (e.g. created by C<qr>), in which case it is interpreted as a
regular expression.

The end of line marker argument C<$eol> is optional, if it is missing (NOT
undef), then C<qr|\015?\012|> is used (which is good for most internet
protocols).

Partial lines at the end of the stream will never be returned, as they are
not marked by the end of line marker.

=cut

register_read_type line => sub {
   my ($self, $cb, $eol) = @_;

   if (@_ < 3) {
      # this is more than twice as fast as the generic code below
      sub {
         $_[0]{rbuf} =~ s/^([^\015\012]*)(\015?\012)// or return;

         $cb->($_[0], $1, $2);
         1
      }
   } else {
      $eol = quotemeta $eol unless ref $eol;
      $eol = qr|^(.*?)($eol)|s;

      sub {
         $_[0]{rbuf} =~ s/$eol// or return;

         $cb->($_[0], $1, $2);
         1
      }
   }
};

=item regex => $accept[, $reject[, $skip], $cb->($handle, $data)

Makes a regex match against the regex object C<$accept> and returns
everything up to and including the match.

Example: read a single line terminated by '\n'.

   $handle->push_read (regex => qr<\n>, sub { ... });

If C<$reject> is given and not undef, then it determines when the data is
to be rejected: it is matched against the data when the C<$accept> regex
does not match and generates an C<EBADMSG> error when it matches. This is
useful to quickly reject wrong data (to avoid waiting for a timeout or a
receive buffer overflow).

Example: expect a single decimal number followed by whitespace, reject
anything else (not the use of an anchor).

   $handle->push_read (regex => qr<^[0-9]+\s>, qr<[^0-9]>, sub { ... });

If C<$skip> is given and not C<undef>, then it will be matched against
the receive buffer when neither C<$accept> nor C<$reject> match,
and everything preceding and including the match will be accepted
unconditionally. This is useful to skip large amounts of data that you
know cannot be matched, so that the C<$accept> or C<$reject> regex do not
have to start matching from the beginning. This is purely an optimisation
and is usually worth only when you expect more than a few kilobytes.

Example: expect a http header, which ends at C<\015\012\015\012>. Since we
expect the header to be very large (it isn't in practise, but...), we use
a skip regex to skip initial portions. The skip regex is tricky in that
it only accepts something not ending in either \015 or \012, as these are
required for the accept regex.

   $handle->push_read (regex =>
      qr<\015\012\015\012>,
      undef, # no reject
      qr<^.*[^\015\012]>,
      sub { ... });

=cut

register_read_type regex => sub {
   my ($self, $cb, $accept, $reject, $skip) = @_;

   my $data;
   my $rbuf = \$self->{rbuf};

   sub {
      # accept
      if ($$rbuf =~ $accept) {
         $data .= substr $$rbuf, 0, $+[0], "";
         $cb->($self, $data);
         return 1;
      }
      
      # reject
      if ($reject && $$rbuf =~ $reject) {
         $self->_error (Errno::EBADMSG);
      }

      # skip
      if ($skip && $$rbuf =~ $skip) {
         $data .= substr $$rbuf, 0, $+[0], "";
      }

      ()
   }
};

=item netstring => $cb->($handle, $string)

A netstring (http://cr.yp.to/proto/netstrings.txt, this is not an endorsement).

Throws an error with C<$!> set to EBADMSG on format violations.

=cut

register_read_type netstring => sub {
   my ($self, $cb) = @_;

   sub {
      unless ($_[0]{rbuf} =~ s/^(0|[1-9][0-9]*)://) {
         if ($_[0]{rbuf} =~ /[^0-9]/) {
            $self->_error (Errno::EBADMSG);
         }
         return;
      }

      my $len = $1;

      $self->unshift_read (chunk => $len, sub {
         my $string = $_[1];
         $_[0]->unshift_read (chunk => 1, sub {
            if ($_[1] eq ",") {
               $cb->($_[0], $string);
            } else {
               $self->_error (Errno::EBADMSG);
            }
         });
      });

      1
   }
};

=item packstring => $format, $cb->($handle, $string)

An octet string prefixed with an encoded length. The encoding C<$format>
uses the same format as a Perl C<pack> format, but must specify a single
integer only (only one of C<cCsSlLqQiInNvVjJw> is allowed, plus an
optional C<!>, C<< < >> or C<< > >> modifier).

For example, DNS over TCP uses a prefix of C<n> (2 octet network order),
EPP uses a prefix of C<N> (4 octtes).

Example: read a block of data prefixed by its length in BER-encoded
format (very efficient).

   $handle->push_read (packstring => "w", sub {
      my ($handle, $data) = @_;
   });

=cut

register_read_type packstring => sub {
   my ($self, $cb, $format) = @_;

   sub {
      # when we can use 5.10 we can use ".", but for 5.8 we use the re-pack method
      defined (my $len = eval { unpack $format, $_[0]{rbuf} })
         or return;

      $format = length pack $format, $len;

      # bypass unshift if we already have the remaining chunk
      if ($format + $len <= length $_[0]{rbuf}) {
         my $data = substr $_[0]{rbuf}, $format, $len;
         substr $_[0]{rbuf}, 0, $format + $len, "";
         $cb->($_[0], $data);
      } else {
         # remove prefix
         substr $_[0]{rbuf}, 0, $format, "";

         # read remaining chunk
         $_[0]->unshift_read (chunk => $len, $cb);
      }

      1
   }
};

=item json => $cb->($handle, $hash_or_arrayref)

Reads a JSON object or array, decodes it and passes it to the
callback. When a parse error occurs, an C<EBADMSG> error will be raised.

If a C<json> object was passed to the constructor, then that will be used
for the final decode, otherwise it will create a JSON coder expecting UTF-8.

This read type uses the incremental parser available with JSON version
2.09 (and JSON::XS version 2.2) and above. You have to provide a
dependency on your own: this module will load the JSON module, but
AnyEvent does not depend on it itself.

Since JSON texts are fully self-delimiting, the C<json> read and write
types are an ideal simple RPC protocol: just exchange JSON datagrams. See
the C<json> write type description, above, for an actual example.

=cut

register_read_type json => sub {
   my ($self, $cb) = @_;

   my $json = $self->{json} ||=
      eval { require JSON::XS; JSON::XS->new->utf8 }
         || do { require JSON; JSON->new->utf8 };

   my $data;
   my $rbuf = \$self->{rbuf};

   sub {
      my $ref = eval { $json->incr_parse ($self->{rbuf}) };

      if ($ref) {
         $self->{rbuf} = $json->incr_text;
         $json->incr_text = "";
         $cb->($self, $ref);

         1
      } elsif ($@) {
         # error case
         $json->incr_skip;

         $self->{rbuf} = $json->incr_text;
         $json->incr_text = "";

         $self->_error (Errno::EBADMSG);

         ()
      } else {
         $self->{rbuf} = "";

         ()
      }
   }
};

=item storable => $cb->($handle, $ref)

Deserialises a L<Storable> frozen representation as written by the
C<storable> write type (BER-encoded length prefix followed by nfreeze'd
data).

Raises C<EBADMSG> error if the data could not be decoded.

=cut

register_read_type storable => sub {
   my ($self, $cb) = @_;

   require Storable;

   sub {
      # when we can use 5.10 we can use ".", but for 5.8 we use the re-pack method
      defined (my $len = eval { unpack "w", $_[0]{rbuf} })
         or return;

      my $format = length pack "w", $len;

      # bypass unshift if we already have the remaining chunk
      if ($format + $len <= length $_[0]{rbuf}) {
         my $data = substr $_[0]{rbuf}, $format, $len;
         substr $_[0]{rbuf}, 0, $format + $len, "";
         $cb->($_[0], Storable::thaw ($data));
      } else {
         # remove prefix
         substr $_[0]{rbuf}, 0, $format, "";

         # read remaining chunk
         $_[0]->unshift_read (chunk => $len, sub {
            if (my $ref = eval { Storable::thaw ($_[1]) }) {
               $cb->($_[0], $ref);
            } else {
               $self->_error (Errno::EBADMSG);
            }
         });
      }

      1
   }
};

=back

=item AnyEvent::Handle::register_read_type type => $coderef->($handle, $cb, @args)

This function (not method) lets you add your own types to C<push_read>.

Whenever the given C<type> is used, C<push_read> will invoke the code
reference with the handle object, the callback and the remaining
arguments.

The code reference is supposed to return a callback (usually a closure)
that works as a plain read callback (see C<< ->push_read ($cb) >>).

It should invoke the passed callback when it is done reading (remember to
pass C<$handle> as first argument as all other callbacks do that).

Note that this is a function, and all types registered this way will be
global, so try to use unique names.

For examples, see the source of this module (F<perldoc -m AnyEvent::Handle>,
search for C<register_read_type>)).

=item $handle->stop_read

=item $handle->start_read

In rare cases you actually do not want to read anything from the
socket. In this case you can call C<stop_read>. Neither C<on_read> nor
any queued callbacks will be executed then. To start reading again, call
C<start_read>.

Note that AnyEvent::Handle will automatically C<start_read> for you when
you change the C<on_read> callback or push/unshift a read callback, and it
will automatically C<stop_read> for you when neither C<on_read> is set nor
there are any read requests in the queue.

These methods will have no effect when in TLS mode (as TLS doesn't support
half-duplex connections).

=cut

sub stop_read {
   my ($self) = @_;

   delete $self->{_rw} unless $self->{tls};
}

sub start_read {
   my ($self) = @_;

   unless ($self->{_rw} || $self->{_eof}) {
      Scalar::Util::weaken $self;

      $self->{_rw} = AnyEvent->io (fh => $self->{fh}, poll => "r", cb => sub {
         my $rbuf = \($self->{tls} ? my $buf : $self->{rbuf});
         my $len = sysread $self->{fh}, $$rbuf, $self->{read_size} || 8192, length $$rbuf;

         if ($len > 0) {
            $self->{_activity} = AnyEvent->now;

            if ($self->{tls}) {
               Net::SSLeay::BIO_write ($self->{_rbio}, $$rbuf);

               &_dotls ($self);
            } else {
               $self->_drain_rbuf unless $self->{_in_drain};
            }

         } elsif (defined $len) {
            delete $self->{_rw};
            $self->{_eof} = 1;
            $self->_drain_rbuf unless $self->{_in_drain};

         } elsif ($! != EAGAIN && $! != EINTR && $! != WSAEWOULDBLOCK) {
            return $self->_error ($!, 1);
         }
      });
   }
}

our $ERROR_SYSCALL;
our $ERROR_WANT_READ;

sub _tls_error {
   my ($self, $err) = @_;

   return $self->_error ($!, 1)
      if $err == Net::SSLeay::ERROR_SYSCALL ();

   my $err =Net::SSLeay::ERR_error_string (Net::SSLeay::ERR_get_error ());

   # reduce error string to look less scary
   $err =~ s/^error:[0-9a-fA-F]{8}:[^:]+:([^:]+):/\L$1: /;

   if ($self->{_on_starttls}) {
      (delete $self->{_on_starttls})->($self, undef, $err);
      &_freetls;
   } else {
      &_freetls;
      $self->_error (Errno::EPROTO, 1, $err);
   }
}

# poll the write BIO and send the data if applicable
# also decode read data if possible
# this is basiclaly our TLS state machine
# more efficient implementations are possible with openssl,
# but not with the buggy and incomplete Net::SSLeay.
sub _dotls {
   my ($self) = @_;

   my $tmp;

   if (length $self->{_tls_wbuf}) {
      while (($tmp = Net::SSLeay::write ($self->{tls}, $self->{_tls_wbuf})) > 0) {
         substr $self->{_tls_wbuf}, 0, $tmp, "";
      }

      $tmp = Net::SSLeay::get_error ($self->{tls}, $tmp);
      return $self->_tls_error ($tmp)
         if $tmp != $ERROR_WANT_READ
            && ($tmp != $ERROR_SYSCALL || $!);
   }

   while (defined ($tmp = Net::SSLeay::read ($self->{tls}))) {
      unless (length $tmp) {
         $self->{_on_starttls}
            and (delete $self->{_on_starttls})->($self, undef, "EOF during handshake"); # ???
         &_freetls;

         if ($self->{on_stoptls}) {
            $self->{on_stoptls}($self);
            return;
         } else {
            # let's treat SSL-eof as we treat normal EOF
            delete $self->{_rw};
            $self->{_eof} = 1;
         }
      }

      $self->{_tls_rbuf} .= $tmp;
      $self->_drain_rbuf unless $self->{_in_drain};
      $self->{tls} or return; # tls session might have gone away in callback
   }

   $tmp = Net::SSLeay::get_error ($self->{tls}, -1);
   return $self->_tls_error ($tmp)
      if $tmp != $ERROR_WANT_READ
         && ($tmp != $ERROR_SYSCALL || $!);

   while (length ($tmp = Net::SSLeay::BIO_read ($self->{_wbio}))) {
      $self->{wbuf} .= $tmp;
      $self->_drain_wbuf;
   }

   $self->{_on_starttls}
      and Net::SSLeay::state ($self->{tls}) == Net::SSLeay::ST_OK ()
      and (delete $self->{_on_starttls})->($self, 1, "TLS/SSL connection established");
}

=item $handle->starttls ($tls[, $tls_ctx])

Instead of starting TLS negotiation immediately when the AnyEvent::Handle
object is created, you can also do that at a later time by calling
C<starttls>.

The first argument is the same as the C<tls> constructor argument (either
C<"connect">, C<"accept"> or an existing Net::SSLeay object).

The second argument is the optional C<AnyEvent::TLS> object that is used
when AnyEvent::Handle has to create its own TLS connection object, or
a hash reference with C<< key => value >> pairs that will be used to
construct a new context.

The TLS connection object will end up in C<< $handle->{tls} >>, the TLS
context in C<< $handle->{tls_ctx} >> after this call and can be used or
changed to your liking. Note that the handshake might have already started
when this function returns.

If it an error to start a TLS handshake more than once per
AnyEvent::Handle object (this is due to bugs in OpenSSL).

=cut

our %TLS_CACHE; #TODO not yet documented, should we?

sub starttls {
   my ($self, $ssl, $ctx) = @_;

   require Net::SSLeay;

   Carp::croak "it is an error to call starttls more than once on an AnyEvent::Handle object"
      if $self->{tls};

   $ERROR_SYSCALL   = Net::SSLeay::ERROR_SYSCALL     ();
   $ERROR_WANT_READ = Net::SSLeay::ERROR_WANT_READ   ();

   $ctx ||= $self->{tls_ctx};

   if ("HASH" eq ref $ctx) {
      require AnyEvent::TLS;

      local $Carp::CarpLevel = 1; # skip ourselves when creating a new context

      if ($ctx->{cache}) {
         my $key = $ctx+0;
         $ctx = $TLS_CACHE{$key} ||= new AnyEvent::TLS %$ctx;
      } else {
         $ctx = new AnyEvent::TLS %$ctx;
      }
   }
   
   $self->{tls_ctx} = $ctx || TLS_CTX ();
   $self->{tls}     = $ssl = $self->{tls_ctx}->_get_session ($ssl, $self, $self->{peername});

   # basically, this is deep magic (because SSL_read should have the same issues)
   # but the openssl maintainers basically said: "trust us, it just works".
   # (unfortunately, we have to hardcode constants because the abysmally misdesigned
   # and mismaintained ssleay-module doesn't even offer them).
   # http://www.mail-archive.com/openssl-dev@openssl.org/msg22420.html
   #
   # in short: this is a mess.
   # 
   # note that we do not try to keep the length constant between writes as we are required to do.
   # we assume that most (but not all) of this insanity only applies to non-blocking cases,
   # and we drive openssl fully in blocking mode here. Or maybe we don't - openssl seems to
   # have identity issues in that area.
#   Net::SSLeay::CTX_set_mode ($ssl,
#      (eval { local $SIG{__DIE__}; Net::SSLeay::MODE_ENABLE_PARTIAL_WRITE () } || 1)
#      | (eval { local $SIG{__DIE__}; Net::SSLeay::MODE_ACCEPT_MOVING_WRITE_BUFFER () } || 2));
   Net::SSLeay::CTX_set_mode ($ssl, 1|2);

   $self->{_rbio} = Net::SSLeay::BIO_new (Net::SSLeay::BIO_s_mem ());
   $self->{_wbio} = Net::SSLeay::BIO_new (Net::SSLeay::BIO_s_mem ());

   Net::SSLeay::set_bio ($ssl, $self->{_rbio}, $self->{_wbio});

   $self->{_on_starttls} = sub { $_[0]{on_starttls}(@_) }
      if $self->{on_starttls};

   &_dotls; # need to trigger the initial handshake
   $self->start_read; # make sure we actually do read
}

=item $handle->stoptls

Shuts down the SSL connection - this makes a proper EOF handshake by
sending a close notify to the other side, but since OpenSSL doesn't
support non-blocking shut downs, it is not possible to re-use the stream
afterwards.

=cut

sub stoptls {
   my ($self) = @_;

   if ($self->{tls}) {
      Net::SSLeay::shutdown ($self->{tls});

      &_dotls;

#      # we don't give a shit. no, we do, but we can't. no...#d#
#      # we, we... have to use openssl :/#d#
#      &_freetls;#d#
   }
}

sub _freetls {
   my ($self) = @_;

   return unless $self->{tls};

   $self->{tls_ctx}->_put_session (delete $self->{tls});
   
   delete @$self{qw(_rbio _wbio _tls_wbuf _on_starttls)};
}

sub DESTROY {
   my ($self) = @_;

   &_freetls;

   my $linger = exists $self->{linger} ? $self->{linger} : 3600;

   if ($linger && length $self->{wbuf}) {
      my $fh   = delete $self->{fh};
      my $wbuf = delete $self->{wbuf};

      my @linger;

      push @linger, AnyEvent->io (fh => $fh, poll => "w", cb => sub {
         my $len = syswrite $fh, $wbuf, length $wbuf;

         if ($len > 0) {
            substr $wbuf, 0, $len, "";
         } else {
            @linger = (); # end
         }
      });
      push @linger, AnyEvent->timer (after => $linger, cb => sub {
         @linger = ();
      });
   }
}

=item $handle->destroy

Shuts down the handle object as much as possible - this call ensures that
no further callbacks will be invoked and as many resources as possible
will be freed. You must not call any methods on the object afterwards.

Normally, you can just "forget" any references to an AnyEvent::Handle
object and it will simply shut down. This works in fatal error and EOF
callbacks, as well as code outside. It does I<NOT> work in a read or write
callback, so when you want to destroy the AnyEvent::Handle object from
within such an callback. You I<MUST> call C<< ->destroy >> explicitly in
that case.

Destroying the handle object in this way has the advantage that callbacks
will be removed as well, so if those are the only reference holders (as
is common), then one doesn't need to do anything special to break any
reference cycles.

The handle might still linger in the background and write out remaining
data, as specified by the C<linger> option, however.

=cut

sub destroy {
   my ($self) = @_;

   $self->DESTROY;
   %$self = ();
}

=item AnyEvent::Handle::TLS_CTX

This function creates and returns the AnyEvent::TLS object used by default
for TLS mode.

The context is created by calling L<AnyEvent::TLS> without any arguments.

=cut

our $TLS_CTX;

sub TLS_CTX() {
   $TLS_CTX ||= do {
      require AnyEvent::TLS;

      new AnyEvent::TLS
   }
}

=back


=head1 NONFREQUENTLY ASKED QUESTIONS

=over 4

=item I C<undef> the AnyEvent::Handle reference inside my callback and
still get further invocations!

That's because AnyEvent::Handle keeps a reference to itself when handling
read or write callbacks.

It is only safe to "forget" the reference inside EOF or error callbacks,
from within all other callbacks, you need to explicitly call the C<<
->destroy >> method.

=item I get different callback invocations in TLS mode/Why can't I pause
reading?

Unlike, say, TCP, TLS connections do not consist of two independent
communication channels, one for each direction. Or put differently. The
read and write directions are not independent of each other: you cannot
write data unless you are also prepared to read, and vice versa.

This can mean than, in TLS mode, you might get C<on_error> or C<on_eof>
callback invocations when you are not expecting any read data - the reason
is that AnyEvent::Handle always reads in TLS mode.

During the connection, you have to make sure that you always have a
non-empty read-queue, or an C<on_read> watcher. At the end of the
connection (or when you no longer want to use it) you can call the
C<destroy> method.

=item How do I read data until the other side closes the connection?

If you just want to read your data into a perl scalar, the easiest way
to achieve this is by setting an C<on_read> callback that does nothing,
clearing the C<on_eof> callback and in the C<on_error> callback, the data
will be in C<$_[0]{rbuf}>:

   $handle->on_read (sub { });
   $handle->on_eof (undef);
   $handle->on_error (sub {
      my $data = delete $_[0]{rbuf};
   });

The reason to use C<on_error> is that TCP connections, due to latencies
and packets loss, might get closed quite violently with an error, when in
fact, all data has been received.

It is usually better to use acknowledgements when transferring data,
to make sure the other side hasn't just died and you got the data
intact. This is also one reason why so many internet protocols have an
explicit QUIT command.

=item I don't want to destroy the handle too early - how do I wait until
all data has been written?

After writing your last bits of data, set the C<on_drain> callback
and destroy the handle in there - with the default setting of
C<low_water_mark> this will be called precisely when all data has been
written to the socket:

   $handle->push_write (...);
   $handle->on_drain (sub {
      warn "all data submitted to the kernel\n";
      undef $handle;
   });

If you just want to queue some data and then signal EOF to the other side,
consider using C<< ->push_shutdown >> instead.

=item I want to contact a TLS/SSL server, I don't care about security.

If your TLS server is a pure TLS server (e.g. HTTPS) that only speaks TLS,
simply connect to it and then create the AnyEvent::Handle with the C<tls>
parameter:

   tcp_connect $host, $port, sub {
      my ($fh) = @_;

      my $handle = new AnyEvent::Handle
         fh  => $fh,
         tls => "connect",
         on_error => sub { ... };

      $handle->push_write (...);
   };

=item I want to contact a TLS/SSL server, I do care about security.

Then you should additionally enable certificate verification, including
peername verification, if the protocol you use supports it (see
L<AnyEvent::TLS>, C<verify_peername>).

E.g. for HTTPS:

   tcp_connect $host, $port, sub {
      my ($fh) = @_;

       my $handle = new AnyEvent::Handle
          fh       => $fh,
          peername => $host,
          tls      => "connect",
          tls_ctx  => { verify => 1, verify_peername => "https" },
          ...

Note that you must specify the hostname you connected to (or whatever
"peername" the protocol needs) as the C<peername> argument, otherwise no
peername verification will be done.

The above will use the system-dependent default set of trusted CA
certificates. If you want to check against a specific CA, add the
C<ca_file> (or C<ca_cert>) arguments to C<tls_ctx>:

       tls_ctx  => {
          verify          => 1,
          verify_peername => "https",
          ca_file         => "my-ca-cert.pem",
       },

=item I want to create a TLS/SSL server, how do I do that?

Well, you first need to get a server certificate and key. You have
three options: a) ask a CA (buy one, use cacert.org etc.) b) create a
self-signed certificate (cheap. check the search engine of your choice,
there are many tutorials on the net) or c) make your own CA (tinyca2 is a
nice program for that purpose).

Then create a file with your private key (in PEM format, see
L<AnyEvent::TLS>), followed by the certificate (also in PEM format). The
file should then look like this:

   -----BEGIN RSA PRIVATE KEY-----
   ...header data
   ... lots of base64'y-stuff
   -----END RSA PRIVATE KEY-----

   -----BEGIN CERTIFICATE-----
   ... lots of base64'y-stuff
   -----END CERTIFICATE-----

The important bits are the "PRIVATE KEY" and "CERTIFICATE" parts.  Then
specify this file as C<cert_file>:

   tcp_server undef, $port, sub {
      my ($fh) = @_;

      my $handle = new AnyEvent::Handle
         fh       => $fh,
         tls      => "accept",
         tls_ctx  => { cert_file => "my-server-keycert.pem" },
         ...

When you have intermediate CA certificates that your clients might not
know about, just append them to the C<cert_file>.

=back


=head1 SUBCLASSING AnyEvent::Handle

In many cases, you might want to subclass AnyEvent::Handle.

To make this easier, a given version of AnyEvent::Handle uses these
conventions:

=over 4

=item * all constructor arguments become object members.

At least initially, when you pass a C<tls>-argument to the constructor it
will end up in C<< $handle->{tls} >>. Those members might be changed or
mutated later on (for example C<tls> will hold the TLS connection object).

=item * other object member names are prefixed with an C<_>.

All object members not explicitly documented (internal use) are prefixed
with an underscore character, so the remaining non-C<_>-namespace is free
for use for subclasses.

=item * all members not documented here and not prefixed with an underscore
are free to use in subclasses.

Of course, new versions of AnyEvent::Handle may introduce more "public"
member variables, but thats just life, at least it is documented.

=back

=head1 AUTHOR

Robin Redeker C<< <elmex at ta-sa.org> >>, Marc Lehmann <schmorp@schmorp.de>.

=cut

1; # End of AnyEvent::Handle
