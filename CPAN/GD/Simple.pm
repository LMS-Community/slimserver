package GD::Simple;

=head1 NAME

GD::Simple - Simplified interface to GD library

=head1 SYNOPSIS

    use GD::Simple;

    # create a new image
    $img = GD::Simple->new(400,250);

    # draw a red rectangle with blue borders
    $img->bgcolor('red');
    $img->fgcolor('blue');
    $img->rectangle(10,10,50,50);

    # draw an empty rectangle with green borders
    $img->bgcolor(undef);
    $img->fgcolor('green');
    $img->rectangle(30,30,100,100);

    # move to (80,80) and draw a green line to (100,190)
    $img->moveTo(80,80);
    $img->lineTo(100,190);

    # draw a solid orange ellipse
    $img->moveTo(110,100);
    $img->bgcolor('orange');
    $img->fgcolor('orange');
    $img->ellipse(40,40);

    # draw a black filled arc
    $img->moveTo(150,150);
    $img->fgcolor('black');
    $img->arc(50,50,0,100,gdNoFill|gdEdged);

    # draw a string at (10,180) using the default
    # built-in font
    $img->moveTo(10,180);
    $img->string('This is very simple');

    # draw a string at (280,210) using 20 point
    # times italic, angled upward 90 degrees
    $img->moveTo(280,210);
    $img->font('Times:italic');
    $img->fontsize(20);
    $img->angle(-90);
    $img->string('This is very fancy');

    # some turtle graphics
    $img->moveTo(300,100);
    $img->penSize(3,3);
    $img->angle(0);
    $img->line(20);   # 20 pixels going to the right
    $img->turn(30);   # set turning angle to 30 degrees
    $img->line(20);   # 20 pixel line
    $img->line(20);
    $img->line(20);
    $img->turn(-90); # set turning angle to -90 degrees
    $img->line(50);  # 50 pixel line

    # draw a cyan polygon edged in blue
    my $poly = new GD::Polygon;
    $poly->addPt(150,100);
    $poly->addPt(199,199);
    $poly->addPt(100,199);
    $img->bgcolor('cyan');
    $img->fgcolor('blue');
    $img->penSize(1,1);
    $img->polygon($poly);

   # convert into png data
   print $img->png;

=head1 DESCRIPTION

GD::Simple is a subclass of the GD library that shortens many of the
long GD method calls by storing information about the pen color, size
and position in the GD object itself.  It also adds a small number of
"turtle graphics" style calls for those who prefer to work in polar
coordinates.  In addition, the library allows you to use symbolic
names for colors, such as "chartreuse", and will manage the colors for
you.

=head2 The Pen

GD::Simple maintains a "pen" whose settings are used for line- and
shape-drawing operations.  The pen has the following properties:

=over 4

=item fgcolor

The pen foreground color is the color of lines and the borders of
filled and unfilled shapes.

=item bgcolor

The pen background color is the color of the contents of filled
shapes.

=item pensize

The pen size is the width of the pen.  Larger sizes draw thicker
lines.

=item position

The pen position is its current position on the canvas in (X,Y)
coordinates.

=item angle

When drawing in turtle mode, the pen angle determines the current
direction of lines of relative length.

=item turn

When drawing in turtle mode, the turn determines the clockwise or
counterclockwise angle that the pen will turn before drawing the next
line.

=item font

The font to use when drawing text.  Both built-in bitmapped fonts and
TrueType fonts are supported.

=item fontsize

The size of the font to use when drawing with TrueType fonts.

=back

One sets the position and properties of the pen and then draws.  As
the drawing progresses, the position of the pen is updated.

=head2 Methods

GD::Simple introduces a number of new methods, a few of which have the
same name as GD::Image methods, and hence change their behavior. In
addition to these new methods, GD::Simple objects support all of the
GD::Image methods. If you make a method call that isn't directly
supported by GD::Simple, it refers the request to the underlying
GD::Image object.  Hence one can load a JPEG image into GD::Simple and
declare it to be TrueColor by using this call, which is effectively
inherited from GD::Image:

  my $img = GD::Simple->newFromJpeg('./myimage.jpg',1);

The rest of this section describes GD::Simple-specific methods.

=cut

use strict;
use GD;
use GD::Group;
use Math::Trig;
use Carp 'croak';

our @ISA = 'Exporter';
our @EXPORT    = @GD::EXPORT;
our @EXPORT_OK = @GD::EXPORT_OK;
our $AUTOLOAD;

my %COLORS;
my $IMAGECLASS = 'GD::Image';

