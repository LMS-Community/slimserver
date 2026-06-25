package Log::Log4perl::JavaMap::TestBuffer;

use Carp;
use strict;
use Log::Log4perl::Appender::TestBuffer;

use constant _INTERNAL_DEBUG => 0;

sub new {
    my ($class, $appender_name, $data) = @_;
    my $stderr;

    return Log::Log4perl::Appender->new("Log::Log4perl::Appender::TestBuffer",
                                        name => $appender_name);
}

1;

=encoding utf8

=head1 NAME

Log::Log4perl::JavaMap::TestBuffer - wraps Log::Log4perl::Appender::TestBuffer

=head1 SYNOPSIS

=head1 DESCRIPTION

Just for testing the Java mapping.

=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

Log::Dispatch::Screen

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

