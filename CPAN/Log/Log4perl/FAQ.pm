1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::FAQ - Frequently Asked Questions on Log::Log4perl

=head1 DESCRIPTION

This FAQ shows a wide variety of
commonly encountered logging tasks and how to solve them
in the most elegant way with Log::Log4perl. Most of the time, this will
be just a matter of smartly configuring your Log::Log4perl configuration files.

=head2 Why use Log::Log4perl instead of any other logging module on CPAN?

That's a good question. There's dozens of logging modules on CPAN.
When it comes to logging, people typically think: "Aha. Writing out
debug and error messages. Debug is lower than error. Easy. I'm gonna
write my own." Writing a logging module is like a rite of passage for
every Perl programmer, just like writing your own templating system.

Of course, after getting the basics right, features need to
be added. You'd like to write a timestamp with every message. Then
timestamps with microseconds. Then messages need to be written to both
the screen and a log file.

And, as your application grows in size you might wonder: Why doesn't
my logging system scale along with it? You would like to switch on
logging in selected parts of the application, and not all across the
board, because this kills performance. This is when people turn to
Log::Log4perl, because it handles all of that.

Avoid this costly switch.

Use C<Log::Log4perl> right from the start. C<Log::Log4perl>'s C<:easy>
mode supports easy logging in simple scripts:

    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($DEBUG);

    DEBUG "A low-level message";
    ERROR "Won't make it until level gets increased to ERROR";

And when your application inevitably grows, your logging system grows
with it without you having to change any code.

Please, don't re-invent logging. C<Log::Log4perl> is here, it's easy
to use, it scales, and covers many areas you haven't thought of yet,
but will enter soon.

=head2 What's the easiest way to use Log4perl?

If you just want to get all the comfort of logging, without much
overhead, use I<Stealth Loggers>. If you use Log::Log4perl in
C<:easy> mode like

    use Log::Log4perl qw(:easy);

you'll have the following functions available in the current package:

    DEBUG("message");
    INFO("message");
    WARN("message");
    ERROR("message");
    FATAL("message");

Just make sure that every package of your code where you're using them in
pulls in C<use Log::Log4perl qw(:easy)> first, then you're set.
Every stealth logger's category will be equivalent to the name of the
package it's located in.

These stealth loggers
will be absolutely silent until you initialize Log::Log4perl in
your main program with either

        # Define any Log4perl behavior
    Log::Log4perl->init("foo.conf");

(using a full-blown Log4perl config file) or the super-easy method

        # Just log to STDERR
    Log::Log4perl->easy_init($DEBUG);

or the parameter-style method with a complexity somewhat in between:

        # Append to a log file
    Log::Log4perl->easy_init( { level   => $DEBUG,
                                file    => ">>test.log" } );

For more info, please check out L<Log::Log4perl/"Stealth Loggers">.

=head2 How can I simply log all my ERROR messages to a file?

After pulling in the C<Log::Log4perl> module, just initialize its
behavior by passing in a configuration to its C<init> method as a string
reference. Then, obtain a logger instance and write out a message
with its C<error()> method:

    use Log::Log4perl qw(get_logger);

        # Define configuration
    my $conf = q(
        log4perl.logger                    = ERROR, FileApp
        log4perl.appender.FileApp          = Log::Log4perl::Appender::File
        log4perl.appender.FileApp.filename = test.log
        log4perl.appender.FileApp.layout   = PatternLayout
        log4perl.appender.FileApp.layout.ConversionPattern = %d> %m%n
    );

        # Initialize logging behavior
    Log::Log4perl->init( \$conf );

        # Obtain a logger instance
    my $logger = get_logger("Bar::Twix");
    $logger->error("Oh my, a dreadful error!");
    $logger->warn("Oh my, a dreadful warning!");

This will append something like

    2002/10/29 20:11:55> Oh my, a dreadful error!

to the log file C<test.log>. How does this all work?

While the Log::Log4perl C<init()> method typically
takes the name of a configuration file as its input parameter like
in

    Log::Log4perl->init( "/path/mylog.conf" );

the example above shows how to pass in a configuration as text in a
scalar reference.

The configuration as shown
defines a logger of the root category, which has an appender of type
C<Log::Log4perl::Appender::File> attached. The line

    log4perl.logger = ERROR, FileApp

doesn't list a category, defining a root logger. Compare that with

    log4perl.logger.Bar.Twix = ERROR, FileApp

which would define a logger for the category C<Bar::Twix>,
showing probably different behavior. C<FileApp> on
the right side of the assignment is
an arbitrarily defined variable name, which is only used to somehow
reference an appender defined later on.

Appender settings in the configuration are defined as follows:

    log4perl.appender.FileApp          = Log::Log4perl::Appender::File
    log4perl.appender.FileApp.filename = test.log

It selects the file appender of the C<Log::Log4perl::Appender>
hierarchy, which will append to the file C<test.log> if it already
exists. If we wanted to overwrite a potentially existing file, we would
have to explicitly set the appropriate C<Log::Log4perl::Appender::File>
parameter C<mode>:

    log4perl.appender.FileApp          = Log::Log4perl::Appender::File
    log4perl.appender.FileApp.filename = test.log
    log4perl.appender.FileApp.mode     = write

Also, the configuration defines a PatternLayout format, adding
the nicely formatted current date and time, an arrow (E<gt>) and
a space before the messages, which is then followed by a newline:

    log4perl.appender.FileApp.layout   = PatternLayout
    log4perl.appender.FileApp.layout.ConversionPattern = %d> %m%n

Obtaining a logger instance and actually logging something is typically
done in a different system part as the Log::Log4perl initialisation section,
but in this example, it's just done right after init for the
sake of compactness:

        # Obtain a logger instance
    my $logger = get_logger("Bar::Twix");
    $logger->error("Oh my, a dreadful error!");

This retrieves an instance of the logger of the category C<Bar::Twix>,
which, as all other categories, inherits behavior from the root logger if no
other loggers are defined in the initialization section.

The C<error()>
method fires up a message, which the root logger catches. Its
priority is equal to
or higher than the root logger's priority (ERROR), which causes the root logger
to forward it to its attached appender. By contrast, the following

    $logger->warn("Oh my, a dreadful warning!");

doesn't make it through, because the root logger sports a higher setting
(ERROR and up) than the WARN priority of the message.

=head2 How can I install Log::Log4perl on Microsoft Windows?

You can install Log::Log4perl using the CPAN client.

Alternatively you can install it using

    ppm install Log-Log4perl

if you're using ActiveState perl.


That's it! Afterwards, just create a Perl script like

    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($DEBUG);

    my $logger = get_logger("Twix::Bar");
    $logger->debug("Watch me!");

and run it. It should print something like

    2002/11/06 01:22:05 Watch me!

If you find that something doesn't work, please let us know at
log4perl-devel@lists.sourceforge.net -- we'll appreciate it. Have fun!

=head2 How can I include global (thread-specific) data in my log messages?

Say, you're writing a web application and want all your
log messages to include the current client's IP address. Most certainly,
you don't want to include it in each and every log message like in

    $logger->debug( $r->connection->remote_ip,
                    " Retrieving user data from DB" );

do you? Instead, you want to set it in a global data structure and
have Log::Log4perl include it automatically via a PatternLayout setting
in the configuration file:

    log4perl.appender.FileApp.layout.ConversionPattern = %X{ip} %m%n

The conversion specifier C<%X{ip}> references an entry under the key
C<ip> in the global C<MDC> (mapped diagnostic context) table, which
you've set once via

    Log::Log4perl::MDC->put("ip", $r->connection->remote_ip);

at the start of the request handler. Note that this is a
I<static> (class) method, there's no logger object involved.
You can use this method with as many key/value pairs as you like as long
as you reference them under different names.

The mappings are stored in a global hash table within Log::Log4perl.
Luckily, because the thread
model in 5.8.0 doesn't share global variables between threads unless
they're explicitly marked as such, there's no problem with multi-threaded
environments.

For more details on the MDC, please refer to
L<Log::Log4perl/"Mapped Diagnostic Context (MDC)"> and
L<Log::Log4perl::MDC>.

=head2 My application is already logging to a file. How can I duplicate all messages to also go to the screen?

Assuming that you already have a Log4perl configuration file like

    log4perl.logger                    = DEBUG, FileApp

    log4perl.appender.FileApp          = Log::Log4perl::Appender::File
    log4perl.appender.FileApp.filename = test.log
    log4perl.appender.FileApp.layout   = PatternLayout
    log4perl.appender.FileApp.layout.ConversionPattern = %d> %m%n

and log statements all over your code,
it's very easy with Log4perl to have the same messages both printed to
the logfile and the screen. No reason to change your code, of course,
just add another appender to the configuration file and you're done:

    log4perl.logger                    = DEBUG, FileApp, ScreenApp

    log4perl.appender.FileApp          = Log::Log4perl::Appender::File
    log4perl.appender.FileApp.filename = test.log
    log4perl.appender.FileApp.layout   = PatternLayout
    log4perl.appender.FileApp.layout.ConversionPattern = %d> %m%n

    log4perl.appender.ScreenApp          = Log::Log4perl::Appender::Screen
    log4perl.appender.ScreenApp.stderr   = 0
    log4perl.appender.ScreenApp.layout   = PatternLayout
    log4perl.appender.ScreenApp.layout.ConversionPattern = %d> %m%n

The configuration file above is assuming that both appenders are
active in the same logger hierarchy, in this case the C<root> category.
But even if you've got file loggers defined in several parts of your system,
belonging to different logger categories,
each logging to different files, you can gobble up all logged messages
by defining a root logger with a screen appender, which would duplicate
messages from all your file loggers to the screen due to Log4perl's
appender inheritance. Check

    http://www.perl.com/pub/a/2002/09/11/log4perl.html

for details. Have fun!

=head2 How can I make sure my application logs a message when it dies unexpectedly?

Whenever you encounter a fatal error in your application, instead of saying
something like

    open FILE, "<blah" or die "Can't open blah -- bailing out!";

just use Log::Log4perl's fatal functions instead:

    my $log = get_logger("Some::Package");
    open FILE, "<blah" or $log->logdie("Can't open blah -- bailing out!");

This will both log the message with priority FATAL according to your current
Log::Log4perl configuration and then call Perl's C<die()>
afterwards to terminate the program. It works the same with
stealth loggers (see L<Log::Log4perl/"Stealth Loggers">),
all you need to do is call

    use Log::Log4perl qw(:easy);
    open FILE, "<blah" or LOGDIE "Can't open blah -- bailing out!";

What can you do if you're using some library which doesn't use Log::Log4perl
and calls C<die()> internally if something goes wrong? Use a
C<$SIG{__DIE__}> pseudo signal handler

    use Log::Log4perl qw(get_logger);

    $SIG{__DIE__} = sub {
        if($^S) {
            # We're in an eval {} and don't want log
            # this message but catch it later
            return;
        }
        local $Log::Log4perl::caller_depth =
              $Log::Log4perl::caller_depth + 1;
        my $logger = get_logger("");
        $logger->fatal(@_);
        die @_; # Now terminate really
    };

