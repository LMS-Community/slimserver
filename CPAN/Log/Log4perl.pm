##################################################
package Log::Log4perl;
##################################################

END { local($?); Log::Log4perl::Logger::cleanup(); }

use 5.006;
use strict;
use warnings;

use Carp;

use Log::Log4perl::Util;
use Log::Log4perl::Logger;
use Log::Log4perl::Level;
use Log::Log4perl::Config;
use Log::Log4perl::Appender;

our $VERSION = '1.57';

   # set this to '1' if you're using a wrapper
   # around Log::Log4perl
our $caller_depth = 0;

    #this is a mapping of convenience names to opcode masks used in
    #$ALLOWED_CODE_OPS_IN_CONFIG_FILE below
our %ALLOWED_CODE_OPS = (
    'safe'        => [ ':browse' ],
    'restrictive' => [ ':default' ],
);

our %WRAPPERS_REGISTERED = map { $_ => 1 } qw(Log::Log4perl);

    #set this to the opcodes which are allowed when
    #$ALLOW_CODE_IN_CONFIG_FILE is set to a true value
    #if undefined, there are no restrictions on code that can be
    #excuted
our @ALLOWED_CODE_OPS_IN_CONFIG_FILE;

    #this hash lists things that should be exported into the Safe
    #compartment.  The keys are the package the symbol should be
    #exported from and the values are array references to the names
    #of the symbols (including the leading type specifier)
our %VARS_SHARED_WITH_SAFE_COMPARTMENT = (
    main => [ '%ENV' ],
);

    #setting this to a true value will allow Perl code to be executed
    #within the config file.  It works in conjunction with
    #$ALLOWED_CODE_OPS_IN_CONFIG_FILE, which if defined restricts the
    #opcodes which can be executed using the 'Safe' module.
    #setting this to a false value disables code execution in the
    #config file
our $ALLOW_CODE_IN_CONFIG_FILE = 1;

    #arrays in a log message will be joined using this character,
    #see Log::Log4perl::Appender::DBI
our $JOIN_MSG_ARRAY_CHAR = '';

    #version required for XML::DOM, to enable XML Config parsing
    #and XML Config unit tests
our $DOM_VERSION_REQUIRED = '1.29'; 

our $CHATTY_DESTROY_METHODS = 0;

our $LOGDIE_MESSAGE_ON_STDERR = 1;
our $LOGEXIT_CODE             = 1;
our %IMPORT_CALLED;

our $EASY_CLOSURES = {};

  # to throw refs as exceptions via logcarp/confess, turn this off
our $STRINGIFY_DIE_MESSAGE = 1;

use constant _INTERNAL_DEBUG => 0;

##################################################
sub import {
##################################################
    my($class) = shift;

    my $caller_pkg = caller();

    return 1 if $IMPORT_CALLED{$caller_pkg}++;

    my(%tags) = map { $_ => 1 } @_;

        # Lazy man's logger
    if(exists $tags{':easy'}) {
        $tags{':levels'} = 1;
        $tags{':nowarn'} = 1;
        $tags{'get_logger'} = 1;
    }

    if(exists $tags{':no_extra_logdie_message'}) {
        $Log::Log4perl::LOGDIE_MESSAGE_ON_STDERR = 0;
        delete $tags{':no_extra_logdie_message'};
    }

    if(exists $tags{get_logger}) {
        # Export get_logger into the calling module's 
        no strict qw(refs);
        *{"$caller_pkg\::get_logger"} = *get_logger;

        delete $tags{get_logger};
    }

    if(exists $tags{':levels'}) {
        # Export log levels ($DEBUG, $INFO etc.) from Log4perl::Level
        for my $key (keys %Log::Log4perl::Level::PRIORITY) {
            my $name  = "$caller_pkg\::$key";
               # Need to split this up in two lines, or CVS will
               # mess it up.
            my $value = $Log::Log4perl::Level::PRIORITY{
              $key};
            no strict qw(refs);
            *{"$name"} = \$value;
        } 

        delete $tags{':levels'};
    }

        # Lazy man's logger
    if(exists $tags{':easy'}) {
        delete $tags{':easy'};

            # Define default logger object in caller's package
        my $logger = get_logger("$caller_pkg");
        
            # Define DEBUG, INFO, etc. routines in caller's package
        for(qw(TRACE DEBUG INFO WARN ERROR FATAL ALWAYS)) {
            my $level   = $_;
            $level = "OFF" if $level eq "ALWAYS";
            my $lclevel = lc($_);
            easy_closure_create($caller_pkg, $_, sub {
                Log::Log4perl::Logger::init_warn() unless 
                    $Log::Log4perl::Logger::INITIALIZED or
                    $Log::Log4perl::Logger::NON_INIT_WARNED;
                $logger->{$level}->($logger, @_, $level);
            }, $logger);
        }

            # Define LOGCROAK, LOGCLUCK, etc. routines in caller's package
        for(qw(LOGCROAK LOGCLUCK LOGCARP LOGCONFESS)) {
            my $method = "Log::Log4perl::Logger::" . lc($_);

            easy_closure_create($caller_pkg, $_, sub {
                unshift @_, $logger;
                goto &$method;
            }, $logger);
        }

            # Define LOGDIE, LOGWARN
         easy_closure_create($caller_pkg, "LOGDIE", sub {
             Log::Log4perl::Logger::init_warn() unless 
                     $Log::Log4perl::Logger::INITIALIZED or
                     $Log::Log4perl::Logger::NON_INIT_WARNED;
             $logger->{FATAL}->($logger, @_, "FATAL");
             $Log::Log4perl::LOGDIE_MESSAGE_ON_STDERR ?
                 CORE::die(Log::Log4perl::Logger::callerline(join '', @_)) :
                 exit $Log::Log4perl::LOGEXIT_CODE;
         }, $logger);

         easy_closure_create($caller_pkg, "LOGEXIT", sub {
            Log::Log4perl::Logger::init_warn() unless 
                    $Log::Log4perl::Logger::INITIALIZED or
                    $Log::Log4perl::Logger::NON_INIT_WARNED;
            $logger->{FATAL}->($logger, @_, "FATAL");
            exit $Log::Log4perl::LOGEXIT_CODE;
         }, $logger);

        easy_closure_create($caller_pkg, "LOGWARN", sub {
            Log::Log4perl::Logger::init_warn() unless 
                    $Log::Log4perl::Logger::INITIALIZED or
                    $Log::Log4perl::Logger::NON_INIT_WARNED;
            $logger->{WARN}->($logger, @_, "WARN");
            CORE::warn(Log::Log4perl::Logger::callerline(join '', @_))
                if $Log::Log4perl::LOGDIE_MESSAGE_ON_STDERR;
        }, $logger);
    }

    if(exists $tags{':nowarn'}) {
        $Log::Log4perl::Logger::NON_INIT_WARNED = 1;
        delete $tags{':nowarn'};
    }

    if(exists $tags{':nostrict'}) {
        $Log::Log4perl::Logger::NO_STRICT = 1;
        delete $tags{':nostrict'};
    }

    if(exists $tags{':resurrect'}) {
        my $FILTER_MODULE = "Filter::Util::Call";
        if(! Log::Log4perl::Util::module_available($FILTER_MODULE)) {
            die "$FILTER_MODULE required with :resurrect" .
                "(install from CPAN)";
        }
        eval "require $FILTER_MODULE" or die "Cannot pull in $FILTER_MODULE";
        Filter::Util::Call::filter_add(
            sub {
                my($status);
                s/^\s*###l4p// if
                    ($status = Filter::Util::Call::filter_read()) > 0;
                $status;
                });
        delete $tags{':resurrect'};
    }

    if(keys %tags) {
        # We received an Option we couldn't understand.
        die "Unknown Option(s): @{[keys %tags]}";
    }
}

##################################################
sub initialized {
##################################################
    return $Log::Log4perl::Logger::INITIALIZED;
}

##################################################
sub new {
##################################################
    die "THIS CLASS ISN'T FOR DIRECT USE. " .
        "PLEASE CHECK 'perldoc " . __PACKAGE__ . "'.";
}

##################################################
sub reset { # Mainly for debugging/testing
##################################################
    # Delegate this to the logger ...
    return Log::Log4perl::Logger->reset();
}

##################################################
sub init_once { # Call init only if it hasn't been
                # called yet.
##################################################
    init(@_) unless $Log::Log4perl::Logger::INITIALIZED;
}

##################################################
sub init { # Read the config file
##################################################
    my($class, @args) = @_;

    #woops, they called ::init instead of ->init, let's be forgiving
    if ($class ne __PACKAGE__) {
        unshift(@args, $class);
    }

    # Delegate this to the config module
    return Log::Log4perl::Config->init(@args);
}

##################################################
sub init_and_watch { 
##################################################
    my($class, @args) = @_;

    #woops, they called ::init instead of ->init, let's be forgiving
    if ($class ne __PACKAGE__) {
        unshift(@args, $class);
    }

    # Delegate this to the config module
    return Log::Log4perl::Config->init_and_watch(@args);
}


##################################################
sub easy_init { # Initialize the root logger with a screen appender
##################################################
    my($class, @args) = @_;

    # Did somebody call us with Log::Log4perl::easy_init()?
    if(ref($class) or $class =~ /^\d+$/) {
        unshift @args, $class;
    }

    # Reset everything first
    Log::Log4perl->reset();

    my @loggers = ();

    my %default = ( level    => $DEBUG,
                    file     => "STDERR",
                    utf8     => undef,
                    category => "",
                    layout   => "%d %m%n",
                  );

    if(!@args) {
        push @loggers, \%default;
    } else {
        for my $arg (@args) {
            if($arg =~ /^\d+$/) {
                my %logger = (%default, level => $arg);
                push @loggers, \%logger;
            } elsif(ref($arg) eq "HASH") {
                my %logger = (%default, %$arg);
                push @loggers, \%logger;
            } else {
                # I suggest this becomes a croak() after a
                # reasonable deprecation cycle.
                carp "All arguments to easy_init should be either "
                   . "an integer log level or a hash reference.";
            }
        }
    }

    for my $logger (@loggers) {

        my $app;

        if($logger->{file} =~ /^stderr$/i) {
            $app = Log::Log4perl::Appender->new(
                "Log::Log4perl::Appender::Screen",
                utf8 => $logger->{utf8});
        } elsif($logger->{file} =~ /^stdout$/i) {
            $app = Log::Log4perl::Appender->new(
                "Log::Log4perl::Appender::Screen",
                stderr => 0,
                utf8   => $logger->{utf8});
        } else {
            my $binmode;
            if($logger->{file} =~ s/^(:.*?)>/>/) {
                $binmode = $1;
            }
            $logger->{file} =~ /^(>)?(>)?/;
            my $mode = ($2 ? "append" : "write");
            $logger->{file} =~ s/.*>+\s*//g;
            $app = Log::Log4perl::Appender->new(
                "Log::Log4perl::Appender::File",
                filename => $logger->{file},
                mode     => $mode,
                utf8     => $logger->{utf8},
                binmode  => $binmode,
            );
        }

        my $layout = Log::Log4perl::Layout::PatternLayout->new(
                                                        $logger->{layout});
        $app->layout($layout);

        my $log = Log::Log4perl->get_logger($logger->{category});
        $log->level($logger->{level});
        $log->add_appender($app);
    }

    $Log::Log4perl::Logger::INITIALIZED = 1;
}

##################################################
sub wrapper_register {  
##################################################
    my $wrapper = $_[-1];

    $WRAPPERS_REGISTERED{ $wrapper } = 1;
}

