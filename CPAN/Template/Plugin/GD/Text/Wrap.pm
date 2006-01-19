#============================================================= -*-Perl-*-
#
# Template::Plugin::GD::Text::Wrap
#
# DESCRIPTION
#
#   Simple Template Toolkit plugin interfacing to the GD::Text::Wrap
#   module.
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
# $Id: Wrap.pm,v 1.56 2004/01/30 19:33:33 abw Exp $
#
#============================================================================

package Template::Plugin::GD::Text::Wrap;

require 5.004;

use strict;
use GD::Text::Wrap;
use Template::Plugin;
use base qw( GD::Text::Wrap Template::Plugin );
use vars qw( $VERSION );

$VERSION = sprintf("%d.%02d", q$Revision: 1.56 $ =~ /(\d+)\.(\d+)/);

sub new
{
    my $class   = shift;
    my $context = shift;
    my $gd      = shift;

    push(@_, %{pop(@_)}) if ( @_ & 1 && ref($_[@_-1]) eq "HASH" );
    return $class->SUPER::new($gd, @_);
}

sub set
{
    my $self = shift;

    push(@_, %{pop(@_)}) if ( @_ & 1 && ref($_[@_-1]) eq "HASH" );
    $self->SUPER::set(@_);
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

Template::Plugin::GD::Text::Wrap - Break and wrap strings in GD images

=head1 SYNOPSIS

    [% USE align = GD.Text.Wrap(gd_image); %]

=head1 EXAMPLES

    [% FILTER null;
        USE gd  = GD.Image(200,400);
        USE gdc = GD.Constants;
        black = gd.colorAllocate(0,   0, 0);
        green = gd.colorAllocate(0, 255, 0);
        txt = "This is some long text. " | repeat(10);
        USE wrapbox = GD.Text.Wrap(gd,
         line_space  => 4,
         color       => green,
         text        => txt,
        );
        wrapbox.set_font(gdc.gdMediumBoldFont);
        wrapbox.set(align => 'center', width => 160);
        wrapbox.draw(20, 20);
        gd.png | stdout(1);
      END;
    -%]

    [% txt = BLOCK -%]
    Lorem ipsum dolor sit amet, consectetuer adipiscing elit,
    sed diam nonummy nibh euismod tincidunt ut laoreet dolore
    magna aliquam erat volutpat.
    [% END -%]
    [% FILTER null;
        #
        # This example follows the example in GD::Text::Wrap, except
        # we create a second image that is a copy just enough of the
        # first image to hold the final text, plus a border.
        #
        USE gd  = GD.Image(400,400);
        USE gdc = GD.Constants;
        green = gd.colorAllocate(0, 255, 0);
        blue  = gd.colorAllocate(0, 0, 255);
        USE wrapbox = GD.Text.Wrap(gd,
         line_space  => 4,
         color       => green,
         text        => txt,
        );
        wrapbox.set_font(gdc.gdMediumBoldFont);
        wrapbox.set(align => 'center', width => 140);
        rect = wrapbox.get_bounds(5, 5);
        x0 = rect.0;
        y0 = rect.1;
        x1 = rect.2 + 9;
        y1 = rect.3 + 9;
        gd.filledRectangle(0, 0, x1, y1, blue);
        gd.rectangle(0, 0, x1, y1, green);
        wrapbox.draw(x0, y0);
        nx = x1 + 1;
        ny = y1 + 1;
        USE gd2 = GD.Image(nx, ny);
        gd2.copy(gd, 0, 0, 0, 0, x1, y1);
        gd2.png | stdout(1);
       END;
    -%]

=head1 DESCRIPTION

The GD.Text.Wrap plugin provides an interface to the GD::Text::Wrap
module. It allows multiples line of text to be drawn in GD images with
various wrapping and alignment.

See L<GD::Text::Wrap> for more details. See
L<Template::Plugin::GD::Text::Align> for a plugin
that allow you to draw text with various alignment
and orientation.

=head1 AUTHOR

Craig Barratt E<lt>craig@arraycomm.comE<gt>


The GD::Text module was written by Martien Verbruggen.


=head1 VERSION

1.56, distributed as part of the
Template Toolkit version 2.14, released on 04 October 2004.

=head1 COPYRIGHT


Copyright (C) 2001 Craig Barratt E<lt>craig@arraycomm.comE<gt>

GD::Text is copyright 1999 Martien Verbruggen.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>, L<Template::Plugin::GD|Template::Plugin::GD>, L<Template::Plugin::GD::Text::Align|Template::Plugin::GD::Text::Align>, L<GD|GD>, L<GD::Text::Wrap|GD::Text::Wrap>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
