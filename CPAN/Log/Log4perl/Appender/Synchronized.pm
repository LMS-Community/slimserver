######################################################################
# Synchronized.pm -- 2003, Mike Schilli <m@perlmeister.com>
######################################################################
# Special appender employing a locking strategy to synchronize
# access.
######################################################################

###########################################
package Log::Log4perl::Appender::Synchronized;
###########################################

use strict;
use warnings;

our @ISA = qw(Log::Log4perl::Appender);

use IPC::Shareable qw(:lock);
use IPC::Semaphore;

our $CVSVERSION   = '$Revision: 1.8 $';
our ($VERSION)    = ($CVSVERSION =~ /(\d+\.\d+)/);

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        appender=> undef,
        key     => '_l4p',
        options => { create => 1, destroy => 1 },
        level   => 0,
        %options,
    };

        # Pass back the appender to be synchronized as a dependency
        # to the configuration file parser
    push @{$options{l4p_depends_on}}, $self->{appender};

        # Blow away lingering semaphores
    nuke_sem($self->{key});

    #warn "$$: IPCshareable created with $self->{key} $self->{options}\n";

    $self->{ipc_shareable} =
    tie $self->{ipc_shareable_var}, 'IPC::Shareable', 
        $self->{key}, $self->{options} or
            die "tie failed: $!";

    $self->{ipc_shareable}->shunlock();

        # Run our post_init method in the configurator after
        # all appenders have been defined to make sure the
        # appender we're syncronizing really exists
    push @{$options{l4p_post_config_subs}}, sub { $self->post_init() };

    bless $self, $class;
}

###########################################
sub log {
###########################################
    my($self, %params) = @_;
    
    $self->{ipc_shareable}->shlock();
    #warn "pid $$ entered\n";

    # Relay that to the SUPER class which needs to render the
    # message according to the appender's layout, first.
    $Log::Log4perl::caller_depth +=2;
    $self->{app}->SUPER::log(\%params, 
                             $params{log4p_category},
                             $params{log4p_level});
    $Log::Log4perl::caller_depth -=2;

    #warn "pid $$ leaves\n";
    $self->{ipc_shareable}->shunlock();
}

###########################################
sub post_init {
###########################################
    my($self) = @_;

    if(! exists $self->{appender}) {
       die "No appender defined for " . __PACKAGE__;
    }

    my $appenders = Log::Log4perl->appenders();
    my $appender = Log::Log4perl->appenders()->{$self->{appender}};

    if(! defined $appender) {
       die "Appender $self->{appender} not defined (yet) when " .
           __PACKAGE__ . " needed it";
    }

    $self->{app} = $appender;
}

###########################################
sub DESTROY {
###########################################
    my($self) = @_;
    no warnings;
    delete $self->{ipc_shareable};
    untie $self->{ipc_shareable_var};
}

###########################################
sub nuke_sem {
###########################################
# This function nukes a semaphore previously
# allocated by IPC::Shareable, which seems to
# hang in its tie() function if an old semaphore
# is still lingering around.
###########################################
    my($key) = @_;

    $key = pack   A4 => $key;
    $key = unpack i  => $key;

    my $sem = IPC::Semaphore->new($key, 3, 0);

        # Didn't exist
    unless(defined $sem) {
        return undef;
    }

    $sem->remove() || die "Cannot remove semaphore $key ($!)";

    return 1;
}

1;

__END__

=head1 NAME

    Log::Log4perl::Appender::Synchronized - Synchronizing other appenders

=head1 SYNOPSIS

    use Log::Log4perl qw(:easy);

    my $conf = qq(
    log4perl.category                   = WARN, Syncer
    
        # File appender (unsynchronized)
    log4perl.appender.Logfile           = Log::Log4perl::Appender::File
    log4perl.appender.Logfile.autoflush = 1
    log4perl.appender.Logfile.filename  = test.log
    log4perl.appender.Logfile.mode      = truncate
    log4perl.appender.Logfile.layout    = SimpleLayout
    
        # Synchronizing appender, using the file appender above
    log4perl.appender.Syncer            = Log::Log4perl::Appender::Synchronized
    log4perl.appender.Syncer.appender   = Logfile
);

    Log::Log4perl->init(\$conf);
    WARN("This message is guaranteed to be complete.");

