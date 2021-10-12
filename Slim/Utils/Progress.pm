package Slim::Utils::Progress;

#
# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2.

use strict;
use base qw(Slim::Utils::Accessor);

use JSON::XS::VersionOneAndTwo;

use Slim::Schema;
use Slim::Utils::Unicode;

use constant UPDATE_DB_INTERVAL  => 5;
use constant UPDATE_BAR_INTERVAL => 0.3;

__PACKAGE__->mk_accessor( rw => qw(
	type
	name
	start
	finish
	eta
	done
	rate
	
	dbup
	dball
	
	_dbid
	_total
) );

if ( main::SCANNER ) {
	__PACKAGE__->mk_accessor( rw => qw(
		bar
		barup
		fh
		term
		avg_msgs_per_sec
		prev_time
		prev_done
		bar_size
	) );
}

=head2 new

Slim::Utils::Progress->new($args)

Description:
Creates a new Slim::Utils::Progress object which will store progress in the database and
optionally display a progress bar on the terminal.

Valid values for the $args hashref are:

=over 5

=item total [optional]

The total number of messages expected to be processed. This should be specified unless the number of items is not known, in which case it can be set later with $class->total

=item type [optional]

A type lable for a progress instance.  This allows multiple progress instances to be grouped by
the database by type.

=item name [optional]

The name of this progress insance.  Information about this progress instance is stored in the
database by type and name.

=item every [optional]

Set to make the progress object update the database for every call to update (rather than once every UPDATE_DB_INTERVAL sec)

=item bar [optional]

Set to display a progress bar on STDOUT (used by scanner.pl).

=back

=cut

sub new {
	my $class = shift;
	my $args  = shift;
	
	my $now = Time::HiRes::time();
	
	my $self = $class->SUPER::new();
	
	$self->type( $args->{type} || 'NOTYPE' );
	# Scanner progress names may include 'raw' path elements (bytes), needs decoding.
	my $name = $args->{name} ? Slim::Utils::Unicode::utf8decode_locale($args->{name}) : 'NONAME';
	$self->name( $name );
	$self->total( $args->{total} || 0 );
	$self->start( $now );
	$self->eta( -1 );
	$self->done( 0 );
	$self->dbup( 0 );
	$self->dball( $args->{every} || 0 );

	if ( Slim::Schema::hasLibrary() ) {
		my $dbh = Slim::Schema->dbh;
		
		my $sth = $dbh->prepare_cached("SELECT id FROM progress WHERE type = ? AND name = ?");
		$sth->execute( $self->type, $self->name );
		my $row = $sth->fetchrow_hashref;
		$sth->finish;
		
		if ( $row ) {
			$self->_dbid( $row->{id} );
		}
		else {
			$dbh->do(
				"INSERT INTO progress (type, name) VALUES (?, ?)",
				undef,
				$self->type, $self->name
			);
			
			$self->_dbid( $dbh->last_insert_id(undef, undef, undef, undef) );
		}
		
		$self->_update_db( {
			total  => $self->total,
			done   => 0,
			start  => int($now),
			active => 1,
		} );
	}
	
	if ( main::SCANNER && $args->{bar} && $::progress ) {
		$self->bar(1);
		$self->barup(0);
		$self->fh( \*STDOUT );
		$self->term( -t $self->fh );
		
		$self->_initBar if $args->{total};
	}

	return $self;
}

=head2 total

Set the total number of items for a progress instance.  Used when the progress instance is started without knowing the
total number of elements.  Should be called before calling update for a progress instance.

=cut

sub total {
	my ( $self, $total ) = @_;
	
	if ( defined $total ) {
		$self->_total($total);
	
		$self->_update_db( { total => $total } );

		if ( main::SCANNER && $self->bar ) {
			# bar only times duration of progress after total set to get accurate tracks/sec
			$self->start( Time::HiRes::time() );
			$self->_initBar;
		}
	}
	
	return $self->_total;
}

=head2 duration

Returns the total time spent.

=cut

sub duration {
	my $self = shift;
	
	return $self->finish - $self->start;
}

=head2 update

Call to update the progress instance. If $info is passed, this is stored in the database info column
so infomation can be associated with current progress (set the 'every' param in the call to new if
you want to rely on this being stored for every call to update). Unless $done is passed, the 
progress is incremented by one from the previous call to update.

=cut

