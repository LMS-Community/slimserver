#============================================================= -*-Perl-*-
#
# Template::Plugin::GD::Polygon
#
# DESCRIPTION
#
#   Simple Template Toolkit plugin interfacing to the GD::Polygon
#   class in the GD.pm module.
#
# AUTHOR
#   Craig Barratt   <craig@arraycomm.com>
#
# COPYRIGHT
#   Copyright (C) 2001 Craig Barratt.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#----------------------------------------------------------------------------
#
# $Id: Polygon.pm,v 1.56 2004/01/30 19:33:27 abw Exp $
#
#============================================================================

package Template::Plugin::GD::Polygon;

require 5.004;

use strict;
use GD;
use Template::Plugin;
use base qw( Template::Plugin );
use vars qw( $VERSION );

$VERSION = sprintf("%d.%02d", q$Revision: 1.56 $ =~ /(\d+)\.(\d+)/);

sub new
{
    my $class   = shift;
    my $context = shift;
    return new GD::Polygon(@_);
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

Template::Plugin::GD::Polygon - Interface to GD module Polygon class

=head1 SYNOPSIS

    [% USE poly = GD.Polygon;
       poly.addPt(50,0);
       poly.addPt(99,99);
    %]

=head1 EXAMPLES

    [% FILTER null;
        USE im   = GD.Image(100,100);
        USE c    = GD.Constants;

        # allocate some colors
        white = im.colorAllocate(255,255,255);
        black = im.colorAllocate(0,  0,  0);
        red   = im.colorAllocate(255,0,  0);
        blue  = im.colorAllocate(0,  0,255);
        green = im.colorAllocate(0,  255,0);

        # make the background transparent and interlaced
        im.transparent(white);
        im.interlaced('true');

        # Put a black frame around the picture
        im.rectangle(0,0,99,99,black);

        # Draw a blue oval
        im.arc(50,50,95,75,0,360,blue);

        # And fill it with red
        im.fill(50,50,red);

        # Draw a blue triangle by defining a polygon
        USE poly = GD.Polygon;
        poly.addPt(50,0);
        poly.addPt(99,99);
        poly.addPt(0,99);
        im.filledPolygon(poly, blue);

        # Output binary image in PNG format
        im.png | stdout(1);
       END;
    -%]

=head1 DESCRIPTION

The GD.Polygon plugin provides an interface to GD.pm's GD::Polygon class.

See L<GD> for a complete description of the GD library and all the
methods that can be called via the GD.Polygon plugin.
See L<Template::Plugin::GD::Image> for the main interface to the
GD functions.
See L<Template::Plugin::GD::Constants> for a plugin that allows you
access to GD.pm's constants.

=head1 AUTHOR

Craig Barratt E<lt>craig@arraycomm.comE<gt>


Lincoln D. Stein wrote the GD.pm interface to the GD library.


=head1 VERSION

1.56, distributed as part of the
Template Toolkit version 2.14, released on 04 October 2004.

=head1 COPYRIGHT


Copyright (C) 2001 Craig Barratt E<lt>craig@arraycomm.comE<gt>

The GD.pm interface is copyright 1995-2000, Lincoln D. Stein.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>, L<Template::Plugin::GD|Template::Plugin::GD>, L<Template::Plugin::GD::Image|Template::Plugin::GD::Image>, L<Template::Plugin::GD::Constants|Template::Plugin::GD::Constants>, L<GD|GD>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
