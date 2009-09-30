package Mac::FSEvents::Event;

use strict;

sub id                { shift->{id} }
sub flags             { shift->{flags} }
sub path              { shift->{path} }
sub must_scan_subdirs { shift->{must_scan_subdirs} }
sub user_dropped      { shift->{user_dropped} }
sub kernel_dropped    { shift->{kernel_dropped} }
sub history_done      { shift->{history_done} }
sub mount             { shift->{mount} }
sub unmount           { shift->{unmount} }

1;
__END__

=head1 NAME

Mac::FSEvents::Event - Object representing a filesystem event

=head1 SYNOPSIS

  printf "Event %d received on path %s\n", $event->id, event->path;

=head1 DESCRIPTION

All events that occur are represented as Mac::FSEevents::Event objects.

=head1 METHODS

=over 4

=item B<id>

The Event ID for this event.  Event IDs come from a single global source
and are guaranteed to always be increasing, even across system reboots or
drives moving between machines.  The only real use for this value is for
passing as the 'since' argument to new() to resume receiving events from
a particular point in time.

=item B<flags>

The flags associated with this event.  The raw flags value is not much use,
use the individual flag methods below.

=item B<path>

The path where the event occurred.

=item B<must_scan_subdirs>

This flag indicates that you must rescan not just the directory in the event,
but all its children, recursively.  This can happen if there was a problem
whereby events were coalesced hierarchically.  For example, an event in
/Users/jsmith/Music and an event in /Users/jsmith/Pictures might be coalesced
into an event with this flag set and path=/Users/jsmith.

=item B<user_dropped>

This flag will be set if L<must_scan_subdirs> is set and the bottleneck happened
in the user application.

=item B<kernel_dropped>

This flag will be set if L<must_scan_subdirs> is set and the bottleneck happened
in the kernel.

=item B<history_done>

This flag indicates a special event marking the end of the
"historical" events sent as a result of the 'since' parameter being specified.
After sending all events, one additional event is sent with this flag set.  You
should ignore the path supplied in this event.

=item B<mount>

This flag indicates a special event sent when a volume is mounted.  The path
in the event is the path to the newly-mounted volume.

=item B<unmount>

This flag indicates a special event sent when a volume is unmounted.  The path
in the event is the path to the directory from which the volume was unmounted.

=back

=head1 AUTHOR

Andy Grundman, E<lt>andy@hybridized.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Andy Grundman

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
