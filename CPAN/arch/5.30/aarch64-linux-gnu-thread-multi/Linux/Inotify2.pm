=head1 NAME

Linux::Inotify2 - scalable directory/file change notification

=head1 SYNOPSIS

=head2 Callback Interface

 use Linux::Inotify2;

 # create a new object
 my $inotify = new Linux::Inotify2
    or die "unable to create new inotify object: $!";
 
 # add watchers
 $inotify->watch ("/etc/passwd", IN_ACCESS, sub {
    my $e = shift;
    my $name = $e->fullname;
    print "$name was accessed\n" if $e->IN_ACCESS;
    print "$name is no longer mounted\n" if $e->IN_UNMOUNT;
    print "$name is gone\n" if $e->IN_IGNORED;
    print "events for $name have been lost\n" if $e->IN_Q_OVERFLOW;
 
    # cancel this watcher: remove no further events
    $e->w->cancel;
 });

 # integration into AnyEvent (works with EV, Glib, Tk, POE...)
 my $inotify_w = AnyEvent->io (
    fh => $inofity->fileno, poll => 'r', cb => sub { $inotify->poll }
 );

 # manual event loop
 1 while $inotify->poll;

=head2 Streaming Interface

 use Linux::Inotify2 ;

 # create a new object
 my $inotify = new Linux::Inotify2
    or die "Unable to create new inotify object: $!" ;

 # create watch
 $inotify->watch ("/etc/passwd", IN_ACCESS)
    or die "watch creation failed" ;

 while () {
   my @events = $inotify->read;
   unless (@events > 0) {
     print "read error: $!";
     last ;
   }
   printf "mask\t%d\n", $_->mask foreach @events ; 
 }

=head1 DESCRIPTION

This module implements an interface to the Linux 2.6.13 and later Inotify
file/directory change notification sytem.

It has a number of advantages over the Linux::Inotify module:

   - it is portable (Linux::Inotify only works on x86)
   - the equivalent of fullname works correctly
   - it is better documented
   - it has callback-style interface, which is better suited for
     integration.

=head2 The Linux::Inotify2 Class

=over 4

=cut

package Linux::Inotify2;

use Carp ();
use Fcntl ();
use Scalar::Util ();

use common::sense;

use base 'Exporter';

BEGIN {
   our $VERSION = '1.21';
   our @EXPORT = qw(
      IN_ACCESS IN_MODIFY IN_ATTRIB IN_CLOSE_WRITE
      IN_CLOSE_NOWRITE IN_OPEN IN_MOVED_FROM IN_MOVED_TO
      IN_CREATE IN_DELETE IN_DELETE_SELF IN_MOVE_SELF
      IN_ALL_EVENTS
      IN_UNMOUNT IN_Q_OVERFLOW IN_IGNORED
      IN_CLOSE IN_MOVE
      IN_ISDIR IN_ONESHOT IN_MASK_ADD IN_DONT_FOLLOW IN_ONLYDIR
   );

   require XSLoader;
   XSLoader::load Linux::Inotify2, $VERSION;
}

=item my $inotify = new Linux::Inotify2

Create a new notify object and return it. A notify object is kind of a
container that stores watches on filesystem names and is responsible for
handling event data.

On error, C<undef> is returned and C<$!> will be set accordingly. The followign errors
are documented:

 ENFILE   The system limit on the total number of file descriptors has been reached.
 EMFILE   The user limit on the total number of inotify instances has been reached.
 ENOMEM   Insufficient kernel memory is available.

Example:

   my $inotify = new Linux::Inotify2
      or die "Unable to create new inotify object: $!";

=cut

sub new {
   my ($class) = @_;

   my $fd = inotify_init;

   return unless $fd >= 0;

   bless { fd => $fd }, $class
}

=item $watch = $inotify->watch ($name, $mask[, $cb])

Add a new watcher to the given notifier. The watcher will create events
on the pathname C<$name> as given in C<$mask>, which can be any of the
following constants (all exported by default) ORed together.

