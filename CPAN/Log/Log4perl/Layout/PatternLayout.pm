##################################################
package Log::Log4perl::Layout::PatternLayout;
##################################################

use 5.006;
use strict;
use warnings;
use Carp;
use Log::Log4perl::Util;
use Log::Log4perl::Level;
use Log::Log4perl::DateFormat;
use Log::Log4perl::NDC;
use Log::Log4perl::MDC;
use File::Spec;

our $TIME_HIRES_AVAILABLE;
our $TIME_HIRES_AVAILABLE_WARNED = 0;
our $HOSTNAME;
our $PROGRAM_START_TIME;

our %GLOBAL_USER_DEFINED_CSPECS = ();

our $CSPECS = 'cCdFHIlLmMnpPrtTxX%';


BEGIN {
    # Check if we've got Time::HiRes. If not, don't make a big fuss,
    # just set a flag so we know later on that we can't have fine-grained
    # time stamps
    $TIME_HIRES_AVAILABLE = 0;
    if(Log::Log4perl::Util::module_available("Time::HiRes")) {
        require Time::HiRes;
        $TIME_HIRES_AVAILABLE = 1;
        $PROGRAM_START_TIME = [Time::HiRes::gettimeofday()];
    } else {
        $PROGRAM_START_TIME = time();
    }

    # Check if we've got Sys::Hostname. If not, just punt.
    $HOSTNAME = "unknown.host";
    if(Log::Log4perl::Util::module_available("Sys::Hostname")) {
        require Sys::Hostname;
        $HOSTNAME = Sys::Hostname::hostname();
    }
}

##################################################
sub current_time {
##################################################
    # Return secs and optionally msecs if we have Time::HiRes
    if($TIME_HIRES_AVAILABLE) {
        return (Time::HiRes::gettimeofday());
    } else {
        return (time(), 0);
    }
}

use base qw(Log::Log4perl::Layout);

no strict qw(refs);

##################################################
sub new {
##################################################
    my $class = shift;
    $class = ref ($class) || $class;

    my $options       = ref $_[0] eq "HASH" ? shift : {};
    my $layout_string = @_ ? shift : '%m%n';
    
    if(exists $options->{ConversionPattern}->{value}) {
        $layout_string = $options->{ConversionPattern}->{value};
    }

    my $self = {
        time_function         => \&current_time,
        format                => undef,
        info_needed           => {},
        stack                 => [],
        CSPECS                => $CSPECS,
        dontCollapseArrayRefs => $options->{dontCollapseArrayRefs}{value},
    };

    if(exists $options->{time_function}) {
        $self->{time_function} = $options->{time_function};
    }

    bless $self, $class;

    #add the global user-defined cspecs
    foreach my $f (keys %GLOBAL_USER_DEFINED_CSPECS){
            #add it to the list of letters
        $self->{CSPECS} .= $f;
             #for globals, the coderef is already evaled, 
        $self->{USER_DEFINED_CSPECS}{$f} = $GLOBAL_USER_DEFINED_CSPECS{$f};
    }

    #add the user-defined cspecs local to this appender
    foreach my $f (keys %{$options->{cspec}}){
        $self->add_layout_cspec($f, $options->{cspec}{$f}{value});
    }

    $self->define($layout_string);

    return $self;
}

##################################################
sub define {
##################################################
    my($self, $format) = @_;

        # If the message contains a %m followed by a newline,
        # make a note of that so that we can cut a superfluous 
        # \n off the message later on
    if($format =~ /%m%n/) {
        $self->{message_chompable} = 1;
    } else {
        $self->{message_chompable} = 0;
    }

    # Parse the format
    $format =~ s/%(-?\d*(?:\.\d+)?) 
                       ([$self->{CSPECS}])
                       (?:{(.*?)})*/
                       rep($self, $1, $2, $3);
                      /gex;

    $self->{printformat} = $format;
}

