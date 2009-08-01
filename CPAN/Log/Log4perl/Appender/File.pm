##################################################
package Log::Log4perl::Appender::File;
##################################################

our @ISA = qw(Log::Log4perl::Appender);

use warnings;
use strict;
use Log::Log4perl::Config::Watch;
use Fcntl;
use constant _INTERNAL_DEBUG => 0;

##################################################
sub new {
##################################################
    my($class, @options) = @_;

    my $self = {
        name      => "unknown name",
        umask     => undef,
        owner     => undef,
        group     => undef,
        autoflush => 1,
        syswrite  => 0,
        mode      => "append",
        binmode   => undef,
        utf8      => undef,
        recreate  => 0,
        recreate_check_interval => 30,
        recreate_check_signal   => undef,
        recreate_pid_write      => undef,
        create_at_logtime       => 0,
        header_text             => undef,
        @options,
    };

    if($self->{create_at_logtime}) {
        $self->{recreate}  = 1;
    }

    if(defined $self->{umask} and $self->{umask} =~ /^0/) {
            # umask value is a string, meant to be an oct value
        $self->{umask} = oct($self->{umask});
    }

    die "Mandatory parameter 'filename' missing" unless
        exists $self->{filename};

    bless $self, $class;

    if($self->{recreate_pid_write}) {
        print "Creating pid file",
              " $self->{recreate_pid_write}\n" if _INTERNAL_DEBUG;
        open FILE, ">$self->{recreate_pid_write}" or 
            die "Cannot open $self->{recreate_pid_write}";
        print FILE "$$\n";
        close FILE;
    }

        # This will die() if it fails
    $self->file_open() unless $self->{create_at_logtime};

    return $self;
}

##################################################
sub filename {
##################################################
    my($self) = @_;

    return $self->{filename};
}

##################################################
sub file_open {
##################################################
    my($self) = @_;

    my $arrows  = ">";
    my $sysmode = (O_CREAT|O_WRONLY);

    my $old_umask = umask();

    if($self->{mode} eq "append") {
        $arrows   = ">>";
        $sysmode |= O_APPEND;
    } elsif ($self->{mode} eq "pipe") {
        $arrows = "|";
    } else {
        $sysmode |= O_TRUNC;
    }

    my $fh = do { local *FH; *FH; };

    umask($self->{umask}) if defined $self->{umask};

    my $didnt_exist = ! -f $self->{filename};

    if($self->{syswrite}) {
        sysopen $fh, "$self->{filename}", $sysmode or
            die "Can't sysopen $self->{filename} ($!)";
    } else {
        open $fh, "$arrows$self->{filename}" or
            die "Can't open $self->{filename} ($!)";
    }

    if($didnt_exist and 
         ( defined $self->{owner} or defined $self->{group} )
      ) {

        eval { $self->perms_fix() };

        if($@) {
              # Cleanup and re-throw
            unlink $self->{filename};
            die $@;
        }
    }

    if($self->{recreate}) {
        $self->{watcher} = Log::Log4perl::Config::Watch->new(
            file           => $self->{filename},
            (defined $self->{recreate_check_interval} ?
              (check_interval => $self->{recreate_check_interval}) : ()),
            (defined $self->{recreate_check_signal} ?
              (signal => $self->{recreate_check_signal}) : ()),
        );
    }

    umask($old_umask) if defined $self->{umask};

    $self->{fh} = $fh;

    if ($self->{autoflush} and ! $self->{syswrite}) {
        my $oldfh = select $self->{fh}; 
        $| = 1; 
        select $oldfh;
    }

    if (defined $self->{binmode}) {
        binmode $self->{fh}, $self->{binmode};
    }

    if (defined $self->{utf8}) {
        binmode $self->{fh}, ":utf8";
    }

    if(defined $self->{header_text}) {
        if( $self->{header_text} !~ /\n\Z/ ) {
            $self->{header_text} .= "\n";
        }
        my $fh = $self->{fh};
        print $fh $self->{header_text};
    }
}