=head1 DESCRIPTION

If multiple processes are using the same C<Log::Log4perl> appender 
without synchronization, overwrites might happen. A typical scenario
for this would be a process spawning children, each of which inherits
the parent's Log::Log4perl configuration.

Usually, you should avoid this scenario and have each child have its
own Log::Log4perl configuration, ensuring that each e.g. writes to
a different logfile.

In cases where you need additional synchronization, however, use
C<Log::Log4perl::Appender::Synchronized> as a gateway between your
loggers and your appenders. An appender itself, 
C<Log::Log4perl::Appender::Synchronized> just takes two additional
arguments:

=over 4

=item C<appender>

Specifies the name of the appender it synchronizes access to. The
appender specified must be defined somewhere in the configuration file,
not necessarily before the definition of 
C<Log::Log4perl::Appender::Synchronized>.

=item C<key>

This optional argument specifies the key for the semaphore that
C<Log::Log4perl::Appender::Synchronized> uses internally to ensure
atomic operations. It defaults to C<_l4p>. If you define more than
one C<Log::Log4perl::Appender::Synchronized> appender, it is 
important to specify different keys for them, as otherwise every
new C<Log::Log4perl::Appender::Synchronized> appender will nuke
previously defined semaphores. The maximum key length is four
characters, longer keys will be truncated to 4 characters -- 
C<mylongkey1> and C<mylongkey2> are interpreted to be the same:
C<mylo> (thanks to David Viner E<lt>dviner@yahoo-inc.comE<gt> for
pointing this out).

=back

C<Log::Log4perl::Appender::Synchronized> uses C<IPC::Shareable>
internally to perform locking with semaphores provided by the
operating system used.

=head2 Performance tips

The C<Log::Log4perl::Appender::Synchronized> serializes access to a
protected resource globally, slowing down actions otherwise performed in
parallel.

Unless specified otherwise, all instances of 
C<Log::Log4perl::Appender::Synchronized> objects in the system will
use the same global IPC key C<_l4p>.

To control access to different appender instances, it often makes sense
to define different keys for different synchronizing appenders. In this
way, Log::Log4perl serializes access to each appender instance separately:

    log4perl.category                   = WARN, Syncer1, Syncer2
    
        # File appender 1 (unsynchronized)
    log4perl.appender.Logfile1           = Log::Log4perl::Appender::File
    log4perl.appender.Logfile1.filename  = test1.log
    log4perl.appender.Logfile1.layout    = SimpleLayout
    
        # File appender 2 (unsynchronized)
    log4perl.appender.Logfile2           = Log::Log4perl::Appender::File
    log4perl.appender.Logfile2.filename  = test2.log
    log4perl.appender.Logfile2.layout    = SimpleLayout
    
        # Synchronizing appender, using the file appender above
    log4perl.appender.Syncer1            = Log::Log4perl::Appender::Synchronized
    log4perl.appender.Syncer1.appender   = Logfile1
    log4perl.appender.Syncer1.key        = l4p1

        # Synchronizing appender, using the file appender above
    log4perl.appender.Syncer2            = Log::Log4perl::Appender::Synchronized
    log4perl.appender.Syncer2.appender   = Logfile2
    log4perl.appender.Syncer2.key        = l4p2

Without the C<.key = l4p1> and C<.key = l4p2> lines, both Synchronized 
appenders would be using the default C<_l4p> key, causing unnecessary
serialization of output written to different files.

=head1 DEVELOPMENT NOTES

C<Log::Log4perl::Appender::Synchronized> is a I<composite> appender.
Unlike other appenders, it doesn't log any messages, it just
passes them on to its attached sub-appender.
For this reason, it doesn't need a layout (contrary to regular appenders).
If it defines none, messages are passed on unaltered.

Custom filters are also applied to the composite appender only.
They are I<not> applied to the sub-appender. Same applies to appender
thresholds. This behaviour might change in the future.

=head1 LEGALESE

Copyright 2003 by Mike Schilli, all rights reserved.
This program is free software, you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 AUTHOR

2003, Mike Schilli <m@perlmeister.com>
