##################################################
package Log::Log4perl::Appender::File;
##################################################

our @ISA = qw(Log::Log4perl::Appender);

use warnings;
use strict;
use Log::Log4perl::Config::Watch;
use Fcntl;
use File::Path;
use File::Spec::Functions qw(splitpath catpath);
use constant _INTERNAL_DEBUG => 0;
use constant SYSWRITE_UTF8_OK => ( $] < 5.024 );

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
        utf8      => 0,
        recreate  => 0,
        recreate_check_interval => 30,
        recreate_check_signal   => undef,
        recreate_pid_write      => undef,
        create_at_logtime       => 0,
        header_text             => undef,
        mkpath                  => 0,
        mkpath_umask            => 0,
        @options,
    };

    if($self->{create_at_logtime}) {
        $self->{recreate}  = 1;
    }
    for my $param ('umask', 'mkpath_umask') {
        if(defined $self->{$param} and $self->{$param} =~ /^0/) {
                # umask value is a string, meant to be an oct value
            $self->{$param} = oct($self->{$param});
        }
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

    print "Calling syswrite_encoder\n" if _INTERNAL_DEBUG;

    $self->{syswrite_encoder} = $self->syswrite_encoder();

    print "syswrite_encoder returned\n" if _INTERNAL_DEBUG;

        # This will die() if it fails
    $self->file_open() unless $self->{create_at_logtime};

    return $self;
}

##################################################
sub syswrite_encoder {
##################################################
    my($self) = @_;

    if( !SYSWRITE_UTF8_OK and $self->{syswrite} and $self->{utf8} ) {
        print "Requiring Encode\n" if _INTERNAL_DEBUG;
        eval { require Encode };
        print "Requiring Encode returned: $@\n" if _INTERNAL_DEBUG;

        if( $@ ) {
            die "syswrite and utf8 requires Encode.pm";
        } else {
            return sub { Encode::encode_utf8($_[0]) };
        }
    }

    return undef;
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


    if($self->{mode} eq "append") {
        $arrows   = ">>";
        $sysmode |= O_APPEND;
    } elsif ($self->{mode} eq "pipe") {
        $arrows = "|";
    } else {
        $sysmode |= O_TRUNC;
    }

    my $fh = do { local *FH; *FH; };


    my $didnt_exist = ! -e $self->{filename};
    if($didnt_exist && $self->{mkpath}) {
        my ($volume, $path, $file) = splitpath($self->{filename});
        if($path ne '' && !-e $path) {
            my $old_umask = umask($self->{mkpath_umask}) if defined $self->{mkpath_umask};
            my $options = {};
            foreach my $param (qw(owner group) ) {
                $options->{$param} = $self->{$param} if defined $self->{$param};
            }
            eval {
                mkpath(catpath($volume, $path, ''),$options);
            };
            umask($old_umask) if defined $old_umask;
            die "Can't create path ${path} ($!)" if $@;
        }
    }

    my $old_umask = umask($self->{umask}) if defined $self->{umask};

    eval {
        if($self->{syswrite}) {
            sysopen $fh, "$self->{filename}", $sysmode or
                die "Can't sysopen $self->{filename} ($!)";
        } else {
            open $fh, "$arrows$self->{filename}" or
                die "Can't open $self->{filename} ($!)";
        }
    };
    umask($old_umask) if defined $old_umask;
    die $@ if $@;

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

    $self->{fh} = $fh;

    if ($self->{autoflush} and ! $self->{syswrite}) {
        my $oldfh = select $self->{fh};
        $| = 1;
        select $oldfh;
    }

    if (defined $self->{binmode}) {
        binmode $self->{fh}, $self->{binmode};
    }

    if ($self->{utf8}) {
          # older perls can handle syswrite+utf8 just fine
        if(SYSWRITE_UTF8_OK or !$self->{syswrite}) {
            binmode $self->{fh}, ":utf8";
        }
    }

    if(defined $self->{header_text}) {
        if( $self->{header_text} !~ /\n\Z/ ) {
            $self->{header_text} .= "\n";
        }

          # quick and dirty print/syswrite without the usual
          # log() recreate magic.
        local $self->{recreate} = 0;
        $self->log( message => $self->{header_text} );
    }
}

##################################################
sub file_close {
##################################################
    my($self) = @_;

    if(defined $self->{fh}) {
        $self->close_with_care( $self->{ fh } );
    }

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

    # Warning: this function gets called by file_open() which assumes 
    # it can use it as a simple print/syswrite wrapper by temporary 
    # disabling the 'recreate' entry. Add anything fancy here and 
    # fix up file_open() accordingly.

    if($self->{recreate}) {
        if($self->{recreate_check_signal}) {
            if(!$self->{watcher} or
               $self->{watcher}->{signal_caught}) {
                $self->file_switch($self->{filename});
                $self->{watcher}->{signal_caught} = 0;
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
         my $rc = 
           syswrite( $fh, 
               $self->{ syswrite_encoder } ?
                 $self->{ syswrite_encoder }->($params{message}) :
                 $params{message} );

         if(!defined $rc) {
             die "Cannot syswrite to '$self->{filename}': $!";
         }
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
        $self->close_with_care( $fh );
    }
}

###########################################
sub close_with_care {
###########################################
    my( $self, $fh ) = @_;

    my $prev_rc = $?;

    my $rc = close $fh;

      # [rt #84723] If a sig handler is reaping the child generated
      # by close() internally before close() gets to it, it'll
      # result in a weird (but benign) error that we don't want to
      # expose to the user.
    if( !$rc ) {
        if( $self->{ mode } eq "pipe" and
            $!{ ECHILD } ) {
            if( $Log::Log4perl::CHATTY_DESTROY_METHODS ) {
                warn "$$: pipe closed with ECHILD error -- guess that's ok";
            }
            $? = $prev_rc;
        } else {
            warn "Can't close $self->{filename} ($!)";
        }
    }

    return $rc;
}

1;

__END__

=encoding utf8

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
should terminate the message, it has to be added explicitly.

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
Might safe you from having to use other synchronisation measures like
semaphores (see: Synchronized appender).

=item umask

Specifies the C<umask> to use when creating the file, determining
the file's permission settings.
If set to C<0022> (default), new
files will be created with C<rw-r--r--> permissions.
If set to C<0000>, new files will be created with C<rw-rw-rw-> permissions.

=item owner

If set, specifies that the owner of the newly created log file should
be different from the effective user id of the running process.
Only makes sense if the process is running as root.
Both numerical user ids and user names are acceptable.
Log4perl does not attempt to change the ownership of I<existing> files.

=item group

If set, specifies that the group of the newly created log file should
be different from the effective group id of the running process.
Only makes sense if the process is running as root.
Both numerical group ids and group names are acceptable.
Log4perl does not attempt to change the group membership of I<existing> files.

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

=item mkpath

If this this option is set to true,
the directory path will be created if it does not exist yet.

=item mkpath_umask

Specifies the C<umask> to use when creating the directory, determining
the directory's permission settings.
If set to C<0022> (default), new
directory will be created with C<rwxr-xr-x> permissions.
If set to C<0000>, new directory will be created with C<rwxrwxrwx> permissions.

=back

Design and implementation of this module has been greatly inspired by
Dave Rolsky's C<Log::Dispatch> appender framework.

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

