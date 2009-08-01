=head1 NAME

AnyEvent::Util - various utility functions.

=head1 SYNOPSIS

   use AnyEvent::Util;

=head1 DESCRIPTION

This module implements various utility functions, mostly replacing
well-known functions by event-ised counterparts.

All functions documented without C<AnyEvent::Util::> prefix are exported
by default.

=over 4

=cut

package AnyEvent::Util;

use Carp ();
use Errno ();
use Socket ();

use AnyEvent (); BEGIN { AnyEvent::common_sense }

use base 'Exporter';

our @EXPORT = qw(fh_nonblocking guard fork_call portable_pipe portable_socketpair);
our @EXPORT_OK = qw(AF_INET6 WSAEWOULDBLOCK WSAEINPROGRESS WSAEINVAL);

our $VERSION = 4.86;

BEGIN {
   my $af_inet6 = eval { local $SIG{__DIE__}; &Socket::AF_INET6 };

   # uhoh
   $af_inet6 ||= 10 if $^O =~ /linux/;
   $af_inet6 ||= 23 if $^O =~ /cygwin/i;
   $af_inet6 ||= 23 if AnyEvent::WIN32;
   $af_inet6 ||= 24 if $^O =~ /openbsd|netbsd/;
   $af_inet6 ||= 28 if $^O =~ /freebsd/;

   $af_inet6 && socket my $ipv6_socket, $af_inet6, &Socket::SOCK_STREAM, 0 # check if they can be created
      or $af_inet6 = 0;

   eval "sub AF_INET6() { $af_inet6 }"; die if $@;

   delete $AnyEvent::PROTOCOL{ipv6} unless $af_inet6;
}

BEGIN {
   # broken windows perls use undocumented error codes...
   if (AnyEvent::WIN32) {
      eval "sub WSAEINVAL      () { 10022 }";
      eval "sub WSAEWOULDBLOCK () { 10035 }";
      eval "sub WSAEINPROGRESS () { 10036 }";
   } else {
      # these should never match any errno value
      eval "sub WSAEINVAL      () { -1e99 }";
      eval "sub WSAEWOULDBLOCK () { -1e99 }";
      eval "sub WSAEINPROGRESS () { -1e99 }";
   }

   # fix buggy Errno on some non-POSIX platforms
   # such as openbsd and windows.
   my %ERR = (
      EBADMSG => Errno::EDOM   (),
      EPROTO  => Errno::ESPIPE (),
   );

   while (my ($k, $v) = each %ERR) {
      next if eval "Errno::$k ()";
      warn "AnyEvent::Util: broken Errno module, adding Errno::$k.\n" if $AnyEvent::VERBOSE >= 8;

      eval "sub Errno::$k () { $v }";
      push @Errno::EXPORT_OK, $k;
      push @{ $Errno::EXPORT_TAGS{POSIX} }, $k;
   }
}

=item ($r, $w) = portable_pipe

Calling C<pipe> in Perl is portable - except it doesn't really work on
sucky windows platforms (at least not with most perls - cygwin's perl
notably works fine): On windows, you actually get two file handles you
cannot use select on.

This function gives you a pipe that actually works even on the broken
windows platform (by creating a pair of TCP sockets on windows, so do not
expect any speed from that, and using C<pipe> everywhere else).

See C<portable_socketpair>, below, for a bidirectional "pipe".

Returns the empty list on any errors.

=item ($fh1, $fh2) = portable_socketpair

Just like C<portable_pipe>, above, but returns a bidirectional pipe
(usually by calling C<socketpair> to create a local loopback socket pair,
except on windows, where it again returns two interconnected TCP sockets).

Returns the empty list on any errors.

=cut

sub _win32_socketpair {
   # perl's socketpair emulation fails on many vista machines, because
   # vista returns fantasy port numbers.

   for (1..10) {
      socket my $l, &Socket::AF_INET, &Socket::SOCK_STREAM, 0
         or next;

      bind $l, Socket::pack_sockaddr_in 0, "\x7f\x00\x00\x01"
         or next;

      my $sa = getsockname $l
         or next;

      listen $l, 1
         or next;

      socket my $r, &Socket::AF_INET, &Socket::SOCK_STREAM, 0
         or next;

      bind $r, Socket::pack_sockaddr_in 0, "\x7f\x00\x00\x01"
         or next;

      connect $r, $sa
         or next;

      accept my $w, $l
         or next;

      # vista has completely broken peername/sockname that return
      # fantasy ports. this combo seems to work, though.
      #
      (Socket::unpack_sockaddr_in getpeername $r)[0]
      == (Socket::unpack_sockaddr_in getsockname $w)[0]
         or (($! = WSAEINVAL), next);

      # vista example (you can't make this shit up...):
      #(Socket::unpack_sockaddr_in getsockname $r)[0] == 53364
      #(Socket::unpack_sockaddr_in getpeername $r)[0] == 53363
      #(Socket::unpack_sockaddr_in getsockname $w)[0] == 53363
      #(Socket::unpack_sockaddr_in getpeername $w)[0] == 53365

      return ($r, $w);
   }

   ()
}

sub portable_pipe() {
   return _win32_socketpair
      if AnyEvent::WIN32;

   my ($r, $w);

   pipe $r, $w
      or return;

   ($r, $w);
}

sub portable_socketpair() {
   return _win32_socketpair
      if AnyEvent::WIN32;

   socketpair my $fh1, my $fh2, &Socket::AF_UNIX, &Socket::SOCK_STREAM, &Socket::PF_UNSPEC
      or return;

   ($fh1, $fh2)
}

=item fork_call { CODE } @args, $cb->(@res)

Executes the given code block asynchronously, by forking. Everything the
block returns will be transferred to the calling process (by serialising and
deserialising via L<Storable>).

If there are any errors, then the C<$cb> will be called without any
arguments. In that case, either C<$@> contains the exception (and C<$!> is
irrelevant), or C<$!> contains an error number. In all other cases, C<$@>
will be C<undef>ined.

The code block must not ever call an event-polling function or use
event-based programming that might cause any callbacks registered in the
parent to run.

Win32 spoilers: Due to the endlessly sucky and broken native windows
perls (there is no way to cleanly exit a child process on that platform
that doesn't also kill the parent), you have to make sure that your main
program doesn't exit as long as any C<fork_calls> are still in progress,
otherwise the program won't exit. Also, on most windows platforms some
memory will leak for every invocation. We are open for improvements that
don't require XS hackery.

Note that forking can be expensive in large programs (RSS 200MB+). On
windows, it is abysmally slow, do not expect more than 5..20 forks/s on
that sucky platform (note this uses perl's pseudo-threads, so avoid those
like the plague).

Example: poor man's async disk I/O (better use L<IO::AIO>).

   fork_call {
      open my $fh, "</etc/passwd"
         or die "passwd: $!";
      local $/;
      <$fh>
   } sub {
      my ($passwd) = @_;
      ...
   };

=item $AnyEvent::Util::MAX_FORKS [default: 10]

The maximum number of child processes that C<fork_call> will fork in
parallel. Any additional requests will be queued until a slot becomes free
again.

The environment variable C<PERL_ANYEVENT_MAX_FORKS> is used to initialise
this value.

=cut

our $MAX_FORKS = int 1 * $ENV{PERL_ANYEVENT_MAX_FORKS};
$MAX_FORKS = 10 if $MAX_FORKS <= 0;

my $forks;
my @fork_queue;

sub _fork_schedule;
sub _fork_schedule {
   require Storable;

   while ($forks < $MAX_FORKS) {
      my $job = shift @fork_queue
         or last;

      ++$forks;

      my $coderef = shift @$job;
      my $cb = pop @$job;
      
      # gimme a break...
      my ($r, $w) = portable_pipe
         or ($forks and last) # allow failures when we have at least one job
         or die "fork_call: $!";

      my $pid = fork;

      if ($pid != 0) {
         # parent
         close $w;

         my $buf;

         my $ww; $ww = AnyEvent->io (fh => $r, poll => 'r', cb => sub {
            my $len = sysread $r, $buf, 65536, length $buf;

            if ($len <= 0) {
               undef $ww;
               close $r;
               --$forks;
               _fork_schedule;
               
               my $result = eval { Storable::thaw ($buf) };
               $result = [$@] unless $result;
               $@ = shift @$result;

               $cb->(@$result);

               # work around the endlessly broken windows perls
               kill 9, $pid if AnyEvent::WIN32;

               # clean up the pid
               waitpid $pid, 0;
            }
         });

      } elsif (defined $pid) {
         # child
         close $r;

         my $result = eval {
            local $SIG{__DIE__};

            Storable::freeze ([undef, $coderef->(@$job)])
         };

         $result = Storable::freeze (["$@"])
            if $@;

         # windows forces us to these contortions
         my $ofs;

         while () {
            my $len = (length $result) - $ofs
               or last;

            $len = syswrite $w, $result, $len < 65536 ? $len : 65536, $ofs;

            last if $len <= 0;

            $ofs += $len;
         }

         # on native windows, _exit KILLS YOUR FORKED CHILDREN!
         if (AnyEvent::WIN32) {
            shutdown $w, 1; # signal parent to please kill us
            sleep 10; # give parent a chance to clean up
            sysread $w, my $buf, 1; # this *might* detect the parent exiting in some cases.
         }
         POSIX::_exit (0);
         exit 1;
         
      } elsif (($! != &Errno::EAGAIN && $! != &Errno::ENOMEM) || !$forks) {
         # we ignore some errors as long as we can run at least one job
         # maybe we should wait a few seconds and retry instead
         die "fork_call: $!";
      }
   }
}

sub fork_call(&@) {
   push @fork_queue, [@_];
   _fork_schedule;
}

END {
   if (AnyEvent::WIN32) {
      while ($forks) {
         @fork_queue = ();
         AnyEvent->one_event;
      }
   }
}

# to be removed
sub dotted_quad($) {
   $_[0] =~ /^(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)
            \.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[0-9][0-9]?)$/x
}

