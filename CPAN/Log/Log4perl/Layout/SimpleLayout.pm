##################################################
package Log::Log4perl::Layout::SimpleLayout;
##################################################
# as documented in
# http://jakarta.apache.org/log4j/docs/api/org/apache/log4j/SimpleLayout.html
##################################################

use 5.006;
use strict;
use warnings;
use Log::Log4perl::Level;

no strict qw(refs);
use base qw(Log::Log4perl::Layout);

##################################################
sub new {
##################################################
    my $class = shift;
    $class = ref ($class) || $class;

    my $self = {
        format      => undef,
        info_needed => {},
        stack       => [],
    };

    bless $self, $class;

    return $self;
}

##################################################
sub render {
##################################################
    my($self, $message, $category, $priority, $caller_level) = @_;

    return "$priority - $message\n";
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Layout::SimpleLayout - Simple Layout

=head1 SYNOPSIS

  use Log::Log4perl::Layout::SimpleLayout;
  my $layout = Log::Log4perl::Layout::SimpleLayout->new();

=head1 DESCRIPTION

This class implements the C<log4j> simple layout format -- it basically 
just prints the message priority and the message, that's all.
Check 
http://jakarta.apache.org/log4j/docs/api/org/apache/log4j/SimpleLayout.html
for details.

=head1 SEE ALSO

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