##################################################
sub rep {
##################################################
    my($self, $num, $op, $curlies) = @_;

    return "%%" if $op eq "%";

    # If it's a %d{...} construct, initialize a simple date
    # format formatter, so that we can quickly render later on.
    # If it's just %d, assume %d{yyyy/MM/dd HH:mm:ss}
    my $sdf;
    if($op eq "d") {
        if(defined $curlies) {
            $sdf = Log::Log4perl::DateFormat->new($curlies);
        } else {
            $sdf = Log::Log4perl::DateFormat->new("yyyy/MM/dd HH:mm:ss");
        }
    }

    push @{$self->{stack}}, [$op, $sdf || $curlies];

    $self->{info_needed}->{$op}++;

    return "%${num}s";
}

##################################################
sub render {
##################################################
    my($self, $message, $category, $priority, $caller_level) = @_;

    $caller_level = 0 unless defined  $caller_level;

    my %info    = ();

    $info{m}    = $message;
        # See 'define'
    chomp $info{m} if $self->{message_chompable};

    my @results = ();

    if($self->{info_needed}->{L} or
       $self->{info_needed}->{F} or
       $self->{info_needed}->{C} or
       $self->{info_needed}->{l} or
       $self->{info_needed}->{M} or
       0
      ) {
        my ($package, $filename, $line, 
            $subroutine, $hasargs,
            $wantarray, $evaltext, $is_require, 
            $hints, $bitmask) = caller($caller_level);

        # If caller() choked because of a whacko caller level,
        # correct undefined values to '[undef]' in order to prevent 
        # warning messages when interpolating later
        unless(defined $bitmask) {
            for($package, 
                $filename, $line,
                $subroutine, $hasargs,
                $wantarray, $evaltext, $is_require,
                $hints, $bitmask) {
                $_ = '[undef]' unless defined $_;
            }
        }

        $info{L} = $line;
        $info{F} = $filename;
        $info{C} = $package;

        if($self->{info_needed}->{M} or
           $self->{info_needed}->{l} or
           0) {
            # To obtain the name of the subroutine which triggered the 
            # logger, we need to go one additional level up.
            my $levels_up = 1; 
            {
                $subroutine = (caller($caller_level+$levels_up))[3];
                    # If we're inside an eval, go up one level further.
                if(defined $subroutine and
                   $subroutine eq "(eval)") {
                    $levels_up++;
                    redo;
                }
            }
            $subroutine = "main::" unless $subroutine;
            $info{M} = $subroutine;
            $info{l} = "$subroutine $filename ($line)";
        }
    }

    $info{X} = "[No curlies defined]";
    $info{x} = Log::Log4perl::NDC->get() if $self->{info_needed}->{x};
    $info{c} = $category;
    $info{d} = 1; # Dummy value, corrected later
    $info{n} = "\n";
    $info{p} = $priority;
    $info{P} = $$;
    $info{H} = $HOSTNAME;

    if($self->{info_needed}->{r}) {
        if($TIME_HIRES_AVAILABLE) {
            $info{r} = 
                int((Time::HiRes::tv_interval ( $PROGRAM_START_TIME ))*1000);
        } else {
            if(! $TIME_HIRES_AVAILABLE_WARNED) {
                $TIME_HIRES_AVAILABLE_WARNED++;
                # warn "Requested %r pattern without installed Time::HiRes\n";
            }
            $info{r} = time() - $PROGRAM_START_TIME;
        }
    }

        # Stack trace wanted?
    if($self->{info_needed}->{T}) {
        my $mess = Carp::longmess(); 
        chomp($mess);
        $mess =~ s/(?:\A\s*at.*\n|^\s*Log::Log4perl.*\n|^\s*)//mg;
        $mess =~ s/\n/, /g;
        $info{T} = $mess;
    }

        # As long as they're not implemented yet ..
    $info{t} = "N/A";

    foreach my $cspec (keys %{$self->{USER_DEFINED_CSPECS}}){
        next unless $self->{info_needed}->{$cspec};
        $info{$cspec} = $self->{USER_DEFINED_CSPECS}->{$cspec}->($self, 
                              $message, $category, $priority, $caller_level+1);
    }

        # Iterate over all info fields on the stack
    for my $e (@{$self->{stack}}) {
        my($op, $curlies) = @$e;
        if(exists $info{$op}) {
            my $result = $info{$op};
            if($curlies) {
                $result = $self->curly_action($op, $curlies, $info{$op});
            } else {
                # just for %d
                if($op eq 'd') {
                    $result = $info{$op}->format($self->{time_function}->());
                }
            }
            $result = "[undef]" unless defined $result;
            push @results, $result;
        } else {
            warn "Format %'$op' not implemented (yet)";
            push @results, "FORMAT-ERROR";
        }
    }

    #print STDERR "sprintf $self->{printformat}--$results[0]--\n";

    return (sprintf $self->{printformat}, @results);
}

