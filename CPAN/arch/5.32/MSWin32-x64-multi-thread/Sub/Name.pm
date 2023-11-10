package Sub::Name; # git description: v0.25-7-gdb146e5
# ABSTRACT: (Re)name a sub
# KEYWORDS: subroutine function utility name rename symbol

#pod =pod
#pod
#pod =head1 SYNOPSIS
#pod
#pod     use Sub::Name;
#pod
#pod     subname $name, $subref;
#pod
#pod     $subref = subname foo => sub { ... };
#pod
#pod =head1 DESCRIPTION
#pod
#pod This module has only one function, which is also exported by default:
#pod
#pod =for stopwords subname
#pod
#pod =head2 subname NAME, CODEREF
#pod
#pod Assigns a new name to referenced sub.  If package specification is omitted in
#pod the name, then the current package is used.  The return value is the sub.
#pod
#pod The name is only used for informative routines (caller, Carp, etc).  You won't
#pod be able to actually invoke the sub by the given name.  To allow that, you need
#pod to do glob-assignment yourself.
#pod
#pod Note that for anonymous closures (subs that reference lexicals declared outside
#pod the sub itself) you can name each instance of the closure differently, which
#pod can be very useful for debugging.
#pod
#pod =head1 SEE ALSO
#pod
#pod =for :list
#pod * L<Sub::Identify> - for getting information about subs
#pod * L<Sub::Util> - set_subname is another implementation of C<subname>
#pod
#pod =for stopwords cPanel
#pod
#pod =head1 COPYRIGHT AND LICENSE
#pod
#pod This software is copyright (c) 2004, 2008 by Matthijs van Duin, all rights reserved;
#pod copyright (c) 2014 cPanel Inc., all rights reserved.
#pod
#pod This program is free software; you can redistribute it and/or modify
#pod it under the same terms as Perl itself.
#pod
#pod =cut

use 5.006;

use strict;
use warnings;

our $VERSION = '0.26';

use Exporter ();
*import = \&Exporter::import;

our @EXPORT = qw(subname);
our @EXPORT_OK = @EXPORT;

use XSLoader;
XSLoader::load(
    __PACKAGE__,
    $VERSION,
);

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Sub::Name - (Re)name a sub

=head1 VERSION

version 0.26

=head1 SYNOPSIS

    use Sub::Name;

    subname $name, $subref;

    $subref = subname foo => sub { ... };

=head1 DESCRIPTION

This module has only one function, which is also exported by default:

=for stopwords subname

=head2 subname NAME, CODEREF

Assigns a new name to referenced sub.  If package specification is omitted in
the name, then the current package is used.  The return value is the sub.

The name is only used for informative routines (caller, Carp, etc).  You won't
be able to actually invoke the sub by the given name.  To allow that, you need
to do glob-assignment yourself.

Note that for anonymous closures (subs that reference lexicals declared outside
the sub itself) you can name each instance of the closure differently, which
can be very useful for debugging.

=head1 SEE ALSO

=over 4

=item *

L<Sub::Identify> - for getting information about subs

=item *

L<Sub::Util> - set_subname is another implementation of C<subname>

=back

=for stopwords cPanel

=head1 SUPPORT

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Sub-Name>
(or L<bug-Sub-Name@rt.cpan.org|mailto:bug-Sub-Name@rt.cpan.org>).

There is also an irc channel available for users of this distribution, at
L<C<#toolchain> on C<irc.perl.org>|irc://irc.perl.org/#toolchain>.

=head1 AUTHOR

Matthijs van Duin <xmath@cpan.org>

=head1 CONTRIBUTORS

=for stopwords Karen Etheridge Graham Knop Leon Timmermans Reini Urban Florian Ragwitz Matthijs van Duin Dagfinn Ilmari Mannsåker gfx Aristotle Pagaltzis J.R. Mash Alexander Bluhm

=over 4

=item *

Karen Etheridge <ether@cpan.org>

=item *

Graham Knop <haarg@haarg.org>

=item *

Leon Timmermans <fawaka@gmail.com>

=item *

Reini Urban <rurban@cpan.org>

=item *

Florian Ragwitz <rafl@debian.org>

=item *

Matthijs van Duin <xmath-no-spam@nospam.cpan.org>

=item *

Dagfinn Ilmari Mannsåker <ilmari@ilmari.org>

=item *

gfx <gfuji@cpan.org>

=item *

Aristotle Pagaltzis <pagaltzis@gmx.de>

=item *

J.R. Mash <jmash.code@gmail.com>

=item *

Alexander Bluhm <alexander.bluhm@gmx.net>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2004, 2008 by Matthijs van Duin, all rights reserved;
copyright (c) 2014 cPanel Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
