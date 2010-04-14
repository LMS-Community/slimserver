=head1 NAME

AnyEvent - the DBI of event loop programming

EV, Event, Glib, Tk, Perl, Event::Lib, Irssi, rxvt-unicode, IO::Async, Qt
and POE are various supported event loops/environments.

=head1 SYNOPSIS

   use AnyEvent;

   # if you prefer function calls, look at the L<AE> manpage for
   # an alternative API.

   # file handle or descriptor readable
   my $w = AnyEvent->io (fh => $fh, poll => "r", cb => sub { ...  });

   # one-shot or repeating timers
   my $w = AnyEvent->timer (after => $seconds, cb => sub { ...  });
   my $w = AnyEvent->timer (after => $seconds, interval => $seconds, cb => ...

   print AnyEvent->now;  # prints current event loop time
   print AnyEvent->time; # think Time::HiRes::time or simply CORE::time.

   # POSIX signal
   my $w = AnyEvent->signal (signal => "TERM", cb => sub { ... });

   # child process exit
   my $w = AnyEvent->child (pid => $pid, cb => sub {
      my ($pid, $status) = @_;
      ...
   });

   # called when event loop idle (if applicable)
   my $w = AnyEvent->idle (cb => sub { ... });

   my $w = AnyEvent->condvar; # stores whether a condition was flagged
   $w->send; # wake up current and all future recv's
   $w->recv; # enters "main loop" till $condvar gets ->send
   # use a condvar in callback mode:
   $w->cb (sub { $_[0]->recv });

=head1 INTRODUCTION/TUTORIAL

This manpage is mainly a reference manual. If you are interested
in a tutorial or some gentle introduction, have a look at the
L<AnyEvent::Intro> manpage.

=head1 SUPPORT

There is a mailinglist for discussing all things AnyEvent, and an IRC
channel, too.

See the AnyEvent project page at the B<Schmorpforge Ta-Sa Software
Repository>, at L<http://anyevent.schmorp.de>, for more info.

=head1 WHY YOU SHOULD USE THIS MODULE (OR NOT)

Glib, POE, IO::Async, Event... CPAN offers event models by the dozen
nowadays. So what is different about AnyEvent?

Executive Summary: AnyEvent is I<compatible>, AnyEvent is I<free of
policy> and AnyEvent is I<small and efficient>.

First and foremost, I<AnyEvent is not an event model> itself, it only
interfaces to whatever event model the main program happens to use, in a
pragmatic way. For event models and certain classes of immortals alike,
the statement "there can only be one" is a bitter reality: In general,
only one event loop can be active at the same time in a process. AnyEvent
cannot change this, but it can hide the differences between those event
loops.

The goal of AnyEvent is to offer module authors the ability to do event
programming (waiting for I/O or timer events) without subscribing to a
religion, a way of living, and most importantly: without forcing your
module users into the same thing by forcing them to use the same event
model you use.

For modules like POE or IO::Async (which is a total misnomer as it is
actually doing all I/O I<synchronously>...), using them in your module is
like joining a cult: After you joined, you are dependent on them and you
cannot use anything else, as they are simply incompatible to everything
that isn't them. What's worse, all the potential users of your
module are I<also> forced to use the same event loop you use.

AnyEvent is different: AnyEvent + POE works fine. AnyEvent + Glib works
fine. AnyEvent + Tk works fine etc. etc. but none of these work together
with the rest: POE + IO::Async? No go. Tk + Event? No go. Again: if
your module uses one of those, every user of your module has to use it,
too. But if your module uses AnyEvent, it works transparently with all
event models it supports (including stuff like IO::Async, as long as those
use one of the supported event loops. It is trivial to add new event loops
to AnyEvent, too, so it is future-proof).

In addition to being free of having to use I<the one and only true event
model>, AnyEvent also is free of bloat and policy: with POE or similar
modules, you get an enormous amount of code and strict rules you have to
follow. AnyEvent, on the other hand, is lean and up to the point, by only
offering the functionality that is necessary, in as thin as a wrapper as
technically possible.

Of course, AnyEvent comes with a big (and fully optional!) toolbox
of useful functionality, such as an asynchronous DNS resolver, 100%
non-blocking connects (even with TLS/SSL, IPv6 and on broken platforms
such as Windows) and lots of real-world knowledge and workarounds for
platform bugs and differences.

Now, if you I<do want> lots of policy (this can arguably be somewhat
useful) and you want to force your users to use the one and only event
model, you should I<not> use this module.

=head1 DESCRIPTION

L<AnyEvent> provides an identical interface to multiple event loops. This
allows module authors to utilise an event loop without forcing module
users to use the same event loop (as only a single event loop can coexist
peacefully at any one time).

The interface itself is vaguely similar, but not identical to the L<Event>
module.

During the first call of any watcher-creation method, the module tries
to detect the currently loaded event loop by probing whether one of the
following modules is already loaded: L<EV>,
L<Event>, L<Glib>, L<AnyEvent::Impl::Perl>, L<Tk>, L<Event::Lib>, L<Qt>,
L<POE>. The first one found is used. If none are found, the module tries
to load these modules (excluding Tk, Event::Lib, Qt and POE as the pure perl
adaptor should always succeed) in the order given. The first one that can
be successfully loaded will be used. If, after this, still none could be
found, AnyEvent will fall back to a pure-perl event loop, which is not
very efficient, but should work everywhere.

Because AnyEvent first checks for modules that are already loaded, loading
an event model explicitly before first using AnyEvent will likely make
that model the default. For example:

   use Tk;
   use AnyEvent;

   # .. AnyEvent will likely default to Tk

The I<likely> means that, if any module loads another event model and
starts using it, all bets are off. Maybe you should tell their authors to
use AnyEvent so their modules work together with others seamlessly...

The pure-perl implementation of AnyEvent is called
C<AnyEvent::Impl::Perl>. Like other event modules you can load it
explicitly and enjoy the high availability of that event loop :)

=head1 WATCHERS

AnyEvent has the central concept of a I<watcher>, which is an object that
stores relevant data for each kind of event you are waiting for, such as
the callback to call, the file handle to watch, etc.

These watchers are normal Perl objects with normal Perl lifetime. After
creating a watcher it will immediately "watch" for events and invoke the
callback when the event occurs (of course, only when the event model
is in control).

