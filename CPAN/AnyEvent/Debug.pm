=head1 NAME

AnyEvent::Debug - debugging utilities for AnyEvent

=head1 SYNOPSIS

   use AnyEvent::Debug;

   # create an interactive shell into the program
   my $shell = AnyEvent::Debug::shell "unix/", "/home/schmorp/myshell";
   # then on the shell: "socat readline /home/schmorp/myshell"

=head1 DESCRIPTION

This module provides functionality hopefully useful for debugging.

At the moment, "only" an interactive shell is implemented. This shell
allows you to interactively "telnet into" your program and execute Perl
code, e.g. to look at global variables.

=head1 FUNCTIONS

=over 4

=cut

package AnyEvent::Debug;

use Errno ();

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util ();
use AnyEvent::Socket ();

=item $shell = AnyEvent;::Debug::shell $host, $service

This function binds on the given host and service port and returns a
shell object, whcih determines the lifetime of the shell. Any number
of conenctions are accepted on the port, and they will give you a very
primitive shell that simply executes every line you enter.

All commands will be executed "blockingly" with the socket C<select>ed for
output. For a less "blocking" interface see L<Coro::Debug>.

The commands will be executed in the C<AnyEvent::Debug::shell> package,
which is initially empty and up to use by all shells. Code is evaluated
under C<use strict 'subs'>.

Consider the beneficial aspects of using more global (our) variables than
local ones (my) in package scope: Earlier all my modules tended to hide
internal variables inside C<my> variables, so users couldn't accidentally
access them. Having interactive access to your programs changed that:
having internal variables still in the global scope means you can debug
them easier.

As no authenticsation is done, in most cases it is best not to use a TCP
port, but a unix domain socket, whcih cna be put wherever youc an access
it, but not others:

   our $SHELL = AnyEvent::Debug::shell "unix/", "/home/schmorp/shell";

Then you can use a tool to connect to the shell, such as the ever
versatile C<socat>, which in addition can give you readline support:

   socat readline /home/schmorp/shell
   # or:
   cd /home/schmorp; socat readline unix:shell

Socat can even give you a persistent history:

   socat readline,history=.anyevent-history unix:shell

Binding on C<127.0.0.1> (or C<::1>) might be a less secure but sitll not
totally insecure (on single-user machines) alternative to let you use
other tools, such as telnet:

   our $SHELL = AnyEvent::Debug::shell "127.1", "1357";

And then:

   telnet localhost 1357

=cut

sub shell($$) {
   AnyEvent::Socket::tcp_server $_[0], $_[1], sub {
      my ($fh, $host, $port) = @_;

      syswrite $fh, "Welcome, $host:$port!\015\012> ";
      my $rbuf;
      my $rw; $rw = AE::io $fh, 0, sub {
         my $len = sysread $fh, $rbuf, 1024, length $rbuf;

         if (defined $len ? $len == 0 : $! != Errno::EAGAIN) {
            undef $rw;
         } else {
            while ($rbuf =~ s/^(.*)\015?\012//) {
               my $line = $1;

               AnyEvent::Util::fh_nonblocking $fh, 0;

               if ($line =~ /^\s*exit\b/) {
                  syswrite $fh, "sorry, no... if you want to execute exit, try CORE::exit.\015\012";
               } else {
                  package AnyEvent::Debug::shell;

                  no strict 'vars';
                  my $old_stdout = select $fh;
                  local $| = 1;

                  my @res = eval $line;

                  select $old_stdout;
                  syswrite $fh, "$@" if $@;
                  syswrite $fh, "\015\012";

                  if (@res > 1) {
                     syswrite $fh, "$_: $res[$_]\015\012" for 0 .. $#res;
                  } elsif (@res == 1) {
                     syswrite $fh, "$res[0]\015\012";
                  }
               }

               syswrite $fh, "> ";
               AnyEvent::Util::fh_nonblocking $fh, 1;
            }
         }
      };
   }
}

1;

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

