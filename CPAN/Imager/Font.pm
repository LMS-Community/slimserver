package Imager::Font;

use Imager::Color;
use strict;
use vars qw($VERSION);

$VERSION = "1.033";

# the aim here is that we can:
#  - add file based types in one place: here
#  - make sure we only attempt to create types that exist
#  - give reasonable defaults
#  - give the user some control over which types get used
my %drivers =
  (
   tt=>{
        class=>'Imager::Font::Truetype',
        module=>'Imager/Font/Truetype.pm',
        files=>'.*\.ttf$',
	description => 'FreeType 1.x',
       },
   t1=>{
        class=>'Imager::Font::Type1',
        module=>'Imager/Font/Type1.pm',
        files=>'.*\.pfb$',
	description => 'T1Lib',
       },
   ft2=>{
         class=>'Imager::Font::FreeType2',
         module=>'Imager/Font/FreeType2.pm',
         files=>'.*\.(pfa|pfb|otf|ttf|fon|fnt|dfont|pcf(\.gz)?)$',
	 description => 'FreeType 2.x',
        },
   ifs=>{
         class=>'Imager::Font::Image',
         module=>'Imager/Font/Image.pm',
         files=>'.*\.ifs$',
        },
   w32=>{
         class=>'Imager::Font::Win32',
         module=>'Imager/Font/Win32.pm',
	 description => 'Win32 GDI Fonts',
        },
  );

# this currently should only contain file based types, don't add w32
my @priority = qw(t1 tt ft2 ifs);

# when Imager::Font is loaded, Imager.xs has not been bootstrapped yet
# this function is called from Imager.pm to finish initialization
sub __init {
  @priority = grep Imager::i_has_format($_), @priority;
  for my $driver_name (grep Imager::i_has_format($_), keys %drivers) {
    $drivers{$driver_name}{enabled} = 1;
  }
}

# search method
# 1. start by checking if file is the parameter
# 1a. if so qualify path and compare to the cache.
# 2a. if in cache - take it's id from there and increment count.
#

sub new {
  my $class = shift;
  my $self = {};
  my ($file, $type, $id);
  my %hsh=(color => Imager::Color->new(255,0,0,0),
	   size => 15,
	   @_);

  bless $self,$class;

  if ($hsh{'file'}) {
    $file = $hsh{'file'};
    if ( $file !~ m/^\// ) {
      $file = './'.$file;
      if (! -e $file) {
	$Imager::ERRSTR = "Font $file not found";
	return();
      }
    }

    $type = $hsh{'type'};
    if (!defined($type) or !$drivers{$type} or !$drivers{$type}{enabled}) {
      for my $drv (@priority) {
        undef $type;
        my $re = $drivers{$drv}{files} or next;
        if ($file =~ /$re/i) {
          $type = $drv;
          last;
        }
      }
    }
    if (!defined($type)) {
      # some types we can support, but the driver isn't available
      # work out which drivers support it, so we can provide the user
      # some useful information on how to get it working
      my @not_here;
      for my $driver_name (keys %drivers) {
	my $driver = $drivers{$driver_name};
	push @not_here, "$driver_name ($driver->{description})"
	  if $driver->{files} && $file =~ /$driver->{files}/i;
      }
      if (@not_here) {
	$Imager::ERRSTR = "No font drivers enabled that can support this file, rebuild Imager with any of ".join(", ", @not_here)." to use this font file";
      }
      else {
	$Imager::ERRSTR = "No font type found for $hsh{'file'}";
      }
      return;
    }
  } elsif ($hsh{face}) {
    $type = "w32";
  } else {
    $Imager::ERRSTR="No font file specified";
    return;
  }

  if (!$Imager::formats{$type}) {
    $Imager::ERRSTR = "`$type' not enabled";
    return;
  }

  # here we should have the font type or be dead already.

  require $drivers{$type}{module};
  return $drivers{$type}{class}->new(%hsh);
}

# returns first defined parameter
sub _first {
  for (@_) {
    return $_ if defined $_;
  }
  return undef;
}

