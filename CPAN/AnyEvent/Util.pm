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

our @EXPORT = qw(fh_nonblocking guard fork_call portable_pipe portable_socketpair run_cmd);
our @EXPORT_OK = qw(AF_INET6 WSAEWOULDBLOCK WSAEINPROGRESS WSAEINVAL close_all_fds_except);

our $VERSION = $AnyEvent::VERSION;

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

         my $ww; $ww = AE::io $r, 0, sub {
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
         };

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

if (!$ENV{PERL_ANYEVENT_AVOID_GUARD} && eval { require Guard; $Guard::VERSION >= 0.5 }) {
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
   };
}

=item AnyEvent::Util::close_all_fds_except @fds

This rarely-used function simply closes all file descriptors (or tries to)
of the current process except the ones given as arguments.

When you want to start a long-running background server, then it is often
beneficial to do this, as too many C-libraries are too stupid to mark
their internal fd's as close-on-exec.

The function expects to be called shortly before an C<exec> call.

Example: close all fds except 0, 1, 2.

   close_all_fds_except 0, 2, 1;

=cut

sub close_all_fds_except {
   my %except; @except{@_} = ();

   require POSIX;

   # some OSes have a usable /dev/fd, sadly, very few
   if ($^O =~ /(freebsd|cygwin|linux)/) {
      # netbsd, openbsd, solaris have a broken /dev/fd
      my $dir;
      if (opendir $dir, "/dev/fd" or opendir $dir, "/proc/self/fd") {
         my @fds = sort { $a <=> $b } grep /^\d+$/, readdir $dir;
         # broken OS's have device nodes for 0..63 usually, solaris 0..255
         if (@fds < 20 or "@fds" ne join " ", 0..$#fds) {
            # assume the fds array is valid now
            exists $except{$_} or POSIX::close ($_)
               for @fds;
            return;
         }
      }
   }

   my $fd_max = eval { POSIX::sysconf (POSIX::_SC_OPEN_MAX ()) - 1 } || 1023;

   exists $except{$_} or POSIX::close ($_)
      for 0..$fd_max;
}

=item $cv = run_cmd $cmd, key => value...

Run a given external command, potentially redirecting file descriptors and
return a condition variable that gets sent the exit status (like C<$?>)
when the program exits I<and> all redirected file descriptors have been
exhausted.

The C<$cmd> is either a single string, which is then passed to a shell, or
an arrayref, which is passed to the C<execvp> function.

The key-value pairs can be:

=over 4

=item ">" => $filename

Redirects program standard output into the specified filename, similar to C<<
>filename >> in the shell.

=item ">" => \$data

Appends program standard output to the referenced scalar. The condvar will
not be signalled before EOF or an error is signalled.

=item ">" => $filehandle

Redirects program standard output to the given filehandle (or actually its
underlying file descriptor).

=item ">" => $callback->($data)

Calls the given callback each time standard output receives some data,
passing it the data received. On EOF or error, the callback will be
invoked once without any arguments.

The condvar will not be signalled before EOF or an error is signalled.

=item "fd>" => $see_above

Like ">", but redirects the specified fd number instead.

=item "<" => $see_above

The same, but redirects the program's standard input instead. The same
forms as for ">" are allowed.

In the callback form, the callback is supposed to return data to be
written, or the empty list or C<undef> or a zero-length scalar to signal
EOF.

Similarly, either the write data must be exhausted or an error is to be
signalled before the condvar is signalled, for both string-reference and
callback forms.

=item "fd<" => $see_above

Like "<", but redirects the specified file descriptor instead.

=item on_prepare => $cb

Specify a callback that is executed just before the comamnd is C<exec>'ed,
in the child process. Be careful not to use any event handling or other
services not available in the child.

This can be useful to set up the environment in special ways, such as
changing the priority of the command.

=item close_all => $boolean

When C<close_all> is enabled (default is disabled), then all extra file
descriptors will be closed, except the ones that were redirected and C<0>,
C<1> and C<2>.

See C<close_all_fds_except> for more details.

=item '$$' => \$pid

A reference to a scalar which will receive the PID of the newly-created
subprocess after C<run_cmd> returns.

Note the the PID might already have been recycled and used by an unrelated
process at the time C<run_cmd> returns, so it's not useful to send
signals, use a unique key in data structures and so on.

=back

Example: run C<rm -rf />, redirecting standard input, output and error to
F</dev/null>.

   my $cv = run_cmd [qw(rm -rf /)],
      "<", "/dev/null",
      ">", "/dev/null",
      "2>", "/dev/null";
   $cv->recv and die "d'oh! something survived!"