This will catch every C<die()>-Exception of your
application or the modules it uses. In case you want to
It
will fetch a root logger and pass on the C<die()>-Message to it.
If you make sure you've configured with a root logger like this:

    Log::Log4perl->init(\q{
        log4perl.category         = FATAL, Logfile
        log4perl.appender.Logfile = Log::Log4perl::Appender::File
        log4perl.appender.Logfile.filename = fatal_errors.log
        log4perl.appender.Logfile.layout = \
                   Log::Log4perl::Layout::PatternLayout
        log4perl.appender.Logfile.layout.ConversionPattern = %F{1}-%L (%M)> %m%n
    });

then all C<die()> messages will be routed to a file properly. The line

     local $Log::Log4perl::caller_depth =
           $Log::Log4perl::caller_depth + 1;

in the pseudo signal handler above merits a more detailed explanation. With
the setup above, if a module calls C<die()> in one of its functions,
the fatal message will be logged in the signal handler and not in the
original function -- which will cause the %F, %L and %M placeholders
in the pattern layout to be replaced by the filename, the line number
and the function/method name of the signal handler, not the error-throwing
module. To adjust this, Log::Log4perl has the C<$caller_depth> variable,
which defaults to 0, but can be set to positive integer values
to offset the caller level. Increasing
it by one will cause it to log the calling function's parameters, not
the ones of the signal handler.
See L<Log::Log4perl/"Using Log::Log4perl from wrapper classes"> for more
details.

=head2 How can I hook up the LWP library with Log::Log4perl?

Or, to put it more generally: How can you utilize a third-party
library's embedded logging and debug statements in Log::Log4perl?
How can you make them print
to configurable appenders, turn them on and off, just as if they
were regular Log::Log4perl logging statements?

The easiest solution is to map the third-party library logging statements
to Log::Log4perl's stealth loggers via a typeglob assignment.

As an example, let's take LWP, one of the most popular Perl modules,
which makes handling WWW requests and responses a breeze.
Internally, LWP uses its own logging and debugging system,
utilizing the following calls
inside the LWP code (from the LWP::Debug man page):

        # Function tracing
    LWP::Debug::trace('send()');

        # High-granular state in functions
    LWP::Debug::debug('url ok');

        # Data going over the wire
    LWP::Debug::conns("read $n bytes: $data");

First, let's assign Log::Log4perl priorities
to these functions: I'd suggest that
C<debug()> messages have priority C<INFO>,
C<trace()> uses C<DEBUG> and C<conns()> also logs with C<DEBUG> --
although your mileage may certainly vary.

Now, in order to transparently hook up LWP::Debug with Log::Log4perl,
all we have to do is say

    package LWP::Debug;
    use Log::Log4perl qw(:easy);

    *trace = *INFO;
    *conns = *DEBUG;
    *debug = *DEBUG;

    package main;
    # ... go on with your regular program ...

at the beginning of our program. In this way, every time the, say,
C<LWP::UserAgent> module calls C<LWP::Debug::trace()>, it will implicitly
call INFO(), which is the C<info()> method of a stealth logger defined for
the Log::Log4perl category C<LWP::Debug>. Is this cool or what?

Here's a complete program:

    use LWP::UserAgent;
    use HTTP::Request::Common;
    use Log::Log4perl qw(:easy);

    Log::Log4perl->easy_init(
        { category => "LWP::Debug",
          level    => $DEBUG,
          layout   => "%r %p %M-%L %m%n",
        });

    package LWP::Debug;
    use Log::Log4perl qw(:easy);
    *trace = *INFO;
    *conns = *DEBUG;
    *debug = *DEBUG;

    package main;
    my $ua = LWP::UserAgent->new();
    my $resp = $ua->request(GET "http://amazon.com");

    if($resp->is_success()) {
        print "Success: Received ",
              length($resp->content()), "\n";
    } else {
        print "Error: ", $resp->code(), "\n";
    }

This will generate the following output on STDERR:

    174 INFO LWP::UserAgent::new-164 ()
    208 INFO LWP::UserAgent::request-436 ()
    211 INFO LWP::UserAgent::send_request-294 GET http://amazon.com
    212 DEBUG LWP::UserAgent::_need_proxy-1123 Not proxied
    405 INFO LWP::Protocol::http::request-122 ()
    859 DEBUG LWP::Protocol::collect-206 read 233 bytes
    863 DEBUG LWP::UserAgent::request-443 Simple response: Found
    869 INFO LWP::UserAgent::request-436 ()
    871 INFO LWP::UserAgent::send_request-294
     GET http://www.amazon.com:80/exec/obidos/gateway_redirect
    872 DEBUG LWP::UserAgent::_need_proxy-1123 Not proxied
    873 INFO LWP::Protocol::http::request-122 ()
    1016 DEBUG LWP::UserAgent::request-443 Simple response: Found
    1020 INFO LWP::UserAgent::request-436 ()
    1022 INFO LWP::UserAgent::send_request-294
     GET http://www.amazon.com/exec/obidos/subst/home/home.html/
    1023 DEBUG LWP::UserAgent::_need_proxy-1123 Not proxied
    1024 INFO LWP::Protocol::http::request-122 ()
    1382 DEBUG LWP::Protocol::collect-206 read 632 bytes
    ...
    2605 DEBUG LWP::Protocol::collect-206 read 77 bytes
    2607 DEBUG LWP::UserAgent::request-443 Simple response: OK
    Success: Received 42584

Of course, in this way, the embedded logging and debug statements within
LWP can be utilized in any Log::Log4perl way you can think of. You can
have them sent to different appenders, block them based on the
category and everything else Log::Log4perl has to offer.

Only drawback of this method: Steering logging behavior via category
is always based on the C<LWP::Debug> package. Although the logging
statements reflect the package name of the issuing module properly,
the stealth loggers in C<LWP::Debug> are all of the category C<LWP::Debug>.
This implies that you can't control the logging behavior based on the
package that's I<initiating> a log request (e.g. LWP::UserAgent) but only
based on the package that's actually I<executing> the logging statement,
C<LWP::Debug> in this case.

To work around this conundrum, we need to write a wrapper function and
plant it into the C<LWP::Debug> package. It will determine the caller and
create a logger bound to a category with the same name as the caller's
package:

    package LWP::Debug;

    use Log::Log4perl qw(:levels get_logger);

    sub l4p_wrapper {
        my($prio, @message) = @_;
        $Log::Log4perl::caller_depth += 2;
        get_logger(scalar caller(1))->log($prio, @message);
        $Log::Log4perl::caller_depth -= 2;
    }

    no warnings 'redefine';
    *trace = sub { l4p_wrapper($INFO, @_); };
    *debug = *conns = sub { l4p_wrapper($DEBUG, @_); };

    package main;
    # ... go on with your main program ...

This is less performant than the previous approach, because every
log request will request a reference to a logger first, then call
the wrapper, which will in turn call the appropriate log function.

This hierarchy shift has to be compensated for by increasing
C<$Log::Log4perl::caller_depth> by 2 before calling the log function
and decreasing it by 2 right afterwards. Also, the C<l4p_wrapper>
function shown above calls C<caller(1)> which determines the name
of the package I<two> levels down the calling hierarchy (and
therefore compensates for both the wrapper function and the
anonymous subroutine calling it).

C<no warnings 'redefine'> suppresses a warning Perl would generate
otherwise
upon redefining C<LWP::Debug>'s C<trace()>, C<debug()> and C<conns()>
functions. In case you use a perl prior to 5.6.x, you need
to manipulate C<$^W> instead.

To make things easy for you when dealing with LWP, Log::Log4perl 0.47
introduces C<Log::Log4perl-E<gt>infiltrate_lwp()> which does exactly the
above.

=head2 What if I need dynamic values in a static Log4perl configuration file?

Say, your application uses Log::Log4perl for logging and
therefore comes with a Log4perl configuration file, specifying the logging
behavior.
But, you also want it to take command line parameters to set values
like the name of the log file.
How can you have
both a static Log4perl configuration file and a dynamic command line
interface?

As of Log::Log4perl 0.28, every value in the configuration file
can be specified as a I<Perl hook>. So, instead of saying

    log4perl.appender.Logfile.filename = test.log

you could just as well have a Perl subroutine deliver the value
dynamically:

    log4perl.appender.Logfile.filename = sub { logfile(); };

given that C<logfile()> is a valid function in your C<main> package
returning a string containing the path to the log file.

Or, think about using the value of an environment variable:

    log4perl.appender.DBI.user = sub { $ENV{USERNAME} };

When C<Log::Log4perl-E<gt>init()> parses the configuration
file, it will notice the assignment above because of its
C<sub {...}> pattern and treat it in a special way:
It will evaluate the subroutine (which can contain
arbitrary Perl code) and take its return value as the right side
of the assignment.

A typical application would be called like this on the command line:

    app                # log file is "test.log"
    app -l mylog.txt   # log file is "mylog.txt"

Here's some sample code implementing the command line interface above:

    use Log::Log4perl qw(get_logger);
    use Getopt::Std;

    getopt('l:', \our %OPTS);

    my $conf = q(
    log4perl.category.Bar.Twix         = WARN, Logfile
    log4perl.appender.Logfile          = Log::Log4perl::Appender::File
    log4perl.appender.Logfile.filename = sub { logfile(); };
    log4perl.appender.Logfile.layout   = SimpleLayout
    );

    Log::Log4perl::init(\$conf);

    my $logger = get_logger("Bar::Twix");
    $logger->error("Blah");

    ###########################################
    sub logfile {
    ###########################################
        if(exists $OPTS{l}) {
            return $OPTS{l};
        } else {
            return "test.log";
        }
    }

Every Perl hook may contain arbitrary perl code,
just make sure to fully qualify eventual variable names
(e.g. C<%main::OPTS> instead of C<%OPTS>).

B<SECURITY NOTE>: this feature means arbitrary perl code
can be embedded in the config file.  In the rare case
where the people who have access to your config file
are different from the people who write your code and
shouldn't have execute rights, you might want to call

    $Log::Log4perl::Config->allow_code(0);

