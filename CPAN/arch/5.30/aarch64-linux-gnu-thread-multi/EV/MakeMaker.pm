package EV::MakeMaker;

BEGIN { eval { require warnings } && warnings->unimport ("uninitialized") }

use Config;
use base 'Exporter';

@EXPORT_OK = qw(&ev_args $installsitearch);

my %opt;

for my $opt (split /:+/, $ENV{PERL_MM_OPT}) {
   my ($k,$v) = split /=/, $opt;
   $opt{$k} = $v;
}

my $extra = $Config{sitearch};

$extra =~ s/$Config{prefix}/$opt{PREFIX}/ if
    exists $opt{PREFIX};

for my $d ($extra, @INC) {
   if (-e "$d/EV/EVAPI.h") {
      $installsitearch = $d;
      last;
   }
}

sub ev_args {
   my %arg = @_;
   $arg{INC} .= " -I$installsitearch/EV -I$installsitearch";
   %arg;
}

1;
__END__

=head1 NAME

EV::MakeMaker - MakeMaker glue for the C-level EV API

=head1 SYNOPSIS

This allows you to access some libevent functionality from other perl
modules.

=head1 DESCRIPTION

For optimal performance, hook into EV at the C-level.  You'll need
to make changes to your C<Makefile.PL> and add code to your C<xs> /
C<c> file(s).

=head1 HOW TO

=head2 Makefile.PL

  use EV::MakeMaker qw(ev_args);

  # ... set up %args ...

  WriteMakefile (ev_args (%args));

=head2 XS

  #include "EVAPI.h"

  BOOT:
    I_EV_API ("YourModule");

=head1 API

See the L<EVAPI.h|http://cvs.schmorp.de/EV/EV/EVAPI.h> header, which you should include instead
of F<ev.h>.

In short, all the functions and macros from F<ev.h> should work, except
that the trailing underscore macros (C<EV_A_>, C<EV_DEFAULT_>) are not
available (except C<EV_P_> :).

Multiplicity is enabled.

The C<data> member in each watcher is of type C<SV *> and not C<void *>
(this might change at some point).

=head1 EXAMPLE

The L<EV::Glib>, L<EV::ADNS> and L<Glib::EV> modules all give nice
examples on how to use this module.

Here are some F<.xs> fragments taken from EV::ADNS that should get you
going:

  #include "EVAPI.h"

  static ev_prepare pw;
  static ev_idle iw;

  static void
  idle_cb (EV_P_ ev_idle *w, int revents)
  {
    ev_idle_stop (EV_A, w);
  }

  MODULE = ...

  BOOT:
  {
    I_EV_API ("EV::ADNS");
    ev_prepare_init (&pw, prepare_cb);
    ev_init (&iw, idle_cb); ev_set_priority (&iw, EV_MINPRI);
    ev_idle_start (EV_DEFAULT, &iw);
  }

=cut