"file" refers to any filesystem object in the watch'ed object (always a
directory), that is files, directories, symlinks, device nodes etc., while
"object" refers to the object the watch has been set on itself:

 IN_ACCESS            object was accessed
 IN_MODIFY            object was modified
 IN_ATTRIB            object metadata changed
 IN_CLOSE_WRITE       writable fd to file / to object was closed
 IN_CLOSE_NOWRITE     readonly fd to file / to object closed
 IN_OPEN              object was opened
 IN_MOVED_FROM        file was moved from this object (directory)
 IN_MOVED_TO          file was moved to this object (directory)
 IN_CREATE            file was created in this object (directory)
 IN_DELETE            file was deleted from this object (directory)
 IN_DELETE_SELF       object itself was deleted
 IN_MOVE_SELF         object itself was moved
 IN_ALL_EVENTS        all of the above events

 IN_ONESHOT           only send event once
 IN_ONLYDIR           only watch the path if it is a directory
 IN_DONT_FOLLOW       don't follow a sym link
 IN_MASK_ADD          not supported with the current version of this module

 IN_CLOSE             same as IN_CLOSE_WRITE | IN_CLOSE_NOWRITE
 IN_MOVE              same as IN_MOVED_FROM | IN_MOVED_TO

C<$cb> is a perl code reference that, if given, is called for each
event. It receives a C<Linux::Inotify2::Event> object.

The returned C<$watch> object is of class C<Linux::Inotify2::Watch>.

On error, C<undef> is returned and C<$!> will be set accordingly. The
following errors are documented:

 EBADF    The given file descriptor is not valid.
 EINVAL   The given event mask contains no legal events.
 ENOMEM   Insufficient kernel memory was available.
 ENOSPC   The user limit on the total number of inotify watches was reached or the kernel failed to allocate a needed resource.
 EACCESS  Read access to the given file is not permitted.

Example, show when C</etc/passwd> gets accessed and/or modified once:

   $inotify->watch ("/etc/passwd", IN_ACCESS | IN_MODIFY, sub {
      my $e = shift;
      print "$e->{w}{name} was accessed\n" if $e->IN_ACCESS;
      print "$e->{w}{name} was modified\n" if $e->IN_MODIFY;
      print "$e->{w}{name} is no longer mounted\n" if $e->IN_UNMOUNT;
      print "events for $e->{w}{name} have been lost\n" if $e->IN_Q_OVERFLOW;

      $e->w->cancel;
   });

=cut

sub watch {
   my ($self, $name, $mask, $cb) = @_;

   my $wd = inotify_add_watch $self->{fd}, $name, $mask;

   return unless $wd >= 0;
   
   my $w = $self->{w}{$wd} = bless {
      inotify => $self,
      wd      => $wd,
      name    => $name,
      mask    => $mask,
      cb      => $cb,
   }, "Linux::Inotify2::Watch";

   Scalar::Util::weaken $w->{inotify};

   $w
}

=item $inotify->fileno

Returns the fileno for this notify object. You are responsible for calling
the C<poll> method when this fileno becomes ready for reading.

=cut

sub fileno {
   $_[0]{fd}
}

=item $inotify->blocking ($blocking)

Clears ($blocking true) or sets ($blocking false) the C<O_NONBLOCK> flag on the file descriptor.

=cut

sub blocking {
   my ($self, $blocking) = @_;

   inotify_blocking $self->{fd}, $blocking;
}

=item $count = $inotify->poll

Reads events from the kernel and handles them. If the notify fileno is
blocking (the default), then this method waits for at least one event
(and thus returns true unless an error occurs). Otherwise it returns
immediately when no pending events could be read.

Returns the count of events that have been handled.

=cut

sub poll {
   scalar &read
}

=item $count = $inotify->read

Reads events from the kernel. Blocks in blocking mode (default) until any
event arrives. Returns list of C<Linux::Inotify2::Event> objects or empty
list if none (non-blocking mode) or error occured ($! should be checked).

=cut

