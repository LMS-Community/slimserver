=head1 NAME

AnyEvent::Impl::EV - AnyEvent adaptor for EV

=head1 SYNOPSIS

   use AnyEvent;
   use EV;
  
   # this module gets loaded automatically as required

=head1 DESCRIPTION

This module provides transparent support for AnyEvent. You don't have to
do anything to make EV work with AnyEvent except by loading EV before
creating the first AnyEvent watcher.

=cut

package AnyEvent::Impl::EV;

use AnyEvent (); BEGIN { AnyEvent::common_sense }
use EV 3.44;

# cannot override directly, as EV doesn't allow arguments
sub time       { EV::time       }
sub now        { EV::now        }
sub now_update { EV::now_update }

*AE::time       = \&EV::time;
*AE::now        = \&EV::now;
*AE::now_update = \&EV::now_update;

*AE::timer = \&EV::timer;

sub timer {
   my ($class, %arg) = @_;

   EV::timer $arg{after}, $arg{interval}, $arg{cb}
}

*AE::io = defined &EV::_ae_io # 3.8
   ? \&EV::_ae_io
   : sub($$$) { EV::io $_[0], $_[1] ? EV::WRITE : EV::READ, $_[2] };

sub io {
   my ($class, %arg) = @_;

   EV::io
      $arg{fh},
      $arg{poll} eq "r" ? EV::READ : EV::WRITE,
      $arg{cb}
}

sub signal {
   my ($class, %arg) = @_;

   EV::signal $arg{signal}, $arg{cb}
}

*AE::signal = \&EV::signal;

sub child {
   my ($class, %arg) = @_;

   my $cb = $arg{cb};

   EV::child $arg{pid}, 0, sub {
      $cb->($_[0]->rpid, $_[0]->rstatus);
   }
}

sub idle {
   my ($class, %arg) = @_;

   EV::idle $arg{cb}
}

*AE::idle = \&EV::idle;

sub one_event {
   EV::loop EV::LOOP_ONESHOT;
}

sub loop {
   EV::loop;
}

1;

=head1 SEE ALSO

L<AnyEvent>, L<EV>.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

