# (X)Emacs mode: -*- cperl -*-

package Term::ProgressBar;

#XXX TODO Redo original test with count=20
#         Amount Output
#         Amount Prefix/Suffix
#         Tinker with $0?
#         Test use of last_update (with update(*undef*)) with scales
#         Choice of FH other than STDERR
#         If no term, output no progress bar; just progress so far
#         Use of simple term with v2.0 bar
#         If name is wider than term, trim name
#         Don't update progress bar on new?

=head1	NAME

Term::ProgressBar - provide a progress meter on a standard terminal

=head1	SYNOPSIS

  use Term::ProgressBar;

  $progress = Term::ProgressBar->new ({count => $count});
  $progress->update ($so_far);

=head1	DESCRIPTION

Term::ProgressBar provides a simple progress bar on the terminal, to let the
user know that something is happening, roughly how much stuff has been done,
and maybe an estimate at how long remains.

A typical use sets up the progress bar with a number of items to do, and then
calls L<update|"update"> to update the bar whenever an item is processed.

Often, this would involve updating the progress bar many times with no
user-visible change.  To avoid uneccessary work, the update method returns a
value, being the update value at which the user will next see a change.  By
only calling update when the current value exceeds the next update value, the
call overhead is reduced.

Remember to call the C<< $progress->update($max_value) >> when the job is done
to get a nice 100% done bar.

A progress bar by default is simple; it just goes from left-to-right, filling
the bar with '=' characters.  These are called B<major> characters.  For
long-running jobs, this may be too slow, so two additional features are
available: a linear completion time estimator, and/or a B<minor> character:
this is a character that I<moves> from left-to-right on the progress bar (it
does not fill it as the major character does), traversing once for each
major-character added.  This exponentially increases the granularity of the
bar for the same width.

=head1 EXAMPLES

=head2 A really simple use

  #!/usr/bin/perl

  use Term::ProgressBar 2.00;

  use constant MAX => 100_000;

  my $progress = Term::ProgressBar->new(MAX);

  for (0..MAX) {
    my $is_power = 0;
    for(my $i = 0; 2**$i <= $_; $i++) {
      $is_power = 1
        if 2**$i == $_;
    }

    if ( $is_power ) {
      $progress->update($_);
    }
  }

Here is a simple example.  The process considers all the numbers between 0 and
MAX, and updates the progress bar whenever it finds one.  Note that the
progress bar update will be very erratic.  See below for a smoother example.
Note also that the progress bar will never complete; see below to solve this.

The complete text of this example is in F<examples/powers> in the
distribution set (it is not installed as part of the module).

=head2 A smoother bar update

  my $progress = Term::ProgressBar->new($max);

  for (0..$max) {
    my $is_power = 0;
    for(my $i = 0; 2**$i <= $_; $i++) {
      $is_power = 1
        if 2**$i == $_;
    }

    $progress->update($_)
  }

This example calls update for each value considered.  This will result in a
much smoother progress update, but more program time is spent updating the bar
than doing the "real" work.  See below to remedy this.  This example does
I<not> call C<< $progress->update($max); >> at the end, since it is
unnecessary, and ProgressBar will throw an exception at an attempt to update a
finished bar.

