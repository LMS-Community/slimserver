#
# Package meta, adds meta database commands to dbish
#
package DBI::Shell::Spool;

use strict;
use vars qw(@ISA $VERSION);

use IO::Tee;

$VERSION = sprintf( "%d.%02d", q$Revision: 11.91 $ =~ /(\d+)\.(\d+)/ );

sub init {
	my ($self, $sh, @arg)  = @_;


	$sh->install_options( 
	[
		[ 'spool'			=> 'off'	],
	]);
	my $com_ref = $sh->{commands};
	$com_ref->{spool}		= { 
		hint => 
			"spool: on/off or file name to send output to",
	};
		
	return $self;
}

#------------------------------------------------------------------
#
# Start or Stop spooling output.
# The spool support the follow states:
# spool - returns the current state of spooling, if on includes the file name.
# spool on - set the state to on, opens a default name of spool.lst (Yes, the
# Oracle default name).  If the spool current state is already on, returns a
# warning message (Already spooling to file X).
# spool /path/file/name - set the state on, attempt to open the file name
# (using the IO::Tee object to allow multiplex output), and set the new IO
# handle to the default handle.
# spool off - set the state to off.  If the previous state was on, flush the
# current buffer and close the file handle.  If the previous state was off,
# return a warning message (Not current spooling).
#
#------------------------------------------------------------------
sub do_spool {
	my ($sh, @args) = @_;

# Get the current state of spool.
	unless(@args) {
		if ($sh->is_spooling) {
			return $sh->print_buffer( qq{spooling output to file: },
			$sh->{spool_file} );
		} else {
			return $sh->print_buffer( qq{not spooling} );
		}
	}

# So what command did I get at this point?
	my $command = shift @args;

	if ($command =~ m/\boff/i) {	# Turn the spool off (if on).
		if ($sh->is_spooling) { # spool on
			# The tee object contains the open handles, get a list, shift the
			# first (this should be STDOUT), flush.  Then for the remainder
			# flush each and close.
			my @fhs = $sh->{out_fh}->handles;
			$sh->{out_fh} = shift @fhs; select $sh->{out_fh};

			$sh->{out_fh}->flush;
			$sh->spool_off; $sh->{spool_file} = undef;
			foreach my $fh (@fhs) {
				$fh->flush;
				$fh->close;
			}
			$sh->{spool_fh} = undef;
			return $sh->{out_fh};
		}
		return $sh->print_buffer( qq{not spooling} );
	}

	my $spool_file = undef;
	if ($command =~ m/on/i) {	# Turn the spool off (if on).
		unless(@args or $args[0] !~ m/!/) {
			$spool_file = q{on.lst};
		}
	}

	# OK, now we're at the one to open the spool file.  How do I handle if the
	# file exists? Well, unless the next arg is a !, open the file for append.
	my $mode = q{a+};
	if (@args and $args[0] =~ m/!/) {
		shift @args; 
		$mode = q{w};
	}
	
	my $out_fh		= $sh->{out_fh};

	$spool_file = defined $spool_file ? $spool_file : $command;

	if (defined $spool_file) {
		my $tee_fh = new IO::Tee($out_fh, new IO::File($spool_file, $mode)) or
			return $sh->alert(qq{Unable create IO::Tee ($spool_file) handle: $!\n});
		$sh->{out_fh} = $tee_fh;
		$sh->{spool_file} = $spool_file; $sh->spool_on;
		$sh->{spool_fh} = ($tee_fh->handles)[1];
		select $tee_fh;
		return $sh->print_buffer( qq{spooling $spool_file} );
	}
return $sh->alert( qq{spool command failed for unknown reason} );
}

1;