sub draw {
  my $self = shift;
  my %input = ('x' => 0, 'y' => 0, @_);
  unless ($input{image}) {
    $Imager::ERRSTR = 'No image supplied to $font->draw()';
    return;
  }
  my $image = $input{image};
  $input{string} = _first($input{string}, $input{text});
  unless (defined $input{string}) {
    $image->_set_error("Missing required parameter 'string'");
    return;
  }
  $input{aa} = _first($input{aa}, $input{antialias}, $self->{aa}, 1);
  # the original draw code worked this out but didn't use it
  $input{align} = _first($input{align}, $self->{align});
  $input{color} = _first($input{color}, $self->{color});
  $input{color} = Imager::_color($input{'color'});

  $input{size} = _first($input{size}, $self->{size});
  unless (defined $input{size}) {
    $image->_set_error("No font size provided");
    return undef;
  }
  $input{align} = _first($input{align}, 1);
  $input{utf8} = _first($input{utf8}, $self->{utf8}, 0);
  $input{vlayout} = _first($input{vlayout}, $self->{vlayout}, 0);

  my $result = $self->_draw(%input);
  unless ($result) {
    $image->_set_error($image->_error_as_msg());
  }

  return $result;
}

sub align {
  my $self = shift;
  my %input = ( halign => 'left', valign => 'baseline', 
                'x' => 0, 'y' => 0, @_ );

  # image needs to be supplied, but can be supplied as undef
  unless (exists $input{image}) {
    Imager->_set_error("Missing required parameter 'image'");
    return;
  }

  my $errors_to = $input{image} || 'Imager';

  my $text = _first($input{string}, $input{text});
  unless (defined $text) {
    $errors_to->_set_error("Missing required parameter 'string'");
    return;
  }

  my $size = _first($input{size}, $self->{size});
  my $utf8 = _first($input{utf8}, 0);

  my $bbox = $self->bounding_box(string=>$text, size=>$size, utf8=>$utf8);
  my $valign = $input{valign};
  $valign = 'baseline'
    unless $valign && $valign =~ /^(?:top|center|bottom|baseline)$/;

  my $halign = $input{halign};
  $halign = 'start' 
    unless $halign && $halign =~ /^(?:left|start|center|end|right)$/;

  my $x = $input{'x'};
  my $y = $input{'y'};

  if ($valign eq 'top') {
    $y += $bbox->ascent;
  }
  elsif ($valign eq 'center') {
    $y += $bbox->ascent - $bbox->text_height / 2;
  }
  elsif ($valign eq 'bottom') {
    $y += $bbox->descent;
  }
  # else baseline is the default

  if ($halign eq 'left') {
    $x -= $bbox->start_offset;
  }
  elsif ($halign eq 'start') {
    # nothing to do
  }
  elsif ($halign eq 'center') {
    $x -= $bbox->start_offset + $bbox->total_width / 2;
  }
  elsif ($halign eq 'end') {
    $x -= $bbox->advance_width;
  }
  elsif ($halign eq 'right') {
    $x -= $bbox->advance_width - $bbox->right_bearing;
  }
  $x = int($x);
  $y = int($y);

  if ($input{image}) {
    delete @input{qw/x y/};
    $self->draw(%input, 'x' => $x, 'y' => $y, align=>1)
      or return;
  }

  return ($x+$bbox->start_offset, $y-$bbox->ascent, 
          $x+$bbox->end_offset, $y-$bbox->descent+1);
}

sub bounding_box {
  my $self=shift;
  my %input=@_;

  if (!exists $input{'string'}) { 
    $Imager::ERRSTR='string parameter missing'; 
    return;
  }
  $input{size} ||= $self->{size};
  $input{sizew} = _first($input{sizew}, $self->{sizew}, 0);
  $input{utf8} = _first($input{utf8}, $self->{utf8}, 0);

  my @box = $self->_bounding_box(%input);

  if (wantarray) {
    if(@box && exists $input{'x'} and exists $input{'y'}) {
      my($gdescent, $gascent)=@box[1,3];
      $box[1]=$input{'y'}-$gascent;      # top = base - ascent (Y is down)
      $box[3]=$input{'y'}-$gdescent;     # bottom = base - descent (Y is down, descent is negative)
      $box[0]+=$input{'x'};
      $box[2]+=$input{'x'};
    } elsif (@box && $input{'canon'}) {
      $box[3]-=$box[1];    # make it cannoical (ie (0,0) - (width, height))
      $box[2]-=$box[0];
    }
    return @box;
  }
  else {
    require Imager::Font::BBox;

    return Imager::Font::BBox->new(@box);
  }
}