##################################################
sub get_logger {  # Get an instance (shortcut)
##################################################
    # get_logger() can be called in the following ways:
    #
    #   (1) Log::Log4perl::get_logger()     => ()
    #   (2) Log::Log4perl->get_logger()     => ("Log::Log4perl")
    #   (3) Log::Log4perl::get_logger($cat) => ($cat)
    #   
    #   (5) Log::Log4perl->get_logger($cat) => ("Log::Log4perl", $cat)
    #   (6)   L4pSubclass->get_logger($cat) => ("L4pSubclass", $cat)

    # Note that (4) L4pSubclass->get_logger() => ("L4pSubclass")
    # is indistinguishable from (3) and therefore can't be allowed.
    # Wrapper classes always have to specify the category explicitly.

    my $category;

    if(@_ == 0) {
          # 1
        my $level = 0;
        do { $category = scalar caller($level++);
        } while exists $WRAPPERS_REGISTERED{ $category };

    } elsif(@_ == 1) {
          # 2, 3
        $category = $_[0];

        my $level = 0;
        while(exists $WRAPPERS_REGISTERED{ $category }) { 
            $category = scalar caller($level++);
        }

    } else {
          # 5, 6
        $category = $_[1];
    }

    # Delegate this to the logger module
    return Log::Log4perl::Logger->get_logger($category);
}

###########################################
sub caller_depth_offset {
###########################################
    my( $level ) = @_;

    my $category;

    { 
        my $category = scalar caller($level + 1);

        if(defined $category and
           exists $WRAPPERS_REGISTERED{ $category }) {
            $level++;
            redo;
        }
    }

    return $level;
}

##################################################
sub appenders {  # Get a hashref of all defined appender wrappers
##################################################
    return \%Log::Log4perl::Logger::APPENDER_BY_NAME;
}

##################################################
sub add_appender { # Add an appender to the system, but don't assign
	           # it to a logger yet
##################################################
    my($class, $appender) = @_;

    my $name = $appender->name();
    die "Mandatory parameter 'name' missing in appender" unless defined $name;

      # Make it known by name in the Log4perl universe
      # (so that composite appenders can find it)
    Log::Log4perl->appenders()->{ $name } = $appender;
}

##################################################
# Return number of appenders changed
sub appender_thresholds_adjust {  # Readjust appender thresholds
##################################################
        # If someone calls L4p-> and not L4p::
    shift if $_[0] eq __PACKAGE__;
    my($delta, $appenders) = @_;
	my $retval = 0;

    if($delta == 0) {
          # Nothing to do, no delta given.
        return;
    }

    if(defined $appenders) {
            # Map names to objects
        $appenders = [map { 
                       die "Unkown appender: '$_'" unless exists
                          $Log::Log4perl::Logger::APPENDER_BY_NAME{
                            $_};
                       $Log::Log4perl::Logger::APPENDER_BY_NAME{
                         $_} 
                      } @$appenders];
    } else {
            # Just hand over all known appenders
        $appenders = [values %{Log::Log4perl::appenders()}] unless 
            defined $appenders;
    }

        # Change all appender thresholds;
    foreach my $app (@$appenders) {
        my $old_thres = $app->threshold();
        my $new_thres;
        if($delta > 0) {
            $new_thres = Log::Log4perl::Level::get_higher_level(
                             $old_thres, $delta);
        } else {
            $new_thres = Log::Log4perl::Level::get_lower_level(
                             $old_thres, -$delta);
        }

        ++$retval if ($app->threshold($new_thres) == $new_thres);
    }
	return $retval;
}

##################################################
sub appender_by_name {  # Get a (real) appender by name
##################################################
        # If someone calls L4p->appender_by_name and not L4p::appender_by_name
    shift if $_[0] eq __PACKAGE__;

    my($name) = @_;

    if(defined $name and
       exists $Log::Log4perl::Logger::APPENDER_BY_NAME{
                 $name}) {
        return $Log::Log4perl::Logger::APPENDER_BY_NAME{
                 $name}->{appender};
    } else {
        return undef;
    }
}

##################################################
sub eradicate_appender {  # Remove an appender from the system
##################################################
        # If someone calls L4p->... and not L4p::...
    shift if $_[0] eq __PACKAGE__;
    Log::Log4perl::Logger->eradicate_appender(@_);
}

##################################################
sub infiltrate_lwp {  # 
##################################################
    no warnings qw(redefine);

    my $l4p_wrapper = sub {
        my($prio, @message) = @_;
        local $Log::Log4perl::caller_depth =
              $Log::Log4perl::caller_depth + 2;
        get_logger(scalar caller(1))->log($prio, @message);
    };

    *LWP::Debug::trace = sub { 
        $l4p_wrapper->($INFO, @_); 
    };
    *LWP::Debug::conns =
    *LWP::Debug::debug = sub { 
        $l4p_wrapper->($DEBUG, @_); 
    };
}

##################################################
sub easy_closure_create {
##################################################
    my($caller_pkg, $entry, $code, $logger) = @_;

    no strict 'refs';

    print("easy_closure: Setting shortcut $caller_pkg\::$entry ", 
         "(logger=$logger\n") if _INTERNAL_DEBUG;

    $EASY_CLOSURES->{ $caller_pkg }->{ $entry } = $logger;
    *{"$caller_pkg\::$entry"} = $code;
}

###########################################
sub easy_closure_cleanup {
###########################################
    my($caller_pkg, $entry) = @_;

    no warnings 'redefine';
    no strict 'refs';

    my $logger = $EASY_CLOSURES->{ $caller_pkg }->{ $entry };

    print("easy_closure: Nuking easy shortcut $caller_pkg\::$entry ", 
         "(logger=$logger\n") if _INTERNAL_DEBUG;

    *{"$caller_pkg\::$entry"} = sub { };
    delete $EASY_CLOSURES->{ $caller_pkg }->{ $entry };
}

##################################################
sub easy_closure_category_cleanup {
##################################################
    my($caller_pkg) = @_;

    if(! exists $EASY_CLOSURES->{ $caller_pkg } ) {
        return 1;
    }

    for my $entry ( keys %{ $EASY_CLOSURES->{ $caller_pkg } } ) {
        easy_closure_cleanup( $caller_pkg, $entry );
    }

    delete $EASY_CLOSURES->{ $caller_pkg };
}

###########################################
sub easy_closure_global_cleanup {
###########################################

    for my $caller_pkg ( keys %$EASY_CLOSURES ) {
        easy_closure_category_cleanup( $caller_pkg );
    }
}

###########################################
sub easy_closure_logger_remove {
###########################################
    my($class, $logger) = @_;

    PKG: for my $caller_pkg ( keys %$EASY_CLOSURES ) {
        for my $entry ( keys %{ $EASY_CLOSURES->{ $caller_pkg } } ) {
            if( $logger == $EASY_CLOSURES->{ $caller_pkg }->{ $entry } ) {
                easy_closure_category_cleanup( $caller_pkg );
                next PKG;
            }
        }
    }
}