sub update {
	my ( $self, $info, $latest ) = @_;

	my $done;

	if ( defined $latest ) {
		$done = $self->done($latest);
	}
	else {
		$done = $self->done( $self->done + 1 );
	}

	my $now = Time::HiRes::time();
	
	my $elapsed = $now - $self->start;
	if ($elapsed <= 0) {
		$elapsed = 0.01;
	}
    
	if ( my $rate = $done / $elapsed ) {
		$self->rate($rate);
	
		if ( my $total = $self->total ) {
			# Calculate new ETA value if we know the total
			$self->eta( int( ( $total - $done ) / $rate ) );
		}
	}

	if ( $self->dball || $now > $self->dbup + UPDATE_DB_INTERVAL ) {
		$self->dbup($now);
	
		# Scanner progress updates may include 'raw' path elements (bytes) in 'info', needs decoding.
		$self->_update_db( {
			done => $done,
			info => $info ? Slim::Utils::Unicode::utf8decode_locale($info) : '',
		} );
	
		# Write progress JSON if applicable
		my $os = Slim::Utils::OSDetect->getOS();
		if ( my $json = $os->progressJSON() ) {
			$self->_write_json($json);
		}
	
		# If we're the scanner process, notify the server of our progress
		if ( main::SCANNER ) {
			my $start = $self->start;
			my $type  = $self->type;
			my $name  = $self->name;
			my $total = $self->total;
		
			my $sqlHelperClass = $os->sqlHelperClass();
			$sqlHelperClass->updateProgress( "progress:${start}||${type}||${name}||${done}||${total}||" );
		}
	}

	if ( main::SCANNER && $self->bar && $now > $self->barup + UPDATE_BAR_INTERVAL ) {
		$self->barup($now);
		$self->_updateBar;
	}
}

=head2 final

Call to signal this progress instance is complete.  This updates the database and potentially the progress bar to the complete state.

=cut

sub final {
	my $self = shift;
	
	my $done   = shift || $self->total;
	my $finish = Time::HiRes::time();
	
	$self->done($done);
	$self->finish($finish);
	
	$self->_update_db( {
		done   => $done,
		finish => int($finish),
		active => 0,
		info   => undef,
	} );
	
	# Write progress JSON if applicable
	my $os = Slim::Utils::OSDetect->getOS();
	if ( my $json = $os->progressJSON() ) {
		$self->_write_json($json);
	}
	
	# If we're the scanner process, notify the server of our progress
	if ( main::SCANNER ) {
		my $start  = int( $self->start );
		my $type   = $self->type;
		my $name   = $self->name;
		$done = 1 if !defined $done;
		
		my $sqlHelperClass = $os->sqlHelperClass();
		$sqlHelperClass->updateProgress( "progress:${start}||${type}||${name}||${done}||${done}||${finish}" );
				
		if ( $self->bar ) {
			$self->_finalBar($done);
		}
	}
}

sub _update_db {
	my ( $self, $args ) = @_;
	
	return unless $self->_dbid;
	
	my @cols = keys %{$args};
	my $ph   = join( ', ', map { $_ . ' = ?' } @cols );
	my @vals = map { $args->{$_} } @cols;
	
	my $sth = Slim::Schema->dbh->prepare_cached("UPDATE progress SET $ph WHERE id = ?");
	$sth->execute( @vals, $self->_dbid );
}

# Progress written to the JSON file retains all previous progress steps
my $progress_step = 0;
my $progress_json = [];
sub _write_json {
	my ( $self, $file ) = @_;
	
	my $name = $self->name;
	if ($name =~ /(.*)\|(.*)/) {
		$name = $2;
	}
	
	my $data = {
		start  => $self->start,
		type   => $self->type,
		name   => $name,
		done   => $self->done,
		total  => $self->total,
		eta    => $self->eta,
		rate   => $self->rate,
		finish => $self->finish || undef,
	};
	
	splice @{$progress_json}, $progress_step, 1, $data;
	
	# Append each new progress step to the array
	if ( $data->{finish} ) {
		$progress_step++;
	}
	
	require File::Slurp;
	File::Slurp::write_file( $file, to_json($progress_json) );
}

# Clear all progress information from previous runs
sub clear {
	my $class = shift;
	
	my $os = Slim::Utils::OSDetect->getOS();
	
	# Wipe progress JSON file
	if ( my $json = $os->progressJSON() ) {
		unlink $json if -e $json;
		
		# Reset progress JSON data
		$progress_step = 0;
		$progress_json = [];
	}
	
	# Wipe database progress
	if ( Slim::Schema::hasLibrary() ) {
		Slim::Schema->dbh->do("DELETE FROM progress");
	}
}

=head2 cleanup

Sometimes the external scanner doesn't finish in a controlled way. Clean up the progress data
by flagging active steps inactive, and adding a message telling the user something went wrong (if needed); 

=cut