sub dpi {
  my $self = shift;

  # I'm assuming a default of 72 dpi
  my @old = (72, 72);
  if (@_) {
    $Imager::ERRSTR = "Setting dpi not implemented for this font type";
    return;
  }

  return @old;
}

sub transform {
  my $self = shift;

  my %hsh = @_;

  # this is split into transform() and _transform() so we can 
  # implement other tags like: degrees=>12, which would build a
  # 12 degree rotation matrix
  # but I'll do that later
  unless ($hsh{matrix}) {
    $Imager::ERRSTR = "You need to supply a matrix";
    return;
  }

  return $self->_transform(%hsh);
}

sub _transform {
  $Imager::ERRSTR = "This type of font cannot be transformed";
  return;
}

sub utf8 {
  return 0;
}

sub priorities {
  my $self = shift;
  my @old = @priority;

  if (@_) {
    @priority = grep Imager::i_has_format($_), @_;
  }
  return @old;
}

1;

__END__

=head1 NAME

Imager::Font - Font handling for Imager.

=head1 SYNOPSIS

  $t1font = Imager::Font->new(file => 'pathtofont.pfb');
  $ttfont = Imager::Font->new(file => 'pathtofont.ttf');
  $w32font = Imager::Font->new(face => 'Times New Roman');

  $blue = Imager::Color->new("#0000FF");
  $font = Imager::Font->new(file  => 'pathtofont.ttf',
			    color => $blue,
			    size  => 30);

  ($neg_width,
   $global_descent,
   $pos_width,
   $global_ascent,
   $descent,
   $ascent,
   $advance_width,
   $right_bearing) = $font->bounding_box(string=>"Foo");

  my $bbox_object = $font->bounding_box(string=>"Foo");

  # documented in Imager::Draw
  $img->string(font  => $font,
	     text  => "Model-XYZ",
	     x     => 15,
	     y     => 40,
	     size  => 40,
	     color => $red,
	     aa    => 1);

=head1 DESCRIPTION

This module handles creating Font objects used by imager.  The module
also handles querying fonts for sizes and such.  If both T1lib and
freetype were avaliable at the time of compilation then Imager should
be able to work with both truetype fonts and t1 postscript fonts.  To
check if Imager is t1 or truetype capable you can use something like
this:

  use Imager;
  print "Has truetype"      if $Imager::formats{tt};
  print "Has t1 postscript" if $Imager::formats{t1};
  print "Has Win32 fonts"   if $Imager::formats{w32};
  print "Has Freetype2"     if $Imager::formats{ft2};

=over 4

=item new

This creates a font object to pass to functions that take a font argument.

  $font = Imager::Font->new(file  => 'denmark.ttf',
                            index => 0,
			    color => $blue,
			    size  => 30,
			    aa    => 1);

This creates a font which is the truetype font denmark.ttf.  It's
default color is $blue, default size is 30 pixels and it's rendered
antialised by default.  Imager can see which type of font a file is by
looking at the suffix of the filename for the font.  A suffix of 'ttf'
is taken to mean a truetype font while a suffix of 'pfb' is taken to
mean a t1 postscript font.  If Imager cannot tell which type a font is
you can tell it explicitly by using the C<type> parameter:

  $t1font = Imager::Font->new(file => 'fruitcase', type => 't1');
  $ttfont = Imager::Font->new(file => 'arglebarf', type => 'tt');

The C<index> parameter is used to select a single face from a font
file containing more than one face, for example, from a Macintosh font
suitcase or a .dfont file.

If any of the C<color>, C<size> or C<aa> parameters are omitted when
calling C<Imager::Font->new()> the they take the following values:

  color => Imager::Color->new(255, 0, 0, 0);  # this default should be changed
  size  => 15
  aa    => 0
  index => 0

To use Win32 fonts supply the facename of the font:

  $font = Imager::Font->new(face=>'Arial Bold Italic');

There isn't any access to other logical font attributes, but this
typically isn't necessary for Win32 TrueType fonts, since you can
contruct the full name of the font as above.

Other logical font attributes may be added if there is sufficient demand.

Parameters:

=over

=item *

