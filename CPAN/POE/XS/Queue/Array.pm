package POE::XS::Queue::Array;
use strict;
use vars qw(@ISA $VERSION);
use POE::Queue;

@ISA = qw(POE::Queue);

BEGIN {
  require Exporter;
  @ISA = qw(Exporter);
  $VERSION = '0.002';
  eval {
    # try XSLoader first, DynaLoader has annoying baggage
    require XSLoader;
    XSLoader::load('POE::XS::Queue::Array' => $VERSION);
    1;
  } or do {
    require DynaLoader;
    push @ISA, 'DynaLoader';
    bootstrap POE::XS::Queue::Array $VERSION;
  }
}

# lifted from POE::Queue::Array
sub ITEM_PRIORITY () { 0 }
sub ITEM_ID       () { 1 }
sub ITEM_PAYLOAD  () { 2 }

sub import {
  my $package = caller();
  no strict 'refs';
  *{ $package . '::ITEM_PRIORITY' } = \&ITEM_PRIORITY;
  *{ $package . '::ITEM_ID'       } = \&ITEM_ID;
  *{ $package . '::ITEM_PAYLOAD'  } = \&ITEM_PAYLOAD;
}

# everything else is XS
1;

__END__

=head1 NAME

POE::XS::Queue::Array - an XS implementation of POE::Queue::Array.

=head1 SYNOPSIS

See POE::Queue.

=head1 DESCRIPTION

This class is an implementation of the abstract POE::Queue interface.
It implements a priority queue using C, with an XS interface supplied.

The current implementation could use some optimization, especially for
large queues.

Please see the POE::Queue documentation, which explains this one's
functions, features, and behavior.

The following extra methods are added beyond POE::Queue::Array:

=over

=item dump

Dumps the internal structure of the queue to stderr.

=item verify

Does limited verification of the structure of the queue.  If the
verification fails then a message is sent to stderr and the queue is
dumped as with the dump() method, and your program will exit.

=back

=head1 SEE ALSO

POE, POE::Queue, POE::Queue::Array

=head1 BUGS

None known.

Some possible improvements include:

=over

=item *

use binary searches for large queues

=item *

use a B-Tree for the queue (not a binary tree, a B-Tree), though this
would require a module rename.

=item *

use a custom hash instead of a HV for the id to priority mapping,
either glib's hash or convert to C++ and use the STL map.

=item *

some of the XS code could be optimized to do less work in scalar
context, pq_remove_items and pq_peek_items could avoid building all
those array refs.

=back

=head1 AUTHOR

Tony Cook <tonyc@cpan.org>

=cut