sub AUTOLOAD {
  my $self = shift;
  my($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
  return if $func_name eq 'DESTROY';

  if (ref $self && exists $self->{gd}) {
    $self->{gd}->$func_name(@_);
  } else {
    my @result = $IMAGECLASS->$func_name(@_);
    if (UNIVERSAL::isa($result[0],'GD::Image')) {
      return $self->new($result[0]);
    } else {
      return @result;
    }
  }
}

=over 4

=item $img = GD::Simple->new($x,$y [,$truecolor])

=item $img = GD::Simple->new($gd)

Create a new GD::Simple object. There are two forms of new(). In the
first form, pass the width and height of the desired canvas, and
optionally a boolean flag to request a truecolor image. In the second
form, pass a previously-created GD::Image object.

=cut

# dual-purpose code - beware
sub new {
  my $pack = shift;

  unshift @_,(100,100) if @_ == 0;

  if (@_ >= 2) { # traditional GD::Image->new() call
    my $gd   = $IMAGECLASS->new(@_);
    my $self = $pack->new($gd);
    $self->clear;
    return $self;
  }

  if (@_ == 1) { # initialize from existing image
    my $gd   = shift;
    my $self = bless {
		      gd             => $gd,
		      xy             => [0,0],
		      font           => gdSmallFont,
		      fontsize       => 9,
		      turningangle   => 0,
		      angle          => 0,
		      pensize        => 1,
		     },$pack;
    $self->{bgcolor} = $self->translate_color(255,255,255);
    $self->{fgcolor} = $self->translate_color(0,0,0);
    return $self;
  }
}

=item GD::Simple->class('GD');

=item GD::Simple->class('GD::SVG');

Select whether new() should use GD or GD::SVG internally. Call
GD::Simple->class('GD::SVG') before calling new() if you wish to
generate SVG images.

If future GD subclasses are created, this method will subport them.

=cut

sub class {
  my $pack    = shift;
  if (@_) {
    $IMAGECLASS = shift;
    eval "require $IMAGECLASS; 1" or die $@;
    $IMAGECLASS = "$IMAGECLASS\:\:Image" 
      if $IMAGECLASS eq 'GD::SVG';
  }
  $IMAGECLASS;
}

=item $img->moveTo($x,$y)

This call changes the position of the pen without drawing. It moves
the pen to position ($x,$y) on the drawing canvas.

=cut

sub moveTo {
  my $self = shift;
  croak 'Usage GD::Simple->moveTo($x,$y)' unless @_ == 2;
  my ($x,$y) = @_;
  $self->{xy} = [$x,$y];
}

=item $img->move($dx,$dy)

=item $img->move($dr)

This call changes the position of the pen without drawing. When called
with two arguments it moves the pen $dx pixels to the right and $dy
pixels downward.  When called with one argument it moves the pen $dr
pixels along the vector described by the current pen angle.

=cut

sub move {
  my $self = shift;
  if (@_ == 1) { # polar coordinates -- this is r
    $self->{angle} += $self->{turningangle};
    my $angle = deg2rad($self->{angle});
    $self->{xy}[0] += $_[0] * cos($angle);
    $self->{xy}[1] += $_[0] * sin($angle);
  }
  elsif (@_ == 2) { # cartesian coordinates
    $self->{xy}[0] += $_[0];
    $self->{xy}[1] += $_[1];
  } else {
    croak 'Usage GD::Simple->move($dx,$dy) or move($r)';
  }
}

=item $img->lineTo($x,$y)

The lineTo() call simultaneously draws and moves the pen.  It draws a
line from the current pen position to the position defined by ($x,$y)
using the current pen size and color.  After drawing, the position of
the pen is updated to the new position.

=cut

sub lineTo {
  my $self = shift;
  croak 'Usage GD::Simple->lineTo($x,$y)' unless @_ == 2;
  $self->gd->line($self->curPos,@_,$self->fgcolor);
  $self->moveTo(@_);
}

=item $img->line($dx,$dy)

=item $img->line($dr)

The line() call simultaneously draws and moves the pen. When called
with two arguments it draws a line from the current position of the
pen to the position $dx pixels to the right and $dy pixels down.  When
called with one argument, it draws a line $dr pixels long along the
angle defined by the current pen angle.

=cut

sub line {
  my $self = shift;
  croak 'Usage GD::Simple->line($dx,$dy) or line($r)' unless @_ >= 1;
  my @curPos = $self->curPos;
  $self->move(@_);
  my @newPos = $self->curPos;
  $self->gd->line(@curPos,@newPos,$self->fgcolor);
}

=item $img->clear

This method clears the canvas by painting over it with the current
background color.

=cut

sub clear {
  my $self = shift;
  $self->gd->filledRectangle(0,0,$self->getBounds,$self->bgcolor);
}

=item $img->rectangle($x1,$y1,$x2,$y2)

This method draws the rectangle defined by corners ($x1,$y1),
($x2,$y2). The rectangle's edges are drawn in the foreground color and
its contents are filled with the background color. To draw a solid
rectangle set bgcolor equal to fgcolor. To draw an unfilled rectangle
(transparent inside), set bgcolor to undef.

=cut

sub rectangle {
  my $self = shift;
  croak 'Usage GD::Simple->rectangle($x1,$y1,$x2,$y2)' unless @_ == 4;
  my $gd = $self->gd;
  my ($bg,$fg) = ($self->bgcolor,$self->fgcolor);
  $gd->filledRectangle(@_,$bg) if defined $bg;
  $gd->rectangle(@_,$fg)       if defined $fg && (!defined $bg || $bg != $fg);
}

=item $img->ellipse($width,$height)

This method draws the ellipse centered at the current location with
width $width and height $height.  The ellipse's border is drawn in the
foreground color and its contents are filled with the background
color. To draw a solid ellipse set bgcolor equal to fgcolor. To draw
an unfilled ellipse (transparent inside), set bgcolor to undef.

=cut

sub ellipse {
  my $self = shift;
  croak 'Usage GD::Simple->ellipse($width,$height)' unless @_ == 2;
  my $gd = $self->gd;
  my ($bg,$fg) = ($self->bgcolor,$self->fgcolor);
  $gd->filledEllipse($self->curPos,@_,$bg) if defined $bg;
  $gd->ellipse($self->curPos,@_,$fg)       if defined $fg && (!defined $bg || $bg != $fg);
}

=item $img->arc($cx,$cy,$width,$height,$start,$end [,$style])

This method draws filled and unfilled arcs.  See L<GD> for a
description of the arguments. To draw a solid arc (such as a pie
wedge) set bgcolor equal to fgcolor. To draw an unfilled arc, set
bgcolor to undef.

=cut

sub arc {
  my $self = shift;
  croak 'Usage GD::Simple->arc($width,$height,$start,$end,$style)' unless @_ >= 4;
  my ($width,$height,$start,$end,$style) = @_;
  my $gd = $self->gd;
  my ($bg,$fg) = ($self->bgcolor,$self->fgcolor);
  my ($cx,$cy) = $self->curPos;

  if ($bg) {
    my @args = ($cx,$cy,$width,$height,$start,$end,$bg);
    push @args,$style if defined $style;
    $gd->filledArc(@args);
  } else {
    my @args = ($cx,$cy,$width,$height,$start,$end,$fg);
    $gd->arc(@args);
  }
}

=item $img->polygon($poly)

This method draws filled and unfilled polygon using the current
settings of fgcolor for the polygon border and bgcolor for the polygon
fill color.  See L<GD> for a description of creating polygons. To draw
a solid polygon set bgcolor equal to fgcolor. To draw an unfilled
polygon, set bgcolor to undef.

=cut

sub polygon {
  my $self = shift;
  croak 'Usage GD::Simple->polygon($poly)' unless @_ == 1;
  my $gd = $self->gd;
  my ($bg,$fg) = ($self->bgcolor,$self->fgcolor);
  $gd->filledPolygon(@_,$bg) if defined $bg;
  $gd->openPolygon(@_,$fg)   if defined $fg && (!defined $bg || $bg != $fg);
}

=item $img->polyline($poly)

This method draws polygons without closing the first and last vertices
(similar to GD::Image->unclosedPolygon()). It uses the fgcolor to draw
the line.

=cut

sub polyline {
  my $self = shift;
  croak 'Usage GD::Simple->polyline($poly)' unless @_ == 1;
  my $gd = $self->gd;
  my $fg = $self->fgcolor;
  $gd->unclosedPolygon(@_,$fg);
}

=item $img->string($string)

This method draws the indicated string starting at the current
position of the pen. The pen is moved to the end of the drawn string.
Depending on the font selected with the font() method, this will use
either a bitmapped GD font or a TrueType font.  The angle of the pen
will be consulted when drawing the text. For TrueType fonts, any angle
is accepted.  For GD bitmapped fonts, the angle can be either 0 (draw
horizontal) or -90 (draw upwards).

For consistency between the TrueType and GD font behavior, the string
is always drawn so that the current position of the pen corresponds to
the bottom left of the first character of the text.  This is different
from the GD behavior, in which the first character of bitmapped fonts
hangs down from the pen point.

This method returns a polygon indicating the bounding box of the
rendered text.  If an error occurred (such as invalid font
specification) it returns undef and an error message in $@.

=cut

sub string {
  my $self   = shift;
  my $string = shift;
  my $font   = $self->font;
  my @bounds;
  if (ref $font && $font->isa('GD::Font')) {
    my ($x,$y) = $self->curPos;
    if ($self->angle == -90) {
      $x -= $font->height;
      $y -= $font->width;
      $self->gd->stringUp($font,$x,$y,$string,$self->fgcolor);
      $self->{xy}[1] -= length($string) * $font->width;
      @bounds = ( ($self->{xy}[0],$y), ($x,$y), ($x,$self->{xy}[1]-$font->width), ($self->{xy}[0],$self->{xy}[1]-$font->width) );
    } else {
      $y -= $font->height;
      $self->gd->string($font,$x,$y,$string,$self->fgcolor);
      $self->{xy}[0] += length($string) * $font->width;
      @bounds = ( ($x,$self->{xy}[1]), ($self->{xy}[0],$self->{xy}[1]), ($self->{xy}[0],$y), ($x,$y) );
    }
  }
  else {
    $self->useFontConfig(1);
    @bounds   = $self->stringFT($self->fgcolor,$font,
				$self->fontsize,-deg2rad($self->angle), # -pi * $self->angle/180,
				$self->curPos,$string);
    return unless @bounds;
    my ($delta_x,$delta_y) = $self->_string_width(@bounds);
    $self->{xy}[0] += $delta_x;
    $self->{xy}[1] += $delta_y;
  }
  my $poly = GD::Polygon->new;
  while (@bounds) {
    $poly->addPt(splice(@bounds,0,2));
  }
  return $poly;
}

=item $metrics = $img->fontMetrics

=item ($metrics,$width,$height) = GD::Simple->fontMetrics($font,$fontsize,$string)

This method returns information about the current font, most commonly
a TrueType font. It can be invoked as an instance method (on a
previously-created GD::Simple object) or as a class method (on the
'GD::Simple' class).

When called as an instance method, fontMetrics() takes no arguments
and returns a single hash reference containing the metrics that
describe the currently selected font and size. The hash reference
contains the following information:

  xheight      the base height of the font from the bottom to the top of
               a lowercase 'm'

  ascent       the length of the upper stem of the lowercase 'd'

  descent      the length of the lower step of the lowercase 'j'

  lineheight   the distance from the bottom of the 'j' to the top of
               the 'd'

  leading      the distance between two adjacent lines

=cut

# return %$fontmetrics
# keys: 'ascent', 'descent', 'lineheight', 'xheight', 'leading'
sub fontMetrics {
  my $self   = shift;

  unless (ref $self) {  #class invocation -- create a scratch
    $self = $self->new;
    $self->font(shift)     if defined $_[0];
    $self->fontsize(shift) if defined $_[0];
  }

  my $font   = $self->font;
  my $metrics;

  if (ref $font && $font->isa('GD::Font')) {
    my $height = $font->height;
    $metrics = {ascent     => 0,
		descent    => 0,
		lineheight => $height,
		xheight    => $height,
		leading    => 0};
  }
  else {
    $self->useFontConfig(1);
    my @mbounds   = GD::Image->stringFT($self->fgcolor,$font,
					$self->fontsize,0,
					0,0,'m');
    my $xheight   = $mbounds[3]-$mbounds[5];
    my @jbounds   = GD::Image->stringFT($self->fgcolor,$font,
					$self->fontsize,0,
					0,0,'j');
    my $ascent    = $mbounds[7]-$jbounds[7];
    my $descent   = $jbounds[3]-$mbounds[3];

    my @mmbounds  = GD::Image->stringFT($self->fgcolor,$font,
					$self->fontsize,0,
					0,0,"m\nm");
    my $twolines  = $mmbounds[3]-$mmbounds[5];
    my $lineheight  = $twolines - 2*$xheight;
    my $leading     = $lineheight - $ascent - $descent;
    $metrics     = {ascent     => $ascent,
		    descent    => $descent,
		    lineheight => $lineheight,
		    xheight    => $xheight,
		    leading    => $leading};
  }

  if ((my $string = shift) && wantarray) {
    my ($width,$height) = $self->stringBounds($string);
    return ($metrics,abs($width),abs($height));
  }
  return $metrics;
}

=item ($delta_x,$delta_y)= $img->stringBounds($string)

This method indicates the X and Y offsets (which may be negative) that
will occur when the given string is drawn using the current font,
fontsize and angle. When the string is drawn horizontally, it gives
the width and height of the string's bounding box.

=cut

sub stringBounds {
  my $self = shift;
  my $string = shift;
  my $font   = $self->font;
  if (ref $font && $font->isa('GD::Font')) {
    if ($self->angle == -90) {
      return ($font->height,-length($string) * $font->width);
    } else {
      return (length($string) * $font->width,$font->height);
    }
  }
  else {
    $self->useFontConfig(1);
    my @bounds   = GD::Image->stringFT($self->fgcolor,$font,
				       $self->fontsize,-deg2rad($self->angle),
				       $self->curPos,$string);
    return $self->_string_width(@bounds);
  }
}

=item $delta_x = $img->stringWidth($string)

This method indicates the width of the string given the current font,
fontsize and angle. It is the same as ($img->stringBounds($string))[0]

=cut

sub stringWidth {
  return ((shift->stringBounds(@_))[0]);
}


sub _string_width {
  my $self   = shift;
  my @bounds = @_;
  my $delta_x = abs($bounds[2]-$bounds[0]);
  my $delta_y = abs($bounds[5]-$bounds[3]);
  my $angle   = $self->angle % 360;
  if ($angle >= 0 && $angle < 90) {
    return ($delta_x,$delta_y);

  } elsif ($angle >= 90 && $angle < 180) {
    return (-$delta_x,$delta_y);

  } elsif ($angle >= 180 && $angle < 270) {
    return (-$delta_x,-$delta_y);

  } elsif ($angle >= 270 && $angle < 360) {
    return ($delta_x,-$delta_y);
  }
}

=item ($x,$y) = $img->curPos

Return the current position of the pen.  Set the current position
using moveTo().

=cut

sub curPos {  @{shift->{xy}}; }

=item $font = $img->font([$newfont] [,$newsize])

Get or set the current font.  Fonts can be GD::Font objects, TrueType
font file paths, or fontconfig font patterns like "Times:italic" (see
L<fontconfig>). The latter feature requires that you have the
fontconfig library installed and are using libgd version 2.0.33 or
higher.

As a shortcut, you may pass two arguments to set the font and the
fontsize simultaneously. The fontsize is only valid when drawing with
TrueType fonts.

=cut

sub font {
  my $self = shift;
  $self->{font}     = shift if @_;
  $self->{fontsize} = shift if @_;
  $self->{font};
}

=item $size = $img->fontsize([$newfontsize])

Get or set the current font size.  This is only valid for TrueType
fonts.

=cut

sub fontsize {
  my $self = shift;
  $self->{fontsize} = shift if @_;
  $self->{fontsize};
}

=item $size = $img->penSize([$newpensize])

Get or set the current pen width for use during line drawing
operations.

=cut

sub penSize {
  my $self = shift;
  if (@_) {
    $self->{pensize} = shift;
    $self->gd->setThickness($self->{pensize});
  }
  $self->{pensize};
}

=item $angle = $img->angle([$newangle])

Set the current angle for use when calling line() or move() with a
single argument. 

Here is an example of using turn() and angle() together to draw an
octagon.  The first line drawn is the downward-slanting top right
edge.  The last line drawn is the horizontal top of the octagon.

  $img->moveTo(200,50);
  $img->angle(0);
  $img->turn(360/8);
  for (1..8) { $img->line(50) }

=cut

sub angle {
  my $self = shift;
  $self->{angle} = shift if @_;
  $self->{angle};
}

=item $angle = $img->turn([$newangle])

Get or set the current angle to turn prior to drawing lines.  This
value is only used when calling line() or move() with a single
argument.  The turning angle will be applied to each call to line() or
move() just before the actual drawing occurs.

Angles are in degrees.  Positive values turn the angle clockwise.

=cut

# degrees, not radians
sub turn {
  my $self = shift;
  $self->{turningangle} = shift if @_;
  $self->{turningangle};
}

=item $color = $img->fgcolor([$newcolor])

Get or set the pen's foreground color.  The current pen color can be
set by (1) using an (r,g,b) triple; (2) using a previously-allocated
color from the GD palette; or (3) by using a symbolic color name such
as "chartreuse."  The list of color names can be obtained using
color_names().

=cut

sub fgcolor {
  my $self = shift;
  $self->{fgcolor} = $self->translate_color(@_) if @_;
  $self->{fgcolor};
}

=item $color = $img->bgcolor([$newcolor])

Get or set the pen's background color.  The current pen color can be
set by (1) using an (r,g,b) triple; (2) using a previously-allocated
color from the GD palette; or (3) by using a symbolic color name such
as "chartreuse."  The list of color names can be obtained using
color_names().

=cut

sub bgcolor {
  my $self = shift;
  $self->{bgcolor} = $self->translate_color(@_) if @_;
  $self->{bgcolor};
}

=item $index = $img->translate_color(@args)

Translates a color into a GD palette or TrueColor index.  You may pass
either an (r,g,b) triple or a symbolic color name. If you pass a
previously-allocated index, the method will return it unchanged.

=cut

sub translate_color {
  my $self = shift;
  return unless defined $_[0];
  my ($r,$g,$b);
  if (@_ == 1 && $_[0] =~ /^-?\d+/) {  # previously allocated index
    return $_[0];
  }
  elsif (@_ == 3) {  # (rgb triplet)
    ($r,$g,$b) = @_;
  } else {
    $self->read_color_table unless %COLORS;
    die "unknown color" unless exists $COLORS{lc $_[0]};
    ($r,$g,$b) = @{$COLORS{lc $_[0]}};
  }
  return $self->colorResolve($r,$g,$b);
}

sub transparent {
  my $self = shift;
  my $index = $self->translate_color(@_);
  $self->gd->transparent($index);
}

=item $index = $img->alphaColor(@args,$alpha)

Creates an alpha color.  You may pass either an (r,g,b) triple or a
symbolic color name, followed by an integer indicating its
opacity. The opacity value ranges from 0 (fully opaque) to 127 (fully
transparent).

=cut

sub alphaColor {
  my $self = shift;
  return unless defined $_[0];
  my ($r,$g,$b,$a);
  if (@_ == 4) {  # (rgb triplet)
    ($r,$g,$b,$a) = @_;
  } else {
    $self->read_color_table unless %COLORS;
    die "unknown color" unless exists $COLORS{lc $_[0]};
    ($r,$g,$b) = @{$COLORS{lc $_[0]}};
    $a = $_[1];
  }
  return $self->colorAllocateAlpha($r,$g,$b,$a);
}

=item @names = GD::Simple->color_names

=item $translate_table = GD::Simple->color_names

Called in a list context, color_names() returns the list of symbolic
color names recognized by this module.  Called in a scalar context,
the method returns a hash reference in which the keys are the color
names and the values are array references containing [r,g,b] triples.

=cut

sub color_names {
  my $self = shift;
  $self->read_color_table unless %COLORS;
  return wantarray ? sort keys %COLORS : \%COLORS;
}

=item $gd = $img->gd

Return the internal GD::Image object.  Usually you will not need to
call this since all GD methods are automatically referred to this object.

=cut

sub gd { shift->{gd} }

sub read_color_table {
  my $class = shift;
  while (<DATA>) {
    chomp;
    last if /^__END__/;
    my ($name,$r,$g,$b) = split /\s+/;
    $COLORS{$name} = [hex $r,hex $g,hex $b];
  }
}

sub setBrush {
  my $self  = shift;
  my $brush = shift;
  if ($brush->isa('GD::Simple')) {
    $self->gd->setBrush($brush->gd);
  } else {
    $self->gd->setBrush($brush);
  }
}

=item ($red,$green,$blue) = GD::Simple->HSVtoRGB($hue,$saturation,$value)

Convert a Hue/Saturation/Value (HSV) color into an RGB triple. The
hue, saturation and value are integers from 0 to 255.

=cut

sub HSVtoRGB {
  my $self = shift;
  @_ == 3 or croak "Usage: GD::Simple->HSVtoRGB(\$hue,\$saturation,\$value)";

  my ($h,$s,$v)=@_;
  my ($r,$g,$b,$i,$f,$p,$q,$t);

  if( $s == 0 ) {
    ## achromatic (grey)
    return ($v,$v,$v);
  }
  $h %= 255;
  $s /= 255;                      ## scale saturation from 0.0-1.0
  $h /= 255;                      ## scale hue from 0 to 1.0
  $h *= 360;                      ## and now scale it to 0 to 360

  $h /= 60;                       ## sector 0 to 5
  $i = $h % 6;
  $f = $h - $i;                   ## factorial part of h
  $p = $v * ( 1 - $s );
  $q = $v * ( 1 - $s * $f );
  $t = $v * ( 1 - $s * ( 1 - $f ) );

  if($i<1) {
    $r = $v;
    $g = $t;
    $b = $p;
  } elsif($i<2){
    $r = $q;
    $g = $v;
    $b = $p;
  } elsif($i<3){
    $r = $p;
    $g = $v;
    $b = $t;
  } elsif($i<4){
    $r = $p;
    $g = $q;
    $b = $v;
  } elsif($i<5){
    $r = $t;
    $g = $p;
    $b = $v;
  } else {
    $r = $v;
    $g = $p;
    $b = $q;
  }
  return (int($r+0.5),int($g+0.5),int($b+0.5));
}

=item ($hue,$saturation,$value) = GD::Simple->RGBtoHSV($hue,$saturation,$value)

Convert a Red/Green/Blue (RGB) value into a Hue/Saturation/Value (HSV)
triple. The hue, saturation and value are integers from 0 to 255.

=back

=cut

sub RGBtoHSV {
  my $self = shift;
  my ($r, $g ,$bl) = @_;
  my ($min,undef,$max) = sort {$a<=>$b} ($r,$g,$bl);
  return (0,0,0) unless $max > 0;

  my $v = $max;
  my $s = 255 * ($max - $min)/$max;
  my $h;
  my $range = $max - $min;

  if ($range == 0) { # all colors are equal, so monochrome
    return (0,0,$max);
  }

  if ($max == $r) {
    $h = 60 * ($g-$bl)/$range;
  }
  elsif ($max == $g) {
    $h = 60 * ($bl-$r)/$range + 120;
  }
  else {
    $h = 60 * ($r-$g)/$range + 240;
  }

  $h = int($h*255/360 + 0.5);

  return ($h, $s, $v);
}

sub newGroup {
    my $self  = shift;
    return $self->GD::newGroup(@_);
}

1;

__DATA__
white                FF           FF            FF
black                00           00            00
aliceblue            F0           F8            FF
antiquewhite         FA           EB            D7
aqua                 00           FF            FF
aquamarine           7F           FF            D4
azure                F0           FF            FF
beige                F5           F5            DC
bisque               FF           E4            C4
blanchedalmond       FF           EB            CD
blue                 00           00            FF
blueviolet           8A           2B            E2
brown                A5           2A            2A
burlywood            DE           B8            87
cadetblue            5F           9E            A0
chartreuse           7F           FF            00
chocolate            D2           69            1E
coral                FF           7F            50
cornflowerblue       64           95            ED
cornsilk             FF           F8            DC
crimson              DC           14            3C
cyan                 00           FF            FF
darkblue             00           00            8B
darkcyan             00           8B            8B
darkgoldenrod        B8           86            0B
darkgray             A9           A9            A9
darkgreen            00           64            00
darkkhaki            BD           B7            6B
darkmagenta          8B           00            8B
darkolivegreen       55           6B            2F
darkorange           FF           8C            00
darkorchid           99           32            CC
darkred              8B           00            00
darksalmon           E9           96            7A
darkseagreen         8F           BC            8F
darkslateblue        48           3D            8B
darkslategray        2F           4F            4F
darkturquoise        00           CE            D1
darkviolet           94           00            D3
deeppink             FF           14            100
deepskyblue          00           BF            FF
dimgray              69           69            69
dodgerblue           1E           90            FF
firebrick            B2           22            22
floralwhite          FF           FA            F0
forestgreen          22           8B            22
fuchsia              FF           00            FF
gainsboro            DC           DC            DC
ghostwhite           F8           F8            FF
gold                 FF           D7            00
goldenrod            DA           A5            20
gray                 80           80            80
green                00           80            00
greenyellow          AD           FF            2F
honeydew             F0           FF            F0
hotpink              FF           69            B4
indianred            CD           5C            5C
indigo               4B           00            82
ivory                FF           FF            F0
khaki                F0           E6            8C
lavender             E6           E6            FA
lavenderblush        FF           F0            F5
lawngreen            7C           FC            00
lemonchiffon         FF           FA            CD
lightblue            AD           D8            E6
lightcoral           F0           80            80
lightcyan            E0           FF            FF
lightgoldenrodyellow FA           FA            D2
lightgreen           90           EE            90
lightgrey            D3           D3            D3
lightpink            FF           B6            C1
lightsalmon          FF           A0            7A
lightseagreen        20           B2            AA
lightskyblue         87           CE            FA
lightslategray       77           88            99
lightsteelblue       B0           C4            DE
lightyellow          FF           FF            E0
lime                 00           FF            00
limegreen            32           CD            32
linen                FA           F0            E6
magenta              FF           00            FF
maroon               80           00            00
mediumaquamarine     66           CD            AA
mediumblue           00           00            CD
mediumorchid         BA           55            D3
mediumpurple         100          70            DB
mediumseagreen       3C           B3            71
mediumslateblue      7B           68            EE
mediumspringgreen    00           FA            9A
mediumturquoise      48           D1            CC
mediumvioletred      C7           15            85
midnightblue         19           19            70
mintcream            F5           FF            FA
mistyrose            FF           E4            E1
moccasin             FF           E4            B5
navajowhite          FF           DE            AD
navy                 00           00            80
oldlace              FD           F5            E6
olive                80           80            00
olivedrab            6B           8E            23
orange               FF           A5            00
orangered            FF           45            00
orchid               DA           70            D6
palegoldenrod        EE           E8            AA
palegreen            98           FB            98
paleturquoise        AF           EE            EE
palevioletred        DB           70            100
papayawhip           FF           EF            D5
peachpuff            FF           DA            B9
peru                 CD           85            3F
pink                 FF           C0            CB
plum                 DD           A0            DD
powderblue           B0           E0            E6
purple               80           00            80
red                  FF           00            00
rosybrown            BC           8F            8F
royalblue            41           69            E1
saddlebrown          8B           45            13
salmon               FA           80            72
sandybrown           F4           A4            60
seagreen             2E           8B            57
seashell             FF           F5            EE
sienna               A0           52            2D
silver               C0           C0            C0
skyblue              87           CE            EB
slateblue            6A           5A            CD
slategray            70           80            90
snow                 FF           FA            FA
springgreen          00           FF            7F
steelblue            46           82            B4
tan                  D2           B4            8C
teal                 00           80            80
thistle              D8           BF            D8
tomato               FF           63            47
turquoise            40           E0            D0
violet               EE           82            EE
wheat                F5           DE            B3
whitesmoke           F5           F5            F5
yellow               FF           FF            00
yellowgreen          9A           CD            32
gradient1	00 ff 00
gradient2	0a ff 00
gradient3	14 ff 00
gradient4	1e ff 00
gradient5	28 ff 00
gradient6	32 ff 00
gradient7	3d ff 00
gradient8	47 ff 00
gradient9	51 ff 00
gradient10	5b ff 00
gradient11	65 ff 00
gradient12	70 ff 00
gradient13	7a ff 00
gradient14	84 ff 00
gradient15	8e ff 00
gradient16	99 ff 00
gradient17	a3 ff 00
gradient18	ad ff 00
gradient19	b7 ff 00
gradient20	c1 ff 00
gradient21	cc ff 00
gradient22	d6 ff 00
gradient23	e0 ff 00
gradient24	ea ff 00
gradient25	f4 ff 00
gradient26	ff ff 00
gradient27	ff f4 00
gradient28	ff ea 00
gradient29	ff e0 00
gradient30	ff d6 00
gradient31	ff cc 00
gradient32	ff c1 00
gradient33	ff b7 00
gradient34	ff ad 00
gradient35	ff a3 00
gradient36	ff 99 00
gradient37	ff 8e 00
gradient38	ff 84 00
gradient39	ff 7a 00
gradient40	ff 70 00
gradient41	ff 65 00
gradient42	ff 5b 00
gradient43	ff 51 00
gradient44	ff 47 00
gradient45	ff 3d 00
gradient46	ff 32 00
gradient47	ff 28 00
gradient48	ff 1e 00
gradient49	ff 14 00
gradient50	ff 0a 00
__END__

=head1 COLORS

This script will create an image showing all the symbolic colors.

 #!/usr/bin/perl

 use strict;
 use GD::Simple;

 my @color_names = GD::Simple->color_names;
 my $cols = int(sqrt(@color_names));
 my $rows = int(@color_names/$cols)+1;

 my $cell_width    = 100;
 my $cell_height   = 50;
 my $legend_height = 16;
 my $width       = $cols * $cell_width;
 my $height      = $rows * $cell_height;

 my $img = GD::Simple->new($width,$height);
 $img->font(gdSmallFont);

 for (my $c=0; $c<$cols; $c++) {
   for (my $r=0; $r<$rows; $r++) {
     my $color = $color_names[$c*$rows + $r] or next;
     my @topleft  = ($c*$cell_width,$r*$cell_height);
     my @botright = ($topleft[0]+$cell_width,$topleft[1]+$cell_height-$legend_height);
     $img->bgcolor($color);
     $img->fgcolor($color);
     $img->rectangle(@topleft,@botright);
     $img->moveTo($topleft[0]+2,$botright[1]+$legend_height-2);
     $img->fgcolor('black');
     $img->string($color);
   }
 }

 print $img->png;

=head1 AUTHOR

The GD::Simple module is copyright 2004, Lincoln D. Stein.  It is
distributed under the same terms as Perl itself.  See the "Artistic
License" in the Perl source code distribution for licensing terms.

The latest versions of GD.pm are available at

  http://stein.cshl.org/WWW/software/GD

=head1 SEE ALSO

L<GD>,
L<GD::Polyline>,
L<GD::SVG>,
L<Image::Magick>

=cut