file - name of the file to load the font from.

=item *

face - face name.  This is used only under Win32 to create a GDI based
font.  This is ignored if the C<file> parameter is supplied.

=item *

type - font driver to use.  Currently the permitted values for this are:

=over

=item *

tt - Freetype 1.x driver.  Supports TTF fonts.

=item *

t1 - T1 Lib driver.  Supports Postscript Type 1 fonts.  Allows for
synthesis of underline, strikethrough and overline.

=item *

ft2 - Freetype 2.x driver.  Supports many different font formats.
Also supports the transform() method.

=back

=item *

color - the default color used with this font.  Default: red.

=item *

size - the default size used with this font.  Default: 15.

=item *

utf8 - if non-zero then text supplied to $img->string(...) and
$font->bounding_box(...) is assumed to be UTF 8 encoded by default.

=item *

align - the default value for the $img->string(...) C<align>
parameter.  Default: 1.

=item *

vlayout - the default value for the $img->string(...) C<vlayout>
parameter.  Default: 0.

=item *

aa - the default value for the $im->string(...) C<aa> parameter.
Default: 0.

=item *

index - for font file containing multiple fonts this selects which
font to use.  This is useful for Macintosh DFON (.dfont) and suitcase
font files.

If you want to use a suitcase font you will need to tell Imager to use
the FreeType 2.x driver by setting C<type> to C<'ft2'>:

  my $font = Imager::Font->new(file=>$file, index => 1, type=>'ft2')
    or die Imager->errstr;

=back



=item bounding_box

Returns the bounding box for the specified string.  Example:

  my ($neg_width,
      $global_descent,
      $pos_width,
      $global_ascent,
      $descent,
      $ascent,
      $advance_width,
      $right_bearing) = $font->bounding_box(string => "A Fool");

  my $bbox_object = $font->bounding_box(string => "A Fool");

=over

=item C<$neg_width>

the relative start of a the string.  In some
cases this can be a negative number, in that case the first letter
stretches to the left of the starting position that is specified in
the string method of the Imager class

=item C<$global_descent> 

how far down the lowest letter of the entire font reaches below the
baseline (this is often j).

=item C<$pos_width>

how wide the string from
the starting position is.  The total width of the string is
C<$pos_width-$neg_width>.

=item C<$descent> 

=item C<$ascent> 

the same as <$global_descent> and <$global_ascent> except that they
are only for the characters that appear in the string.

=item C<$advance_width>

the distance from the start point that the next string output should
start at, this is often the same as C<$pos_width>, but can be
different if the final character overlaps the right side of its
character cell.

=item C<$right_bearing>

The distance from the right side of the final glyph to the end of the
advance width.  If the final glyph overflows the advance width this
value is negative.

=back

Obviously we can stuff all the results into an array just as well:

  @metrics = $font->bounding_box(string => "testing 123");

Note that extra values may be added, so $metrics[-1] isn't supported.
It's possible to translate the output by a passing coordinate to the
bounding box method:

  @metrics = $font->bounding_box(string => "testing 123", x=>45, y=>34);

This gives the bounding box as if the string had been put down at C<(x,y)>
By giving bounding_box 'canon' as a true value it's possible to measure
the space needed for the string:

  @metrics = $font->bounding_box(string=>"testing",size=>15,canon=>1);

This returns tha same values in $metrics[0] and $metrics[1],
but:

 $bbox[2] - horizontal space taken by glyphs
 $bbox[3] - vertical space taken by glyphs

Returns an L<Imager::Font::BBox> object in scalar context, so you can
avoid all those confusing indices.  This has methods as named above,
with some extra convenience methods.

Parameters are:

=over

=item *

string - the string to calculate the bounding box for.  Required.

=item *

size - the font size to use.  Default: value set in
Imager::Font->new(), or 15.

=item *

sizew - the font width to use.  Default to the value of the C<size>
parameter.

=item *

utf8 - For drivers that support it, treat the string as UTF8 encoded.
For versions of perl that support Unicode (5.6 and later), this will
be enabled automatically if the 'string' parameter is already a UTF8
string. See L<UTF8> for more information.  Default: the C<utf8> value
passed to Imager::Font->new(...) or 0.

=item *

x, y - offsets applied to @box[0..3] to give you a adjusted bounding
box.  Ignored in scalar context.

