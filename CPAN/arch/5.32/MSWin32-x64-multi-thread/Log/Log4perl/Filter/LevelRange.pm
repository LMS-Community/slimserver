##################################################
package Log::Log4perl::Filter::LevelRange;
##################################################

use 5.006;

use strict;
use warnings;

use Log::Log4perl::Level;
use Log::Log4perl::Config;

use constant _INTERNAL_DEBUG => 0;

use base "Log::Log4perl::Filter";

##################################################
sub new {
##################################################
    my ($class, %options) = @_;

    my $self = { LevelMin      => 'DEBUG',
                 LevelMax      => 'FATAL',
                 AcceptOnMatch => 1,
                 %options,
               };
     
    $self->{AcceptOnMatch} = Log::Log4perl::Config::boolean_to_perlish(
                                                $self->{AcceptOnMatch});

    bless $self, $class;

    return $self;
}

##################################################
sub ok {
##################################################
     my ($self, %p) = @_;

     if(Log::Log4perl::Level::to_priority($self->{LevelMin}) <= 
        Log::Log4perl::Level::to_priority($p{log4p_level}) and
        Log::Log4perl::Level::to_priority($self->{LevelMax}) >= 
        Log::Log4perl::Level::to_priority($p{log4p_level})) {
         return $self->{AcceptOnMatch};
     } else {
         return ! $self->{AcceptOnMatch};
     }
}

1;

__END__

=head1 NAME

Log::Log4perl::Filter::LevelRange - Filter for a range of log levels

=head1 SYNOPSIS

    log4perl.filter.Match1               = Log::Log4perl::Filter::LevelRange
    log4perl.filter.Match1.LevelMin      = INFO
    log4perl.filter.Match1.LevelMax      = ERROR
    log4perl.filter.Match1.AcceptOnMatch = true

=head1 DESCRIPTION

This Log4perl custom filter checks if the current message
has a priority matching a predefined range. 
The C<LevelMin> and C<LevelMax> parameters define the levels
(choose from C<DEBUG>, C<INFO>, C<WARN>, C<ERROR>, C<FATAL>) marking
the window of allowed messages priorities.
The additional parameter C<AcceptOnMatch> defines if the filter
is supposed to pass or block the message (C<true> or C<false>).

=head1 SEE ALSO

L<Log::Log4perl::Filter>,
L<Log::Log4perl::Filter::LevelMatch>,
L<Log::Log4perl::Filter::StringRange>,
L<Log::Log4perl::Filter::Boolean>

=head1 AUTHOR

Mike Schilli, E<lt>log4perl@perlmeister.comE<gt>, 2003

=cut
