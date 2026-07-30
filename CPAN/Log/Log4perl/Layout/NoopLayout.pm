##################################################
package Log::Log4perl::Layout::NoopLayout;
##################################################


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
    #my($self, $message, $category, $priority, $caller_level) = @_;
    return $_[1];;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Layout::NoopLayout - Pass-thru Layout

=head1 SYNOPSIS

  use Log::Log4perl::Layout::NoopLayout;
  my $layout = Log::Log4perl::Layout::NoopLayout->new();

=head1 DESCRIPTION

This is a no-op layout, returns the logging message unaltered,
useful for implementing the DBI logger.

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