The complete text of this example is in F<examples/powers2> in the
distribution set (it is not installed as part of the module.

=head2 A (much) more efficient update

  my $progress = Term::ProgressBar->new({name => 'Powers', count => $max, remove => 1});
  $progress->minor(0);
  my $next_update = 0;

  for (0..$max) {
    my $is_power = 0;
    for(my $i = 0; 2**$i <= $_; $i++) {
      $is_power = 1
        if 2**$i == $_;
    }

    $next_update = $progress->update($_)
      if $_ >= $next_update;
  }
  $progress->update($max)
    if $max >= $next_update;

This example does two things to improve efficiency: firstly, it uses the value
returned by L<update|"update"> to only call it again when needed; secondly, it
switches off the use of minor characters to update a lot less frequently (C<<
$progress->minor(0); >>.  The use of the return value of L<update|"update">
means that the call of C<< $progress->update($max); >> at the end is required
to ensure that the bar ends on 100%, which gives the user a nice feeling.

This example also sets the name of the progress bar.

This example also demonstrates the use of the 'remove' flag, which removes the
progress bar from the terminal when done.

The complete text of this example is in F<examples/powers3> in the
distribution set (it is not installed as part of the module.

=head2 Using Completion Time Estimation

  my $progress = Term::ProgressBar->new({name  => 'Powers',
                                         count => $max,
                                         ETA   => linear, });
  $progress->max_update_rate(1);
  my $next_update = 0;

  for (0..$max) {
    my $is_power = 0;
    for(my $i = 0; 2**$i <= $_; $i++) {
      if ( 2**$i == $_ ) {
        $is_power = 1;
        $progress->message(sprintf "Found %8d to be 2 ** %2d", $_, $i);
      }
    }

    $next_update = $progress->update($_)
      if $_ > $next_update;
  }
  $progress->update($max)
      if $max >= $next_update;

This example uses the L<ETA|"ETA"> option to switch on completion estimation.
Also, the update return is tuned to try to update the bar approximately once
per second, with the L<max_update_rate|"max_update_rate"> call.  See the
documentation for the L<new|new> method for details of the format(s) used.

This example also provides an example of the use of the L<message|"message">
function to output messages to the same filehandle whilst keeping the progress bar intact

The complete text of this example is in F<examples/powers5> in the
distribution set (it is not installed as part of the module.

=cut

# ----------------------------------------------------------------------

# Pragmas --------------------------

use strict;

# Inheritance ----------------------

use base qw( Exporter );
use vars '@EXPORT_OK';
@EXPORT_OK = qw( $PACKAGE $VERSION );

# Utility --------------------------

use Carp                    qw( croak );
use Class::MethodMaker 1.02 qw( );
use Fatal                   qw( open sysopen close seek );
use POSIX                   qw( ceil strftime );

# ----------------------------------------------------------------------

# CLASS METHODS --------------------------------------------------------

# ----------------------------------
# CLASS CONSTANTS
# ----------------------------------

=head1 CLASS CONSTANTS

Z<>

=cut

use constant MINUTE => 60;
use constant HOUR   => 60 * MINUTE;
use constant DAY    => 24 * HOUR;

# The point past which to give ETA of just date, rather than time
use constant ETA_DATE_CUTOFF => 3 * DAY;
# The point past which to give ETA of time, rather time left
use constant ETA_TIME_CUTOFF => 10 * MINUTE;
# The ratio prior to which to not dare any estimates
use constant PREDICT_RATIO => 0.01;

use constant DEFAULTS => {
                          lbrack     => '[',
                          rbrack     => ']',
                          minor_char => '*',
                          major_char => '=',
                          fh         => \*STDERR,
                          name       => undef,
                          ETA        => undef,
                          max_update_rate => 0.5,

                          # The following defaults are never used, but the keys
                          # are valuable for error checking
                          count      => undef,
                          bar_width  => undef,
                          term_width => undef,
                          term       => undef,
                          remove     => 0,
                         };

use constant ETA_TYPES => { map { $_ => 1 } qw( linear ) };

use constant ALREADY_FINISHED => 'progress bar already finished';

use constant DEBUG => 0;

# -------------------------------------

use vars qw($PACKAGE $VERSION);
$PACKAGE = 'Term-ProgressBar';
$VERSION = '2.09';

# ----------------------------------
# CLASS CONSTRUCTION
# ----------------------------------

# ----------------------------------
# CLASS COMPONENTS
# ----------------------------------

# This is here to allow testing to redirect away from the terminal but still
# see terminal output, IYSWIM
my $__FORCE_TERM = 0;

# ----------------------------------
# CLASS HIGHER-LEVEL FUNCTIONS
# ----------------------------------

# ----------------------------------
# CLASS HIGHER-LEVEL PROCEDURES
# ----------------------------------

sub __force_term {
  my $class = shift;
  ($__FORCE_TERM) = @_;
}

# ----------------------------------
# CLASS UTILITY FUNCTIONS
# ----------------------------------

sub term_size {
  my ($fh) = @_;

  eval {
    require Term::ReadKey;
  }; if ($@) {
    warn "Guessing terminal width due to problem with Term::ReadKey\n";
    return 50;
  }

  my $result;
  eval {
    $result = (Term::ReadKey::GetTerminalSize($fh))[0];
    $result-- if ($^O eq "MSWin32");
  }; if ( $@ ) {
    warn "error from Term::ReadKey::GetTerminalSize(): $@";
  }

  # If GetTerminalSize() failed it should (according to its docs)
  # return an empty list.  It doesn't - that's why we have the eval {}
  # above - but also it may appear to succeed and return a width of
  # zero.
  #
  if ( ! $result ) {
    $result = 50;
    warn "guessing terminal width $result\n";
  }

  return $result;
}


# INSTANCE METHODS -----------------------------------------------------

# ----------------------------------
# INSTANCE CONSTRUCTION
# ----------------------------------

=head1 INSTANCE CONSTRUCTION

Z<>

=cut

# Don't document hash keys until tested that the give the desired affect!

=head2 new

Create & return a new Term::ProgressBar instance.

=over 4

=item ARGUMENTS

If one argument is provided, and it is a hashref, then the hash is treated as
a set of key/value pairs, with the following keys; otherwise, it is treated as
a number, being equivalent to the C<count> key.

=over 4

=item count

The item count.  The progress is marked at 100% when update I<count> is
invoked, and proportionally until then.

=item name

A name to prefix the progress bar with.

=item fh

The filehandle to output to.  Defaults to stderr.  Do not try to use
*foo{THING} syntax if you want Term capabilities; it does not work.  Pass in a
globref instead.

=item ETA

A total time estimation to use.  If enabled, a time finished estimation is
printed on the RHS (once sufficient updates have been performed to make such
an estimation feasible).  Naturally, this is an I<estimate>; no guarantees are
made.  The format of the estimate

Note that the format is intended to be as compact as possible while giving
over the relevant information.  Depending upon the time remaining, the format
is selected to provide some resolution whilst remaining compact.  Since the
time remaining decreases, the format typically changes over time.

As the ETA approaches, the format will state minutes & seconds left.  This is
identifiable by the word C<'Left'> at the RHS of the line.  If the ETA is
further away, then an estimate time of completion (rather than time left) is
given, and is identifiable by C<'ETA'> at the LHS of the ETA box (on the right
of the progress bar).  A time or date may be presented; these are of the form
of a 24 hour clock, e.g. C<'13:33'>, a time plus days (e.g., C<' 7PM+3'> for
around in over 3 days time) or a day/date, e.g. C<' 1Jan'> or C<'27Feb'>.

If ETA is switched on, the return value of L<update|"update"> is also
affected: the idea here is that if the progress bar seems to be moving quicker
than the eye would normally care for (and thus a great deal of time is spent
doing progress updates rather than "real" work), the next value is increased
to slow it.  The maximum rate aimed for is tunable via the
L<max_update_rate|"max_update_rate"> component.

The available values for this are:

=over 4

=item undef

Do not do estimation.  The default.

=item linear

Perform linear estimation.  This is simply that the amount of time between the
creation of the progress bar and now is divided by the current amount done,
and completion estimated linearly.

=back

=back

=item EXAMPLES

  my $progress = Term::ProgressBar->new(100); # count from 1 to 100
  my $progress = Term::ProgressBar->new({ count => 100 }); # same

  # Count to 200 thingies, outputting to stdout instead of stderr,
  # prefix bar with 'thingy'
  my $progress = Term::ProgressBar->new({ count => 200,
                                          fh    => \*STDOUT,
                                          name  => 'thingy' });

=back

=cut

Class::MethodMaker->import (new_with_init => 'new',
                            new_hash_init => 'hash_init',);

sub init {
  my $self = shift;

  # V1 Compatibility
  return $self->init({count      => $_[1], name => $_[0],
                      term_width => 50,    bar_width => 50,
                      major_char => '#',   minor_char => '',
                      lbrack     => '',    rbrack     => '',
                      term       => '0 but true', })
    if @_ == 2;

  my $target;

  croak
    sprintf("Term::ProgressBar::new We don't handle this many arguments: %d",
            scalar @_)
    if @_ != 1;

  my %config;

  if ( UNIVERSAL::isa ($_[0], 'HASH') ) {
    ($target) = @{$_[0]}{qw(count)};
    %config = %{$_[0]}; # Copy in, so later playing does not tinker externally
  } else {
    ($target) = @_;
  }

  if ( my @bad = grep ! exists DEFAULTS->{$_}, keys %config )  {
    croak sprintf("Input parameters (%s) to %s not recognized\n",
                  join(':', @bad), 'Term::ProgressBar::new');
  }

  croak "Target count required for Term::ProgressBar new\n"
    unless defined $target;

  $config{$_} = DEFAULTS->{$_}
    for grep ! exists $config{$_}, keys %{DEFAULTS()};
  delete $config{count};

  $config{term} = -t $config{fh}
    unless defined $config{term};

  if ( $__FORCE_TERM ) {
    $config{term} = 1;
    $config{term_width} = $__FORCE_TERM;
    die "term width $config{term_width} (from __force_term) too small"
      if $config{term_width} < 5;
  } elsif ( $config{term} and ! defined $config{term_width}) {
    $config{term_width} = term_size($config{fh});
    die if $config{term_width} < 5;
  }

  unless ( defined $config{bar_width} ) {
    if ( defined $config{term_width} ) {
      # 5 for the % marker
      $config{bar_width}  = $config{term_width} - 5;
      $config{bar_width} -= $_
        for map(( defined $config{$_} ? length($config{$_}) : 0),
                  qw( lbrack rbrack name ));
      $config{bar_width} -= 2 # Extra for ': '
        if defined $config{name};
      $config{bar_width} -= 10
        if defined $config{ETA};
      if ( $config{bar_width} < 1 ) {
        warn "terminal width $config{term_width} too small for bar; defaulting to 10\n";
        $config{bar_width} = 10;
      }
#    } elsif ( ! $config{term} ) {
#      $config{bar_width}  = 1;
#      $config{term_width} = defined $config{ETA} ? 12 : 5;
    } else {
      $config{bar_width}  = $target;
      die "configured bar_width $config{bar_width} < 1"
 	if $config{bar_width} < 1;
    }
  }

  $config{start} = time;

  select(((select $config{fh}), $| = 1)[0]);

  $self->ETA(delete $config{ETA});

  $self->hash_init (%config,

                    offset        => 0,
                    scale         => 1,

                    last_update   => 0,
                    last_position => 0,
                   );
  $self->target($target);
  $self->minor($config{term} && $target > $config{bar_width} ** 1.5);

  $self->update(0); # Initialize the progress bar
}


# ----------------------------------
# INSTANCE FINALIZATION
# ----------------------------------

# ----------------------------------
# INSTANCE COMPONENTS
# ----------------------------------

=head1 INSTANCE COMPONENTS

=cut

=head2 Scalar Components.

See L<Class::MethodMaker/get_set> for usage.

=over 4

=item target

The final target.  Updates are measured in terms of this.  Changes will have
no effect until the next update, but the next update value should be relative
to the new target.  So

  $p = Term::ProgressBar({count => 20});
  # Halfway
  $p->update(10);
  # Double scale
  $p->target(40)
  $p->update(21);

will cause the progress bar to update to 52.5%

=item max_update_rate

This value is taken as being the maximum speed between updates to aim for.
B<It is only meaningful if ETA is switched on.> It defaults to 0.5, being the
number of seconds between updates.

=back

=head2 Boolean Components

See L<Class::MethodMaker/get_set> for usage.

=over 4

=item minor

Default: set.  If unset, no minor scale will be calculated or updated.

Minor characters are used on the progress bar to give the user the idea of
progress even when there are so many more tasks than the terminal is wide that
the granularity would be too great.  By default, Term::ProgressBar makes a
guess as to when minor characters would be valuable.  However, it may not
always guess right, so this method may be called to force it one way or the
other.  Of course, the efficiency saving is minimal unless the client is
utilizing the return value of L<update|"update">.

See F<examples/powers4> and F<examples/powers3> to see minor characters in
action, and not in action, respectively.

=back

=cut

# Private Scalar Components
#  offset    ) Default: 0.       Added to any value supplied to update.
#  scale     ) Default: 1.       Any value supplied to update is multiplied by
#                                this.
#  major_char) Default: '='.     The character printed for the major scale.
#  minor_char) Default: '*'.     The character printed for the minor scale.
#  name      ) Default: undef.   The name to print to the side of the bar.
#  fh        ) Default: STDERR.  The filehandle to output progress to.

# Private Counter Components
#  last_update  ) Default: 0.    The so_far value last time update was invoked.
#  last_position) Default: 0.    The number of the last progress mark printed.

# Private Boolean Components
#  term      ) Default: detected (by C<Term::ReadKey>).
#              If unset, we assume that we are not connected to a terminal (or
#              at least, not a suitably intelligent one).  Then, we attempt
#              minimal functionality.

Class::MethodMaker->import
  (
   get_set       => [qw/ major_units major_char
                         minor_units minor_char
                         lbrack      rbrack
                         name
                         offset      scale
                         fh          start
                         max_update_rate
                     /],
   counter       => [qw/ last_position last_update /],
   boolean       => [qw/ minor name_printed pb_ended remove /],
   # let it be boolean to handle 0 but true
   get_set       => [qw/ term /],
  );

# We generate these by hand since we want to check the values.
sub bar_width {
    my $self = shift;
    return $self->{bar_width} if not @_;
    croak 'wrong number of arguments' if @_ != 1;
    croak 'bar_width < 1' if $_[0] < 1;
    $self->{bar_width} = $_[0];
}
sub term_width {
    my $self = shift;
    return $self->{term_width} if not @_;
    croak 'wrong number of arguments' if @_ != 1;
    croak 'term_width must be at least 5' if $self->term and $_[0] < 5;
    $self->{term_width} = $_[0];
}

sub target {
  my $self = shift;

  if ( @_ ) {
    my ($target) = @_;

    if ( $target ) {
      $self->major_units($self->bar_width / $target);
      $self->minor_units($self->bar_width ** 2 / $target);
      $self->minor      ( defined $self->term_width   and
                          $self->term_width < $target );
    }
    $self->{target}  = $target;
  }

  return $self->{target};
}

sub ETA {
  my $self = shift;

  if (@_) {
    my ($type) = @_;
    croak "Invalid ETA type: $type\n"
      if defined $type and ! exists ETA_TYPES->{$type};
    $self->{ETA} = $type;
  }

  return $self->{ETA};
}

# ----------------------------------
# INSTANCE HIGHER-LEVEL FUNCTIONS
# ----------------------------------

# ----------------------------------
# INSTANCE HIGHER-LEVEL PROCEDURES
# ----------------------------------

=head1 INSTANCE HIGHER-LEVEL PROCEDURES

Z<>

=cut

sub no_minor {
  warn sprintf("%s: This method is deprecated.  Please use %s instead\n",
               (caller (0))[3], '$x->minor (0)',);
  $_[0]->clear_minor (0);
}

# -------------------------------------

=head2 update

Update the progress bar.

=over 4

=item ARGUMENTS

=over 4

=item so_far

Current progress point, in whatever units were passed to C<new>.

If not defined, assumed to be 1+ whatever was the value last time C<update>
was called (starting at 0).

=back

=item RETURNS

=over 4

=item next_call

The next value of so_far at which to call C<update>.

=back

=back

=cut

sub update {
  my $self = shift;
  my ($so_far) = @_;

  if ( ! defined $so_far ) {
    $so_far = $self->last_update + 1;
  }

  my $input_so_far = $so_far;
  $so_far *= $self->scale
    unless $self->scale == 1;
  $so_far += $self->offset;

  my $target = my $next = $self->target;
  my $name = $self->name;
  my $fh = $self->fh;

  if ( $target < 1 ) {
    print $fh "\r";
    printf $fh "$name: "
      if defined $name;
    print $fh "(nothing to do)\n";
    return 2**32-1;
  }

  my $biggies     = $self->major_units * $so_far;
  my @chars = (' ') x $self->bar_width;
  $chars[$_] = $self->major_char
    for 0..$biggies-1;

  if ( $self->minor ) {
    my $smally      = $self->minor_units * $so_far % $self->bar_width;
    $chars[$smally] = $self->minor_char
      unless $so_far == $target;
    $next *= ($self->minor_units * $so_far + 1) / ($self->bar_width ** 2);
  } else {
    $next *= ($self->major_units * $so_far + 1) / $self->bar_width;
  }

  local $\ = undef;

  if ( $self->term > 0 ) {
    local $\ = undef;
    my $to_print = "\r";
    $to_print .= "$name: "
      if defined $name;
    my $ratio = $so_far / $target;
    # Rounds down %
    $to_print .= (sprintf ("%3d%% %s%s%s",
                        $ratio * 100,
                        $self->lbrack, join ('', @chars), $self->rbrack));
    my $ETA = $self->ETA;
    if ( defined $ETA and $ratio > 0 ) {
      if ( $ETA eq 'linear' ) {
        if ( $ratio == 1 ) {
          my $taken = time - $self->start;
          my $ss    = $taken % 60;
          my $mm    = int(($taken % 3600) / 60);
          my $hh    = int($taken / 3600);
          if ( $hh > 99 ) {
            $to_print .= sprintf('D %2dh%02dm', $hh, $mm, $ss);
          } else {
            $to_print .= sprintf('D%2dh%02dm%02ds', $hh, $mm, $ss);
          }
        } elsif ( $ratio < PREDICT_RATIO ) {
          # No safe prediction yet
          $to_print .= 'ETA ------';
        } else {
          my $time = time;
          my $left = (($time - $self->start) * ((1 - $ratio) / $ratio));
          if ( $left  < ETA_TIME_CUTOFF ) {
            $to_print .= sprintf '%1dm%02ds Left', int($left / 60), $left % 60;
          } else {
            my $eta  = $time + $left;
            my $format;
            if ( $left < DAY ) {
              $format = 'ETA  %H:%M';
            } elsif ( $left < ETA_DATE_CUTOFF ) {
              $format = sprintf('ETA %%l%%p+%d',$left/DAY);
            } else {
              $format = 'ETA %e%b';
            }
            $to_print .= strftime($format, localtime $eta);
          }
          # Calculate next to be at least SEC_PER_UPDATE seconds away
          if ( $left > 0 ) {
            my $incr = ($target - $so_far) / ($left / $self->max_update_rate);
            $next = $so_far + $incr
              if $so_far + $incr > $next;
          }
        }
      } else {
        croak "Bad ETA type: $ETA\n";
      }
    }
    for ($self->{last_printed}) {
	unless (defined and $_ eq $to_print) {
	    print $fh $to_print;
	}
	$_ = $to_print;
    }

    $next -= $self->offset;
    $next /= $self->scale
      unless $self->scale == 1;

    if ( $so_far >= $target and $self->remove and ! $self->pb_ended) {
      print $fh "\r", ' ' x $self->term_width, "\r";
      $self->pb_ended;
    }

  } else {
    local $\ = undef;

    if ( $self->term ) { # special case for backwards compat.
     if ( $so_far == 0 and defined $name and ! $self->name_printed ) {
       print $fh "$name: ";
       $self->set_name_printed;
     }

      my $position = int($self->bar_width * ($input_so_far / $target));
      my $add      = $position - $self->last_position;
      $self->last_position_incr ($add)
        if $add;

     print $fh $self->major_char x $add;

     $next -= $self->offset;
     $next /= $self->scale
       unless $self->scale == 1;
    } else {
      my $pc = int(100*$input_so_far/$target);
      printf $fh "[%s] %s: %3d%%\n", scalar(localtime), $name, $pc;

      $next = ceil($target * ($pc+1)/100);
    }

    if ( $input_so_far >= $target ) {
      if ( $self->pb_ended ) {
        croak ALREADY_FINISHED;
      } else {
        if ( $self->term ) {
          print $fh "\n"
        }
        $self->set_pb_ended;
      }
    }
  }


  $next = $target if $next > $target;

  $self->last_update($input_so_far);
  return $next;
}

# -------------------------------------

=head2 message

Output a message.  This is very much like print, but we try not to disturb the
terminal.

=over 4

=item ARGUMENTS

=over 4

=item string

The message to output.

=back

=back

=cut

sub message {
  my $self = shift;
  my ($string) = @_;
  chomp ($string);

  my $fh = $self->fh;
  local $\ = undef;
  if ( $self->term ) {
    print $fh "\r", ' ' x $self->term_width;
    print $fh "\r$string\n";
  } else {
    print $fh "\n$string\n";
    print $fh $self->major_char x $self->last_position;
  }
  undef $self->{last_printed};
  $self->update($self->last_update);
}


# ----------------------------------------------------------------------

=head1 BUGS

Z<>

=head1 REPORTING BUGS

Email the author.

=head1 COMPATIBILITY

If exactly two arguments are provided, then L<new|"new"> operates in v1
compatibility mode: the arguments are considered to be name, and item count.
Various other defaults are set to emulate version one (e.g., the major output
character is '#', the bar width is set to 50 characters and the output
filehandle is not treated as a terminal). This mode is deprecated.

=head1	AUTHOR

Martyn J. Pearce fluffy@cpan.org

Significant contributions from Ed Avis, amongst others.

=head1 COPYRIGHT

Copyright (c) 2001, 2002, 2003, 2004, 2005 Martyn J. Pearce.  This program is
free software; you can redistribute it and/or modify it under the same terms
as Perl itself.

=head1	SEE ALSO

Z<>

=cut

1; # keep require happy.

__END__
