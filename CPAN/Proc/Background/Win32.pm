package Proc::Background::Win32;

# ABSTRACT: Windows-specific implementation of process create/wait/kill
require 5.004_04;

use strict;
use Exporter;
use Carp;
use Win32;
use Win32::Process qw( NORMAL_PRIORITY_CLASS INFINITE );
use Win32::ShellQuote ();

@Proc::Background::Win32::ISA = qw(Exporter);

sub _start {
  my ($self, $options)= @_;
  my ($cmd, $exe, $cmdline, $err)= @{$self}{'_command','_exe'};

  # If 'command' is a single string, treat it as system() would and assume
  # it should be split into arguments.  The first argument is then the
  # application executable, if not already specified as an option.
  if (ref $cmd ne 'ARRAY') {
    $cmdline= $cmd;
    ($exe) = Win32::ShellQuote::unquote_native($cmdline)
      unless exists $options->{exe};
  }
  # system() would treat a list of arguments as an un-quoted ARGV
  # for the program, so concatenate them into a command line appropriate
  # for Win32 CommandLineToArgvW to decode back to what we started with.
  # Preserve the first un-quoted argument for use as lpApplicationName,
  # unless user requested some value (including undef).
  else {
    $exe = $cmd->[0] unless exists $options->{exe};
    $cmdline= Win32::ShellQuote::quote_native(@$cmd);
  }

  if (defined $exe) {
    # Find the absolute path to the program.  If it cannot be found,
    # then return.
    ($exe, $err) = Proc::Background::_resolve_path($exe);
    return $self->_fatal($err) unless defined $exe;
    # To work around a problem where Win32::Process::Create cannot start a
    # process when the full pathname has a space in it, convert the full
    # pathname to the Windows short 8.3 format which contains no spaces.
    $exe = Win32::GetShortPathName($exe)
  }
  else {
    Win32::Process->VERSION > 0.16
      or croak "{exe => undef} feature requires Win32::Process 0.17";
  }

  my $cwd= '.';
  if (defined $options->{cwd}) {
    -d $options->{cwd}
      or return $self->_fatal("directory does not exist: '$options->{cwd}'");
    $cwd= $options->{cwd};
  }

  # On Strawberry Perl, CreateProcess will inherit the current process STDIN/STDOUT/STDERR,
  # but there is no way to specify them without altering the current process.
  # So, redirect handles, then create process, then revert them.
  my ($inherit, $new_stdin, $old_stdin, $new_stdout, $old_stdout, $new_stderr, $old_stderr);
  if (exists $options->{stdin}) {
    $inherit= 1;
    $new_stdin= _resolve_file_handle($options->{stdin}, '<', \*STDIN);
    open $old_stdin, '<&'.fileno(\*STDIN) or croak "Can't save STDIN: $!\n"
      if defined $new_stdin;
  }
  if (exists $options->{stdout}) {
    $inherit= 1;
    $new_stdout= _resolve_file_handle($options->{stdout}, '>>', \*STDOUT);
    open $old_stdout, '>&'.fileno(\*STDOUT) or croak "Can't save STDOUT: $!\n"
      if defined $new_stdout;
  }
  if (exists $options->{stderr}) {
    $inherit= 1;
    $new_stderr= _resolve_file_handle($options->{stderr}, '>>', \*STDERR);
    open $old_stderr, '>&'.fileno(\*STDERR) or croak "Can't save STDERR: $!\n"
      if defined $new_stderr;
  }
    
  {
    local $@;
    eval {
      open STDIN, '<&'.fileno($new_stdin) or die "Can't redirect STDIN: $!\n"
        if defined $new_stdin;
      open STDOUT, '>&'.fileno($new_stdout) or die "Can't redirect STDOUT: $!\n"
        if defined $new_stdout;
      open STDERR, '>&'.fileno($new_stderr) or die "Can't redirect STDERR: $!\n"
        if defined $new_stderr;

      # Perl 5.004_04 cannot run Win32::Process::Create on a nonexistant
      # hash key.
      my $os_obj = 0;

      # Create the process.
      Win32::Process::Create($os_obj, $exe, $cmdline, $inherit, NORMAL_PRIORITY_CLASS, $cwd)
        or die Win32::FormatMessage( Win32::GetLastError() )."\n";
      $self->{_pid}    = $os_obj->GetProcessID;
      $self->{_os_obj} = $os_obj;
    };
    chomp($err= $@);
    # Now restore handles before throwing exception
    open STDERR, '>&'.fileno($old_stderr) or warn "Can't restore STDERR: $!\n"
      if defined $old_stderr;
    open STDOUT, '>&'.fileno($old_stdout) or warn "Can't restore STDOUT: $!\n"
      if defined $old_stdout;
    open STDIN, '<&'.fileno($old_stdin) or warn "Can't restore STDIN: $!\n"
      if defined $old_stdin;
  }
  if ($self->{_os_obj}) {
    return 1;
  } else {
    return $self->_fatal($err);
  }
}

sub _resolve_file_handle {
  my ($thing, $mode, $default)= @_;
  if (!defined $thing) {
    open my $fh, $mode, 'NUL' or croak "open(NUL): $!";
    return $fh;
  } elsif (ref $thing) {
    return fileno($thing) == fileno($default)? undef : $thing;
  } else {
    open my $fh, $mode, $thing or croak "open($thing): $!";
    return $fh;
  }
}