before you call init(). This will prevent Log::Log4perl from
executing I<any> Perl code in the config file (including
code for custom conversion specifiers
(see L<Log::Log4perl::Layout::PatternLayout/"Custom cspecs">).

=head2 How can I roll over my logfiles automatically at midnight?

Long-running applications tend to produce ever-increasing logfiles.
For backup and cleanup purposes, however, it is often desirable to move
the current logfile to a different location from time to time and
start writing a new one.

This is a non-trivial task, because it has to happen in sync with
the logging system in order not to lose any messages in the process.

Luckily, I<Mark Pfeiffer>'s C<Log::Dispatch::FileRotate> appender
works well with Log::Log4perl to rotate your logfiles in a variety of ways.

Note, however, that having the application deal with rotating a log
file is not cheap. Among other things, it requires locking the log file
with every write to avoid race conditions.
There are good reasons to use external rotators like C<newsyslog>
instead.
See the entry C<How can I rotate a logfile with newsyslog?> in the
FAQ for more information on how to configure it.

When using C<Log::Dispatch::FileRotate>,
all you have to do is specify it in your Log::Log4perl configuration file
and your logfiles will be rotated automatically.

You can choose between rolling based on a maximum size ("roll if greater
than 10 MB") or based on a date pattern ("roll everyday at midnight").
In both cases, C<Log::Dispatch::FileRotate> allows you to define a
number C<max> of saved files to keep around until it starts overwriting
the oldest ones. If you set the C<max> parameter to 2 and the name of
your logfile is C<test.log>, C<Log::Dispatch::FileRotate> will
move C<test.log> to C<test.log.1> on the first rollover. On the second
rollover, it will move C<test.log.1> to C<test.log.2> and then C<test.log>
to C<test.log.1>. On the third rollover, it will move C<test.log.1> to
C<test.log.2> (therefore discarding the old C<test.log.2>) and
C<test.log> to C<test.log.1>. And so forth. This way, there's always
going to be a maximum of 2 saved log files around.

Here's an example of a Log::Log4perl configuration file, defining a
daily rollover at midnight (date pattern C<yyyy-MM-dd>), keeping
a maximum of 5 saved logfiles around:

    log4perl.category         = WARN, Logfile
    log4perl.appender.Logfile = Log::Dispatch::FileRotate
    log4perl.appender.Logfile.filename    = test.log
    log4perl.appender.Logfile.max         = 5
    log4perl.appender.Logfile.DatePattern = yyyy-MM-dd
    log4perl.appender.Logfile.TZ          = PST
    log4perl.appender.Logfile.layout = \
        Log::Log4perl::Layout::PatternLayout
    log4perl.appender.Logfile.layout.ConversionPattern = %d %m %n

Please see the C<Log::Dispatch::FileRotate> documentation for details.
C<Log::Dispatch::FileRotate> is available on CPAN.

=head2 What's the easiest way to turn off all logging, even with a lengthy Log4perl configuration file?

In addition to category-based levels and appender thresholds,
Log::Log4perl supports system-wide logging thresholds. This is the
minimum level the system will require of any logging events in order for them
to make it through to any configured appenders.

For example, putting the line

    log4perl.threshold = ERROR

anywhere in your configuration file will limit any output to any appender
to events with priority of ERROR or higher (ERROR or FATAL that is).

However, in order to suppress all logging entirely, you need to use a
priority that's higher than FATAL: It is simply called C<OFF>, and it is never
used by any logger. By definition, it is higher than the highest
defined logger level.

Therefore, if you keep the line

    log4perl.threshold = OFF

somewhere in your Log::Log4perl configuration, the system will be quiet
as a graveyard. If you deactivate the line (e.g. by commenting it out),
the system will, upon config reload, snap back to normal operation, providing
logging messages according to the rest of the configuration file again.

=head2 How can I log DEBUG and above to the screen and INFO and above to a file?

You need one logger with two appenders attached to it:

    log4perl.logger = DEBUG, Screen, File

    log4perl.appender.Screen   = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.layout = SimpleLayout

    log4perl.appender.File   = Log::Log4perl::Appender::File
    log4perl.appender.File.filename = test.log
    log4perl.appender.File.layout = SimpleLayout
    log4perl.appender.Screen.Threshold = INFO

Since the file logger isn't supposed to get any messages with a priority
less than INFO, the appender's C<Threshold> setting blocks those out,
although the logger forwards them.

It's a common mistake to think you can define two loggers for this, but
it won't work unless those two loggers have different categories. If you
wanted to log all DEBUG and above messages from the Foo::Bar module to a file
and all INFO and above messages from the Quack::Schmack module to the
screen, then you could have defined two loggers with different levels
C<log4perl.logger.Foo.Bar> (level INFO)
and C<log4perl.logger.Quack.Schmack> (level DEBUG) and assigned the file
appender to the former and the screen appender to the latter. But what we
wanted to accomplish was to route all messages, regardless of which module
(or category) they came from, to both appenders. The only
way to accomplish this is to define the root logger with the lower
level (DEBUG), assign both appenders to it, and block unwanted messages at
the file appender (C<Threshold> set to INFO).

=head2 I keep getting duplicate log messages! What's wrong?

Having several settings for related categories in the Log4perl
configuration file sometimes leads to a phenomenon called
"message duplication". It can be very confusing at first,
but if thought through properly, it turns out that Log4perl behaves
as advertised. But, don't despair, of course there's a number of
ways to avoid message duplication in your logs.

Here's a sample Log4perl configuration file that produces the
phenomenon:

    log4perl.logger.Cat        = ERROR, Screen
    log4perl.logger.Cat.Subcat = WARN, Screen

    log4perl.appender.Screen   = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.layout = SimpleLayout

It defines two loggers, one for category C<Cat> and one for
C<Cat::Subcat>, which is obviously a subcategory of C<Cat>.
The parent logger has a priority setting of ERROR, the child
is set to the lower C<WARN> level.

Now imagine the following code in your program:

    my $logger = get_logger("Cat.Subcat");
    $logger->warn("Warning!");

What do you think will happen? An unexperienced Log4perl user
might think: "Well, the message is being sent with level WARN, so the
C<Cat::Subcat> logger will accept it and forward it to the
attached C<Screen> appender. Then, the message will percolate up
the logger hierarchy, find
the C<Cat> logger, which will suppress the message because of its
ERROR setting."
But, perhaps surprisingly, what you'll get with the
code snippet above is not one but two log messages written
to the screen:

    WARN - Warning!
    WARN - Warning!

What happened? The culprit is that once the logger C<Cat::Subcat>
decides to fire, it will forward the message I<unconditionally>
to all directly or indirectly attached appenders. The C<Cat> logger
will never be asked if it wants the message or not -- the message
will just be pushed through to the appender attached to C<Cat>.

One way to prevent the message from bubbling up the logger
hierarchy is to set the C<additivity> flag of the subordinate logger to
C<0>:

    log4perl.logger.Cat            = ERROR, Screen
    log4perl.logger.Cat.Subcat     = WARN, Screen
    log4perl.additivity.Cat.Subcat = 0

    log4perl.appender.Screen   = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.layout = SimpleLayout

The message will now be accepted by the C<Cat::Subcat> logger,
forwarded to its appender, but then C<Cat::Subcat> will suppress
any further action. While this setting avoids duplicate messages
as seen before, it is often not the desired behavior. Messages
percolating up the hierarchy are a useful Log4perl feature.

If you're defining I<different> appenders for the two loggers,
one other option is to define an appender threshold for the
higher-level appender. Typically it is set to be
equal to the logger's level setting:

    log4perl.logger.Cat           = ERROR, Screen1
    log4perl.logger.Cat.Subcat    = WARN, Screen2

    log4perl.appender.Screen1   = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen1.layout = SimpleLayout
    log4perl.appender.Screen1.Threshold = ERROR

    log4perl.appender.Screen2   = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen2.layout = SimpleLayout

Since the C<Screen1> appender now blocks every message with
a priority less than ERROR, even if the logger in charge
lets it through, the message percolating up the hierarchy is
being blocked at the last minute and I<not> appended to C<Screen1>.

So far, we've been operating well within the boundaries of the
Log4j standard, which Log4perl adheres to. However, if
you would really, really like to use a single appender
and keep the message percolation intact without having to deal
with message duplication, there's a non-standard solution for you:

    log4perl.logger.Cat        = ERROR, Screen
    log4perl.logger.Cat.Subcat = WARN, Screen

    log4perl.appender.Screen   = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.layout = SimpleLayout

    log4perl.oneMessagePerAppender = 1

The C<oneMessagePerAppender> flag will suppress duplicate messages
to the same appender. Again, that's non-standard. But way cool :).

=head2 How can I configure Log::Log4perl to send me email if something happens?

Some incidents require immediate action. You can't wait until someone
checks the log files, you need to get notified on your pager right away.

The easiest way to do that is by using the C<Log::Dispatch::Email::MailSend>
module as an appender. It comes with the C<Log::Dispatch> bundle and
allows you to specify recipient and subject of outgoing emails in the Log4perl
configuration file:

    log4perl.category = FATAL, Mailer
    log4perl.appender.Mailer         = Log::Dispatch::Email::MailSend
    log4perl.appender.Mailer.to      = drone@pageme.net
    log4perl.appender.Mailer.subject = Something's broken!
    log4perl.appender.Mailer.layout  = SimpleLayout

The message of every log incident this appender gets
will then be forwarded to the given
email address. Check the C<Log::Dispatch::Email::MailSend> documentation
for details. And please make sure there's not a flood of email messages
sent out by your application, filling up the recipient's inbox.

There's one caveat you need to know about: The C<Log::Dispatch::Email>
hierarchy of appenders turns on I<buffering> by default. This means that
the appender will not send out messages right away but wait until a
certain threshold has been reached. If you'd rather have your alerts
sent out immediately, use

    log4perl.appender.Mailer.buffered = 0

to turn buffering off.

=head2 How can I write my own appender?

First off, Log::Log4perl comes with a set of standard appenders. Then,
there's a lot of Log4perl-compatible appenders already
available on CPAN: Just run a search for C<Log::Dispatch> on
http://search.cpan.org and chances are that what you're looking for
has already been developed, debugged and been used successfully
in production -- no need for you to reinvent the wheel.

Also, Log::Log4perl ships with a nifty database appender named
Log::Log4perl::Appender::DBI -- check it out if talking to databases is your
desire.

But if you're up for a truly exotic task, you might have to write
an appender yourself. That's very easy -- it takes no longer
than a couple of minutes.

Say, we wanted to create an appender of the class
C<ColorScreenAppender>, which logs messages
to the screen in a configurable color. Just create a new class
in C<ColorScreenAppender.pm>:

    package ColorScreenAppender;

Now let's assume that your Log::Log4perl
configuration file C<test.conf> looks like this:

    log4perl.logger = INFO, ColorApp

    log4perl.appender.ColorApp=ColorScreenAppender
    log4perl.appender.ColorApp.color=blue

    log4perl.appender.ColorApp.layout = PatternLayout
    log4perl.appender.ColorApp.layout.ConversionPattern=%d %m %n

This will cause Log::Log4perl on C<init()> to look for a class
ColorScreenAppender and call its constructor new(). Let's add
new() to ColorScreenAppender.pm:

    sub new {
        my($class, %options) = @_;

        my $self = { %options };
        bless $self, $class;

        return $self;
    }

To initialize this appender, Log::Log4perl will call
and pass all attributes of the appender as defined in the configuration
file to the constructor as name/value pairs (in this case just one):

    ColorScreenAppender->new(color => "blue");

The new() method listed above stores the contents of the
%options hash in the object's
instance data hash (referred to by $self).
That's all for initializing a new appender with Log::Log4perl.

Second, ColorScreenAppender needs to expose a
C<log()> method, which will be called by Log::Log4perl
every time it thinks the appender should fire. Along with the
object reference (as usual in Perl's object world), log()
will receive a list of name/value pairs, of which only the one
under the key C<message> shall be of interest for now since it is the
message string to be logged. At this point, Log::Log4perl has already taken
care of joining the message to be a single string.

For our special appender ColorScreenAppender, we're using the
Term::ANSIColor module to colorize the output:

    use Term::ANSIColor;

    sub log {
        my($self, %params) = @_;

        print colored($params{message},
                      $self->{color});
    }

The color (as configured in the Log::Log4perl configuration file)
is available as $self-E<gt>{color} in the appender object. Don't
forget to return

    1;

at the end of ColorScreenAppender.pm and you're done. Install the new appender
somewhere where perl can find it and try it with a test script like

    use Log::Log4perl qw(:easy);
    Log::Log4perl->init("test.conf");
    ERROR("blah");

to see the new colored output. Is this cool or what?

And it gets even better: You can write dynamically generated appender
classes using the C<Class::Prototyped> module. Here's an example of
an appender prepending every outgoing message with a configurable
number of bullets:

    use Class::Prototyped;

    my $class = Class::Prototyped->newPackage(
      "MyAppenders::Bulletizer",
      bullets => 1,
      log     => sub {
        my($self, %params) = @_;
        print "*" x $self->bullets(),
              $params{message};
      },
    );

    use Log::Log4perl qw(:easy);

    Log::Log4perl->init(\ q{
      log4perl.logger = INFO, Bully

      log4perl.appender.Bully=MyAppenders::Bulletizer
      log4perl.appender.Bully.bullets=3

      log4perl.appender.Bully.layout = PatternLayout
      log4perl.appender.Bully.layout.ConversionPattern=%m %n
    });

        # ... prints: "***Boo!\n";
    INFO "Boo!";

=head2 How can I drill down on references before logging them?

If you've got a reference to a nested structure or object, then
you probably don't want to log it as C<HASH(0x81141d4)> but rather
dump it as something like

    $VAR1 = {
              'a' => 'b',
              'd' => 'e'
            };

via a module like Data::Dumper. While it's syntactically correct to say

    $logger->debug(Data::Dumper::Dumper($ref));

this call imposes a huge performance penalty on your application
if the message is suppressed by Log::Log4perl, because Data::Dumper
will perform its expensive operations in any case, because it doesn't
know that its output will be thrown away immediately.

As of Log::Log4perl 0.28, there's a better way: Use the
message output filter format as in

    $logger->debug( {filter => \&Data::Dumper::Dumper,
                     value  => $ref} );

and Log::Log4perl won't call the filter function unless the message really
gets written out to an appender. Just make sure to pass the whole slew as a
reference to a hash specifying a filter function (as a sub reference)
under the key C<filter> and the value to be passed to the filter function in
C<value>).
When it comes to logging, Log::Log4perl will call the filter function,
pass the C<value> as an argument and log the return value.
Saves you serious cycles.

=head2 How can I collect all FATAL messages in an extra log file?

Suppose you have employed Log4perl all over your system and you've already
activated logging in various subsystems. On top of that, without disrupting
any other settings, how can you collect all FATAL messages all over the system
and send them to a separate log file?

If you define a root logger like this:

    log4perl.logger                  = FATAL, File
    log4perl.appender.File           = Log::Log4perl::Appender::File
    log4perl.appender.File.filename  = /tmp/fatal.txt
    log4perl.appender.File.layout    = PatternLayout
    log4perl.appender.File.layout.ConversionPattern= %d %m %n
        # !!! Something's missing ...

you'll be surprised to not only receive all FATAL messages
issued anywhere in the system,
but also everything else -- gazillions of
ERROR, WARN, INFO and even DEBUG messages will end up in
your fatal.txt logfile!
Reason for this is Log4perl's (or better: Log4j's) appender additivity.
Once a
lower-level logger decides to fire, the message is going to be forwarded
to all appenders upstream -- without further priority checks with their
attached loggers.

There's a way to prevent this, however: If your appender defines a
minimum threshold, only messages of this priority or higher are going
to be logged. So, just add

    log4perl.appender.File.Threshold = FATAL

to the configuration above, and you'll get what you wanted in the
first place: An overall system FATAL message collector.

=head2 How can I bundle several log messages into one?

Would you like to tally the messages arriving at your appender and
dump out a summary once they're exceeding a certain threshold?
So that something like

    $logger->error("Blah");
    $logger->error("Blah");
    $logger->error("Blah");

won't be logged as

    Blah
    Blah
    Blah

but as

    [3] Blah

instead? If you'd like to hold off on logging a message until it has been
sent a couple of times, you can roll that out by creating a buffered
appender.

Let's define a new appender like

    package TallyAppender;

    sub new {
        my($class, %options) = @_;

        my $self = { maxcount => 5,
                     %options
                   };

        bless $self, $class;

        $self->{last_message}        = "";
        $self->{last_message_count}  = 0;

        return $self;
    }

with two additional instance variables C<last_message> and
C<last_message_count>, storing the content of the last message sent
and a counter of how many times this has happened. Also, it features
a configuration parameter C<maxcount> which defaults to 5 in the
snippet above but can be set in the Log4perl configuration file like this:

    log4perl.logger = INFO, A
    log4perl.appender.A=TallyAppender
    log4perl.appender.A.maxcount = 3

The main tallying logic lies in the appender's C<log> method,
which is called every time Log4perl thinks a message needs to get logged
by our appender:

    sub log {
        my($self, %params) = @_;

            # Message changed? Print buffer.
        if($self->{last_message} and
           $params{message} ne $self->{last_message}) {
            print "[$self->{last_message_count}]: " .
                  "$self->{last_message}";
            $self->{last_message_count} = 1;
            $self->{last_message} = $params{message};
            return;
        }

        $self->{last_message_count}++;
        $self->{last_message} = $params{message};

            # Threshold exceeded? Print, reset counter
        if($self->{last_message_count} >=
           $self->{maxcount}) {
            print "[$self->{last_message_count}]: " .
                  "$params{message}";
            $self->{last_message_count} = 0;
            $self->{last_message}       = "";
            return;
        }
    }

We basically just check if the oncoming message in C<$param{message}>
is equal to what we've saved before in the C<last_message> instance
variable. If so, we're increasing C<last_message_count>.
We print the message in two cases: If the new message is different
than the buffered one, because then we need to dump the old stuff
and store the new. Or, if the counter exceeds the threshold, as
defined by the C<maxcount> configuration parameter.

Please note that the appender always gets the fully rendered message and
just compares it as a whole -- so if there's a date/timestamp in there,
that might confuse your logic. You can work around this by specifying
%m %n as a layout and add the date later on in the appender. Or, make
the comparison smart enough to omit the date.

At last, don't forget what happens if the program is being shut down.
If there's still messages in the buffer, they should be printed out
at that point. That's easy to do in the appender's DESTROY method,
which gets called at object destruction time:

    sub DESTROY {
        my($self) = @_;

        if($self->{last_message_count}) {
            print "[$self->{last_message_count}]: " .
                  "$self->{last_message}";
            return;
        }
    }

This will ensure that none of the buffered messages are lost.
Happy buffering!

=head2 I want to log ERROR and WARN messages to different files! How can I do that?

Let's assume you wanted to have each logging statement written to a
different file, based on the statement's priority. Messages with priority
C<WARN> are supposed to go to C</tmp/app.warn>, events prioritized
as C<ERROR> should end up in C</tmp/app.error>.

Now, if you define two appenders C<AppWarn> and C<AppError>
and assign them both to the root logger,
messages bubbling up from any loggers below will be logged by both
appenders because of Log4perl's message propagation feature. If you limit
their exposure via the appender threshold mechanism and set
C<AppWarn>'s threshold to C<WARN> and C<AppError>'s to C<ERROR>, you'll
still get C<ERROR> messages in C<AppWarn>, because C<AppWarn>'s C<WARN>
setting will just filter out messages with a I<lower> priority than
C<WARN> -- C<ERROR> is higher and will be allowed to pass through.

What we need for this is a Log4perl I<Custom Filter>, available with
Log::Log4perl 0.30.

Both appenders need to verify that
the priority of the oncoming messages exactly I<matches> the priority
the appender is supposed to log messages of. To accomplish this task,
let's define two custom filters, C<MatchError> and C<MatchWarn>, which,
when attached to their appenders, will limit messages passed on to them
to those matching a given priority:

    log4perl.logger = WARN, AppWarn, AppError

        # Filter to match level ERROR
    log4perl.filter.MatchError = Log::Log4perl::Filter::LevelMatch
    log4perl.filter.MatchError.LevelToMatch  = ERROR
    log4perl.filter.MatchError.AcceptOnMatch = true

        # Filter to match level WARN
    log4perl.filter.MatchWarn  = Log::Log4perl::Filter::LevelMatch
    log4perl.filter.MatchWarn.LevelToMatch  = WARN
    log4perl.filter.MatchWarn.AcceptOnMatch = true

        # Error appender
    log4perl.appender.AppError = Log::Log4perl::Appender::File
    log4perl.appender.AppError.filename = /tmp/app.err
    log4perl.appender.AppError.layout   = SimpleLayout
    log4perl.appender.AppError.Filter   = MatchError

        # Warning appender
    log4perl.appender.AppWarn = Log::Log4perl::Appender::File
    log4perl.appender.AppWarn.filename = /tmp/app.warn
    log4perl.appender.AppWarn.layout   = SimpleLayout
    log4perl.appender.AppWarn.Filter   = MatchWarn

The appenders C<AppWarn> and C<AppError> defined above are logging to C</tmp/app.warn> and
C</tmp/app.err> respectively and have the custom filters C<MatchWarn> and C<MatchError>
attached.
This setup will direct all WARN messages, issued anywhere in the system, to /tmp/app.warn (and
ERROR messages to /tmp/app.error) -- without any overlaps.

=head2 On our server farm, Log::Log4perl configuration files differ slightly from host to host. Can I roll them all into one?

You sure can, because Log::Log4perl allows you to specify attribute values
dynamically. Let's say that one of your appenders expects the host's IP address
as one of its attributes. Now, you could certainly roll out different
configuration files for every host and specify the value like

    log4perl.appender.MyAppender    = Log::Log4perl::Appender::SomeAppender
    log4perl.appender.MyAppender.ip = 10.0.0.127

but that's a maintenance nightmare. Instead, you can have Log::Log4perl
figure out the IP address at configuration time and set the appender's
value correctly:

        # Set the IP address dynamically
    log4perl.appender.MyAppender    = Log::Log4perl::Appender::SomeAppender
    log4perl.appender.MyAppender.ip = sub { \
       use Sys::Hostname; \
       use Socket; \
       return inet_ntoa(scalar gethostbyname hostname); \
    }

If Log::Log4perl detects that an attribute value starts with something like
C<"sub {...">, it will interpret it as a perl subroutine which is to be executed
once at configuration time (not runtime!) and its return value is
to be used as the attribute value. This comes in handy
for rolling out applications where Log::Log4perl configuration files
show small host-specific differences, because you can deploy the unmodified
application distribution on all instances of the server farm.

=head2 Log4perl doesn't interpret my backslashes correctly!

If you're using Log4perl's feature to specify the configuration as a
string in your program (as opposed to a separate configuration file),
chances are that you've written it like this:

    # *** WRONG! ***

    Log::Log4perl->init( \ <<END_HERE);
        log4perl.logger = WARN, A1
        log4perl.appender.A1 = Log::Log4perl::Appender::Screen
        log4perl.appender.A1.layout = \
            Log::Log4perl::Layout::PatternLayout
        log4perl.appender.A1.layout.ConversionPattern = %m%n
    END_HERE

    # *** WRONG! ***

and you're getting the following error message:

    Layout not specified for appender A1 at .../Config.pm line 342.

What's wrong? The problem is that you're using a here-document with
substitution enabled (C<E<lt>E<lt>END_HERE>) and that Perl won't
interpret backslashes at line-ends as continuation characters but
will essentially throw them out. So, in the code above, the layout line
will look like

    log4perl.appender.A1.layout =

to Log::Log4perl which causes it to report an error. To interpret the backslash
at the end of the line correctly as a line-continuation character, use
the non-interpreting mode of the here-document like in

    # *** RIGHT! ***

    Log::Log4perl->init( \ <<'END_HERE');
        log4perl.logger = WARN, A1
        log4perl.appender.A1 = Log::Log4perl::Appender::Screen
        log4perl.appender.A1.layout = \
            Log::Log4perl::Layout::PatternLayout
        log4perl.appender.A1.layout.ConversionPattern = %m%n
    END_HERE

    # *** RIGHT! ***

(note the single quotes around C<'END_HERE'>) or use C<q{...}>
instead of a here-document and Perl will treat the backslashes at
line-end as intended.

=head2 I want to suppress certain messages based on their content!

Let's assume you've plastered all your functions with Log4perl
statements like

    sub some_func {

        INFO("Begin of function");

        # ... Stuff happens here ...

        INFO("End of function");
    }

to issue two log messages, one at the beginning and one at the end of
each function. Now you want to suppress the message at the beginning
and only keep the one at the end, what can you do? You can't use the category
mechanism, because both messages are issued from the same package.

Log::Log4perl's custom filters (0.30 or better) provide an interface for the
Log4perl user to step in right before a message gets logged and decide if
it should be written out or suppressed, based on the message content or other
parameters:

    use Log::Log4perl qw(:easy);

    Log::Log4perl::init( \ <<'EOT' );
        log4perl.logger             = INFO, A1
        log4perl.appender.A1        = Log::Log4perl::Appender::Screen
        log4perl.appender.A1.layout = \
            Log::Log4perl::Layout::PatternLayout
        log4perl.appender.A1.layout.ConversionPattern = %m%n

        log4perl.filter.M1 = Log::Log4perl::Filter::StringMatch
        log4perl.filter.M1.StringToMatch = Begin
        log4perl.filter.M1.AcceptOnMatch = false

        log4perl.appender.A1.Filter = M1
EOT

The last four statements in the configuration above are defining a custom
filter C<M1> of type C<Log::Log4perl::Filter::StringMatch>, which comes with
Log4perl right out of the box and allows you to define a text pattern to match
(as a perl regular expression) and a flag C<AcceptOnMatch> indicating
if a match is supposed to suppress the message or let it pass through.

The last line then assigns this filter to the C<A1> appender, which will
call it every time it receives a message to be logged and throw all
messages out I<not> matching the regular expression C<Begin>.

Instead of using the standard C<Log::Log4perl::Filter::StringMatch> filter,
you can define your own, simply using a perl subroutine:

    log4perl.filter.ExcludeBegin  = sub { !/Begin/ }
    log4perl.appender.A1.Filter   = ExcludeBegin

For details on custom filters, check L<Log::Log4perl::Filter>.

=head2 My new module uses Log4perl -- but what happens if the calling program didn't configure it?

If a Perl module uses Log::Log4perl, it will typically rely on the
calling program to initialize it. If it is using Log::Log4perl in C<:easy>
mode, like in

    package MyMod;
    use Log::Log4perl qw(:easy);

    sub foo {
        DEBUG("In foo");
    }

    1;

and the calling program doesn't initialize Log::Log4perl at all (e.g. because
it has no clue that it's available), Log::Log4perl will silently
ignore all logging messages. However, if the module is using Log::Log4perl
in regular mode like in

    package MyMod;
    use Log::Log4perl qw(get_logger);

    sub foo {
        my $logger = get_logger("");
        $logger->debug("blah");
    }

    1;

and the main program is just using the module like in

    use MyMode;
    MyMode::foo();

then Log::Log4perl will also ignore all logging messages but
issue a warning like

    Log4perl: Seems like no initialization happened.
    Forgot to call init()?

(only once!) to remind novice users to not forget to initialize
the logging system before using it.
However, if you want to suppress this message, just
add the C<:nowarn> target to the module's C<use Log::Log4perl> call:

    use Log::Log4perl qw(get_logger :nowarn);

This will have Log::Log4perl silently ignore all logging statements if
no initialization has taken place. If, instead of using init(), you're
using Log4perl's API to define loggers and appenders, the same
notification happens if no call to add_appenders() is made, i.e. no
appenders are defined.

If the module wants to figure out if some other program part has
already initialized Log::Log4perl, it can do so by calling

    Log::Log4perl::initialized()

which will return a true value in case Log::Log4perl has been initialized
and a false value if not.

=head2 How can I synchronize access to an appender?

If you're using the same instance of an appender in multiple processes,
and each process is passing on messages to the appender in parallel,
you might end up with overlapping log entries.

Typical scenarios include a file appender that you create in the main
program, and which will then be shared between the parent and a
forked child process. Or two separate processes, each initializing a
Log4perl file appender on the same logfile.

Log::Log4perl won't synchronize access to the shared logfile by
default. Depending on your operating system's flush mechanism,
buffer size and the size of your messages, there's a small chance of
an overlap.

The easiest way to prevent overlapping messages in logfiles written to
by multiple processes is setting the
file appender's C<syswrite> flag along with a file write mode of C<"append">.
This makes sure that
C<Log::Log4perl::Appender::File> uses C<syswrite()> (which is guaranteed
to run uninterrupted) instead of C<print()> which might buffer
the message or get interrupted by the OS while it is writing. And in
C<"append"> mode, the OS kernel ensures that multiple processes share
one end-of-file marker, ensuring that each process writes to the I<real>
end of the file. (The value of C<"append">
for the C<mode> parameter is the default setting in Log4perl's file
appender so you don't have to set it explicitly.)

      # Guarantees atomic writes

    log4perl.category.Bar.Twix          = WARN, Logfile

    log4perl.appender.Logfile           = Log::Log4perl::Appender::File
    log4perl.appender.Logfile.mode      = append
    log4perl.appender.Logfile.syswrite  = 1
    log4perl.appender.Logfile.filename  = test.log
    log4perl.appender.Logfile.layout    = SimpleLayout

Another guaranteed way of having messages separated with any kind of
appender is putting a Log::Log4perl::Appender::Synchronized composite
appender in between Log::Log4perl and the real appender. It will make
sure to let messages pass through this virtual gate one by one only.

Here's a sample configuration to synchronize access to a file appender:

    log4perl.category.Bar.Twix          = WARN, Syncer

    log4perl.appender.Logfile           = Log::Log4perl::Appender::File
    log4perl.appender.Logfile.autoflush = 1
    log4perl.appender.Logfile.filename  = test.log
    log4perl.appender.Logfile.layout    = SimpleLayout

    log4perl.appender.Syncer            = Log::Log4perl::Appender::Synchronized
    log4perl.appender.Syncer.appender   = Logfile

C<Log::Log4perl::Appender::Synchronized> uses
the C<IPC::Shareable> module and its semaphores, which will slow down writing
the log messages, but ensures sequential access featuring atomic checks.
Check L<Log::Log4perl::Appender::Synchronized> for details.

=head2 Can I use Log::Log4perl with log4j's Chainsaw?

Yes, Log::Log4perl can be configured to send its events to log4j's
graphical log UI I<Chainsaw>.

=for html
<p>
<TABLE><TR><TD>
<A HREF="http://log4perl.sourceforge.net/images/chainsaw2.jpg"><IMG SRC="http://log4perl.sourceforge.net/images/chainsaw2s.jpg"></A>
<TR><TD>
<I>Figure 1: Chainsaw receives Log::Log4perl events</I>
</TABLE>
<p>

=for text
Figure1: Chainsaw receives Log::Log4perl events

Here's how it works:

=over 4

=item *

Get Guido Carls' E<lt>gcarls@cpan.orgE<gt> Log::Log4perl extension
C<Log::Log4perl::Layout::XMLLayout> from CPAN and install it:

    perl -MCPAN -eshell
    cpan> install Log::Log4perl::Layout::XMLLayout

=item *

Install and start Chainsaw, which is part of the C<log4j> distribution now
(see http://jakarta.apache.org/log4j ). Create a configuration file like

  <log4j:configuration debug="true">
    <plugin name="XMLSocketReceiver"
            class="org.apache.log4j.net.XMLSocketReceiver">
      <param name="decoder" value="org.apache.log4j.xml.XMLDecoder"/>
      <param name="Port" value="4445"/>
    </plugin>
    <root> <level value="debug"/> </root>
  </log4j:configuration>

and name it e.g. C<config.xml>. Then start Chainsaw like

  java -Dlog4j.debug=true -Dlog4j.configuration=config.xml \
    -classpath ".:log4j-1.3alpha.jar:log4j-chainsaw-1.3alpha.jar" \
    org.apache.log4j.chainsaw.LogUI

and watch the GUI coming up.

=item *

Configure Log::Log4perl to use a socket appender with an XMLLayout, pointing
to the host/port where Chainsaw (as configured above) is waiting with its
XMLSocketReceiver:

  use Log::Log4perl qw(get_logger);
  use Log::Log4perl::Layout::XMLLayout;

  my $conf = q(
    log4perl.category.Bar.Twix          = WARN, Appender
    log4perl.appender.Appender          = Log::Log4perl::Appender::Socket
    log4perl.appender.Appender.PeerAddr = localhost
    log4perl.appender.Appender.PeerPort = 4445
    log4perl.appender.Appender.layout   = Log::Log4perl::Layout::XMLLayout
  );

  Log::Log4perl::init(\$conf);

    # Nasty hack to suppress encoding header
  my $app = Log::Log4perl::appenders->{"Appender"};
  $app->layout()->{enc_set} = 1;

  my $logger = get_logger("Bar.Twix");
  $logger->error("One");

The nasty hack shown in the code snippet above is currently (October 2003)
necessary, because Chainsaw expects XML messages to arrive in a format like

  <log4j:event logger="Bar.Twix"
               timestamp="1066794904310"
               level="ERROR"
               thread="10567">
    <log4j:message><![CDATA[Two]]></log4j:message>
    <log4j:NDC><![CDATA[undef]]></log4j:NDC>
    <log4j:locationInfo class="main"
      method="main"
      file="./t"
      line="32">
    </log4j:locationInfo>
  </log4j:event>

without a preceding

  <?xml version = "1.0" encoding = "iso8859-1"?>

which Log::Log4perl::Layout::XMLLayout applies to the first event sent
over the socket.

=back

See figure 1 for a screenshot of Chainsaw in action, receiving events from
the Perl script shown above.

Many thanks to Chainsaw's
Scott Deboy <sdeboy@comotivsystems.com> for his support!

=head2 How can I run Log::Log4perl under mod_perl?

In persistent environments it's important to play by the rules outlined
in section L<Log::Log4perl/"Initialize once and only once">.
If you haven't read this yet, please go ahead and read it right now. It's
very important.

And no matter if you use a startup handler to init() Log::Log4perl or use the
init_once() strategy (added in 0.42), either way you're very likely to have
unsynchronized writes to logfiles.

If Log::Log4perl is configured with a log file appender, and it is
initialized via
the Apache startup handler, the file handle created initially will be
shared among all Apache processes. Similarly, with the init_once()
approach: although every process has a separate L4p configuration,
processes are gonna share the appender file I<names> instead, effectively
opening several different file handles on the same file.

Now, having several appenders using the same file handle or having
several appenders logging to the same file unsynchronized, this might
result in overlapping messages. Sometimes, this is acceptable. If it's
not, here's two strategies:

=over 4

=item *

Use the L<Log::Log4perl::Appender::Synchronized> appender to connect to
your file appenders. Here's the writeup:
http://log4perl.sourceforge.net/releases/Log-Log4perl/docs/html/Log/Log4perl/FAQ.html#23804

=item *

Use a different logfile for every process like in

     #log4perl.conf
     ...
     log4perl.appender.A1.filename = sub { "mylog.$$.log" }

=back

=head2 My program already uses warn() and die(). How can I switch to Log4perl?

If your program already uses Perl's C<warn()> function to spew out
error messages and you'd like to channel those into the Log4perl world,
just define a C<__WARN__> handler where your program or module resides:

    use Log::Log4perl qw(:easy);

    $SIG{__WARN__} = sub {
        local $Log::Log4perl::caller_depth =
            $Log::Log4perl::caller_depth + 1;
        WARN @_;
    };

Why the C<local> setting of C<$Log::Log4perl::caller_depth>?
If you leave that out,
C<PatternLayout> conversion specifiers like C<%M> or C<%F> (printing
the current function/method and source filename) will refer
to where the __WARN__ handler resides, not the environment
Perl's C<warn()> function was issued from. Increasing C<caller_depth>
adjusts for this offset. Having it C<local>, makes sure the level
gets set back after the handler exits.

Once done, if your program does something like

    sub some_func {
        warn "Here's a warning";
    }

you'll get (depending on your Log::Log4perl configuration) something like

    2004/02/19 20:41:02-main::some_func: Here's a warning at ./t line 25.

in the appropriate appender instead of having a screen full of STDERR
messages. It also works with the C<Carp> module and its C<carp()>
and C<cluck()> functions.

If, on the other hand, catching C<die()> and friends is
required, a C<__DIE__> handler is appropriate:

    $SIG{__DIE__} = sub {
        if($^S) {
            # We're in an eval {} and don't want log
            # this message but catch it later
            return;
        }
        local $Log::Log4perl::caller_depth =
            $Log::Log4perl::caller_depth + 1;
        LOGDIE @_;
    };

This will call Log4perl's C<LOGDIE()> function, which will log a fatal
error and then call die() internally, causing the program to exit. Works
equally well with C<Carp>'s C<croak()> and C<confess()> functions.

=head2 Some module prints messages to STDERR. How can I funnel them to Log::Log4perl?

If a module you're using doesn't use Log::Log4perl but prints logging
messages to STDERR instead, like

    ########################################
    package IgnorantModule;
    ########################################

    sub some_method {
        print STDERR "Parbleu! An error!\n";
    }

    1;

there's still a way to capture these messages and funnel them
into Log::Log4perl, even without touching the module. What you need is
a trapper module like

    ########################################
    package Trapper;
    ########################################

    use Log::Log4perl qw(:easy);

    sub TIEHANDLE {
        my $class = shift;
        bless [], $class;
    }

    sub PRINT {
        my $self = shift;
        $Log::Log4perl::caller_depth++;
        DEBUG @_;
        $Log::Log4perl::caller_depth--;
    }

    1;

and a C<tie> command in the main program to tie STDERR to the trapper
module along with regular Log::Log4perl initialization:

    ########################################
    package main;
    ########################################

    use Log::Log4perl qw(:easy);

    Log::Log4perl->easy_init(
        {level  => $DEBUG,
         file   => 'stdout',   # make sure not to use stderr here!
         layout => "%d %M: %m%n",
        });

    tie *STDERR, "Trapper";

Make sure not to use STDERR as Log::Log4perl's file appender
here (which would be the default in C<:easy> mode), because it would
end up in an endless recursion.

Now, calling

    IgnorantModule::some_method();

will result in the desired output

    2004/05/06 11:13:04 IgnorantModule::some_method: Parbleu! An error!

=head2 How come PAR (Perl Archive Toolkit) creates executables which then can't find their Log::Log4perl appenders?

If not instructed otherwise, C<Log::Log4perl> dynamically pulls in
appender classes found in its configuration. If you specify

    #!/usr/bin/perl
    # mytest.pl

    use Log::Log4perl qw(get_logger);

    my $conf = q(
      log4perl.category.Bar.Twix = WARN, Logfile
      log4perl.appender.Logfile  = Log::Log4perl::Appender::Screen
      log4perl.appender.Logfile.layout = SimpleLayout
    );

    Log::Log4perl::init(\$conf);
    my $logger = get_logger("Bar::Twix");
    $logger->error("Blah");

then C<Log::Log4perl::Appender::Screen> will be pulled in while the program
runs, not at compile time. If you have PAR compile the script above to an
executable binary via

    pp -o mytest mytest.pl

and then run C<mytest> on a machine without having Log::Log4perl installed,
you'll get an error message like

    ERROR: can't load appenderclass 'Log::Log4perl::Appender::Screen'
    Can't locate Log/Log4perl/Appender/Screen.pm in @INC ...

Why? At compile time, C<pp> didn't realize that
C<Log::Log4perl::Appender::Screen> would be needed later on and didn't
wrap it into the executable created. To avoid this, either say
C<use Log::Log4perl::Appender::Screen> in the script explicitly or
compile it with

    pp -o mytest -M Log::Log4perl::Appender::Screen mytest.pl

to make sure the appender class gets included.

=head2 How can I access a custom appender defined in the configuration?

Any appender defined in the configuration file or somewhere in the code
can be accessed later via
C<Log::Log4perl-E<gt>appender_by_name("appender_name")>,
which returns a reference of the appender object.

Once you've got a hold of the object, it can be queried or modified to
your liking. For example, see the custom C<IndentAppender> defined below:
After calling C<init()> to define the Log4perl settings, the
appender object is retrieved to call its C<indent_more()> and C<indent_less()>
methods to control indentation of messages:

    package IndentAppender;

    sub new {
        bless { indent => 0 }, $_[0];
    }

    sub indent_more  { $_[0]->{indent}++ }
    sub indent_less  { $_[0]->{indent}-- }

    sub log {
        my($self, %params) = @_;
        print " " x $self->{indent}, $params{message};
    }

    package main;

    use Log::Log4perl qw(:easy);

    my $conf = q(
    log4perl.category          = DEBUG, Indented
    log4perl.appender.Indented = IndentAppender
    log4perl.appender.Indented.layout = Log::Log4perl::Layout::SimpleLayout
    );

    Log::Log4perl::init(\$conf);

    my $appender = Log::Log4perl->appender_by_name("Indented");

    DEBUG "No identation";
    $appender->indent_more();
    DEBUG "One more";
    $appender->indent_more();
    DEBUG "Two more";
    $appender->indent_less();
    DEBUG "One less";

As you would expect, this will print

    DEBUG - No identation
     DEBUG - One more
      DEBUG - Two more
     DEBUG - One less

because the very appender used by Log4perl is modified dynamically at
runtime.

=head2 I don't know if Log::Log4perl is installed. How can I prepare my script?

In case your script needs to be prepared for environments that may or may
not have Log::Log4perl installed, there's a trick.

If you put the following BEGIN blocks at the top of the program,
you'll be able to use the DEBUG(), INFO(), etc. macros in
Log::Log4perl's C<:easy> mode.
If Log::Log4perl
is installed in the target environment, the regular Log::Log4perl rules
apply. If not, all of DEBUG(), INFO(), etc. are "stubbed" out, i.e. they
turn into no-ops:

    use warnings;
    use strict;

    BEGIN {
        eval { require Log::Log4perl; };

        if($@) {
            print "Log::Log4perl not installed - stubbing.\n";
            no strict qw(refs);
            *{"main::$_"} = sub { } for qw(DEBUG INFO WARN ERROR FATAL);
        } else {
            no warnings;
            print "Log::Log4perl installed - life is good.\n";
            require Log::Log4perl::Level;
            Log::Log4perl::Level->import(__PACKAGE__);
            Log::Log4perl->import(qw(:easy));
            Log::Log4perl->easy_init($main::DEBUG);
        }
    }

        # The regular script begins ...
    DEBUG "Hey now!";

This snippet will first probe for Log::Log4perl, and if it can't be found,
it will alias DEBUG(), INFO(), with empty subroutines via typeglobs.
If Log::Log4perl is available, its level constants are first imported
(C<$DEBUG>, C<$INFO>, etc.) and then C<easy_init()> gets called to initialize
the logging system.

=head2 Can file appenders create files with different permissions?

Typically, when C<Log::Log4perl::Appender::File> creates a new file,
its permissions are set to C<rw-r--r-->. Why? Because your
environment's I<umask> most likely defaults to
C<0022>, that's the standard setting.

What's a I<umask>, you're asking? It's a template that's applied to
the permissions of all newly created files. While calls like
C<open(FILE, "E<gt>foo")> will always try to create files in C<rw-rw-rw-
> mode, the system will apply the current I<umask> template to
determine the final permission setting. I<umask> is a bit mask that's
inverted and then applied to the requested permission setting, using a
bitwise AND:

    $request_permission &~ $umask

So, a I<umask> setting of 0000 (the leading 0 simply indicates an
octal value) will create files in C<rw-rw-rw-> mode, a setting of 0277
will use C<r-------->, and the standard 0022 will use C<rw-r--r-->.

As an example, if you want your log files to be created with
C<rw-r--rw-> permissions, use a I<umask> of C<0020> before
calling Log::Log4perl->init():

    use Log::Log4perl;

    umask 0020;
        # Creates log.out in rw-r--rw mode
    Log::Log4perl->init(\ q{
        log4perl.logger = WARN, File
        log4perl.appender.File = Log::Log4perl::Appender::File
        log4perl.appender.File.filename = log.out
        log4perl.appender.File.layout = SimpleLayout
    });

=head2 Using Log4perl in an END block causes a problem!

It's not easy to get to this error, but if you write something like

    END { Log::Log4perl::get_logger()->debug("Hey there."); }

    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($DEBUG);

it won't work. The reason is that C<Log::Log4perl> defines an
END block that cleans up all loggers. And perl will run END blocks
in the reverse order as they're encountered in the compile phase,
so in the scenario above, the END block will run I<after> Log4perl
has cleaned up its loggers.

Placing END blocks using Log4perl I<after>
a C<use Log::Log4perl> statement fixes the problem:

    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($DEBUG);

    END { Log::Log4perl::get_logger()->debug("Hey there."); }

In this scenario, the shown END block is executed I<before> Log4perl
cleans up and the debug message will be processed properly.

=head2 Help! My appender is throwing a "Wide character in print" warning!

This warning shows up when Unicode strings are printed without
precautions. The warning goes away if the complaining appender is
set to utf-8 mode:

      # Either in the log4perl configuration file:
  log4perl.appender.Logfile.filename = test.log
  log4perl.appender.Logfile.utf8     = 1

      # Or, in easy mode:
  Log::Log4perl->easy_init( {
    level => $DEBUG,
    file  => ":utf8> test.log"
  } );

If the complaining appender is a screen appender, set its C<utf8> option:

      log4perl.appender.Screen.stderr = 1
      log4perl.appender.Screen.utf8   = 1

Alternatively, C<binmode> does the trick:

      # Either STDOUT ...
    binmode(STDOUT, ":utf8);

      # ... or STDERR.
    binmode(STDERR, ":utf8);

Some background on this: Perl's strings are either byte strings or
Unicode strings. C<"Mike"> is a byte string.
C<"\x{30DE}\x{30A4}\x{30AF}"> is a Unicode string. Unicode strings are
marked specially and are UTF-8 encoded internally.

If you print a byte string to STDOUT,
all is well, because STDOUT is by default set to byte mode. However,
if you print a Unicode string to STDOUT without precautions, C<perl>
will try to transform the Unicode string back to a byte string before
printing it out. This is troublesome if the Unicode string contains
'wide' characters which can't be represented in Latin-1.

For example, if you create a Unicode string with three japanese Katakana
characters as in

    perl -le 'print "\x{30DE}\x{30A4}\x{30AF}"'

(coincidentally pronounced Ma-i-ku, the japanese pronunciation of
"Mike"), STDOUT is in byte mode and the warning

    Wide character in print at ./script.pl line 14.

appears. Setting STDOUT to UTF-8 mode as in

    perl -le 'binmode(STDOUT, ":utf8"); print "\x{30DE}\x{30A4}\x{30AF}"'

will silently print the Unicode string to STDOUT in UTF-8. To see the
characters printed, you'll need a UTF-8 terminal with a font including
japanese Katakana characters.

=head2 How can I send errors to the screen, and debug messages to a file?

Let's assume you want to maintain a detailed DEBUG output in a file
and only messages of level ERROR and higher should be printed on the
screen. Often times, developers come up with something like this:

     # Wrong!!!
    log4perl.logger = DEBUG, FileApp
    log4perl.logger = ERROR, ScreenApp
     # Wrong!!!

This won't work, however. Logger definitions aren't additive, and the
second statement will overwrite the first one. Log4perl versions
below 1.04 were silently accepting this, leaving people confused why
it wouldn't work as expected.
As of 1.04, this will throw a I<fatal error> to notify the user of
the problem.

What you want to do instead, is this:

    log4perl.logger                    = DEBUG, FileApp, ScreenApp

    log4perl.appender.FileApp          = Log::Log4perl::Appender::File
    log4perl.appender.FileApp.filename = test.log
    log4perl.appender.FileApp.layout   = SimpleLayout

    log4perl.appender.ScreenApp          = Log::Log4perl::Appender::Screen
    log4perl.appender.ScreenApp.stderr   = 0
    log4perl.appender.ScreenApp.layout   = SimpleLayout
       ### limiting output to ERROR messages
    log4perl.appender.ScreenApp.Threshold = ERROR
       ###

Note that without the second appender's C<Threshold> setting, both appenders
would receive all messages prioritized DEBUG and higher. With the
threshold set to ERROR, the second appender will filter the messages
as required.

=head2 Where should I put my logfiles?

Your log files may go anywhere you want them, but the effective
user id of the calling process must have write access.

If the log file doesn't exist at program start, Log4perl's file appender
will create it. For this, it needs write access to the directory where
the new file will be located in. If the log file already exists at startup,
the process simply needs write access to the file. Note that it will
need write access to the file's directory if you're encountering situations
where the logfile gets recreated, e.g. during log rotation.

If Log::Log4perl is used by a web server application (e.g. in a CGI script
or mod_perl), then the webserver's user (usually C<nobody> or C<www>)
must have the permissions mentioned above.

To prepare your web server to use log4perl, we'd recommend:

    webserver:~$ su -
    webserver:~# mkdir /var/log/cgiapps
    webserver:~# chown nobody:root /var/log/cgiapps/
    webserver:~# chown nobody:root -R /var/log/cgiapps/
    webserver:~# chmod 02755 -R /var/log/cgiapps/

Then set your /etc/log4perl.conf file to include:

    log4perl.appender.FileAppndr1.filename =
        /var/log/cgiapps/<app-name>.log

=head2 How can my file appender deal with disappearing log files?

The file appender that comes with Log4perl, L<Log::Log4perl::Appender::File>,
will open a specified log file at initialization time and will
keep writing to it via a file handle.

In case the associated file goes way, messages written by a
long-running process will still be written
to the file handle. In case the file has been moved to a different
location on the same file system, the writer will keep writing to
it under the new filename. In case the file has been removed from
the file system, the log messages will end up in nowhere land. This
is not a bug in Log4perl, this is how Unix works. There is
no error message in this case, because the writer has no idea that
the file handle is not associated with a visible file.

To prevent the loss of log messages when log files disappear, the
file appender's C<recreate> option needs to be set to a true value:

    log4perl.appender.Logfile.recreate = 1

This will instruct the file appender to check in regular intervals
(default: 30 seconds) if the log file is still there. If it finds
out that the file is missing, it will recreate it.

Continuously checking if the log file still exists is fairly
expensive. For this reason it is only performed every 30 seconds. To
change this interval, the option C<recreate_check_interval> can be set
to the number of seconds between checks. In the extreme case where the
check should be performed before every write, it can even be set to 0:

    log4perl.appender.Logfile.recreate = 1
    log4perl.appender.Logfile.recreate_check_interval = 0

To avoid having to check the file system so frequently, a signal
handler can be set up:

    log4perl.appender.Logfile.recreate = 1
    log4perl.appender.Logfile.recreate_check_signal = USR1

This will install a signal handler which will recreate a missing log file
immediately when it receives the defined signal.

Note that the init_and_watch() method for Log4perl's initialization
can also be instructed to install a signal handler, usually using the
HUP signal. Make sure to use a different signal if you're using both
of them at the same time.

=head2 How can I rotate a logfile with newsyslog?

Here's a few things that need to be taken care of when using the popular
log file rotating utility C<newsyslog>
(http://www.courtesan.com/newsyslog) with Log4perl's file appender
in long-running processes.

For example, with a newsyslog configuration like

    # newsyslog.conf
    /tmp/test.log 666  12  5  *  B

and a call to

    # newsyslog -f /path/to/newsyslog.conf

C<newsyslog> will take action if C</tmp/test.log> is larger than the
specified 5K in size. It will move the current log file C</tmp/test.log> to
C</tmp/test.log.0> and create a new and empty C</tmp/test.log> with
the specified permissions (this is why C<newsyslog> needs to run as root).
An already existing C</tmp/test.log.0> would be moved to
C</tmp/test.log.1>, C</tmp/test.log.1> to C</tmp/test.log.2>, and so
forth, for every one of a max number of 12 archived logfiles that have
been configured in C<newsyslog.conf>.

Although a new file has been created, from Log4perl's appender's point
of view, this situation is identical to the one described in the
previous FAQ entry, labeled C<How can my file appender deal with
disappearing log files>.

To make sure that log messages are written to the new log file and not
to an archived one or end up in nowhere land,
the appender's C<recreate> and C<recreate_check_interval> have to be
configured to deal with the 'disappearing' log file.

The situation gets interesting when C<newsyslog>'s option
to compress archived log files is enabled. This causes the
original log file not to be moved, but to disappear. If the
file appender isn't configured to recreate the logfile in this situation,
log messages will actually be lost without warning. This also
applies for the short time frame of C<recreate_check_interval> seconds
in between the recreator's file checks.

To make sure that no messages get lost, one option is to set the
interval to

    log4perl.appender.Logfile.recreate_check_interval = 0

However, this is fairly expensive. A better approach is to define
a signal handler:

    log4perl.appender.Logfile.recreate = 1
    log4perl.appender.Logfile.recreate_check_signal  = USR1
    log4perl.appender.Logfile.recreate_pid_write = /tmp/myappid

As a service for C<newsyslog> users, Log4perl's file appender writes
the current process ID to a PID file specified by the C<recreate_pid_write>
option.  C<newsyslog> then needs to be configured as in

    # newsyslog.conf configuration for compressing archive files and
    # sending a signal to the Log4perl-enabled application
    /tmp/test.log 666  12  5  *  B /tmp/myappid 30

to send the defined signal (30, which is USR1 on FreeBSD) to the
application process at rotation time. Note that the signal number
is different on Linux, where USR1 denotes as 10. Check C<man signal>
for details.

=head2 How can a process under user id A log to a file under user id B?

This scenario often occurs in configurations where processes run under
various user IDs but need to write to a log file under a fixed, but
different user id.

With a traditional file appender, the log file will probably be created
under one user's id and appended to under a different user's id. With
a typical umask of 0002, the file will be created with -rw-rw-r--
permissions. If a user who's not in the first user's group
subsequently appends to the log file, it will fail because of a
permission problem.

Two potential solutions come to mind:

=over 4

=item *

Creating the file with a umask of 0000 will allow all users to append
to the log file. Log4perl's file appender C<Log::Log4perl::Appender::File>
has an C<umask> option that can be set to support this:

    log4perl.appender.File = Log::Log4perl::Appender::File
    log4perl.appender.File.umask = sub { 0000 };

This way, the log file will be created with -rw-rw-rw- permissions and
therefore has world write permissions. This might open up the logfile
for unwanted manipulations by arbitrary users, though.

=item *

Running the process under an effective user id of C<root> will allow
it to write to the log file, no matter who started the process.
However, this is not a good idea, because of security concerns.

=back

Luckily, under Unix, there's the syslog daemon which runs as root and
takes log requests from user processes over a socket and writes them
to log files as configured in C</etc/syslog.conf>.

By modifying C</etc/syslog.conf> and HUPing the syslog daemon, you can
configure new log files:

    # /etc/syslog.conf
    ...
    user.* /some/path/file.log

Using the C<Log::Dispatch::Syslog> appender, which comes with the
C<Log::Log4perl> distribution, you can then send messages via syslog:

    use Log::Log4perl qw(:easy);

    Log::Log4perl->init(\<<EOT);
        log4perl.logger = DEBUG, app
        log4perl.appender.app=Log::Dispatch::Syslog
        log4perl.appender.app.Facility=user
        log4perl.appender.app.layout=SimpleLayout
    EOT

        # Writes to /some/path/file.log
    ERROR "Message!";

This way, the syslog daemon will solve the permission problem.

Note that while it is possible to use syslog() without Log4perl (syslog
supports log levels, too), traditional syslog setups have a
significant drawback.

Without Log4perl's ability to activate logging in only specific
parts of a system, complex systems will trigger log events all over
the place and slow down execution to a crawl at high debug levels.

Remote-controlling logging in the hierarchical parts of an application
via Log4perl's categories is one of its most distinguished features.
It allows for enabling high debug levels in specified areas without
noticeable performance impact.

=head2 I want to use UTC instead of the local time!

If a layout defines a date, Log::Log4perl uses local time to populate it.
If you want UTC instead, set

    log4perl.utcDateTimes = 1

in your configuration. Alternatively, you can set

    $Log::Log4perl::DateFormat::GMTIME = 1;

in your program before the first log statement.

=head2 Can Log4perl intercept messages written to a filehandle?

You have a function that prints to a filehandle. You want to tie
into that filehandle and forward all arriving messages to a
Log4perl logger.

First, let's write a package that ties a file handle and forwards it
to a Log4perl logger:

    package FileHandleLogger;
    use Log::Log4perl qw(:levels get_logger);

    sub TIEHANDLE {
       my($class, %options) = @_;

       my $self = {
           level    => $DEBUG,
           category => '',
           %options
       };

       $self->{logger} = get_logger($self->{category}),
       bless $self, $class;
    }

    sub PRINT {
        my($self, @rest) = @_;
        $Log::Log4perl::caller_depth++;
        $self->{logger}->log($self->{level}, @rest);
        $Log::Log4perl::caller_depth--;
    }

    sub PRINTF {
        my($self, $fmt, @rest) = @_;
        $Log::Log4perl::caller_depth++;
        $self->PRINT(sprintf($fmt, @rest));
        $Log::Log4perl::caller_depth--;
    }

    1;

Now, if you have a function like

    sub function_printing_to_fh {
        my($fh) = @_;
        printf $fh "Hi there!\n";
    }

which takes a filehandle and prints something to it, it can be used
with Log4perl:

    use Log::Log4perl qw(:easy);
    usa FileHandleLogger;

    Log::Log4perl->easy_init($DEBUG);

    tie *SOMEHANDLE, 'FileHandleLogger' or
        die "tie failed ($!)";

    function_printing_to_fh(*SOMEHANDLE);
        # prints "2007/03/22 21:43:30 Hi there!"

If you want, you can even specify a different log level or category:

    tie *SOMEHANDLE, 'FileHandleLogger',
        level => $INFO, category => "Foo::Bar" or die "tie failed ($!)";

=head2 I want multiline messages rendered line-by-line!

With the standard C<PatternLayout>, if you send a multiline message to
an appender as in

    use Log::Log4perl qw(:easy);
    Log

it gets rendered this way:

    2007/04/04 23:23:39 multi
    line
    message

If you want each line to be rendered separately according to
the layout use C<Log::Log4perl::Layout::PatternLayout::Multiline>:

    use Log::Log4perl qw(:easy);

    Log::Log4perl->init(\<<EOT);
      log4perl.category         = DEBUG, Screen
      log4perl.appender.Screen = Log::Log4perl::Appender::Screen
      log4perl.appender.Screen.layout = \\
        Log::Log4perl::Layout::PatternLayout::Multiline
      log4perl.appender.Screen.layout.ConversionPattern = %d %m %n
    EOT

    DEBUG "some\nmultiline\nmessage";

and you'll get

    2007/04/04 23:23:39 some
    2007/04/04 23:23:39 multiline
    2007/04/04 23:23:39 message

instead.

=head2 I'm on Windows and I'm getting all these 'redefined' messages!

If you're on Windows and are getting warning messages like

  Constant subroutine Log::Log4perl::_INTERNAL_DEBUG redefined at
    C:/Programme/Perl/lib/constant.pm line 103.
  Subroutine import redefined at
    C:/Programme/Perl/site/lib/Log/Log4Perl.pm line 69.
  Subroutine initialized redefined at
    C:/Programme/Perl/site/lib/Log/Log4Perl.pm line 207.

then chances are that you're using 'Log::Log4Perl' (wrong uppercase P)
instead of the correct 'Log::Log4perl'. Perl on Windows doesn't
handle this error well and spits out a slew of confusing warning
messages. But now you know, just use the correct module name and
you'll be fine.

=head2 Log4perl complains that no initialization happened during shutdown!

If you're using Log4perl log commands in DESTROY methods of your objects,
you might see confusing messages like

    Log4perl: Seems like no initialization happened. Forgot to call init()?
    Use of uninitialized value in subroutine entry at
    /home/y/lib/perl5/site_perl/5.6.1/Log/Log4perl.pm line 134 during global
    destruction. (in cleanup) Undefined subroutine &main:: called at
    /home/y/lib/perl5/site_perl/5.6.1/Log/Log4perl.pm line 134 during global
    destruction.

when the program shuts down. What's going on?

This phenomenon happens if you have circular references in your objects,
which perl can't clean up when an object goes out of scope but waits
until global destruction instead. At this time, however, Log4perl has
already shut down, so you can't use it anymore.

For example, here's a simple class which uses a logger in its DESTROY
method:

    package A;
    use Log::Log4perl qw(:easy);
    sub new { bless {}, shift }
    sub DESTROY { DEBUG "Waaah!"; }

Now, if the main program creates a self-referencing object, like in

    package main;
    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($DEBUG);

    my $a = A->new();
    $a->{selfref} = $a;

then you'll see the error message shown above during global destruction.
How to tackle this problem?

First, you should clean up your circular references before global
destruction. They will not only cause objects to be destroyed in an order
that's hard to predict, but also eat up memory until the program shuts
down.

So, the program above could easily be fixed by putting

    $a->{selfref} = undef;

at the end or in an END handler. If that's hard to do, use weak references:

    package main;
    use Scalar::Util qw(weaken);
    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($DEBUG);

    my $a = A->new();
    $a->{selfref} = weaken $a;

This allows perl to clean up the circular reference when the object
goes out of scope, and doesn't wait until global destruction.

=head2 How can I access POE heap values from Log4perl's layout?

POE is a framework for creating multitasked applications running in a
single process and a single thread. POE's threads equivalents are
'sessions' and since they run quasi-simultaneously, you can't use
Log4perl's global NDC/MDC to hold session-specific data.

However, POE already maintains a data store for every session. It is called
'heap' and is just a hash storing session-specific data in key-value pairs.
To access this per-session heap data from a Log4perl layout, define a
custom cspec and reference it with the newly defined pattern in the layout:

    use strict;
    use POE;
    use Log::Log4perl qw(:easy);

    Log::Log4perl->init( \ q{
        log4perl.logger = DEBUG, Screen
        log4perl.appender.Screen = Log::Log4perl::Appender::Screen
        log4perl.appender.Screen.layout = PatternLayout
        log4perl.appender.Screen.layout.ConversionPattern = %U %m%n
        log4perl.PatternLayout.cspec.U = \
            sub { POE::Kernel->get_active_session->get_heap()->{ user } }
    } );

    for (qw( Huey Lewey Dewey )) {
        POE::Session->create(
            inline_states => {
                _start    => sub {
                    $_[HEAP]->{user} = $_;
                    POE::Kernel->yield('hello');
                },
                hello     => sub {
                    DEBUG "I'm here now";
                }
            }
        );
    }

    POE::Kernel->run();
    exit;

The code snippet above defines a new layout placeholder (called
'cspec' in Log4perl) %U which calls a subroutine, retrieves the active
session, gets its heap and looks up the entry specified ('user').

Starting with Log::Log4perl 1.20, cspecs also support parameters in
curly braces, so you can say

    log4perl.appender.Screen.layout.ConversionPattern = %U{user} %U{id} %m%n
    log4perl.PatternLayout.cspec.U = \
            sub { POE::Kernel->get_active_session-> \
                  get_heap()->{ $_[0]->{curlies} } }

and print the POE session heap entries 'user' and 'id' with every logged
message. For more details on cpecs, read the PatternLayout manual.

=head2 I want to print something unconditionally!

Sometimes it's a script that's supposed to log messages regardless if
Log4perl has been initialized or not. Or there's a logging statement that's
not going to be suppressed under any circumstances -- many people want to
have the final word, make the executive decision, because it seems like
the only logical choice.

But think about it:
First off, if a messages is supposed to be printed, where is it supposed
to end up at? STDOUT? STDERR? And are you sure you want to set in stone
that this message needs to be printed, while someone else might
find it annoying and wants to get rid of it?

The truth is, there's always going to be someone who wants to log a
messages at all cost, but also another person who wants to suppress it
with equal vigilance. There's no good way to serve these two conflicting
desires, someone will always want to win at the cost of leaving
the other party disappointed.

So, the best Log4perl offers is the ALWAYS level for a message that even
fires if the system log level is set to $OFF:

    use Log::Log4perl qw(:easy);

    Log::Log4perl->easy_init( $OFF );
    ALWAYS "This gets logged always. Well, almost always";

The logger won't fire, though, if Log4perl hasn't been initialized or
if someone defines a custom log hurdle that's higher than $OFF.

Bottom line: Leave the setting of the logging level to the initial Perl
script -- let their owners decided what they want, no matter how tempting
it may be to decide it for them.

=head2 Why doesn't my END handler remove my log file on Win32?

If you have code like

    use Log::Log4perl qw( :easy );
    Log::Log4perl->easy_init( { level => $DEBUG, file => "my.log" } );
    END { unlink "my.log" or die };

then you might be in for a surprise when you're running it on
Windows, because the C<unlink()> call in the END handler will complain that
the file is still in use.

What happens in Perl if you have something like

    END { print "first end in main\n"; }
    use Module;
    END { print "second end in main\n"; }

and

    package Module;
    END { print "end in module\n"; }
    1;

is that you get

    second end in main
    end in module
    first end in main

because perl stacks the END handlers in reverse order in which it
encounters them in the compile phase.

Log4perl defines an END handler that cleans up left-over appenders (e.g.
file appenders which still hold files open), because those appenders have
circular references and therefore aren't cleaned up otherwise.

Now if you define an END handler after "use Log::Log4perl", it'll
trigger before Log4perl gets a chance to clean up, which isn't a 
problem on Unix where you can delete a file even if some process has a 
handle to it open, but it's a problem on Win32, where the OS won't 
let you do that.

The solution is easy, just place the END handler I<before> Log4perl
gets loaded, like in

    END { unlink "my.log" or die };
    use Log::Log4perl qw( :easy );
    Log::Log4perl->easy_init( { level => $DEBUG, file => "my.log" } );

which will call the END handlers in the intended order.

=cut

=head1 SEE ALSO

Log::Log4perl

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

