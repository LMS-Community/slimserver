##################################################
package Log::Log4perl::Appender::TestFileCreeper;
##################################################
# Test appender, intentionally slow. It writes 
# out one byte at a time to provoke sync errors.
# Don't use it, unless for testing.
##################################################

use warnings;
use strict;

use Log::Log4perl::Appender::File;

our @ISA = qw(Log::Log4perl::Appender::File);

##################################################
sub log {
##################################################
    my($self, %params) = @_;

    my $fh = $self->{fh};

    for (split //, $params{message}) {
        print $fh $_;
        my $oldfh = select $self->{fh}; 
        $| = 1; 
        select $oldfh;
    }
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Appender::TestFileCreeper - Intentionally slow test appender

=head1 SYNOPSIS

    use Log::Log4perl::Appender::TestFileCreeper;

    my $app = Log::Log4perl::Appender::TestFileCreeper->new(
      filename  => 'file.log',
      mode      => 'append',
    );

    $file->log(message => "Log me\n");

=head1 DESCRIPTION

This is a test appender, and it is intentionally slow. It writes 
out one byte at a time to provoke sync errors. Don't use it, unless 
for testing.

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