# Reap the child.
#   (0, exit_value)	: sucessfully waited on.
#   (1, undef)	: process already reaped and exit value lost.
#   (2, undef)	: process still running.
sub _waitpid {
  my ($self, $blocking, $wait_seconds) = @_;

  # Try to wait on the process.
  my $result = $self->{_os_obj}->Wait($wait_seconds? int($wait_seconds * 1000) : $blocking ? INFINITE : 0);
  # Process finished.  Grab the exit value.
  if ($result == 1) {
    delete $self->{_suspended};
    my $exit_code;
    $self->{_os_obj}->GetExitCode($exit_code);
    if ($exit_code == 256 && $self->{_called_terminateprocess}) {
      return (0, 9); # simulate SIGKILL exit status
    } else {
      return (0, $exit_code<<8);
    }
  }
  # Process still running.
  elsif ($result == 0) {
    return (2, 0);
  }
  # If we reach here, then something odd happened.
  return (0, 1<<8);
}

sub _suspend {
  $_[0]->{_os_obj}->Suspend();
}

sub _resume {
  $_[0]->{_os_obj}->Resume();
}

sub _terminate {
  my $self = shift;
  my @kill_sequence= @_ && ref $_[0] eq 'ARRAY'? @{ $_[0] } : qw( TERM 2 TERM 8 KILL 3 KILL 7 );

  # Try the kill the process several times.
  # _reap will collect the exit status of the program.
  while (@kill_sequence and $self->alive) {
    my $sig= shift @kill_sequence;
    my $delay= shift @kill_sequence;
    # TODO: fix _taskkill, then re-enable:  $sig eq 'KILL'? $self->_terminateprocess : $self->_taskkill;
    $self->_terminateprocess;
    next unless defined $delay;
    last if $self->_reap(1, $delay); # block before sending next signal
  }
}

# Use taskkill.exe as a sort of graceful SIGTERM substitute.
sub _taskkill {
  my $self = shift;
  # TODO: This doesn't work reliably.  Disabled for now, and continue to be heavy-handed
  # using TerminateProcess.  The right solution would either be to do more elaborate setup
  # to make sure the correct taskkill.exe is used (and available), or to dig much deeper
  # into Win32 API to enumerate windows or threads and send WM_QUIT, or whatever other APIs
  # processes might be watching on Windows.  That should probably be its own module.
  my $pid= $self->{_pid};
  my $out= `taskkill.exe /PID $pid`;
  # If can't run taskkill, fall back to TerminateProcess
  $self->_terminateprocess unless $? == 0;
}

# Win32 equivalent of SIGKILL is TerminateProcess()
sub _terminateprocess {
  my $self = shift;
  $self->{_os_obj}->Kill(256);  # call TerminateProcess, essentially SIGKILL
  $self->{_called_terminateprocess} = 1;
}

1;

__END__

=head1 DESCRIPTION

This module does not have a public interface.  Use L<Proc::Background>.

=head1 IMPLEMENTATION

=head2 Perl Fork Limitations

When Perl is built as a native Win32 application, the C<fork> and C<exec> are
a broken approximation of their Unix counterparts.  Calling C<fork> creates a
I<thread> instead of a process, and there is no way to exit the thread without
running Perl cleanup code, which could damage the parent in unpredictable
ways, like closing file handles.  Calling C<POSIX::_exit> will kill both
parent and child (the whole process), and even calling C<exec> in the child
still runs global destruction.  File handles are shared between parent and
child, so any file handle redirection you perform in the forked child will
affect the parent and vice versa.

In short, B<never> call C<fork> or C<exec> on native Win32 Perl.

=head2 Command Line

This module implements background processes using L<Win32::Process>, which
uses the Windows API's concepts of C<CreateProcess>, C<TerminateProces>,
C<WaitForSingleObject>, C<GetExitCode>, and so on.

Windows CreateProcess expects an executable name and a command line; breaking
the command line into an argument list is left to each individual application,
most of which use the library function L<https://docs.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-commandlinetoargvw|CommandLineToArgvW>.  This module
uses L<Win32::ShellQuote> to parse and format Windows command lines.

If you supply a single-string command line, and don't specify the executable
with the C<exe> option, this module parses the first argument from the
command line to be the 'exe' option.  It then looks for the 'exe' in
C<< $ENV{PATH} >>, and tries again with a suffix of C<< .exe >> if it didn't
find one.  If you specify the option as C<< { exe => undef } >>, this module
skips that step and passes NULL to Win32 C<CreateProcess>, which causes
Windows to parse the first argument and find the executable on its own.
(Letting Windows search for the executable is probably a better idea anyway,
and this might become the default in the future.  It only works with
Win32::Process 0.17 or later)

If you supply an array of arguments as the command, this module combines them
into a command line using C<Win32::ShellQuote/quote_native>.  The first
argument is used as the executable (unless you specified the C<'exe'> option,
like above).

=head2 Initial File Handles

When B<no handle options> are specified, the new process does B<not inherit any file handles>
of the current process.  This differs from the Unix implementation where they are all
inherited by default, but I'm leaving it this way for backward compatibility.
In other words, yes, they ought to be inherited by default, but changing that now
is more likely to break things than fix things.

If you specify B<any> of C<stdin>, C<stdout>, or C<stderr>, any handle not
specified B<will be inherited> as-is.  In other words, by indicating you are
interested in passing file handles, the default Unix behavior occurs.
If you wish to redirect a handle to NUL, set the option to C<undef>:

  stdin  => undef,     # stdin will read from NUL device
  stdout => $some_fh,  # stdout will write to a file handle
  stderr => \*STDERR,  # stderr will go to the same STDERR of the current process

You may set a file handle to a pipe, but beware, Windows does not support
non-blocking reads or writes to pipes.

=cut
