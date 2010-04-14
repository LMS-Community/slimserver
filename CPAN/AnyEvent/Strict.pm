=head1 NAME

AnyEvent::Strict - force strict mode on for the whole process

=head1 SYNOPSIS

   use AnyEvent::Strict;
   # strict mode now switched on

=head1 DESCRIPTION

This module implements AnyEvent's strict mode.

Loading it makes AnyEvent check all arguments to AnyEvent-methods, at the
expense of being slower (often the argument checking takes longer than the
actual function).

Normally, you don't load this module yourself but instead use it
indirectly via the C<PERL_ANYEVENT_STRICT> environment variable (see
L<AnyEvent>). However, this module can be loaded at any time.

=cut

package AnyEvent::Strict;

use Carp qw(croak);

use AnyEvent (); BEGIN { AnyEvent::common_sense }

our @ISA;

AnyEvent::post_detect {
   # assume the first ISA member is the implementation
   # # and link us in before it in the chain.
   my $MODEL = shift @AnyEvent::ISA;
   unshift @ISA, $MODEL;
   unshift @AnyEvent::ISA, AnyEvent::Strict::
};

sub io {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->io called with illegal cb argument '$arg{cb}'";
   delete $arg{cb};
 
   $arg{poll} =~ /^[rw]$/
      or croak "AnyEvent->io called with illegal poll argument '$arg{poll}'";

   if (defined fileno $arg{fh} or ref $arg{fh} or $arg{fh} !~ /^\s*\d+\s*$/) {
      defined fileno $arg{fh}
         or croak "AnyEvent->io called with illegal fh argument '$arg{fh}'";
   } else {
      $arg{fh} = AnyEvent::_dupfh $arg{poll}, $arg{fh};
   }

   -f $arg{fh}
      and croak "AnyEvent->io called with fh argument pointing to a file";

   delete $arg{poll};
   delete $arg{fh};
 
   croak "AnyEvent->io called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::io (@_)
}

sub timer {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->timer called with illegal cb argument '$arg{cb}'";
   delete $arg{cb};
 
   exists $arg{after}
      or croak "AnyEvent->timer called without mandatory 'after' parameter";
   delete $arg{after};
 
   !$arg{interval} or $arg{interval} > 0
      or croak "AnyEvent->timer called with illegal interval argument '$arg{interval}'";
   delete $arg{interval};
 
   croak "AnyEvent->timer called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::timer (@_)
}

sub signal {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->signal called with illegal cb argument '$arg{cb}'";
   delete $arg{cb};
 
   defined AnyEvent::Base::sig2num $arg{signal} and $arg{signal} == 0
      or croak "AnyEvent->signal called with illegal signal name '$arg{signal}'";
   delete $arg{signal};
 
   croak "AnyEvent->signal called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::signal (@_)
}

sub child {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->child called with illegal cb argument '$arg{cb}'";
   delete $arg{cb};
 
   $arg{pid} =~ /^-?\d+$/
      or croak "AnyEvent->child called with malformed pid value '$arg{pid}'";
   delete $arg{pid};
 
   croak "AnyEvent->child called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::child (@_)
}

sub idle {
   my $class = shift;
   my %arg = @_;

   ref $arg{cb}
      or croak "AnyEvent->idle called with illegal cb argument '$arg{cb}'";
   delete $arg{cb};
 
   croak "AnyEvent->idle called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::idle (@_)
}

sub condvar {
   my $class = shift;
   my %arg = @_;

   !exists $arg{cb} or ref $arg{cb}
      or croak "AnyEvent->condvar called with illegal cb argument '$arg{cb}'";
   delete $arg{cb};
 
   croak "AnyEvent->condvar called with unsupported parameter(s) " . join ", ", keys %arg
      if keys %arg;

   $class->SUPER::condvar (@_)
}

sub time {
   my $class = shift;

   @_
      and croak "AnyEvent->time wrongly called with paramaters";

   $class->SUPER::time (@_)
}

sub now {
   my $class = shift;

   @_
      and croak "AnyEvent->now wrongly called with paramaters";

   $class->SUPER::now (@_)
}

1;

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

