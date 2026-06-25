##################################################
package Log::Log4perl::Layout::PatternLayout;
##################################################

use 5.006;
use strict;
use warnings;

use constant _INTERNAL_DEBUG => 0;

use Carp;
use Log::Log4perl::Util;
use Log::Log4perl::Level;
use Log::Log4perl::DateFormat;
use Log::Log4perl::NDC;
use Log::Log4perl::MDC;
use Log::Log4perl::Util::TimeTracker;
use File::Spec;
use File::Basename;

our $TIME_HIRES_AVAILABLE_WARNED = 0;
our $HOSTNAME;
our %GLOBAL_USER_DEFINED_CSPECS = ();

our $CSPECS = 'cCdFHIlLmMnpPrRtTxX%';

BEGIN {
    # Check if we've got Sys::Hostname. If not, just punt.
    $HOSTNAME = "unknown.host";
    if(Log::Log4perl::Util::module_available("Sys::Hostname")) {
        require Sys::Hostname;
        $HOSTNAME = Sys::Hostname::hostname();
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
    
    my $self = {
        format                => undef,
        info_needed           => {},
        stack                 => [],
        CSPECS                => $CSPECS,
        dontCollapseArrayRefs => $options->{dontCollapseArrayRefs}{value},
        last_time             => undef,
        undef_column_value    => 
            (exists $options->{ undef_column_value } 
                ? $options->{ undef_column_value } 
                : "[undef]"),
    };

    $self->{timer} = Log::Log4perl::Util::TimeTracker->new(
        time_function => $options->{time_function}
    );

    if(exists $options->{ConversionPattern}->{value}) {
        $layout_string = $options->{ConversionPattern}->{value};
    }

    if(exists $options->{message_chomp_before_newline}) {
        $self->{message_chomp_before_newline} = 
          $options->{message_chomp_before_newline}->{value};
    } else {
        $self->{message_chomp_before_newline} = 1;
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

    # non-portable line breaks
    $layout_string =~ s/\\n/\n/g;
    $layout_string =~ s/\\r/\r/g;

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
    if($self->{message_chomp_before_newline} and $format =~ /%m%n/) {
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
    if($op eq "d") {
        if(defined $curlies) {
            $curlies = Log::Log4perl::DateFormat->new($curlies);
        } else {
            $curlies = Log::Log4perl::DateFormat->new("yyyy/MM/dd HH:mm:ss");
        }
    } elsif($op eq "m") {
        $curlies = $self->curlies_csv_parse($curlies);
    }

    push @{$self->{stack}}, [$op, $curlies];

    $self->{info_needed}->{$op}++;

    return "%${num}s";
}

###########################################
sub curlies_csv_parse {
###########################################
    my($self, $curlies) = @_;

    my $data = {};

    if(defined $curlies and length $curlies) {
        $curlies =~ s/\s//g;

        for my $field (split /,/, $curlies) {
            my($key, $value) = split /=/, $field;
            $data->{$key} = $value;
        }
    }

    return $data;
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

    my $caller_offset = Log::Log4perl::caller_depth_offset( $caller_level );

    if($self->{info_needed}->{L} or
       $self->{info_needed}->{F} or
       $self->{info_needed}->{C} or
       $self->{info_needed}->{l} or
       $self->{info_needed}->{M} or
       $self->{info_needed}->{T} or
       0
      ) {

        my ($package, $filename, $line, 
            $subroutine, $hasargs,
            $wantarray, $evaltext, $is_require, 
            $hints, $bitmask) = caller($caller_offset);

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
                my @callinfo = caller($caller_offset+$levels_up);

                if(_INTERNAL_DEBUG) {
                    callinfo_dump( $caller_offset, \@callinfo );
                }

                $subroutine = $callinfo[3];
                    # If we're inside an eval, go up one level further.
                if(defined $subroutine and
                   $subroutine eq "(eval)") {
                    print "Inside an eval, one up\n" if _INTERNAL_DEBUG;
                    $levels_up++;
                    redo;
                }
            }
            $subroutine = "main::" unless $subroutine;
            print "Subroutine is '$subroutine'\n" if _INTERNAL_DEBUG;
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

    my $current_time;

    if($self->{info_needed}->{r} or $self->{info_needed}->{R}) {
        if(!$TIME_HIRES_AVAILABLE_WARNED++ and 
           !$self->{timer}->hires_available()) {
            warn "Requested %r/%R pattern without installed Time::HiRes\n";
        }
        $current_time = [$self->{timer}->gettimeofday()];
    }

    if($self->{info_needed}->{r}) {
        $info{r} = $self->{timer}->milliseconds( $current_time );
    }
    if($self->{info_needed}->{R}) {
        $info{R} = $self->{timer}->delta_milliseconds( $current_time );
    }

        # Stack trace wanted?
    if($self->{info_needed}->{T}) {
        local $Carp::CarpLevel =
              $Carp::CarpLevel + $caller_offset;
        my $mess = Carp::longmess(); 
        chomp($mess);
        # $mess =~ s/(?:\A\s*at.*\n|^\s*Log::Log4perl.*\n|^\s*)//mg;
        $mess =~ s/(?:\A\s*at.*\n|^\s*)//mg;
        $mess =~ s/\n/, /g;
        $info{T} = $mess;
    }

        # As long as they're not implemented yet ..
    $info{t} = "N/A";

        # Iterate over all info fields on the stack
    for my $e (@{$self->{stack}}) {
        my($op, $curlies) = @$e;

        my $result;

        if(exists $self->{USER_DEFINED_CSPECS}->{$op}) {
            next unless $self->{info_needed}->{$op};
            $self->{curlies} = $curlies;
            $result = $self->{USER_DEFINED_CSPECS}->{$op}->($self, 
                              $message, $category, $priority, 
                              $caller_offset+1);
        } elsif(exists $info{$op}) {
            $result = $info{$op};
            if($curlies) {
                $result = $self->curly_action($op, $curlies, $info{$op},
                                              $self->{printformat}, \@results);
            } else {
                # just for %d
                if($op eq 'd') {
                    $result = $info{$op}->format($self->{timer}->gettimeofday());
                }
            }
        } else {
            warn "Format %'$op' not implemented (yet)";
            $result = "FORMAT-ERROR";
        }

        $result = $self->{undef_column_value} unless defined $result;
        push @results, $result;
    }

      # dbi appender needs that
    if( scalar @results == 1 and
        !defined $results[0] ) {
        return undef;
    }

    return (sprintf $self->{printformat}, @results);
}

##################################################
sub curly_action {
##################################################
    my($self, $ops, $curlies, $data, $printformat, $results) = @_;

    if($ops eq "c") {
        $data = shrink_category($data, $curlies);
    } elsif($ops eq "C") {
        $data = shrink_category($data, $curlies);
    } elsif($ops eq "X") {
        $data = Log::Log4perl::MDC->get($curlies);
    } elsif($ops eq "d") {
        $data = $curlies->format( $self->{timer}->gettimeofday() );
    } elsif($ops eq "M") {
        $data = shrink_category($data, $curlies);
    } elsif($ops eq "m") {
        if(exists $curlies->{chomp}) {
            chomp $data;
        }
        if(exists $curlies->{indent}) {
            if(defined $curlies->{indent}) {
                  # fixed indent
                $data =~ s/\n/ "\n" . (" " x $curlies->{indent})/ge;
            } else {
                  # indent on the lead-in
                no warnings; # trailing array elements are undefined
                my $indent = length sprintf $printformat, @$results;
                $data =~ s/\n/ "\n" . (" " x $indent)/ge;
            }
        }
    } elsif($ops eq "F") {
        my @parts = File::Spec->splitdir($data);
            # Limit it to max curlies entries
        if(@parts > $curlies) {
            splice @parts, 0, @parts - $curlies;
        }
        $data = File::Spec->catfile(@parts);
    } elsif($ops eq "p") {
        $data = substr $data, 0, $curlies;
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

###########################################
sub callinfo_dump {
###########################################
    my($level, $info) = @_;

    my @called_by = caller(0);

    # Just for internal debugging
    $called_by[1] = basename $called_by[1];
    print "caller($level) at $called_by[1]-$called_by[2] returned ";

    my @by_idx;

    # $info->[1] = basename $info->[1] if defined $info->[1];

    my $i = 0;
    for my $field (qw(package filename line subroutine hasargs
                      wantarray evaltext is_require hints bitmask)) {
        $by_idx[$i] = $field;
        $i++;
    }

    $i = 0;
    for my $value (@$info) {
        my $field = $by_idx[ $i ];
        print "$field=", 
              (defined $info->[$i] ? $info->[$i] : "[undef]"),
              " ";
        $i++;
    }

    print "\n";
}

1;

__END__

=encoding utf8

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
    %d{...} Current date in customized format (see below)
    %F File where the logging event occurred
    %H Hostname (if Sys::Hostname is available)
    %l Fully qualified name of the calling method followed by the
       callers source the file name and line number between 
       parentheses.
    %L Line number within the file where the log statement was issued
    %m The message to be logged
    %m{chomp} Log message, stripped off a trailing newline
    %m{indent} Log message, multi-lines indented so they line up with first
    %m{indent=n} Log message, multi-lines indented by n spaces
    %M Method or function where the logging request was issued
    %n Newline (OS-independent)
    %p Priority/level of the logging event (%p{1} shows the first letter)
    %P pid of the current process
    %r Number of milliseconds elapsed from program start to logging 
       event
    %R Number of milliseconds elapsed from last logging event to
       current logging event 
    %T A stack trace of functions called
    %x The topmost NDC (see below)
    %X{key} The entry 'key' of the MDC (see below)
    %% A literal percent (%) sign

NDC and MDC are explained in L<Log::Log4perl/"Nested Diagnostic Context (NDC)">
and L<Log::Log4perl/"Mapped Diagnostic Context (MDC)">.

The granularity of time values is milliseconds if Time::HiRes is available.
If not, only full seconds are used.

Every once in a while, someone uses the "%m%n" pattern and
additionally provides an extra newline in the log message (e.g.
C<-E<gt>log("message\n")>. To avoid printing an extra newline in
this case, the PatternLayout will chomp the message, printing only
one newline. This option can be controlled by PatternLayout's
C<message_chomp_before_newline> option. See L<Advanced options>
for details.

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

    %M     Display fully qualified method/function name
    %M{1}  Just display method name (foo)
    %M{2}  Display method name and last path component (main::foo)

In this way, you're able to shrink the displayed category or
limit file/path components to save space in your logs.

=head2 Fine-tune the date

If you're not happy with the default %d format for the date which 
looks like

    yyyy/MM/DD HH:mm:ss

(which is slightly different from Log4j which uses C<yyyy-MM-dd HH:mm:ss,SSS>)
you're free to fine-tune it in order to display only certain characteristics
of a date, according to the SimpleDateFormat in the Java World
(http://docs.oracle.com/javase/8/docs/api/java/text/SimpleDateFormat.html):

    %d{HH:mm}     "23:45" -- Just display hours and minutes
    %d{yy, EEEE}  "02, Monday" -- Just display two-digit year 
                                  and spelled-out weekday
    %d{e}         "1473741760" -- Epoch seconds
    %d{h a}       "12 PM"      -- Hour and am/pm marker
    ... and many more

For an exhaustive list of all supported date features, look at
L<Log::Log4perl::DateFormat>.

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

When the log message is being put together, your anonymous sub 
will be called with these arguments:

    ($layout, $message, $category, $priority, $caller_level);
    
    layout: the PatternLayout object that called it
    message: the logging message (%m)
    category: e.g. groceries.beverages.adult.beer.schlitz
    priority: e.g. DEBUG|WARN|INFO|ERROR|FATAL
    caller_level: how many levels back up the call stack you have 
        to go to find the caller

Please note that the subroutines you're defining in this way are going
to be run in the C<main> namespace, so be sure to fully qualify functions
and variables if they're located in different packages. I<Also make sure
these subroutines aren't using Log4perl, otherwise Log4perl will enter 
an infinite recursion.>

With Log4perl 1.20 and better, cspecs can be written with parameters in
curly braces. Writing something like

    log4perl.appender.Screen.layout.ConversionPattern = %U{user} %U{id} %m%n

will cause the cspec function defined for %U to be called twice, once
with the parameter 'user' and then again with the parameter 'id', 
and the placeholders in the cspec string will be replaced with
the respective return values.

The parameter value is available in the 'curlies' entry of the first
parameter passed to the subroutine (the layout object reference). 
So, if you wanted to map %U{xxx} to entries in the POE session hash, 
you'd write something like:

   log4perl.PatternLayout.cspec.U = sub { \
     POE::Kernel->get_active_session->get_heap()->{ $_[0]->{curlies} } }
                                          
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
since the epoch or as an array, carrying seconds and 
microseconds, just like C<Time::HiRes::gettimeofday> does.

=item message_chomp_before_newline

If a layout contains the pattern "%m%n" and the message ends with a newline,
PatternLayout will chomp the message, to prevent printing two newlines. 
If this is not desired, and you want two newlines in this case, 
the feature can be turned off by setting the
C<message_chomp_before_newline> option to a false value:

  my $layout = Log::Log4perl::Layout::PatternLayout->new(
      { message_chomp_before_newline => 0
      }, 
      "%d (%F:%L)> %m%n");

In a Log4perl configuration file, the feature can be turned off like this:

    log4perl.appender.App.layout   = PatternLayout
    log4perl.appender.App.layout.ConversionPattern = %d %m%n
      # Yes, I want two newlines
    log4perl.appender.App.layout.message_chomp_before_newline = 0

=back

=head2 Getting rid of newlines

If your code contains logging statements like 

      # WRONG, don't do that!
    $logger->debug("Some message\n");

then it's usually best to strip the newlines from these calls. As explained
in L<Log::Log4perl/Logging newlines>, logging statements should never contain
newlines, but rely on appender layouts to add necessary newlines instead.

If changing the code is not an option, use the special PatternLayout 
placeholder %m{chomp} to refer to the message excluding a trailing 
newline:

    log4perl.appender.App.layout.ConversionPattern = %d %m{chomp}%n

This will add a single newline to every message, regardless if it
complies with the Log4perl newline guidelines or not (thanks to 
Tim Bunce for this idea).

=head2 Multi Lines

If a log message consists of several lines, like

    $logger->debug("line1\nline2\nline3");

then by default, they get logged like this (assuming the the layout is
set to "%d>%m%n"):

      # layout %d>%m%n
    2014/07/27 12:46:16>line1
    line2
    line3

If you'd rather have the messages aligned like

      # layout %d>%m{indent}%n
    2014/07/27 12:46:16>line1
                        line2
                        line3

then use the C<%m{indent}> option for the %m specifier. This option
can also take a fixed value, as in C<%m{indent=2}>, which indents
subsequent lines by two spaces:

      # layout %d>%m{indent=2}%n
    2014/07/27 12:46:16>line1
      line2
      line3

Note that you can still add the C<chomp> option for the C<%m> specifier
in this case (see above what it does), simply add it after a 
separating comma, like in C<%m{indent=2,chomp}>.

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

