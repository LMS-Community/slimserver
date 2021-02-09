package Font::FreeType::Glyph;
use warnings;
use strict;

use Carp;

sub outline_decompose
{
    my $self = shift;
    my $handlers = @_ == 1 ? shift : { @_ };
    $self->outline_decompose_($handlers);
}

sub postscript
{
    my ($self, $fh) = @_;
    my $s;
    my $ps = '';

    $self->outline_decompose_({
        move_to => sub {
            $s = "$_[0] $_[1] moveto\n";
            if ($fh) { print $fh $s } else { $ps .= $s }
        },
        line_to => sub {
            $s = "$_[0] $_[1] lineto\n";
            if ($fh) { print $fh $s } else { $ps .= $s }
        },
        cubic_to => sub {
            $s = "$_[2] $_[3] $_[4] $_[5] $_[0] $_[1] curveto\n";
            if ($fh) { print $fh $s } else { $ps .= $s }
        },
    });

    return $fh ? $self : $ps;
}

sub svg_path
{
    my ($self, $fh) = @_;
    my $s;
    my $path = '';

    $self->outline_decompose_({
        move_to => sub {
            $s .= "M$_[0] $_[1]\n";
            if ($fh) { print $fh $s } else { $path .= $s }
        },
        line_to => sub {
            $s = "L$_[0] $_[1]\n";
            if ($fh) { print $fh $s } else { $path .= $s }
        },
        cubic_to => sub {
            $s = "C$_[2] $_[3] $_[4] $_[5] $_[0] $_[1]\n";
            if ($fh) { print $fh $s } else { $path .= $s }
        },
        conic_to => sub {
            $s = "Q$_[2] $_[3] $_[0] $_[1]\n";
            if ($fh) { print $fh $s } else { $path .= $s }
        },
    });

    return $fh ? $self : $path;
}

sub bitmap_pgm
{
    my $self = shift;
    my ($bmp, $left, $top) = $self->bitmap(@_);

    my $wd = length $bmp->[0];
    my $ht = @$bmp;
    return ("P5\n$wd $ht\n255\n" . join('', @$bmp), $left, $top);
}

sub bitmap_magick
{
    require Image::Magick;

    my $self = shift;
    my ($bmp, $left, $top) = $self->bitmap(@_);

    my $wd = length $bmp->[0];
    my $ht = @$bmp;

    my $img = Image::Magick->new(magick=>'gray', size => "${wd}x$ht",
                                 depth => 8);
    my $err = $img->BlobToImage(join '', @$bmp);
    croak "error creating Image::Magick object: $err" if $err;
    return ($img, $left, $top);
}

1;

__END__

=head1 NAME

Font::FreeType::Glyph - glyphs from font typefaces loaded from Font::FreeType

=head1 SYNOPSIS

    use Font::FreeType;

    my $freetype = Font::FreeType->new;
    my $face = $freetype->face('Vera.ttf');
    $face->set_char_size(24, 24, 100, 100);

    my $glyph = $face->glyph_from_char('A');
    my $glyph = $face->glyph_from_char_code(65);

    # Render into an array of strings, one byte per pixel.
    my ($bitmap, $left, $top) = $glyph->bitmap;

    # Read vector outline.
    $glyph->outline_decompose(
        move_to => sub { ... },
        line_to => sub { ... },
        conic_to => sub { ... },
        cubic_to => sub { ... },
    );

=head1 DESCRIPTION

This class represents an individual glyph (character image) loaded from
a font.  See L<Font::FreeType::Face|Font::FreeType::Face> for how to
obtain a glyph object, in particular the C<glyph_from_char_code()>
and C<glyph_from_char()> methods.

Things you an do with glyphs include:

=over 4

=item *

Get metadata about the glyph, such as the size of its image and other
metrics.

=item *

Render a bitmap image of the glyph (if it's from a vector font) or
extract the existing bitmap (if it's from a bitmap font), using the
C<bitmap()> method.

=item *

Extract a precise description of the lines and curves that make up
the glyph's outline, using the C<outline_decompose()> method.

=back

For a detailed description of the meaning of glyph metrics, and
the structure of vectorial outlines,
see L<http://freetype.sourceforge.net/freetype2/docs/glyphs/>

=head1 METHODS

Unless otherwise stated, all methods will die if there is an error,
and the metrics are scaled to the size of the font face.

=over 4

=item bitmap([I<render-mode>])

If the glyph is from a bitmap font, the bitmap image is returned.  If
it is from a vector font, then the outline is rendered into a bitmap
at the face's current size.

Three values are returned: the bitmap itself, the number of pixels from
the origin to where the left of the area the bitmap describes, and the
number of pixels from the origin to the top of the area of the bitmap
(positive being up).

The bitmap value is a reference to an array.  Each item in the array
represents a line of the bitmap, starting from the top.  Each item is
a string of bytes, with one byte representing one pixel of the image,
starting from the left.  A value of 0 indicates background (outside the
glyph outline), and 255 represents a point inside the outline.

If antialiasing is used then shades of grey between 0 and 255 may occur.
Antialiasing is performed by default, but can be turned off by passing
the C<FT_RENDER_MODE_MONO> option.

The size of the bitmap can be obtained as follows:

    my ($bitmap, $left, $top) = $glyph->bitmap;
    my $width = length $bitmap->[0];
    my $height = @$bitmap;

The optional C<render_mode> argument can be any one of the following:

=over 4

=item FT_RENDER_MODE_NORMAL

The default.  Uses antialiasing.

=item FT_RENDER_MODE_LIGHT

Changes the hinting algorithm to make the glyph image closer to it's
real shape, but probably more fuzzy.

Only available with Freetype version 2.1.4 or newer.

=item FT_RENDER_MODE_MONO

Render with antialiasing disabled.  Each pixel will be either 0 or 255.

=item FT_RENDER_MODE_LCD

Render in colour for an LCD display, with three times as many pixels
across the image as normal.  This mode probably won't work yet.

Only available with Freetype version 2.1.3 or newer.

=item FT_RENDER_MODE_LCD_V

Render in colour for an LCD display, with three times as many rows
down the image as normal.  This mode probably won't work yet.

Only available with Freetype version 2.1.3 or newer.

=back

=item bitmap_magick([I<render_mode>])

A simple wrapper around the C<bitmap()> method.  Renders the bitmap as
normal and returns it as an L<Image::Magick|Image::Magick> object,
which can then be composited onto a larger bitmapped image, or manipulated
using any of the features available in Image::Magick.

The image is in the 'gray' format, with a depth of 8 bits.

The left and top distances in pixels are returned as well, in the
same way as for the C<bitmap()> method.

This method, particularly the use of the left and top offsets for
correct positioning of the bitmap, is demonstrated in the
I<magick.pl> example program.

=item bitmap_pgm([I<render_mode>])

A simple wrapper around the C<bitmap()> method.  It renders the bitmap
and constructs it into a PGM (portable grey-map) image file, which it
returns as a string.  The optional I<render-mode> is passed directly
to the C<bitmap()> method.

The PGM image returned is in the 'binary' format, with one byte per
pixel.  It is not an efficient format, but can be read by many image
manipulation programs.  For a detailed description of the format
see L<http://netpbm.sourceforge.net/doc/pgm.html>

The left and top distances in pixels are returned as well, in the
same way as for the C<bitmap()> method.

The I<render-glyph.pl> example program uses this method.

=item char_code()

The character code (in Unicode) of the glyph.  Could potentially
return codes in other character sets if the font doesn't have a Unicode
character mapping, but most modern fonts do.

=item has_outline()

True if the glyph has a vector outline, in which case it is safe to
call C<outline_decompose()>.  Otherwise, the glyph only has a bitmap
image.

=item height()

The height of the glyph.

=item horizontal_advance()

The distance from the origin of this glyph to the place where the next
glyph's origin should be.  Only applies to horizontal layouts.  Always
positive, so for right-to-left text (such as Hebrew) it should be
subtracted from the current glyph's position.

=item index()

The glyph's index number in the font.  This number is determined
by the FreeType library, and so isn't necessarily the same as any
special index number used by the font format.

=item left_bearing()

The left side bearing, which is the distance from the origin to
the left of the glyph image.  Usually positive for horizontal layouts
and negative for vertical ones.

=item name()

The name of the glyph, if the font format supports glyph names,
otherwise I<undef>.

=item outline_bbox()

The bounding box of the glyph's outline.  This box will enclose all
the 'ink' that would be laid down if the outline were filled in.
It is calculated by studying each segment of the outline, so may
not be particularly efficient.

The bounding box is returned as a list of four values, so the method
should be called as follows:

    my ($xmin, $ymin, $xmax, $ymax) = $glyph->outline_bbox();

=item outline_decompose(I<%callbacks>)

This method can be used to extract a description of the glyph's outline,
scaled to the face's current size.  It will die if the glyph doesn't
have an outline (if it comes from a bitmap font).

Vector outlines of glyphs are represented by a sequence of operations.
Each operation can start a new curve (by moving the imaginary pen
position), or draw a line or curve from the current position of the
pen to a new position.  This Perl interface will walk through the outline
calling subroutines (through code references you supply) for each operation.
Arguments are passed to your subroutines as normal, in C<@_>.

Note: when you intend to extract the outline of a glyph, always
pass the C<FT_LOAD_NO_HINTING> option when creating the face object,
or the hinting will distort the outline.

The I<%callbacks> parameter should contain three or four of the
following keys, each with a reference to a C<sub> as it's value.
The C<conic_to> handler is optional, but the others are required.

=over 4

=item C<move_to>

Move the pen to a new position, without adding anything to
the outline.  The first operation should always be C<move_to>, but
characters with disconnected parts, such as C<i>, might have several
of these.

The I<x> and I<y> coordinates of the new pen position are supplied.

=item C<line_to>

Move the pen to a new position, drawing a straight line from the
old position.

The I<x> and I<y> coordinates of the new pen position are supplied.
Depending you how you are using this information you may have to keep
track of the previous position yourself.

=item C<conic_to>

Move the pen to a new position, drawing a conic BE<eacute>zier arc
(also known as a quadratic BE<eacute>zier curve)
from the old position, using a single control point.

If you don't supply a C<conic_to> handler, all conic curves will be
automatically translated into cubic curves.

The I<x> and I<y> coordinates of the new pen position are supplied,
followed by the I<x> and I<y> coordinates of the control point.

=item C<cubic_to>

Move the pen to a new position, drawing a cubic BE<eacute>zier arc
from the old position, using two control points.

Cubic arcs are the ones produced in PostScript by the C<curveto>
operator.

The I<x> and I<y> coordinates of the new pen position are supplied,
followed by the I<x> and I<y> coordinates of the first control point,
then the same for the second control point.

=back

Note that TrueType fonts use conic curves and PostScript ones use
cubic curves.

=item postscript([I<file-handle>])

Generate PostScript code to draw the outline of the glyph.  More precisely,
the output will construct a PostScript path for the outline, which can
then be filled in or stroked as you like.

The I<glyph-to-eps.pl> example program shows how to wrap the output
in enough extra code to generate a complete EPS file.

If you pass a file-handle to this method then it will write the PostScript
code to that file, otherwise it will return it as a string.

=item right_bearing()

The distance from the right edge of the glyph image to the place where
the origin of the next character should be (i.e., the end of the
advance width).  Only applies to horizontal layouts.  Usually positive.

=item svg_path()

Turn the outline of the glyph into a string in a format suitable
for including in an SVG graphics file, as the C<d> attribute of
a C<path> element.  Note that because SVG's coordinate system has
its origin in the top left corner the outline will be upside down.
An SVG transformation can be used to flip it.

The I<glyph-to-svg.pl> example program shows how to wrap the output
in enough XML to generate a complete SVG file, and one way of
transforming the outline to be the right way up.

If you pass a file-handle to this method then it will write the path
string to that file, otherwise it will return it as a string.

=item vertical_advance()

The distance from the origin of the current glyph to the place where
the next glyph's origin should be, moving down the page.  Only applies
to vertical layouts.  Always positive.

=item width()

The width of the glyph.  This is the distance from the left
side to the right side, not the amount you should move along before
placing the next glyph when typesetting.  For that, see
the C<horizontal_advance()> method.

=back

=head1 SEE ALSO

L<Font::FreeType|Font::FreeType>,
L<Font::FreeType::Face|Font::FreeType::Face>

=head1 AUTHOR

Geoff Richards E<lt>qef@laxan.comE<gt>

=head1 COPYRIGHT

Copyright 2004, Geoff Richards.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

# vi:ts=4 sw=4 expandtab
