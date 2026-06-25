##################################################
package Log::Log4perl::Filter;
##################################################

use 5.006;
use strict;
use warnings;

use Log::Log4perl::Level;
use Log::Log4perl::Config;

use constant _INTERNAL_DEBUG => 0;

our %FILTERS_DEFINED = ();

##################################################
sub new {
##################################################
    my($class, $name, $action) = @_;
  
    print "Creating filter $name\n" if _INTERNAL_DEBUG;

    my $self = { name => $name };
    bless $self, $class;

    if(ref($action) eq "CODE") {
        # it's a code ref
        $self->{ok} = $action;
    } else {
        # it's something else
        die "Code for ($name/$action) not properly defined";
    }

    return $self;
}

##################################################
sub register {         # Register a filter by name
                       # (Passed on to subclasses)
##################################################
    my($self) = @_;

    by_name($self->{name}, $self);
}

##################################################
sub by_name {        # Get/Set a filter object by name
##################################################
    my($name, $value) = @_;

    if(defined $value) {
        $FILTERS_DEFINED{$name} = $value;
    }

    if(exists $FILTERS_DEFINED{$name}) {
        return $FILTERS_DEFINED{$name};
    } else {
        return undef;
    }
}

##################################################
sub reset {
##################################################
    %FILTERS_DEFINED = ();
}

##################################################
sub ok {
##################################################
    my($self, %p) = @_;

    print "Calling $self->{name}'s ok method\n" if _INTERNAL_DEBUG;

        # Force filter classes to define their own
        # ok(). Exempt are only sub {..} ok functions,
        # defined in the conf file.
    die "This is to be overridden by the filter" unless
         defined $self->{ok};

    # What should we set the message in $_ to? The most logical
    # approach seems to be to concat all parts together. If some
    # filter wants to dissect the parts, it still can examine %p,
    # which gets passed to the subroutine and contains the chunks
    # in $p{message}.
        # Split because of CVS
    local($_) = join $
                     Log::Log4perl::JOIN_MSG_ARRAY_CHAR, @{$p{message}};
    print "\$_ is '$_'\n" if _INTERNAL_DEBUG;

    my $decision = $self->{ok}->(%p);

    print "$self->{name}'s ok'ed: ", 
          ($decision ? "yes" : "no"), "\n" if _INTERNAL_DEBUG;

    return $decision;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Filter - Log4perl Custom Filter Base Class

=head1 SYNOPSIS

  use Log::Log4perl;

  Log::Log4perl->init(\ <<'EOT');
    log4perl.logger = INFO, Screen
    log4perl.filter.MyFilter        = sub { /let this through/ }
    log4perl.appender.Screen        = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.Filter = MyFilter
    log4perl.appender.Screen.layout = Log::Log4perl::Layout::SimpleLayout
  EOT

      # Define a logger
  my $logger = Log::Log4perl->get_logger("Some");

      # Let this through
  $logger->info("Here's the info, let this through!");

      # Suppress this
  $logger->info("Here's the info, suppress this!");

  #################################################################
  # StringMatch Filter:
  #################################################################
  log4perl.filter.M1               = Log::Log4perl::Filter::StringMatch
  log4perl.filter.M1.StringToMatch = let this through
  log4perl.filter.M1.AcceptOnMatch = true

  #################################################################
  # LevelMatch Filter:
  #################################################################
  log4perl.filter.M1               = Log::Log4perl::Filter::LevelMatch
  log4perl.filter.M1.LevelToMatch  = INFO
  log4perl.filter.M1.AcceptOnMatch = true

=head1 DESCRIPTION

Log4perl allows the use of customized filters in its appenders
to control the output of messages. These filters might grep for
certain text chunks in a message, verify that its priority
matches or exceeds a certain level or that this is the 10th
time the same message has been submitted -- and come to a log/no log 
decision based upon these circumstantial facts.

Filters have names and can be specified in two different ways in the Log4perl
configuration file: As subroutines or as filter classes. Here's a 
simple filter named C<MyFilter> which just verifies that the 
oncoming message matches the regular expression C</let this through/i>:

    log4perl.filter.MyFilter        = sub { /let this through/i }

It exploits the fact that when the subroutine defined
above is called on a message,
Perl's special C<$_> variable will be set to the message text (prerendered,
i.e. concatenated but not layouted) to be logged. 
The subroutine is expected to return a true value 
if it wants the message to be logged or a false value if doesn't.

Also, Log::Log4perl will pass a hash to the subroutine,
containing all key/value pairs that it would pass to the corresponding 
appender, as specified in Log::Log4perl::Appender. Here's an
example of a filter checking the priority of the oncoming message:

  log4perl.filter.MyFilter        = sub {    \
       my %p = @_;                           \
       if($p{log4p_level} eq "WARN" or       \
          $p{log4p_level} eq "INFO") {       \
           return 1;                         \
       }                                     \
       return 0;                             \
  }     

If the message priority equals C<WARN> or C<INFO>, 
it returns a true value, causing
the message to be logged.

=head2 Predefined Filters