sub read {
   my ($self) = @_;

   my @ev = inotify_read $self->{fd};
   my @res;

   for (@ev) {
      my $w = $_->{w} = $self->{w}{$_->{wd}}
         or next; # no such watcher

      exists $self->{ignore}{$_->{wd}}
         and next; # watcher has been canceled

      bless $_, "Linux::Inotify2::Event";

      push @res, $_;

      $w->{cb}->($_) if $w->{cb};
      $w->cancel if $_->{mask} & (IN_IGNORED | IN_UNMOUNT | IN_ONESHOT | IN_DELETE_SELF);
   }

   delete $self->{ignore};

   @res
}

sub DESTROY {
   inotify_close $_[0]{fd}
}

=back

=head2 The Linux::Inotify2::Event Class

Objects of this class are handed as first argument to the watch
callback. It has the following members and methods:

=over 4

=item $event->w

=item $event->{w}

The watcher object for this event.

=item $event->name

=item $event->{name}

The path of the filesystem object, relative to the watch name.

=item $watch->fullname

Returns the "full" name of the relevant object, i.e. including the C<name>
member of the watcher (if the the watch is on a directory and a dir entry
is affected), or simply the C<name> member itself when the object is the
watch object itself.

=item $event->mask

=item $event->{mask}

The received event mask. In addition the the events described for
C<$inotify->watch>, the following flags (exported by default) can be set:

 IN_ISDIR             event object is a directory
 IN_Q_OVERFLOW        event queue overflowed

 # when any of the following flags are set,
 # then watchers for this event are automatically canceled
 IN_UNMOUNT           filesystem for watch'ed object was unmounted
 IN_IGNORED           file was ignored/is gone (no more events are delivered)
 IN_ONESHOT           only one event was generated

=item $event->IN_xxx

Returns a boolean that returns true if the event mask matches the
event. All of the C<IN_xxx> constants can be used as methods.

=item $event->cookie

=item $event->{cookie}

The event cookie to "synchronize two events". Normally zero, this value is
set when two events relating to the same file are generated. As far as I
know, this only happens for C<IN_MOVED_FROM> and C<IN_MOVED_TO> events, to
identify the old and new name of a file.

=back

=cut

package Linux::Inotify2::Event;

sub w       { $_[0]{w}      }
sub name    { $_[0]{name}   }
sub mask    { $_[0]{mask}   }
sub cookie  { $_[0]{cookie} }

sub fullname {
   length $_[0]{name}
      ? "$_[0]{w}{name}/$_[0]{name}"
      : $_[0]{w}{name};
}

for my $name (@Linux::Inotify2::EXPORT) {
   my $mask = &{"Linux::Inotify2::$name"};

   *$name = sub { ($_[0]{mask} & $mask) == $mask };
}

=head2 The Linux::Inotify2::Watch Class

Watch objects are created by calling the C<watch> method of a notifier.

It has the following members and methods:

=over 4

=item $watch->name

=item $watch->{name}

The name as specified in the C<watch> call. For the object itself, this is
the empty string.  For directory watches, this is the name of the entry
without leading path elements.

=item $watch->mask

=item $watch->{mask}

The mask as specified in the C<watch> call.

=item $watch->cb ([new callback])

=item $watch->{cb}

The callback as specified in the C<watch> call. Can optionally be changed.

=item $watch->cancel

Cancels/removes this watch. Future events, even if already queued queued,
will not be handled and resources will be freed.

=back

=cut

package Linux::Inotify2::Watch;

sub name    { $_[0]{name} }
sub mask    { $_[0]{mask} }

sub cb {
   $_[0]{cb} = $_[1] if @_ > 1;
   $_[0]{cb}
}

sub cancel {
   my ($self) = @_;

   my $inotify = delete $self->{inotify}
      or return 1; # already canceled

   delete $inotify->{w}{$self->{wd}}; # we are no longer there
   $inotify->{ignore}{$self->{wd}} = 1; # ignore further events for one poll

   (Linux::Inotify2::inotify_rm_watch $inotify->{fd}, $self->{wd})
      ? 1 : undef
}

=head1 SEE ALSO

L<AnyEvent>, L<Linux::Inotify>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

1
