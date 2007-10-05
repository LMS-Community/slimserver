############################################################################
#
# Polyline.pm
#
# Author:	Dan Harasty
# Email:	harasty@cpan.org
# Version:	0.2
# Date:		2002/08/06
#
# For usage documentation: see POD at end of file
#
# For changes: see "Changes" file included with distribution
#

use strict;

package GD::Polyline;

############################################################################
#
# GD::Polyline
#
############################################################################
#
# What's this?  A class with nothing but a $VERSION and and @ISA?
# Below, this module overrides and adds several modules to 
# the parent class, GD::Polygon.  Those updated/new methods 
# act on polygons and polylines, and sometimes those behaviours
# vary slightly based on whether the object is a polygon or polyine.
#

use vars qw($VERSION @ISA);
$VERSION = "0.2";
@ISA = qw(GD::Polygon);


package GD::Polygon;

############################################################################
#
# new methods on GD::Polygon
#
############################################################################

use GD;
use Carp 'croak','carp';

use vars qw($bezSegs $csr);
$bezSegs = 20;	# number of bezier segs -- number of segments in each portion of the spline produces by toSpline()
$csr = 1/3;		# control seg ratio -- the one possibly user-tunable parameter in the addControlPoints() algorithm


sub rotate {
    my ($self, $angle, $cx, $cy) = @_;
    $self->offset(-$cx,-$cy) if $cx or $cy;
    $self->transform(cos($angle),sin($angle),-sin($angle),cos($angle),$cx,$cy);
}

sub centroid {
    my ($self, $scale) = @_;
    my ($cx,$cy);
    $scale = 1 unless defined $scale;
    
    map {$cx += $_->[0]; $cy += $_->[1]} $self->vertices();
    
    $cx *= $scale / $self->length();
    $cy *= $scale / $self->length();

	return ($cx, $cy);    
}


sub segLength {
    my $self = shift;
    my @points = $self->vertices();

	my ($p1, $p2, @segLengths);
	
	$p1 = shift @points;
	
	# put the first vertex on the end to "close" a polygon, but not a polyline
	push @points, $p1 unless $self->isa('GD::Polyline');
	
	while ($p2 = shift @points) {
		push @segLengths, _len($p1, $p2);
		$p1 = $p2;
	}
	
	return @segLengths if wantarray;
	
	my $sum;
	map {$sum += $_} @segLengths;
	return $sum;
}

sub segAngle {
    my $self = shift;
    my @points = $self->vertices();

	my ($p1, $p2, @segAngles);
	
	$p1 = shift @points;
	
	# put the first vertex on the end to "close" a polygon, but not a polyline
	push @points, $p1 unless $self->isa('GD::Polyline');
	
	while ($p2 = shift @points) {
		push @segAngles, _angle_reduce2(_angle($p1, $p2));
		$p1 = $p2;
	}
	
	return @segAngles;
}

