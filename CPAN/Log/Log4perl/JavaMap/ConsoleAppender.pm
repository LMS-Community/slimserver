package Log::Log4perl::JavaMap::ConsoleAppender;

use Carp;
use strict;
use Log::Dispatch::Screen;


sub new {
    my ($class, $appender_name, $data) = @_;
    my $stderr;

    if (my $t = $data->{Target}{value}) {
        if ($t eq 'System.out') {
            $stderr = 0;
        }elsif ($t eq 'System.err') {
            $stderr = 1;
        }else{
            die "ERROR: illegal value '$t' for $data->{value}.Target' in appender $appender_name\n";
        }
    }elsif (defined $data->{stderr}{value}){
        $stderr = $data->{stderr}{value};
    }else{
        $stderr = 0;
    }

    return Log::Log4perl::Appender->new("Log::Dispatch::Screen",
        name   => $appender_name,
        stderr => $stderr );
}


1;


=encoding utf8

=head1 NAME

Log::Log4perl::JavaMap::ConsoleAppender - wraps Log::Dispatch::Screen

=head1 SYNOPSIS


=head1 DESCRIPTION

Possible config properties for log4j ConsoleAppender are 

    Target (System.out, System.err, default is System.out)

Possible config properties for Log::Dispatch::Screen are

    stderr (0 or 1)

=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

Log::Dispatch::Screen

=cut 

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