##################################################
sub remove_logger {
##################################################
    my ($class, $logger) = @_;

    # Any stealth logger convenience function still using it will
    # now become a no-op.
    Log::Log4perl->easy_closure_logger_remove( $logger );

    # Remove the logger from the system
      # Need to split this up in two lines, or CVS will
      # mess it up.
    delete $Log::Log4perl::Logger::LOGGERS_BY_NAME->{ 
      $logger->{category} };
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl - Log4j implementation for Perl

=head1 SYNOPSIS
        
		# Easy mode if you like it simple ...

    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($ERROR);

    DEBUG "This doesn't go anywhere";
    ERROR "This gets logged";

        # ... or standard mode for more features:

    Log::Log4perl::init('/etc/log4perl.conf');
    
    --or--
    
        # Check config every 10 secs
    Log::Log4perl::init_and_watch('/etc/log4perl.conf',10);

    --then--
    
    $logger = Log::Log4perl->get_logger('house.bedrm.desk.topdrwr');
    
    $logger->debug('this is a debug message');
    $logger->info('this is an info message');
    $logger->warn('etc');
    $logger->error('..');
    $logger->fatal('..');
    
    #####/etc/log4perl.conf###############################
    log4perl.logger.house              = WARN,  FileAppndr1
    log4perl.logger.house.bedroom.desk = DEBUG, FileAppndr1
    
    log4perl.appender.FileAppndr1      = Log::Log4perl::Appender::File
    log4perl.appender.FileAppndr1.filename = desk.log 
    log4perl.appender.FileAppndr1.layout   = \
                            Log::Log4perl::Layout::SimpleLayout
    ######################################################

=head1 ABSTRACT

Log::Log4perl provides a powerful logging API for your application

=head1 DESCRIPTION

Log::Log4perl lets you remote-control and fine-tune the logging behaviour
of your system from the outside. It implements the widely popular 
(Java-based) Log4j logging package in pure Perl. 

B<For a detailed tutorial on Log::Log4perl usage, please read> 

L<http://www.perl.com/pub/a/2002/09/11/log4perl.html>

Logging beats a debugger if you want to know what's going on 
in your code during runtime. However, traditional logging packages
are too static and generate a flood of log messages in your log files
that won't help you.

C<Log::Log4perl> is different. It allows you to control the number of 
logging messages generated at three different levels:

=over 4

=item *

At a central location in your system (either in a configuration file or
in the startup code) you specify I<which components> (classes, functions) 
of your system should generate logs.

=item *

You specify how detailed the logging of these components should be by
specifying logging I<levels>.

=item *

You also specify which so-called I<appenders> you want to feed your
log messages to ("Print it to the screen and also append it to /tmp/my.log")
and which format ("Write the date first, then the file name and line 
number, and then the log message") they should be in.

=back

This is a very powerful and flexible mechanism. You can turn on and off
your logs at any time, specify the level of detail and make that
dependent on the subsystem that's currently executed. 

Let me give you an example: You might 
find out that your system has a problem in the 
C<MySystem::Helpers::ScanDir>
component. Turning on detailed debugging logs all over the system would
generate a flood of useless log messages and bog your system down beyond
recognition. With C<Log::Log4perl>, however, you can tell the system:
"Continue to log only severe errors to the log file. Open a second
log file, turn on full debug logs in the C<MySystem::Helpers::ScanDir>
component and dump all messages originating from there into the new
log file". And all this is possible by just changing the parameters
in a configuration file, which your system can re-read even 
while it's running!

=head1 How to use it

The C<Log::Log4perl> package can be initialized in two ways: Either
via Perl commands or via a C<log4j>-style configuration file.

=head2 Initialize via a configuration file

This is the easiest way to prepare your system for using
C<Log::Log4perl>. Use a configuration file like this:

    ############################################################
    # A simple root logger with a Log::Log4perl::Appender::File 
    # file appender in Perl.
    ############################################################
    log4perl.rootLogger=ERROR, LOGFILE
    
    log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
    log4perl.appender.LOGFILE.filename=/var/log/myerrs.log
    log4perl.appender.LOGFILE.mode=append
    
    log4perl.appender.LOGFILE.layout=PatternLayout
    log4perl.appender.LOGFILE.layout.ConversionPattern=[%r] %F %L %c - %m%n

These lines define your standard logger that's appending severe
errors to C</var/log/myerrs.log>, using the format

    [millisecs] source-filename line-number class - message newline

Assuming that this configuration file is saved as C<log.conf>, you need to 
read it in the startup section of your code, using the following
commands:

  use Log::Log4perl;
  Log::Log4perl->init("log.conf");

After that's done I<somewhere> in the code, you can retrieve
logger objects I<anywhere> in the code. Note that
there's no need to carry any logger references around with your 
functions and methods. You can get a logger anytime via a singleton
mechanism:

    package My::MegaPackage;
    use  Log::Log4perl;

    sub some_method {
        my($param) = @_;

        my $log = Log::Log4perl->get_logger("My::MegaPackage");

        $log->debug("Debug message");
        $log->info("Info message");
        $log->error("Error message");

        ...
    }

With the configuration file above, C<Log::Log4perl> will write
"Error message" to the specified log file, but won't do anything for 
the C<debug()> and C<info()> calls, because the log level has been set
to C<ERROR> for all components in the first line of 
configuration file shown above.

Why C<Log::Log4perl-E<gt>get_logger> and
not C<Log::Log4perl-E<gt>new>? We don't want to create a new
object every time. Usually in OO-Programming, you create an object
once and use the reference to it to call its methods. However,
this requires that you pass around the object to all functions
and the last thing we want is pollute each and every function/method
we're using with a handle to the C<Logger>:

    sub function {  # Brrrr!!
        my($logger, $some, $other, $parameters) = @_;
    }

Instead, if a function/method wants a reference to the logger, it
just calls the Logger's static C<get_logger($category)> method to obtain
a reference to the I<one and only> possible logger object of
a certain category.
That's called a I<singleton> if you're a Gamma fan.

How does the logger know
which messages it is supposed to log and which ones to suppress?
C<Log::Log4perl> works with inheritance: The config file above didn't 
specify anything about C<My::MegaPackage>. 
And yet, we've defined a logger of the category 
C<My::MegaPackage>.
In this case, C<Log::Log4perl> will walk up the namespace hierarchy
(C<My> and then we're at the root) to figure out if a log level is
defined somewhere. In the case above, the log level at the root
(root I<always> defines a log level, but not necessarily an appender)
defines that 
the log level is supposed to be C<ERROR> -- meaning that I<DEBUG>
and I<INFO> messages are suppressed. Note that this 'inheritance' is
unrelated to Perl's class inheritance, it is merely related to the
logger namespace.
By the way, if you're ever in doubt about what a logger's category is, 
use C<$logger-E<gt>category()> to retrieve it.

=head2 Log Levels

There are six predefined log levels: C<FATAL>, C<ERROR>, C<WARN>, C<INFO>,
C<DEBUG>, and C<TRACE> (in descending priority). Your configured logging level
has to at least match the priority of the logging message.

If your configured logging level is C<WARN>, then messages logged 
with C<info()>, C<debug()>, and C<trace()> will be suppressed. 
C<fatal()>, C<error()> and C<warn()> will make their way through,
because their priority is higher or equal than the configured setting.

Instead of calling the methods

    $logger->trace("...");  # Log a trace message
    $logger->debug("...");  # Log a debug message
    $logger->info("...");   # Log a info message
    $logger->warn("...");   # Log a warn message
    $logger->error("...");  # Log a error message
    $logger->fatal("...");  # Log a fatal message

you could also call the C<log()> method with the appropriate level
using the constants defined in C<Log::Log4perl::Level>:

    use Log::Log4perl::Level;

    $logger->log($TRACE, "...");
    $logger->log($DEBUG, "...");
    $logger->log($INFO, "...");
    $logger->log($WARN, "...");
    $logger->log($ERROR, "...");
    $logger->log($FATAL, "...");

This form is rarely used, but it comes in handy if you want to log 
at different levels depending on an exit code of a function:

    $logger->log( $exit_level{ $rc }, "...");

As for needing more logging levels than these predefined ones: It's
usually best to steer your logging behaviour via the category 
mechanism instead.

If you need to find out if the currently configured logging
level would allow a logger's logging statement to go through, use the
logger's C<is_I<level>()> methods:

    $logger->is_trace()    # True if trace messages would go through
    $logger->is_debug()    # True if debug messages would go through
    $logger->is_info()     # True if info messages would go through
    $logger->is_warn()     # True if warn messages would go through
    $logger->is_error()    # True if error messages would go through
    $logger->is_fatal()    # True if fatal messages would go through

Example: C<$logger-E<gt>is_warn()> returns true if the logger's current
level, as derived from either the logger's category (or, in absence of
that, one of the logger's parent's level setting) is 
C<$WARN>, C<$ERROR> or C<$FATAL>.

Also available are a series of more Java-esque functions which return
the same values. These are of the format C<isI<Level>Enabled()>,
so C<$logger-E<gt>isDebugEnabled()> is synonymous to 
C<$logger-E<gt>is_debug()>.


These level checking functions
will come in handy later, when we want to block unnecessary
expensive parameter construction in case the logging level is too
low to log the statement anyway, like in:

    if($logger->is_error()) {
        $logger->error("Erroneous array: @super_long_array");
    }

If we had just written

    $logger->error("Erroneous array: @super_long_array");

then Perl would have interpolated
C<@super_long_array> into the string via an expensive operation
only to figure out shortly after that the string can be ignored
entirely because the configured logging level is lower than C<$ERROR>.

The to-be-logged
message passed to all of the functions described above can
consist of an arbitrary number of arguments, which the logging functions
just chain together to a single string. Therefore

    $logger->debug("Hello ", "World", "!");  # and
    $logger->debug("Hello World!");

are identical.

Note that even if one of the methods above returns true, it doesn't 
necessarily mean that the message will actually get logged. 
What is_debug() checks is that
the logger used is configured to let a message of the given priority 
(DEBUG) through. But after this check, Log4perl will eventually apply custom 
filters and forward the message to one or more appenders. None of this
gets checked by is_xxx(), for the simple reason that it's 
impossible to know what a custom filter does with a message without
having the actual message or what an appender does to a message without
actually having it log it.

=head2 Log and die or warn

Often, when you croak / carp / warn / die, you want to log those messages.
Rather than doing the following:

    $logger->fatal($err) && die($err);

you can use the following:

    $logger->logdie($err);

And if instead of using

    warn($message);
    $logger->warn($message);

to both issue a warning via Perl's warn() mechanism and make sure you have
the same message in the log file as well, use:

    $logger->logwarn($message);

Since there is
an ERROR level between WARN and FATAL, there are two additional helper
functions in case you'd like to use ERROR for either warn() or die():

    $logger->error_warn();
    $logger->error_die();

Finally, there's the Carp functions that, in addition to logging,
also pass the stringified message to their companions in the Carp package:

    $logger->logcarp();        # warn w/ 1-level stack trace
    $logger->logcluck();       # warn w/ full stack trace
    $logger->logcroak();       # die w/ 1-level stack trace
    $logger->logconfess();     # die w/ full stack trace

=head2 Appenders

If you don't define any appenders, nothing will happen. Appenders will
be triggered whenever the configured logging level requires a message
to be logged and not suppressed.

C<Log::Log4perl> doesn't define any appenders by default, not even the root
logger has one.

C<Log::Log4perl> already comes with a standard set of appenders:

    Log::Log4perl::Appender::Screen
    Log::Log4perl::Appender::ScreenColoredLevels
    Log::Log4perl::Appender::File
    Log::Log4perl::Appender::Socket
    Log::Log4perl::Appender::DBI
    Log::Log4perl::Appender::Synchronized
    Log::Log4perl::Appender::RRDs

to log to the screen, to files and to databases. 

On CPAN, you can find additional appenders like

    Log::Log4perl::Layout::XMLLayout

by Guido Carls E<lt>gcarls@cpan.orgE<gt>.
It allows for hooking up Log::Log4perl with the graphical Log Analyzer
Chainsaw (see 
L<Log::Log4perl::FAQ/"Can I use Log::Log4perl with log4j's Chainsaw?">).

=head2 Additional Appenders via Log::Dispatch

C<Log::Log4perl> also supports I<Dave Rolskys> excellent C<Log::Dispatch>
framework which implements a wide variety of different appenders. 

Here's the list of appender modules currently available via C<Log::Dispatch>:

       Log::Dispatch::ApacheLog
       Log::Dispatch::DBI (by Tatsuhiko Miyagawa)
       Log::Dispatch::Email,
       Log::Dispatch::Email::MailSend,
       Log::Dispatch::Email::MailSendmail,
       Log::Dispatch::Email::MIMELite
       Log::Dispatch::File
       Log::Dispatch::FileRotate (by Mark Pfeiffer)
       Log::Dispatch::Handle
       Log::Dispatch::Screen
       Log::Dispatch::Syslog
       Log::Dispatch::Tk (by Dominique Dumont)

Please note that in order to use any of these additional appenders, you
have to fetch Log::Dispatch from CPAN and install it. Also the particular
appender you're using might require installing the particular module.

For additional information on appenders, please check the
L<Log::Log4perl::Appender> manual page.

=head2 Appender Example

Now let's assume that we want to log C<info()> or
higher prioritized messages in the C<Foo::Bar> category
to both STDOUT and to a log file, say C<test.log>.
In the initialization section of your system,
just define two appenders using the readily available
C<Log::Log4perl::Appender::File> and C<Log::Log4perl::Appender::Screen> 
modules:

  use Log::Log4perl;

     # Configuration in a string ...
  my $conf = q(
    log4perl.category.Foo.Bar          = INFO, Logfile, Screen

    log4perl.appender.Logfile          = Log::Log4perl::Appender::File
    log4perl.appender.Logfile.filename = test.log
    log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.Logfile.layout.ConversionPattern = [%r] %F %L %m%n

    log4perl.appender.Screen         = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.stderr  = 0
    log4perl.appender.Screen.layout = Log::Log4perl::Layout::SimpleLayout
  );

     # ... passed as a reference to init()
  Log::Log4perl::init( \$conf );

Once the initialization shown above has happened once, typically in
the startup code of your system, just use the defined logger anywhere in 
your system:

  ##########################
  # ... in some function ...
  ##########################
  my $log = Log::Log4perl::get_logger("Foo::Bar");

    # Logs both to STDOUT and to the file test.log
  $log->info("Important Info!");

The C<layout> settings specified in the configuration section define the 
format in which the
message is going to be logged by the specified appender. The format shown
for the file appender is logging not only the message but also the number of
milliseconds since the program has started (%r), the name of the file
the call to the logger has happened and the line number there (%F and
%L), the message itself (%m) and a OS-specific newline character (%n):

    [187] ./myscript.pl 27 Important Info!

The
screen appender above, on the other hand, 
uses a C<SimpleLayout>, which logs the 
debug level, a hyphen (-) and the log message:

    INFO - Important Info!

For more detailed info on layout formats, see L<Log Layouts>. 

In the configuration sample above, we chose to define a I<category> 
logger (C<Foo::Bar>).
This will cause only messages originating from
this specific category logger to be logged in the defined format
and locations.

=head2 Logging newlines

There's some controversy between different logging systems as to when and 
where newlines are supposed to be added to logged messages.

The Log4perl way is that a logging statement I<should not> 
contain a newline:

    $logger->info("Some message");
    $logger->info("Another message");

If this is supposed to end up in a log file like

    Some message
    Another message

then an appropriate appender layout like "%m%n" will take care of adding
a newline at the end of each message to make sure every message is 
printed on its own line.

Other logging systems, Log::Dispatch in particular, recommend adding the
newline to the log statement. This doesn't work well, however, if you, say,
replace your file appender by a database appender, and all of a sudden
those newlines scattered around the code don't make sense anymore.

Assigning matching layouts to different appenders and leaving newlines
out of the code solves this problem. If you inherited code that has logging
statements with newlines and want to make it work with Log4perl, read
the L<Log::Log4perl::Layout::PatternLayout> documentation on how to 
accomplish that.

=head2 Configuration files

As shown above, you can define C<Log::Log4perl> loggers both from within
your Perl code or from configuration files. The latter have the unbeatable
advantage that you can modify your system's logging behaviour without 
interfering with the code at all. So even if your code is being run by 
somebody who's totally oblivious to Perl, they still can adapt the
module's logging behaviour to their needs.

C<Log::Log4perl> has been designed to understand C<Log4j> configuration
files -- as used by the original Java implementation. Instead of 
reiterating the format description in [2], let me just list three
examples (also derived from [2]), which should also illustrate
how it works:

    log4j.rootLogger=DEBUG, A1
    log4j.appender.A1=org.apache.log4j.ConsoleAppender
    log4j.appender.A1.layout=org.apache.log4j.PatternLayout
    log4j.appender.A1.layout.ConversionPattern=%-4r %-5p %c %x - %m%n

This enables messages of priority C<DEBUG> or higher in the root
hierarchy and has the system write them to the console. 
C<ConsoleAppender> is a Java appender, but C<Log::Log4perl> jumps
through a significant number of hoops internally to map these to their
corresponding Perl classes, C<Log::Log4perl::Appender::Screen> in this case.

Second example:

    log4perl.rootLogger=DEBUG, A1
    log4perl.appender.A1=Log::Log4perl::Appender::Screen
    log4perl.appender.A1.layout=PatternLayout
    log4perl.appender.A1.layout.ConversionPattern=%d %-5p %c - %m%n
    log4perl.logger.com.foo=WARN

This defines two loggers: The root logger and the C<com.foo> logger.
The root logger is easily triggered by debug-messages, 
but the C<com.foo> logger makes sure that messages issued within
the C<Com::Foo> component and below are only forwarded to the appender
if they're of priority I<warning> or higher. 

Note that the C<com.foo> logger doesn't define an appender. Therefore,
it will just propagate the message up the hierarchy until the root logger
picks it up and forwards it to the one and only appender of the root
category, using the format defined for it.

Third example:

    log4j.rootLogger=DEBUG, stdout, R
    log4j.appender.stdout=org.apache.log4j.ConsoleAppender
    log4j.appender.stdout.layout=org.apache.log4j.PatternLayout
    log4j.appender.stdout.layout.ConversionPattern=%5p (%F:%L) - %m%n
    log4j.appender.R=org.apache.log4j.RollingFileAppender
    log4j.appender.R.File=example.log
    log4j.appender.R.layout=org.apache.log4j.PatternLayout
    log4j.appender.R.layout.ConversionPattern=%p %c - %m%n

The root logger defines two appenders here: C<stdout>, which uses 
C<org.apache.log4j.ConsoleAppender> (ultimately mapped by C<Log::Log4perl>
to L<Log::Log4perl::Appender::Screen>) to write to the screen. And
C<R>, a C<org.apache.log4j.RollingFileAppender> 
(mapped by C<Log::Log4perl> to 
L<Log::Dispatch::FileRotate> with the C<File> attribute specifying the
log file.

See L<Log::Log4perl::Config> for more examples and syntax explanations.

=head2 Log Layouts

If the logging engine passes a message to an appender, because it thinks
it should be logged, the appender doesn't just
write it out haphazardly. There's ways to tell the appender how to format
the message and add all sorts of interesting data to it: The date and
time when the event happened, the file, the line number, the
debug level of the logger and others.

There's currently two layouts defined in C<Log::Log4perl>: 
C<Log::Log4perl::Layout::SimpleLayout> and
C<Log::Log4perl::Layout::PatternLayout>:

=over 4 

=item C<Log::Log4perl::SimpleLayout> 

formats a message in a simple
way and just prepends it by the debug level and a hyphen:
C<"$level - $message>, for example C<"FATAL - Can't open password file">.

=item C<Log::Log4perl::Layout::PatternLayout> 

on the other hand is very powerful and 
allows for a very flexible format in C<printf>-style. The format
string can contain a number of placeholders which will be
replaced by the logging engine when it's time to log the message:

    %c Category of the logging event.
    %C Fully qualified package (or class) name of the caller
    %d Current date in yyyy/MM/dd hh:mm:ss format
    %F File where the logging event occurred
    %H Hostname (if Sys::Hostname is available)
    %l Fully qualified name of the calling method followed by the
       callers source the file name and line number between 
       parentheses.
    %L Line number within the file where the log statement was issued
    %m The message to be logged
    %m{chomp} The message to be logged, stripped off a trailing newline
    %M Method or function where the logging request was issued
    %n Newline (OS-independent)
    %p Priority of the logging event
    %P pid of the current process
    %r Number of milliseconds elapsed from program start to logging 
       event
    %R Number of milliseconds elapsed from last logging event to
       current logging event 
    %T A stack trace of functions called
    %x The topmost NDC (see below)
    %X{key} The entry 'key' of the MDC (see below)
    %% A literal percent (%) sign

NDC and MDC are explained in L<"Nested Diagnostic Context (NDC)">
and L<"Mapped Diagnostic Context (MDC)">.

Also, C<%d> can be fine-tuned to display only certain characteristics
of a date, according to the SimpleDateFormat in the Java World
(L<http://java.sun.com/j2se/1.3/docs/api/java/text/SimpleDateFormat.html>)

In this way, C<%d{HH:mm}> displays only hours and minutes of the current date,
while C<%d{yy, EEEE}> displays a two-digit year, followed by a spelled-out day
(like C<Wednesday>). 

Similar options are available for shrinking the displayed category or
limit file/path components, C<%F{1}> only displays the source file I<name>
without any path components while C<%F> logs the full path. %c{2} only
logs the last two components of the current category, C<Foo::Bar::Baz> 
becomes C<Bar::Baz> and saves space.

If those placeholders aren't enough, then you can define your own right in
the config file like this:

    log4perl.PatternLayout.cspec.U = sub { return "UID $<" }

See L<Log::Log4perl::Layout::PatternLayout> for further details on
customized specifiers.

Please note that the subroutines you're defining in this way are going
to be run in the C<main> namespace, so be sure to fully qualify functions
and variables if they're located in different packages.

SECURITY NOTE: this feature means arbitrary perl code can be embedded in the 
config file.  In the rare case where the people who have access to your config 
file are different from the people who write your code and shouldn't have 
execute rights, you might want to call

    Log::Log4perl::Config->allow_code(0);

before you call init(). Alternatively you can supply a restricted set of
Perl opcodes that can be embedded in the config file as described in
L<"Restricting what Opcodes can be in a Perl Hook">.

=back

All placeholders are quantifiable, just like in I<printf>. Following this 
tradition, C<%-20c> will reserve 20 chars for the category and left-justify it.

For more details on logging and how to use the flexible and the simple
format, check out the original C<log4j> website under

L<SimpleLayout|http://logging.apache.org/log4j/1.2/apidocs/org/apache/log4j/SimpleLayout.html>
and
L<PatternLayout|http://logging.apache.org/log4j/1.2/apidocs/org/apache/log4j/PatternLayout.html>

=head2 Penalties

Logging comes with a price tag. C<Log::Log4perl> has been optimized
to allow for maximum performance, both with logging enabled and disabled.

But you need to be aware that there's a small hit every time your code
encounters a log statement -- no matter if logging is enabled or not. 
C<Log::Log4perl> has been designed to keep this so low that it will
be unnoticeable to most applications.

Here's a couple of tricks which help C<Log::Log4perl> to avoid
unnecessary delays:

You can save serious time if you're logging something like

        # Expensive in non-debug mode!
    for (@super_long_array) {
        $logger->debug("Element: $_");
    }

and C<@super_long_array> is fairly big, so looping through it is pretty
expensive. Only you, the programmer, knows that going through that C<for>
loop can be skipped entirely if the current logging level for the 
actual component is higher than C<debug>.
In this case, use this instead:

        # Cheap in non-debug mode!
    if($logger->is_debug()) {
        for (@super_long_array) {
            $logger->debug("Element: $_");
        }
    }

If you're afraid that generating the parameters to the
logging function is fairly expensive, use closures:

        # Passed as subroutine ref
    use Data::Dumper;
    $logger->debug(sub { Dumper($data) } );

This won't unravel C<$data> via Dumper() unless it's actually needed
because it's logged. 

Also, Log::Log4perl lets you specify arguments
to logger functions in I<message output filter syntax>:

    $logger->debug("Structure: ",
                   { filter => \&Dumper,
                     value  => $someref });

In this way, shortly before Log::Log4perl sending the
message out to any appenders, it will be searching all arguments for
hash references and treat them in a special way:

It will invoke the function given as a reference with the C<filter> key
(C<Data::Dumper::Dumper()>) and pass it the value that came with
the key named C<value> as an argument.
The anonymous hash in the call above will be replaced by the return 
value of the filter function.

=head1 Categories

B<Categories are also called "Loggers" in Log4perl, both refer
to the same thing and these terms are used interchangeably.>
C<Log::Log4perl> uses I<categories> to determine if a log statement in
a component should be executed or suppressed at the current logging level.
Most of the time, these categories are just the classes the log statements
are located in:

    package Candy::Twix;

    sub new { 
        my $logger = Log::Log4perl->get_logger("Candy::Twix");
        $logger->debug("Creating a new Twix bar");
        bless {}, shift;
    }
 
    # ...

    package Candy::Snickers;

    sub new { 
        my $logger = Log::Log4perl->get_logger("Candy.Snickers");
        $logger->debug("Creating a new Snickers bar");
        bless {}, shift;
    }

    # ...

    package main;
    Log::Log4perl->init("mylogdefs.conf");

        # => "LOG> Creating a new Snickers bar"
    my $first = Candy::Snickers->new();
        # => "LOG> Creating a new Twix bar"
    my $second = Candy::Twix->new();

Note that you can separate your category hierarchy levels
using either dots like
in Java (.) or double-colons (::) like in Perl. Both notations
are equivalent and are handled the same way internally.

However, categories are just there to make
use of inheritance: if you invoke a logger in a sub-category, 
it will bubble up the hierarchy and call the appropriate appenders.
Internally, categories are not related to the class hierarchy of the program
at all -- they're purely virtual. You can use arbitrary categories --
for example in the following program, which isn't oo-style, but
procedural:

    sub print_portfolio {

        my $log = Log::Log4perl->get_logger("user.portfolio");
        $log->debug("Quotes requested: @_");

        for(@_) {
            print "$_: ", get_quote($_), "\n";
        }
    }

    sub get_quote {

        my $log = Log::Log4perl->get_logger("internet.quotesystem");
        $log->debug("Fetching quote: $_[0]");

        return yahoo_quote($_[0]);
    }

The logger in first function, C<print_portfolio>, is assigned the
(virtual) C<user.portfolio> category. Depending on the C<Log4perl>
configuration, this will either call a C<user.portfolio> appender,
a C<user> appender, or an appender assigned to root -- without
C<user.portfolio> having any relevance to the class system used in 
the program.
The logger in the second function adheres to the 
C<internet.quotesystem> category -- again, maybe because it's bundled 
with other Internet functions, but not because there would be
a class of this name somewhere.

However, be careful, don't go overboard: if you're developing a system
in object-oriented style, using the class hierarchy is usually your best
choice. Think about the people taking over your code one day: The
class hierarchy is probably what they know right up front, so it's easy
for them to tune the logging to their needs.

=head2 Turn off a component

C<Log4perl> doesn't only allow you to selectively switch I<on> a category
of log messages, you can also use the mechanism to selectively I<disable>
logging in certain components whereas logging is kept turned on in higher-level
categories. This mechanism comes in handy if you find that while bumping 
up the logging level of a high-level (i. e. close to root) category, 
that one component logs more than it should, 

Here's how it works: 

    ############################################################
    # Turn off logging in a lower-level category while keeping
    # it active in higher-level categories.
    ############################################################
    log4perl.rootLogger=DEBUG, LOGFILE
    log4perl.logger.deep.down.the.hierarchy = ERROR, LOGFILE

    # ... Define appenders ...

This way, log messages issued from within 
C<Deep::Down::The::Hierarchy> and below will be
logged only if they're C<ERROR> or worse, while in all other system components
even C<DEBUG> messages will be logged.

=head2 Return Values

All logging methods return values indicating if their message
actually reached one or more appenders. If the message has been
suppressed because of level constraints, C<undef> is returned.

For example,

    my $ret = $logger->info("Message");

will return C<undef> if the system debug level for the current category
is not C<INFO> or more permissive. 
If Log::Log4perl
forwarded the message to one or more appenders, the number of appenders
is returned.

If appenders decide to veto on the message with an appender threshold,
the log method's return value will have them excluded. This means that if
you've got one appender holding an appender threshold and you're 
logging a message
which passes the system's log level hurdle but not the appender threshold,
C<0> will be returned by the log function.

The bottom line is: Logging functions will return a I<true> value if the message
made it through to one or more appenders and a I<false> value if it didn't.
This allows for constructs like

    $logger->fatal("@_") or print STDERR "@_\n";

which will ensure that the fatal message isn't lost
if the current level is lower than FATAL or printed twice if 
the level is acceptable but an appender already points to STDERR.

=head2 Pitfalls with Categories

Be careful with just blindly reusing the system's packages as
categories. If you do, you'll get into trouble with inherited methods.
Imagine the following class setup:

    use Log::Log4perl;

    ###########################################
    package Bar;
    ###########################################
    sub new {
        my($class) = @_;
        my $logger = Log::Log4perl::get_logger(__PACKAGE__);
        $logger->debug("Creating instance");
        bless {}, $class;
    }
    ###########################################
    package Bar::Twix;
    ###########################################
    our @ISA = qw(Bar);

    ###########################################
    package main;
    ###########################################
    Log::Log4perl->init(\ qq{
    log4perl.category.Bar.Twix = DEBUG, Screen
    log4perl.appender.Screen = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.layout = SimpleLayout
    });

    my $bar = Bar::Twix->new();

C<Bar::Twix> just inherits everything from C<Bar>, including the constructor
C<new()>.
Contrary to what you might be thinking at first, this won't log anything. 
Reason for this is the C<get_logger()> call in package C<Bar>, which
will always get a logger of the C<Bar> category, even if we call C<new()> via
the C<Bar::Twix> package, which will make perl go up the inheritance 
tree to actually execute C<Bar::new()>. Since we've only defined logging
behaviour for C<Bar::Twix> in the configuration file, nothing will happen.

This can be fixed by changing the C<get_logger()> method in C<Bar::new()>
to obtain a logger of the category matching the
I<actual> class of the object, like in

        # ... in Bar::new() ...
    my $logger = Log::Log4perl::get_logger( $class );

In a method other than the constructor, the class name of the actual
object can be obtained by calling C<ref()> on the object reference, so

    package BaseClass;
    use Log::Log4perl qw( get_logger );

    sub new { 
        bless {}, shift; 
    }

    sub method {
        my( $self ) = @_;

        get_logger( ref $self )->debug( "message" );
    }

    package SubClass;
    our @ISA = qw(BaseClass);

is the recommended pattern to make sure that 

    my $sub = SubClass->new();
    $sub->meth();

starts logging if the C<"SubClass"> category 
(and not the C<"BaseClass"> category has logging enabled at the DEBUG level.

=head2 Initialize once and only once

It's important to realize that Log::Log4perl gets initialized once and only
once, typically at the start of a program or system. Calling C<init()>
more than once will cause it to clobber the existing configuration and
I<replace> it by the new one.

If you're in a traditional CGI environment, where every request is
handled by a new process, calling C<init()> every time is fine. In
persistent environments like C<mod_perl>, however, Log::Log4perl
should be initialized either at system startup time (Apache offers
startup handlers for that) or via

        # Init or skip if already done
    Log::Log4perl->init_once($conf_file);

C<init_once()> is identical to C<init()>, just with the exception
that it will leave a potentially existing configuration alone and 
will only call C<init()> if Log::Log4perl hasn't been initialized yet.

If you're just curious if Log::Log4perl has been initialized yet, the
check

    if(Log::Log4perl->initialized()) {
        # Yes, Log::Log4perl has already been initialized
    } else {
        # No, not initialized yet ...
    }

can be used.

If you're afraid that the components of your system are stepping on 
each other's toes or if you are thinking that different components should
initialize Log::Log4perl separately, try to consolidate your system
to use a centralized Log4perl configuration file and use 
Log4perl's I<categories> to separate your components.

=head2 Custom Filters

Log4perl allows the use of customized filters in its appenders
to control the output of messages. These filters might grep for
certain text chunks in a message, verify that its priority
matches or exceeds a certain level or that this is the 10th
time the same message has been submitted -- and come to a log/no log 
decision based upon these circumstantial facts.

Check out L<Log::Log4perl::Filter> for detailed instructions 
on how to use them.

=head2 Performance

The performance of Log::Log4perl calls obviously depends on a lot of things.
But to give you a general idea, here's some rough numbers:

On a Pentium 4 Linux box at 2.4 GHz, you'll get through

=over 4

=item *

500,000 suppressed log statements per second

=item *

30,000 logged messages per second (using an in-memory appender)

=item *

init_and_watch delay mode: 300,000 suppressed, 30,000 logged.
init_and_watch signal mode: 450,000 suppressed, 30,000 logged.

=back

Numbers depend on the complexity of the Log::Log4perl configuration.
For a more detailed benchmark test, check the C<docs/benchmark.results.txt> 
document in the Log::Log4perl distribution.

=head1 Cool Tricks

Here's a collection of useful tricks for the advanced C<Log::Log4perl> user.
For more, check the FAQ, either in the distribution 
(L<Log::Log4perl::FAQ>) or on L<http://log4perl.sourceforge.net>.

=head2 Shortcuts

When getting an instance of a logger, instead of saying

    use Log::Log4perl;
    my $logger = Log::Log4perl->get_logger();

it's often more convenient to import the C<get_logger> method from 
C<Log::Log4perl> into the current namespace:

    use Log::Log4perl qw(get_logger);
    my $logger = get_logger();

Please note this difference: To obtain the root logger, please use
C<get_logger("")>, call it without parameters (C<get_logger()>), you'll
get the logger of a category named after the current package. 
C<get_logger()> is equivalent to C<get_logger(__PACKAGE__)>.

=head2 Alternative initialization

Instead of having C<init()> read in a configuration file by specifying
a file name or passing it a reference to an open filehandle
(C<Log::Log4perl-E<gt>init( \*FILE )>),
you can 
also pass in a reference to a string, containing the content of
the file:

    Log::Log4perl->init( \$config_text );

Also, if you've got the C<name=value> pairs of the configuration in
a hash, you can just as well initialize C<Log::Log4perl> with
a reference to it:

    my %key_value_pairs = (
        "log4perl.rootLogger"       => "ERROR, LOGFILE",
        "log4perl.appender.LOGFILE" => "Log::Log4perl::Appender::File",
        ...
    );

    Log::Log4perl->init( \%key_value_pairs );

Or also you can use a URL, see below:

=head2 Using LWP to parse URLs

(This section borrowed from XML::DOM::Parser by T.J. Mather).

The init() function now also supports URLs, e.g. I<http://www.erols.com/enno/xsa.xml>.
It uses LWP to download the file and then calls parse() on the resulting string.
By default it will use a L<LWP::UserAgent> that is created as follows:

 use LWP::UserAgent;
 $LWP_USER_AGENT = LWP::UserAgent->new;
 $LWP_USER_AGENT->env_proxy;

Note that env_proxy reads proxy settings from environment variables, which is what Log4perl needs to
do to get through our firewall. If you want to use a different LWP::UserAgent, you can 
set it with

    Log::Log4perl::Config::set_LWP_UserAgent($my_agent);

Currently, LWP is used when the filename (passed to parsefile) starts with one of
the following URL schemes: http, https, ftp, wais, gopher, or file (followed by a colon.)

Don't use this feature with init_and_watch().

=head2 Automatic reloading of changed configuration files

Instead of just statically initializing Log::Log4perl via

    Log::Log4perl->init($conf_file);

there's a way to have Log::Log4perl periodically check for changes
in the configuration and reload it if necessary:

    Log::Log4perl->init_and_watch($conf_file, $delay);

In this mode, Log::Log4perl will examine the configuration file 
C<$conf_file> every C<$delay> seconds for changes via the file's
last modification timestamp. If the file has been updated, it will
be reloaded and replace the current Log::Log4perl configuration.

The way this works is that with every logger function called 
(debug(), is_debug(), etc.), Log::Log4perl will check if the delay 
interval has expired. If so, it will run a -M file check on the 
configuration file. If its timestamp has been modified, the current
configuration will be dumped and new content of the file will be
loaded.

This convenience comes at a price, though: Calling time() with every
logging function call, especially the ones that are "suppressed" (!), 
will slow down these Log4perl calls by about 40%.

To alleviate this performance hit a bit, C<init_and_watch()> 
can be configured to listen for a Unix signal to reload the 
configuration instead:

    Log::Log4perl->init_and_watch($conf_file, 'HUP');

This will set up a signal handler for SIGHUP and reload the configuration
if the application receives this signal, e.g. via the C<kill> command:

    kill -HUP pid

where C<pid> is the process ID of the application. This will bring you back
to about 85% of Log::Log4perl's normal execution speed for suppressed
statements. For details, check out L<"Performance">. For more info
on the signal handler, look for L<Log::Log4perl::Config::Watch/"SIGNAL MODE">.

If you have a somewhat long delay set between physical config file checks
or don't want to use the signal associated with the config file watcher,
you can trigger a configuration reload at the next possible time by
calling C<Log::Log4perl::Config-E<gt>watcher-E<gt>force_next_check()>.

One thing to watch out for: If the configuration file contains a syntax
or other fatal error, a running application will stop with C<die> if
this damaged configuration will be loaded during runtime, triggered
either by a signal or if the delay period expired and the change is 
detected. This behaviour might change in the future.

To allow the application to intercept and control a configuration reload
in init_and_watch mode, a callback can be specified:

    Log::Log4perl->init_and_watch($conf_file, 10, { 
            preinit_callback => \&callback });

If Log4perl determines that the configuration needs to be reloaded, it will
call the C<preinit_callback> function without parameters. If the callback
returns a true value, Log4perl will proceed and reload the configuration.  If
the callback returns a false value, Log4perl will keep the old configuration
and skip reloading it until the next time around.  Inside the callback, an
application can run all kinds of checks, including accessing the configuration
file, which is available via
C<Log::Log4perl::Config-E<gt>watcher()-E<gt>file()>.

=head2 Variable Substitution

To avoid having to retype the same expressions over and over again,
Log::Log4perl's configuration files support simple variable substitution.
New variables are defined simply by adding

    varname = value

lines to the configuration file before using

    ${varname}

afterwards to recall the assigned values. Here's an example:

    layout_class   = Log::Log4perl::Layout::PatternLayout
    layout_pattern = %d %F{1} %L> %m %n
    
    log4perl.category.Bar.Twix = WARN, Logfile, Screen

    log4perl.appender.Logfile  = Log::Log4perl::Appender::File
    log4perl.appender.Logfile.filename = test.log
    log4perl.appender.Logfile.layout = ${layout_class}
    log4perl.appender.Logfile.layout.ConversionPattern = ${layout_pattern}

    log4perl.appender.Screen  = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.layout = ${layout_class}
    log4perl.appender.Screen.layout.ConversionPattern = ${layout_pattern}

This is a convenient way to define two appenders with the same layout 
without having to retype the pattern definitions.

Variable substitution via C<${varname}> 
will first try to find an explicitly defined 
variable. If that fails, it will check your shell's environment
for a variable of that name. If that also fails, the program will C<die()>.

=head2 Perl Hooks in the Configuration File

If some of the values used in the Log4perl configuration file 
need to be dynamically modified by the program, use Perl hooks:

    log4perl.appender.File.filename = \
        sub { return getLogfileName(); }

Each value starting with the string C<sub {...> is interpreted as Perl code to
be executed at the time the application parses the configuration
via C<Log::Log4perl::init()>. The return value of the subroutine
is used by Log::Log4perl as the configuration value.

The Perl code is executed in the C<main> package, functions in
other packages have to be called in fully-qualified notation.

Here's another example, utilizing an environment variable as a
username for a DBI appender:

    log4perl.appender.DB.username = \
        sub { $ENV{DB_USER_NAME } }

However, please note the difference between these code snippets and those
used for user-defined conversion specifiers as discussed in
L<Log::Log4perl::Layout::PatternLayout>: 
While the snippets above are run I<once>
when C<Log::Log4perl::init()> is called, the conversion specifier
snippets are executed I<each time> a message is rendered according to
the PatternLayout.

SECURITY NOTE: this feature means arbitrary perl code can be embedded in the 
config file.  In the rare case where the people who have access to your config 
file are different from the people who write your code and shouldn't have 
execute rights, you might want to set

    Log::Log4perl::Config->allow_code(0);

before you call init().  Alternatively you can supply a restricted set of
Perl opcodes that can be embedded in the config file as described in
L<"Restricting what Opcodes can be in a Perl Hook">.

=head2 Restricting what Opcodes can be in a Perl Hook

The value you pass to Log::Log4perl::Config->allow_code() determines whether
the code that is embedded in the config file is eval'd unrestricted, or
eval'd in a Safe compartment.  By default, a value of '1' is assumed,
which does a normal 'eval' without any restrictions. A value of '0' 
however prevents any embedded code from being evaluated.

If you would like fine-grained control over what can and cannot be included
in embedded code, then please utilize the following methods:

 Log::Log4perl::Config->allow_code( $allow );
 Log::Log4perl::Config->allowed_code_ops($op1, $op2, ... );
 Log::Log4perl::Config->vars_shared_with_safe_compartment( [ \%vars | $package, \@vars ] );
 Log::Log4perl::Config->allowed_code_ops_convenience_map( [ \%map | $name, \@mask ] );

Log::Log4perl::Config-E<gt>allowed_code_ops() takes a list of opcode masks
that are allowed to run in the compartment.  The opcode masks must be
specified as described in L<Opcode>:

 Log::Log4perl::Config->allowed_code_ops(':subprocess');

This example would allow Perl operations like backticks, system, fork, and
waitpid to be executed in the compartment.  Of course, you probably don't
want to use this mask -- it would allow exactly what the Safe compartment is
designed to prevent.

Log::Log4perl::Config-E<gt>vars_shared_with_safe_compartment() 
takes the symbols which
should be exported into the Safe compartment before the code is evaluated. 
The keys of this hash are the package names that the symbols are in, and the
values are array references to the literal symbol names.  For convenience,
the default settings export the '%ENV' hash from the 'main' package into the
compartment:

 Log::Log4perl::Config->vars_shared_with_safe_compartment(
   main => [ '%ENV' ],
 );

Log::Log4perl::Config-E<gt>allowed_code_ops_convenience_map() is an accessor
method to a map of convenience names to opcode masks. At present, the
following convenience names are defined:

 safe        = [ ':browse' ]
 restrictive = [ ':default' ]

For convenience, if Log::Log4perl::Config-E<gt>allow_code() is called with a
value which is a key of the map previously defined with
Log::Log4perl::Config-E<gt>allowed_code_ops_convenience_map(), then the
allowed opcodes are set according to the value defined in the map. If this
is confusing, consider the following:

 use Log::Log4perl;
 
 my $config = <<'END';
  log4perl.logger = INFO, Main
  log4perl.appender.Main = Log::Log4perl::Appender::File
  log4perl.appender.Main.filename = \
      sub { "example" . getpwuid($<) . ".log" }
  log4perl.appender.Main.layout = Log::Log4perl::Layout::SimpleLayout
 END
 
 $Log::Log4perl::Config->allow_code('restrictive');
 Log::Log4perl->init( \$config );       # will fail
 $Log::Log4perl::Config->allow_code('safe');
 Log::Log4perl->init( \$config );       # will succeed

The reason that the first call to -E<gt>init() fails is because the
'restrictive' name maps to an opcode mask of ':default'.  getpwuid() is not
part of ':default', so -E<gt>init() fails.  The 'safe' name maps to an opcode
mask of ':browse', which allows getpwuid() to run, so -E<gt>init() succeeds.

allowed_code_ops_convenience_map() can be invoked in several ways:

=over 4

=item allowed_code_ops_convenience_map()

Returns the entire convenience name map as a hash reference in scalar
context or a hash in list context.

=item allowed_code_ops_convenience_map( \%map )

Replaces the entire convenience name map with the supplied hash reference.

=item allowed_code_ops_convenience_map( $name )

Returns the opcode mask for the given convenience name, or undef if no such
name is defined in the map.

=item allowed_code_ops_convenience_map( $name, \@mask )

Adds the given name/mask pair to the convenience name map.  If the name
already exists in the map, it's value is replaced with the new mask.

=back

as can vars_shared_with_safe_compartment():

=over 4

=item vars_shared_with_safe_compartment()

Return the entire map of packages to variables as a hash reference in scalar
context or a hash in list context.

=item vars_shared_with_safe_compartment( \%packages )

Replaces the entire map of packages to variables with the supplied hash
reference.

=item vars_shared_with_safe_compartment( $package )

Returns the arrayref of variables to be shared for a specific package.

=item vars_shared_with_safe_compartment( $package, \@vars )

Adds the given package / varlist pair to the map.  If the package already
exists in the map, it's value is replaced with the new arrayref of variable
names.

=back

For more information on opcodes and Safe Compartments, see L<Opcode> and
L<Safe>.

=head2 Changing the Log Level on a Logger

Log4perl provides some internal functions for quickly adjusting the
log level from within a running Perl program. 

Now, some people might
argue that you should adjust your levels from within an external 
Log4perl configuration file, but Log4perl is everybody's darling.

Typically run-time adjusting of levels is done
at the beginning, or in response to some external input (like a
"more logging" runtime command for diagnostics).

You get the log level from a logger object with:

    $current_level = $logger->level();

and you may set it with the same method, provided you first
imported the log level constants, with:

    use Log::Log4perl::Level;

Then you can set the level on a logger to one of the constants,

    $logger->level($ERROR); # one of DEBUG, INFO, WARN, ERROR, FATAL

To B<increase> the level of logging currently being done, use:

    $logger->more_logging($delta);

and to B<decrease> it, use:

    $logger->less_logging($delta);

$delta must be a positive integer (for now, we may fix this later ;).

There are also two equivalent functions:

    $logger->inc_level($delta);
    $logger->dec_level($delta);

They're included to allow you a choice in readability. Some folks
will prefer more/less_logging, as they're fairly clear in what they
do, and allow the programmer not to worry too much about what a Level
is and whether a higher level means more or less logging. However,
other folks who do understand and have lots of code that deals with
levels will probably prefer the inc_level() and dec_level() methods as
they want to work with Levels and not worry about whether that means
more or less logging. :)

That diatribe aside, typically you'll use more_logging() or inc_level()
as such:

    my $v = 0; # default level of verbosity.
    
    GetOptions("v+" => \$v, ...);

    if( $v ) {
      $logger->more_logging($v); # inc logging level once for each -v in ARGV
    }

=head2 Custom Log Levels

First off, let me tell you that creating custom levels is heavily
deprecated by the log4j folks. Indeed, instead of creating additional
levels on top of the predefined DEBUG, INFO, WARN, ERROR and FATAL, 
you should use categories to control the amount of logging smartly,
based on the location of the log-active code in the system.

Nevertheless, 
Log4perl provides a nice way to create custom levels via the 
create_custom_level() routine function. However, this must be done
before the first call to init() or get_logger(). Say you want to create
a NOTIFY logging level that comes after WARN (and thus before INFO).
You'd do such as follows:

    use Log::Log4perl;
    use Log::Log4perl::Level;

    Log::Log4perl::Logger::create_custom_level("NOTIFY", "WARN");

And that's it! C<create_custom_level()> creates the following functions /
variables for level FOO:

    $FOO_INT        # integer to use in L4p::Level::to_level()
    $logger->foo()  # log function to log if level = FOO
    $logger->is_foo()   # true if current level is >= FOO

These levels can also be used in your
config file, but note that your config file probably won't be
portable to another log4perl or log4j environment unless you've
made the appropriate mods there too.

Since Log4perl translates log levels to syslog and Log::Dispatch if 
their appenders are used, you may add mappings for custom levels as well:

  Log::Log4perl::Level::add_priority("NOTIFY", "WARN",
                                     $syslog_equiv, $log_dispatch_level);

For example, if your new custom "NOTIFY" level is supposed to map 
to syslog level 2 ("LOG_NOTICE") and Log::Dispatch level 2 ("notice"), use:

  Log::Log4perl::Logger::create_custom_level("NOTIFY", "WARN", 2, 2);

=head2 System-wide log levels

As a fairly drastic measure to decrease (or increase) the logging level
all over the system with one single configuration option, use the C<threshold>
keyword in the Log4perl configuration file:

    log4perl.threshold = ERROR

sets the system-wide (or hierarchy-wide according to the log4j documentation)
to ERROR and therefore deprives every logger in the system of the right 
to log lower-prio messages.

=head2 Easy Mode

For teaching purposes (especially for [1]), I've put C<:easy> mode into 
C<Log::Log4perl>, which just initializes a single root logger with a 
defined priority and a screen appender including some nice standard layout:

    ### Initialization Section
    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($ERROR);  # Set priority of root logger to ERROR

    ### Application Section
    my $logger = get_logger();
    $logger->fatal("This will get logged.");
    $logger->debug("This won't.");

This will dump something like

    2002/08/04 11:43:09 ERROR> script.pl:16 main::function - This will get logged.

to the screen. While this has been proven to work well familiarizing people
with C<Log::Logperl> slowly, effectively avoiding to clobber them over the 
head with a 
plethora of different knobs to fiddle with (categories, appenders, levels, 
layout), the overall mission of C<Log::Log4perl> is to let people use
categories right from the start to get used to the concept. So, let's keep
this one fairly hidden in the man page (congrats on reading this far :).

=head2 Stealth loggers

Sometimes, people are lazy. If you're whipping up a 50-line script and want 
the comfort of Log::Log4perl without having the burden of carrying a
separate log4perl.conf file or a 5-liner defining that you want to append
your log statements to a file, you can use the following features:

    use Log::Log4perl qw(:easy);

    Log::Log4perl->easy_init( { level   => $DEBUG,
                                file    => ">>test.log" } );

        # Logs to test.log via stealth logger
    DEBUG("Debug this!");
    INFO("Info this!");
    WARN("Warn this!");
    ERROR("Error this!");

    some_function();

    sub some_function {
            # Same here
        FATAL("Fatal this!");
    }

In C<:easy> mode, C<Log::Log4perl> will instantiate a I<stealth logger>
and introduce the
convenience functions C<TRACE>, C<DEBUG()>, C<INFO()>, C<WARN()>, 
C<ERROR()>, C<FATAL()>, and C<ALWAYS> into the package namespace.
These functions simply take messages as
arguments and forward them to the stealth loggers methods (C<debug()>,
C<info()>, and so on).

If a message should never be blocked, regardless of the log level,
use the C<ALWAYS> function which corresponds to a log level of C<OFF>:

    ALWAYS "This will be printed regardless of the log level";

The C<easy_init> method can be called with a single level value to
create a STDERR appender and a root logger as in

    Log::Log4perl->easy_init($DEBUG);

or, as shown below (and in the example above) 
with a reference to a hash, specifying values
for C<level> (the logger's priority), C<file> (the appender's data sink),
C<category> (the logger's category and C<layout> for the appender's 
pattern layout specification.
All key-value pairs are optional, they 
default to C<$DEBUG> for C<level>, C<STDERR> for C<file>,
C<""> (root category) for C<category> and 
C<%d %m%n> for C<layout>:

    Log::Log4perl->easy_init( { level    => $DEBUG,
                                file     => ">test.log",
                                utf8     => 1,
                                category => "Bar::Twix",
                                layout   => '%F{1}-%L-%M: %m%n' } );

The C<file> parameter takes file names preceded by C<"E<gt>">
(overwrite) and C<"E<gt>E<gt>"> (append) as arguments. This will
cause C<Log::Log4perl::Appender::File> appenders to be created behind
the scenes. Also the keywords C<STDOUT> and C<STDERR> (no C<E<gt>> or
C<E<gt>E<gt>>) are recognized, which will utilize and configure
C<Log::Log4perl::Appender::Screen> appropriately. The C<utf8> flag,
if set to a true value, runs a C<binmode> command on the file handle
to establish a utf8 line discipline on the file, otherwise you'll get a
'wide character in print' warning message and probably not what you'd
expect as output.

The stealth loggers can be used in different packages, you just need to make
sure you're calling the "use" function in every package you're using
C<Log::Log4perl>'s easy services:

    package Bar::Twix;
    use Log::Log4perl qw(:easy);
    sub eat { DEBUG("Twix mjam"); }

    package Bar::Mars;
    use Log::Log4perl qw(:easy);
    sub eat { INFO("Mars mjam"); }

    package main;

    use Log::Log4perl qw(:easy);

    Log::Log4perl->easy_init( { level    => $DEBUG,
                                file     => ">>test.log",
                                category => "Bar::Twix",
                                layout   => '%F{1}-%L-%M: %m%n' },
                              { level    => $DEBUG,
                                file     => "STDOUT",
                                category => "Bar::Mars",
                                layout   => '%m%n' },
                            );
    Bar::Twix::eat();
    Bar::Mars::eat();

As shown above, C<easy_init()> will take any number of different logger 
definitions as hash references.

Also, stealth loggers feature the functions C<LOGWARN()>, C<LOGDIE()>,
and C<LOGEXIT()>,
combining a logging request with a subsequent Perl warn() or die() or exit()
statement. So, for example

    if($all_is_lost) {
        LOGDIE("Terrible Problem");
    }

will log the message if the package's logger is at least C<FATAL> but
C<die()> (including the traditional output to STDERR) in any case afterwards.

See L<"Log and die or warn"> for the similar C<logdie()> and C<logwarn()>
functions of regular (i.e non-stealth) loggers.

Similarily, C<LOGCARP()>, C<LOGCLUCK()>, C<LOGCROAK()>, and C<LOGCONFESS()>
are provided in C<:easy> mode, facilitating the use of C<logcarp()>,
C<logcluck()>, C<logcroak()>, and C<logconfess()> with stealth loggers.

B<When using Log::Log4perl in easy mode, 
please make sure you understand the implications of 
L</"Pitfalls with Categories">>.

By the way, these convenience functions perform exactly as fast as the 
standard Log::Log4perl logger methods, there's I<no> performance penalty
whatsoever.

=head2 Nested Diagnostic Context (NDC)

If you find that your application could use a global (thread-specific)
data stack which your loggers throughout the system have easy access to,
use Nested Diagnostic Contexts (NDCs). Also check out
L<"Mapped Diagnostic Context (MDC)">, this might turn out to be even more
useful.

For example, when handling a request of a web client, it's probably 
useful to have the user's IP address available in all log statements
within code dealing with this particular request. Instead of passing
this piece of data around between your application functions, you can just
use the global (but thread-specific) NDC mechanism. It allows you
to push data pieces (scalars usually) onto its stack via

    Log::Log4perl::NDC->push("San");
    Log::Log4perl::NDC->push("Francisco");

and have your loggers retrieve them again via the "%x" placeholder in
the PatternLayout. With the stack values above and a PatternLayout format
like "%x %m%n", the call

    $logger->debug("rocks");

will end up as 

    San Francisco rocks

in the log appender.

The stack mechanism allows for nested structures.
Just make sure that at the end of the request, you either decrease the stack
one by one by calling

    Log::Log4perl::NDC->pop();
    Log::Log4perl::NDC->pop();

or clear out the entire NDC stack by calling

    Log::Log4perl::NDC->remove();

Even if you should forget to do that, C<Log::Log4perl> won't grow the stack
indefinitely, but limit it to a maximum, defined in C<Log::Log4perl::NDC>
(currently 5). A call to C<push()> on a full stack will just replace
the topmost element by the new value.

Again, the stack is always available via the "%x" placeholder
in the Log::Log4perl::Layout::PatternLayout class whenever a logger
fires. It will replace "%x" by the blank-separated list of the
values on the stack. It does that by just calling

    Log::Log4perl::NDC->get();

internally. See details on how this standard log4j feature is implemented
in L<Log::Log4perl::NDC>.

=head2 Mapped Diagnostic Context (MDC)

Just like the previously discussed NDC stores thread-specific
information in a stack structure, the MDC implements a hash table
to store key/value pairs in.

The static method

    Log::Log4perl::MDC->put($key, $value);

stores C<$value> under a key C<$key>, with which it can be retrieved later
(possibly in a totally different part of the system) by calling
the C<get> method:

    my $value = Log::Log4perl::MDC->get($key);

If no value has been stored previously under C<$key>, the C<get> method
will return C<undef>.

Typically, MDC values are retrieved later on via the C<"%X{...}"> placeholder
in C<Log::Log4perl::Layout::PatternLayout>. If the C<get()> method
returns C<undef>, the placeholder will expand to the string C<[undef]>.

An application taking a web request might store the remote host
like

    Log::Log4perl::MDC->put("remote_host", $r->headers("HOST"));

at its beginning and if the appender's layout looks something like

    log4perl.appender.Logfile.layout.ConversionPattern = %X{remote_host}: %m%n

then a log statement like

   DEBUG("Content delivered");

will log something like

   adsl-63.dsl.snf.pacbell.net: Content delivered 

later on in the program.

For details, please check L<Log::Log4perl::MDC>.

=head2 Resurrecting hidden Log4perl Statements

Sometimes scripts need to be deployed in environments without having
Log::Log4perl installed yet. On the other hand, you don't want to
live without your Log4perl statements -- they're gonna come in
handy later.

So, just deploy your script with Log4perl statements commented out with the
pattern C<###l4p>, like in

    ###l4p DEBUG "It works!";
    # ...
    ###l4p INFO "Really!";

If Log::Log4perl is available,
use the C<:resurrect> tag to have Log4perl resurrect those buried 
statements before the script starts running:

    use Log::Log4perl qw(:resurrect :easy);

    ###l4p Log::Log4perl->easy_init($DEBUG);
    ###l4p DEBUG "It works!";
    # ...
    ###l4p INFO "Really!";

This will have a source filter kick in and indeed print

    2004/11/18 22:08:46 It works!
    2004/11/18 22:08:46 Really!

In environments lacking Log::Log4perl, just comment out the first line
and the script will run nevertheless (but of course without logging):

    # use Log::Log4perl qw(:resurrect :easy);

    ###l4p Log::Log4perl->easy_init($DEBUG);
    ###l4p DEBUG "It works!";
    # ...
    ###l4p INFO "Really!";

because everything's a regular comment now. Alternatively, put the
magic Log::Log4perl comment resurrection line into your shell's 
PERL5OPT environment variable, e.g. for bash:

    set PERL5OPT=-MLog::Log4perl=:resurrect,:easy
    export PERL5OPT

This will awaken the giant within an otherwise silent script like
the following:

    #!/usr/bin/perl

    ###l4p Log::Log4perl->easy_init($DEBUG);
    ###l4p DEBUG "It works!";

As of C<Log::Log4perl> 1.12, you can even force I<all> modules
loaded by a script to have their hidden Log4perl statements
resurrected. For this to happen, load C<Log::Log4perl::Resurrector>
I<before> loading any modules:

    use Log::Log4perl qw(:easy);
    use Log::Log4perl::Resurrector;

    use Foobar; # All hidden Log4perl statements in here will
                # be uncommented before Foobar gets loaded.

    Log::Log4perl->easy_init($DEBUG);
    ...

Check the C<Log::Log4perl::Resurrector> manpage for more details.

=head2 Access defined appenders

All appenders defined in the configuration file or via Perl code
can be retrieved by the C<appender_by_name()> class method. This comes
in handy if you want to manipulate or query appender properties after
the Log4perl configuration has been loaded via C<init()>.

Note that internally, Log::Log4perl uses the C<Log::Log4perl::Appender> 
wrapper class to control the real appenders (like 
C<Log::Log4perl::Appender::File> or C<Log::Dispatch::FileRotate>). 
The C<Log::Log4perl::Appender> class has an C<appender> attribute,
pointing to the real appender.

The reason for this is that external appenders like 
C<Log::Dispatch::FileRotate> don't support all of Log::Log4perl's 
appender control mechanisms (like appender thresholds).

The previously mentioned method C<appender_by_name()> returns a
reference to the I<real> appender object. If you want access to the
wrapper class (e.g. if you want to modify the appender's threshold),
use the hash C<$Log::Log4perl::Logger::APPENDER_BY_NAME{...}> instead,
which holds references to all appender wrapper objects.

=head2 Modify appender thresholds

To set an appender's threshold, use its C<threshold()> method:

    $app->threshold( $FATAL );

To conveniently adjust I<all> appender thresholds (e.g. because a script
uses more_logging()), use

       # decrease thresholds of all appenders
    Log::Log4perl->appender_thresholds_adjust(-1);

This will decrease the thresholds of all appenders in the system by
one level, i.e. WARN becomes INFO, INFO becomes DEBUG, etc. To only modify 
selected ones, use

       # decrease thresholds of selected appenders
    Log::Log4perl->appender_thresholds_adjust(-1, ['AppName1', ...]);

and pass the names of affected appenders in a ref to an array.

=head1 Advanced configuration within Perl

Initializing Log::Log4perl can certainly also be done from within Perl.
At last, this is what C<Log::Log4perl::Config> does behind the scenes.
Log::Log4perl's configuration file parsers are using a publically 
available API to set up Log::Log4perl's categories, appenders and layouts.

Here's an example on how to configure two appenders with the same layout
in Perl, without using a configuration file at all:

  ########################
  # Initialization section
  ########################
  use Log::Log4perl;
  use Log::Log4perl::Layout;
  use Log::Log4perl::Level;

     # Define a category logger
  my $log = Log::Log4perl->get_logger("Foo::Bar");

     # Define a layout
  my $layout = Log::Log4perl::Layout::PatternLayout->new("[%r] %F %L %m%n");

     # Define a file appender
  my $file_appender = Log::Log4perl::Appender->new(
                          "Log::Log4perl::Appender::File",
                          name      => "filelog",
                          filename  => "/tmp/my.log");

     # Define a stdout appender
  my $stdout_appender =  Log::Log4perl::Appender->new(
                          "Log::Log4perl::Appender::Screen",
                          name      => "screenlog",
                          stderr    => 0);

     # Define a mixed stderr/stdout appender
  my $mixed_stdout_stderr_appender = Log::Log4perl::Appender->new(
                          "Log::Log4perl::Appender::Screen",
                          name      => "screenlog",
                          stderr    => { ERROR => 1, FATAL => 1 });

     # Have both appenders use the same layout (could be different)
  $stdout_appender->layout($layout);
  $file_appender->layout($layout);

  $log->add_appender($stdout_appender);
  $log->add_appender($file_appender);
  $log->level($INFO);

Please note the class of the appender object is passed as a I<string> to
C<Log::Log4perl::Appender> in the I<first> argument. Behind the scenes,
C<Log::Log4perl::Appender> will create the necessary
C<Log::Log4perl::Appender::*> (or C<Log::Dispatch::*>) object and pass
along the name value pairs we provided to
C<Log::Log4perl::Appender-E<gt>new()> after the first argument.

The C<name> value is optional and if you don't provide one,
C<Log::Log4perl::Appender-E<gt>new()> will create a unique one for you.
The names and values of additional parameters are dependent on the requirements
of the particular appender class and can be looked up in their
manual pages.

A side note: In case you're wondering if
C<Log::Log4perl::Appender-E<gt>new()> will also take care of the
C<min_level> argument to the C<Log::Dispatch::*> constructors called
behind the scenes -- yes, it does. This is because we want the
C<Log::Dispatch> objects to blindly log everything we send them
(C<debug> is their lowest setting) because I<we> in C<Log::Log4perl>
want to call the shots and decide on when and what to log.

The call to the appender's I<layout()> method specifies the format (as a
previously created C<Log::Log4perl::Layout::PatternLayout> object) in which the
message is being logged in the specified appender. 
If you don't specify a layout, the logger will fall back to
C<Log::Log4perl::SimpleLayout>, which logs the debug level, a hyphen (-)
and the log message.

Layouts are objects, here's how you create them:

        # Create a simple layout
    my $simple = Log::Log4perl::SimpleLayout();

        # create a flexible layout:
        # ("yyyy/MM/dd hh:mm:ss (file:lineno)> message\n")
    my $pattern = Log::Log4perl::Layout::PatternLayout("%d (%F:%L)> %m%n");

Every appender has exactly one layout assigned to it. You assign
the layout to the appender using the appender's C<layout()> object:

    my $app =  Log::Log4perl::Appender->new(
                  "Log::Log4perl::Appender::Screen",
                  name      => "screenlog",
                  stderr    => 0);

        # Assign the previously defined flexible layout
    $app->layout($pattern);

        # Add the appender to a previously defined logger
    $logger->add_appender($app);

        # ... and you're good to go!
    $logger->debug("Blah");
        # => "2002/07/10 23:55:35 (test.pl:207)> Blah\n"

It's also possible to remove appenders from a logger:

    $logger->remove_appender($appender_name);

will remove an appender, specified by name, from a given logger. 
Please note that this does
I<not> remove an appender from the system.

To eradicate an appender from the system, 
you need to call C<Log::Log4perl-E<gt>eradicate_appender($appender_name)>
which will first remove the appender from every logger in the system
and then will delete all references Log4perl holds to it.

To remove a logger from the system, use 
C<Log::Log4perl-E<gt>remove_logger($logger)>. After the remaining 
reference C<$logger> goes away, the logger will self-destruct. If the
logger in question is a stealth logger, all of its convenience shortcuts
(DEBUG, INFO, etc) will turn into no-ops.

=head1 How about Log::Dispatch::Config?

Tatsuhiko Miyagawa's C<Log::Dispatch::Config> is a very clever 
simplified logger implementation, covering some of the I<log4j>
functionality. Among the things that 
C<Log::Log4perl> can but C<Log::Dispatch::Config> can't are:

=over 4

=item *

You can't assign categories to loggers. For small systems that's fine,
but if you can't turn off and on detailed logging in only a tiny
subsystem of your environment, you're missing out on a majorly
useful log4j feature.

=item *

Defining appender thresholds. Important if you want to solve problems like
"log all messages of level FATAL to STDERR, plus log all DEBUG
messages in C<Foo::Bar> to a log file". If you don't have appenders
thresholds, there's no way to prevent cluttering STDERR with DEBUG messages.

=item *

PatternLayout specifications in accordance with the standard
(e.g. "%d{HH:mm}").

=back

Bottom line: Log::Dispatch::Config is fine for small systems with
simple logging requirements. However, if you're
designing a system with lots of subsystems which you need to control
independently, you'll love the features of C<Log::Log4perl>,
which is equally easy to use.

=head1 Using Log::Log4perl with wrapper functions and classes

If you don't use C<Log::Log4perl> as described above, 
but from a wrapper function, the pattern layout will generate wrong data 
for %F, %C, %L, and the like. Reason for this is that C<Log::Log4perl>'s 
loggers assume a static caller depth to the application that's using them. 

If you're using
one (or more) wrapper functions, C<Log::Log4perl> will indicate where
your logger function called the loggers, not where your application
called your wrapper:

    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init({ level => $DEBUG, 
                               layout => "%M %m%n" });

    sub mylog {
        my($message) = @_;

        DEBUG $message;
    }

    sub func {
        mylog "Hello";
    }

    func();

prints

    main::mylog Hello

but that's probably not what your application expects. Rather, you'd
want

    main::func Hello

because the C<func> function called your logging function.

But don't despair, there's a solution: Just register your wrapper
package with Log4perl beforehand. If Log4perl then finds that it's being 
called from a registered wrapper, it will automatically step up to the
next call frame.

    Log::Log4perl->wrapper_register(__PACKAGE__);

    sub mylog {
        my($message) = @_;

        DEBUG $message;
    }

Alternatively, you can increase the value of the global variable
C<$Log::Log4perl::caller_depth> (defaults to 0) by one for every
wrapper that's in between your application and C<Log::Log4perl>,
then C<Log::Log4perl> will compensate for the difference:

    sub mylog {
        my($message) = @_;

        local $Log::Log4perl::caller_depth =
              $Log::Log4perl::caller_depth + 1;
        DEBUG $message;
    }

Also, note that if you're writing a subclass of Log4perl, like

    package MyL4pWrapper;
    use Log::Log4perl;
    our @ISA = qw(Log::Log4perl);

and you want to call get_logger() in your code, like

    use MyL4pWrapper;

    sub get_logger {
        my $logger = Log::Log4perl->get_logger();
    }

then the get_logger() call will get a logger for the C<MyL4pWrapper>
category, not for the package calling the wrapper class as in

    package UserPackage;
    my $logger = MyL4pWrapper->get_logger();

To have the above call to get_logger return a logger for the 
"UserPackage" category, you need to tell Log4perl that "MyL4pWrapper"
is a Log4perl wrapper class:

    use MyL4pWrapper;
    Log::Log4perl->wrapper_register(__PACKAGE__);

    sub get_logger {
          # Now gets a logger for the category of the calling package
        my $logger = Log::Log4perl->get_logger();
    }

This feature works both for Log4perl-relaying classes like the wrapper
described above, and for wrappers that inherit from Log4perl use Log4perl's
get_logger function via inheritance, alike.

=head1 Access to Internals

The following methods are only of use if you want to peek/poke in
the internals of Log::Log4perl. Be careful not to disrupt its
inner workings.

=over 4

=item C<< Log::Log4perl->appenders() >>

To find out which appenders are currently defined (not only
for a particular logger, but overall), a C<appenders()>
method is available to return a reference to a hash mapping appender
names to their Log::Log4perl::Appender object references.

=back

=head1 Dirty Tricks

=over 4

=item infiltrate_lwp()

The famous LWP::UserAgent module isn't Log::Log4perl-enabled. Often, though,
especially when tracing Web-related problems, it would be helpful to get
some insight on what's happening inside LWP::UserAgent. Ideally, LWP::UserAgent
would even play along in the Log::Log4perl framework.

A call to C<Log::Log4perl-E<gt>infiltrate_lwp()> does exactly this. 
In a very rude way, it pulls the rug from under LWP::UserAgent and transforms
its C<debug/conn> messages into C<debug()> calls of loggers of the category
C<"LWP::UserAgent">. Similarily, C<LWP::UserAgent>'s C<trace> messages 
are turned into C<Log::Log4perl>'s C<info()> method calls. Note that this
only works for LWP::UserAgent versions E<lt> 5.822, because this (and
probably later) versions miss debugging functions entirely.

=item Suppressing 'duplicate' LOGDIE messages

If a script with a simple Log4perl configuration uses logdie() to catch
errors and stop processing, as in 

    use Log::Log4perl qw(:easy) ;
    Log::Log4perl->easy_init($DEBUG);
    
    shaky_function() or LOGDIE "It failed!";

there's a cosmetic problem: The message gets printed twice:

    2005/07/10 18:37:14 It failed!
    It failed! at ./t line 12

The obvious solution is to use LOGEXIT() instead of LOGDIE(), but there's
also a special tag for Log4perl that suppresses the second message:

    use Log::Log4perl qw(:no_extra_logdie_message);

This causes logdie() and logcroak() to call exit() instead of die(). To
modify the script exit code in these occasions, set the variable
C<$Log::Log4perl::LOGEXIT_CODE> to the desired value, the default is 1.

=item Redefine values without causing errors

Log4perl's configuration file parser has a few basic safety mechanisms to 
make sure configurations are more or less sane. 

One of these safety measures is catching redefined values. For example, if
you first write

    log4perl.category = WARN, Logfile

and then a couple of lines later

    log4perl.category = TRACE, Logfile

then you might have unintentionally overwritten the first value and Log4perl
will die on this with an error (suspicious configurations always throw an
error). Now, there's a chance that this is intentional, for example when
you're lumping together several configuration files and actually I<want>
the first value to overwrite the second. In this case use

    use Log::Log4perl qw(:nostrict);

to put Log4perl in a more permissive mode.

=item Prevent croak/confess from stringifying

The logcroak/logconfess functions stringify their arguments before
they pass them to Carp's croak/confess functions. This can get in the
way if you want to throw an object or a hashref as an exception, in
this case use:

    $Log::Log4perl::STRINGIFY_DIE_MESSAGE = 0;

    eval {
          # throws { foo => "bar" }
          # without stringification
        $logger->logcroak( { foo => "bar" } );
    };

=back

=head1 EXAMPLE

A simple example to cut-and-paste and get started:

    use Log::Log4perl qw(get_logger);
    
    my $conf = q(
    log4perl.category.Bar.Twix         = WARN, Logfile
    log4perl.appender.Logfile          = Log::Log4perl::Appender::File
    log4perl.appender.Logfile.filename = test.log
    log4perl.appender.Logfile.layout = \
        Log::Log4perl::Layout::PatternLayout
    log4perl.appender.Logfile.layout.ConversionPattern = %d %F{1} %L> %m %n
    );
    
    Log::Log4perl::init(\$conf);
    
    my $logger = get_logger("Bar::Twix");
    $logger->error("Blah");

This will log something like

    2002/09/19 23:48:15 t1 25> Blah 

to the log file C<test.log>, which Log4perl will append to or 
create it if it doesn't exist already.

=head1 INSTALLATION

If you want to use external appenders provided with C<Log::Dispatch>,
you need to install C<Log::Dispatch> (2.00 or better) from CPAN,
which itself depends on C<Attribute-Handlers> and
C<Params-Validate>. And a lot of other modules, that's the reason
why we're now shipping Log::Log4perl with its own standard appenders
and only if you wish to use additional ones, you'll have to go through
the C<Log::Dispatch> installation process.

Log::Log4perl needs C<Test::More>, C<Test::Harness> and C<File::Spec>, 
but they already come with fairly recent versions of perl.
If not, everything's automatically fetched from CPAN if you're using the CPAN 
shell (CPAN.pm), because they're listed as dependencies.

C<Time::HiRes> (1.20 or better) is required only if you need the
fine-grained time stamps of the C<%r> parameter in
C<Log::Log4perl::Layout::PatternLayout>.

Manual installation works as usual with

    perl Makefile.PL
    make
    make test
    make install

=head1 DEVELOPMENT

Log::Log4perl is still being actively developed. We will
always make sure the test suite (approx. 500 cases) will pass, but there 
might still be bugs. please check L<http://github.com/mschilli/log4perl>
for the latest release. The api has reached a mature state, we will 
not change it unless for a good reason.

Bug reports and feedback are always welcome, just email them to our 
mailing list shown in the AUTHORS section. We're usually addressing
them immediately.

=head1 REFERENCES

=over 4

=item [1]

Michael Schilli, "Retire your debugger, log smartly with Log::Log4perl!",
Tutorial on perl.com, 09/2002, 
L<http://www.perl.com/pub/a/2002/09/11/log4perl.html>

=item [2]

Ceki Gülcü, "Short introduction to log4j",
L<http://logging.apache.org/log4j/1.2/manual.html>

=item [3]

Vipan Singla, "Don't Use System.out.println! Use Log4j.",
L<http://www.vipan.com/htdocs/log4jhelp.html>

=item [4]

The Log::Log4perl project home page: L<http://log4perl.com>

=back

=head1 SEE ALSO

L<Log::Log4perl::Config|Log::Log4perl::Config>,
L<Log::Log4perl::Appender|Log::Log4perl::Appender>,
L<Log::Log4perl::Layout::PatternLayout|Log::Log4perl::Layout::PatternLayout>,
L<Log::Log4perl::Layout::SimpleLayout|Log::Log4perl::Layout::SimpleLayout>,
L<Log::Log4perl::Level|Log::Log4perl::Level>,
L<Log::Log4perl::JavaMap|Log::Log4perl::JavaMap>
L<Log::Log4perl::NDC|Log::Log4perl::NDC>,

=head1 AUTHORS

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
Grundman, Paul Harrington, Alexander Hartmaier, David Hull, 
Robert Jacobson, Jason Kohles, Jeff Macdonald, Markus Peter, 
Brett Rann, Peter Rabbitson, Erik Selberg, Aaron Straup Cope, 
Lars Thegler, David Viner, Mac Yang.

=head1 LICENSE

Copyright 2002-2013 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

