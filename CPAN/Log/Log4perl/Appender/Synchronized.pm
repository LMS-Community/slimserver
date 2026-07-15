######################################################################
# Synchronized.pm -- 2003, 2007 Mike Schilli <m@perlmeister.com>
######################################################################
# Special appender employing a locking strategy to synchronize
# access.
######################################################################

###########################################
package Log::Log4perl::Appender::Synchronized;
###########################################

use strict;
use warnings;
use Log::Log4perl::Util::Semaphore;

our @ISA = qw(Log::Log4perl::Appender);

our $VERSION    = '1.53';

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        appender=> undef,
        key     => '_l4p',
        level   => 0,
        %options,
    };

    my @values = ();
    for my $param (qw(uid gid mode destroy key)) {
        push @values, $param, $self->{$param} if defined $self->{$param};
    }

    $self->{sem} = Log::Log4perl::Util::Semaphore->new(
        @values
    );

        # Pass back the appender to be synchronized as a dependency
        # to the configuration file parser
    push @{$options{l4p_depends_on}}, $self->{appender};

        # Run our post_init method in the configurator after
        # all appenders have been defined to make sure the
        # appender we're synchronizing really exists
    push @{$options{l4p_post_config_subs}}, sub { $self->post_init() };

    bless $self, $class;
}

###########################################
sub log {
###########################################
    my($self, %params) = @_;
    
    $self->{sem}->semlock();

    # Relay that to the SUPER class which needs to render the
    # message according to the appender's layout, first.
    $Log::Log4perl::caller_depth +=2;
    $self->{app}->SUPER::log(\%params, 
                             $params{log4p_category},
                             $params{log4p_level});
    $Log::Log4perl::caller_depth -=2;

    $self->{sem}->semunlock();
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

1;

__END__

=encoding utf8

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

In most cases, you won't need an external synchronisation tool like
Log::Log4perl::Appender::Synchronized at all. Log4perl's file appender, 
Log::Log4perl::Appender::File, for example, provides the C<syswrite>
mechanism for making sure that even long log lines won't interleave.
Short log lines won't interleave anyway, because the operating system
makes sure the line gets written before a task switch occurs.

In cases where you need additional synchronization, however, you can use
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

C<Log::Log4perl::Appender::Synchronized> uses Log::Log4perl::Util::Semaphore
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

=head2 Advanced configuration

To configure the underlying Log::Log4perl::Util::Semaphore module in 
a different way than with the default settings provided by 
Log::Log4perl::Appender::Synchronized, use the following parameters:

    log4perl.appender.Syncer1.destroy  = 1
    log4perl.appender.Syncer1.mode     = sub { 0775 }
    log4perl.appender.Syncer1.uid      = hugo
    log4perl.appender.Syncer1.gid      = 100

Valid options are 
C<destroy> (Remove the semaphore on exit), 
C<mode> (permissions on the semaphore), 
C<uid> (uid or user name the semaphore is owned by), 
and
C<gid> (group id the semaphore is owned by), 

Note that C<mode> is usually given in octal and therefore needs to be
specified as a perl sub {}, unless you want to calculate what 0755 means
in decimal.

Changing ownership or group settings for a semaphore will obviously only
work if the current user ID owns the semaphore already or if the current
user is C<root>. The C<destroy> option causes the current process to 
destroy the semaphore on exit. Spawned children of the process won't
inherit this behavior.

=head2 Semaphore user and group IDs with mod_perl

Setting user and group IDs is especially important when the Synchronized
appender is used with mod_perl. If Log4perl gets initialized by a startup
handler, which runs as root, and not as the user who will later use
the semaphore, the settings for uid, gid, and mode can help establish 
matching semaphore ownership and access rights.

=head1 DEVELOPMENT NOTES

C<Log::Log4perl::Appender::Synchronized> is a I<composite> appender.
Unlike other appenders, it doesn't log any messages, it just
passes them on to its attached sub-appender.
For this reason, it doesn't need a layout (contrary to regular appenders).
If it defines none, messages are passed on unaltered.

Custom filters are also applied to the composite appender only.
They are I<not> applied to the sub-appender. Same applies to appender
thresholds. This behaviour might change in the future.

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

