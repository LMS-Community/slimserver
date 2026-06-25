##################################################
package Log::Log4perl::Filter::LevelMatch;
##################################################

use 5.006;

use strict;
use warnings;

use Log::Log4perl::Level;
use Log::Log4perl::Config;
use Log::Log4perl::Util qw( params_check );

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
     
    params_check( $self,
                  [ qw( LevelToMatch ) ], 
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

=encoding utf8

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
L<Log::Log4perl::Filter::Boolean>,
L<Log::Log4perl::Filter::LevelRange>,
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