Note that B<callbacks must not permanently change global variables>
potentially in use by the event loop (such as C<$_> or C<$[>) and that B<<
callbacks must not C<die> >>. The former is good programming practise in
Perl and the latter stems from the fact that exception handling differs
widely between event loops.

To disable the watcher you have to destroy it (e.g. by setting the
variable you store it in to C<undef> or otherwise deleting all references
to it).

All watchers are created by calling a method on the C<AnyEvent> class.

Many watchers either are used with "recursion" (repeating timers for
example), or need to refer to their watcher object in other ways.

An any way to achieve that is this pattern:

   my $w; $w = AnyEvent->type (arg => value ..., cb => sub {
      # you can use $w here, for example to undef it
      undef $w;
   });

Note that C<my $w; $w => combination. This is necessary because in Perl,
my variables are only visible after the statement in which they are
declared.

=head2 I/O WATCHERS

   $w = AnyEvent->io (
      fh   => <filehandle_or_fileno>,
      poll => <"r" or "w">,
      cb   => <callback>,
   );

You can create an I/O watcher by calling the C<< AnyEvent->io >> method
with the following mandatory key-value pairs as arguments:

C<fh> is the Perl I<file handle> (or a naked file descriptor) to watch
for events (AnyEvent might or might not keep a reference to this file
handle). Note that only file handles pointing to things for which
non-blocking operation makes sense are allowed. This includes sockets,
most character devices, pipes, fifos and so on, but not for example files
or block devices.

C<poll> must be a string that is either C<r> or C<w>, which creates a
watcher waiting for "r"eadable or "w"ritable events, respectively.

C<cb> is the callback to invoke each time the file handle becomes ready.

Although the callback might get passed parameters, their value and
presence is undefined and you cannot rely on them. Portable AnyEvent
callbacks cannot use arguments passed to I/O watcher callbacks.

The I/O watcher might use the underlying file descriptor or a copy of it.
You must not close a file handle as long as any watcher is active on the
underlying file descriptor.

Some event loops issue spurious readyness notifications, so you should
always use non-blocking calls when reading/writing from/to your file
handles.

Example: wait for readability of STDIN, then read a line and disable the
watcher.

   my $w; $w = AnyEvent->io (fh => \*STDIN, poll => 'r', cb => sub {
      chomp (my $input = <STDIN>);
      warn "read: $input\n";
      undef $w;
   });

=head2 TIME WATCHERS

   $w = AnyEvent->timer (after => <seconds>, cb => <callback>);

   $w = AnyEvent->timer (
      after    => <fractional_seconds>,
      interval => <fractional_seconds>,
      cb       => <callback>,
   );

You can create a time watcher by calling the C<< AnyEvent->timer >>
method with the following mandatory arguments:

C<after> specifies after how many seconds (fractional values are
supported) the callback should be invoked. C<cb> is the callback to invoke
in that case.

Although the callback might get passed parameters, their value and
presence is undefined and you cannot rely on them. Portable AnyEvent
callbacks cannot use arguments passed to time watcher callbacks.

The callback will normally be invoked once only. If you specify another
parameter, C<interval>, as a strictly positive number (> 0), then the
callback will be invoked regularly at that interval (in fractional
seconds) after the first invocation. If C<interval> is specified with a
false value, then it is treated as if it were missing.

The callback will be rescheduled before invoking the callback, but no
attempt is done to avoid timer drift in most backends, so the interval is
only approximate.

Example: fire an event after 7.7 seconds.

   my $w = AnyEvent->timer (after => 7.7, cb => sub {
      warn "timeout\n";
   });

   # to cancel the timer:
   undef $w;

Example 2: fire an event after 0.5 seconds, then roughly every second.

   my $w = AnyEvent->timer (after => 0.5, interval => 1, cb => sub {
      warn "timeout\n";
   };

=head3 TIMING ISSUES

There are two ways to handle timers: based on real time (relative, "fire
in 10 seconds") and based on wallclock time (absolute, "fire at 12
o'clock").

While most event loops expect timers to specified in a relative way, they
use absolute time internally. This makes a difference when your clock
"jumps", for example, when ntp decides to set your clock backwards from
the wrong date of 2014-01-01 to 2008-01-01, a watcher that is supposed to
fire "after" a second might actually take six years to finally fire.

AnyEvent cannot compensate for this. The only event loop that is conscious
about these issues is L<EV>, which offers both relative (ev_timer, based
on true relative time) and absolute (ev_periodic, based on wallclock time)
timers.

AnyEvent always prefers relative timers, if available, matching the
AnyEvent API.

AnyEvent has two additional methods that return the "current time":

=over 4

=item AnyEvent->time

This returns the "current wallclock time" as a fractional number of
seconds since the Epoch (the same thing as C<time> or C<Time::HiRes::time>
return, and the result is guaranteed to be compatible with those).

It progresses independently of any event loop processing, i.e. each call
will check the system clock, which usually gets updated frequently.

=item AnyEvent->now

This also returns the "current wallclock time", but unlike C<time>, above,
this value might change only once per event loop iteration, depending on
the event loop (most return the same time as C<time>, above). This is the
time that AnyEvent's timers get scheduled against.

I<In almost all cases (in all cases if you don't care), this is the
function to call when you want to know the current time.>

This function is also often faster then C<< AnyEvent->time >>, and
thus the preferred method if you want some timestamp (for example,
L<AnyEvent::Handle> uses this to update it's activity timeouts).

The rest of this section is only of relevance if you try to be very exact
with your timing, you can skip it without bad conscience.

For a practical example of when these times differ, consider L<Event::Lib>
and L<EV> and the following set-up:

The event loop is running and has just invoked one of your callback at
time=500 (assume no other callbacks delay processing). In your callback,
you wait a second by executing C<sleep 1> (blocking the process for a
second) and then (at time=501) you create a relative timer that fires
after three seconds.

With L<Event::Lib>, C<< AnyEvent->time >> and C<< AnyEvent->now >> will
both return C<501>, because that is the current time, and the timer will
be scheduled to fire at time=504 (C<501> + C<3>).

With L<EV>, C<< AnyEvent->time >> returns C<501> (as that is the current
time), but C<< AnyEvent->now >> returns C<500>, as that is the time the
last event processing phase started. With L<EV>, your timer gets scheduled
to run at time=503 (C<500> + C<3>).

In one sense, L<Event::Lib> is more exact, as it uses the current time
regardless of any delays introduced by event processing. However, most
callbacks do not expect large delays in processing, so this causes a
higher drift (and a lot more system calls to get the current time).

In another sense, L<EV> is more exact, as your timer will be scheduled at
the same time, regardless of how long event processing actually took.

In either case, if you care (and in most cases, you don't), then you
can get whatever behaviour you want with any event loop, by taking the
difference between C<< AnyEvent->time >> and C<< AnyEvent->now >> into
account.

=item AnyEvent->now_update

Some event loops (such as L<EV> or L<AnyEvent::Impl::Perl>) cache
the current time for each loop iteration (see the discussion of L<<
AnyEvent->now >>, above).

When a callback runs for a long time (or when the process sleeps), then
this "current" time will differ substantially from the real time, which
might affect timers and time-outs.

When this is the case, you can call this method, which will update the
event loop's idea of "current time".

A typical example would be a script in a web server (e.g. C<mod_perl>) -
when mod_perl executes the script, then the event loop will have the wrong
idea about the "current time" (being potentially far in the past, when the
script ran the last time). In that case you should arrange a call to C<<
AnyEvent->now_update >> each time the web server process wakes up again
(e.g. at the start of your script, or in a handler).

Note that updating the time I<might> cause some events to be handled.

=back

=head2 SIGNAL WATCHERS

   $w = AnyEvent->signal (signal => <uppercase_signal_name>, cb => <callback>);

You can watch for signals using a signal watcher, C<signal> is the signal
I<name> in uppercase and without any C<SIG> prefix, C<cb> is the Perl
callback to be invoked whenever a signal occurs.

Although the callback might get passed parameters, their value and
presence is undefined and you cannot rely on them. Portable AnyEvent
callbacks cannot use arguments passed to signal watcher callbacks.

Multiple signal occurrences can be clumped together into one callback
invocation, and callback invocation will be synchronous. Synchronous means
that it might take a while until the signal gets handled by the process,
but it is guaranteed not to interrupt any other callbacks.

The main advantage of using these watchers is that you can share a signal
between multiple watchers, and AnyEvent will ensure that signals will not
interrupt your program at bad times.

This watcher might use C<%SIG> (depending on the event loop used),
so programs overwriting those signals directly will likely not work
correctly.

Example: exit on SIGINT

   my $w = AnyEvent->signal (signal => "INT", cb => sub { exit 1 });

=head3 Restart Behaviour

While restart behaviour is up to the event loop implementation, most will
not restart syscalls (that includes L<Async::Interrupt> and AnyEvent's
pure perl implementation).

=head3 Safe/Unsafe Signals

Perl signals can be either "safe" (synchronous to opcode handling) or
"unsafe" (asynchronous) - the former might get delayed indefinitely, the
latter might corrupt your memory.

AnyEvent signal handlers are, in addition, synchronous to the event loop,
i.e. they will not interrupt your running perl program but will only be
called as part of the normal event handling (just like timer, I/O etc.
callbacks, too).

=head3 Signal Races, Delays and Workarounds

Many event loops (e.g. Glib, Tk, Qt, IO::Async) do not support attaching
callbacks to signals in a generic way, which is a pity, as you cannot
do race-free signal handling in perl, requiring C libraries for
this. AnyEvent will try to do it's best, which means in some cases,
signals will be delayed. The maximum time a signal might be delayed is
specified in C<$AnyEvent::MAX_SIGNAL_LATENCY> (default: 10 seconds). This
variable can be changed only before the first signal watcher is created,
and should be left alone otherwise. This variable determines how often
AnyEvent polls for signals (in case a wake-up was missed). Higher values
will cause fewer spurious wake-ups, which is better for power and CPU
saving.

All these problems can be avoided by installing the optional
L<Async::Interrupt> module, which works with most event loops. It will not
work with inherently broken event loops such as L<Event> or L<Event::Lib>
(and not with L<POE> currently, as POE does it's own workaround with
one-second latency). For those, you just have to suffer the delays.

=head2 CHILD PROCESS WATCHERS

   $w = AnyEvent->child (pid => <process id>, cb => <callback>);

You can also watch on a child process exit and catch its exit status.

The child process is specified by the C<pid> argument (one some backends,
using C<0> watches for any child process exit, on others this will
croak). The watcher will be triggered only when the child process has
finished and an exit status is available, not on any trace events
(stopped/continued).

The callback will be called with the pid and exit status (as returned by
waitpid), so unlike other watcher types, you I<can> rely on child watcher
callback arguments.

This watcher type works by installing a signal handler for C<SIGCHLD>,
and since it cannot be shared, nothing else should use SIGCHLD or reap
random child processes (waiting for specific child processes, e.g. inside
C<system>, is just fine).

There is a slight catch to child watchers, however: you usually start them
I<after> the child process was created, and this means the process could
have exited already (and no SIGCHLD will be sent anymore).

Not all event models handle this correctly (neither POE nor IO::Async do,
see their AnyEvent::Impl manpages for details), but even for event models
that I<do> handle this correctly, they usually need to be loaded before
the process exits (i.e. before you fork in the first place). AnyEvent's
pure perl event loop handles all cases correctly regardless of when you
start the watcher.

This means you cannot create a child watcher as the very first
thing in an AnyEvent program, you I<have> to create at least one
watcher before you C<fork> the child (alternatively, you can call
C<AnyEvent::detect>).

As most event loops do not support waiting for child events, they will be
emulated by AnyEvent in most cases, in which the latency and race problems
mentioned in the description of signal watchers apply.

Example: fork a process and wait for it

   my $done = AnyEvent->condvar;
  
   my $pid = fork or exit 5;
  
   my $w = AnyEvent->child (
      pid => $pid,
      cb  => sub {
         my ($pid, $status) = @_;
         warn "pid $pid exited with status $status";
         $done->send;
      },
   );
  
   # do something else, then wait for process exit
   $done->recv;

=head2 IDLE WATCHERS

   $w = AnyEvent->idle (cb => <callback>);

Repeatedly invoke the callback after the process becomes idle, until
either the watcher is destroyed or new events have been detected.

Idle watchers are useful when there is a need to do something, but it
is not so important (or wise) to do it instantly. The callback will be
invoked only when there is "nothing better to do", which is usually
defined as "all outstanding events have been handled and no new events
have been detected". That means that idle watchers ideally get invoked
when the event loop has just polled for new events but none have been
detected. Instead of blocking to wait for more events, the idle watchers
will be invoked.

Unfortunately, most event loops do not really support idle watchers (only
EV, Event and Glib do it in a usable fashion) - for the rest, AnyEvent
will simply call the callback "from time to time".

Example: read lines from STDIN, but only process them when the
program is otherwise idle:

   my @lines; # read data
   my $idle_w;
   my $io_w = AnyEvent->io (fh => \*STDIN, poll => 'r', cb => sub {
      push @lines, scalar <STDIN>;

      # start an idle watcher, if not already done
      $idle_w ||= AnyEvent->idle (cb => sub {
         # handle only one line, when there are lines left
         if (my $line = shift @lines) {
            print "handled when idle: $line";
         } else {
            # otherwise disable the idle watcher again
            undef $idle_w;
         }
      });
   });

=head2 CONDITION VARIABLES

   $cv = AnyEvent->condvar;

   $cv->send (<list>);
   my @res = $cv->recv;

If you are familiar with some event loops you will know that all of them
require you to run some blocking "loop", "run" or similar function that
will actively watch for new events and call your callbacks.

AnyEvent is slightly different: it expects somebody else to run the event
loop and will only block when necessary (usually when told by the user).

The instrument to do that is called a "condition variable", so called
because they represent a condition that must become true.

Now is probably a good time to look at the examples further below.

Condition variables can be created by calling the C<< AnyEvent->condvar
>> method, usually without arguments. The only argument pair allowed is
C<cb>, which specifies a callback to be called when the condition variable
becomes true, with the condition variable as the first argument (but not
the results).

After creation, the condition variable is "false" until it becomes "true"
by calling the C<send> method (or calling the condition variable as if it
were a callback, read about the caveats in the description for the C<<
->send >> method).

Condition variables are similar to callbacks, except that you can
optionally wait for them. They can also be called merge points - points
in time where multiple outstanding events have been processed. And yet
another way to call them is transactions - each condition variable can be
used to represent a transaction, which finishes at some point and delivers
a result. And yet some people know them as "futures" - a promise to
compute/deliver something that you can wait for.

Condition variables are very useful to signal that something has finished,
for example, if you write a module that does asynchronous http requests,
then a condition variable would be the ideal candidate to signal the
availability of results. The user can either act when the callback is
called or can synchronously C<< ->recv >> for the results.

You can also use them to simulate traditional event loops - for example,
you can block your main program until an event occurs - for example, you
could C<< ->recv >> in your main program until the user clicks the Quit
button of your app, which would C<< ->send >> the "quit" event.

Note that condition variables recurse into the event loop - if you have
two pieces of code that call C<< ->recv >> in a round-robin fashion, you
lose. Therefore, condition variables are good to export to your caller, but
you should avoid making a blocking wait yourself, at least in callbacks,
as this asks for trouble.

Condition variables are represented by hash refs in perl, and the keys
used by AnyEvent itself are all named C<_ae_XXX> to make subclassing
easy (it is often useful to build your own transaction class on top of
AnyEvent). To subclass, use C<AnyEvent::CondVar> as base class and call
it's C<new> method in your own C<new> method.

There are two "sides" to a condition variable - the "producer side" which
eventually calls C<< -> send >>, and the "consumer side", which waits
for the send to occur.

Example: wait for a timer.

   # condition: "wait till the timer is fired"
   my $timer_fired = AnyEvent->condvar;

   # create the timer - we could wait for, say
   # a handle becomign ready, or even an
   # AnyEvent::HTTP request to finish, but
   # in this case, we simply use a timer:
   my $w = AnyEvent->timer (
      after => 1,
      cb    => sub { $timer_fired->send },
   );

   # this "blocks" (while handling events) till the callback
   # calls ->send
   $timer_fired->recv;

Example: wait for a timer, but take advantage of the fact that condition
variables are also callable directly.

   my $done = AnyEvent->condvar;
   my $delay = AnyEvent->timer (after => 5, cb => $done);
   $done->recv;

Example: Imagine an API that returns a condvar and doesn't support
callbacks. This is how you make a synchronous call, for example from
the main program:

   use AnyEvent::CouchDB;

   ...

   my @info = $couchdb->info->recv;

And this is how you would just set a callback to be called whenever the
results are available:

   $couchdb->info->cb (sub {
      my @info = $_[0]->recv;
   });

=head3 METHODS FOR PRODUCERS

These methods should only be used by the producing side, i.e. the
code/module that eventually sends the signal. Note that it is also
the producer side which creates the condvar in most cases, but it isn't
uncommon for the consumer to create it as well.

=over 4

=item $cv->send (...)

Flag the condition as ready - a running C<< ->recv >> and all further
calls to C<recv> will (eventually) return after this method has been
called. If nobody is waiting the send will be remembered.

If a callback has been set on the condition variable, it is called
immediately from within send.

Any arguments passed to the C<send> call will be returned by all
future C<< ->recv >> calls.

Condition variables are overloaded so one can call them directly (as if
they were a code reference). Calling them directly is the same as calling
C<send>.

=item $cv->croak ($error)

Similar to send, but causes all call's to C<< ->recv >> to invoke
C<Carp::croak> with the given error message/object/scalar.

This can be used to signal any errors to the condition variable
user/consumer. Doing it this way instead of calling C<croak> directly
delays the error detetcion, but has the overwhelmign advantage that it
diagnoses the error at the place where the result is expected, and not
deep in some event clalback without connection to the actual code causing
the problem.

=item $cv->begin ([group callback])

=item $cv->end

These two methods can be used to combine many transactions/events into
one. For example, a function that pings many hosts in parallel might want
to use a condition variable for the whole process.

Every call to C<< ->begin >> will increment a counter, and every call to
C<< ->end >> will decrement it.  If the counter reaches C<0> in C<< ->end
>>, the (last) callback passed to C<begin> will be executed, passing the
condvar as first argument. That callback is I<supposed> to call C<< ->send
>>, but that is not required. If no group callback was set, C<send> will
be called without any arguments.

You can think of C<< $cv->send >> giving you an OR condition (one call
sends), while C<< $cv->begin >> and C<< $cv->end >> giving you an AND
condition (all C<begin> calls must be C<end>'ed before the condvar sends).

Let's start with a simple example: you have two I/O watchers (for example,
STDOUT and STDERR for a program), and you want to wait for both streams to
close before activating a condvar:

   my $cv = AnyEvent->condvar;

   $cv->begin; # first watcher
   my $w1 = AnyEvent->io (fh => $fh1, cb => sub {
      defined sysread $fh1, my $buf, 4096
         or $cv->end;
   });

   $cv->begin; # second watcher
   my $w2 = AnyEvent->io (fh => $fh2, cb => sub {
      defined sysread $fh2, my $buf, 4096
         or $cv->end;
   });

   $cv->recv;

This works because for every event source (EOF on file handle), there is
one call to C<begin>, so the condvar waits for all calls to C<end> before
sending.

The ping example mentioned above is slightly more complicated, as the
there are results to be passwd back, and the number of tasks that are
begung can potentially be zero:

   my $cv = AnyEvent->condvar;

   my %result;
   $cv->begin (sub { shift->send (\%result) });

   for my $host (@list_of_hosts) {
      $cv->begin;
      ping_host_then_call_callback $host, sub {
         $result{$host} = ...;
         $cv->end;
      };
   }

   $cv->end;

This code fragment supposedly pings a number of hosts and calls
C<send> after results for all then have have been gathered - in any
order. To achieve this, the code issues a call to C<begin> when it starts
each ping request and calls C<end> when it has received some result for
it. Since C<begin> and C<end> only maintain a counter, the order in which
results arrive is not relevant.

There is an additional bracketing call to C<begin> and C<end> outside the
loop, which serves two important purposes: first, it sets the callback
to be called once the counter reaches C<0>, and second, it ensures that
C<send> is called even when C<no> hosts are being pinged (the loop
doesn't execute once).

This is the general pattern when you "fan out" into multiple (but
potentially none) subrequests: use an outer C<begin>/C<end> pair to set
the callback and ensure C<end> is called at least once, and then, for each
subrequest you start, call C<begin> and for each subrequest you finish,
call C<end>.

=back

=head3 METHODS FOR CONSUMERS

These methods should only be used by the consuming side, i.e. the
code awaits the condition.

=over 4

=item $cv->recv

Wait (blocking if necessary) until the C<< ->send >> or C<< ->croak
>> methods have been called on c<$cv>, while servicing other watchers
normally.

You can only wait once on a condition - additional calls are valid but
will return immediately.

If an error condition has been set by calling C<< ->croak >>, then this
function will call C<croak>.

In list context, all parameters passed to C<send> will be returned,
in scalar context only the first one will be returned.

Note that doing a blocking wait in a callback is not supported by any
event loop, that is, recursive invocation of a blocking C<< ->recv
>> is not allowed, and the C<recv> call will C<croak> if such a
condition is detected. This condition can be slightly loosened by using
L<Coro::AnyEvent>, which allows you to do a blocking C<< ->recv >> from
any thread that doesn't run the event loop itself.

Not all event models support a blocking wait - some die in that case
(programs might want to do that to stay interactive), so I<if you are
using this from a module, never require a blocking wait>. Instead, let the
caller decide whether the call will block or not (for example, by coupling
condition variables with some kind of request results and supporting
callbacks so the caller knows that getting the result will not block,
while still supporting blocking waits if the caller so desires).

You can ensure that C<< -recv >> never blocks by setting a callback and
only calling C<< ->recv >> from within that callback (or at a later
time). This will work even when the event loop does not support blocking
waits otherwise.

=item $bool = $cv->ready

Returns true when the condition is "true", i.e. whether C<send> or
C<croak> have been called.

=item $cb = $cv->cb ($cb->($cv))

This is a mutator function that returns the callback set and optionally
replaces it before doing so.

The callback will be called when the condition becomes (or already was)
"true", i.e. when C<send> or C<croak> are called (or were called), with
the only argument being the condition variable itself. Calling C<recv>
inside the callback or at any later time is guaranteed not to block.

=back

=head1 SUPPORTED EVENT LOOPS/BACKENDS

The available backend classes are (every class has its own manpage):

=over 4

=item Backends that are autoprobed when no other event loop can be found.

EV is the preferred backend when no other event loop seems to be in
use. If EV is not installed, then AnyEvent will fall back to its own
pure-perl implementation, which is available everywhere as it comes with
AnyEvent itself.

   AnyEvent::Impl::EV        based on EV (interface to libev, best choice).
   AnyEvent::Impl::Perl      pure-perl implementation, fast and portable.

=item Backends that are transparently being picked up when they are used.

These will be used when they are currently loaded when the first watcher
is created, in which case it is assumed that the application is using
them. This means that AnyEvent will automatically pick the right backend
when the main program loads an event module before anything starts to
create watchers. Nothing special needs to be done by the main program.

   AnyEvent::Impl::Event     based on Event, very stable, few glitches.
   AnyEvent::Impl::Glib      based on Glib, slow but very stable.
   AnyEvent::Impl::Tk        based on Tk, very broken.
   AnyEvent::Impl::EventLib  based on Event::Lib, leaks memory and worse.
   AnyEvent::Impl::POE       based on POE, very slow, some limitations.
   AnyEvent::Impl::Irssi     used when running within irssi.

=item Backends with special needs.

Qt requires the Qt::Application to be instantiated first, but will
otherwise be picked up automatically. As long as the main program
instantiates the application before any AnyEvent watchers are created,
everything should just work.

   AnyEvent::Impl::Qt        based on Qt.

Support for IO::Async can only be partial, as it is too broken and
architecturally limited to even support the AnyEvent API. It also
is the only event loop that needs the loop to be set explicitly, so
it can only be used by a main program knowing about AnyEvent. See
L<AnyEvent::Impl::Async> for the gory details.

   AnyEvent::Impl::IOAsync   based on IO::Async, cannot be autoprobed.

=item Event loops that are indirectly supported via other backends.

Some event loops can be supported via other modules:

There is no direct support for WxWidgets (L<Wx>) or L<Prima>.

B<WxWidgets> has no support for watching file handles. However, you can
use WxWidgets through the POE adaptor, as POE has a Wx backend that simply
polls 20 times per second, which was considered to be too horrible to even
consider for AnyEvent.

B<Prima> is not supported as nobody seems to be using it, but it has a POE
backend, so it can be supported through POE.

AnyEvent knows about both L<Prima> and L<Wx>, however, and will try to
load L<POE> when detecting them, in the hope that POE will pick them up,
in which case everything will be automatic.

=back

=head1 GLOBAL VARIABLES AND FUNCTIONS

These are not normally required to use AnyEvent, but can be useful to
write AnyEvent extension modules.

=over 4

=item $AnyEvent::MODEL

Contains C<undef> until the first watcher is being created, before the
backend has been autodetected.

Afterwards it contains the event model that is being used, which is the
name of the Perl class implementing the model. This class is usually one
of the C<AnyEvent::Impl:xxx> modules, but can be any other class in the
case AnyEvent has been extended at runtime (e.g. in I<rxvt-unicode> it
will be C<urxvt::anyevent>).

=item AnyEvent::detect

Returns C<$AnyEvent::MODEL>, forcing autodetection of the event model
if necessary. You should only call this function right before you would
have created an AnyEvent watcher anyway, that is, as late as possible at
runtime, and not e.g. while initialising of your module.

If you need to do some initialisation before AnyEvent watchers are
created, use C<post_detect>.

=item $guard = AnyEvent::post_detect { BLOCK }

Arranges for the code block to be executed as soon as the event model is
autodetected (or immediately if this has already happened).

The block will be executed I<after> the actual backend has been detected
(C<$AnyEvent::MODEL> is set), but I<before> any watchers have been
created, so it is possible to e.g. patch C<@AnyEvent::ISA> or do
other initialisations - see the sources of L<AnyEvent::Strict> or
L<AnyEvent::AIO> to see how this is used.

The most common usage is to create some global watchers, without forcing
event module detection too early, for example, L<AnyEvent::AIO> creates
and installs the global L<IO::AIO> watcher in a C<post_detect> block to
avoid autodetecting the event module at load time.

If called in scalar or list context, then it creates and returns an object
that automatically removes the callback again when it is destroyed (or
C<undef> when the hook was immediately executed). See L<AnyEvent::AIO> for
a case where this is useful.

Example: Create a watcher for the IO::AIO module and store it in
C<$WATCHER>. Only do so after the event loop is initialised, though.

   our WATCHER;

   my $guard = AnyEvent::post_detect {
      $WATCHER = AnyEvent->io (fh => IO::AIO::poll_fileno, poll => 'r', cb => \&IO::AIO::poll_cb);
   };

   # the ||= is important in case post_detect immediately runs the block,
   # as to not clobber the newly-created watcher. assigning both watcher and
   # post_detect guard to the same variable has the advantage of users being
   # able to just C<undef $WATCHER> if the watcher causes them grief.

   $WATCHER ||= $guard;

=item @AnyEvent::post_detect

If there are any code references in this array (you can C<push> to it
before or after loading AnyEvent), then they will called directly after
the event loop has been chosen.

You should check C<$AnyEvent::MODEL> before adding to this array, though:
if it is defined then the event loop has already been detected, and the
array will be ignored.

Best use C<AnyEvent::post_detect { BLOCK }> when your application allows
it, as it takes care of these details.

This variable is mainly useful for modules that can do something useful
when AnyEvent is used and thus want to know when it is initialised, but do
not need to even load it by default. This array provides the means to hook
into AnyEvent passively, without loading it.

Example: To load Coro::AnyEvent whenever Coro and AnyEvent are used
together, you could put this into Coro (this is the actual code used by
Coro to accomplish this):

   if (defined $AnyEvent::MODEL) {
      # AnyEvent already initialised, so load Coro::AnyEvent
      require Coro::AnyEvent;
   } else {
      # AnyEvent not yet initialised, so make sure to load Coro::AnyEvent
      # as soon as it is
      push @AnyEvent::post_detect, sub { require Coro::AnyEvent };
   }

=back

=head1 WHAT TO DO IN A MODULE

As a module author, you should C<use AnyEvent> and call AnyEvent methods
freely, but you should not load a specific event module or rely on it.

Be careful when you create watchers in the module body - AnyEvent will
decide which event module to use as soon as the first method is called, so
by calling AnyEvent in your module body you force the user of your module
to load the event module first.

Never call C<< ->recv >> on a condition variable unless you I<know> that
the C<< ->send >> method has been called on it already. This is
because it will stall the whole program, and the whole point of using
events is to stay interactive.

It is fine, however, to call C<< ->recv >> when the user of your module
requests it (i.e. if you create a http request object ad have a method
called C<results> that returns the results, it should call C<< ->recv >>
freely, as the user of your module knows what she is doing. always).

=head1 WHAT TO DO IN THE MAIN PROGRAM

There will always be a single main program - the only place that should
dictate which event model to use.

If it doesn't care, it can just "use AnyEvent" and use it itself, or not
do anything special (it does not need to be event-based) and let AnyEvent
decide which implementation to chose if some module relies on it.

If the main program relies on a specific event model - for example, in
Gtk2 programs you have to rely on the Glib module - you should load the
event module before loading AnyEvent or any module that uses it: generally
speaking, you should load it as early as possible. The reason is that
modules might create watchers when they are loaded, and AnyEvent will
decide on the event model to use as soon as it creates watchers, and it
might chose the wrong one unless you load the correct one yourself.

You can chose to use a pure-perl implementation by loading the
C<AnyEvent::Impl::Perl> module, which gives you similar behaviour
everywhere, but letting AnyEvent chose the model is generally better.

=head2 MAINLOOP EMULATION

Sometimes (often for short test scripts, or even standalone programs who
only want to use AnyEvent), you do not want to run a specific event loop.

In that case, you can use a condition variable like this:

   AnyEvent->condvar->recv;

This has the effect of entering the event loop and looping forever.

Note that usually your program has some exit condition, in which case
it is better to use the "traditional" approach of storing a condition
variable somewhere, waiting for it, and sending it when the program should
exit cleanly.


=head1 OTHER MODULES

The following is a non-exhaustive list of additional modules that use
AnyEvent as a client and can therefore be mixed easily with other AnyEvent
modules and other event loops in the same program. Some of the modules
come with AnyEvent, most are available via CPAN.

=over 4

=item L<AnyEvent::Util>

Contains various utility functions that replace often-used but blocking
functions such as C<inet_aton> by event-/callback-based versions.

=item L<AnyEvent::Socket>

Provides various utility functions for (internet protocol) sockets,
addresses and name resolution. Also functions to create non-blocking tcp
connections or tcp servers, with IPv6 and SRV record support and more.

=item L<AnyEvent::Handle>

Provide read and write buffers, manages watchers for reads and writes,
supports raw and formatted I/O, I/O queued and fully transparent and
non-blocking SSL/TLS (via L<AnyEvent::TLS>.

=item L<AnyEvent::DNS>

Provides rich asynchronous DNS resolver capabilities.

=item L<AnyEvent::HTTP>

A simple-to-use HTTP library that is capable of making a lot of concurrent
HTTP requests.

=item L<AnyEvent::HTTPD>

Provides a simple web application server framework.

=item L<AnyEvent::FastPing>

The fastest ping in the west.

=item L<AnyEvent::DBI>

Executes L<DBI> requests asynchronously in a proxy process.

=item L<AnyEvent::AIO>

Truly asynchronous I/O, should be in the toolbox of every event
programmer. AnyEvent::AIO transparently fuses L<IO::AIO> and AnyEvent
together.

=item L<AnyEvent::BDB>

Truly asynchronous Berkeley DB access. AnyEvent::BDB transparently fuses
L<BDB> and AnyEvent together.

=item L<AnyEvent::GPSD>

A non-blocking interface to gpsd, a daemon delivering GPS information.

=item L<AnyEvent::IRC>

AnyEvent based IRC client module family (replacing the older Net::IRC3).

=item L<AnyEvent::XMPP>

AnyEvent based XMPP (Jabber protocol) module family (replacing the older
Net::XMPP2>.

=item L<AnyEvent::IGS>

A non-blocking interface to the Internet Go Server protocol (used by
L<App::IGS>).

=item L<Net::FCP>

AnyEvent-based implementation of the Freenet Client Protocol, birthplace
of AnyEvent.

=item L<Event::ExecFlow>

High level API for event-based execution flow control.

=item L<Coro>

Has special support for AnyEvent via L<Coro::AnyEvent>.

=back

=cut

package AnyEvent;

# basically a tuned-down version of common::sense
sub common_sense {
   # from common:.sense 1.0
   ${^WARNING_BITS} = "\xfc\x3f\x33\x00\x0f\xf3\xcf\xc0\xf3\xfc\x33\x00";
   # use strict vars subs - NO UTF-8, as Util.pm doesn't like this atm. (uts46data.pl)
   $^H |= 0x00000600;
}

BEGIN { AnyEvent::common_sense }

use Carp ();

our $VERSION = '5.26';
our $MODEL;

our $AUTOLOAD;
our @ISA;

our @REGISTRY;

our $VERBOSE;

BEGIN {
   require "AnyEvent/constants.pl";

   eval "sub TAINT (){" . (${^TAINT}*1) . "}";

   delete @ENV{grep /^PERL_ANYEVENT_/, keys %ENV}
      if ${^TAINT};

   $VERBOSE = $ENV{PERL_ANYEVENT_VERBOSE}*1;

}

our $MAX_SIGNAL_LATENCY = 10;

our %PROTOCOL; # (ipv4|ipv6) => (1|2), higher numbers are preferred

{
   my $idx;
   $PROTOCOL{$_} = ++$idx
      for reverse split /\s*,\s*/,
             $ENV{PERL_ANYEVENT_PROTOCOLS} || "ipv4,ipv6";
}

my @models = (
   [EV::                   => AnyEvent::Impl::EV::   , 1],
   [AnyEvent::Impl::Perl:: => AnyEvent::Impl::Perl:: , 1],
   # everything below here will not (normally) be autoprobed
   # as the pureperl backend should work everywhere
   # and is usually faster
   [Event::                => AnyEvent::Impl::Event::, 1],
   [Glib::                 => AnyEvent::Impl::Glib:: , 1], # becomes extremely slow with many watchers
   [Event::Lib::           => AnyEvent::Impl::EventLib::], # too buggy
   [Irssi::                => AnyEvent::Impl::Irssi::],    # Irssi has a bogus "Event" package
   [Tk::                   => AnyEvent::Impl::Tk::],       # crashes with many handles
   [Qt::                   => AnyEvent::Impl::Qt::],       # requires special main program
   [POE::Kernel::          => AnyEvent::Impl::POE::],      # lasciate ogni speranza
   [Wx::                   => AnyEvent::Impl::POE::],
   [Prima::                => AnyEvent::Impl::POE::],
   # IO::Async is just too broken - we would need workarounds for its
   # byzantine signal and broken child handling, among others.
   # IO::Async is rather hard to detect, as it doesn't have any
   # obvious default class.
   [IO::Async::               => AnyEvent::Impl::IOAsync::], # requires special main program
   [IO::Async::Loop::         => AnyEvent::Impl::IOAsync::], # requires special main program
   [IO::Async::Notifier::     => AnyEvent::Impl::IOAsync::], # requires special main program
   [AnyEvent::Impl::IOAsync:: => AnyEvent::Impl::IOAsync::], # requires special main program
);

our %method = map +($_ => 1),
   qw(io timer time now now_update signal child idle condvar one_event DESTROY);

our @post_detect;

sub post_detect(&) {
   my ($cb) = @_;

   push @post_detect, $cb;

   defined wantarray
      ? bless \$cb, "AnyEvent::Util::postdetect"
      : ()
}

sub AnyEvent::Util::postdetect::DESTROY {
   @post_detect = grep $_ != ${$_[0]}, @post_detect;
}

sub detect() {
   # free some memory
   *detect = sub () { $MODEL };

   local $!; # for good measure
   local $SIG{__DIE__};

   if ($ENV{PERL_ANYEVENT_MODEL} =~ /^([a-zA-Z]+)$/) {
      my $model = "AnyEvent::Impl::$1";
      if (eval "require $model") {
         $MODEL = $model;
         warn "AnyEvent: loaded model '$model' (forced by \$ENV{PERL_ANYEVENT_MODEL}), using it.\n" if $VERBOSE >= 2;
      } else {
         warn "AnyEvent: unable to load model '$model' (from \$ENV{PERL_ANYEVENT_MODEL}):\n$@" if $VERBOSE;
      }
   }

   # check for already loaded models
   unless ($MODEL) {
      for (@REGISTRY, @models) {
         my ($package, $model) = @$_;
         if (${"$package\::VERSION"} > 0) {
            if (eval "require $model") {
               $MODEL = $model;
               warn "AnyEvent: autodetected model '$model', using it.\n" if $VERBOSE >= 2;
               last;
            }
         }
      }

      unless ($MODEL) {
         # try to autoload a model
         for (@REGISTRY, @models) {
            my ($package, $model, $autoload) = @$_;
            if (
               $autoload
               and eval "require $package"
               and ${"$package\::VERSION"} > 0
               and eval "require $model"
            ) {
               $MODEL = $model;
               warn "AnyEvent: autoloaded model '$model', using it.\n" if $VERBOSE >= 2;
               last;
            }
         }

         $MODEL
           or die "No event module selected for AnyEvent and autodetect failed. Install any one of these modules: EV, Event or Glib.\n";
      }
   }

   @models = (); # free probe data

   push @{"$MODEL\::ISA"}, "AnyEvent::Base";
   unshift @ISA, $MODEL;

   # now nuke some methods that are overriden by the backend.
   # SUPER is not allowed.
   for (qw(time signal child idle)) {
      undef &{"AnyEvent::Base::$_"}
         if defined &{"$MODEL\::$_"};
   }

   require AnyEvent::Strict if $ENV{PERL_ANYEVENT_STRICT};

   (shift @post_detect)->() while @post_detect;

   *post_detect = sub(&) {
      shift->();

      undef
   };

   $MODEL
}

sub AUTOLOAD {
   (my $func = $AUTOLOAD) =~ s/.*://;

   $method{$func}
      or Carp::croak "$func: not a valid AnyEvent class method";

   detect;

   my $class = shift;
   $class->$func (@_);
}

# utility function to dup a filehandle. this is used by many backends
# to support binding more than one watcher per filehandle (they usually
# allow only one watcher per fd, so we dup it to get a different one).
sub _dupfh($$;$$) {
   my ($poll, $fh, $r, $w) = @_;

   # cygwin requires the fh mode to be matching, unix doesn't
   my ($rw, $mode) = $poll eq "r" ? ($r, "<&") : ($w, ">&");

   open my $fh2, $mode, $fh
      or die "AnyEvent->io: cannot dup() filehandle in mode '$poll': $!,";

   # we assume CLOEXEC is already set by perl in all important cases

   ($fh2, $rw)
}

=head1 SIMPLIFIED AE API

Starting with version 5.0, AnyEvent officially supports a second, much
simpler, API that is designed to reduce the calling, typing and memory
overhead by using function call syntax and a fixed number of parameters.

See the L<AE> manpage for details.

=cut

package AE;

our $VERSION = $AnyEvent::VERSION;

# fall back to the main API by default - backends and AnyEvent::Base
# implementations can overwrite these.

sub io($$$) {
   AnyEvent->io (fh => $_[0], poll => $_[1] ? "w" : "r", cb => $_[2])
}

sub timer($$$) {
   AnyEvent->timer (after => $_[0], interval => $_[1], cb => $_[2])
}

sub signal($$) {
   AnyEvent->signal (signal => $_[0], cb => $_[1])
}

sub child($$) {
   AnyEvent->child (pid => $_[0], cb => $_[1])
}

sub idle($) {
   AnyEvent->idle (cb => $_[0])
}

sub cv(;&) {
   AnyEvent->condvar (@_ ? (cb => $_[0]) : ())
}

sub now() {
   AnyEvent->now
}

sub now_update() {
   AnyEvent->now_update
}

sub time() {
   AnyEvent->time
}

package AnyEvent::Base;

# default implementations for many methods

sub time {
   eval q{ # poor man's autoloading {}
      # probe for availability of Time::HiRes
      if (eval "use Time::HiRes (); Time::HiRes::time (); 1") {
         warn "AnyEvent: using Time::HiRes for sub-second timing accuracy.\n" if $VERBOSE >= 8;
         *AE::time = \&Time::HiRes::time;
         # if (eval "use POSIX (); (POSIX::times())...
      } else {
         warn "AnyEvent: using built-in time(), WARNING, no sub-second resolution!\n" if $VERBOSE;
         *AE::time = sub (){ time }; # epic fail
      }

      *time = sub { AE::time }; # different prototypes
   };
   die if $@;

   &time
}

*now = \&time;

sub now_update { }

# default implementation for ->condvar

sub condvar {
   eval q{ # poor man's autoloading {}
      *condvar = sub {
         bless { @_ == 3 ? (_ae_cb => $_[2]) : () }, "AnyEvent::CondVar"
      };

      *AE::cv = sub (;&) {
         bless { @_ ? (_ae_cb => shift) : () }, "AnyEvent::CondVar"
      };
   };
   die if $@;

   &condvar
}

# default implementation for ->signal

our $HAVE_ASYNC_INTERRUPT;

sub _have_async_interrupt() {
   $HAVE_ASYNC_INTERRUPT = 1*(!$ENV{PERL_ANYEVENT_AVOID_ASYNC_INTERRUPT}
                              && eval "use Async::Interrupt 1.02 (); 1")
      unless defined $HAVE_ASYNC_INTERRUPT;

   $HAVE_ASYNC_INTERRUPT
}

our ($SIGPIPE_R, $SIGPIPE_W, %SIG_CB, %SIG_EV, $SIG_IO);
our (%SIG_ASY, %SIG_ASY_W);
our ($SIG_COUNT, $SIG_TW);

# install a dummy wakeup watcher to reduce signal catching latency
# used by Impls
sub _sig_add() {
   unless ($SIG_COUNT++) {
      # try to align timer on a full-second boundary, if possible
      my $NOW = AE::now;

      $SIG_TW = AE::timer
         $MAX_SIGNAL_LATENCY - ($NOW - int $NOW),
         $MAX_SIGNAL_LATENCY,
         sub { } # just for the PERL_ASYNC_CHECK
      ;
   }
}

sub _sig_del {
   undef $SIG_TW
      unless --$SIG_COUNT;
}

our $_sig_name_init; $_sig_name_init = sub {
   eval q{ # poor man's autoloading {}
      undef $_sig_name_init;

      if (_have_async_interrupt) {
         *sig2num  = \&Async::Interrupt::sig2num;
         *sig2name = \&Async::Interrupt::sig2name;
      } else {
         require Config;

         my %signame2num;
         @signame2num{ split ' ', $Config::Config{sig_name} }
                        = split ' ', $Config::Config{sig_num};

         my @signum2name;
         @signum2name[values %signame2num] = keys %signame2num;

         *sig2num = sub($) {
            $_[0] > 0 ? shift : $signame2num{+shift}
         };
         *sig2name = sub ($) {
            $_[0] > 0 ? $signum2name[+shift] : shift
         };
      }
   };
   die if $@;
};

sub sig2num ($) { &$_sig_name_init; &sig2num  }
sub sig2name($) { &$_sig_name_init; &sig2name }

sub signal {
   eval q{ # poor man's autoloading {}
      # probe for availability of Async::Interrupt 
      if (_have_async_interrupt) {
         warn "AnyEvent: using Async::Interrupt for race-free signal handling.\n" if $VERBOSE >= 8;

         $SIGPIPE_R = new Async::Interrupt::EventPipe;
         $SIG_IO = AE::io $SIGPIPE_R->fileno, 0, \&_signal_exec;

      } else {
         warn "AnyEvent: using emulated perl signal handling with latency timer.\n" if $VERBOSE >= 8;

         if (AnyEvent::WIN32) {
            require AnyEvent::Util;

            ($SIGPIPE_R, $SIGPIPE_W) = AnyEvent::Util::portable_pipe ();
            AnyEvent::Util::fh_nonblocking ($SIGPIPE_R, 1) if $SIGPIPE_R;
            AnyEvent::Util::fh_nonblocking ($SIGPIPE_W, 1) if $SIGPIPE_W; # just in case
         } else {
            pipe $SIGPIPE_R, $SIGPIPE_W;
            fcntl $SIGPIPE_R, AnyEvent::F_SETFL, AnyEvent::O_NONBLOCK if $SIGPIPE_R;
            fcntl $SIGPIPE_W, AnyEvent::F_SETFL, AnyEvent::O_NONBLOCK if $SIGPIPE_W; # just in case

            # not strictly required, as $^F is normally 2, but let's make sure...
            fcntl $SIGPIPE_R, AnyEvent::F_SETFD, AnyEvent::FD_CLOEXEC;
            fcntl $SIGPIPE_W, AnyEvent::F_SETFD, AnyEvent::FD_CLOEXEC;
         }

         $SIGPIPE_R
            or Carp::croak "AnyEvent: unable to create a signal reporting pipe: $!\n";

         $SIG_IO = AE::io $SIGPIPE_R, 0, \&_signal_exec;
      }

      *signal = $HAVE_ASYNC_INTERRUPT
         ? sub {
              my (undef, %arg) = @_;

              # async::interrupt
              my $signal = sig2num $arg{signal};
              $SIG_CB{$signal}{$arg{cb}} = $arg{cb};

              $SIG_ASY{$signal} ||= new Async::Interrupt
                 cb             => sub { undef $SIG_EV{$signal} },
                 signal         => $signal,
                 pipe           => [$SIGPIPE_R->filenos],
                 pipe_autodrain => 0,
              ;

              bless [$signal, $arg{cb}], "AnyEvent::Base::signal"
           }
         : sub {
              my (undef, %arg) = @_;

              # pure perl
              my $signal = sig2name $arg{signal};
              $SIG_CB{$signal}{$arg{cb}} = $arg{cb};

              $SIG{$signal} ||= sub {
                 local $!;
                 syswrite $SIGPIPE_W, "\x00", 1 unless %SIG_EV;
                 undef $SIG_EV{$signal};
              };

              # can't do signal processing without introducing races in pure perl,
              # so limit the signal latency.
              _sig_add;

              bless [$signal, $arg{cb}], "AnyEvent::Base::signal"
           }
      ;

      *AnyEvent::Base::signal::DESTROY = sub {
         my ($signal, $cb) = @{$_[0]};

         _sig_del;

         delete $SIG_CB{$signal}{$cb};

         $HAVE_ASYNC_INTERRUPT
            ? delete $SIG_ASY{$signal}
            : # delete doesn't work with older perls - they then
              # print weird messages, or just unconditionally exit
              # instead of getting the default action.
              undef $SIG{$signal}
            unless keys %{ $SIG_CB{$signal} };
      };

      *_signal_exec = sub {
         $HAVE_ASYNC_INTERRUPT
            ? $SIGPIPE_R->drain
            : sysread $SIGPIPE_R, (my $dummy), 9;

         while (%SIG_EV) {
            for (keys %SIG_EV) {
               delete $SIG_EV{$_};
               $_->() for values %{ $SIG_CB{$_} || {} };
            }
         }
      };
   };
   die if $@;

   &signal
}

# default implementation for ->child

our %PID_CB;
our $CHLD_W;
our $CHLD_DELAY_W;
our $WNOHANG;

# used by many Impl's
sub _emit_childstatus($$) {
   my (undef, $rpid, $rstatus) = @_;

   $_->($rpid, $rstatus)
      for values %{ $PID_CB{$rpid} || {} },
          values %{ $PID_CB{0}     || {} };
}

sub child {
   eval q{ # poor man's autoloading {}
      *_sigchld = sub {
         my $pid;

         AnyEvent->_emit_childstatus ($pid, $?)
            while ($pid = waitpid -1, $WNOHANG) > 0;
      };

      *child = sub {
         my (undef, %arg) = @_;

         defined (my $pid = $arg{pid} + 0)
            or Carp::croak "required option 'pid' is missing";

         $PID_CB{$pid}{$arg{cb}} = $arg{cb};

         # WNOHANG is almost cetrainly 1 everywhere
         $WNOHANG ||= $^O =~ /^(?:openbsd|netbsd|linux|freebsd|cygwin|MSWin32)$/
                      ? 1
                      : eval { local $SIG{__DIE__}; require POSIX; &POSIX::WNOHANG } || 1;

         unless ($CHLD_W) {
            $CHLD_W = AE::signal CHLD => \&_sigchld;
            # child could be a zombie already, so make at least one round
            &_sigchld;
         }

         bless [$pid, $arg{cb}], "AnyEvent::Base::child"
      };

      *AnyEvent::Base::child::DESTROY = sub {
         my ($pid, $cb) = @{$_[0]};

         delete $PID_CB{$pid}{$cb};
         delete $PID_CB{$pid} unless keys %{ $PID_CB{$pid} };

         undef $CHLD_W unless keys %PID_CB;
      };
   };
   die if $@;

   &child
}

# idle emulation is done by simply using a timer, regardless
# of whether the process is idle or not, and not letting
# the callback use more than 50% of the time.
sub idle {
   eval q{ # poor man's autoloading {}
      *idle = sub {
         my (undef, %arg) = @_;

         my ($cb, $w, $rcb) = $arg{cb};

         $rcb = sub {
            if ($cb) {
               $w = _time;
               &$cb;
               $w = _time - $w;

               # never use more then 50% of the time for the idle watcher,
               # within some limits
               $w = 0.0001 if $w < 0.0001;
               $w = 5      if $w > 5;

               $w = AE::timer $w, 0, $rcb;
            } else {
               # clean up...
               undef $w;
               undef $rcb;
            }
         };

         $w = AE::timer 0.05, 0, $rcb;

         bless \\$cb, "AnyEvent::Base::idle"
      };

      *AnyEvent::Base::idle::DESTROY = sub {
         undef $${$_[0]};
      };
   };
   die if $@;

   &idle
}

package AnyEvent::CondVar;

our @ISA = AnyEvent::CondVar::Base::;

package AnyEvent::CondVar::Base;

#use overload
#   '&{}'    => sub { my $self = shift; sub { $self->send (@_) } },
#   fallback => 1;

# save 300+ kilobytes by dirtily hardcoding overloading
${"AnyEvent::CondVar::Base::OVERLOAD"}{dummy}++; # Register with magic by touching.
*{'AnyEvent::CondVar::Base::()'}   = sub { }; # "Make it findable via fetchmethod."
*{'AnyEvent::CondVar::Base::(&{}'} = sub { my $self = shift; sub { $self->send (@_) } }; # &{}
${'AnyEvent::CondVar::Base::()'}   = 1; # fallback

our $WAITING;

sub _send {
   # nop
}

sub send {
   my $cv = shift;
   $cv->{_ae_sent} = [@_];
   (delete $cv->{_ae_cb})->($cv) if $cv->{_ae_cb};
   $cv->_send;
}

sub croak {
   $_[0]{_ae_croak} = $_[1];
   $_[0]->send;
}

sub ready {
   $_[0]{_ae_sent}
}

sub _wait {
   $WAITING
      and !$_[0]{_ae_sent}
      and Carp::croak "AnyEvent::CondVar: recursive blocking wait detected";

   local $WAITING = 1;
   AnyEvent->one_event while !$_[0]{_ae_sent};
}

sub recv {
   $_[0]->_wait;

   Carp::croak $_[0]{_ae_croak} if $_[0]{_ae_croak};
   wantarray ? @{ $_[0]{_ae_sent} } : $_[0]{_ae_sent}[0]
}

sub cb {
   my $cv = shift;

   @_
      and $cv->{_ae_cb} = shift
      and $cv->{_ae_sent}
      and (delete $cv->{_ae_cb})->($cv);

   $cv->{_ae_cb}
}

sub begin {
   ++$_[0]{_ae_counter};
   $_[0]{_ae_end_cb} = $_[1] if @_ > 1;
}

sub end {
   return if --$_[0]{_ae_counter};
   &{ $_[0]{_ae_end_cb} || sub { $_[0]->send } };
}

# undocumented/compatibility with pre-3.4
*broadcast = \&send;
*wait      = \&_wait;

=head1 ERROR AND EXCEPTION HANDLING

In general, AnyEvent does not do any error handling - it relies on the
caller to do that if required. The L<AnyEvent::Strict> module (see also
the C<PERL_ANYEVENT_STRICT> environment variable, below) provides strict
checking of all AnyEvent methods, however, which is highly useful during
development.

As for exception handling (i.e. runtime errors and exceptions thrown while
executing a callback), this is not only highly event-loop specific, but
also not in any way wrapped by this module, as this is the job of the main
program.

The pure perl event loop simply re-throws the exception (usually
within C<< condvar->recv >>), the L<Event> and L<EV> modules call C<<
$Event/EV::DIED->() >>, L<Glib> uses C<< install_exception_handler >> and
so on.

=head1 ENVIRONMENT VARIABLES

The following environment variables are used by this module or its
submodules.

Note that AnyEvent will remove I<all> environment variables starting with
C<PERL_ANYEVENT_> from C<%ENV> when it is loaded while taint mode is
enabled.

=over 4

=item C<PERL_ANYEVENT_VERBOSE>

By default, AnyEvent will be completely silent except in fatal
conditions. You can set this environment variable to make AnyEvent more
talkative.

When set to C<1> or higher, causes AnyEvent to warn about unexpected
conditions, such as not being able to load the event model specified by
C<PERL_ANYEVENT_MODEL>.

When set to C<2> or higher, cause AnyEvent to report to STDERR which event
model it chooses.

When set to C<8> or higher, then AnyEvent will report extra information on
which optional modules it loads and how it implements certain features.

=item C<PERL_ANYEVENT_STRICT>

AnyEvent does not do much argument checking by default, as thorough
argument checking is very costly. Setting this variable to a true value
will cause AnyEvent to load C<AnyEvent::Strict> and then to thoroughly
check the arguments passed to most method calls. If it finds any problems,
it will croak.

In other words, enables "strict" mode.

Unlike C<use strict> (or it's modern cousin, C<< use L<common::sense>
>>, it is definitely recommended to keep it off in production. Keeping
C<PERL_ANYEVENT_STRICT=1> in your environment while developing programs
can be very useful, however.

=item C<PERL_ANYEVENT_MODEL>

This can be used to specify the event model to be used by AnyEvent, before
auto detection and -probing kicks in. It must be a string consisting
entirely of ASCII letters. The string C<AnyEvent::Impl::> gets prepended
and the resulting module name is loaded and if the load was successful,
used as event model. If it fails to load AnyEvent will proceed with
auto detection and -probing.

This functionality might change in future versions.

For example, to force the pure perl model (L<AnyEvent::Impl::Perl>) you
could start your program like this:

   PERL_ANYEVENT_MODEL=Perl perl ...

=item C<PERL_ANYEVENT_PROTOCOLS>

Used by both L<AnyEvent::DNS> and L<AnyEvent::Socket> to determine preferences
for IPv4 or IPv6. The default is unspecified (and might change, or be the result
of auto probing).

Must be set to a comma-separated list of protocols or address families,
current supported: C<ipv4> and C<ipv6>. Only protocols mentioned will be
used, and preference will be given to protocols mentioned earlier in the
list.

This variable can effectively be used for denial-of-service attacks
against local programs (e.g. when setuid), although the impact is likely
small, as the program has to handle conenction and other failures anyways.

Examples: C<PERL_ANYEVENT_PROTOCOLS=ipv4,ipv6> - prefer IPv4 over IPv6,
but support both and try to use both.  C<PERL_ANYEVENT_PROTOCOLS=ipv4>
- only support IPv4, never try to resolve or contact IPv6
addresses. C<PERL_ANYEVENT_PROTOCOLS=ipv6,ipv4> support either IPv4 or
IPv6, but prefer IPv6 over IPv4.

=item C<PERL_ANYEVENT_EDNS0>

Used by L<AnyEvent::DNS> to decide whether to use the EDNS0 extension
for DNS. This extension is generally useful to reduce DNS traffic, but
some (broken) firewalls drop such DNS packets, which is why it is off by
default.

Setting this variable to C<1> will cause L<AnyEvent::DNS> to announce
EDNS0 in its DNS requests.

=item C<PERL_ANYEVENT_MAX_FORKS>

The maximum number of child processes that C<AnyEvent::Util::fork_call>
will create in parallel.

=item C<PERL_ANYEVENT_MAX_OUTSTANDING_DNS>

The default value for the C<max_outstanding> parameter for the default DNS
resolver - this is the maximum number of parallel DNS requests that are
sent to the DNS server.

=item C<PERL_ANYEVENT_RESOLV_CONF>

The file to use instead of F</etc/resolv.conf> (or OS-specific
configuration) in the default resolver. When set to the empty string, no
default config will be used.

=item C<PERL_ANYEVENT_CA_FILE>, C<PERL_ANYEVENT_CA_PATH>.

When neither C<ca_file> nor C<ca_path> was specified during
L<AnyEvent::TLS> context creation, and either of these environment
variables exist, they will be used to specify CA certificate locations
instead of a system-dependent default.

=item C<PERL_ANYEVENT_AVOID_GUARD> and C<PERL_ANYEVENT_AVOID_ASYNC_INTERRUPT>

When these are set to C<1>, then the respective modules are not
loaded. Mostly good for testing AnyEvent itself.

=back

=head1 SUPPLYING YOUR OWN EVENT MODEL INTERFACE

This is an advanced topic that you do not normally need to use AnyEvent in
a module. This section is only of use to event loop authors who want to
provide AnyEvent compatibility.

If you need to support another event library which isn't directly
supported by AnyEvent, you can supply your own interface to it by
pushing, before the first watcher gets created, the package name of
the event module and the package name of the interface to use onto
C<@AnyEvent::REGISTRY>. You can do that before and even without loading
AnyEvent, so it is reasonably cheap.

Example:

   push @AnyEvent::REGISTRY, [urxvt => urxvt::anyevent::];

This tells AnyEvent to (literally) use the C<urxvt::anyevent::>
package/class when it finds the C<urxvt> package/module is already loaded.

When AnyEvent is loaded and asked to find a suitable event model, it
will first check for the presence of urxvt by trying to C<use> the
C<urxvt::anyevent> module.

The class should provide implementations for all watcher types. See
L<AnyEvent::Impl::EV> (source code), L<AnyEvent::Impl::Glib> (Source code)
and so on for actual examples. Use C<perldoc -m AnyEvent::Impl::Glib> to
see the sources.

If you don't provide C<signal> and C<child> watchers than AnyEvent will
provide suitable (hopefully) replacements.

The above example isn't fictitious, the I<rxvt-unicode> (a.k.a. urxvt)
terminal emulator uses the above line as-is. An interface isn't included
in AnyEvent because it doesn't make sense outside the embedded interpreter
inside I<rxvt-unicode>, and it is updated and maintained as part of the
I<rxvt-unicode> distribution.

I<rxvt-unicode> also cheats a bit by not providing blocking access to
condition variables: code blocking while waiting for a condition will
C<die>. This still works with most modules/usages, and blocking calls must
not be done in an interactive application, so it makes sense.

=head1 EXAMPLE PROGRAM

The following program uses an I/O watcher to read data from STDIN, a timer
to display a message once per second, and a condition variable to quit the
program when the user enters quit:

   use AnyEvent;

   my $cv = AnyEvent->condvar;

   my $io_watcher = AnyEvent->io (
      fh   => \*STDIN,
      poll => 'r',
      cb   => sub {
         warn "io event <$_[0]>\n";   # will always output <r>
         chomp (my $input = <STDIN>); # read a line
         warn "read: $input\n";       # output what has been read
         $cv->send if $input =~ /^q/i; # quit program if /^q/i
      },
   );

   my $time_watcher = AnyEvent->timer (after => 1, interval => 1, cb => sub {
      warn "timeout\n"; # print 'timeout' at most every second
   });

   $cv->recv; # wait until user enters /^q/i

=head1 REAL-WORLD EXAMPLE

Consider the L<Net::FCP> module. It features (among others) the following
API calls, which are to freenet what HTTP GET requests are to http:

   my $data = $fcp->client_get ($url); # blocks

   my $transaction = $fcp->txn_client_get ($url); # does not block
   $transaction->cb ( sub { ... } ); # set optional result callback
   my $data = $transaction->result; # possibly blocks

The C<client_get> method works like C<LWP::Simple::get>: it requests the
given URL and waits till the data has arrived. It is defined to be:

   sub client_get { $_[0]->txn_client_get ($_[1])->result }

And in fact is automatically generated. This is the blocking API of
L<Net::FCP>, and it works as simple as in any other, similar, module.

More complicated is C<txn_client_get>: It only creates a transaction
(completion, result, ...) object and initiates the transaction.

   my $txn = bless { }, Net::FCP::Txn::;

It also creates a condition variable that is used to signal the completion
of the request:

   $txn->{finished} = AnyAvent->condvar;

It then creates a socket in non-blocking mode.

   socket $txn->{fh}, ...;
   fcntl $txn->{fh}, F_SETFL, O_NONBLOCK;
   connect $txn->{fh}, ...
      and !$!{EWOULDBLOCK}
      and !$!{EINPROGRESS}
      and Carp::croak "unable to connect: $!\n";

Then it creates a write-watcher which gets called whenever an error occurs
or the connection succeeds:

   $txn->{w} = AnyEvent->io (fh => $txn->{fh}, poll => 'w', cb => sub { $txn->fh_ready_w });

And returns this transaction object. The C<fh_ready_w> callback gets
called as soon as the event loop detects that the socket is ready for
writing.

The C<fh_ready_w> method makes the socket blocking again, writes the
request data and replaces the watcher by a read watcher (waiting for reply
data). The actual code is more complicated, but that doesn't matter for
this example:

   fcntl $txn->{fh}, F_SETFL, 0;
   syswrite $txn->{fh}, $txn->{request}
      or die "connection or write error";
   $txn->{w} = AnyEvent->io (fh => $txn->{fh}, poll => 'r', cb => sub { $txn->fh_ready_r });

Again, C<fh_ready_r> waits till all data has arrived, and then stores the
result and signals any possible waiters that the request has finished:

   sysread $txn->{fh}, $txn->{buf}, length $txn->{$buf};

   if (end-of-file or data complete) {
     $txn->{result} = $txn->{buf};
     $txn->{finished}->send;
     $txb->{cb}->($txn) of $txn->{cb}; # also call callback
   }

The C<result> method, finally, just waits for the finished signal (if the
request was already finished, it doesn't wait, of course, and returns the
data:

   $txn->{finished}->recv;
   return $txn->{result};

The actual code goes further and collects all errors (C<die>s, exceptions)
that occurred during request processing. The C<result> method detects
whether an exception as thrown (it is stored inside the $txn object)
and just throws the exception, which means connection errors and other
problems get reported to the code that tries to use the result, not in a
random callback.

All of this enables the following usage styles:

1. Blocking:

   my $data = $fcp->client_get ($url);

2. Blocking, but running in parallel:

   my @datas = map $_->result,
                  map $fcp->txn_client_get ($_),
                     @urls;

Both blocking examples work without the module user having to know
anything about events.

3a. Event-based in a main program, using any supported event module:

   use EV;

   $fcp->txn_client_get ($url)->cb (sub {
      my $txn = shift;
      my $data = $txn->result;
      ...
   });

   EV::loop;

3b. The module user could use AnyEvent, too:

   use AnyEvent;

   my $quit = AnyEvent->condvar;

   $fcp->txn_client_get ($url)->cb (sub {
      ...
      $quit->send;
   });

   $quit->recv;


=head1 BENCHMARKS

To give you an idea of the performance and overheads that AnyEvent adds
over the event loops themselves and to give you an impression of the speed
of various event loops I prepared some benchmarks.

=head2 BENCHMARKING ANYEVENT OVERHEAD

Here is a benchmark of various supported event models used natively and
through AnyEvent. The benchmark creates a lot of timers (with a zero
timeout) and I/O watchers (watching STDOUT, a pty, to become writable,
which it is), lets them fire exactly once and destroys them again.

Source code for this benchmark is found as F<eg/bench> in the AnyEvent
distribution. It uses the L<AE> interface, which makes a real difference
for the EV and Perl backends only.

=head3 Explanation of the columns

I<watcher> is the number of event watchers created/destroyed. Since
different event models feature vastly different performances, each event
loop was given a number of watchers so that overall runtime is acceptable
and similar between tested event loop (and keep them from crashing): Glib
would probably take thousands of years if asked to process the same number
of watchers as EV in this benchmark.

I<bytes> is the number of bytes (as measured by the resident set size,
RSS) consumed by each watcher. This method of measuring captures both C
and Perl-based overheads.

I<create> is the time, in microseconds (millionths of seconds), that it
takes to create a single watcher. The callback is a closure shared between
all watchers, to avoid adding memory overhead. That means closure creation
and memory usage is not included in the figures.

I<invoke> is the time, in microseconds, used to invoke a simple
callback. The callback simply counts down a Perl variable and after it was
invoked "watcher" times, it would C<< ->send >> a condvar once to
signal the end of this phase.

I<destroy> is the time, in microseconds, that it takes to destroy a single
watcher.

=head3 Results

          name watchers bytes create invoke destroy comment
         EV/EV   100000   223   0.47   0.43    0.27 EV native interface
        EV/Any   100000   223   0.48   0.42    0.26 EV + AnyEvent watchers
  Coro::EV/Any   100000   223   0.47   0.42    0.26 coroutines + Coro::Signal
      Perl/Any   100000   431   2.70   0.74    0.92 pure perl implementation
   Event/Event    16000   516  31.16  31.84    0.82 Event native interface
     Event/Any    16000  1203  42.61  34.79    1.80 Event + AnyEvent watchers
   IOAsync/Any    16000  1911  41.92  27.45   16.81 via IO::Async::Loop::IO_Poll
   IOAsync/Any    16000  1726  40.69  26.37   15.25 via IO::Async::Loop::Epoll
      Glib/Any    16000  1118  89.00  12.57   51.17 quadratic behaviour
        Tk/Any     2000  1346  20.96  10.75    8.00 SEGV with >> 2000 watchers
       POE/Any     2000  6951 108.97 795.32   14.24 via POE::Loop::Event
       POE/Any     2000  6648  94.79 774.40  575.51 via POE::Loop::Select

=head3 Discussion

The benchmark does I<not> measure scalability of the event loop very
well. For example, a select-based event loop (such as the pure perl one)
can never compete with an event loop that uses epoll when the number of
file descriptors grows high. In this benchmark, all events become ready at
the same time, so select/poll-based implementations get an unnatural speed
boost.

Also, note that the number of watchers usually has a nonlinear effect on
overall speed, that is, creating twice as many watchers doesn't take twice
the time - usually it takes longer. This puts event loops tested with a
higher number of watchers at a disadvantage.

To put the range of results into perspective, consider that on the
benchmark machine, handling an event takes roughly 1600 CPU cycles with
EV, 3100 CPU cycles with AnyEvent's pure perl loop and almost 3000000 CPU
cycles with POE.

C<EV> is the sole leader regarding speed and memory use, which are both
maximal/minimal, respectively. When using the L<AE> API there is zero
overhead (when going through the AnyEvent API create is about 5-6 times
slower, with other times being equal, so still uses far less memory than
any other event loop and is still faster than Event natively).

The pure perl implementation is hit in a few sweet spots (both the
constant timeout and the use of a single fd hit optimisations in the perl
interpreter and the backend itself). Nevertheless this shows that it
adds very little overhead in itself. Like any select-based backend its
performance becomes really bad with lots of file descriptors (and few of
them active), of course, but this was not subject of this benchmark.

The C<Event> module has a relatively high setup and callback invocation
cost, but overall scores in on the third place.

C<IO::Async> performs admirably well, about on par with C<Event>, even
when using its pure perl backend.

C<Glib>'s memory usage is quite a bit higher, but it features a
faster callback invocation and overall ends up in the same class as
C<Event>. However, Glib scales extremely badly, doubling the number of
watchers increases the processing time by more than a factor of four,
making it completely unusable when using larger numbers of watchers
(note that only a single file descriptor was used in the benchmark, so
inefficiencies of C<poll> do not account for this).

The C<Tk> adaptor works relatively well. The fact that it crashes with
more than 2000 watchers is a big setback, however, as correctness takes
precedence over speed. Nevertheless, its performance is surprising, as the
file descriptor is dup()ed for each watcher. This shows that the dup()
employed by some adaptors is not a big performance issue (it does incur a
hidden memory cost inside the kernel which is not reflected in the figures
above).

C<POE>, regardless of underlying event loop (whether using its pure perl
select-based backend or the Event module, the POE-EV backend couldn't
be tested because it wasn't working) shows abysmal performance and
memory usage with AnyEvent: Watchers use almost 30 times as much memory
as EV watchers, and 10 times as much memory as Event (the high memory
requirements are caused by requiring a session for each watcher). Watcher
invocation speed is almost 900 times slower than with AnyEvent's pure perl
implementation.

The design of the POE adaptor class in AnyEvent can not really account
for the performance issues, though, as session creation overhead is
small compared to execution of the state machine, which is coded pretty
optimally within L<AnyEvent::Impl::POE> (and while everybody agrees that
using multiple sessions is not a good approach, especially regarding
memory usage, even the author of POE could not come up with a faster
design).

=head3 Summary

=over 4

=item * Using EV through AnyEvent is faster than any other event loop
(even when used without AnyEvent), but most event loops have acceptable
performance with or without AnyEvent.

=item * The overhead AnyEvent adds is usually much smaller than the overhead of
the actual event loop, only with extremely fast event loops such as EV
adds AnyEvent significant overhead.

=item * You should avoid POE like the plague if you want performance or
reasonable memory usage.

=back

=head2 BENCHMARKING THE LARGE SERVER CASE

This benchmark actually benchmarks the event loop itself. It works by
creating a number of "servers": each server consists of a socket pair, a
timeout watcher that gets reset on activity (but never fires), and an I/O
watcher waiting for input on one side of the socket. Each time the socket
watcher reads a byte it will write that byte to a random other "server".

The effect is that there will be a lot of I/O watchers, only part of which
are active at any one point (so there is a constant number of active
fds for each loop iteration, but which fds these are is random). The
timeout is reset each time something is read because that reflects how
most timeouts work (and puts extra pressure on the event loops).

In this benchmark, we use 10000 socket pairs (20000 sockets), of which 100
(1%) are active. This mirrors the activity of large servers with many
connections, most of which are idle at any one point in time.

Source code for this benchmark is found as F<eg/bench2> in the AnyEvent
distribution. It uses the L<AE> interface, which makes a real difference
for the EV and Perl backends only.

=head3 Explanation of the columns

I<sockets> is the number of sockets, and twice the number of "servers" (as
each server has a read and write socket end).

I<create> is the time it takes to create a socket pair (which is
nontrivial) and two watchers: an I/O watcher and a timeout watcher.

I<request>, the most important value, is the time it takes to handle a
single "request", that is, reading the token from the pipe and forwarding
it to another server. This includes deleting the old timeout and creating
a new one that moves the timeout into the future.

=head3 Results

     name sockets create  request 
       EV   20000  62.66     7.99 
     Perl   20000  68.32    32.64 
  IOAsync   20000 174.06   101.15 epoll
  IOAsync   20000 174.67   610.84 poll
    Event   20000 202.69   242.91 
     Glib   20000 557.01  1689.52 
      POE   20000 341.54 12086.32 uses POE::Loop::Event

=head3 Discussion

This benchmark I<does> measure scalability and overall performance of the
particular event loop.

EV is again fastest. Since it is using epoll on my system, the setup time
is relatively high, though.

Perl surprisingly comes second. It is much faster than the C-based event
loops Event and Glib.

IO::Async performs very well when using its epoll backend, and still quite
good compared to Glib when using its pure perl backend.

Event suffers from high setup time as well (look at its code and you will
understand why). Callback invocation also has a high overhead compared to
the C<< $_->() for .. >>-style loop that the Perl event loop uses. Event
uses select or poll in basically all documented configurations.

Glib is hit hard by its quadratic behaviour w.r.t. many watchers. It
clearly fails to perform with many filehandles or in busy servers.

POE is still completely out of the picture, taking over 1000 times as long
as EV, and over 100 times as long as the Perl implementation, even though
it uses a C-based event loop in this case.

=head3 Summary

=over 4

=item * The pure perl implementation performs extremely well.

=item * Avoid Glib or POE in large projects where performance matters.

=back

=head2 BENCHMARKING SMALL SERVERS

While event loops should scale (and select-based ones do not...) even to
large servers, most programs we (or I :) actually write have only a few
I/O watchers.

In this benchmark, I use the same benchmark program as in the large server
case, but it uses only eight "servers", of which three are active at any
one time. This should reflect performance for a small server relatively
well.

The columns are identical to the previous table.

=head3 Results

    name sockets create request 
      EV      16  20.00    6.54 
    Perl      16  25.75   12.62 
   Event      16  81.27   35.86 
    Glib      16  32.63   15.48 
     POE      16 261.87  276.28 uses POE::Loop::Event

=head3 Discussion

The benchmark tries to test the performance of a typical small
server. While knowing how various event loops perform is interesting, keep
in mind that their overhead in this case is usually not as important, due
to the small absolute number of watchers (that is, you need efficiency and
speed most when you have lots of watchers, not when you only have a few of
them).

EV is again fastest.

Perl again comes second. It is noticeably faster than the C-based event
loops Event and Glib, although the difference is too small to really
matter.

POE also performs much better in this case, but is is still far behind the
others.

=head3 Summary

=over 4

=item * C-based event loops perform very well with small number of
watchers, as the management overhead dominates.

=back

=head2 THE IO::Lambda BENCHMARK

Recently I was told about the benchmark in the IO::Lambda manpage, which
could be misinterpreted to make AnyEvent look bad. In fact, the benchmark
simply compares IO::Lambda with POE, and IO::Lambda looks better (which
shouldn't come as a surprise to anybody). As such, the benchmark is
fine, and mostly shows that the AnyEvent backend from IO::Lambda isn't
very optimal. But how would AnyEvent compare when used without the extra
baggage? To explore this, I wrote the equivalent benchmark for AnyEvent.

The benchmark itself creates an echo-server, and then, for 500 times,
connects to the echo server, sends a line, waits for the reply, and then
creates the next connection. This is a rather bad benchmark, as it doesn't
test the efficiency of the framework or much non-blocking I/O, but it is a
benchmark nevertheless.

   name                    runtime
   Lambda/select           0.330 sec
      + optimized          0.122 sec
   Lambda/AnyEvent         0.327 sec
      + optimized          0.138 sec
   Raw sockets/select      0.077 sec
   POE/select, components  0.662 sec
   POE/select, raw sockets 0.226 sec
   POE/select, optimized   0.404 sec

   AnyEvent/select/nb      0.085 sec
   AnyEvent/EV/nb          0.068 sec
      +state machine       0.134 sec

The benchmark is also a bit unfair (my fault): the IO::Lambda/POE
benchmarks actually make blocking connects and use 100% blocking I/O,
defeating the purpose of an event-based solution. All of the newly
written AnyEvent benchmarks use 100% non-blocking connects (using
AnyEvent::Socket::tcp_connect and the asynchronous pure perl DNS
resolver), so AnyEvent is at a disadvantage here, as non-blocking connects
generally require a lot more bookkeeping and event handling than blocking
connects (which involve a single syscall only).

The last AnyEvent benchmark additionally uses L<AnyEvent::Handle>, which
offers similar expressive power as POE and IO::Lambda, using conventional
Perl syntax. This means that both the echo server and the client are 100%
non-blocking, further placing it at a disadvantage.

As you can see, the AnyEvent + EV combination even beats the
hand-optimised "raw sockets benchmark", while AnyEvent + its pure perl
backend easily beats IO::Lambda and POE.

And even the 100% non-blocking version written using the high-level (and
slow :) L<AnyEvent::Handle> abstraction beats both POE and IO::Lambda
higher level ("unoptimised") abstractions by a large margin, even though
it does all of DNS, tcp-connect and socket I/O in a non-blocking way.

The two AnyEvent benchmarks programs can be found as F<eg/ae0.pl> and
F<eg/ae2.pl> in the AnyEvent distribution, the remaining benchmarks are
part of the IO::Lambda distribution and were used without any changes.


=head1 SIGNALS

AnyEvent currently installs handlers for these signals:

=over 4

=item SIGCHLD

A handler for C<SIGCHLD> is installed by AnyEvent's child watcher
emulation for event loops that do not support them natively. Also, some
event loops install a similar handler.

Additionally, when AnyEvent is loaded and SIGCHLD is set to IGNORE, then
AnyEvent will reset it to default, to avoid losing child exit statuses.

=item SIGPIPE

A no-op handler is installed for C<SIGPIPE> when C<$SIG{PIPE}> is C<undef>
when AnyEvent gets loaded.

The rationale for this is that AnyEvent users usually do not really depend
on SIGPIPE delivery (which is purely an optimisation for shell use, or
badly-written programs), but C<SIGPIPE> can cause spurious and rare
program exits as a lot of people do not expect C<SIGPIPE> when writing to
some random socket.

The rationale for installing a no-op handler as opposed to ignoring it is
that this way, the handler will be restored to defaults on exec.

Feel free to install your own handler, or reset it to defaults.

=back

=cut

undef $SIG{CHLD}
   if $SIG{CHLD} eq 'IGNORE';

$SIG{PIPE} = sub { }
   unless defined $SIG{PIPE};

=head1 RECOMMENDED/OPTIONAL MODULES

One of AnyEvent's main goals is to be 100% Pure-Perl(tm): only perl (and
it's built-in modules) are required to use it.

That does not mean that AnyEvent won't take advantage of some additional
modules if they are installed.

This section explains which additional modules will be used, and how they
affect AnyEvent's operation.

=over 4

=item L<Async::Interrupt>

This slightly arcane module is used to implement fast signal handling: To
my knowledge, there is no way to do completely race-free and quick
signal handling in pure perl. To ensure that signals still get
delivered, AnyEvent will start an interval timer to wake up perl (and
catch the signals) with some delay (default is 10 seconds, look for
C<$AnyEvent::MAX_SIGNAL_LATENCY>).

If this module is available, then it will be used to implement signal
catching, which means that signals will not be delayed, and the event loop
will not be interrupted regularly, which is more efficient (and good for
battery life on laptops).

This affects not just the pure-perl event loop, but also other event loops
that have no signal handling on their own (e.g. Glib, Tk, Qt).

Some event loops (POE, Event, Event::Lib) offer signal watchers natively,
and either employ their own workarounds (POE) or use AnyEvent's workaround
(using C<$AnyEvent::MAX_SIGNAL_LATENCY>). Installing L<Async::Interrupt>
does nothing for those backends.

=item L<EV>

This module isn't really "optional", as it is simply one of the backend
event loops that AnyEvent can use. However, it is simply the best event
loop available in terms of features, speed and stability: It supports
the AnyEvent API optimally, implements all the watcher types in XS, does
automatic timer adjustments even when no monotonic clock is available,
can take avdantage of advanced kernel interfaces such as C<epoll> and
C<kqueue>, and is the fastest backend I<by far>. You can even embed
L<Glib>/L<Gtk2> in it (or vice versa, see L<EV::Glib> and L<Glib::EV>).

If you only use backends that rely on another event loop (e.g. C<Tk>),
then this module will do nothing for you.

=item L<Guard>

The guard module, when used, will be used to implement
C<AnyEvent::Util::guard>. This speeds up guards considerably (and uses a
lot less memory), but otherwise doesn't affect guard operation much. It is
purely used for performance.

=item L<JSON> and L<JSON::XS>

One of these modules is required when you want to read or write JSON data
via L<AnyEvent::Handle>. L<JSON> is also written in pure-perl, but can take
advantage of the ultra-high-speed L<JSON::XS> module when it is installed.

=item L<Net::SSLeay>

Implementing TLS/SSL in Perl is certainly interesting, but not very
worthwhile: If this module is installed, then L<AnyEvent::Handle> (with
the help of L<AnyEvent::TLS>), gains the ability to do TLS/SSL.

=item L<Time::HiRes>

This module is part of perl since release 5.008. It will be used when the
chosen event library does not come with a timing source on it's own. The
pure-perl event loop (L<AnyEvent::Impl::Perl>) will additionally use it to
try to use a monotonic clock for timing stability.

=back


=head1 FORK

Most event libraries are not fork-safe. The ones who are usually are
because they rely on inefficient but fork-safe C<select> or C<poll> calls
- higher performance APIs such as BSD's kqueue or the dreaded Linux epoll
are usually badly thought-out hacks that are incompatible with fork in
one way or another. Only L<EV> is fully fork-aware and ensures that you
continue event-processing in both parent and child (or both, if you know
what you are doing).

This means that, in general, you cannot fork and do event processing in
the child if the event library was initialised before the fork (which
usually happens when the first AnyEvent watcher is created, or the library
is loaded).

If you have to fork, you must either do so I<before> creating your first
watcher OR you must not use AnyEvent at all in the child OR you must do
something completely out of the scope of AnyEvent.

The problem of doing event processing in the parent I<and> the child
is much more complicated: even for backends that I<are> fork-aware or
fork-safe, their behaviour is not usually what you want: fork clones all
watchers, that means all timers, I/O watchers etc. are active in both
parent and child, which is almost never what you want. USing C<exec>
to start worker children from some kind of manage rprocess is usually
preferred, because it is much easier and cleaner, at the expense of having
to have another binary.


=head1 SECURITY CONSIDERATIONS

AnyEvent can be forced to load any event model via
$ENV{PERL_ANYEVENT_MODEL}. While this cannot (to my knowledge) be used to
execute arbitrary code or directly gain access, it can easily be used to
make the program hang or malfunction in subtle ways, as AnyEvent watchers
will not be active when the program uses a different event model than
specified in the variable.

You can make AnyEvent completely ignore this variable by deleting it
before the first watcher gets created, e.g. with a C<BEGIN> block:

   BEGIN { delete $ENV{PERL_ANYEVENT_MODEL} }
  
   use AnyEvent;

Similar considerations apply to $ENV{PERL_ANYEVENT_VERBOSE}, as that can
be used to probe what backend is used and gain other information (which is
probably even less useful to an attacker than PERL_ANYEVENT_MODEL), and
$ENV{PERL_ANYEVENT_STRICT}.

Note that AnyEvent will remove I<all> environment variables starting with
C<PERL_ANYEVENT_> from C<%ENV> when it is loaded while taint mode is
enabled.


=head1 BUGS

Perl 5.8 has numerous memleaks that sometimes hit this module and are hard
to work around. If you suffer from memleaks, first upgrade to Perl 5.10
and check wether the leaks still show up. (Perl 5.10.0 has other annoying
memleaks, such as leaking on C<map> and C<grep> but it is usually not as
pronounced).


=head1 SEE ALSO

Utility functions: L<AnyEvent::Util>.

Event modules: L<EV>, L<EV::Glib>, L<Glib::EV>, L<Event>, L<Glib::Event>,
L<Glib>, L<Tk>, L<Event::Lib>, L<Qt>, L<POE>.

Implementations: L<AnyEvent::Impl::EV>, L<AnyEvent::Impl::Event>,
L<AnyEvent::Impl::Glib>, L<AnyEvent::Impl::Tk>, L<AnyEvent::Impl::Perl>,
L<AnyEvent::Impl::EventLib>, L<AnyEvent::Impl::Qt>,
L<AnyEvent::Impl::POE>, L<AnyEvent::Impl::IOAsync>, L<Anyevent::Impl::Irssi>.

Non-blocking file handles, sockets, TCP clients and
servers: L<AnyEvent::Handle>, L<AnyEvent::Socket>, L<AnyEvent::TLS>.

Asynchronous DNS: L<AnyEvent::DNS>.

Coroutine support: L<Coro>, L<Coro::AnyEvent>, L<Coro::EV>,
L<Coro::Event>,

Nontrivial usage examples: L<AnyEvent::GPSD>, L<AnyEvent::XMPP>,
L<AnyEvent::HTTP>.


=head1 AUTHOR

   Marc Lehmann <schmorp@schmorp.de>
   http://home.schmorp.de/

=cut

1