##################################################
sub curly_action {
##################################################
    my($self, $ops, $curlies, $data) = @_;

    if($ops eq "c") {
        $data = shrink_category($data, $curlies);
    } elsif($ops eq "C") {
        $data = shrink_category($data, $curlies);
    } elsif($ops eq "X") {
        $data = Log::Log4perl::MDC->get($curlies);
    } elsif($ops eq "d") {
        $data = $curlies->format($self->{time_function}->());
    } elsif($ops eq "F") {
        my @parts = File::Spec->splitdir($data);
            # Limit it to max curlies entries
        if(@parts > $curlies) {
            splice @parts, 0, @parts - $curlies;
        }
        $data = File::Spec->catfile(@parts);
    }

    return $data;
}

##################################################
sub shrink_category {
##################################################
    my($category, $len) = @_;

    my @components = split /\.|::/, $category;

    if(@components > $len) {
        splice @components, 0, @components - $len;
        $category = join '.', @components;
    } 

    return $category;
}

##################################################
sub add_global_cspec {
##################################################
# This is a Class method.
# Accepts a coderef or text
##################################################

    unless($Log::Log4perl::ALLOW_CODE_IN_CONFIG_FILE) {
        die "\$Log::Log4perl::ALLOW_CODE_IN_CONFIG_FILE setting " .
            "prohibits user defined cspecs";
    }

    my ($letter, $perlcode) = @_;

    croak "Illegal value '$letter' in call to add_global_cspec()"
        unless ($letter =~ /^[a-zA-Z]$/);

    croak "Missing argument for perlcode for 'cspec.$letter' ".
          "in call to add_global_cspec()"
        unless $perlcode;

    croak "Please don't redefine built-in cspecs [$CSPECS]\n".
          "like you do for \"cspec.$letter\"\n "
        if ($CSPECS =~/$letter/);

    if (ref $perlcode eq 'CODE') {
        $GLOBAL_USER_DEFINED_CSPECS{$letter} = $perlcode;

    }elsif (! ref $perlcode){
        
        $GLOBAL_USER_DEFINED_CSPECS{$letter} = 
            Log::Log4perl::Config::compile_if_perl($perlcode);

        if ($@) {
            die qq{Compilation failed for your perl code for }.
                qq{"log4j.PatternLayout.cspec.$letter":\n}.
                qq{This is the error message: \t$@\n}.
                qq{This is the code that failed: \n$perlcode\n};
        }

        croak "eval'ing your perlcode for 'log4j.PatternLayout.cspec.$letter' ".
              "doesn't return a coderef \n".
              "Here is the perl code: \n\t$perlcode\n "
            unless (ref $GLOBAL_USER_DEFINED_CSPECS{$letter} eq 'CODE');

    }else{
        croak "I don't know how to handle perlcode=$perlcode ".
              "for 'cspec.$letter' in call to add_global_cspec()";
    }
}

