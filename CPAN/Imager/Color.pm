package Imager::Color;

use Imager;
use strict;
use vars qw($VERSION);

$VERSION = "1.010";

# It's just a front end to the XS creation functions.

# used in converting hsv to rgb
my @hsv_map = 
  (
   'vkm', 'nvm', 'mvk', 'mnv', 'kmv', 'vmn'
  );

sub _hsv_to_rgb {
  my ($hue, $sat, $val) = @_;

  # HSV conversions from pages 401-403 "Procedural Elements for Computer 
  # Graphics", 1985, ISBN 0-07-053534-5.

  my @result;
  if ($sat <= 0) {
    return ( 255 * $val, 255 * $val, 255 * $val );
  }
  else {
    $val >= 0 or $val = 0;
    $val <= 1 or $val = 1;
    $sat <= 1 or $sat = 1;
    $hue >= 360 and $hue %= 360;
    $hue < 0 and $hue += 360;
    $hue /= 60.0;
    my $i = int($hue);
    my $f = $hue - $i;
    $val *= 255;
    my $m = $val * (1.0 - $sat);
    my $n = $val * (1.0 - $sat * $f);
    my $k = $val * (1.0 - $sat * (1 - $f));
    my $v = $val;
    my %fields = ( 'm'=>$m, 'n'=>$n, 'v'=>$v, 'k'=>$k, );
    return @fields{split //, $hsv_map[$i]};
  }
}

# cache of loaded gimp files
# each key is a filename, under each key is a hashref with the following
# keys:
#   mod_time => last mod_time of file
#   colors => hashref name to arrayref of colors
my %gimp_cache;

# palette search locations
# this is pretty rude
# $HOME is replaced at runtime
my @gimp_search =
  (
   '$HOME/.gimp-1.2/palettes/Named_Colors',
   '$HOME/.gimp-1.1/palettes/Named_Colors',
   '$HOME/.gimp/palettes/Named_Colors',
   '/usr/share/gimp/1.2/palettes/Named_Colors',
   '/usr/share/gimp/1.1/palettes/Named_Colors',
   '/usr/share/gimp/palettes/Named_Colors',
  );

sub _load_gimp_palette {
  my ($filename) = @_;

  if (open PAL, "< $filename") {
    my $hdr = <PAL>;
    chomp $hdr;
    unless ($hdr =~ /GIMP Palette/) {
      close PAL;
      $Imager::ERRSTR = "$filename is not a GIMP palette file";
      return;
    }
    my $line;
    my %pal;
    my $mod_time = (stat PAL)[9];
    while (defined($line = <PAL>)) {
      next if $line =~ /^#/ || $line =~ /^\s*$/;
      chomp $line;
      my ($r,$g, $b, $name) = split ' ', $line, 4;
      if ($name) {
        $name =~ s/\s*\([\d\s]+\)\s*$//;
        $pal{lc $name} = [ $r, $g, $b ];
      }
    }
    close PAL;

    $gimp_cache{$filename} = { mod_time=>$mod_time, colors=>\%pal };

    return 1;
  }
  else {
    $Imager::ERRSTR = "Cannot open palette file $filename: $!";
    return;
  }
}

sub _get_gimp_color {
  my %args = @_;

  my $filename;
  if ($args{palette}) {
    $filename = $args{palette};
  }
  else {
    # try to make one up - this is intended to die if tainting is
    # enabled and $ENV{HOME} is tainted.  To avoid that untaint $ENV{HOME}
    # or set the palette parameter
    for my $attempt (@gimp_search) {
      my $work = $attempt; # don't modify the source array
      $work =~ /\$HOME/ && !defined $ENV{HOME}
	and next;
      $work =~ s/\$HOME/$ENV{HOME}/;
      if (-e $work) {
        $filename = $work;
        last;
      }
    }
    if (!$filename) {
      $Imager::ERRSTR = "No GIMP palette found";
      return ();
    }
  }

  if ((!$gimp_cache{$filename} 
      || (stat $filename)[9] != $gimp_cache{$filename})
     && !_load_gimp_palette($filename)) {
    return ();
  }

  if (!$gimp_cache{$filename}{colors}{lc $args{name}}) {
    $Imager::ERRSTR = "Color '$args{name}' isn't in $filename";
    return ();
  }

  return @{$gimp_cache{$filename}{colors}{lc $args{name}}};
}

my @x_search = 
  (
   '/usr/share/X11/rgb.txt', # newer Xorg X11 dists use this
   '/usr/lib/X11/rgb.txt', # seems fairly standard
   '/usr/local/lib/X11/rgb.txt', # seems possible
   '/usr/X11R6/lib/X11/rgb.txt', # probably the same as the first
   '/usr/openwin/lib/rgb.txt',
   '/usr/openwin/lib/X11/rgb.txt',
  );

# called by the test code to check if we can test this stuff
sub _test_x_palettes {
  @x_search;
}

# x rgb.txt cache
# same structure as %gimp_cache
my %x_cache;

sub _load_x_rgb {
  my ($filename) = @_;

  local *RGB;
  if (open RGB, "< $filename") {
    my $line;
    my %pal;
    my $mod_time = (stat RGB)[9];
    while (defined($line = <RGB>)) {
      # the version of rgb.txt supplied with GNU Emacs uses # for comments
      next if $line =~ /^[!#]/ || $line =~ /^\s*$/;
      chomp $line;
      my ($r,$g, $b, $name) = split ' ', $line, 4;
      if ($name) {
        $pal{lc $name} = [ $r, $g, $b ];
      }
    }
    close RGB;

    $x_cache{$filename} = { mod_time=>$mod_time, colors=>\%pal };

    return 1;
  }
  else {
    $Imager::ERRSTR = "Cannot open palette file $filename: $!";
    return;
  }
}

sub _get_x_color {
  my %args = @_;

  my $filename;
  if ($args{palette}) {
    $filename = $args{palette};
  }
  else {
    for my $attempt (@x_search) {
      if (-e $attempt) {
        $filename = $attempt;
        last;
      }
    }
    if (!$filename) {
      $Imager::ERRSTR = "No X rgb.txt palette found";
      return ();
    }
  }

  if ((!$x_cache{$filename} 
      || (stat $filename)[9] != $x_cache{$filename})
     && !_load_x_rgb($filename)) {
    return ();
  }

  if (!$x_cache{$filename}{colors}{lc $args{name}}) {
    $Imager::ERRSTR = "Color '$args{name}' isn't in $filename";
    return ();
  }

  return @{$x_cache{$filename}{colors}{lc $args{name}}};
}

# Parse color spec into an a set of 4 colors

sub _pspec {
  return (@_,255) if @_ == 3 && !grep /[^\d.+eE-]/, @_;
  return (@_    ) if @_ == 4 && !grep /[^\d.+eE-]/, @_;
  if ($_[0] =~ 
      /^\#?([\da-f][\da-f])([\da-f][\da-f])([\da-f][\da-f])([\da-f][\da-f])/i) {
    return (hex($1),hex($2),hex($3),hex($4));
  }
  if ($_[0] =~ /^\#?([\da-f][\da-f])([\da-f][\da-f])([\da-f][\da-f])/i) {
    return (hex($1),hex($2),hex($3),255);
  }
  if ($_[0] =~ /^\#([\da-f])([\da-f])([\da-f])$/i) {
    return (hex($1) * 17, hex($2) * 17, hex($3) * 17, 255);
  }
  my %args;
  if (@_ == 1) {
    # a named color
    %args = ( name => @_ );
  }
  else {
    %args = @_;
  }
  my @result;
  if (exists $args{gray}) {
    @result = $args{gray};
  }
  elsif (exists $args{grey}) {
    @result = $args{grey};
  }
  elsif ((exists $args{red} || exists $args{r}) 
         && (exists $args{green} || exists $args{g})
         && (exists $args{blue} || exists $args{b})) {
    @result = ( exists $args{red} ? $args{red} : $args{r},
                exists $args{green} ? $args{green} : $args{g},
                exists $args{blue} ? $args{blue} : $args{b} );
  }
  elsif ((exists $args{hue} || exists $args{h}) 
         && (exists $args{saturation} || exists $args{'s'})
         && (exists $args{value} || exists $args{v})) {
    my $hue = exists $args{hue}        ? $args{hue}        : $args{h};
    my $sat = exists $args{saturation} ? $args{saturation} : $args{'s'};
    my $val = exists $args{value}      ? $args{value}      : $args{v};

    @result = _hsv_to_rgb($hue, $sat, $val);
  }
  elsif (exists $args{web}) {
    if ($args{web} =~ /^#?([\da-f][\da-f])([\da-f][\da-f])([\da-f][\da-f])$/i) {
      @result = (hex($1),hex($2),hex($3));
    }
    elsif ($args{web} =~ /^#?([\da-f])([\da-f])([\da-f])$/i) {
      @result = (hex($1) * 17, hex($2) * 17, hex($3) * 17);
    }
  }
  elsif ($args{name}) {
    unless (@result = _get_gimp_color(%args)) {
      unless (@result = _get_x_color(%args)) {
        require Imager::Color::Table;
        unless (@result = Imager::Color::Table->get($args{name})) {
          $Imager::ERRSTR = "No color named $args{name} found";
          return ();
        }
      }
    }
  }
  elsif ($args{gimp}) {
    @result = _get_gimp_color(name=>$args{gimp}, %args);
  }
  elsif ($args{xname}) {
    @result = _get_x_color(name=>$args{xname}, %args);
  }
  elsif ($args{builtin}) {
    require Imager::Color::Table;
    @result = Imager::Color::Table->get($args{builtin});
  }
  elsif ($args{rgb}) {
    @result = @{$args{rgb}};
  }
  elsif ($args{rgba}) {
    @result = @{$args{rgba}};
    return @result if @result == 4;
  }
  elsif ($args{hsv}) {
    @result = _hsv_to_rgb(@{$args{hsv}});
  }
  elsif ($args{channels}) {
    return @{$args{channels}};
  }
  elsif (exists $args{channel0} || $args{c0}) {
    my $i = 0;
    while (exists $args{"channel$i"} || exists $args{"c$i"}) {
      push(@result, 
           exists $args{"channel$i"} ? $args{"channel$i"} : $args{"c$i"});
      ++$i;
    }
  }
  else {
    $Imager::ERRSTR = "No color specification found";
    return ();
  }
  if (@result) {
    if (exists $args{alpha} || exists $args{a}) {
      push(@result, exists $args{alpha} ? $args{alpha} : $args{a});
    }
    while (@result < 4) {
      push(@result, 255);
    }
    return @result;
  }
  return ();
}

sub new {
  shift; # get rid of class name.
  my @arg = _pspec(@_);
  return @arg ? new_internal($arg[0],$arg[1],$arg[2],$arg[3]) : ();
}

sub set {
  my $self = shift;
  my @arg = _pspec(@_);
  return @arg ? set_internal($self, $arg[0],$arg[1],$arg[2],$arg[3]) : ();
}

sub equals {
  my ($self, %opts) = @_;

  my $other = $opts{other}
    or return Imager->_set_error("'other' parameter required");
  my $ignore_alpha = $opts{ignore_alpha} || 0;

  my @left = $self->rgba;
  my @right = $other->rgba;
  my $last_chan = $ignore_alpha ? 2 : 3;
  for my $ch (0 .. $last_chan) {
    $left[$ch] == $right[$ch]
      or return;
  }
  
  return 1;
}

1;

__END__

=head1 NAME

Imager::Color - Color handling for Imager.

=head1 SYNOPSIS

  $color = Imager::Color->new($red, $green, $blue);
  $color = Imager::Color->new($red, $green, $blue, $alpha);
  $color = Imager::Color->new("#C0C0FF"); # html color specification

  $color->set($red, $green, $blue);
  $color->set($red, $green, $blue, $alpha);
  $color->set("#C0C0FF"); # html color specification

  ($red, $green, $blue, $alpha) = $color->rgba();
  @hsv = $color->hsv(); # not implemented but proposed

  $color->info();

  if ($color->equals(other=>$other_color)) { 
    ...
  }


=head1 DESCRIPTION

This module handles creating color objects used by imager.  The idea is
that in the future this module will be able to handle colorspace calculations
as well.

An Imager color consists of up to four components, each in the range 0
to 255. Unfortunately the meaning of the components can change
depending on the type of image you're dealing with:

=over

=item *

for 3 or 4 channel images the color components are red, green, blue,
alpha.

=item *

for 1 or 2 channel images the color components are gray, alpha, with
the other two components ignored.

=back

An alpha value of zero is fully transparent, an alpha value of 255 is
fully opaque.

=head1 METHODS

=over 4

=item new

This creates a color object to pass to functions that need a color argument.

=item set

This changes an already defined color.  Note that this does not affect any places
where the color has been used previously.

=item rgba

This returns the rgba code of the color the object contains.

=item info

Calling info merely dumps the relevant colorcode to the log.

=item equals(other=>$other_color)

=item equals(other=>$other_color, ignore_alpha=>1)

Compares $self and color $other_color returning true if the color
components are the same.

Compares all four channels unless C<ignore_alpha> is set.  If
C<ignore_alpha> is set only the first three channels are compared.

=back

You can specify colors in several different ways, you can just supply
simple values:

=over

=item *

simple numeric parameters - if you supply 3 or 4 numeric arguments, you get a color made up of those RGB (and possibly A) components.

=item *

a six hex digit web color, either 'RRGGBB' or '#RRGGBB'

=item *

an eight hex digit web color, either 'RRGGBBAA' or '#RRGGBBAA'.

=item *

a 3 hex digit web color, '#RGB' - a value of F becomes 255.

=item *

a color name, from whichever of the gimp Named_Colors file or X
rgb.txt is found first.  The same as using the name keyword.

=back

You can supply named parameters:

=over

=item *

'red', 'green' and 'blue', optionally shortened to 'r', 'g' and 'b'.
The color components in the range 0 to 255.

 # all of the following are equivalent
 my $c1 = Imager::Color->new(red=>100, blue=>255, green=>0);
 my $c2 = Imager::Color->new(r=>100, b=>255, g=>0);
 my $c3 = Imager::Color->new(r=>100, blue=>255, g=>0);

=item *

'hue', 'saturation' and 'value', optionally shortened to 'h', 's' and
'v', to specify a HSV color.  0 <= hue < 360, 0 <= s <= 1 and 0 <= v
<= 1.

  # the same as RGB(127,255,127)
  my $c1 = Imager::Color->new(hue=>120, v=>1, s=>0.5);
  my $c1 = Imager::Color->new(hue=>120, value=>1, saturation=>0.5);

=item *

'web', which can specify a 6 or 3 hex digit web color, in any of the
forms '#RRGGBB', '#RGB', 'RRGGBB' or 'RGB'.

  my $c1 = Imager::Color->new(web=>'#FFC0C0'); # pale red

=item *

'gray' or 'grey' which specifies a single channel, from 0 to 255.

  # exactly the same
  my $c1 = Imager::Color->new(gray=>128);
  my $c1 = Imager::Color->new(grey=>128);

=item *

'rgb' which takes a 3 member arrayref, containing each of the red,
green and blue values.

  # the same
  my $c1 = Imager::Color->new(rgb=>[255, 100, 0]);
  my $c1 = Imager::Color->new(r=>255, g=>100, b=>0);

=item *

'hsv' which takes a 3 member arrayref, containting each of hue,
saturation and value.

  # the same
  my $c1 = Imager::Color->new(hsv=>[120, 0.5, 1]);
  my $c1 = Imager::Color->new(hue=>120, v=>1, s=>0.5);

=item *

'gimp' which specifies a color from a GIMP palette file.  You can
specify the filename of the palette file with the 'palette' parameter,
or let Imager::Color look in various places, typically
"$HOME/gimp-1.x/palettes/Named_Colors" with and without the version
number, and in /usr/share/gimp/palettes/.  The palette file must have
color names.

  my $c1 = Imager::Color->new(gimp=>'snow');
  my $c1 = Imager::Color->new(gimp=>'snow', palette=>'testimg/test_gimp_pal);

=item *

'xname' which specifies a color from an X11 rgb.txt file.  You can
specify the filename of the rgb.txt file with the 'palette' parameter,
or let Imager::Color look in various places, typically
'/usr/lib/X11/rgb.txt'.

  my $c1 = Imager::Color->new(xname=>'blue') # usually RGB(0, 0, 255)

=item *

'builtin' which specifies a color from the built-in color table in
Imager::Color::Table.  The colors in this module are the same as the
default X11 rgb.txt file.

  my $c1 = Imager::Color->new(builtin=>'black') # always RGB(0, 0, 0)

=item *

'name' which specifies a name from either a GIMP palette, an X rgb.txt
file or the built-in color table, whichever is found first.

=item *

'channel0', 'channel1', etc, each of which specifies a single channel.  These can be abbreviated to 'c0', 'c1' etc.

=item * 

'channels' which takes an arrayref of the channel values.

=back

Optionally you can add an alpha channel to a color with the 'alpha' or
'a' parameter.

These color specifications can be used for both constructing new
colors with the new() method and modifying existing colors with the
set() method.

=head1 AUTHOR

Arnar M. Hrafnkelsson, addi@umich.edu
And a great deal of help from others - see the README for a complete
list.

=head1 SEE ALSO

Imager(3), Imager::Color
http://imager.perl.org/

=cut
