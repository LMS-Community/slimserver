package Proc::Background;

# ABSTRACT: Generic interface to Unix and Win32 background process management
require 5.004_04;

use strict;
use Exporter;
use Carp;
use Cwd;
use Scalar::Util;
@Proc::Background::ISA       = qw(Exporter);
@Proc::Background::EXPORT_OK = qw(timeout_system);

# Determine if the operating system is Windows.
my $is_windows = $^O eq 'MSWin32';
my $weaken_subref = Scalar::Util->can('weaken');

# Set up a regular expression that tests if the path is absolute and
# if it has a directory separator in it.  Also create a list of file
# extensions of append to the programs name to look for the real
# executable.
my $is_absolute_re;
my $has_dir_element_re;
my $path_sep;
my @extensions = ('');
if ($is_windows) {
  $is_absolute_re     = '^(?:(?:[a-zA-Z]:[\\\\/])|(?:[\\\\/]{2}\w+[\\\\/]))';
  $has_dir_element_re = "[\\\\/]";
  $path_sep           = "\\";
  push(@extensions, '.exe');
} else {
  $is_absolute_re     = "^/";
  $has_dir_element_re = "/";
  $path_sep           = "/";
}

# Make this class a subclass of Proc::Win32 or Proc::Unix.  Any
# unresolved method calls will go to either of these classes.
if ($is_windows) {
  require Proc::Background::Win32;
  unshift(@Proc::Background::ISA, 'Proc::Background::Win32');
} else {
  require Proc::Background::Unix;
  unshift(@Proc::Background::ISA, 'Proc::Background::Unix');
}

# Take either a relative or absolute path to a command and make it an
# absolute path.
sub _resolve_path {
  my $command = shift;

  return ( undef, 'empty command string' ) unless length $command;

  # Make the path to the progam absolute if it isn't already.  If the
  # path is not absolute and if the path contains a directory element
  # separator, then only prepend the current working to it.  If the
  # path is not absolute, then look through the PATH environment to
  # find the executable.  In all cases, look for the programs with any
  # extensions added to the original path name.
  my $path;
  if ($command =~ /$is_absolute_re/o) {
    foreach my $ext (@extensions) {
      my $p = "$command$ext";
      if (-f $p and -x _) {
        $path = $p;
        last;
      }
    }
    return defined $path? ( $path, undef ) : ( undef, "no executable program located at $command" );
  } else {
    my $cwd = cwd;
    if ($command =~ /$has_dir_element_re/o) {
      my $p1 = "$cwd$path_sep$command";
      foreach my $ext (@extensions) {
        my $p2 = "$p1$ext";
        if (-f $p2 and -x _) {
          $path = $p2;
          last;
        }
      }
    } else {
      foreach my $dir (split($is_windows ? ';' : ':', $ENV{PATH})) {
        next unless length $dir;
        $dir = "$cwd$path_sep$dir" unless $dir =~ /$is_absolute_re/o;
        my $p1 = "$dir$path_sep$command";
        foreach my $ext (@extensions) {
          my $p2 = "$p1$ext";
          if (-f $p2 and -x _) {
            $path = $p2;
            last;
          }
        }
        last if defined $path;
      }
    }
    return defined $path? ( $path, undef ) : ( undef, "cannot find absolute location of $command" );
  }
}

# Define the set of allowed options, to warn about unknown ones.
# Make it a method so subclasses can override it.
%Proc::Background::_available_options= (
  autodie => 1, command => 1, exe => 1,
  cwd => 1, stdin => 1, stdout => 1, stderr => 1,
  autoterminate => 1, die_upon_destroy => 1,
);

sub _available_options {
  return \%Proc::Background::_available_options;
}

