##################################################
package Log::Log4perl::Filter::Boolean;
##################################################

use 5.006;

use strict;
use warnings;

use Log::Log4perl::Level;
use Log::Log4perl::Config;

use constant _INTERNAL_DEBUG => 0;

use base qw(Log::Log4perl::Filter);

##################################################
sub new {
##################################################
    my ($class, %options) = @_;

    my $self = { params => {},
                 %options,
               };
     
    bless $self, $class;
     
    print "Compiling '$options{logic}'\n" if _INTERNAL_DEBUG;

        # Set up meta-decider for later
    $self->compile_logic($options{logic});

    return $self;
}

##################################################
sub ok {
##################################################
     my ($self, %p) = @_;

     return $self->eval_logic(\%p);
}

##################################################
sub compile_logic {
##################################################
    my ($self, $logic) = @_;

       # Extract Filter placeholders in logic as defined
       # in configuration file.
    while($logic =~ /([\w_-]+)/g) {
            # Get the corresponding filter object
        my $filter = Log::Log4perl::Filter::by_name($1);
        die "Filter $filter required by Boolean filter, but not defined" 
            unless $filter;

        $self->{params}->{$1} = $filter;
    }

        # Fabricate a parameter list: A1/A2/A3 => $A1, $A2, $A3
    my $plist = join ', ', map { '$' . $_ } keys %{$self->{params}};

        # Replace all the (dollar-less) placeholders in the code 
        # by scalars (basically just put dollars in front of them)
    $logic =~ s/([\w_-]+)/\$$1/g;

        # Set up the meta decider, which transforms the config file
        # logic into compiled perl code
    my $func = <<EOT;
        sub { 
            my($plist) = \@_;
            $logic;
        }
EOT

    print "func=$func\n" if _INTERNAL_DEBUG;

    my $eval_func = eval $func;

    if(! $eval_func) {
        die "Syntax error in Boolean filter logic: $eval_func";
    }

    $self->{eval_func} = $eval_func;
}

##################################################
sub eval_logic {
##################################################
    my($self, $p) = @_;

    my @plist = ();

        # Eval the results of all filters referenced
        # in the code (although the order of keys is
        # not predictable, it is consistent :)
    for my $param (keys %{$self->{params}}) {
            # Call ok() and map the result to 1 or 0
        print "Calling filter $param\n" if _INTERNAL_DEBUG;
        push @plist, ($self->{params}->{$param}->ok(%$p) ? 1 : 0);
    }

        # Now pipe the parameters into the canned function,
        # have it evaluate the logic and return the final
        # decision
    print "Passing in (", join(', ', @plist), ")\n" if _INTERNAL_DEBUG;
    return $self->{eval_func}->(@plist);
}

1;

__END__

=head1 NAME

Log::Log4perl::Filter::Boolean - Special filter to combine the results of others

=head1 SYNOPSIS

    log4perl.logger = WARN, AppWarn, AppError

    log4perl.filter.Match1       = sub { /let this through/ }
    log4perl.filter.Match2       = sub { /and that, too/ }
    log4perl.filter.MyBoolean       = Log::Log4perl::Filter::Boolean
    log4perl.filter.MyBoolean.logic = Match1 || Match2

    log4perl.appender.Screen        = Log::Dispatch::Screen
    log4perl.appender.Screen.Filter = MyBoolean
    log4perl.appender.Screen.layout = Log::Log4perl::Layout::SimpleLayout

=head1 DESCRIPTION

Sometimes, it's useful to combine the output of various filters to
arrive at a log/no log decision. While Log4j, Log4perl's mother ship,
chose to implement this feature as a filter chain, similar to Linux' IP chains,
Log4perl tries a different approach. 

Typically, filter results will not need to be passed along in chains but 
combined in a programmatic manner using boolean logic. "Log if
this filter says 'yes' and that filter says 'no'" 
is a fairly common requirement but hard to implement as a chain.

C<Log::Log4perl::Filter::Boolean> is a special predefined custom filter
for Log4perl which combines the results of other custom filters 
in arbitrary ways, using boolean expressions:

    log4perl.logger = WARN, AppWarn, AppError

    log4perl.filter.Match1       = sub { /let this through/ }
    log4perl.filter.Match2       = sub { /and that, too/ }
    log4perl.filter.MyBoolean       = Log::Log4perl::Filter::Boolean
    log4perl.filter.MyBoolean.logic = Match1 || Match2

    log4perl.appender.Screen        = Log::Dispatch::Screen
    log4perl.appender.Screen.Filter = MyBoolean
    log4perl.appender.Screen.layout = Log::Log4perl::Layout::SimpleLayout

C<Log::Log4perl::Filter::Boolean>'s boolean expressions allow for combining
different appenders by name using AND (&& or &), OR (|| or |) and NOT (!) as
logical expressions. Parentheses are used for grouping. Precedence follows
standard Perl. Here's a bunch of examples:

    Match1 && !Match2            # Match1 and not Match2
    !(Match1 || Match2)          # Neither Match1 nor Match2
    (Match1 && Match2) || Match3 # Both Match1 and Match2 or Match3

=head1 SEE ALSO

L<Log::Log4perl::Filter>,
L<Log::Log4perl::Filter::LevelMatch>,
L<Log::Log4perl::Filter::LevelRange>,
L<Log::Log4perl::Filter::StringRange>

=head1 AUTHOR

Mike Schilli, E<lt>log4perl@perlmeister.comE<gt>, 2003

=cut
