#============================================================= -*-Perl-*-
#
# Template::Plugin::Image
#
# DESCRIPTION
#  Plugin for encapsulating information about an image.
#
# AUTHOR
#   Andy Wardley <abw@wardley.org>
#
# COPYRIGHT
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
# REVISION
#   $Id: Image.pm,v 1.18 2006/01/30 20:05:48 abw Exp $
#
#============================================================================

package Template::Plugin::Image;

require 5.004;

use strict;
use Template::Exception;
use Template::Plugin;
use File::Spec;
#use Image::Info;
#use Image::Size;

use base qw( Template::Plugin );
use vars qw( $VERSION $AUTOLOAD );

$VERSION = sprintf("%d.%02d", q$Revision: 1.18 $ =~ /(\d+)\.(\d+)/);

BEGIN {
    if (eval { require Image::Info; }) {
        *img_info = \&Image::Info::image_info;
    }
    elsif (eval { require Image::Size; }) {
        *img_info = sub {
            my $file = shift;
            my @stuff = Image::Size::imgsize($file);
            return { "width"  => $stuff[0],
                     "height" => $stuff[1],
                     "error"  =>
                        # imgsize returns either a three letter file type
                        # or an error message as third value
                        (defined($stuff[2]) && length($stuff[2]) > 3
                            ? $stuff[2]
                            : undef),
                   };
        }
    }
    else {
        die(Template::Exception->new("image",
            "Couldn't load Image::Info or Image::Size: $@"));
    }

}

#------------------------------------------------------------------------
# new($context, $name, \%config)
#
# Create a new Image object.  Takes the pathname of the file as
# the argument following the context and an optional 
# hash reference of configuration parameters.
#------------------------------------------------------------------------

sub new {
    my $config = ref($_[-1]) eq 'HASH' ? pop(@_) : { };
    my ($class, $context, $name) = @_;
    my ($root, $file, $type);

    # name can be a positional or named argument
    $name = $config->{ name } unless defined $name;

    return $class->throw('no image file specified')
        unless defined $name and length $name;

    # name can be specified as an absolute path or relative
    # to a root directory 

    if ($root = $config->{ root }) {
        $file = File::Spec->catfile($root, $name);
    }
    else {
        $file = defined $config->{file} ? $config->{file} : $name;
    }

    # Make a note of whether we are using Image::Size or
    # Image::Info -- at least for the test suite
    $type = $INC{"Image/Size.pm"} ? "Image::Size" : "Image::Info";

    # set a default (empty) alt attribute for tag()
    $config->{ alt } = '' unless defined $config->{ alt };

    # do we want to check to see if file exists?
    bless { 
        %$config,
        name => $name,
        file => $file,
        root => $root,
        type => $type,
    }, $class;
}

#------------------------------------------------------------------------
# init()
#
# Calls image_info on $self->{ file }
#------------------------------------------------------------------------

sub init {
    my $self = shift;
    return $self if $self->{ size };

    my $image = img_info($self->{ file });
    return $self->throw($image->{ error }) if defined $image->{ error };

    @$self{ keys %$image } = values %$image;
    $self->{ size } = [ $image->{ width }, $image->{ height } ];

    $self->{ modtime } = (stat $self->{ file })[10];

    return $self;
}

#------------------------------------------------------------------------
# attr()
#
# Return the width and height as HTML/XML attributes.
#------------------------------------------------------------------------

sub attr {
    my $self = shift;
    my $size = $self->size();
    return "width=\"$size->[0]\" height=\"$size->[1]\"";
}


#------------------------------------------------------------------------
# modtime()
#
# Return last modification time as a time_t:
#
#   [% date.format(image.modtime, "%Y/%m/%d") %]
#------------------------------------------------------------------------

sub modtime {
    my $self = shift;
    $self->init;
    return $self->{ modtime };
}


#------------------------------------------------------------------------
# tag(\%options)
#
# Return an XHTML img tag.
#------------------------------------------------------------------------

sub tag {
    my $self = shift;
    my $options = ref $_[0] eq 'HASH' ? shift : { @_ };

    my $tag = '<img src="' . $self->name() . '" ' . $self->attr();
 
    # XHTML spec says that the alt attribute is mandatory, so who
    # are we to argue?

    $options->{ alt } = $self->{ alt }
        unless defined $options->{ alt };

    if (%$options) {
        while (my ($key, $val) = each %$options) {
            my $escaped = escape( $val );
            $tag .= qq[ $key="$escaped"];
        }
    }

    $tag .= ' />';

    return $tag;
}

sub escape {
    my ($text) = @_;
    for ($text) {
        s/&/&amp;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
        s/"/&quot;/g;
    }
    $text;
}

sub throw {
    my ($self, $error) = @_;
    die (Template::Exception->new('Image', $error));
}

sub AUTOLOAD {
    my $self = shift;
   (my $a = $AUTOLOAD) =~ s/.*:://;

    $self->init;
    return $self->{ $a };
}

1;

__END__


#------------------------------------------------------------------------
# IMPORTANT NOTE
#   This documentation is generated automatically from source
#   templates.  Any changes you make here may be lost.
# 
#   The 'docsrc' documentation source bundle is available for download
#   from http://www.template-toolkit.org/docs.html and contains all
#   the source templates, XML files, scripts, etc., from which the
#   documentation for the Template Toolkit is built.
#------------------------------------------------------------------------

=head1 NAME

Template::Plugin::Image - Plugin access to image sizes

=head1 SYNOPSIS

    [% USE Image(filename) %]
    [% Image.width %]
    [% Image.height %]
    [% Image.size.join(', ') %]
    [% Image.attr %]
    [% Image.tag %]