# We want the created object to live in Proc::Background instead of
# the OS specific class so that generic method calls can be used.
sub new {
  my $class = shift;

  # The parameters are an optional %options hashref followed by any number
  # of arguments to become the @argv for exec().  If options are given, check
  # the keys for typos.
  my $options;
  if (@_ and ref $_[0] eq 'HASH') {
    $options= shift;
    my $known= $class->_available_options;
    my @unknown= grep !$known->{$_}, keys %$options;
    carp "Unknown options: ".join(', ', @unknown)
      if @unknown;
  }
  else {
    $options= {};
  }

  my $self= bless {}, $class;
  $self->{_autodie}= 1 if $options->{autodie};

  # Resolve any confusion between the 'command' option and positional @argv params.
  # Store the command in $self->{_command} so that the ::Unix and ::Win32 don't have
  # to deal with it redundantly.
  my $cmd= $options->{command};
  if (defined $cmd) {
    croak "Can't use both 'command' option and command argument list"
      if @_;
    # Can be an arrayref or a single string
    croak "command must be a non-empty string or an arrayref of strings"
      unless (ref $cmd eq 'ARRAY' && defined $cmd->[0] && length $cmd->[0])
        or (!ref $cmd && defined $cmd && length $cmd);
  }
  else {
    # Back-compat: maintain original API quirks
    confess "Proc::Background::new called with insufficient number of arguments"
      unless @_;
    return $self->_fatal('command is undefined') unless defined $_[0];

    # Interpret the parameters as an @argv if there is more than one,
    # or if the 'exe' option was given.
    $cmd= (@_ > 1 || defined $options->{exe})? [ @_ ] : $_[0];
  }

  $self->{_command}= $cmd;
  $self->{_exe}= $options->{exe} if defined $options->{exe};

  # Also back-compat: failing to fork or CreateProcess returns undef
  return unless $self->_start($options);

  # Save the start time
  $self->{_start_time} = time;

  if ($options->{autoterminate} || $options->{die_upon_destroy}) {
    $self->autoterminate(1);
  }

  return $self;
}

# The original API returns undef from the constructor in case of various errors.
# The autodie option converts these undefs into exceptions.
sub _fatal {
  my ($self, $message)= @_;
  croak $message if $self->{_autodie};
  warn "$0: $message";
  return undef;
}

sub autoterminate {
  my ($self, $newval)= @_;
  if (@_ > 1 and ($newval xor $self->{_die_upon_destroy})) {
    if ($newval) {
      # Global destruction can break this feature, because there are no guarantees
      # on which order object destructors are called.  In order to avoid that, need
      # to run all the ->die methods during END{}, and that requires weak
      # references which weren't available until 5.8
      $weaken_subref->( $Proc::Background::_die_upon_destroy{$self+0}= $self )
        if $weaken_subref;
      # could warn about it for earlier perl... but has been broken for 15 years and
      # who is still using < 5.8 anyway?
    }
    else {
      delete $Proc::Background::_die_upon_destroy{$self+0};
    }
    $self->{_die_upon_destroy}= $newval? 1 : 0;
  }
  $self->{_die_upon_destroy} || 0
}

sub DESTROY {
  my $self = shift;
  if ($self->{_die_upon_destroy}) {
    # During a mainline exit() $? is the prospective exit code from the
    # parent program. Preserve it across any waitpid() in die()
    local $?;
    $self->terminate;
    delete $Proc::Background::_die_upon_destroy{$self+0};
  }
}

END {
  # Child processes need killed before global destruction, else the
  # Win32::Process objects might get destroyed first.
  for (grep defined, values %Proc::Background::_die_upon_destroy) {
    $_->terminate;
    delete $_->{_die_upon_destroy}
  }
  %Proc::Background::_die_upon_destroy= ();
}

