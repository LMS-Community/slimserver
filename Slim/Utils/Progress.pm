package Slim::Utils::Progress;

# $Id$
#
# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

use strict;

use Slim::Schema;

use constant UPDATE_DB_INTERVAL  => 1;
use constant UPDATE_BAR_INTERVAL => 0.3;

=head2 new

Slim::Utils::Progress->new($args)

Description:
Creates a new Slim::Utils::Progress object which will store progress in the database and
optionally display a progress bar on the terminal.

Valid values for the $args hashref are:

=over 5

=item total (required)

The total number of messages expected to be processed. This item is required.

=item type [optional]

A type lable for a progress instance.  This allows multiple progress instances to be grouped by
the database by type.

=item name [optional]

The name of this progress insance.  Information about this progress instance is stored in the
database by type and name.

=item every [optional]

Set to make the progress object update the database for every call to update (rather than once every UPDATE_DB_INTERVAL sec)

=item bar [optional]

Set to display a progress bar on STDOUT (used by scanner.pl and will only do so if $::perfmon is set).

=back

=cut

sub new {
	my $class = shift;
	my $args  = shift;

	my $done;
	my $obj;
	my $now = Time::HiRes::time();

	$obj = Slim::Schema->rs('Progress')->find_or_create({
		'type' => $args->{'type'}  || 'NOTYPE',
		'name' => $args->{'name'}  || 'NONAME',
	});

	if (defined $args->{'total'}) {

		$obj->total($args->{'total'});
		$obj->done(0);
		$obj->start ( time() );
		$obj->active(1);

		$obj->update;

		$done = 0;
	}

	my $ref = {
		'total' => $args->{'total'},
		'done'  => $done,
		'obj'   => $obj,
		'dbup'  => 0,
		'dball' => $args->{'every'},
	};

	bless $ref, $class;

	if ($args->{'bar'} && $::progress) {

		$ref->{'bar'} = 1;
		$ref->{'barup'} = 0;
		$ref->{'start_time'} = $now,
		$ref->{'fh'} = \*STDOUT,
		$ref->{'term'} = $args->{'term'} || -t $ref->{'fh'};

		$ref->_initBar,
	}

	return $ref;
}

=head2 update

public instance () update ([String $info], [Integer $num_done])

Description:
Call to update the progress instance. If $info is passed, this is stored in the database info column
so infomation can be associated with current progress (set the 'every' param in the call to new if
you want to rely on this being stored for every call to update). Unless $num_done is passed, the 
progress is incremented by one from the previous call to update.

=cut

sub update {
	my $class = shift;
	my $info  = shift;
	my $latest= shift;

	my $done;

	if (defined $latest) {

		$done = $class->{'done'} = $latest;

	} else {

		$done = ++$class->{'done'};

	}

	my $now = Time::HiRes::time();

	if ($class->{'dball'} || $now > $class->{'dbup'} + UPDATE_DB_INTERVAL) {

		$class->{'dbup'} = $now;

		my $obj = $class->{'obj'} || return;

		$obj->done($done);
		$obj->info($info) if $info;

		$obj->update();
	}

	if ($class->{'bar'} && $now > $class->{'barup'} + UPDATE_BAR_INTERVAL) {

		$class->{'barup'} = $now;

		$class->_updateBar( $done );

	}
}

=head2 final

public instance () final

Description:
Call to signal this progress instance is complete.  This updates the database and potentially the progress bar to the complete state.

=cut

sub final {
	my $class = shift;

	my $obj = $class->{'obj'} || return;

	$obj->done( $class->{'total'} );
	$obj->finish( time() );
	$obj->active(0);
	$obj->info( undef );

	$obj->update;

	if ($class->{'bar'}) {

		$class->_finalBar( $class->{'total'} );
	}
}

# The following code is adapted from Mail::SpamAssassin::Util::Progress which ships
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

use constant HAS_TERM_READKEY => eval { require Term::ReadKey };

sub _initBar {
	my $self = shift;

	my $fh = $self->{'fh'};

	# 0 for now, maybe allow this to be passed in
	$self->{'prev_num_done'} = 0;

	# 0 for now, maybe allow this to be passed in
	$self->{'num_done'} = 0;

	$self->{'avg_msgs_per_sec'} = undef;

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

sub _updateBar {
	my ($self, $num_done) = @_;

	my $fh       = $self->{'fh'};
	my $time_now = Time::HiRes::time();

	# If nothing is passed in to update assume we are adding one to the prev_num_done value
	if (!defined $num_done) {
		$num_done = $self->{'prev_num_done'} + 1;
	}

	my $msgs_since = $num_done - $self->{'prev_num_done'};
	my $time_since = $time_now - $self->{'prev_time'};

	# Avoid a divide by 0 error.
	if ($time_since == 0) {
		$time_since = 1;
	}

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

sub _finalBar {
	my ($self, $num_done) = @_;

	# passing in $num_done is optional, and will most likely rarely be used,
	# we should generally favor the data that has been passed in to update()
	if (!defined $num_done) {
		$num_done = $self->{'num_done'};
	}

	my $fh = $self->{'fh'};

	my $time_taken = Time::HiRes::time() - $self->{'start_time'};

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
