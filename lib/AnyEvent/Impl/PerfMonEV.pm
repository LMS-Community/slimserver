package AnyEvent::Impl::PerfMonEV;

# Subclassed AnyEvent::Impl::EV to allow callbacks to timed by perfmon

no warnings;
use strict;

use base qw(AnyEvent::Impl::EV);

sub timer {
   my ($class, %arg) = @_;

   EV::timer $arg{after}, $arg{interval}, sub {
	   my $now = AnyEvent->time;
	   $arg{cb}->(@_);
	   Slim::Utils::PerfMon->check('timer', AnyEvent->time - $now, undef, $arg{cb});
   };
}

sub io {
   my ($class, %arg) = @_;

   my $cb = $arg{cb};

   EV::io
      $arg{fh},
      $arg{poll} eq "r" ? EV::READ : EV::WRITE,
      sub {
		  my $now = AnyEvent->time;
		  $cb->(@_);
		  Slim::Utils::PerfMon->check('io', AnyEvent->time - $now, undef, $cb);
	  };
}

sub signal {
   my ($class, %arg) = @_;

   EV::signal $arg{signal}, sub {
	   my $now = AnyEvent->time;
	   $arg{cb}->(@_);
	   Slim::Utils::PerfMon->check('anyevent', AnyEvent->time - $now, undef, $arg{cb});
   };
}

sub child {
   my ($class, %arg) = @_;

   my $cb = $arg{cb};

   EV::child $arg{pid}, 0, sub {
	   my $now = AnyEvent->time;
	   $cb->($_[0]->rpid, $_[0]->rstatus);
	   Slim::Utils::PerfMon->check('anyevent', AnyEvent->time - $now, undef, $cb);
   }
}

sub idle {
   my ($class, %arg) = @_;

   EV::idle sub {
	   my $now = AnyEvent->time;
	   $arg{cb}->(@_);
	   Slim::Utils::PerfMon->check('anyevent', AnyEvent->time - $now, undef, $arg{cb});
   };
}

1;