# Reap the child.  If the first argument is false, then return immediately.
# Else, block waiting for the process to exit.  If no second argument is
# given, wait forever, else wait for that number of seconds.
# If the wait was sucessful, then delete
# $self->{_os_obj} and set $self->{_exit_value} to the OS specific
# class return of _reap.  Return 1 if we sucessfully waited, 0
# otherwise.
sub _reap {
  my ($self, $blocking, $wait_seconds) = @_;

  return 0 unless exists($self->{_os_obj});

  # Try to wait on the process.  Use the OS dependent wait call using
  # the Proc::Background::*::waitpid call, which returns one of three
  # values.
  #   (0, exit_value)	: sucessfully waited on.
  #   (1, undef)	: process already reaped and exit value lost.
  #   (2, undef)	: process still running.
  my ($result, $exit_value) = $self->_waitpid($blocking, $wait_seconds);
  if ($result == 0 or $result == 1) {
    $self->{_exit_value} = defined($exit_value) ? $exit_value : 0;
    delete $self->{_os_obj};
    # Save the end time of the class.
    $self->{_end_time} = time;
    return 1;
  }
  return 0;
}

sub alive {
  my $self = shift;

  # If $self->{_os_obj} is not set, then the process is definitely
  # not running.
  return 0 unless exists($self->{_os_obj});

  # If $self->{_exit_value} is set, then the process has already finished.
  return 0 if exists($self->{_exit_value});

  # Try to reap the child.  If it doesn't reap, then it's alive.
  !$self->_reap(0);
}

sub suspended {
  $_[0]->{_suspended}? 1 : 0
}

sub suspend {
  my $self= shift;
  return $self->_fatal("can't suspend, process has exited")
    if !$self->{_os_obj};
  $self->{_suspended} = 1 if $self->_suspend;
  return $self->{_suspended};
}

sub resume {
  my $self= shift;
  return $self->_fatal("can't resume, process has exited")
    if !$self->{_os_obj};
  $self->{_suspended} = 0 if $self->_resume;
  return !$self->{_suspended};
}

sub wait {
  my ($self, $timeout_seconds) = @_;

  # If $self->{_exit_value} exists, then we already waited.
  return $self->{_exit_value} if exists($self->{_exit_value});

  carp "calling ->wait on a suspended process" if $self->{_suspended};

  # If neither _os_obj or _exit_value are set, then something is wrong.
  return undef if !exists($self->{_os_obj});

  # Otherwise, wait for the process to finish.
  return $self->_reap(1, $timeout_seconds)? $self->{_exit_value} : undef;
}

sub terminate { shift->die(@_) }
sub die {
  my $self = shift;

  croak "process is already terminated" if $self->{_autodie} && !$self->{_os_obj};

  # See if the process has already died.
  return 1 unless $self->alive;

  # Kill the process using the OS specific method.
  $self->_terminate(@_? ([ @_ ]) : ());

  # See if the process is still alive.
  !$self->alive;
}

sub command {
  $_[0]->{_command};
}

sub exe {
  $_[0]->{_exe}
}

sub start_time {
  $_[0]->{_start_time};
}

sub exit_code {
  return undef unless exists $_[0]->{_exit_value};
  return $_[0]->{_exit_value} >> 8;
}

sub exit_signal {
  return undef unless exists $_[0]->{_exit_value};
  return $_[0]->{_exit_value} & 127;
}

sub end_time {
  $_[0]->{_end_time};
}

sub pid {
  $_[0]->{_pid};
}

sub timeout_system {
  unless (@_ > 1) {
    confess "$0: timeout_system passed too few arguments.\n";
  }

  my $timeout = shift;
  unless ($timeout =~ /^\d+(?:\.\d*)?$/ or $timeout =~ /^\.\d+$/) {
    confess "$0: timeout_system passed a non-positive number first argument.\n";
  }

  my $proc = Proc::Background->new(@_) or return;
  my $end_time = $proc->start_time + $timeout;
  my $delay= $timeout;
  while ($delay > 0 && defined $proc->{_os_obj}) {
    last if defined $proc->wait($delay);
    # If it times out, it's likely that wait() already waited the entire duration.
    # But, if it got interrupted, there might be time remaining.
    # But, if the system clock changes, this could break horribly.  Constrain it to a sane value.
    my $t= time;
    if ($t < $end_time - $delay) { # time moved backward!
      $end_time= $t + $delay;
    } else {
      $delay= $end_time - $t;
    }
  }

  my $alive = $proc->alive;
  $proc->terminate if $alive;

  if (wantarray) {
    return ($proc->wait, $alive);
  } else {
    return $proc->wait;
  }
}

