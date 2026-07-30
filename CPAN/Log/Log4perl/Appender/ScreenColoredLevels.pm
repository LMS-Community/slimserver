##################################################
package Log::Log4perl::Appender::ScreenColoredLevels;
##################################################
use Log::Log4perl::Appender::Screen;
our @ISA = qw(Log::Log4perl::Appender::Screen);

use warnings;
use strict;

use Term::ANSIColor qw();
use Log::Log4perl::Level;

BEGIN {
    $Term::ANSIColor::EACHLINE="\n";
}

##################################################
sub new {
##################################################
    my($class, %options) = @_;

    my %specific_options = ( color => {} );

    for my $option ( keys %specific_options ) {
        $specific_options{ $option } = delete $options{ $option } if
            exists $options{ $option };
    }

    my $self = $class->SUPER::new( %options );
    @$self{ keys %specific_options } = values %specific_options;
    bless $self, __PACKAGE__; # rebless

      # also accept lower/mixed case levels in config
    for my $level ( keys %{ $self->{color} } ) {
        my $uclevel = uc($level);
        $self->{color}->{$uclevel} = $self->{color}->{$level};
    }

    my %default_colors = (
        TRACE   => 'yellow',
        DEBUG   => '',
        INFO    => 'green',
        WARN    => 'blue',
        ERROR   => 'magenta',
        FATAL   => 'red',
    );
    for my $level ( keys %default_colors ) {
        if ( ! exists $self->{ 'color' }->{ $level } ) {
            $self->{ 'color' }->{ $level } = $default_colors{ $level };
        }
    }

    bless $self, $class;
}
    
##################################################
sub log {
##################################################
    my($self, %params) = @_;

    my $msg = $params{ 'message' };

    if ( my $color = $self->{ 'color' }->{ $params{ 'log4p_level' } } ) {
        $msg = Term::ANSIColor::colored( $msg, $color );
    }

    my $fh = \*STDOUT;
    if (ref $self->{stderr}) {
        $fh = \*STDERR if $self->{stderr}{ $params{'log4p_level'} }
                            || $self->{stderr}{ lc $params{'log4p_level'} };
    } elsif ($self->{stderr}) {
        $fh = \*STDERR;
    }

    print $fh $msg;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Appender::ScreenColoredLevels - Colorize messages according to level

=head1 SYNOPSIS

    use Log::Log4perl qw(:easy);

    Log::Log4perl->init(\ <<'EOT');
      log4perl.category = DEBUG, Screen
      log4perl.appender.Screen = \
          Log::Log4perl::Appender::ScreenColoredLevels
      log4perl.appender.Screen.layout = \
          Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Screen.layout.ConversionPattern = \
          %d %F{1} %L> %m %n
    EOT

      # Appears black
    DEBUG "Debug Message";

      # Appears green
    INFO  "Info Message";

      # Appears blue
    WARN  "Warn Message";

      # Appears magenta
    ERROR "Error Message";

      # Appears red
    FATAL "Fatal Message";

=head1 DESCRIPTION

This appender acts like Log::Log4perl::Appender::Screen, except that
it colorizes its output, based on the priority of the message sent.

You can configure the colors and attributes used for the different
levels, by specifying them in your configuration:

    log4perl.appender.Screen.color.TRACE=cyan
    log4perl.appender.Screen.color.DEBUG=bold blue

You can also specify nothing, to indicate that level should not have
coloring applied, which means the text will be whatever the default
color for your terminal is.  This is the default for debug messages.

    log4perl.appender.Screen.color.DEBUG=

You can use any attribute supported by L<Term::ANSIColor> as a configuration
option.

    log4perl.appender.Screen.color.FATAL=\
        bold underline blink red on_white

The commonly used colors and attributes are:

=over 4

=item attributes

BOLD, DARK, UNDERLINE, UNDERSCORE, BLINK

=item colors

BLACK, RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE

=item background colors

ON_BLACK, ON_RED, ON_GREEN, ON_YELLOW, ON_BLUE, ON_MAGENTA, ON_CYAN, ON_WHITE

=back

See L<Term::ANSIColor> for a complete list, and information on which are
supported by various common terminal emulators.

The default values for these options are:

=over 4

=item Trace

Yellow

=item Debug

None (whatever the terminal default is)

=item Info

Green

=item Warn

Blue

=item Error

Magenta

=item Fatal

Red

=back

The constructor C<new()> takes an optional parameter C<stderr>,
if set to a true value, the appender will log all levels to STDERR.
If C<stderr> is set to a false value, it will log all levels to
STDOUT. Otherwise, C<stderr> may be set to a hash, with a key for
each C<log4p_level> and a truthy value to dynamically use stderr.
The default setting for C<stderr> is 1, so all messages will be logged
to STDERR by default.

    # All messages/levels to STDERR
    my $app = Log::Log4perl::Appender::Screen->new(
        stderr  => 1,
    );

    # Only ERROR and FATAL to STDERR (case-sensitive)
    my $app = Log::Log4perl::Appender::Screen->new(
        stderr  => { ERROR => 1, FATAL => 1},
    );

The constructor can also take an optional
parameter C<color>, whose value is a  hashref of color configuration
options, any levels that are not included in the hashref will be set
to their default values.

=head2 Using ScreenColoredLevels on Windows

Note that if you're using this appender on Windows, you need to fetch
Win32::Console::ANSI from CPAN and add

    use Win32::Console::ANSI;

to your script.

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

