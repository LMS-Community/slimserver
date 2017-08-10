package Image::Scale;

use strict;

use constant IMAGE_SCALE_TYPE_GD       => 0;
use constant IMAGE_SCALE_TYPE_GD_FIXED => 1;
use constant IMAGE_SCALE_TYPE_GM       => 2;
use constant IMAGE_SCALE_TYPE_GM_FIXED => 3;

our $VERSION = '0.11';

require XSLoader;
XSLoader::load('Image::Scale', $VERSION);

sub new {
    my $class = shift;
    my $self;
    
    my $file = shift || die "Image::Scale->new requires an image path\n";
    my $opts = shift || {};
    
    if ( ref $file eq 'SCALAR' ) {
        $self = bless {
            data => $file,
            %{$opts},
        };
    }
    else {
        if ( !-e $file ) {
            die "Image::Scale couldn't find $file\n";
        }
        
        open my $fh, '<', $file || die "Image::Scale couldn't open $file: $!\n";
        binmode $fh;
    
        $self = bless {
            file => $file,
            _fh  => $fh,
            %{$opts},
        };
    }
    
    # XS init, determine the file type and image size
    $self->{_image} = $self->__init();
    
    # __init will return undef on any errors
    return if !$self->{_image};
    
    return $self;
}

sub resize_gd {
    shift->resize( { %{+shift}, type => IMAGE_SCALE_TYPE_GD } );
}

sub resize_gd_fixed_point {
    shift->resize( { %{+shift}, type => IMAGE_SCALE_TYPE_GD_FIXED } );
}

sub resize_gm {
    shift->resize( { %{+shift}, type => IMAGE_SCALE_TYPE_GM } );
}

sub resize_gm_fixed_point {
    shift->resize( { %{+shift}, type => IMAGE_SCALE_TYPE_GM_FIXED } );
}

sub DESTROY {
    my $self = shift;
    
    # XS cleanup
    $self->__cleanup( $self->{_image} ) if $self->{_image};
    
    close $self->{_fh} if $self->{_fh}; 
}

1;
__END__

=head1 NAME

Image::Scale - Fast, high-quality fixed-point image resizing

=head1 SYNOPSIS

    use Image::Scale
    
    # Resize to 150 width and save to a file
    my $img = Image::Scale->new('image.jpg') || die "Invalid JPEG file";
    $img->resize_gd( { width => 150 } );
    $img->save_jpeg('resized.jpg');
    
    # Easily resize artwork embedded within an audio file
    # You can use L<Audio::Scan> to obtain offset/length information
    my $img = Image::Scale->new( 'track.mp3', { offset => 2200, length => 34123 } );
    $img->resize_gd_fixed_point( { width => 75, height => 75, keep_aspect => 1 } );
    my $data = $img->as_png();

=head1 DESCRIPTION

This module implements several resizing algorithms with a focus on low overhead,
speed and minimal features. Algorithms available are:

  GD's copyResampled (floating-point)
  GD's copyResampled fixed-point (useful on embedded devices/NAS devices)
  GraphicsMagick's assortment of resize filters (floating-point)
  GraphicsMagick's Triangle filter in fixed-point

Supported image formats include JPEG, GIF, PNG, and BMP for input, and
JPEG and PNG for output.

This module came about because we needed to improve the very slow performance of
floating-point resizing algorithms on platforms without a floating-point
unit, such as ARM devices like the SheevaPlug, and the Sparc-based ReadyNAS Duo.
Previously it would take many seconds to resize using GD on the ReadyNAS but the
conversion to fixed-point with a little assembly code brings this down to the range of
well under 1 second.

GD is also incredibly difficult to build on platforms such as Windows so we
needed a replacement.

Normal platforms will also see improvement, by removing all of the GD overhead this
version of copyResampled is around 3 times faster while also using less memory.

The fixed-point versions have an accuracy to around 4 decimal places so the quality
of floating-point vs. fixed is essentially identical.

=head1 METHODS

=head2 new( $PATH or \$DATA, [ \%OPTIONS ] )

Initialize a new Image::Scale object from PATH, which may be any valid JPEG,
GIF, PNG, or BMP file.

Raw image data may also be passed in as a scalar reference.  Using a file path
is recommended when possible as this is more efficient and requires less memory.

new() reads the image header, and will return undef if the header is invalid,
so be sure to check for this.

Optionally you can also pass in additional options in a hashref:

    offset
    length

To access an image embedded within another file, such as an audio file, you can
specify a byte offset and length.

=head2 width()

Returns the width of the original source image.

=head2 height()

Returns the height of the original source image.

=head2 resized_width()

Returns the resized width from the last call to resize_*(). Returns 0 if no
resize function has been called yet.

=head2 resized_height()

Returns the resized height from the last call to resize_*(). Returns 0 if no
resize function has been called yet.

=head2 resize( \%OPTIONS )

resize() uses the default resize algorithm, which is resize_gd_fixed_point.  See below
for details on the available options.

=head2 resize_gd( \%OPTIONS )

=head2 resize_gd_fixed_point( \%OPTIONS )

=head2 resize_gm( \%OPTIONS )

=head2 resize_gm_fixed_point( \%OPTIONS )

The 4 resize methods available are:

    resize_gd - This is GD's copyResampled algorithm (floating-point)
    resize_gd_fixed_point - copyResampled (converted to fixed-point)
    resize_gm - GraphicsMagick, see below for filter options
    resize_gm_fixed_point - GraphicsMagick, only the Triangle filter is available in fixed-point mode

Options are specified in a hashref:

    width
    height

At least one of width or height are required. If only one is supplied the
image will retain the original aspect ratio.

    filter

For use with resize_gm() only.  Choose from the following filters, sorted in order
from least to most CPU time.  This does not necessarily mean least to best quality, though!
Be sure to do your own comparisons for quality.

    Point
    Box
    Triangle
    Hermite
    Hanning
    Hamming
    Blackman
    Gaussian
    Quadratic
    Cubic
    Catrom
    Mitchell
    Lanczos
    Bessel
    Sinc

If no filter is specified the default is Lanczos if downsizing, and Mitchell for upsizing or
if the image has an alpha channel.

    keep_aspect => 1

Only useful when both width and height are specified. This option will keep the
original aspect ratio of the source as well as center the image when resizing into
a different aspect ratio. For best results, images altered in this way should be
saved as PNG which will automatically add the necessary transparency around the image.

    bgcolor => 0xffffff

When using keep_aspect, you can use bgcolor to define the background color of the padded
portion of the image.  Usually this should only be used if saving as JPEG because PNG
will default to transparent.  If this value is set and the image is saved as PNG, the
PNG will not be transparent.  The default bgcolor value is 0x000000 (black).

    ignore_exif => 1

By default, if a JPEG image contains an EXIF tag with orientation info, the image will be
rotated accordingly during resizing.  To disable this feature, set ignore_exif to 1.

    memory_limit => $limit_in_bytes

To avoid excess memory growth when resizing images that may be very
large, you can specify this option. If the resize_*() method would result in a
total memory allocation greater than $limit_in_bytes, the method will die.
Be sure to wrap the resize call in an eval when using this option.

=head2 save_jpeg( $PATH, [ $QUALITY ] )

Saves the resized image as a JPEG to PATH. If a quality is not specified, the
quality defaults to 90.

=head2 as_jpeg( [ $QUALITY ] )

Returns the resized JPEG image as scalar data. If a quality is not specified, the
quality defaults to 90.

=head2 save_png( $PATH )

Saves the resized image as a PNG to PATH. Transparency is preserved when saving to PNG.

=head2 as_png()

Returns the resized PNG image as scalar data.

=head2 jpeg_version()

=head2 png_version()

=head2 gif_version()

Returns the version of the image library used.  Returns undef if support for that image
format was not built.

=head1 PERFORMANCE

These numbers were gathered on my 2.4ghz MacBook Pro with version 0.06.

JPEG image, 1425x1425 -> 100x100 (libjpeg-turbo 1.0.0 with pre-scaling)
Note that GD does not support JPEG pre-scaling which results
in very poor performance and high memory usage. These numbers also include
returning the resized image as a JPEG.

    GD copyResampled                        4.8/s
    resize_gm( { filter => 'Triangle' } )   127/s
    resize_gd_fixed_point                   128/s
    resize_gd                               131/s
    resize_gm_fixed_point                   133/s

PNG image, 350x350 -> 100x100 (libpng 1.4.3)
libpng is quite slow, probably because they were forced to remove a lot of assembly
code recently. These numbers also include returning the resized image as a PNG.

    GD copyResampled                        46.1/s
    resize_gm( { filter => 'Triangle' } )   61.4/s
    resize_gm_fixed_point                   64.9/s
    resize_gd                               76.0/s
    resize_gd_fixed_point                   77.6/s

Here are some numbers from a machine without floating-point support (version 0.01).
(Marvell SheevaPlug 1.2ghz ARM9, JPEG 1425x1425 -> 200x200, libjpeg 6b with scaling)

    GD copyResampled                        1.08/s
    resize_gd                               2.16/s
    resize_gm( { filter => 'Triangle' } )   2.85/s
    resize_gd_fixed_point                   7.98/s
    resize_gm_fixed_point                   9.44/s

And finally, from an even slower machine, the 240mhz Netgear ReadyNAS Duo which
has extremely poor floating-point performance (version 0.01).
(JPEG 1425x1425 -> 200x200, libjpeg 6b with scaling)

    resize_gd                               0.029/s (34.5 s/iter)
    resize_gm( { filter => 'Triangle' } )   0.033/s (30.4 s/iter)
    resize_gd_fixed_point                   1.92/s  (0.522 s/iter)
    resize_gm_fixed_point                   2.07/s  (0.483 s/iter) (63x faster than floating-point!)

=head1 SEE ALSO

L<GD>,
L<Image::Magick>,
L<Imager>

=head1 AUTHOR

Andy Grundman, E<lt>andy@hybridized.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 Andy Grundman

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

=cut