##################################################
sub add_layout_cspec {
##################################################
# object method
# adds a cspec just for this layout
##################################################
    my ($self, $letter, $perlcode) = @_;

    unless($Log::Log4perl::ALLOW_CODE_IN_CONFIG_FILE) {
        die "\$Log::Log4perl::ALLOW_CODE_IN_CONFIG_FILE setting " .
            "prohibits user defined cspecs";
    }

    croak "Illegal value '$letter' in call to add_layout_cspec()"
        unless ($letter =~ /^[a-zA-Z]$/);

    croak "Missing argument for perlcode for 'cspec.$letter' ".
          "in call to add_layout_cspec()"
        unless $perlcode;

    croak "Please don't redefine built-in cspecs [$CSPECS] \n".
          "like you do for 'cspec.$letter'"
        if ($CSPECS =~/$letter/);

    if (ref $perlcode eq 'CODE') {

        $self->{USER_DEFINED_CSPECS}{$letter} = $perlcode;

    }elsif (! ref $perlcode){
        
        $self->{USER_DEFINED_CSPECS}{$letter} =
            Log::Log4perl::Config::compile_if_perl($perlcode);

        if ($@) {
            die qq{Compilation failed for your perl code for }.
                qq{"cspec.$letter":\n}.
                qq{This is the error message: \t$@\n}.
                qq{This is the code that failed: \n$perlcode\n};
        }
        croak "eval'ing your perlcode for 'cspec.$letter' ".
              "doesn't return a coderef \n".
              "Here is the perl code: \n\t$perlcode\n "
            unless (ref $self->{USER_DEFINED_CSPECS}{$letter} eq 'CODE');


    }else{
        croak "I don't know how to handle perlcode=$perlcode ".
              "for 'cspec.$letter' in call to add_layout_cspec()";
    }

    $self->{CSPECS} .= $letter;
}


1;

__END__

=head1 NAME

Log::Log4perl::Layout::PatternLayout - Pattern Layout

=head1 SYNOPSIS

  use Log::Log4perl::Layout::PatternLayout;

  my $layout = Log::Log4perl::Layout::PatternLayout->new(
                                                   "%d (%F:%L)> %m");


=head1 DESCRIPTION

Creates a pattern layout according to
http://jakarta.apache.org/log4j/docs/api/org/apache/log4j/PatternLayout.html
and a couple of Log::Log4perl-specific extensions.

The C<new()> method creates a new PatternLayout, specifying its log
format. The format
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
    %M Method or function where the logging request was issued
    %n Newline (OS-independent)
    %p Priority of the logging event
    %P pid of the current process
    %r Number of milliseconds elapsed from program start to logging 
       event
    %T A stack trace of functions called
    %x The topmost NDC (see below)
    %X{key} The entry 'key' of the MDC (see below)
    %% A literal percent (%) sign

NDC and MDC are explained in L<Log::Log4perl/"Nested Diagnostic Context (NDC)">
and L<Log::Log4perl/"Mapped Diagnostic Context (MDC)">.

The granularity of time values is milliseconds if Time::HiRes is available.
If not, only full seconds are used.

=head2 Quantify placeholders

All placeholders can be extended with formatting instructions,
just like in I<printf>:

    %20c   Reserve 20 chars for the category, right-justify and fill
           with blanks if it is shorter
    %-20c  Same as %20c, but left-justify and fill the right side 
           with blanks
    %09r   Zero-pad the number of milliseconds to 9 digits
    %.8c   Specify the maximum field with and have the formatter
           cut off the rest of the value

=head2 Fine-tuning with curlies

Some placeholders have special functions defined if you add curlies 
with content after them:

    %c{1}  Just show the right-most category compontent, useful in large
           class hierarchies (Foo::Baz::Bar -> Bar)
    %c{2}  Just show the two right most category components
           (Foo::Baz::Bar -> Baz::Bar)

    %F     Display source file including full path
    %F{1}  Just display filename
    %F{2}  Display filename and last path component (dir/test.log)
    %F{3}  Display filename and last two path components (d1/d2/test.log)

In this way, you're able to shrink the displayed category or
limit file/path components to save space in your logs.

=head2 Fine-tune the date

If you're not happy with the default %d format for the date which 
looks like

    yyyy/MM/DD HH:mm:ss

