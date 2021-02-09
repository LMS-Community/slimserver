package Font::FreeType::Face;
use warnings;
use strict;


1;

__END__

=head1 NAME

Font::FreeType::Face - font typefaces loaded from Font::FreeType

=head1 SYNOPSIS

    use Font::FreeType;

    my $freetype = Font::FreeType->new;
    my $face = $freetype->face('Vera.ttf');

=head1 DESCRIPTION

This class represents a font face (or typeface) loaded from a font file.
Usually a face represents all the information in the font file (such as
a TTF file), although it is possible to have multiple faces in a single
file.

Never 'use' this module directly; the class is loaded automatically from
L<Font::FreeType|Font::FreeType>.  Use the C<Font::FreeType-E<gt>face()>
method to create a new Font::FreeType::Face object from a filename.

=head1 METHODS

Unless otherwise stated, all methods will die if there is an error.

=over 4

=item ascender()

The height above the baseline of the 'top' of the font's glyphs, scaled to
the current size of the face.

=item attach_file(I<filename>)

Informs FreeType of an ancillary file needed for reading the font.
Hasn't been tested yet.

=item current_face_index()

The index number of the current font face.  Usually this will be
zero, which is the default.  See C<Font::FreeType-E<gt>face()> for how
to load other faces from the same file.

=item descender()

The depth below the baseline of the 'bottom' of the font's glyphs, scaled to
the current size of the face.  Actually represents the distance moving up
from the baseline, so usually negative.

=item family_name()

A string containing the name of the family this font claims to be from.

=item fixed_sizes()

In scalar context returns the number of fixed sizes (of embedded bitmaps)
available in the font.  In list context returns a list of hashes which
detail those sizes.  Each hash can contain the following keys, but they
will be absent if the information isn't available:

=over 4

=item size

Size of the glyphs in points.  Only available with Freetype 2.1.5 or newer.

=item height

Height of the bitmaps in pixels.

=item width

Width of the bitmaps in pixels.

=item x_res_dpi, y_res_dpi

Resolution the bitmaps were designed for, in dots per inch.
Only available with Freetype 2.1.5 or newer.

=item x_res_ppem, y_res_ppem

Resolution the bitmaps were designed for, in pixels per em.
Only available with Freetype 2.1.5 or newer.

=back

=item foreach_char(I<code-ref>)

Iterates through all the characters in the font, and calls I<code-ref>
for each of them in turn.  Glyphs which don't correspond to Unicode
characters are ignored.  There is currently no facility for iterating
over all glyphs.

Each time your callback code is called, C<$_> will be set to a
L<Font::FreeType::Glyph|Font::FreeType::Glyph> object for the current glyph.
For an example see the program I<list-characters.pl> provided in the
distribution.

=item glyph_from_char(I<character>)

Returns a L<Font::FreeType::Glyph|Font::FreeType::Glyph> object for the
glyph corresponding to the first character in the string provided.
Note that currently non-ASCII characters are not likely to work with
this, so you might be better using the C<glyph_from_char_code()>
method below and the Perl C<ord> function.

Returns I<undef> if the glyph is not available in the font.

=item glyph_from_char_code(I<char-code>)

Returns a L<Font::FreeType::Glyph|Font::FreeType::Glyph> object for the
glyph corresponding to Unicode character I<char-code>.  FreeType supports
using other character sets, but this module doesn't yet.

Returns I<undef> if the glyph is not available in the font.

=item has_glyph_names()

True if individual glyphs have names.  If so, the names can be
retrieved with the C<name()> method on
L<Font::FreeType::Glyph|Font::FreeType::Glyph> objects.

See also C<has_reliable_glyph_names()> below.

=item has_horizontal_metrics()

=item has_vertical_metrics()

These return true if the font contains metrics for the corresponding
directional layout.  Most fonts will contain horizontal metrics, describing
(for example) how the characters should be spaced out across a page when
being written horizontally like English.  Some fonts, such as Chinese ones,
may contain vertical metrics as well, allowing typesetting down the page.

=item has_kerning()