sub vertexAngle {
    my $self = shift;
    my @points = $self->vertices();

	my ($p1, $p2, $p3, @vertexAngle);

	$p1 = $points[$#points];	# last vertex
	$p2 = shift @points;		# current point -- the first vertex

	# put the first vertex on the end to "close" a polygon, but not a polyline
	push @points, $p2 unless $self->isa('GD::Polyline');
	
	while ($p3 = shift @points) {
		push @vertexAngle, _angle_reduce2(_angle($p1, $p2, $p3));
		($p1, $p2) = ($p2, $p3);
	}
	
	$vertexAngle[0] = undef if defined $vertexAngle[0] and $self->isa("GD::Polyline");
	
	return @vertexAngle if wantarray;
	
}



sub toSpline {
    my $self = shift;
    my @points = $self->vertices();

	# put the first vertex on the end to "close" a polygon, but not a polyline    
    push @points, [$self->getPt(0)] unless $self->isa('GD::Polyline');

	unless (@points > 1 and @points % 3 == 1) {
	    carp "Attempt to call toSpline() with invalid set of control points";
		return undef;
	}
    
    my ($ap1, $dp1, $dp2, $ap2); # ap = anchor point, dp = director point
    $ap1 = shift @points;

	my $bez = new ref($self);

    $bez->addPt(@$ap1);
    
    while (@points) {
    	($dp1, $dp2, $ap2) = splice(@points, 0, 3);
    	
		for (1..$bezSegs) {
			my ($t0, $t1, $c1, $c2, $c3, $c4, $x, $y); 
			
			$t1 = $_/$bezSegs;
			$t0 = (1 - $t1);
			
			# possible optimization:
			# these coefficient could be calculated just once and 
			# cached in an array for a given value of $bezSegs
			
			$c1 =     $t0 * $t0 * $t0;
			$c2 = 3 * $t0 * $t0 * $t1;
			$c3 = 3 * $t0 * $t1 * $t1;
			$c4 =     $t1 * $t1 * $t1;
	
			$x = $c1 * $ap1->[0] + $c2 * $dp1->[0] + $c3 * $dp2->[0] + $c4 * $ap2->[0];
			$y = $c1 * $ap1->[1] + $c2 * $dp1->[1] + $c3 * $dp2->[1] + $c4 * $ap2->[1];
		
			$bez->addPt($x, $y);
		}
    	
    	$ap1 = $ap2;
    }
    
    # remove the last anchor point if this is a polygon -- since it will autoclose without it
	$bez->deletePt($bez->length()-1) unless $self->isa('GD::Polyline');
    
	return $bez;
}

sub addControlPoints {
    my $self = shift;
    my @points = $self->vertices();

	unless (@points > 1) {
	    carp "Attempt to call addControlPoints() with too few vertices in polyline";
		return undef;
	}
	
	my $points = scalar(@points);
	my @segAngles  = $self->segAngle();
	my @segLengths = $self->segLength();

	my ($prevLen, $nextLen, $prevAngle, $thisAngle, $nextAngle);
	my ($controlSeg, $pt, $ptX, $ptY, @controlSegs);

	# this loop goes about creating polylines -- here called control segments --
	# that hold the control points for the final set of control points
	
	# each control segment has three points, and these are colinear
	
	# the first and last will ultimately be "director points", and
	# the middle point will ultimately be an "anchor point"
	
	for my $i (0..$#points) {

		$controlSeg = new GD::Polyline;

		$pt = $points[$i];
		($ptX, $ptY) = @$pt;

		if ($self->isa('GD::Polyline') and ($i == 0 or $i == $#points)) {
			$controlSeg->addPt($ptX, $ptY);	# director point
			$controlSeg->addPt($ptX, $ptY);	# anchor point
			$controlSeg->addPt($ptX, $ptY);	# director point
			next;	
		}
				
		$prevLen = $segLengths[$i-1];
		$nextLen = $segLengths[$i];
		$prevAngle = $segAngles[$i-1];
		$nextAngle = $segAngles[$i];		
		
		# make a control segment with control points (director points)
		# before and after the point from the polyline (anchor point)
		
		$controlSeg->addPt($ptX - $csr * $prevLen, $ptY);	# director point
		$controlSeg->addPt($ptX                  , $ptY);	# anchor point  
		$controlSeg->addPt($ptX + $csr * $nextLen, $ptY);	# director point

		# note that:
		# - the line is parallel to the x-axis, as the points have a common $ptY
		# - the points are thus clearly colinear
		# - the director point is a distance away from the anchor point in proportion to the length of the segment it faces
		
		# now, we must come up with a reasonable angle for the control seg
		#  first, "unwrap" $nextAngle w.r.t. $prevAngle
		$nextAngle -= 2*pi() until $nextAngle < $prevAngle + pi();
		$nextAngle += 2*pi() until $nextAngle > $prevAngle - pi();
		#  next, use seg lengths as an inverse weighted average
		#  to "tip" the control segment toward the *shorter* segment
		$thisAngle = ($nextAngle * $prevLen + $prevAngle * $nextLen) / ($prevLen + $nextLen);
				       
		# rotate the control segment to $thisAngle about it's anchor point
		$controlSeg->rotate($thisAngle, $ptX, $ptY);
		
	} continue {
		# save the control segment for later
		push @controlSegs, $controlSeg;
		
	}
	
	# post process
	
	my $controlPoly = new ref($self);

	# collect all the control segments' points in to a single control poly
	
	foreach my $cs (@controlSegs) {
		foreach my $pt ($cs->vertices()) {
			$controlPoly->addPt(@$pt);
		}
	}
	
	# final clean up based on poly type
	
	if ($controlPoly->isa('GD::Polyline')) {
		# remove the first and last control point
		# since they are director points ... 
		$controlPoly->deletePt(0);
		$controlPoly->deletePt($controlPoly->length()-1);
	} else {
		# move the first control point to the last control point
		# since it is supposed to end with two director points ... 
		$controlPoly->addPt($controlPoly->getPt(0));
		$controlPoly->deletePt(0);
	}
	
	return $controlPoly;
}


# The following helper functions are for internal
# use of this module.  Input arguments of "points"
# refer to an array ref of two numbers, [$x, $y]
# as is used internally in the GD::Polygon
#
# _len()
# Find the length of a segment, passing in two points.
# Internal function; NOT a class or object method.
#
sub _len {
#	my ($p1, $p2) = @_;
#	return sqrt(($p2->[0]-$p1->[0])**2 + ($p2->[1]-$p1->[1])**2);
	my $pt = _subtract(@_);
	return sqrt($pt->[0] ** 2 + $pt->[1] **2);
}

use Math::Trig;

# _angle()
# Find the angle of... well, depends on the number of arguments:
# - one point: the angle from x-axis to the point (origin is the center)
# - two points: the angle of the vector defined from point1 to point2
# - three points: 
# Internal function; NOT a class or object method.
#
sub _angle {
	my ($p1, $p2, $p3) = @_;
	my $angle = undef;
	if (@_ == 1) {
		return atan2($p1->[1], $p1->[0]);
	}
	if (@_ == 2) {
		return _angle(_subtract($p1, $p2));
	}
	if (@_ == 3) {
		return _angle(_subtract($p2, $p3)) - _angle(_subtract($p2, $p1));
	}
}

# _subtract()
# Find the difference of two points; returns a point.
# Internal function; NOT a class or object method.
#
sub _subtract {
	my ($p1, $p2) = @_;
#	print(_print_point($p2), "-", _print_point($p1), "\n");
	return [$p2->[0]-$p1->[0], $p2->[1]-$p1->[1]];	
}

# _print_point()
# Returns a string suitable for displaying the value of a point.
# Internal function; NOT a class or object method.
#
sub _print_point {
	my ($p1) = @_;
	return "[" . join(", ", @$p1) . "]";
}

# _angle_reduce1()
# "unwraps" angle to interval -pi < angle <= +pi
# Internal function; NOT a class or object method.
#
sub _angle_reduce1 {
	my ($angle) = @_;
	$angle += 2 * pi() while $angle <= -pi();
	$angle -= 2 * pi() while $angle >   pi();
	return $angle;
}

# _angle_reduce2()
# "unwraps" angle to interval 0 <= angle < 2 * pi
# Internal function; NOT a class or object method.
#
sub _angle_reduce2 {
	my ($angle) = @_;
	$angle += 2 * pi() while $angle <  0;
	$angle -= 2 * pi() while $angle >= 2 * pi();
	return $angle;
}

############################################################################
#
# new methods on GD::Image
#
############################################################################

sub GD::Image::polyline {
    my $self = shift;	# the GD::Image
    my $p    = shift;	# the GD::Polyline (or GD::Polygon)
    my $c    = shift;	# the color
    
    my @points = $p->vertices();
    my $p1 = shift @points;
    my $p2;
    while ($p2 = shift @points) {
	    $self->line(@$p1, @$p2, $c);
    	$p1 = $p2;
    }
}	    

sub GD::Image::polydraw {
    my $self = shift;	# the GD::Image
    my $p    = shift;	# the GD::Polyline or GD::Polygon
    my $c    = shift;	# the color
    
   	return $self->polyline($p, $c) if $p->isa('GD::Polyline');
   	return $self->polygon($p, $c);    	
}	    


1;
__END__

=pod

=head1 NAME

GD::Polyline - Polyline object and Polygon utilities (including splines) for use with GD

=head1 SYNOPSIS

	use GD;
	use GD::Polyline;

	# create an image
	$image = new GD::Image (500,300);
	$white  = $image->colorAllocate(255,255,255);
	$black  = $image->colorAllocate(  0,  0,  0);
	$red    = $image->colorAllocate(255,  0,  0);
	
	# create a new polyline
	$polyline = new GD::Polyline;
			
	# add some points
	$polyline->addPt(  0,  0);
	$polyline->addPt(  0,100);
	$polyline->addPt( 50,125);
	$polyline->addPt(100,  0);

	# polylines can use polygon methods (and vice versa)
	$polyline->offset(200,100);
	
	# rotate 60 degrees, about the centroid
	$polyline->rotate(3.14159/3, $polyline->centroid()); 
	
	# scale about the centroid
	$polyline->scale(1.5, 2, $polyline->centroid());  
	
	# draw the polyline
	$image->polydraw($polyline,$black);
	
	# create a spline, which is also a polyine
	$spline = $polyline->addControlPoints->toSpline;
	$image->polydraw($spline,$red);

	# output the png
	binmode STDOUT;
	print $image->png;

=head1 DESCRIPTION

B<Polyline.pm> extends the GD module by allowing you to create polylines.  Think
of a polyline as "an open polygon", that is, the last vertex is not connected
to the first vertex (unless you expressly add the same value as both points).

For the remainder of this doc, "polyline" will refer to a GD::Polyline,
"polygon" will refer to a GD::Polygon that is not a polyline, and
"polything" and "$poly" may be either.

The big feature added to GD by this module is the means
to create splines, which are approximations to curves.

=head1 The Polyline Object

GD::Polyline defines the following class:

=over 5

=item C<GD::Polyline>

A polyline object, used for storing lists of vertices prior to
rendering a polyline into an image.

=item C<new>

C<GD::Polyline-E<gt>new> I<class method>

Create an empty polyline with no vertices.

	$polyline = new GD::Polyline;

	$polyline->addPt(  0,  0);
	$polyline->addPt(  0,100);
	$polyline->addPt( 50,100);
	$polyline->addPt(100,  0);

	$image->polydraw($polyline,$black);

In fact GD::Polyline is a subclass of GD::Polygon, 
so all polygon methods (such as B<offset> and B<transform>)
may be used on polylines.
Some new methods have thus been added to GD::Polygon (such as B<rotate>)
and a few updated/modified/enhanced (such as B<scale>) I<in this module>.  
See section "New or Updated GD::Polygon Methods" for more info.

=back

Note that this module is very "young" and should be
considered subject to change in future releases, and/or
possibly folded in to the existing polygon object and/or GD module.

=head1 Updated Polygon Methods

The following methods (defined in GD.pm) are OVERRIDDEN if you use this module.

All effort has been made to provide 100% backward compatibility, but if you
can confirm that has not been achieved, please consider that a bug and let the
the author of Polyline.pm know.

=over 5

=item C<scale>

C<$poly-E<gt>scale($sx, $sy, $cx, $cy)> I<object method -- UPDATE to GD::Polygon::scale>

Scale a polything in along x-axis by $sx and along the y-axis by $sy,
about centery point ($cx, $cy).

Center point ($cx, $cy) is optional -- if these are omitted, the function
will scale about the origin.

To flip a polything, use a scale factor of -1.  For example, to
flip the polything top to bottom about line y = 100, use:

	$poly->scale(1, -1, 0, 100);

=back

=head1 New Polygon Methods

The following methods are added to GD::Polygon, and thus can be used
by polygons and polylines.

Don't forget: a polyline is a GD::Polygon, so GD::Polygon methods 
like offset() can be used, and they can be used in
GD::Image methods like filledPolygon().

=over 5

=item C<rotate>

C<$poly-E<gt>rotate($angle, $cx, $cy)> I<object method>

Rotate a polything through $angle (clockwise, in radians) about center point ($cx, $cy).

Center point ($cx, $cy) is optional -- if these are omitted, the function
will rotate about the origin

In this function and other angle-oriented functions in GD::Polyline,
positive $angle corrensponds to clockwise rotation.  This is opposite
of the usual Cartesian sense, but that is because the raster is opposite
of the usual Cartesian sense in that the y-axis goes "down".

=item C<centroid>

C<($cx, $cy) = $poly-E<gt>centroid($scale)> I<object method>

Calculate and return ($cx, $cy), the centroid of the vertices of the polything.
For example, to rotate something 180 degrees about it's centroid:

	$poly->rotate(3.14159, $poly->centroid());

$scale is optional; if supplied, $cx and $cy are multiplied by $scale 
before returning.  The main use of this is to shift an polything to the 
origin like this:

	$poly->offset($poly->centroid(-1));

=item C<segLength>

C<@segLengths = $poly-E<gt>segLength()> I<object method>

In array context, returns an array the lengths of the segments in the polything.
Segment n is the segment from vertex n to vertex n+1.
Polygons have as many segments as vertices; polylines have one fewer.

In a scalar context, returns the sum of the array that would have been returned
in the array context.

=item C<segAngle>

C<@segAngles = $poly-E<gt>segAngle()> I<object method>

Returns an array the angles of each segment from the x-axis.
Segment n is the segment from vertex n to vertex n+1.
Polygons have as many segments as vertices; polylines have one fewer.

Returned angles will be on the interval 0 <= $angle < 2 * pi and
angles increase in a clockwise direction.

=item C<vertexAngle>

C<@vertexAngles = $poly-E<gt>vertexAngle()> I<object method>

Returns an array of the angles between the segment into and out of each vertex.
For polylines, the vertex angle at vertex 0 and the last vertex are not defined;
however $vertexAngle[0] will be undef so that $vertexAngle[1] will correspond to 
vertex 1.

Returned angles will be on the interval 0 <= $angle < 2 * pi and
angles increase in a clockwise direction.

Note that this calculation does not attempt to figure out the "interior" angle
with respect to "inside" or "outside" the polygon, but rather, 
just the angle between the adjacent segments
in a clockwise sense.  Thus a polygon with all right angles will have vertex
angles of either pi/2 or 3*pi/2, depending on the way the polygon was "wound".

=item C<toSpline>

C<$poly-E<gt>toSpline()> I<object method & factory method>

Create a new polything which is a reasonably smooth curve
using cubic spline algorithms, often referred to as Bezier
curves.  The "source" polything is called the "control polything".
If it is a polyline, the control polyline must 
have 4, 7, 10, or some number of vertices of equal to 3n+1.
If it is a polygon, the control polygon must 
have 3, 6, 9, or some number of vertices of equal to 3n.

	$spline = $poly->toSpline();	
	$image->polydraw($spline,$red);

In brief, groups of four points from the control polyline
are considered "control
points" for a given portion of the spline: the first and
fourth are "anchor points", and the spline passes through
them; the second and third are "director points".  The
spline does not pass through director points, however the
spline is tangent to the line segment from anchor point to
adjacent director point.

The next portion of the spline reuses the previous portion's
last anchor point.  The spline will have a cusp
(non-continuous slope) at an anchor point, unless the anchor
points and its adjacent director point are colinear.

In the current implementation, toSpline() return a fixed
number of segments in the returned polyline per set-of-four
control points.  In the future, this and other parameters of
the algorithm may be configurable.

=item C<addControlPoints>

C<$polyline-E<gt>addControlPoints()> I<object method & factory method>

So you say: "OK.  Splines sound cool.  But how can I
get my anchor points and its adjacent director point to be
colinear so that I have a nice smooth curves from my
polyline?"  Relax!  For The Lazy: addControlPoints() to the
rescue.

addControlPoints() returns a polyline that can serve
as the control polyline for toSpline(), which returns
another polyline which is the spline.  Is your head spinning
yet?  Think of it this way:

=over 5

=item +

If you have a polyline, and you have already put your
control points where you want them, call toSpline() directly.
Remember, only every third vertex will be "on" the spline.

You get something that looks like the spline "inscribed" 
inside the control polyline.

=item +

If you have a polyline, and you want all of its vertices on
the resulting spline, call addControlPoints() and then
toSpline():

	$control = $polyline->addControlPoints();	
	$spline  = $control->toSpline();	
	$image->polyline($spline,$red);

You get something that looks like the control polyline "inscribed" 
inside the spline.

=back

Adding "good" control points is subjective; this particular 
algorithm reveals its author's tastes.  
In the future, you may be able to alter the taste slightly
via parameters to the algorithm.  For The Hubristic: please 
build a better one!

And for The Impatient: note that addControlPoints() returns a
polyline, so you can pile up the the call like this, 
if you'd like:

	$image->polyline($polyline->addControlPoints()->toSpline(),$mauve);

=back

=head1 New GD::Image Methods

=over 5

=item C<polyline>

C<$image-E<gt>polyline(polyline,color)> I<object method> 

	$image->polyline($polyline,$black)

This draws a polyline with the specified color.  
Both real color indexes and the special 
colors gdBrushed, gdStyled and gdStyledBrushed can be specified.

Neither the polyline() method or the polygon() method are very
picky: you can call either method with either a GD::Polygon or a GD::Polyline.
The I<method> determines if the shape is "closed" or "open" as drawn, I<not>
the object type.

=item C<polydraw>

C<$image-E<gt>polydraw(polything,color)> I<object method> 

	$image->polydraw($poly,$black)

This method draws the polything as expected (polygons are closed, 
polylines are open) by simply checking the object type and calling 
either $image->polygon() or $image->polyline().

=back

=head1 Examples

Please see file "polyline-examples.pl" that is included with the distribution.

=head1 See Also

For more info on Bezier splines, see http://www.webreference.com/dlab/9902/bezier.html.

=head1 Future Features

On the drawing board are additional features such as:

	- polygon winding algorithms (to determine if a point is "inside" or "outside" the polygon)

	- new polygon from bounding box
	
	- find bounding polygon (tightest fitting simple convex polygon for a given set of vertices)
	
	- addPts() method to add many points at once
	
	- clone() method for polygon
	
	- functions to interwork GD with SVG
	
Please provide input on other possible features you'd like to see.

=head1 Author

This module has been written by Daniel J. Harasty.  
Please send questions, comments, complaints, and kudos to him
at harasty@cpan.org.

Thanks to Lincoln Stein for input and patience with me and this, 
my first CPAN contribution.

=head1 Copyright Information

The Polyline.pm module is copyright 2002, Daniel J. Harasty.  It is
distributed under the same terms as Perl itself.  See the "Artistic
License" in the Perl source code distribution for licensing terms.

The latest version of Polyline.pm is available at 
your favorite CPAN repository and/or 
along with GD.pm by Lincoln D. Stein at http://stein.cshl.org/WWW/software/GD.

=cut

# future:
#	addPts
#	boundingPolygon
#	addControlPoints('method' => 'fitToSegments', 'numSegs' => 10)
#	toSpline('csr' => 1/4);

#	GD::Color
#		colorMap('x11' | 'svg' | <filename> )
#		colorByName($image, 'orange');
#		setImage($image);
#		cbn('orange');
#
#
#
