package Log::Log4perl::Config::Watch;

use constant _INTERNAL_DEBUG => 0;

our $NEXT_CHECK_TIME;
our $SIGNAL_CAUGHT;

our $L4P_TEST_CHANGE_DETECTED;
our $L4P_TEST_CHANGE_CHECKED;

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = { file            => "",
                 check_interval  => 30,
                 l4p_internal    => 0,
                 signal          => undef,
                 %options,
                 _last_checked_at => 0,
                 _last_timestamp  => 0,
               };

    bless $self, $class;

    if($self->{signal}) {
            # We're in signal mode, set up the handler
        print "Setting up signal handler for '$self->{signal}'\n" if
            _INTERNAL_DEBUG;

        # save old signal handlers; they belong to other appenders or
        # possibly something else in the consuming application
        my $old_sig_handler = $SIG{$self->{signal}};
        $SIG{$self->{signal}} = sub { 
            print "Caught $self->{signal} signal\n" if _INTERNAL_DEBUG;
            $self->force_next_check();
            $old_sig_handler->(@_) if $old_sig_handler and ref $old_sig_handler eq 'CODE';
        };
            # Reset the marker. The handler is going to modify it.
        $self->{signal_caught} = 0;
        $SIGNAL_CAUGHT = 0 if $self->{l4p_internal};
    } else {
            # Just called to initialize
        $self->change_detected(undef, 1);
        $self->file_has_moved(undef, 1);
    }

    return $self;
}

###########################################
sub force_next_check {
###########################################
    my($self) = @_;

    $self->{signal_caught}   = 1;
    $self->{next_check_time} = 0;

    if( $self->{l4p_internal} ) {
        $SIGNAL_CAUGHT = 1;
        $NEXT_CHECK_TIME = 0;
    }
}

###########################################
sub force_next_check_reset {
###########################################
    my($self) = @_;

    $self->{signal_caught} = 0;
    $SIGNAL_CAUGHT = 0 if $self->{l4p_internal};
}

###########################################
sub file {
###########################################
    my($self) = @_;

    return $self->{file};
}

###########################################
sub signal {
###########################################
    my($self) = @_;

    return $self->{signal};
}

###########################################
sub check_interval {
###########################################
    my($self) = @_;

    return $self->{check_interval};
}

###########################################
sub file_has_moved {
###########################################
    my($self, $time, $force) = @_;

    my $task = sub {
        my @stat = stat($self->{file});

        my $has_moved = 0;

        if(! $stat[0]) {
            # The file's gone, obviously it got moved or deleted.
            print "File is gone\n" if _INTERNAL_DEBUG;
            return 1;
        }

        my $current_inode = "$stat[0]:$stat[1]";
        print "Current inode: $current_inode\n" if _INTERNAL_DEBUG;

        if(exists $self->{_file_inode} and 
            $self->{_file_inode} ne $current_inode) {
            print "Inode changed from $self->{_file_inode} to ",
                  "$current_inode\n" if _INTERNAL_DEBUG;
            $has_moved = 1;
        }

        $self->{_file_inode} = $current_inode;
        return $has_moved;
    };

    return $self->check($time, $task, $force);
}

###########################################
sub change_detected {
###########################################
    my($self, $time, $force) = @_;

    my $task = sub {
        my @stat = stat($self->{file});
        my $new_timestamp = $stat[9];

        $L4P_TEST_CHANGE_CHECKED = 1;

        if(! defined $new_timestamp) {
            if($self->{l4p_internal}) {
                # The file is gone? Let it slide, we don't want L4p to re-read
                # the config now, it's gonna die.
                return undef;
            }
            $L4P_TEST_CHANGE_DETECTED = 1;
            return 1;
        }

        if($new_timestamp > $self->{_last_timestamp}) {
            $self->{_last_timestamp} = $new_timestamp;
            print "Change detected (file=$self->{file} store=$new_timestamp)\n"
                  if _INTERNAL_DEBUG;
            $L4P_TEST_CHANGE_DETECTED = 1;
            return 1; # Has changed
        }
           
        print "$self->{file} unchanged (file=$new_timestamp ",
              "stored=$self->{_last_timestamp})!\n" if _INTERNAL_DEBUG;
        return "";  # Hasn't changed
    };

    return $self->check($time, $task, $force);
}