1;

__END__

=pod

=head1 SYNOPSIS

  use Proc::Background 'timeout_system';
  timeout_system($seconds, $command, $arg1, $arg2);
  timeout_system($seconds, "$command $arg1 $arg2");
  
  my $proc1 = Proc::Background->new($command, $arg1, $arg2) || die "failed";
  my $proc2 = Proc::Background->new("$command $arg1 1>&2") || die "failed";
  if ($proc1->alive) {
    $proc1->terminate;
    $proc1->wait;
  }
  say 'Ran for ' . ($proc1->end_time - $proc1->start_time) . ' seconds';
  
  Proc::Background->new({
    autodie => 1,           # Throw exceptions instead of returning undef
    cwd => 'some/path/',    # Set working directory for the new process
    exe => 'busybox',       # Specify executable different from argv[0]
    command => [ $command ] # resolve ambiguity of command line vs. argv[0]
  });
  
  # Set initial file handles
  Proc::Background->new({
    stdin => undef,                # /dev/null or NUL
    stdout => '/append/to/fname',  # will try to open()
    stderr => $log_fh,             # use existing handle
    command => \@command,
  });
  
  # Automatically kill the process if the object gets destroyed
  my $proc4 = Proc::Background->new({ autoterminate => 1 }, $command);
  $proc4    = undef;  # calls ->terminate

=head1 DESCRIPTION

This is a generic interface for placing processes in the background on
both Unix and Win32 platforms.  This module lets you start, kill, wait
on, retrieve exit values, and see if background processes still exist.

=head1 CONSTRUCTOR

=over 4

=item B<new> [options] I<command>, [I<arg>, [I<arg>, ...]]

=item B<new> [options] 'I<command> [I<arg> [I<arg> ...]]'

This creates a new background process.  Just like C<system()>, you can
supply a single string of the entire command line, or individual
arguments.  The first argument may be a hashref of named options.
To resolve the ambiguity between a command line vs. a single-element
argument list, see the C<command> option below.

By default, the constructor returns an empty list on failure,
except for a few cases of invalid arguments which call C<croak>.

For platform-specific details, see L<Proc::Background::Unix/IMPLEMENTATION>
or L<Proc::Background::Win32/IMPLEMENTATION>, but in short:

=over 7

=item Unix

This implementation uses C<fork>/C<exec>.  If you supply a single-string
command line, it is passed to the shell.  If you supply multiple arguments,
they are passed to C<exec>.  In the multi-argument case, it will also check
that the executable exists before calling C<fork>.

=item Win32

This implementation uses the L<Windows CreateProcess API|Win32::Process/METHODS>.
If you supply a single-string command line, it derives the executable by
parsing the command line and looking for the first element in the C<PATH>,
appending C<".exe"> if needed.  If you supply multiple arguments, the
first is used as the C<exe> and the command line is built using
L<Win32::ShellQuote>.  To let Windows search for the executable, pass option
C<< { exe => undef } >>.

=back

B<Options:>

=over

=item C<autodie>

This module traditionally has returned C<undef> if the child could not
be started.  Modern Perl recommends the use of exceptions for things
like this.  This option, like Perl's L<autodie> pragma, causes all
fatal errors in starting the process to die with exceptions instead of
returning undef.  (module-usage errors or other problems prior to
launching the process may still 'croak' regardless of this setting)

=item C<command>

You may specify the command as an option instead of passing the command
as a list.  A string value is considered a command line, and an arrayref
value is considered an argument list.  Using this option resolves the
ambiguity in the plain-list constructor between a command line vs.
a single-element argument list.

=item C<exe>

