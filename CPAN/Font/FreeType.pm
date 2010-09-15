package Font::FreeType;
use warnings;
use strict;

our $VERSION = '0.03';

require DynaLoader;
our @ISA = qw( DynaLoader );

use Font::FreeType::Glyph;
use Carp;

bootstrap Font::FreeType;

sub import
{
    my $caller_pkg = caller;
    qefft2_import($caller_pkg);
}

sub face
{
    my ($self, $filename, %option) = @_;
    croak 'usage: $freetype->face($filename, %options)'
      unless defined $self && defined $filename;
    return qefft2_face($self, $filename, $option{index} || 0,
                       $option{load_flags} || 0);
}

# TODO - maybe I should have a section no error messages, like this:
# error loading freetype glyph: invalid ppem value
# (probably means you've forgotten to set the character size with set_char_size()).
# or maybe I should set a default size to avoid the problem?

1;

__END__

=head1 NAME

Font::FreeType - read font files and render glyphs from Perl using FreeType2

=head1 SYNOPSIS

    use Font::FreeType;

    my $freetype = Font::FreeType->new;
    my $face = $freetype->face('Vera.ttf');

    $face->set_char_size(24, 24, 100, 100);
    my $glyph = $face->glyph_from_char('A');

=head1 DESCRIPTION

This module allows Perl programs to conveniently read information from
font files.  All the font access is done through the FreeType2 library,
which supports many formats.  It can render images of characters with
high-quality hinting and antialiasing, extract metrics information, and
extract the outlines of characters in scalable formats like TrueType.

Warning: this module is currently in 'beta' stage.  It'll be another
release or two before it stabilizes.  The API may change in ways that
break programs based on it, but I don't think it will change much.
Some of the values returned may be wrong, or not scaled correctly.
See the I<TODO> file to get a handle on how far along this work is.
Contributions welcome, particularly if you know more than I do (which
isn't much) about fonts and the FreeType2 library.

The Font::FreeType API is not intended to replicate the C API of the
FreeType library -- it offers a much more Perl-friendly interface.

The quickest way to get started with this library is to look at the
examples in the I<examples> directory of the distribution.  Full
details of the API are contained in this documentation, and (more
importantly) the documentation for the
L<Font::FreeType::Face|Font::FreeType::Face> and
L<Font::FreeType::Glyph|Font::FreeType::Glyph> classes.

To use the library, first create a Font::FreeType object.  This can
be used to load B<faces> from files, for example:

    my $freetype = Font::FreeType->new;
    my $face = $freetype->face('Vera.ttf');

If your font is scalable (i.e., not a bitmapped font) then set the size
and resolution you want to see it at, for example 24pt at 100dpi:

    $face->set_char_size(24, 24, 100, 100);

Then load a particular glyph (an image of a character), either by
character code (in Unicode) or the actual character:

    my $glyph = $face->glyph_from_char_code(65);
    my $glyph = $face->glyph_from_char('A');

Glyphs can be rendered to bitmap images, among other things:

    my $bitmap = $glyph->bitmap;

See the documentation for L<Font::FreeType::Glyph|Font::FreeType::Glyph>
for details of the format of the bitmap array reference that returns, and
for other ways to get information about a glyph.

=head1 METHODS

Unless otherwise stated, all methods will die if there is an error.

=over 4

=item new()

Create a new 'instance' of the freetype library and return the object.
This is a class method, which doesn't take any arguments.  If you only
want to load one face, then it's probably not even worth saving the
object to a variable:

    my $face = Font::FreeType->new->face('Vera.ttf');

=item face(I<filename>, I<%options>)

Return a L<Font::FreeType::Face|Font::FreeType::Face> object representing
a font face from the specified file.

The C<index> option specifies which face to load from the file.  It
defaults to 0, and since most fonts only contain one face it rarely
needs to be provided.

The C<load_flags> option takes various flags which alter the way
glyphs are loaded.  The default is usually OK for rendering fonts
to bitmap images.  When extracting outlines from fonts, be sure to
set the FT_LOAD_NO_HINTING flag.

The following load flags are available.  They can be combined with
the bitwise OR operator (C<|>).  The symbols are exported by the
module and so will be available once you do C<use Font::FreeType>.

=over 4

=item FT_LOAD_DEFAULT

The same as doing nothing special.

=item FT_LOAD_CROP_BITMAP

Remove extraneous black bits round the edges of bitmaps when loading
embedded bitmaps.

=item FT_LOAD_FORCE_AUTOHINT

Use FreeType's own automatic hinting algorithm rather than the normal
TrueType one.  Probably only useful for testing the FreeType library.

=item FT_LOAD_IGNORE_GLOBAL_ADVANCE_WIDTH

Probably only useful for loading fonts with wrong metrics.

=item FT_LOAD_IGNORE_TRANSFORM

Don't transform glyphs.  This module doesn't yet have support for
transformations.

=item FT_LOAD_LINEAR_DESIGN

Don't scale the metrics.

=item FT_LOAD_NO_AUTOHINT

Don't use the FreeType autohinting algorithm.  Hinting with other
algorithms (such as the TrueType one) will still be done if possible.
Apparently some fonts look worse with the autohinter than without
any hinting.

This option is only available with FreeType 2.1.3 or newer.

=item FT_LOAD_NO_BITMAP

Don't load embedded bitmaps provided with scalable fonts.  Bitmap
fonts are still loaded normally.  This probably doesn't make much
difference in the current version of this module, as embedded
bitmaps aren't deliberately used.

=item FT_LOAD_NO_HINTING

Prevents the coordinates of the outline from being adjusted ('grid
fitted') to the current size.  Hinting should be turned on when rendering
bitmap images of glyphs, and off when extracting the outline
information if you don't know at what resolution it will be rendered.
For example, when converting glyphs to PostScript or PDF, use this
to turn the hinting off.

=item FT_LOAD_NO_SCALE

Don't scale the font's outline or metrics to the right size.  This
will currently generate bad numbers.  To be fixed in a later version.

=item FT_LOAD_PEDANTIC

Raise errors when a font file is broken, rather than trying to work
around it.

=item FT_LOAD_VERTICAL_LAYOUT

Return metrics and glyphs suitable for vertical layout.  This module
doesn't yet provide any intentional support for vertical layout, so
this probably won't be much use.

=back

=item version()

Returns the version number of the underlying FreeType library being
used.  If called in scalar context returns a string containing three
numbers in the format "major.minor.patch".  In list context returns
the three numbers as separate values.

=back

=head1 SEE ALSO

L<Font::FreeType::Face|Font::FreeType::Face>,
L<Font::FreeType::Glyph|Font::FreeType::Glyph>

=head1 AUTHOR

Geoff Richards E<lt>qef@laxan.comE<gt>

=head1 COPYRIGHT

Copyright 2004, Geoff Richards.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

# vi:ts=4 sw=4 expandtab:
