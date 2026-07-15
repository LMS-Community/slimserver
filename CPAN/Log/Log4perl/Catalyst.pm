package Log::Log4perl::Catalyst;

use strict;
use Log::Log4perl qw(:levels);
use Log::Log4perl::Logger;

our $VERSION                  = '1.53';
our $CATALYST_APPENDER_SUFFIX = "catalyst_buffer";
our $LOG_LEVEL_ADJUSTMENT     = 1;

init();

##################################################
sub init {
##################################################

    my @levels = qw[ trace debug info warn error fatal ];

    Log::Log4perl->wrapper_register(__PACKAGE__);

    for my $level (@levels) {
        no strict 'refs';

        *{$level} = sub {
            my ( $self, @message ) = @_;

            local $Log::Log4perl::caller_depth =
                  $Log::Log4perl::caller_depth +
                     $LOG_LEVEL_ADJUSTMENT;

            my $logger = Log::Log4perl->get_logger();
            $logger->$level(@message);
            return 1;
        };

        *{"is_$level"} = sub {
            my ( $self, @message ) = @_;

            local $Log::Log4perl::caller_depth =
                  $Log::Log4perl::caller_depth +
                     $LOG_LEVEL_ADJUSTMENT;

            my $logger = Log::Log4perl->get_logger();
            my $func   = "is_" . $level;
            return $logger->$func;
        };
    }
}

##################################################
sub new {
##################################################
    my($class, $config, %options) = @_;

    my $self = {
        autoflush   => 0,
        abort       => 0,
        watch_delay => 0,
        %options,
    };

    if( !Log::Log4perl->initialized() ) {
        if( defined $config ) {
            if( $self->{watch_delay} ) {
                Log::Log4perl::init_and_watch( $config, $self->{watch_delay} );
            } else {
                Log::Log4perl::init( $config );
            }
        } else {
             Log::Log4perl->easy_init({
                 level  => $DEBUG,
                 layout => "[%d] [catalyst] [%p] %m%n",
             });
        }
    }

      # Unless we have autoflush, Catalyst likes to buffer all messages
      # until it calls flush(). This is somewhat unusual for Log4perl,
      # but we just put an army of buffer appenders in front of all 
      # appenders defined in the system.

    if(! $options{autoflush} ) {
        for my $appender (values %Log::Log4perl::Logger::APPENDER_BY_NAME) {
            next if $appender->{name} =~ /_$CATALYST_APPENDER_SUFFIX$/;

            # put a buffering appender in front of every appender
            # defined so far

            my $buf_app_name = "$appender->{name}_$CATALYST_APPENDER_SUFFIX";

            my $buf_app = Log::Log4perl::Appender->new(
                'Log::Log4perl::Appender::Buffer',
                name       => $buf_app_name,
                appender   => $appender->{name},
                trigger    => sub { 0 },    # only trigger on explicit flush()
            );

            Log::Log4perl->add_appender($buf_app);
            $buf_app->post_init();
            $buf_app->composite(1);

            # Point all loggers currently connected to the previously defined
            # appenders to the chained buffer appenders instead.

            foreach my $logger (
                           values %$Log::Log4perl::Logger::LOGGERS_BY_NAME){
                if(defined $logger->remove_appender( $appender->{name}, 0, 1)) {
                    $logger->add_appender( $buf_app );
                }
            }
        }
    }

    bless $self, $class;

    return $self;
}

##################################################
sub _flush {
##################################################
    my ($self) = @_;

    for my $appender (values %Log::Log4perl::Logger::APPENDER_BY_NAME) {
        next if $appender->{name} !~ /_$CATALYST_APPENDER_SUFFIX$/;

        if ($self->abort) {
            $appender->{appender}{buffer} = [];
        }
        else {
            $appender->flush();
        }
    }

    $self->abort(undef);
}

##################################################
sub abort {
##################################################
    my $self = shift;

    $self->{abort} = $_[0] if @_;

    return $self->{abort};
}

##################################################
sub levels {
##################################################
      # stub function, until we have something meaningful
    return 0;
}

##################################################
sub enable {
##################################################
      # stub function, until we have something meaningful
    return 0;
}