Specify the executable.  This can serve two purposes:
on Win32 it avoids the need to parse the commandline, and on Unix it can be
used to run an executable while passing a different value for C<$ARGV[0]>.

=item C<stdin>, C<stdout>, C<stderr>

Specify one or more overrides for the standard handles of the child.
The value should be a Perl filehandle with an underlying system C<fileno>
value.  As a convenience, you can pass C<undef> to open the C<NUL> device
on Win32 or C</dev/null> on Unix.  You may also pass a plain-scalar file
name which this module will attmept to open for reading or appending.

(for anything more elaborate, see L<IPC::Run> instead)

Note that on Win32, none of the parent's handles are inherited by default,
which is the opposite on Unix.  When you specify any of these handles on
Win32 the default will change to inherit the rest from the parent.

=item C<cwd>

Specify a path which should become the child process's current working
directory.  The path must already exist.

=item C<autoterminate>

If you pass a true value for this option, then destruction of the
Proc::Background object (going out of scope, or script-end) will kill the
process via C<< ->terminate >>.  Without this option, the child process
continues running.  C<die_upon_destroy> is an alias for this option, used
by previous versions of this module.

=back

=back

=head1 ATTRIBUTES

=over

=item B<command>

The command (string or arrayref) that was passed to the constructor.

=item B<exe>

The path to the executable that was passed as an option to the constructor,
or derived from the C<command>.

=item B<start_time>

Return the value that the Perl function time() returned when the
process was started.

=item B<pid>

Returns the process ID of the created process.  This value is saved
even if the process has already finished.

=item B<alive>

Return 1 if the process is still active, 0 otherwise.  This makes a
non-blocking call to C<wait> to check the real status of the process if it
has not been reaped yet.

=item B<suspended>

Boolean whether the process is thought to be stopped.  This does not actually
consult the operating system, and just returns the last known status from a
call to C<suspend> or C<resume>.  It is always false if C<alive> is false.

=item B<exit_code>

Returns the exit code of the process, assuming it exited cleanly.
Returns C<undef> if the process has not exited yet, and 0 if the
process exited with a signal (or TerminateProcess).  Since 0 is
ambiguous, check for C<exit_signal> first.

=item B<exit_signal>

Returns the value of the signal the process exited with, assuming it
died on a signal.  Returns C<undef> if it has not exited yet, and 0
if it did not die to a signal.

=item B<end_time>

Return the value that the Perl function time() returned when the exit
status was obtained from the process.

=item B<autoterminate>

This writeable attribute lets you enable or disable the autoterminate
option, which could also be passed to the constructor.

=back

=head1 METHODS

=over

=item B<wait>

  $exit= $proc->wait; # blocks forever
  $exit= $proc->wait($timeout_seconds); # since version 1.20

Wait for the process to exit.  Return the exit status of the command
as returned by wait() on the system.  To get the actual exit value,
divide by 256 or right bit shift by 8, regardless of the operating
system being used.  If the process never existed, this returns undef.
This function may be called multiple times even after the process has
exited and it will return the same exit status.

Since version 1.20, you may pass an optional argument of the number of
seconds to wait for the process to exit.  This may be fractional, and
if it is zero then the wait will be non-blocking.  Note that on Unix
this is implemented with L<Time::HiRes/alarm> before a call to wait(),
so it may not be compatible with scripts that use alarm() for other
purposes, or systems/perls that resume system calls after a signal.
In the event of a timeout, the return will be undef.

=item B<suspend>

Pause the process.  This returns true if the process is stopped afterward.
This throws an excetion if the process is not C<alive> and C<autodie> is
enabled.

=item B<resume>

Resume a paused process.  This returns true if the process is not stopped
afterward.  This throws an exception if the process is not C<alive> and
C<autodie> is enabled.

=item B<terminate>, B<terminate(@kill_sequence)>

Reliably try to kill the process.  Returns 1 if the process no longer
exists once B<terminate> has completed, 0 otherwise.  This will also return
1 if the process has already exited.

