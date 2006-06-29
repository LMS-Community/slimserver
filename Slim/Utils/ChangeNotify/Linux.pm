package Slim::Utils::ChangeNotify::Linux;

# $Id$

use strict;
use base 'Class::Accessor::Fast';

use File::Find;
use Linux::Inotify2;

use Slim::Utils::Misc;

__PACKAGE__->mk_accessors( qw[ notifier ] );

my $watcherMask = IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE;

sub newWatcher {
	my $class = shift;

	my $self  = $class->SUPER::new();

	$self->notifier(Linux::Inotify2->new);

	return $self;
}

sub addWatcher {
	my $self  = shift;
	my $args  = shift;

	my $entry = $args->{'dir'} || $args->{'file'};
	my $cb    = $args->{'callback'};

	if ($entry && ref($cb) eq 'CODE') {

		if (-d $entry) {

			find(sub {

				next if !-d $File::Find::name;

				$self->notifier->watch($File::Find::name, $watcherMask, $cb);

			}, $entry);

		} elsif (-f $entry) {

			$self->notifier->watch($entry, $watcherMask, $cb);
		}

		return 1;
	}

	return 0;
}

sub watcherDescriptor {
	my $self = shift;

	return $self->notifier->fileno;
}

sub pollDescriptor {
	my $self = shift;

	return $self->notifier->poll;
}

1;

__END__
