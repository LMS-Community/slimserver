package URI::ws;

use strict;
use warnings;

# ABSTRACT: WebSocket support for URI package
our $VERSION = '0.03'; # VERSION


use base qw( URI::_server );


sub default_port { 80 }

1;

__END__

=pod

=head1 NAME

URI::ws - WebSocket support for URI package

=head1 VERSION

version 0.03

=head1 SYNOPSIS

 use URI;
 my $uri = URI->new('ws://localhost:3000/foo');

=head1 DESCRIPTION

After this module is installed, the URI package provides the same set
of methods for WebSocket URIs as it does for HTTP ones.  For secure
WebSockets, see L<URI::wss>.

=head1 METHODS

=head2 URI::ws-E<gt>default_port

Returns the default port (80)

=head1 SEE ALSO

L<URI>, L<URI::wss>

=cut

=head1 AUTHOR

Graham Ollis <plicease@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
