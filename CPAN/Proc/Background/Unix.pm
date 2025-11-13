package Proc::Background::Unix;

# ABSTRACT: Unix-specific implementation of process create/wait/kill
require 5.004_04;

use strict;
use Exporter;
use Carp;
use POSIX qw( :errno_h :sys_wait_h );

# Test for existence of FD_CLOEXEC, needed for child-error-through-pipe trick
my ($FD_CLOEXEC);
eval {
  require Fcntl;
  $FD_CLOEXEC= Fcntl::FD_CLOEXEC();
};

# For un-explained mysterious reasons, Time::HiRes::alarm seem to misbehave on 5.10 and earlier
# but core alarm works fine.
my $alarm= ($] >= 5.012)? do { require Time::HiRes; \&Time::HiRes::alarm; }
  : sub {
    # round up to whole seconds
		CORE::alarm(POSIX::ceil($_[0]));
	};

@Proc::Background::Unix::ISA = qw(Exporter);

# Start the background process.  If it is started sucessfully, then record
# the process id in $self->{_os_obj}.
sub _start {
  my ($self, $options)= @_;

  # There are three main scenarios for how-to-exec:
  #   * single-string command, to be handled by shell
  #   * arrayref command, to be handled by execve
  #   * arrayref command with 'exe' (fake argv0)
  # and one that isn't logical:
  #   * single-string command with exe
  # throw an error for that last one rather than trying something awkward
  # like splitting the command string.

  my @argv;
  my ($cmd, $exe)= @{$self}{'_command','_exe'};

  if (ref $cmd eq 'ARRAY') {
    @argv= @$cmd;
    ($exe, my $err) = Proc::Background::_resolve_path(defined $exe? $exe : $argv[0]);
    return $self->_fatal($err) unless defined $exe;
    $self->{_exe}= $exe;
  } elsif (defined $exe) {
    croak "Can't combine 'exe' option with single-string 'command', use arrayref 'command' instead.";
  }

  if (defined $options->{cwd}) {
    -d $options->{cwd}
      or return $self->_fatal("directory does not exist: '$options->{cwd}'");
  }

  my ($new_stdin, $new_stdout, $new_stderr);
  $new_stdin= _resolve_file_handle($options->{stdin}, '<', \*STDIN)
    if exists $options->{stdin};
  $new_stdout= _resolve_file_handle($options->{stdout}, '>>', \*STDOUT)
    if exists $options->{stdout};
  $new_stderr= _resolve_file_handle($options->{stderr}, '>>', \*STDERR)
    if exists $options->{stderr};

  # Fork a child process.
  my ($pipe_r, $pipe_w);
  if (defined $FD_CLOEXEC) {
    # use a pipe for the child to report exec() errors
    pipe $pipe_r, $pipe_w or return $self->_fatal("pipe: $!");
    # This pipe needs to be in the non-preserved range that doesn't exist after exec().
    # In the edge case where a pipe received a FD less than $^F, the CLOEXEC flag isn't set.
    # Try again on higher descriptors, then close the lower ones.
    my @rejects;
    while (fileno $pipe_r <= $^F or fileno $pipe_w <= $^F) {
      push @rejects, $pipe_r, $pipe_w;
      pipe $pipe_r, $pipe_w or return $self->_fatal("pipe: $!");
    }
  }
  my $pid;
  {
    if ($pid = fork()) {
      # parent
      $self->{_os_obj} = $pid;
      $self->{_pid}    = $pid;
      if (defined $pipe_r) {
        close $pipe_w;
        # wait for child to reply or close the pipe
        local $SIG{PIPE}= sub {};
        my $msg= '';
        while (0 < read $pipe_r, $msg, 1024, length $msg) {}
        close $pipe_r;
        # If child wrote anything to the pipe, it failed to exec.
        # Reap it before dying.
        if (length $msg) {
          waitpid $pid, 0;
          return $self->_fatal($msg);
        }
      }
      last;
    } elsif (defined $pid) {
      # child
      # Make absolutely sure nothing in this block interacts with the rest of the
      # process state, and that flow control never skips the _exit().
      $SIG{$_}= sub{die;} for qw( INT HUP QUIT TERM ); # clear custom signal handlers
      $SIG{$_}= 'DEFAULT' for qw( __WARN__ __DIE__ );
      eval {
        eval {
          chdir($options->{cwd}) or die "chdir($options->{cwd}): $!\n"
            if defined $options->{cwd};

          open STDIN, '<&'.fileno($new_stdin) or die "Can't redirect STDIN: $!\n"
            if defined $new_stdin;
          open STDOUT, '>&'.fileno($new_stdout) or die "Can't redirect STDOUT: $!\n"
            if defined $new_stdout;
          open STDERR, '>&'.fileno($new_stderr) or die "Can't redirect STDERR: $!\n"
            if defined $new_stderr;

          if (defined $exe) {
            exec { $exe } @argv or die "$0: exec failed: $!\n";
          } else {
            exec $cmd or die "$0: exec failed: $!\n";
          }
        };
        if (defined $pipe_w) {
          print $pipe_w $@;
          close $pipe_w; # force it to flush.  Nothing else needs closed because we are about to _exit
        } else {
          print STDERR $@;
        }
      };
      POSIX::_exit(1);
    } elsif ($! == EAGAIN) {
      sleep 5;
      redo;
    } else {
      return $self->_fatal("fork: $!");
    }
  }

  $self;
}