###########################################
sub check {
###########################################
    my($self, $time, $task, $force) = @_;

    $time = time() unless defined $time;

    if( $self->{signal_caught} or $SIGNAL_CAUGHT ) {
       $force = 1;
       $self->force_next_check_reset();
       print "Caught signal, forcing check\n" if _INTERNAL_DEBUG;

    }

    print "Soft check (file=$self->{file} time=$time)\n" if _INTERNAL_DEBUG;

        # Do we need to check?
    if(!$force and
       $self->{_last_checked_at} + 
       $self->{check_interval} > $time) {
        print "No need to check\n" if _INTERNAL_DEBUG;
        return ""; # don't need to check, return false
    }
       
    $self->{_last_checked_at} = $time;

    # Set global var for optimizations in case we just have one watcher
    # (like in Log::Log4perl)
    $self->{next_check_time} = $time + $self->{check_interval};
    $NEXT_CHECK_TIME = $self->{next_check_time} if $self->{l4p_internal};

    print "Hard check (file=$self->{file} time=$time)\n" if _INTERNAL_DEBUG;
    return $task->($time);
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Config::Watch - Detect file changes

=head1 SYNOPSIS

    use Log::Log4perl::Config::Watch;

    my $watcher = Log::Log4perl::Config::Watch->new(
                          file            => "/data/my.conf",
                          check_interval  => 30,
                  );

    while(1) {
        if($watcher->change_detected()) {
            print "Change detected!\n";
        }
        sleep(1);
    }

=head1 DESCRIPTION

This module helps detecting changes in files. Although it comes with the
C<Log::Log4perl> distribution, it can be used independently.

The constructor defines the file to be watched and the check interval 
in seconds. Subsequent calls to C<change_detected()> will 

=over 4

=item *

return a false value immediately without doing physical file checks
if C<check_interval> hasn't elapsed.

=item *

perform a physical test on the specified file if the number
of seconds specified in C<check_interval> 
have elapsed since the last physical check. If the file's modification
date has changed since the last physical check, it will return a true 
value, otherwise a false value is returned.

=back

Bottom line: C<check_interval> allows you to call the function
C<change_detected()> as often as you like, without paying the performing
a significant performance penalty because file system operations 
are being performed (however, you pay the price of not knowing about
file changes until C<check_interval> seconds have elapsed).

The module clearly distinguishes system time from file system time. 
If your (e.g. NFS mounted) file system is off by a constant amount
of time compared to the executing computer's clock, it'll just
work fine.

To disable the resource-saving delay feature, just set C<check_interval> 
to 0 and C<change_detected()> will run a physical file test on
every call.

If you already have the current time available, you can pass it
on to C<change_detected()> as an optional parameter, like in

    change_detected($time)

which then won't trigger a call to C<time()>, but use the value
provided.

=head2 SIGNAL MODE

Instead of polling time and file changes, C<new()> can be instructed 
to set up a signal handler. If you call the constructor like

    my $watcher = Log::Log4perl::Config::Watch->new(
                          file    => "/data/my.conf",
                          signal  => 'HUP'
                  );

then a signal handler will be installed, setting the object's variable 
C<$self-E<gt>{signal_caught}> to a true value when the signal arrives.
Comes with all the problems that signal handlers go along with.

=head2 TRIGGER CHECKS

To trigger a physical file check on the next call to C<change_detected()>
regardless if C<check_interval> has expired or not, call

    $watcher->force_next_check();

on the watcher object.

=head2 DETECT MOVED FILES

The watcher can also be used to detect files that have moved. It will 
not only detect if a watched file has disappeared, but also if it has
been replaced by a new file in the meantime.

    my $watcher = Log::Log4perl::Config::Watch->new(
        file           => "/data/my.conf",
        check_interval => 30,
    );

    while(1) {
        if($watcher->file_has_moved()) {
            print "File has moved!\n";
        }
        sleep(1);
    }

The parameters C<check_interval> and C<signal> limit the number of physical 
file system checks, similarily as with C<change_detected()>.

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

