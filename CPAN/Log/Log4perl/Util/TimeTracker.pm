##################################################
package Log::Log4perl::Util::TimeTracker;
##################################################

use 5.006;
use strict;
use warnings;
use Log::Log4perl::Util;
use Carp;

our $TIME_HIRES_AVAILABLE;

BEGIN {
    # Check if we've got Time::HiRes. If not, don't make a big fuss,
    # just set a flag so we know later on that we can't have fine-grained
    # time stamps
    $TIME_HIRES_AVAILABLE = 0;
    if(Log::Log4perl::Util::module_available("Time::HiRes")) {
        require Time::HiRes;
        $TIME_HIRES_AVAILABLE = 1;
    }
}

##################################################
sub new {
##################################################
    my $class = shift;
    $class = ref ($class) || $class;

    my $self = {
        reset_time            => undef,
        @_,
    };

    $self->{time_function} = \&_gettimeofday unless 
        defined $self->{time_function};

    bless $self, $class;

    $self->reset();

    return $self;
}

##################################################
sub hires_available {
##################################################
    return $TIME_HIRES_AVAILABLE;
}

##################################################
sub _gettimeofday {
##################################################
    # Return secs and optionally msecs if we have Time::HiRes
    if($TIME_HIRES_AVAILABLE) {
        return (Time::HiRes::gettimeofday());
    } else {
        return (time(), 0);
    }
}

##################################################
sub gettimeofday {
##################################################
    my($self) = @_;

    my($seconds, $microseconds) = $self->{time_function}->();

    $microseconds = 0 if ! defined $microseconds;
    return($seconds, $microseconds);
}

##################################################
sub reset {
##################################################
    my($self) = @_;

    my $current_time = [$self->gettimeofday()];
    $self->{reset_time} = $current_time;
    $self->{last_call_time} = $current_time;

    return $current_time;
}

##################################################
sub time_diff {
##################################################
    my($time_from, $time_to) = @_;

    my $seconds = $time_to->[0] -
                  $time_from->[0];

    my $milliseconds = int(( $time_to->[1] -
                             $time_from->[1] ) / 1000);

    if($milliseconds < 0) {
        $milliseconds = 1000 + $milliseconds;
        $seconds--;
    }

    return($seconds, $milliseconds);
}

##################################################
sub milliseconds {
##################################################
    my($self, $current_time) = @_;

    $current_time = [ $self->gettimeofday() ] unless
        defined $current_time;

    my($seconds, $milliseconds) = time_diff(
            $self->{reset_time}, 
            $current_time);

    return $seconds*1000 + $milliseconds;
}

##################################################
sub delta_milliseconds {
##################################################
    my($self, $current_time) = @_;

    $current_time = [ $self->gettimeofday() ] unless
        defined $current_time;

    my($seconds, $milliseconds) = time_diff(
            $self->{last_call_time}, 
            $current_time);

    $self->{last_call_time} = $current_time;

    return $seconds*1000 + $milliseconds;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Util::TimeTracker - Track time elapsed

=head1 SYNOPSIS

  use Log::Log4perl::Util::TimeTracker;

  my $timer = Log::Log4perl::Util::TimeTracker->new();

    # equivalent to Time::HiRes::gettimeofday(), regardless
    # if Time::HiRes is present or not. 
  my($seconds, $microseconds) = $timer->gettimeofday();

    # reset internal timer
  $timer->reset();

    # return milliseconds since last reset
  $msecs = $timer->milliseconds();

    # return milliseconds since last call
  $msecs = $timer->delta_milliseconds();

=head1 DESCRIPTION

This utility module helps tracking time elapsed for PatternLayout's
date and time placeholders. Its accuracy depends on the availability
of the Time::HiRes module. If it's available, its granularity is
milliseconds, if not, seconds.

The most common use of this module is calling the gettimeofday() 
method:

  my($seconds, $microseconds) = $timer->gettimeofday();

It returns seconds and microseconds of the current epoch time. If 
Time::HiRes is installed, it will simply defer to its gettimeofday()
function, if it's missing, time() will be called instead and $microseconds
will always be 0.

To measure time elapsed in milliseconds, use the reset() method to 
reset the timer to the current time, followed by one or more calls to
the milliseconds() method:

    # reset internal timer
  $timer->reset();

    # return milliseconds since last reset
  $msecs = $timer->milliseconds();

On top of the time span between the last reset and the current time, 
the module keeps track of the time between calls to delta_milliseconds():

  $msecs = $timer->delta_milliseconds();

On the first call, this will return the number of milliseconds since the
last reset(), on subsequent calls, it will return the time elapsed in
milliseconds since the last call to delta_milliseconds() instead. Note
that reset() also resets the time of the last call.

The internal timer of this module gets its time input from the POSIX time() 
function, or, if the Time::HiRes module is available, from its 
gettimeofday() function. To figure out which one it is, use

    if( $timer->hires_available() ) {
        print "Hooray, we get real milliseconds!\n";
    } else {
        print "Milliseconds are just bogus\n";
    }

For testing purposes, a different time source can be provided, so test
suites can simulate time passing by without actually having to wait:

  my $start_time = time();

  my $timer = Log::Log4perl::Util::TimeTracker->new(
          time_function => sub {
              return $start_time++;
          },
  );

Every call to $timer->epoch() will then return a time value that is one
second ahead of the value returned on the previous call. This also means
that every call to delta_milliseconds() will return a value that exceeds
the value returned on the previous call by 1000.

=head1 LICENSE

Copyright 2002-2013 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=head1 AUTHOR

Please contribute patches to the project on Github:

    http://github.com/mschilli/log4perl

Send bug reports or requests for enhancements to the authors via our

MAILING LIST (questions, bug reports, suggestions/patches): 
log4perl-devel@lists.sourceforge.net

Authors (please contact them via the list above, not directly):
Mike Schilli <m@perlmeister.com>,
Kevin Goess <cpan@goess.org>

Contributors (in alphabetical order):
Ateeq Altaf, Cory Bennett, Jens Berthold, Jeremy Bopp, Hutton
Davidson, Chris R. Donnelly, Matisse Enzer, Hugh Esco, Anthony
Foiani, James FitzGibbon, Carl Franks, Dennis Gregorovic, Andy
Grundman, Paul Harrington, Alexander Hartmaier  David Hull, 
Robert Jacobson, Jason Kohles, Jeff Macdonald, Markus Peter, 
Brett Rann, Peter Rabbitson, Erik Selberg, Aaron Straup Cope, 
Lars Thegler, David Viner, Mac Yang.

