#!/usr/bin/perl

package Log::Log4perl::Layout::PatternLayout::Multiline;
use base qw(Log::Log4perl::Layout::PatternLayout);

###########################################
sub render {
###########################################
    my($self, $message, $category, $priority, $caller_level) = @_;

    my @messages = split /\r?\n/, $message;

    $caller_level = 0 unless defined $caller_level;

    my $result = '';

    for my $msg ( @messages ) {
        $result .= $self->SUPER::render(
            $msg, $category, $priority, $caller_level + 1
        );
    }
    return $result;
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Layout::PatternLayout::Multiline

=head1 SYNOPSIS

    use Log::Log4perl::Layout::PatternLayout::Multiline;

    my $layout = Log::Log4perl::Layout::PatternLayout::Multiline->new(
        "%d (%F:%L)> %m");

=head1 DESCRIPTION

C<Log::Log4perl::Layout::PatternLayout::Multiline> is a subclass
of Log4perl's PatternLayout and is helpful if you send multiline
messages to your appenders which appear as

    2007/04/04 23:59:01 This is
    a message with
    multiple lines

and you want them to appear as 

    2007/04/04 23:59:01 This is
    2007/04/04 23:59:01 a message with
    2007/04/04 23:59:01 multiple lines

instead. This layout class simply splits up the incoming message into
several chunks split by line breaks and renders them with PatternLayout
just as if it had arrived in separate chunks in the first place.

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