Example: run F<openssl> and create a self-signed certificate and key,
storing them in C<$cert> and C<$key>. When finished, check the exit status
in the callback and print key and certificate.

   my $cv = run_cmd [qw(openssl req 
                     -new -nodes -x509 -days 3650
                     -newkey rsa:2048 -keyout /dev/fd/3
                     -batch -subj /CN=AnyEvent
                    )],
      "<", "dev/null",
      ">" , \my $cert,
      "3>", \my $key,
      "2>", "/dev/null";

   $cv->cb (sub {
      shift->recv and die "openssl failed";

      print "$key\n$cert\n";
   });

=cut

sub run_cmd {
   my $cmd = shift;

   require POSIX;

   my $cv = AE::cv;

   my %arg;
   my %redir;
   my @exe;

   while (@_) {
      my ($type, $ob) = splice @_, 0, 2;

      my $fd = $type =~ s/^(\d+)// ? $1 : undef;

      if ($type eq ">") {
         $fd = 1 unless defined $fd;

         if (defined eval { fileno $ob }) {
            $redir{$fd} = $ob;
         } elsif (ref $ob) {
            my ($pr, $pw) = AnyEvent::Util::portable_pipe;
            $cv->begin;
            my $w; $w = AE::io $pr, 0,
               "SCALAR" eq ref $ob
                  ? sub {
                       sysread $pr, $$ob, 16384, length $$ob
                          and return;
                       undef $w; $cv->end;
                    }
                  : sub {
                       my $buf;
                       sysread $pr, $buf, 16384
                          and return $ob->($buf);
                       undef $w; $cv->end;
                       $ob->();
                    }
            ;
            $redir{$fd} = $pw;
         } else {
            push @exe, sub {
               open my $fh, ">", $ob
                  or POSIX::_exit (125);
               $redir{$fd} = $fh;
            };
         }

      } elsif ($type eq "<") {
         $fd = 0 unless defined $fd;

         if (defined eval { fileno $ob }) {
            $redir{$fd} = $ob;
         } elsif (ref $ob) {
            my ($pr, $pw) = AnyEvent::Util::portable_pipe;
            $cv->begin;

            my $data;
            if ("SCALAR" eq ref $ob) {
               $data = $$ob;
               $ob = sub { };
            } else {
               $data = $ob->();
            }

            my $w; $w = AE::io $pw, 1, sub {
               my $len = syswrite $pw, $data;

               if ($len <= 0) {
                  undef $w; $cv->end;
               } else {
                  substr $data, 0, $len, "";
                  unless (length $data) {
                     $data = $ob->();
                     unless (length $data) {
                        undef $w; $cv->end
                     }
                  }
               }
            };

            $redir{$fd} = $pr;
         } else {
            push @exe, sub {
               open my $fh, "<", $ob
                  or POSIX::_exit (125);
               $redir{$fd} = $fh;
            };
         }

      } else {
         $arg{$type} = $ob;
      }
   }

   my $pid = fork;

   defined $pid
      or Carp::croak "fork: $!";

   unless ($pid) {
      # step 1, execute
      $_->() for @exe;

      # step 2, move any existing fd's out of the way
      # this also ensures that dup2 is never called with fd1==fd2
      # so the cloexec flag is always cleared
      my (@oldfh, @close);
      for my $fh (values %redir) {
         push @oldfh, $fh; # make sure we keep it open
         $fh = fileno $fh; # we only want the fd

         # dup if we are in the way
         # if we "leak" fds here, they will be dup2'ed over later
         defined ($fh = POSIX::dup ($fh)) or POSIX::_exit (124)
            while exists $redir{$fh};
      }

      # step 3, execute redirects
      while (my ($k, $v) = each %redir) {
         defined POSIX::dup2 ($v, $k)
            or POSIX::_exit (123);
      }

      # step 4, close everything else, except 0, 1, 2
      if ($arg{close_all}) {
         close_all_fds_except 0, 1, 2, keys %redir
      } else {
         POSIX::close ($_)
            for values %redir;
      }

      eval { $arg{on_prepare}(); 1 } or POSIX::_exit (123)
         if exists $arg{on_prepare};

      ref $cmd
         ? exec {$cmd->[0]} @$cmd
         : exec $cmd;

      POSIX::_exit (126);
   }

   ${$arg{'$$'}} = $pid
      if $arg{'$$'};

   %redir = (); # close child side of the fds

   my $status;
   $cv->begin (sub { shift->send ($status) });
   my $cw; $cw = AE::child $pid, sub {
      $status = $_[1];
      undef $cw; $cv->end;
   };

   $cv
}
1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

