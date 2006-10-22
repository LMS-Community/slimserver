##################################################
package Log::Log4perl::Appender::ScreenColoredLevels;
##################################################
our @ISA = qw(Log::Log4perl::Appender);

use warnings;
use strict;

use Term::ANSIColor qw(:constants);
use Log::Log4perl::Level;

##################################################
sub new {
##################################################
    my($class, @options) = @_;

    my $self = {
        name   => "unknown name",
        stderr => 1,
        @options,
    };

    bless $self, $class;
}
    
##################################################
sub log {
##################################################
    my($self, %params) = @_;

    $params{message} = color($params{log4p_level}, $params{message});
    
    if($self->{stderr}) {
        print STDERR $params{message};
    } else {
        print $params{message};
    }
}

##################################################
sub color {
##################################################
    my($level, $message) = @_;

    if(0) {
    } elsif($level eq "DEBUG") {
        return $message;
    } elsif($level eq "INFO") {
        return GREEN . $message . RESET;
    } elsif($level eq "WARN") {
        return BLUE . $message . RESET;
    } elsif($level eq "ERROR") {
        return MAGENTA . $message . RESET;
    } elsif($level eq "FATAL") {
        return RED . $message . RESET;
    } else {
        return $message;
    }
}

1;

__END__

=head1 NAME

Log::Log4perl::Appender::ScreenColoredLevel - Colorize messages according to level

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

The color scheme is

=over 4

=item Debug

Black

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
if set to a true value, the appender will log to STDERR. If C<stderr>
is set to a false value, it will log to STDOUT. The default setting
for C<stderr> is 1, so messages will be logged to STDERR by default.

=head1 AUTHOR

Mike Schilli <log4perl@perlmeister.com>, 2004

=cut
