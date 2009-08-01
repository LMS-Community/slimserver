=head1 NAME

AnyEvent::AIO - truly asynchronous file and directory I/O

=head1 SYNOPSIS

   use AnyEvent::AIO;
   use IO::AIO;

   # can now use any of the aio requests your IO::AIO module supports
   # as long as you use an event loop supported by AnyEvent.

=head1 DESCRIPTION

This module is an L<AnyEvent> user, you need to make sure that you use and
run a supported event loop.

Loading this module will install the necessary magic to seamlessly
integrate L<IO::AIO> into L<AnyEvent>, i.e. you no longer need to concern
yourself with calling C<IO::AIO::poll_cb> or any of that stuff (you still
can, but this module will do it in case you don't).

The AnyEvent watcher can be disabled by executing C<undef
$AnyEvent::AIO::WATCHER>. Please notify the author of when and why you
think this was necessary.

=cut

package AnyEvent::AIO;

use strict;
no warnings;

use AnyEvent ();
use IO::AIO ();

use base Exporter::;

our $VERSION = '1.1';
our $WATCHER;

my $guard = AnyEvent::post_detect {
   $WATCHER = AnyEvent->io (fh => IO::AIO::poll_fileno, poll => 'r', cb => \&IO::AIO::poll_cb);
};
$WATCHER ||= $guard;

IO::AIO::_on_next_submit \&AnyEvent::detect;

=head1 SEE ALSO

L<AnyEvent>, L<Coro::AIO> (for a more natural syntax).

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

1