sub cleanup {
	my ($class, $type) = @_;

	my $dbh = Slim::Schema->dbh;
	
	my $sth = $dbh->prepare( qq{
	    UPDATE progress
	    SET    active = 0, finish = ?, info = ''
	    WHERE  type = ? AND active = 1 AND name != 'failure'
	} );
	my $found = $sth->execute( time(), $type );
	
	# if there was invalid data, flag the process as failed
	if ( $found && $found > 0 ) {
		$dbh->do(
			"INSERT INTO progress (type, name, info) VALUES (?, 'failure', ?)",
			undef,
			$type, $type
		);
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

use constant HAS_TERM_READKEY => eval { main::SCANNER && require Term::ReadKey };

sub _initBar { if ( main::SCANNER && $::progress ) {
	my $self = shift;
	
	return unless $self->term;

	my $fh = $self->fh;

	$self->avg_msgs_per_sec(undef);
	$self->prev_time( $self->start );
	$self->prev_done( 0 );

	my $term_size = undef;

	# If they have set the COLUMNS environment variable, respect it and move on
	if ( $ENV{COLUMNS} ) {
		$term_size = $ENV{COLUMNS};
	}

	# The ideal case would be if they happen to have Term::ReadKey installed
	if ( !defined $term_size && HAS_TERM_READKEY ) {
		my $term_readkey_term_size = eval { (Term::ReadKey::GetTerminalSize($self->fh))[0] };

		# an error will just keep the default
		if (!$@) {
			# GetTerminalSize might have returned an empty array, so check the
			# value and set if it exists, if not we keep the default
			$term_size = $term_readkey_term_size if $term_readkey_term_size;
		}
	}

	# only viable on Unix based OS, so exclude windows, etc here
	if ( !defined $term_size && $^O !~ /^(mswin|dos|os2)/oi ) {

		my $data = `stty -a`;
		if ( $data =~ /columns (\d+)/ ) {
			$term_size = $1;
		}

		if ( !defined $term_size ) {
			my $data = `tput cols`;
			if ($data =~ /^(\d+)/) {
				$term_size = $1;
			}
		}
	}

	# fall back on the default
	if ( !defined $term_size ) {
		$term_size = 80;
	}

	# Adjust the bar size based on what all is going to print around it,
	# do not forget the trailing space. Here is what we have to deal with
	#123456789012345678901234567890123456789
	# XXX% [] XXX.XX tracks/sec XXmXXs LEFT
	# XXX% [] XXX.XX tracks/sec XXmXXs DONE
	$self->bar_size( $term_size - 39 );

	my @chars = (' ') x $self->bar_size;

	print $fh sprintf("\r%3d%% [%s] %6.2f items/sec %s:%s:%s LEFT",
		    0, join('', @chars), 0, '--', '--', '--');
} }

sub _updateBar { if ( main::SCANNER && $::progress ) {
	my $self = shift;

	return unless $self->total;

	my $now  = Time::HiRes::time();
	my $fh   = $self->fh;
	my $done = $self->done;
	my $eta  = $self->eta;

	my $msgs_since = $done - $self->prev_done;
	my $time_since = $now - $self->prev_time;
	
	$self->prev_time( $now );
	$self->prev_done( $done );

	# Avoid a divide by 0 error.
	if ( $time_since == 0 ) {
		$time_since = 1;
	}

	if ( $self->term ) {
		my $percentage = $done != 0 ? int(($done / $self->total) * 100) : 0;

		my @chars    = (' ') x $self->bar_size;
		my $used_bar = $done * ( $self->bar_size / $self->total );

		for (0..$used_bar-1) {
			$chars[$_] = '=';
		}

		my $rate = $msgs_since / $time_since;

		# semi-complicated calculation here so that we get the avg msg per sec over time
		if ( defined $self->avg_msgs_per_sec ) {
			$self->avg_msgs_per_sec( 0.5 * $self->avg_msgs_per_sec + 0.5 * ($msgs_since / $time_since) );
		}
		else {
			$self->avg_msgs_per_sec( $msgs_since / $time_since );
		}

		my $hour = int($eta/3600);
		my $min  = int($eta/60) % 60;
		my $sec  = int($eta % 60);
		
		print $fh sprintf("\r%3d%% [%s] %6.2f items/sec %02d:%02d:%02d LEFT",
				$percentage, join('', @chars), $self->avg_msgs_per_sec, $hour, $min, $sec);
	}
	else {
		# we have no term, so fake it
		print $fh '.' x $msgs_since;
	}
} }

sub _finalBar { if ( main::SCANNER && $::progress ) {
	my ( $self, $done ) = @_;

	my $fh = $self->fh;
	my $time_taken = Time::HiRes::time() - $self->start;

	# can't have 0 time, so just make it 1 second
	$time_taken ||= 1;

	# in theory this should be 100% and the bar would be completely full, however
	# there is a chance that we had an early exit so we aren't at 100%
	my $percentage = $done != 0 ? int(($done / $self->total) * 100) : 0;

	my $msgs_per_sec = $done / $time_taken;

	my $hour = int($time_taken/3600);
	my $min  = int($time_taken/60) % 60;
	my $sec  = $time_taken % 60;

	if ( $self->term && $self->total ) {

		my @chars    = (' ') x $self->bar_size;
		my $used_bar = $done * ( $self->bar_size / $self->total );

		for ( 0..$used_bar - 1 ) {
			$chars[$_] = '=';
		}

		print $fh sprintf("\r%3d%% [%s] %6.2f items/sec %02d:%02d:%02d DONE\n",
		      $percentage, join('', @chars), $msgs_per_sec, $hour, $min, $sec);
	}
	else {
		print $fh sprintf("\n%3d%% Completed %6.2f items/sec in %02dm%02ds\n",
		      $percentage, $msgs_per_sec, $min, $sec);
	}
} }

1;