##################################################
sub disable {
##################################################
      # stub function, until we have something meaningful
    return 0;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Catalyst - Log::Log4perl Catalyst Module

=head1 SYNOPSIS

In your main Catalyst application module:

  use Log::Log4perl::Catalyst;

    # Either make Log4perl act like the Catalyst default logger:
  __PACKAGE__->log(Log::Log4perl::Catalyst->new());

    # or use a Log4perl configuration file, utilizing the full 
    # functionality of Log4perl
  __PACKAGE__->log(Log::Log4perl::Catalyst->new('l4p.conf'));
  
... and then sprinkle logging statements all over any code executed
by Catalyst:

    $c->log->debug("This is using log4perl!");

=head1 DESCRIPTION

This module provides Log4perl functions to Catalyst applications. It was
inspired by Catalyst::Log::Log4perl on CPAN, but has been completely 
rewritten and uses a different approach to unite Catalyst and Log4perl.

Log4perl provides loggers, usually associated with the current
package, which can then be remote-controlled by a central
configuration. This means that if you have a controller function like

    package MyApp::Controller::User;

    sub add : Chained('base'): PathPart('add'): Args(0) {
        my ( $self, $c ) = @_;

        $c->log->info("Adding a user");
        # ...
    }

Level-based control is available via the following methods:

   $c->log->debug("Reading configuration");
   $c->log->info("Adding a user");
   $c->log->warn("Can't read configuration ($!)");
   $c->log->error("Can't add user ", $user);
   $c->log->fatal("Database down, aborting request");

But that's not all, Log4perl is much more powerful.

The logging statement can be suppressed or activated based on a Log4perl
file that looks like

      # All MyApp loggers opened up for DEBUG and above
    log4perl.logger.MyApp = DEBUG, Screen
    # ...

or 

      # All loggers block messages below INFO
    log4perl.logger=INFO, Screen
    # ...

respectively. See the Log4perl manpage on how to perform fine-grained 
log-level and location filtering, and how to forward messages not only
to the screen or to log files, but also to databases, email appenders,
and much more.

Also, you can change the message layout. For example if you want
to know where a particular statement was logged, turn on file names and 
line numbers:

    # Log4perl configuration file
    # ...
    log4perl.appender.Screen.layout.ConversionPattern = \
          %F{1}-%L: %p %m%n

Messages will then look like

    MyApp.pm-1869: INFO Saving user profile for user "wonko"

Or want to log a request's IP address with every log statement? No problem 
with Log4perl, just call

    Log::Log4perl::MDC->put( "ip", $c->req->address() );

at the beginning of the request cycle and use

    # Log4perl configuration file
    # ...
    log4perl.appender.Screen.layout.ConversionPattern = \
          [%d]-%X{ip} %F{1}-%L: %p %m%n

as a Log4perl layout. Messages will look like

    [2010/02/22 23:25:55]-123.122.108.10 MyApp.pm-1953: INFO Reading profile for user "wonko"

Again, check the Log4perl manual page, there's a plethora of configuration
options.

=head1 METHODS

=over 4

=item new($config, [%options])

If called without parameters, new() initializes Log4perl in a way 
so that messages are logged similarly to Catalyst's default logging
mechanism. If you provide a configuration, either the name of a configuration
file or a reference to a scalar string containing the configuration, it
will call Log4perl with these parameters.

The second (optional) parameter is a list of key/value pairs:

  'autoflush'   =>  1   # Log without buffering ('abort' not supported)
  'watch_delay' => 30   # If set, use L<Log::Log4perl>'s init_and_watch

=item _flush()

Flushes the cache.

=item abort($abort)

Clears the logging system's internal buffers without logging anything.

=back

=head2 Using :easy Macros with Catalyst

If you're tired of typing

    $c->log->debug("...");

and would prefer to use Log4perl's convenient :easy mode macros like

    DEBUG "...";

then just pull those macros in via Log::Log4perl's :easy mode and start
cranking:

    use Log::Log4perl qw(:easy);

      # ... use macros later on
    sub base :Chained('/') :PathPart('apples') :CaptureArgs(0) {
        my ( $self, $c ) = @_;

        DEBUG "Handling apples";
    }

Note the difference between Log4perl's initialization in Catalyst, which
uses the Catalyst-specific Log::Log4perl::Catalyst module (top of this
page), and making use of Log4perl's loggers with the standard 
Log::Log4perl loggers and macros. While initialization requires Log4perl
to perform dark magic to conform to Catalyst's different logging strategy,
obtaining Log4perl's logger objects or calling its macros are unchanged.

Instead of using Catalyst's way of referencing the "context" object $c to 
obtain logger references via its log() method, you can just as well use 
Log4perl's get_logger() or macros to access Log4perl's logger singletons. 
The result is the same.

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

