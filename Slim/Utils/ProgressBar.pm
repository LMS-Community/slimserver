package Slim::Utils::ProgressBar;

# $Id$
#
# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

# This code is adapted from Mail::SpamAssassin::Util::Progress which ships
# with the following license:
#
# Copyright 2004 Apache Software Foundation
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use bytes;

use constant HAS_TERM_READKEY => eval { require Term::ReadKey };

# Load Time::HiRes if it's available
BEGIN {
	eval { require Time::HiRes };
	Time::HiRes->import( qw(time) ) unless $@;
}

=head2 new

(Slim::Utils::ProgressBar) new (\% $args)

Description:
Creates a new Slim::Utils::ProgressBar object, valid values for the $args hashref are:

=over 4

=item total (required)

The total number of messages expected to be processed. This item is required.

=item fh [optional]

An optional filehandle may be passed in, otherwise STDERR will be used by default.

=item term [optional]

The module will attempt to determine if a valid terminal exists on the
filehandle. This item allows you to override that value.

=back

=cut

sub new {
	my ($class, $args) = @_;

	$class = ref($class) || $class;

	if (!$::progress) {
		return undef;
	}

	# Treat a single value as a count.
	if (!ref($args) eq 'HASH') {
		$args = { 'total' => $args };
	}

	if (!exists($args->{'total'}) || $args->{'total'} < 1) {

		Slim::Utils::Misc::msg("ProgressBar: must provide a total value > 1\n");
		return undef;
	}

	my $self = {
		'total' => $args->{'total'},
		'fh'    => $args->{'fh'} || \*STDERR,
	};

	bless $self, $class;

	$self->{'term'} = $args->{'term'} || -t $self->{'fh'};

	# this will give us the initial progress bar
	$self->init_bar;

	return $self;
}

=head2 init_bar

public instance () init_bar()

Description:
This method creates the initial progress bar and is called automatically from new. In addition
you can call init_bar on an existing object to reset the bar to it's original state.

=cut

sub init_bar {
	my $self = shift;

	my $fh = $self->{'fh'};

	# 0 for now, maybe allow this to be passed in
	$self->{'prev_num_done'} = 0;

	# 0 for now, maybe allow this to be passed in
	$self->{'num_done'} = 0;

	$self->{'avg_msgs_per_sec'} = undef;

	$self->{'start_time'} = time();
	$self->{'prev_time'}  = $self->{'start_time'};

	return unless $self->{'term'};

	my $term_size = undef;

	# If they have set the COLUMNS environment variable, respect it and move on
	if ($ENV{'COLUMNS'}) {
		$term_size = $ENV{'COLUMNS'};
	}

	# The ideal case would be if they happen to have Term::ReadKey installed
	if (!defined($term_size) && HAS_TERM_READKEY) {

		my $term_readkey_term_size = eval { (Term::ReadKey::GetTerminalSize($self->{fh}))[0] };

		# an error will just keep the default
		if (!$@) {
			# GetTerminalSize might have returned an empty array, so check the
			# value and set if it exists, if not we keep the default
			$term_size = $term_readkey_term_size if $term_readkey_term_size;
		}
	}

	# only viable on Unix based OS, so exclude windows, etc here
	if (!defined $term_size && $^O !~ /^(mswin|dos|os2)/oi) {

		my $data = `stty -a`;
		if ($data =~ /columns (\d+)/) {
			$term_size = $1;
		}

		if (!defined $term_size) {
			my $data = `tput cols`;
			if ($data =~ /^(\d+)/) {
				$term_size = $1;
			}
		}
	}

	# fall back on the default
	if (!defined $term_size) {
		$term_size = 80;
	}

	# Adjust the bar size based on what all is going to print around it,
	# do not forget the trailing space. Here is what we have to deal with
	#123456789012345678901234567890123456789
	# XXX% [] XXX.XX tracks/sec XXmXXs LEFT
	# XXX% [] XXX.XX tracks/sec XXmXXs DONE
	$self->{'bar_size'} = $term_size - 39;

	my @chars = (' ') x $self->{'bar_size'};

	print $fh sprintf("\r%3d%% [%s] %6.2f tracks/sec %sm%ss LEFT",
		    0, join('', @chars), 0, '--', '--');
}