##################################################
sub file_close {
##################################################
    my($self) = @_;

    undef $self->{fh};
}

##################################################
sub perms_fix {
##################################################
    my($self) = @_;

    my ($uid_org, $gid_org) = (stat $self->{filename})[4,5];

    my ($uid, $gid) = ($uid_org, $gid_org);

    if(!defined $uid) {
        die "stat of $self->{filename} failed ($!)";
    }

    my $needs_fixing = 0;

    if(defined $self->{owner}) {
        $uid = $self->{owner};
        if($self->{owner} !~ /^\d+$/) {
            $uid = (getpwnam($self->{owner}))[2];
            die "Unknown user: $self->{owner}" unless defined $uid;
        }
    }

    if(defined $self->{group}) {
        $gid = $self->{group};
        if($self->{group} !~ /^\d+$/) {
            $gid = getgrnam($self->{group});

            die "Unknown group: $self->{group}" unless defined $gid;
        }
    }
    if($uid != $uid_org or $gid != $gid_org) {
        chown($uid, $gid, $self->{filename}) or 
            die "chown('$uid', '$gid') on '$self->{filename}' failed: $!";
    }
}

##################################################
sub file_switch {
##################################################
    my($self, $new_filename) = @_;

    print "Switching file from $self->{filename} to $new_filename\n" if
        _INTERNAL_DEBUG;

    $self->file_close();
    $self->{filename} = $new_filename;
    $self->file_open();
}

##################################################
sub log {
##################################################
    my($self, %params) = @_;

    if($self->{recreate}) {
        if($self->{recreate_check_signal}) {
            if($self->{watcher}->{signal_caught}) {
                $self->{watcher}->{signal_caught} = 0;
                $self->file_switch($self->{filename});
            }
        } else {
            if(!$self->{watcher} or
                $self->{watcher}->file_has_moved()) {
                $self->file_switch($self->{filename});
            }
        }
    }

    my $fh = $self->{fh};

    if($self->{syswrite}) {
        syswrite $fh, $params{message} or
            die "Cannot syswrite to '$self->{filename}': $!";
    } else {
        print $fh $params{message} or
            die "Cannot write to '$self->{filename}': $!";
    }
}

##################################################
sub DESTROY {
##################################################
    my($self) = @_;

    if ($self->{fh}) {
        my $fh = $self->{fh};
        close $fh;
    }
}

1;

__END__

=head1 NAME

Log::Log4perl::Appender::File - Log to file

=head1 SYNOPSIS

    use Log::Log4perl::Appender::File;

    my $app = Log::Log4perl::Appender::File->new(
      filename  => 'file.log',
      mode      => 'append',
      autoflush => 1,
      umask     => 0222,
    );

    $file->log(message => "Log me\n");

=head1 DESCRIPTION

This is a simple appender for writing to a file.

The C<log()> method takes a single scalar. If a newline character
should terminate the message, it has to be added explicitely.

Upon destruction of the object, the filehandle to access the
file is flushed and closed.

If you want to switch over to a different logfile, use the
C<file_switch($newfile)> method which will first close the old
file handle and then open a one to the new file specified.

=head2 OPTIONS

=over 4

=item filename

Name of the log file.

=item mode

Messages will be append to the file if C<$mode> is set to the
string C<"append">. Will clobber the file
if set to C<"clobber">. If it is C<"pipe">, the file will be understood 
as executable to pipe output to. Default mode is C<"append">.

=item autoflush

C<autoflush>, if set to a true value, triggers flushing the data
out to the file on every call to C<log()>. C<autoflush> is on by default.

=item syswrite

C<syswrite>, if set to a true value, makes sure that the appender uses
syswrite() instead of print() to log the message. C<syswrite()> usually
maps to the operating system's C<write()> function and makes sure that
no other process writes to the same log file while C<write()> is busy.
Might safe you from having to use other syncronisation measures like
semaphores (see: Synchronized appender).

=item umask

