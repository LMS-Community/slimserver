##################################################
package Log::Log4perl::Filter::LevelRange;
##################################################

use 5.006;

use strict;
use warnings;

use Log::Log4perl::Level;
use Log::Log4perl::Config;
use Log::Log4perl::Util qw( params_check );

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
     
    params_check( $self,
                  [ qw( LevelMin LevelMax ) ], 
                  [ qw( name AcceptOnMatch ) ] 
                );

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

=encoding utf8

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

C<LevelMin> defaults to C<DEBUG>, and C<LevelMax> to C<FATAL>.

The additional parameter C<AcceptOnMatch> defines if the filter
is supposed to pass or block the message (C<true> or C<false>).

=head1 SEE ALSO

L<Log::Log4perl::Filter>,
L<Log::Log4perl::Filter::Boolean>,
L<Log::Log4perl::Filter::LevelMatch>,
L<Log::Log4perl::Filter::MDC>,
L<Log::Log4perl::Filter::StringMatch>

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