True if the font provides kerning information.  See the C<kerning()>
method below.

=item has_reliable_glyph_names()

True if the font contains reliable PostScript glyph names.  Some
Some fonts contain bad glyph names.  This method always returns false
when used with Freetype versions earlier than 2.1.1.

See also C<has_glyph_names()> above.

=item height()

The height of the text.  Not entirely sure what that corresponds
to (is it the line height or what?).

=item is_bold()

True if the font claims to be in a bold style.

=item is_fixed_width()

True if all the characters in the font are the same width.
Will be true for monospaced fonts like Courier.

=item is_italic()

Returns true if the font claims to be in an italic style.

=item is_scalable()

True if the font has a scalable outline, meaning it can be rendered
nicely at virtually any size.  Returns false for bitmap fonts.

=item is_sfnt()

True if the font file is in the 'sfnt' format, meaning it is
either TrueType or OpenType.  This isn't much use yet, but future versions
of this library might provide access to extra information about sfnt fonts.

=item kerning(I<left-glyph-index>, I<right-glyph-index>, [I<mode>])

Returns the suggested kerning adjustment between two glyphs.  When
called in scalar context returns a single value, which should be added
to the position of the second glyph on the I<x> axis for horizontal
layouts, or the I<y> axis for vertical layouts.

Note: currently always returns the I<x> axis kerning, but this will
be fixed when vertical layouts are handled properly.

For example, assuming C<$left> and C<$right> are two
L<Font::FreeType::Glyph|Font::FreeType::Glyph> objects:

    my $kern_distance = $face->kerning($left->index, $right->index);

In list context this returns two values corresponding to the I<x> and
I<y> axes, which should be treated in the same way.

The C<mode> argument controls how the kerning is calculated, with
the following options available:

=over 4

=item FT_KERNING_DEFAULT

Grid-fitting (hinting) and scaling are done.  Use this
when rendering glyphs to bitmaps to make the kerning take the resolution
of the output in to account.

=item FT_KERNING_UNFITTED

Scaling is done, but not hinting.  Use this when extracting
the outlines of glyphs.  If you used the C<FT_LOAD_NO_HINTING> option
when creating the face then use this when calculating the kerning.

=item FT_KERNING_UNSCALED

Leave the measurements in font units, without scaling, and without hinting.

=back

=item number_of_faces()

The number of faces contained in the file from which this one
was created.  Usually there is only one.  See C<Font::FreeType-E<gt>face()>
for how to load the others if there are more.

=item number_of_glyphs()

The number of glyphs in the font face.

=item postscript_name()

A string containing the PostScript name of the font, or I<undef>
if it doesn't have one.

=item set_char_size(I<width>, I<height>, I<x_res>, I<y_res>)

Set the size at which glyphs should be rendered.  Metrics are also
scaled to match.  The width and height will usually be the same, and
are in points.  The resolution is in dots-per-inch.

When generating PostScript outlines a resolution of 72 will scale
to PostScript points.

=item set_pixel_size(I<width>, I<height>)

Set the size at which bitmapped fonts will be loaded.  Bitmap fonts are
automatically set to the first available standard size, so this usually
isn't needed.

=item style_name()

A string describing the style of the font, such as 'Roman' or
'Demi Bold'.  Most TrueType fonts are just 'Regular'.

=item underline_position()

=item underline_thickness()

The suggested position and thickness of underlining for the font,
or I<undef> if the information isn't provided.  Currently in font units,
but this is likely to be changed in a future version.

=item units_per_em()

The size of the em square used by the font designer.  This can
be used to scale font-specific measurements to the right size, although
that's usually done for you by FreeType.  Usually this is 2048 for
TrueType fonts.

=back

=head1 SEE ALSO

L<Font::FreeType|Font::FreeType>,
L<Font::FreeType::Glyph|Font::FreeType::Glyph>

=head1 AUTHOR

Geoff Richards E<lt>qef@laxan.comE<gt>

=head1 COPYRIGHT

Copyright 2004, Geoff Richards.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

# vi:ts=4 sw=4 expandtab