sub _resolve_file_handle {
  my ($thing, $mode, $default)= @_;
  if (!defined $thing) {
    open my $fh, $mode, '/dev/null' or croak "open(/dev/null): $!";
    return $fh;
  } elsif (ref $thing) {
    # use 'undef' to mean no-change
    return (fileno($thing) == fileno($default))? undef : $thing;
  } else {
    open my $fh, $mode, $thing or croak "open($thing): $!";
    return $fh;
  }
}

# Wait for the child.
#   (0, exit_value)	: sucessfully waited on.
#   (1, undef)	: process already reaped and exit value lost.
#   (2, undef)	: process still running.
sub _waitpid {
  my ($self, $blocking, $wait_seconds) = @_;

  {
    # Try to wait on the process.
    # Implement the optional timeout with the 'alarm' call.
    my $result= 0;
    if ($blocking && $wait_seconds) {
      local $SIG{ALRM}= sub { die "alarm\n" };
      $alarm->($wait_seconds);
      eval { $result= waitpid($self->{_os_obj}, 0); };
      $alarm->(0);
    }
    else {
      $result= waitpid($self->{_os_obj}, $blocking? 0 : WNOHANG);
    }

    # Process finished.  Grab the exit value.
    if ($result == $self->{_os_obj}) {
      delete $self->{_suspended};
      return (0, $?);
    }
    # Process already reaped.  We don't know the exist status.
    elsif ($result == -1 and $! == ECHILD) {
      return (1, 0);
    }
    # Process still running.
    elsif ($result == 0) {
      return (2, 0);
    }
    # If we reach here, then waitpid caught a signal, so let's retry it.
    redo;
  }
  return 0;
}

sub _suspend {
  kill STOP => $_[0]->{_os_obj};
}

sub _resume {
  kill CONT => $_[0]->{_os_obj};
}

sub _terminate {
  my $self = shift;
  my @kill_sequence= @_ && ref $_[0] eq 'ARRAY'? @{ $_[0] } : qw( TERM 2 TERM 8 KILL 3 KILL 7 );
  # Try to kill the process with different signals.  Calling alive() will
  # collect the exit status of the program.
  while (@kill_sequence and $self->alive) {
    my $sig= shift @kill_sequence;
    my $delay= shift @kill_sequence;
    kill($sig, $self->{_os_obj});
    next unless defined $delay;
    last if $self->_reap(1, $delay); # block before sending next signal
  }
}

1;

__END__

=head1 DESCRIPTION

This module does not have a public interface.  Use L<Proc::Background>.

=head1 IMPLEMENTATION

=head2 Command vs. Exec

Unix systems start a new process by creating a mirror of the current process
(C<fork>) and then having it alter its own state to prepare for the new
program, and then calling C<exec> to replace the running code with code loaded
from a new file.  However, there is a second common method where the user
wants to specify a command line string as they would type it in their shell.
In this case, the actual program being executed is the shell, and the command
line is given as one element of its argument list.

Perl already supports both methods, such that if you pass one string to C<exec>
containing shell characters, it calls the shell, and if you pass multiple
arguments, it directly invokes C<exec>.

This module mostly just lets Perl's C<exec> do its job, but also checks for
the existence of the executable first, to make errors easier to catch.  This
check is skipped if there is a single-string command line.

Unix lets you run a different executable than what is listed in the first
argument.  (this feature lets one Unix executable behave as multiple
different programs depending on what name it sees in the first argument)
You can use that feature by passing separate options of C<exe> and C<command>
to this module's constructor instead of a simple argument list.  But, you
can't mix a C<exe> option with a shell-interpreted command line string.

=head2 Errors during Exec

If the C<autodie> option is enabled, and the system supports C<FD_CLOEXEC>,
this module uses a trick where the forked child relays any errors through
a pipe so that the parent can throw and handle the exception directly instead
of creating a child process that is dead-on-arrival with the error on STDERR.

=cut