=item *

canon - if non-zero and the C<x>, C<y> parameters are not supplied,
then $pos_width and $global_ascent values will returned as the width
and height of the text instead.

=back

=item string

The $img->string(...) method is now documented in
L<Imager::Draw/string>

=item align(string=>$text, size=>$size, x=>..., y=>..., valign => ..., halign=>...)

Higher level text output - outputs the text aligned as specified
around the given point (x,y).

  # "Hello" centered at 100, 100 in the image.
  my ($left, $top, $right, $bottom) = 
    $font->align(string=>"Hello",
                 x=>100, y=>100, 
                 halign=>'center', valign=>'center', 
                 image=>$image);

Takes the same parameters as $font->draw(), and the following extra
parameters:

=over

=item valign

Possible values are:

=over

=item top

Point is at the top of the text.

=item bottom

Point is at the bottom of the text.

=item baseline

Point is on the baseline of the text (default.)

=item center

Point is vertically centered within the text.

=back

=item halign

=over

=item left

The point is at the left of the text.

=item start

The point is at the start point of the text.

=item center

The point is horizontally centered within the text.

=item right

The point is at the right end of the text.

=item end

The point is at the end point of the text.

=back

=item image

The image to draw to.  Set to C<undef> to avoid drawing but still
calculate the bounding box.

=back

Returns a list specifying the bounds of the drawn text.

=item dpi()

=item dpi(xdpi=>$xdpi, ydpi=>$ydpi)

=item dpi(dpi=>$dpi)

Set or retrieve the spatial resolution of the image in dots per inch.
The default is 72 dpi.

This isn't implemented for all font types yet.

Possible parameters are:

=over

=item *

xdpi, ydpi - set the horizontal and vertical resolution in dots per
inch.

=item *

dpi - set both horizontal and vertical resolution to this value.

=back

Returns a list containing the previous xdpi, ydpi values.

=item transform(matrix=>$matrix)

Applies a transformation to the font, where matrix is an array ref of
numbers representing a 2 x 3 matrix:

  [  $matrix->[0],  $matrix->[1],  $matrix->[2],
     $matrix->[3],  $matrix->[4],  $matrix->[5]   ]

Not all font types support transformations, these will return false.

It's possible that a driver will disable hinting if you use a
transformation, to prevent discontinuities in the transformations.
See the end of the test script t/t38ft2font.t for an example.

Currently only the ft2 (Freetype 2.x) driver supports the transform()
method.

See samples/slant_text.pl for a sample using this function.

Note that the transformation is done in font co-ordinates where y
increases as you move up, not image co-ordinates where y decreases as
you move up.

=item has_chars(string=>$text)

Checks if the characters in $text are defined by the font.

In a list context returns a list of true or false value corresponding
to the characters in $text, true if the character is defined, false if
not.  In scalar context returns a string of NUL or non-NUL
characters.  Supports UTF8 where the font driver supports UTF8.

Not all fonts support this method (use $font->can("has_chars") to
check.)

=over

=item *

string - string of characters to check for.  Required.  Must contain
at least one character.

=item *

utf8 - For drivers that support it, treat the string as UTF8 encoded.
For versions of perl that support Unicode (5.6 and later), this will
be enabled automatically if the 'string' parameter is already a UTF8
string. See L<UTF8> for more information.  Default: the C<utf8> value
passed to Imager::Font->new(...) or 0.

=back

=item face_name()

Returns the internal name of the face.  Not all font types support
this method yet.

=item glyph_names(string=>$string [, utf8=>$utf8 ][, reliable_only=>0 ] );

Returns a list of glyph names for each of the characters in the
string.  If the character has no name then C<undef> is returned for
the character.

Some font files do not include glyph names, in this case Freetype 2
will not return any names.  Freetype 1 can return standard names even
if there are no glyph names in the font.

Freetype 2 has an API function that returns true only if the font has
"reliable glyph names", unfortunately this always returns false for
TTF fonts.  This can avoid the check of this API by supplying
C<reliable_only> as 0.  The consequences of using this on an unknown
font may be unpredictable, since the Freetype documentation doesn't
say how those name tables are unreliable, or how FT2 handles them.

Both Freetype 1.x and 2.x allow support for glyph names to not be
included.

