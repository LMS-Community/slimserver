=head1 NAME

AE - simpler/faster/newer/cooler AnyEvent API

=head1 SYNOPSIS

  use AnyEvent; # not AE

  # file handle or descriptor readable
  my $w = AE::io $fh, 0, sub { ...  };

  # one-shot or repeating timers
  my $w = AE::timer $seconds,        0, sub { ... }; # once
  my $w = AE::timer $seconds, interval, sub { ... }; # repeated

  print AE::now;  # prints current event loop time
  print AE::time; # think Time::HiRes::time or simply CORE::time.

  # POSIX signal
  my $w = AE::signal TERM => sub { ... };

  # child process exit
  my $w = AE::child $pid, sub {
     my ($pid, $status) = @_;
     ...
  };

  # called when event loop idle (if applicable)
  my $w = AE::idle { ... };

  my $w = AE::cv; # stores whether a condition was flagged
  $w->send; # wake up current and all future recv's
  $w->recv; # enters "main loop" till $condvar gets ->send
  # use a condvar in callback mode:
  $w->cb (sub { $_[0]->recv });


=head1 DESCRIPTION

This module documents the new simpler AnyEvent API.

The rationale for the new API is that experience with L<EV> shows that
this API actually "works", despite it's lack of extensibility, leading to
a shorter, easier and faster API.

The main difference to AnyEvent is that instead of method calls, function
calls are used, and that no named arguments are used.

This makes calls to watcher creation functions really short, which can
make a program more readable, despite the lack of named parameters.
Function calls also allow more static type checking than method calls, so
many mistakes are caught at compiletime with this API.

Also, some backends (Perl and EV) are so fast that the method call
overhead is very noticeable (with EV it increases the execution time five-
to six-fold, with Perl the method call overhead is about a factor of two).

At the moment, there will be no checking (L<AnyEvent::Strict> does not
affect his API), so the L<AnyEvent> API has a definite advantage here
still.

Note that the C<AE> API is an alternative to, not the future version of,
the AnyEvent API. Both APIs can be used interchangably and and there are
no plans to "switch", so if in doubt, feel free to use the L<AnyEvent>
API in new code.

As the AE API is complementary, not everything in the AnyEvent API is
available, so you still need to use AnyEvent for the finer stuff. Also,
you should not C<use AE> directly, C<use AnyEvent> will provide the AE
namespace.

=head2 FUNCTIONS

This section briefly describes the alternative watcher
constructors. Semantics and any methods are not described here, please
refer to the L<AnyEvent> manpage for the details.

=over 4

=cut

package AE;

use AnyEvent (); # BEGIN { AnyEvent::common_sense }

our $VERSION = $AnyEvent::VERSION;

=item $w = AE::io $fh_or_fd, $watch_write, $cb

Creates an I/O watcher that listens for read events (C<$watch_write>
false) or write events (C<$watch_write> is true) on the file handle or
file descriptor C<$fh_or_fd>.

The callback C<$cb> is invoked as soon and as long as I/O of the type
specified by C<$watch_write>) can be done on the file handle/descriptor.

Example: wait until STDIN becomes readable.

  $stdin_ready = AE::io *STDIN, 0, sub { scalar <STDIN> };

Example. wait until STDOUT becomes writable and print something.

  $stdout_ready = AE::io *STDOUT, 1, sub { print STDOUT "woaw\n" };

=item $w = AE::timer $after, $interval, $cb

Creates a timer watcher that invokes the callback C<$cb> after at least
C<$after> second have passed (C<$after> can be negative or C<0>).

If C<$interval> is C<0>, then the clalback will only be invoked once,
otherwise it must be a positive number of seconds that specified the
interval between successive invocations of the callback.

Example: print "too late" after at least one second has passed.

  $timer_once = AE::timer 1, 0, sub { print "too late\n" };

Example: print "blubb" once a second, starting as soon as possible.

  $timer_repeated = AE::timer 0, 1, sub { print "blubb\n" };

=item $w = AE::signal $signame, $cb

Invoke the callback c<$cb> each time one or more occurences of the named
signal C<$signame> are detected.

=item $w = AE::child $pid, $cb

Invokes the callbakc C<$cb> when the child with the given C<$pid> exits
(or all children, when C<$pid> is zero).

The callback will get the actual pid and exit status as arguments.

=item $w = AE::idle $cb

Invoke the callback C<$cb> each time the event loop is "idle" (has no
events outstanding), but do not prevent the event loop from polling for
more events.

=item $cv = AE::cv

=item $cv = AE::cv { BLOCK }

Create a new condition variable. The first form is identical to C<<
AnyEvent->condvar >>, the second form additionally sets the callback (as
if the C<cb> method is called on the condition variable).

=item AE::now

Returns the current event loop time (may be cached by the event loop).

=item AE::now_update

Ensures that the current event loop time is up to date.

=item AE::time

Return the current time (not cached, always consults a hardware clock).

=back

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

1