For common tasks like verifying that the message priority matches
a certain priority, there's already a 
set of predefined filters available. To perform an exact level match, it's
much cleaner to use Log4perl's C<LevelMatch> filter instead:

  log4perl.filter.M1               = Log::Log4perl::Filter::LevelMatch
  log4perl.filter.M1.LevelToMatch  = INFO
  log4perl.filter.M1.AcceptOnMatch = true

This will let the message through if its priority is INFO and suppress
it otherwise. The statement can be negated by saying

  log4perl.filter.M1.AcceptOnMatch = false

instead. This way, the message will be logged if its priority is
anything but INFO.

On a similar note, Log4perl's C<StringMatch> filter will check the 
oncoming message for strings or regular expressions:

  log4perl.filter.M1               = Log::Log4perl::Filter::StringMatch
  log4perl.filter.M1.StringToMatch = bl.. bl..
  log4perl.filter.M1.AcceptOnMatch = true

This will open the gate for messages like C<blah blah> because the 
regular expression in the C<StringToMatch> matches them. Again,
the setting of C<AcceptOnMatch> determines if the filter is defined
in a positive or negative way.

All class filter entries in the configuration file
have to adhere to the following rule:
Only after a filter has been defined by name and class/subroutine,
its attribute values can be
assigned, just like the C<true> value above gets assigned to the
C<AcceptOnMatch> attribute I<after> the
filter C<M1> has been defined.

=head2 Attaching a filter to an appender

Attaching a filter to an appender is as easy as assigning its name to
the appender's C<Filter> attribute:

    log4perl.appender.MyAppender.Filter = MyFilter

This will cause C<Log::Log4perl> to call the filter subroutine/method
every time a message is supposed to be passed to the appender. Depending
on the filter's return value, C<Log::Log4perl> will either continue as
planned or withdraw immediately.

=head2 Combining filters with Log::Log4perl::Filter::Boolean

Sometimes, it's useful to combine the output of various filters to
arrive at a log/no log decision. While Log4j, Log4perl's mother ship,
has chosen to implement this feature as a filter chain, similar to Linux' IP chains,
Log4perl tries a different approach. 

Typically, filter results will not need to be bumped along chains but 
combined in a programmatic manner using boolean logic. "Log if
this filter says 'yes' and that filter says 'no'" 
is a fairly common requirement, but hard to implement as a chain.

C<Log::Log4perl::Filter::Boolean> is a specially predefined custom filter
for Log4perl. It combines the results of other custom filters 
in arbitrary ways, using boolean expressions:

    log4perl.logger = WARN, AppWarn, AppError

    log4perl.filter.Match1       = sub { /let this through/ }
    log4perl.filter.Match2       = sub { /and that, too/ }
    log4perl.filter.MyBoolean       = Log::Log4perl::Filter::Boolean
    log4perl.filter.MyBoolean.logic = Match1 || Match2

    log4perl.appender.Screen        = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.Filter = MyBoolean
    log4perl.appender.Screen.layout = Log::Log4perl::Layout::SimpleLayout

C<Log::Log4perl::Filter::Boolean>'s boolean expressions allow for combining
different appenders by name using AND (&& or &), OR (|| or |) and NOT (!) as
logical expressions. Also, parentheses can be used for defining precedences. 
Operator precedence follows standard Perl conventions. Here's a bunch of examples:

    Match1 && !Match2            # Match1 and not Match2
    !(Match1 || Match2)          # Neither Match1 nor Match2
    (Match1 && Match2) || Match3 # Both Match1 and Match2 or Match3

=head2 Writing your own filter classes

If none of Log::Log4perl's predefined filter classes fits your needs,
you can easily roll your own: Just define a new class,
derive it from the baseclass C<Log::Log4perl::Filter>,
and define its C<new> and C<ok> methods like this:

    package Log::Log4perl::Filter::MyFilter;

    use base Log::Log4perl::Filter;

    sub new {
        my ($class, %options) = @_;

        my $self = { %options,
                   };
     
        bless $self, $class;

        return $self;
    }

    sub ok {
         my ($self, %p) = @_;

         # ... decide and return 1 or 0
    }

    1;

Log4perl will call the ok() method to determine if the filter
should let the message pass or not. A true return value indicates
the message will be logged by the appender, a false value blocks it.

Values you've defined for its attributes in Log4perl's configuration file,
will be received through its C<new> method:

    log4perl.filter.MyFilter       = Log::Log4perl::Filter::MyFilter
    log4perl.filter.MyFilter.color = red

will cause C<Log::Log4perl::Filter::MyFilter>'s constructor to be called
like this:

    Log::Log4perl::Filter::MyFilter->new( name  => "MyFilter",
                                          color => "red" );

The custom filter class should use this to set the object's attributes, 
to have them available later to base log/nolog decisions on it.

C<ok()> is the filter's method to tell if it agrees or disagrees with logging
the message. It will be called by Log::Log4perl whenever it needs the
filter to decide. A false value returned by C<ok()> will block messages,
a true value will let them through.

=head2 A Practical Example: Level Matching

See L<Log::Log4perl::FAQ> for this.

=head1 SEE ALSO

L<Log::Log4perl::Filter::LevelMatch>,
L<Log::Log4perl::Filter::LevelRange>,
L<Log::Log4perl::Filter::StringRange>,
L<Log::Log4perl::Filter::Boolean>

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

