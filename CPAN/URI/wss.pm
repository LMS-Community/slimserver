package URI::wss;

use strict;
use warnings;

# ABSTRACT: Secure WebSocket support for URI package
our $VERSION = '0.03'; # VERSION


use base qw( URI::ws );


sub default_port { 443 }


sub secure { 1 }

1;

__END__

=pod

=head1 NAME

URI::wss - Secure WebSocket support for URI package

=head1 VERSION

version 0.03

=head1 SYNOPSIS

 use URI;
 my $uri = URI->new('wss://localhost:3000/foo');

=head1 DESCRIPTION

After this module is installed, the URI package provides the same set
of methods for secure WebSocket URIs as it does for insecure WebSocket
URIs.  For insecure (unencrypted) WebSockets, see L<URI::ws>.

=head1 METHODS

=head2 URI::wss->default_port

Returns the default port (443)

=head2 $uri->secure

Returns true.

=head1 SEE ALSO

L<URI>, L<URI::ws>

=cut

=head1 AUTHOR

Graham Ollis <plicease@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
