######################################################################
# Buffer.pm -- 2004, Mike Schilli <m@perlmeister.com>
######################################################################
# Composite appender buffering messages until a trigger condition is met.
######################################################################

###########################################
package Log::Log4perl::Appender::Buffer;
###########################################

use strict;
use warnings;

our @ISA = qw(Log::Log4perl::Appender);

our $CVSVERSION   = '$Revision: 1.2 $';
our ($VERSION)    = ($CVSVERSION =~ /(\d+\.\d+)/);

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        appender=> undef,
        buffer  => [],
        options => { 
            max_messages  => undef, 
            trigger       => undef,
            trigger_level => undef,
        },
        level   => 0,
        %options,
    };

    if($self->{trigger_level}) {
        $self->{trigger} = level_trigger($self->{trigger_level});
    }

        # Pass back the appender to be synchronized as a dependency
        # to the configuration file parser
    push @{$options{l4p_depends_on}}, $self->{appender};

        # Run our post_init method in the configurator after
        # all appenders have been defined to make sure the
        # appender we're playing 'dam' for really exists
    push @{$options{l4p_post_config_subs}}, sub { $self->post_init() };

    bless $self, $class;
}

###########################################
sub log {
###########################################
    my($self, %params) = @_;

        # Do we need to discard a message because there's already
        # max_size messages in the buffer?
    if(defined $self->{max_messages} and
       @{$self->{buffer}} == $self->{max_messages}) {
        shift @{$self->{buffer}};
    }

        # Save event time for later
    $params{log4p_logtime} = $self->{app}->{layout}->{time_function}->() if
       exists $self->{app}->{layout}->{time_function};

        # Save message and other parameters
    push @{$self->{buffer}}, \%params;

    $self->flush() if $self->{trigger}->($self, \%params);
}

###########################################
sub flush {
###########################################
    my($self) = @_;

        # Log pending messages if we have any
    for(@{$self->{buffer}}) {
            # Trick the renderer into using the original event time
        local $self->{app}->{layout}->{time_function};
        $self->{app}->{layout}->{time_function} =
                                    sub { $_->{log4p_logtime} };
        $self->{app}->SUPER::log($_,
                                 $_->{log4p_category},
                                 $_->{log4p_level});
    }

        # Empty buffer
    $self->{buffer} = [];
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
sub level_trigger {
###########################################
    my($level) = @_;

        # closure holding $level
    return sub {
        my($self, $params) = @_;

        return Log::Log4perl::Level::to_priority(
                 $params->{log4p_level}) >= 
               Log::Log4perl::Level::to_priority($level);
    };
}
    
###########################################
sub DESTROY {
###########################################
    my($self) = @_;
}

1;

__END__

=head1 NAME

    Log::Log4perl::Appender::Buffer - Buffering Appender

=head1 SYNOPSIS

    use Log::Log4perl qw(:easy);

    my $conf = qq(
    log4perl.category                  = DEBUG, Buffer

        # Regular Screen Appender
    log4perl.appender.Screen           = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.stdout    = 1
    log4perl.appender.Screen.layout    = PatternLayout
    log4perl.appender.Screen.layout.ConversionPattern = %d %p %c %m %n

        # Buffering appender, using the appender above as outlet
    log4perl.appender.Buffer               = Log::Log4perl::Appender::Buffer
    log4perl.appender.Buffer.appender      = Screen
    log4perl.appender.Buffer.trigger_level = ERROR
    );

    Log::Log4perl->init(\$conf);

    DEBUG("This message gets buffered.");
    INFO("This message gets buffered also.");

    # Time passes. Nothing happens. But then ...

    print "It's GO time!!!\n";

    ERROR("This message triggers a buffer flush.");

=head1 DESCRIPTION

C<Log::Log4perl::Appender::Buffer> takes these arguments:

=over 4

=item C<appender>

Specifies the name of the appender it buffers messages for. The
appender specified must be defined somewhere in the configuration file,
not necessarily before the definition of 
C<Log::Log4perl::Appender::Buffer>.

=item C<max_messages>

Specifies the maximum number of messages the appender will hold in
its ring buffer. C<max_messages> is optional. By default,
C<Log::Log4perl::Appender::Buffer> will I<not> limit the number of
messages buffered. This might be undesirable in long-running processes
accumulating lots of messages before a flush happens. If
C<max_messages> is set to a numeric value,
C<Log::Log4perl::Appender::Buffer> will displace old messages in its
buffer to make room if the buffer is full.

=item C<trigger_level>

If trigger_level is set to one of Log4perl's levels (see
Log::Log4perl::Level), a C<trigger> function will be defined internally
to flush the buffer if a message with a priority of $level or higher
comes along. This is just a convenience function. Defining

    log4perl.appender.Buffer.trigger_level = ERROR

is equivalent to creating a trigger function like

    log4perl.appender.Buffer.trigger = sub {   \
        my($self, $params) = @_;               \
        return $params->{log4p_level} >=       \
               $Log::Log4perl::Level::ERROR; }

See the next section for defining generic trigger functions.

=item C<trigger>

C<trigger> holds a reference to a subroutine, which
C<Log::Log4perl::Appender::Buffer> will call on every incoming message
with the same parameters as the appender's C<log()> method:

        my($self, $params) = @_;

C<$params> references a hash containing
the message priority (key C<l4p_level>), the
message category (key C<l4p_category>) and the content of the message
(key C<message>).

If the subroutine returns 1, it will trigger a flush of buffered messages.

Shortcut 

=back

=head1 DEVELOPMENT NOTES

C<Log::Log4perl::Appender::Buffer> is a I<composite> appender.
Unlike other appenders, it doesn't log any messages, it just
passes them on to its attached sub-appender.
For this reason, it doesn't need a layout (contrary to regular appenders).
If it defines none, messages are passed on unaltered.

Custom filters are also applied to the composite appender only.
They are I<not> applied to the sub-appender. Same applies to appender
thresholds. This behaviour might change in the future.

=head1 LEGALESE

Copyright 2004 by Mike Schilli, all rights reserved.
This program is free software, you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 AUTHOR

2004, Mike Schilli <m@perlmeister.com>