Specifies the C<umask> to use when creating the file, determining
the file's permission settings. 
If set to C<0222> (default), new
files will be created with C<rw-r--r--> permissions.
If set to C<0000>, new files will be created with C<rw-rw-rw-> permissions.

=item owner

If set, specifies that the owner of the newly created log file should
be different from the effective user id of the running process.
Only makes sense if the process is running as root. 
Both numerical user ids and user names are acceptable.

=item group

If set, specifies that the group of the newly created log file should
be different from the effective group id of the running process.
Only makes sense if the process is running as root.
Both numerical group ids and group names are acceptable.

=item utf8

If you're printing out Unicode strings, the output filehandle needs
to be set into C<:utf8> mode:

    my $app = Log::Log4perl::Appender::File->new(
      filename  => 'file.log',
      mode      => 'append',
      utf8      => 1,
    );

=item binmode

To manipulate the output filehandle via C<binmode()>, use the
binmode parameter:

    my $app = Log::Log4perl::Appender::File->new(
      filename  => 'file.log',
      mode      => 'append',
      binmode   => ":utf8",
    );

A setting of ":utf8" for C<binmode> is equivalent to specifying
the C<utf8> option (see above).

=item recreate

Normally, if a file appender logs to a file and the file gets moved to
a different location (e.g. via C<mv>), the appender's open file handle
will automatically follow the file to the new location.

This may be undesirable. When using an external logfile rotator, 
for example, the appender should create a new file under the old name
and start logging into it. If the C<recreate> option is set to a true value, 
C<Log::Log4perl::Appender::File> will do exactly that. It defaults to 
false. Check the C<recreate_check_interval> option for performance 
optimizations with this feature.

=item recreate_check_interval

In C<recreate> mode, the appender has to continuously check if the
file it is logging to is still in the same location. This check is
fairly expensive, since it has to call C<stat> on the file name and
figure out if its inode has changed. Doing this with every call
to C<log> can be prohibitively expensive. Setting it to a positive
integer value N will only check the file every N seconds. It defaults to 30.

This obviously means that the appender will continue writing to 
a moved file until the next check occurs, in the worst case
this will happen C<recreate_check_interval> seconds after the file
has been moved or deleted. If this is undesirable,
setting C<recreate_check_interval> to 0 will have the
appender check the file with I<every> call to C<log()>.

=item recreate_check_signal

In C<recreate> mode, if this option is set to a signal name
(e.g. "USR1"), the appender will recreate a missing logfile
when it receives the signal. It uses less resources than constant
polling. The usual limitation with perl's signal handling apply.
Check the FAQ for using this option with the log rotating 
utility C<newsyslog>.

=item recreate_pid_write

The popular log rotating utility C<newsyslog> expects a pid file
in order to send the application a signal when its logs have
been rotated. This option expects a path to a file where the pid
of the currently running application gets written to.
Check the FAQ for using this option with the log rotating 
utility C<newsyslog>.

=item create_at_logtime

The file appender typically creates its logfile in its constructor, i.e. 
at Log4perl C<init()> time. This is desirable for most use cases, because
it makes sure that file permission problems get detected right away, and 
not after days/weeks/months of operation when the appender suddenly needs
to log something and fails because of a problem that was obvious at
startup.

However, there are rare use cases where the file shouldn't be created
at Log4perl C<init()> time, e.g. if the appender can't be used by the current
user although it is defined in the configuration file. If you set
C<create_at_logtime> to a true value, the file appender will try to create
the file at log time. Note that this setting lets permission problems
sit undetected until log time, which might be undesirable.

=item header_text

If you want Log4perl to print a header into every newly opened
(or re-opened) logfile, set C<header_text> to either a string
or a subroutine returning a string. If the message doesn't have a newline,
a newline at the end of the header will be provided.

=back

Design and implementation of this module has been greatly inspired by
Dave Rolsky's C<Log::Dispatch> appender framework.

=head1 AUTHOR

Mike Schilli <log4perl@perlmeister.com>, 2003, 2005

=cut