# just a forwarder
sub inet_aton {
   require AnyEvent::Socket;
   *inet_aton = \&AnyEvent::Socket::inet_aton;
   goto &inet_aton
}

=item fh_nonblocking $fh, $nonblocking

Sets the blocking state of the given filehandle (true == nonblocking,
false == blocking). Uses fcntl on anything sensible and ioctl FIONBIO on
broken (i.e. windows) platforms.

=cut

sub fh_nonblocking($$) {
   my ($fh, $nb) = @_;

   require Fcntl;

   if (AnyEvent::WIN32) {
      $nb = (! ! $nb) + 0;
      ioctl $fh, 0x8004667e, \$nb; # FIONBIO
   } else {
      fcntl $fh, &Fcntl::F_SETFL, $nb ? &Fcntl::O_NONBLOCK : 0;
   }
}

=item $guard = guard { CODE }

This function creates a special object that, when called, will execute the
code block.

This is often handy in continuation-passing style code to clean up some
resource regardless of where you break out of a process.

The L<Guard> module will be used to implement this function, if it is
available. Otherwise a pure-perl implementation is used.

You can call one method on the returned object:

=item $guard->cancel

This simply causes the code block not to be invoked: it "cancels" the
guard.

=cut

sub guard(&) {
   if (!$ENV{PERL_ANYEVENT_AVOID_GUARD} && eval "use Guard 0.5 (); 1") {
      warn "AnyEvent::Util: using Guard module to implement guards.\n" if $AnyEvent::VERBOSE >= 8;
      *guard = \&Guard::guard;
   } else {
      warn "AnyEvent::Util: using pure-perl guard implementation.\n" if $AnyEvent::VERBOSE >= 8;

      *AnyEvent::Util::guard::DESTROY = sub {
         local $@;

         eval {
            local $SIG{__DIE__};
            ${$_[0]}->();
         };

         warn "runtime error in AnyEvent::guard callback: $@" if $@;
      };

      *AnyEvent::Util::guard::cancel = sub ($) {
         ${$_[0]} = sub { };
      };

      *guard = sub (&) {
         bless \(my $cb = shift), "AnyEvent::Util::guard"
      }
   }

   goto &guard;
}

#############################################################################

our %SIGNAME2NUM;

sub sig2num($) {
   return shift if $_[0] > 0;

   unless (scalar keys %SIGNAME2NUM) {
      require Config;

      @SIGNAME2NUM{ split ' ', $Config::Config{sig_name} }
                  = split ' ', $Config::Config{sig_num};
   }

   $SIGNAME2NUM{+shift}
}

1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