=head2 update

public instance () update ([Integer $num_done])

Description:
This method is what gets called to update the progress bar.  You may optionally pass in
an integer value that indicates how many messages have been processed.  If you do not pass
anything in then the num_done value will be incremented by one.

=cut

sub update {
	my ($self, $num_done) = @_;

	my $fh       = $self->{'fh'};
	my $time_now = time();

	# If nothing is passed in to update assume we are adding one to the prev_num_done value
	if (!defined $num_done) {
		$num_done = $self->{'prev_num_done'} + 1;
	}

	my $msgs_since = $num_done - $self->{'prev_num_done'};
	my $time_since = $time_now - $self->{'prev_time'};

	if ($self->{'term'}) {

		my $percentage = $num_done != 0 ? int(($num_done / $self->{'total'}) * 100) : 0;

		my @chars    = (' ') x $self->{'bar_size'};
		my $used_bar = $num_done * ($self->{'bar_size'} / $self->{'total'});

		for (0..$used_bar-1) {
			$chars[$_] = '=';
		}

		my $rate         = $msgs_since/$time_since;
		my $overall_rate = $num_done/($time_now-$self->{'start_time'});

		# semi-complicated calculation here so that we get the avg msg per sec over time
		if (defined $self->{'avg_msgs_per_sec'}) {

			$self->{'avg_msgs_per_sec'} = 0.5 * $self->{'avg_msgs_per_sec'} + 0.5 * ($msgs_since / $time_since);

		} else {

			$self->{'avg_msgs_per_sec'} = $msgs_since / $time_since;
		}

		# using the overall_rate here seems to provide much smoother eta numbers
		my $eta = ($self->{'total'} - $num_done)/$overall_rate;

		# we make the assumption that we will never run > 1 hour, maybe this is bad
		my $min = int($eta/60) % 60;
		my $sec = int($eta % 60);

		print $fh sprintf("\r%3d%% [%s] %6.2f tracks/sec %02dm%02ds LEFT",
				$percentage, join('', @chars), $self->{'avg_msgs_per_sec'}, $min, $sec);

	} else {

		# we have no term, so fake it
		print $fh '.' x $msgs_since;
	}

	$self->{'prev_time'}     = $time_now;
	$self->{'prev_num_done'} = $num_done;
	$self->{'num_done'}      = $num_done;
}

=head2 final

public instance () final ([Integer $num_done])

Description:
This method should be called once all processing has finished.  It will print out the final msgs per sec
calculation and the total time taken.  You can optionally pass in a num_done value, otherwise it will use
the value calculated from the last call to update.

=cut

sub final {
	my ($self, $num_done) = @_;

	# passing in $num_done is optional, and will most likely rarely be used,
	# we should generally favor the data that has been passed in to update()
	if (!defined $num_done) {
		$num_done = $self->{'num_done'};
	}

	my $fh = $self->{'fh'};

	my $time_taken = time() - $self->{'start_time'};

	# can't have 0 time, so just make it 1 second
	   $time_taken ||= 1;

	# in theory this should be 100% and the bar would be completely full, however
	# there is a chance that we had an early exit so we aren't at 100%
	my $percentage = $num_done != 0 ? int(($num_done / $self->{'total'}) * 100) : 0;

	my $msgs_per_sec = $num_done / $time_taken;

	my $min = int($time_taken/60) % 60;
	my $sec = $time_taken % 60;

	if ($self->{'term'}) {

		my @chars    = (' ') x $self->{'bar_size'};
		my $used_bar = $num_done * ($self->{'bar_size'} / $self->{'total'});

		for (0..$used_bar-1) {
			$chars[$_] = '=';
		}

		print $fh sprintf("\r%3d%% [%s] %6.2f tracks/sec %02dm%02ds DONE\n",
		      $percentage, join('', @chars), $msgs_per_sec, $min, $sec);

	} else {

		print $fh sprintf("\n%3d%% Completed %6.2f tracks/sec in %02dm%02ds\n",
		      $percentage, $msgs_per_sec, $min, $sec);
	}
}

1;

__END__
