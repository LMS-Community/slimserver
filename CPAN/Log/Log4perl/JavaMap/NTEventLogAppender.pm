package Log::Log4perl::JavaMap::NTEventLogAppender;

use Carp;
use strict;



sub new {
    my ($class, $appender_name, $data) = @_;
    my $stderr;

    my ($source,   #        
        );

    if (defined $data->{Source}{value}) {
        $source = $data->{Source}{value}
    }elsif (defined $data->{source}{value}){
        $source = $data->{source}{value};
    }else{
        $source = 'user';
    }

    
    return Log::Log4perl::Appender->new("Log::Dispatch::Win32EventLog",
        name      => $appender_name,
        source    => $source,
        min_level => 'debug',
    );
}

1;

=encoding utf8

=head1 NAME

Log::Log4perl::JavaMap::NTEventLogAppender - wraps Log::Dispatch::Win32EventLog


=head1 DESCRIPTION

This maps log4j's NTEventLogAppender to Log::Dispatch::Win32EventLog

Possible config properties for log4j NTEventLogAppender are 

    Source

Possible config properties for Log::Dispatch::Win32EventLog are

    source

Boy, that was hard.

=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

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