C<@kill_sequence> is a list of actions and seconds-to-wait for that
action to end the process.  The default is C< TERM 2 TERM 8 KILL 3 KILL 7 >.
On Unix this sends SIGTERM and SIGKILL; on Windows it just calls
TerminateProcess (graceful termination is still a TODO).

Note that C<terminate()> (formerly named C<die()>) on Proc::Background 1.10
and earlier on Unix called a sequence of:

  ->die( ( HUP => 1 )x5, ( QUIT => 1 )x5, ( INT => 1 )x5, ( KILL => 1 )x5 );

which wasn't what most people need, since SIGHUP is open to interpretation,
and QUIT is almost always immediately fatal and generates a coredump.
The new default should accomodate programs that acknowledge a second
SIGTERM, and give enough time for it to exit on a laggy system while still
not holding up the main script too much.

C<die> is preserved as an alias for C<terminate>.

This throws an exception if the process has been reaped and C<autodie> is
enabled.

=back

=head1 FUNCTIONS

=over 4

=item B<timeout_system> I<timeout>, I<command>, [I<arg>, [I<arg>...]]

=item B<timeout_system> 'I<timeout> I<command> [I<arg> [I<arg>...]]'

Run a command for I<timeout> seconds and if the process did not exit,
then kill it.

In a scalar context, B<timeout_system> returns the exit status from
the process.  In an array context, B<timeout_system> returns a two
element array, where the first element is the exist status from the
process and the second is set to 1 if the process was killed by
B<timeout_system> or 0 if the process exited by itself.

The exit status is the value returned from the wait() call.  If the
process was killed, then the return value will include the killing of
it.  To get the actual exit value, divide by 256.

If something failed in the creation of the process, the subroutine
returns an empty list in a list context, an undefined value in a
scalar context, or nothing in a void context.

=back

=head1 BUGS

The following behaviors aren't ideal, but are preserved for backward-compatibility.

=over

=item Commandline vs. Single Argv[]

C<< ->new($x) >> is treated as a command line.  In C<< ->new({ exe => $y }, $x) >>,
$x is treated as C<$ARGV[0]>.  Use C<< ->new({ command => ... }) >>
(scalar vs. arrayref) to dis-ambiguate.

=item Win32 Argv Quoting

This is a bug in Windows, not this module.  It is not possible to universally
convert an @ARGV into a commandline, because each Win32 program performs its
own command line parsing, and cmd.exe and find.exe deviate from the majority
of other executables.  Those things could be improved with hieuristics, which
this module doesn't have.

=item Win32 exe determination

If you don't specify an absolute path for option C<exe>, this module manually
searches the %PATH% looking for the executable, and is less thorough than the
native Windows shell behavior.  Use C<< { exe => undef } >> to get the naive
Windows exe search.  (but you need Win32::Process version 0.17 or newer)

=item Win32 SIGTERM

This module only supports TerminateProcess, which is equivalent to SIGKILL, not
SIGTERM.  SIGTERM could be emulated by calling taskkill.exe, or using windows
messages.  Patches welcome.

=back

=head1 SEE ALSO

=over

=item L<IPC::Run>

IPC::Run is a much more complete solution for running child processes.
It handles dozens of forms of redirection and pipe pumping, and should
probably be your first stop for any complex needs.

However, also note the very large and slightly alarming list of
limitations it lists for Win32.  Proc::Background is a much simpler design
and should be more reliable for simple needs.

=item L<Win32::ShellQuote>

If you are running on Win32, this article by Daniel Colascione helps
describe the problem you are up against for passing argument lists:
L<Everyone quotes command line arguments the wrong way|https://blogs.msdn.microsoft.com/twistylittlepassagesallalike/2011/04/23/everyone-quotes-command-line-arguments-the-wrong-way/>

This module gives you parsing / quoting per the standard
CommandLineToArgvW behavior.  But, if you need to pass arguments to be
processed by C<cmd.exe> then you need to do additional work.

=back
