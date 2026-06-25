##################################################
package Log::Log4perl::Appender;
##################################################

use 5.006;
use strict;
use warnings;

use Log::Log4perl::Level;
use Carp;

use constant _INTERNAL_DEBUG => 0;

our $unique_counter = 0;

##################################################
sub reset {
##################################################
    $unique_counter = 0;
}

##################################################
sub unique_name {
##################################################
        # THREADS: Need to lock here to make it thread safe
    $unique_counter++;
    my $unique_name = sprintf("app%03d", $unique_counter);
        # THREADS: Need to unlock here to make it thread safe
    return $unique_name;
}

##################################################
sub new {
##################################################
    my($class, $appenderclass, %params) = @_;

        # Pull in the specified Log::Log4perl::Appender object
    eval {

           # Eval erroneously succeeds on unknown appender classes if
           # the eval string just consists of valid perl code (e.g. an
           # appended ';' in $appenderclass variable). Fail if we see
           # anything in there that can't be class name.
        die "'$appenderclass' not a valid class name " if 
            $appenderclass =~ /[^:\w]/;

        # Check if the class/package is already available because
        # something like Class::Prototyped injected it previously.

        # Use UNIVERSAL::can to check the appender's new() method
        # [RT 28987]
        if( ! $appenderclass->can('new') ) {
            # Not available yet, try to pull it in.
            # see 'perldoc -f require' for why two evals
            eval "require $appenderclass";
                 #unless ${$appenderclass.'::IS_LOADED'};  #for unit tests, 
                                                          #see 004Config
            die $@ if $@;
        }
    };

    $@ and die "ERROR: can't load appenderclass '$appenderclass'\n$@";
    print "Appender class $appenderclass loaded OK ($@)\n" if _INTERNAL_DEBUG;

    $params{name} = unique_name() unless exists $params{name};

    # If it's a Log::Dispatch::File appender, default to append 
    # mode (Log::Dispatch::File defaults to 'clobber') -- consensus 9/2002
    # (Log::Log4perl::Appender::File already defaults to 'append')
    if ($appenderclass eq 'Log::Dispatch::File' &&
        ! exists $params{mode}) {
        $params{mode} = 'append';
    }

    print "Calling $appenderclass new\n" if _INTERNAL_DEBUG;

    my $appender = $appenderclass->new(
            # Set min_level to the lowest setting. *we* are 
            # controlling this now, the appender should just
            # log it with no questions asked.
        min_level => 'debug',
            # Set 'name' and other parameters
        map { $_ => $params{$_} } keys %params,
    );

    print "Calling $appenderclass new returned OK\n" if _INTERNAL_DEBUG;

    my $self = {
                 appender  => $appender,
                 name      => $params{name},
                 layout    => undef,
                 level     => $ALL,
                 composite => 0,
               };

        #whether to collapse arrays, etc.
    $self->{warp_message} = $params{warp_message};

    if (!$INC{'Log/Log4perl/Config.pm'}) {
        require Log::Log4perl::Config;
    }

    if($self->{warp_message} and
       my $cref = 
       Log::Log4perl::Config::compile_if_perl($self->{warp_message})) {
        $self->{warp_message} = $cref;
    }
    
    bless $self, $class;

    return $self;
}

##################################################
sub composite { # Set/Get the composite flag
##################################################
    my ($self, $flag) = @_;

    $self->{composite} = $flag if defined $flag;
    return $self->{composite};
}

##################################################
sub threshold { # Set/Get the appender threshold
##################################################
    my ($self, $level) = @_;

    print "Setting threshold to $level\n" if _INTERNAL_DEBUG;

    if(defined $level) {
        # Checking for \d makes for a faster regex(p)
        $self->{level} = ($level =~ /^(\d+)$/) ? $level :
            # Take advantage of &to_priority's error reporting
            Log::Log4perl::Level::to_priority($level);
    }

    return $self->{level};
}