(which is slightly different from Log4j which uses C<yyyy-MM-dd HH:mm:ss,SSS>)
you're free to fine-tune it in order to display only certain characteristics
of a date, according to the SimpleDateFormat in the Java World
(http://java.sun.com/j2se/1.3/docs/api/java/text/SimpleDateFormat.html):

    %d{HH:mm}     "23:45" -- Just display hours and minutes
    %d{yy, EEEE}  "02, Monday" -- Just display two-digit year 
                                  and spelled-out weekday
Here's the symbols and their meaning, according to the SimpleDateFormat
specification:

    Symbol   Meaning                 Presentation     Example
    ------   -------                 ------------     -------
    G        era designator          (Text)           AD
    y        year                    (Number)         1996 
    M        month in year           (Text & Number)  July & 07
    d        day in month            (Number)         10
    h        hour in am/pm (1-12)    (Number)         12
    H        hour in day (0-23)      (Number)         0
    m        minute in hour          (Number)         30
    s        second in minute        (Number)         55
    E        day in week             (Text)           Tuesday
    D        day in year             (Number)         189
    a        am/pm marker            (Text)           PM

    (Text): 4 or more pattern letters--use full form, < 4--use short or 
            abbreviated form if one exists. 

    (Number): the minimum number of digits. Shorter numbers are 
              zero-padded to this amount. Year is handled 
              specially; that is, if the count of 'y' is 2, the 
              Year will be truncated to 2 digits. 

    (Text & Number): 3 or over, use text, otherwise use number. 

There's also a bunch of pre-defined formats:

    %d{ABSOLUTE}   "HH:mm:ss,SSS"
    %d{DATE}       "dd MMM yyyy HH:mm:ss,SSS"
    %d{ISO8601}    "yyyy-MM-dd HH:mm:ss,SSS"

=head2 Custom cspecs

First of all, "cspecs" is short for "conversion specifiers", which is 
the log4j and the printf(3) term for what Mike is calling "placeholders."
I suggested "cspecs" for this part of the api before I saw that Mike was 
using "placeholders" consistently in the log4perl documentation.  Ah, the
joys of collaboration ;=) --kg

If the existing corpus of placeholders/cspecs isn't good enough for you,
you can easily roll your own:

    #'U' a global user-defined cspec     
    log4j.PatternLayout.cspec.U = sub { return "UID: $< "}
    
    #'K' cspec local to appndr1                 (pid in hex)
    log4j.appender.appndr1.layout.cspec.K = sub { return sprintf "%1x", $$}
    
    #and now you can use them
    log4j.appender.appndr1.layout.ConversionPattern = %K %U %m%n

The benefit of this approach is that you can define and use the cspecs 
right next to each other in the config file.

If you're an API kind of person, there's also this call:

    Log::Log4perl::Layout::PatternLayout::
                    add_global_cspec('Z', sub {'zzzzzzzz'}); #snooze?

When the log messages is being put together, your anonymous sub 
will be called with these arguments:

    ($layout, $message, $category, $priority, $caller_level);
    
    layout: the PatternLayout object that called it
    message: the logging message (%m)
    category: e.g. groceries.beverages.adult.beer.schlitz
    priority: e.g. DEBUG|WARN|INFO|ERROR|FATAL
    caller_level: how many levels back up the call stack you have 
        to go to find the caller

There are currently some issues around providing API access to an 
appender-specific cspec, but let us know if this is something you want.

Please note that the subroutines you're defining in this way are going
to be run in the C<main> namespace, so be sure to fully qualify functions
and variables if they're located in different packages.

B<SECURITY NOTE>
  
This feature means arbitrary perl code can be embedded in the config file. 
In the rare case where the people who have access to your config file are
different from the people who write your code and shouldn't have execute
rights, you might want to set

    $Log::Log4perl::Config->allow_code(0);

before you call init().  Alternatively you can supply a restricted set of
Perl opcodes that can be embedded in the config file as described in
L<Log::Log4perl/"Restricting what Opcodes can be in a Perl Hook">.
  
=head2 Advanced Options

The constructor of the C<Log::Log4perl::Layout::PatternLayout> class
takes an optional hash reference as a first argument to specify
additional options in order to (ab)use it in creative ways:

  my $layout = Log::Log4perl::Layout::PatternLayout->new(
    { time_function       => \&my_time_func,
    }, 
    "%d (%F:%L)> %m");

Here's a list of parameters:

=over 4

=item time_function

Takes a reference to a function returning the time for the time/date
fields, either in seconds
since the epoch or as a reference to an array, carrying seconds and 
microseconds, just like C<Time::HiRes::gettimeofday> does.

=back

=head1 SEE ALSO

=head1 AUTHOR

Mike Schilli, E<lt>m@perlmeister.comE<gt>

=cut
