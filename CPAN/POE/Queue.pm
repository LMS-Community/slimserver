# $Id: Queue.pm 9097 2006-08-22 18:32:53Z dsully $

package POE::Queue;

use vars qw($VERSION);
$VERSION = do {my($r)=(q$Revision: 1903 $=~/(\d+)/);sprintf"1.%04d",$r};

use Carp qw(croak);

sub new {
  my $type = shift;
  croak "$type is a virtual base class and not meant to be used directly";
}

1;

__END__

=head1 NAME

POE::Queue - documentation for POE's priority queue interface

=head1 SYNOPSIS

  $queue = POE::Queue::Foo->new();

  $payload_id = $queue->enqueue($priority, $payload);

  ($priority, $id, $payload) = $queue->dequeue_next();

  $next_priority = $queue->get_next_priority();
  $item_count = $queue->get_item_count();

  ($priority, $id, $payload) = $q->remove_item($id, \&filter);

  @items = $q->remove_items(\&filter, $count);  # $count is optional

  @items = $q->peek_items(\&filter, $count);  # $count is optional

  $new_priority = $q->adjust_priority($id, \&filter, $delta);
  $new_priority = $q->set_priority($id, \&filter, $priority);

=head1 DESCRIPTION

Priority queues are basically lists of arbitrary things that allow
items to be inserted arbitrarily but that return them in a particular
order.  The order they are returned in is determined by each item's
priority.

Priorities may represent anything, as long as they are numbers and
represent an order from smallest to largest.  Items with the same
priority are entered into a queue in FIFO order.  That is, items at
the same priority are dequeued in the order they achieved a that
priority.

POE uses priority queues to store and sequence its events.  Queue
items are events, and their priorities are the UNIX epoch times they
are due.

=over 4

=item $queue = POE::Queue::Foo->new();

Creates a priority queue, returning its reference.

=item $payload_id = $queue->enqueue($priority, $payload);

Enqueue a payload, which can be just about anything, at a specified
priority level.  Returns a unique ID which can be used to manipulate
the payload or its priority directly.

The payload will be placed into the queue in priority order, from
lowest to highest.  The new payload will follow any others that
already exist in the queue at the specified priority.

=item ($priority, $id, $payload) = $queue->dequeue_next();

Returns the priority, ID, and payload of the item with the lowest
priority.  If several items exist with the same priority, it returns
the one that was at that priority the longest.

=item $next_priority = $queue->get_next_priority();

Returns the priority of the item at the head of the queue.  This is
the lowest priority in the queue.

=item $item_count = $queue->get_item_count();

Returns the number of items in the queue.

=item ($priority, $id, $payload) = $q->remove_item($id, \&filter);

Removes an item by its ID, but only if its payload passes the tests in
a filter function.  If a payload is found with the given ID, it is
passed by reference to the filter function.  This filter only allows
wombats to be removed from a queue.

  sub filter {
    my $payload = $_[0];
    return 1 if $payload eq "wombat";
    return 0;
  }

Returns undef on failure, and sets $! to the reason why the call
failed: ESRCH if the $id did not exist in the queue, or EPERM if the
filter function returned 0.

=item @items = $q->remove_items(\&filter);

=item @items = $q->remove_items(\&filter, $count);

Removes multiple items that match a filter function from a queue.
Returns them as a list of list references.  Each returned item is

  [ $priority, $id, $payload ].

This filter does not allow anything to be removed.

  sub filter { 0 }

The $count is optional.  If supplied, remove_items() will remove at
most $count items.  This is useful when you know how many items exist
in the queue to begin with, as POE sometimes does.  If a $count is
supplied, it should be correct.  There is no telling which items are
removed by remove_items() if $count is too low.

=item @items = $q->peek_items(\&filter);

=item @items = $q->peek_items(\&filter, $count);

Returns a list of items that match a filter function from a queue.
The items are not removed from the list.  Each returned item is a list
reference

  [ $priority, $id, $payload ]

This filter only lets you move monkeys.

  sub filter {
    return $_[0]->[TYPE] & IS_A_MONKEY;
  }

The $count is optional.  If supplied, peek_items() will return at most
$count items.  This is useful when you know how many items exist in
the queue to begin with, as POE sometimes does.  If a $count is
supplied, it should be correct.  There is no telling which items are
returned by peek_items() if $count is too low.

=item $new_priority = $q->adjust_priority($id, \&filter, $delta);

Changes the priority of an item by $delta (which can be negative).
The item is identified by its $id, but the change will only happen if
the supplied filter function returns true.  Returns $new_priority,
which is the priority of the item after it has been adjusted.

This filter function allows anything to be removed.

  sub filter { 1 }

=item $new_priority = $q->set_priority($id, \&filter, $priority);

Changes the priority of an item to $priority.  The item is identified
by its $id, but the change will only happen if the supplied filter
function returns true when applied to the event payload.  Returns
$new_priority, which should match $priority.

=back

=head1 SEE ALSO

L<POE>, L<POE::Queue::Array>

=head1 BUGS

None known.

=head1 AUTHORS & COPYRIGHTS

Please see L<POE> for more information about authors, contributors,
and POE's licensing.

=cut
