##################################################
package Log::Log4perl::Filter::LevelMatch;
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

    my $self = { LevelToMatch  => '',
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

     if($self->{LevelToMatch} eq $p{log4p_level}) {
         print "Levels match\n" if _INTERNAL_DEBUG;
         return $self->{AcceptOnMatch};
     } else {
         print "Levels don't match\n" if _INTERNAL_DEBUG;
         return !$self->{AcceptOnMatch};
     }
}

1;

__END__

=head1 NAME

Log::Log4perl::Filter::LevelMatch - Filter to match the log level exactly

=head1 SYNOPSIS

    log4perl.filter.Match1               = Log::Log4perl::Filter::LevelMatch
    log4perl.filter.Match1.LevelToMatch  = ERROR
    log4perl.filter.Match1.AcceptOnMatch = true

=head1 DESCRIPTION

This Log4perl custom filter checks if the currently submitted message
matches a predefined priority, as set in C<LevelToMatch>.
The additional parameter C<AcceptOnMatch> defines if the filter
is supposed to pass or block the message (C<true> or C<false>)
on a match.

=head1 SEE ALSO

L<Log::Log4perl::Filter>,
L<Log::Log4perl::Filter::LevelRange>,
L<Log::Log4perl::Filter::StringRange>,
L<Log::Log4perl::Filter::Boolean>

=head1 AUTHOR

Mike Schilli, E<lt>log4perl@perlmeister.comE<gt>, 2003

=cut
