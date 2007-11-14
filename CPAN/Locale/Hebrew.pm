# $File: //member/autrijus/Locale-Hebrew/Hebrew.pm $ $Author: dsully $
# $Revision: #4 $ $Change: 11169 $ $DateTime: 2004/09/18 09:21:22 $

package Locale::Hebrew;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Exporter;
use DynaLoader;

@ISA = qw(Exporter DynaLoader);
@EXPORT = @EXPORT_OK = qw(hebrewflip);
$VERSION = '1.04';

__PACKAGE__->bootstrap($VERSION);

=head1 NAME

Locale::Hebrew - Bidirectional Hebrew support

=head1 VERSION

This document describes version 1.04 of Locale::Hebrew, released
September 18, 2004.

=head1 SYNOPSIS

    use Locale::Hebrew;
    $visual = hebrewflip($logical);

=head1 DESCRIPTION

This module is based on code from the Unicode Consortium.

The charset on their code was bogus, therefore this module had to work
the real charset from scratch.  There might have some mistakes, though.

One function, C<hebrewflip>, is exported by default.

=head1 NOTES

The input string is assumed to be in C<iso-8859-8> encoding by default.

On Perl version 5.8.1 and above, this module can handle Unicode strings
by transparently encoding and decoding it as C<iso-8859-8>.  The return
value should still be a Unicode string.

=cut

sub hebrewflip ($) {
    if ($] >= 5.008001 and utf8::is_utf8($_[0])) {
        require Encode;
        return Encode::decode(
            'iso-8859-8',
            _hebrewflip( Encode::encode('iso-8859-8', $_[0]) )
        );
    }
    goto &_hebrewflip;
}

1;

=head1 ACKNOWLEDGMENTS

Lots of help from Raz Information Systems, L<http://www.raz.co.il/>.

Thanks to Oded S. Resnik for suggesting Unicode support and exporting
C<hebrewflip> by default.

=head1 AUTHORS

Ariel Brosh E<lt>schop@cpan.orgE<gt> is the original author, now passed
away.

Autrijus Tang E<lt>autrijus@autrijus.orgE<gt> is the current maintainer.

=head1 COPYRIGHT

Copyright 2001, 2002 by Ariel Brosh.

Copyright 2003, 2004 by Autrijus Tang.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

__END__
# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
