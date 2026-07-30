##################################################
package Log::Log4perl::NDC;
##################################################

use 5.006;
use strict;
use warnings;

our @NDC_STACK = ();
our $MAX_SIZE  = 5;

###########################################
sub get {
###########################################
    if(@NDC_STACK) {
        # Return elements blank separated
        return join " ", @NDC_STACK;
    } else {
        return "[undef]";
    }
}

###########################################
sub pop {
###########################################
    if(@NDC_STACK) {
        return pop @NDC_STACK;
    } else {
        return undef;
    }
}

###########################################
sub push {
###########################################
    my($self, $text) = @_;

    unless(defined $text) {
        # Somebody called us via Log::Log4perl::NDC::push("blah") ?
        $text = $self;
    }

    if(@NDC_STACK >= $MAX_SIZE) {
        CORE::pop(@NDC_STACK);
    }

    return push @NDC_STACK, $text;
}

###########################################
sub remove {
###########################################
    @NDC_STACK = ();
}

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::NDC - Nested Diagnostic Context

=head1 DESCRIPTION

Log::Log4perl allows loggers to maintain global thread-specific data, 
called the Nested Diagnostic Context (NDC).

At some point, the application might decide to push a piece of
data onto the NDC stack, which other parts of the application might 
want to reuse. For example, at the beginning of a web request in a server,
the application might decide to push the IP address of the client
onto the stack to provide it for other loggers down the road without
having to pass the data from function to function.

The Log::Log4perl::Layout::PatternLayout class even provides the handy
C<%x> placeholder which is replaced by the blank-separated list
of elements currently on the stack.

This module maintains a simple stack which you can push data on to, query
what's on top, pop it off again or delete the entire stack.

Its purpose is to provide a thread-specific context which all 
Log::Log4perl loggers can refer to without the application having to
pass around the context data between its functions.

Since in 5.8.0 perl's threads don't share data only upon request,
global data is by definition thread-specific.

=over 4

=item Log::Log4perl::NDC->push($text);

Push an item onto the stack. If the stack grows beyond the defined
limit (C<$Log::Log4perl::NDC::MAX_SIZE>), just the topmost element
will be replated.

This is typically done when a context is entered.

=item Log::Log4perl::NDC->pop();

Discard the upmost element of the stack. This is typically done when
a context is left.

=item my $text = Log::Log4perl::NDC->get();

Retrieve the content of the stack as a string of blank-separated values
without disrupting the stack structure. Typically done by C<%x>.
If the stack is empty the value C<"[undef]"> is being returned.

=item Log::Log4perl::NDC->remove();

Reset the stack, remove all items.

=back

Please note that all of the methods above are class methods, there's no
instances of this class.

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

