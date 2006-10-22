##################################################
package Log::Log4perl::Appender::Screen;
##################################################

our @ISA = qw(Log::Log4perl::Appender);

use warnings;
use strict;

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

    if($self->{stderr}) {
        print STDERR $params{message};
    } else {
        print $params{message};
    }
}

1;

__END__

=head1 NAME

Log::Log4perl::Appender::Screen - Log to STDOUT/STDERR

=head1 SYNOPSIS

    use Log::Log4perl::Appender::Screen;

    my $app = Log::Log4perl::Appender::Screen->new(
      stderr    => 0,
    );

    $file->log(message => "Log me\n");

=head1 DESCRIPTION

This is a simple appender for writing to STDOUT or STDERR.

The constructor C<new()> take an optional parameter C<stderr>,
if set to a true value, the appender will log to STDERR. If C<stderr>
is set to a false value, it will log to STDOUT. The default setting
for C<stderr> is 1, so messages will be logged to STDERR by default.

Design and implementation of this module has been greatly inspired by
Dave Rolsky's C<Log::Dispatch> appender framework.

=head1 AUTHOR

Mike Schilli <log4perl@perlmeister.com>, 2003

=cut