=head1 DESCRIPTION

This plugin provides an interface to the Image::Info or Image::Size
modules for determining the size of image files.

You can specify the plugin name as either 'Image' or 'image'.  The
plugin object created will then have the same name.  The file name of
the image should be specified as a positional or named argument.

    [% # all these are valid, take your pick %]
    [% USE Image('foo.gif') %]
    [% USE image('bar.gif') %]
    [% USE Image 'ping.gif' %]
    [% USE image(name='baz.gif') %]
    [% USE Image name='pong.gif' %]

A "root" parameter can be used to specify the location of the image file:

    [% USE Image(root='/path/to/root', name='images/home.png') %]
    # image path: /path/to/root/images/home.png
    # img src: images/home.png

In cases where the image path and image url do not match up, specify the
file name directly:

    [% USE Image(file='/path/to/home.png', name='/images/home.png') %]

The "alt" parameter can be used to specify an alternate name for the
image, for use in constructing an XHTML element (see the tag() method
below).

    [% USE Image('home.png', alt="Home") %]

You can also provide an alternate name for an Image plugin object.

    [% USE img1 = image 'foo.gif' %]
    [% USE img2 = image 'bar.gif' %]

The 'name' method returns the image file name.

    [% img1.name %]     # foo.gif

The 'width' and 'height' methods return the width and height of the
image, respectively.  The 'size' method returns a reference to a 2
element list containing the width and height.

    [% USE image 'foo.gif' %]
    width: [% image.width %]
    height: [% image.height %]
    size: [% image.size.join(', ') %]

The 'modtime' method returns the ctime of the file in question, suitable
for use with date.format:

    [% USE image 'foo.gif' %]
    [% USE date %]
    [% date.format(image.modtime, "%B, %e %Y") %]

The 'attr' method returns the height and width as HTML/XML attributes.

    [% USE image 'foo.gif' %]
    [% image.attr %]

Typical output:

    width="60" height="20"

The 'tag' method returns a complete XHTML tag referencing the image.

    [% USE image 'foo.gif' %]
    [% image.tag %]

Typical output:

    <img src="foo.gif" width="60" height="20" alt="" />

You can provide any additional attributes that should be added to the 
XHTML tag.

    [% USE image 'foo.gif' %]
    [% image.tag(class="logo" alt="Logo") %]

Typical output:

    <img src="foo.gif" width="60" height="20" alt="Logo" class="logo" />

Note that the 'alt' attribute is mandatory in a strict XHTML 'img'
element (even if it's empty) so it is always added even if you don't
explicitly provide a value for it.  You can do so as an argument to 
the 'tag' method, as shown in the previous example, or as an argument

    [% USE image('foo.gif', alt='Logo') %]

=head1 CATCHING ERRORS

If the image file cannot be found then the above methods will throw an
'Image' error.  You can enclose calls to these methods in a
TRY...CATCH block to catch any potential errors.

    [% TRY;
         image.width;
       CATCH;
         error;      # print error
       END
    %]

=head1 USING Image::Info

At run time, the plugin tries to load Image::Info in preference to
Image::Size. If Image::Info is found, then some additional methods are
available, in addition to 'size', 'width', 'height', 'attr', and 'tag'.
These additional methods are named after the elements that Image::Info
retrieves from the image itself; see L<Image::Info> for more details
-- the types of methods available depend on the type of image.
These additional methods will always include the following:

=over 4

=item file_media_type

This is the MIME type that is appropriate for the given file format.
The corresponding value is a string like: "image/png" or "image/jpeg".

=item file_ext

The is the suggested file name extention for a file of the given
file format.  The value is a 3 letter, lowercase string like
"png", "jpg".


=item color_type

The value is a short string describing what kind of values the pixels
encode.  The value can be one of the following:

  Gray
  GrayA
  RGB
  RGBA
  CMYK
  YCbCr
  CIELab

These names can also be prefixed by "Indexed-" if the image is
composed of indexes into a palette.  Of these, only "Indexed-RGB" is
likely to occur.

(It is similar to the TIFF field PhotometricInterpretation, but this
name was found to be too long, so we used the PNG inpired term
instead.)

=item resolution

The value of this field normally gives the physical size of the image
on screen or paper. When the unit specifier is missing then this field
denotes the squareness of pixels in the image.

The syntax of this field is:

   <res> <unit>
   <xres> "/" <yres> <unit>
   <xres> "/" <yres>

The E<lt>resE<gt>, E<lt>xresE<gt> and E<lt>yresE<gt> fields are
numbers.  The E<lt>unitE<gt> is a string like C<dpi>, C<dpm> or
C<dpcm> (denoting "dots per inch/cm/meter).

=item SamplesPerPixel

This says how many channels there are in the image.  For some image
formats this number might be higher than the number implied from the
C<color_type>.

=item BitsPerSample

This says how many bits are used to encode each of samples.  The value
is a reference to an array containing numbers. The number of elements
in the array should be the same as C<SamplesPerPixel>.

=item Comment

Textual comments found in the file.  The value is a reference to an
array if there are multiple comments found.

=item Interlace

If the image is interlaced, then this tell which interlace method is
used.

=item Compression

This tell which compression algorithm is used.

=item Gamma

A number.


=back

=head1 AUTHOR

Andy Wardley E<lt>abw@wardley.orgE<gt>

L<http://wardley.org/|http://wardley.org/>




=head1 VERSION

1.18, distributed as part of the
Template Toolkit version 2.15, released on 26 May 2006.

=head1 COPYRIGHT

  Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