##################################################
sub log { 
##################################################
# Relay this call to Log::Log4perl::Appender:* or
# Log::Dispatch::*
##################################################
    my ($self, $p, $category, $level, $cache) = @_;

    # Check if the appender has a last-minute veto in form
    # of an "appender threshold"
    if($self->{level} > $
                        Log::Log4perl::Level::PRIORITY{$level}) {
        print "$self->{level} > $level, aborting\n" if _INTERNAL_DEBUG;
        return undef;
    }

    # Run against the (yes only one) customized filter (which in turn
    # might call other filters via the Boolean filter) and check if its
    # ok() method approves the message or blocks it.
    if($self->{filter}) {
        if($self->{filter}->ok(%$p,
                               log4p_category => $category,
                               log4p_level    => $level )) {
            print "Filter $self->{filter}->{name} passes\n" if _INTERNAL_DEBUG;
        } else {
            print "Filter $self->{filter}->{name} blocks\n" if _INTERNAL_DEBUG;
            return undef;
        }
    }

    unless($self->composite()) {

            #not defined, the normal case
        if (! defined $self->{warp_message} ){
                #join any message elements
            if (ref $p->{message} eq "ARRAY") {
                for my $i (0..$#{$p->{message}}) {
                    if( !defined $p->{message}->[ $i ] ) {
                        local $Carp::CarpLevel =
                        $Carp::CarpLevel + $Log::Log4perl::caller_depth + 1;
                        carp "Warning: Log message argument #" . 
                             ($i+1) . " undefined";
                    }
                }
                $p->{message} = 
                    join($Log::Log4perl::JOIN_MSG_ARRAY_CHAR, 
                         @{$p->{message}} 
                         );
            }
            
            #defined but false, e.g. Appender::DBI
        } elsif (! $self->{warp_message}) {
            ;  #leave the message alone
    
        } elsif (ref($self->{warp_message}) eq "CODE") {
            #defined and a subref
            $p->{message} = 
                [$self->{warp_message}->(@{$p->{message}})];
        } else {
            #defined and a function name?
            no strict qw(refs);
            $p->{message} = 
                [$self->{warp_message}->(@{$p->{message}})];
        }

        $p->{message} = $self->{layout}->render($p->{message}, 
            $category,
            $level,
            3 + $Log::Log4perl::caller_depth,
        ) if $self->layout();
    }

    my $args = [%$p, log4p_category => $category, log4p_level => $level];

    if(defined $cache) {
        $$cache = $args;
    } else {
        $self->{appender}->log(@$args);
    }

    return 1;
}

###########################################
sub log_cached {
###########################################
    my ($self, $cache) = @_;

    $self->{appender}->log(@$cache);
}

##################################################
sub name { # Set/Get the name
##################################################
    my($self, $name) = @_;

        # Somebody wants to *set* the name?
    if($name) {
        $self->{name} = $name;
    }

    return $self->{name};
}

###########################################
sub layout { # Set/Get the layout object
             # associated with this appender
###########################################
    my($self, $layout) = @_;

        # Somebody wants to *set* the layout?
    if($layout) {
        $self->{layout} = $layout;

        # somebody wants a layout, but not set yet, so give 'em default
    }elsif (! $self->{layout}) {
        $self->{layout} = Log::Log4perl::Layout::SimpleLayout
                                                ->new($self->{name});

    }

    return $self->{layout};
}

##################################################
sub filter { # Set filter
##################################################
    my ($self, $filter) = @_;

    if($filter) {
        print "Setting filter to $filter->{name}\n" if _INTERNAL_DEBUG;
        $self->{filter} = $filter;
    }

    return $self->{filter};
}

##################################################
sub AUTOLOAD { 
##################################################
# Relay everything else to the underlying 
# Log::Log4perl::Appender::* or Log::Dispatch::*
#  object
##################################################
    my $self = shift;

    no strict qw(vars);

    $AUTOLOAD =~ s/.*:://;

    if(! defined $self->{appender}) {
        die "Can't locate object method $AUTOLOAD() in ", __PACKAGE__;
    }

    return $self->{appender}->$AUTOLOAD(@_);
}

##################################################
sub DESTROY {
##################################################
    foreach my $key (keys %{$_[0]}) {
        # print "deleting $key\n";
        delete $_[0]->{$key};
    }
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Appender - Log appender class

=head1 SYNOPSIS

  use Log::Log4perl;

      # Define a logger
  my $logger = Log::Log4perl->get_logger("abc.def.ghi");

      # Define a layout
  my $layout = Log::Log4perl::Layout::PatternLayout->new(
                   "%d (%F:%L)> %m");

      # Define an appender
  my $appender = Log::Log4perl::Appender->new(
                   "Log::Log4perl::Appender::Screen",
                   name => 'dumpy');

      # Set the appender's layout
  $appender->layout($layout);
  $logger->add_appender($appender);

=head1 DESCRIPTION

This class is a wrapper around the C<Log::Log4perl::Appender>
appender set. 

It also supports the <Log::Dispatch::*> collections of appenders. The
module hides the idiosyncrasies of C<Log::Dispatch> (e.g. every
dispatcher gotta have a name, but there's no accessor to retrieve it)
from C<Log::Log4perl> and yet re-uses the extremely useful variety of
dispatchers already created and tested in C<Log::Dispatch>.

=head1 FUNCTIONS

=head2 Log::Log4perl::Appender->new($dispatcher_class_name, ...);

The constructor C<new()> takes the name of the appender
class to be created as a I<string> (!) argument, optionally followed by 
a number of appender-specific parameters,
for example:

      # Define an appender
  my $appender = Log::Log4perl::Appender->new(
      "Log::Log4perl::Appender::File"
      filename => 'out.log');

In case of C<Log::Dispatch> appenders,
if no C<name> parameter is specified, the appender object will create
a unique one (format C<appNNN>), which can be retrieved later via
the C<name()> method:

  print "The appender's name is ", $appender->name(), "\n";

Other parameters are specific to the appender class being used.
In the case above, the C<filename> parameter specifies the name of 
the C<Log::Log4perl::Appender::File> dispatcher used. 

However, if, for instance, 
you're using a C<Log::Dispatch::Email> dispatcher to send you 
email, you'll have to specify C<from> and C<to> email addresses.
Every dispatcher is different.
Please check the C<Log::Dispatch::*> documentation for the appender used
for details on specific requirements.

The C<new()> method will just pass these parameters on to a newly created
C<Log::Dispatch::*> object of the specified type.

When it comes to logging, the C<Log::Log4perl::Appender> will transparently
relay all messages to the C<Log::Dispatch::*> object it carries 
in its womb.

=head2 $appender->layout($layout);

The C<layout()> method sets the log layout
used by the appender to the format specified by the 
C<Log::Log4perl::Layout::*> object which is passed to it as a reference.
Currently there's two layouts available:

    Log::Log4perl::Layout::SimpleLayout
    Log::Log4perl::Layout::PatternLayout

Please check the L<Log::Log4perl::Layout::SimpleLayout> and 
L<Log::Log4perl::Layout::PatternLayout> manual pages for details.

=head1 Supported Appenders 

Here's the list of appender modules currently available via C<Log::Dispatch>,
if not noted otherwise, written by Dave Rolsky:

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

C<Log4perl> doesn't care which ones you use, they're all handled in 
the same way via the C<Log::Log4perl::Appender> interface.
Please check the well-written manual pages of the 
C<Log::Dispatch> hierarchy on how to use each one of them.

=head1 Parameters passed on to the appender's log() method

When calling the appender's log()-Funktion, Log::Log4perl will 
submit a list of key/value pairs. Entries to the following keys are
guaranteed to be present:

=over 4

=item message

Text of the rendered message

=item log4p_category

Name of the category of the logger that triggered the event.

=item log4p_level

Log::Log4perl level of the event

=back

=head1 Pitfalls

Since the C<Log::Dispatch::File> appender truncates log files by default,
and most of the time this is I<not> what you want, we've instructed 
C<Log::Log4perl> to change this behavior by slipping it the 
C<mode =E<gt> append> parameter behind the scenes. So, effectively
with C<Log::Log4perl> 0.23, a configuration like

    log4perl.category = INFO, FileAppndr
    log4perl.appender.FileAppndr          = Log::Dispatch::File
    log4perl.appender.FileAppndr.filename = test.log
    log4perl.appender.FileAppndr.layout   = Log::Log4perl::Layout::SimpleLayout

will always I<append> to an existing logfile C<test.log> while if you 
specifically request clobbering like in

    log4perl.category = INFO, FileAppndr
    log4perl.appender.FileAppndr          = Log::Dispatch::File
    log4perl.appender.FileAppndr.filename = test.log
    log4perl.appender.FileAppndr.mode     = write
    log4perl.appender.FileAppndr.layout   = Log::Log4perl::Layout::SimpleLayout

it will overwrite an existing log file C<test.log> and start from scratch.

=head1 Appenders Expecting Message Chunks

Instead of simple strings, certain appenders are expecting multiple fields
as log messages. If a statement like 

    $logger->debug($ip, $user, "signed in");

causes an off-the-shelf C<Log::Log4perl::Appender::Screen> 
appender to fire, the appender will 
just concatenate the three message chunks passed to it
in order to form a single string.
The chunks will be separated by a string defined in 
C<$Log::Log4perl::JOIN_MSG_ARRAY_CHAR> (defaults to the empty string
""). 

However, different appenders might choose to 
interpret the message above differently: An
appender like C<Log::Log4perl::Appender::DBI> might take the
three arguments passed to the logger and put them in three separate
rows into the DB.

The  C<warp_message> appender option is used to specify the desired 
behavior.
If no setting for the appender property

    # *** Not defined ***
    # log4perl.appender.SomeApp.warp_message

is defined in the Log4perl configuration file, the
appender referenced by C<SomeApp> will fall back to the standard behavior
and join all message chunks together, separating them by
C<$Log::Log4perl::JOIN_MSG_ARRAY_CHAR>.

If, on the other hand, it is set to a false value, like in

    log4perl.appender.SomeApp.layout=NoopLayout
    log4perl.appender.SomeApp.warp_message = 0

then the message chunks are passed unmodified to the appender as an
array reference. Please note that you need to set the appender's
layout to C<Log::Log4perl::Layout::NoopLayout> which just leaves 
the messages chunks alone instead of formatting them or replacing
conversion specifiers.

B<Please note that the standard appenders in the Log::Dispatch hierarchy
will choke on a bunch of messages passed to them as an array reference. 
You can't use C<warp_message = 0> (or the function name syntax
defined below) on them.
Only special appenders like Log::Log4perl::Appender::DBI can deal with
this.>

If (and now we're getting fancy)
an appender expects message chunks, but we would 
like to pre-inspect and probably modify them before they're 
actually passed to the appender's C<log>
method, an inspection subroutine can be defined with the
appender's C<warp_message> property:

    log4perl.appender.SomeApp.layout=NoopLayout
    log4perl.appender.SomeApp.warp_message = sub { \
                                           $#_ = 2 if @_ > 3; \
                                           return @_; }

The inspection subroutine defined by the C<warp_message> 
property will receive the list of message chunks, like they were
passed to the logger and is expected to return a corrected list.
The example above simply limits the argument list to a maximum of
three by cutting off excess elements and returning the shortened list.

Also, the warp function can be specified by name like in

    log4perl.appender.SomeApp.layout=NoopLayout
    log4perl.appender.SomeApp.warp_message = main::filter_my_message

In this example,
C<filter_my_message> is a function in the C<main> package, 
defined like this:

    my $COUNTER = 0;

    sub filter_my_message {
        my @chunks = @_;
        unshift @chunks, ++$COUNTER;
        return @chunks;
    }

The subroutine above will add an ever increasing counter
as an additional first field to 
every message passed to the C<SomeApp> appender -- but not to
any other appender in the system.

=head2 Composite Appenders

Composite appenders relay their messages to sub-appenders after providing
some filtering or synchronizing functionality on incoming messages. 
Examples are 
Log::Log4perl::Appender::Synchronized,
Log::Log4perl::Appender::Limit, and
Log::Log4perl::Appender::Buffer. Check their manual pages for details.

Composite appender objects are regular Log::Log4perl::Appender objects, 
but they have the composite flag set:

    $app->composite(1);

and they define a post_init() method, which sets the appender it relays
its messages to:

    ###########################################
    sub post_init {
    ############################################
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

The reason for this post-processing step is that the relay appender
might not be defined yet when the composite appender gets defined.
This can happen if Log4perl is initialized with a configuration file
(which is the most common way to initialize Log4perl), because
appenders spring into existence in unpredictable order.

For example, if you define a Synchronized appender like

    log4perl.appender.Syncer            = Log::Log4perl::Appender::Synchronized
    log4perl.appender.Syncer.appender   = Logfile

then Log4perl will set the appender's C<appender> attribute to the
I<name> of the appender to finally relay messages to. After the
Log4perl configuration file has been processed, Log4perl will remember to 
call the composite appender's post_init() method, which will grab
the relay appender instance referred to by the name (Logfile) 
and set it in its C<app> attribute. This is exactly what the
code snippet above does.

But if you initialize Log4perl by its API, you need to remember to
perform these steps. Here's the lineup:

    use Log::Log4perl qw(get_logger :levels);
    
    my $fileApp = Log::Log4perl::Appender->new(
    		'Log::Log4perl::Appender::File',
    		name     => 'MyFileApp',
    		filename => 'mylog',
    		mode     => 'append',
    		);
    $fileApp->layout(
    		Log::Log4perl::Layout::PatternLayout::Multiline->new(
    			'%d{yyyy-MM-dd HH:mm:ss} %p [%c] #%P> %m%n')
    		);
      # Make the appender known to the system (without assigning it to
      # any logger
    Log::Log4perl->add_appender( $fileApp );
    
    my $syncApp = Log::Log4perl::Appender->new(
    		'Log::Log4perl::Appender::Synchronized',
    		name       => 'MySyncApp',
    		appender   => 'MyFileApp',
    		key        => 'nem',
    		);
    $syncApp->post_init();
    $syncApp->composite(1);

      # The Synchronized appender is now ready, assign it to a logger
      # and start logging.
    get_logger("")->add_appender($syncApp);

    get_logger("")->level($DEBUG);
    get_logger("wonk")->debug("waah!");

The composite appender's log() function will typically cache incoming 
messages until a certain trigger condition is met and then forward a bulk
of messages to the relay appender.

Caching messages is surprisingly tricky, because you want them to look
like they came from the code location they were originally issued from
and not from the location that triggers the flush. Luckily, Log4perl
offers a cache mechanism for messages, all you need to do is call the
base class' log() function with an additional reference to a scalar,
and then save its content to your composite appender's message buffer
afterwards:

    ###########################################
    sub log {
    ###########################################
        my($self, %params) = @_;

        # ... some logic to decide whether to cache or flush

            # Adjust the caller stack
        local $Log::Log4perl::caller_depth =
              $Log::Log4perl::caller_depth + 2;

            # We need to cache.
            # Ask the appender to save a cached message in $cache
        $self->{relay_app}->SUPER::log(\%params,
                             $params{log4p_category},
                             $params{log4p_level}, \my $cache);

            # Save it in the appender's message buffer
        push @{ $self->{buffer} }, $cache;
    }

Note that before calling the log() method of the relay appender's base class
(and thus introducing two additional levels on the call stack), we need to
adjust the call stack to allow Log4perl to render cspecs like the %M or %L
correctly.  The cache will then contain a correctly rendered message, according
to the layout of the target appender.

Later, when the time comes to flush the cached messages, a call to the relay
appender's base class' log_cached() method with the cached message as 
an argument will forward the correctly rendered message:

    ###########################################
    sub log {
    ###########################################
        my($self, %params) = @_;

        # ... some logic to decide whether to cache or flush

            # Flush pending messages if we have any
        for my $cache (@{$self->{buffer}}) {
            $self->{relay_app}->SUPER::log_cached($cache);
        }
    }


=head1 SEE ALSO

Log::Dispatch

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