=item draw

This is used by Imager's string() method to implement drawing text.
See L<Imager::Draw/string>.

=back

=head1 MULTIPLE MASTER FONTS

The Freetype 2 driver supports multiple master fonts:

=over

=item is_mm()

Test if the font is a multiple master font.

=item mm_axes()

Returns a list of the axes that can be changes in the font.  Each
entry is an array reference which contains:

=over

=item 1.

Name of the axis.

=item 2.

minimum value for this axis.

=item 3.

maximum value for this axis

=back

=item set_mm_coords(coords=>\@values)

Blends an interpolated design from the master fonts.  @values must
contain as many values as there are axes in the font.

=back

For example, to select the minimum value in each axis:

  my @axes = $font->mm_axes;
  my @coords = map $_->[1], @axes;
  $font->set_mm_coords(coords=>\@coords);

It's possible other drivers will support multiple master fonts in the
future, check if your selected font object supports the is_mm() method
using the can() method.

=head1 UTF8

There are 2 ways of rendering Unicode characters with Imager:

=over

=item *

For versions of perl that support it, use perl's native UTF8 strings.
This is the simplest method.

=item *

Hand build your own UTF8 encoded strings.  Only recommended if your
version of perl has no UTF8 support.

=back

Imager won't construct characters for you, so if want to output
unicode character 00C3 "LATIN CAPITAL LETTER A WITH DIAERESIS", and
your font doesn't support it, Imager will I<not> build it from 0041
"LATIN CAPITAL LETTER A" and 0308 "COMBINING DIAERESIS".

To check if a driver supports UTF8 call the utf8 method:

=over

=item utf8

Return true if the font supports UTF8.

=back

=head2 Native UTF8 Support

If your version of perl supports UTF8 and the driver supports UTF8,
just use the $im->string() method, and it should do the right thing.

=head2 Build your own

In this case you need to build your own UTF8 encoded characters.

For example:

 $x = pack("C*", 0xE2, 0x80, 0x90); # character code 0x2010 HYPHEN

You need to be be careful with versions of perl that have UTF8
support, since your string may end up doubly UTF8 encoded.

For example:

 $x = "A\xE2\x80\x90\x41\x{2010}";
 substr($x, -1, 0) = ""; 
 # at this point $x is has the UTF8 flag set, but has 5 characters,
 # none, of which is the constructed UTF8 character

The test script t/t38ft2font.t has a small example of this after the 
comment:

  # an attempt using emulation of UTF8

=head1 DRIVER CONTROL

If you don't supply a 'type' parameter to Imager::Font->new(), but you
do supply a 'file' parameter, Imager will attempt to guess which font
driver to used based on the extension of the font file.

Since some formats can be handled by more than one driver, a priority
list is used to choose which one should be used, if a given format can
be handled by more than one driver.

=over

=item priorities

The current priorities can be retrieved with:

  @drivers = Imager::Font->priorities();

You can set new priorities and save the old priorities with:

  @old = Imager::Font->priorities(@drivers);

=back

If you supply driver names that are not currently supported, they will
be ignored.

Imager supports both T1Lib and Freetype2 for working with Type 1
fonts, but currently only T1Lib does any caching, so by default T1Lib
is given a higher priority.  Since Imager's Freetype2 support can also
do font transformations, you may want to give that a higher priority:

  my @old = Imager::Font->priorities(qw(tt ft2 t1));

=head1 AUTHOR

Arnar M. Hrafnkelsson, addi@umich.edu
And a great deal of help from others - see the README for a complete
list.

=head1 BUGS

You need to modify this class to add new font types.

The $pos_width member returned by the bounding_box() method has
historically returned different values from different drivers.  The
Freetype 1.x and 2.x, and the Win32 drivers return the max of the
advance width and the right edge of the right-most glyph.  The Type 1
driver always returns the right edge of the right-most glyph.

The newer advance_width and right_bearing values allow access to any
of the above.

=head1 REVISION

$Revision: 1263 $

=head1 SEE ALSO

Imager(3), Imager::Font::FreeType2(3), Imager::Font::Type1(3),
Imager::Font::Win32(3), Imager::Font::Truetype(3), Imager::Font::BBox(3)

 http://imager.perl.org/

=cut


