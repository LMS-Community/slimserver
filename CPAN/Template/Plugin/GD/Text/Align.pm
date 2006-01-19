#============================================================= -*-Perl-*-
#
# Template::Plugin::GD::Text::Align
#
# DESCRIPTION
#
#   Simple Template Toolkit plugin interfacing to the GD::Text::Align
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
# $Id: Align.pm,v 1.56 2004/01/30 19:33:32 abw Exp $
#
#============================================================================

package Template::Plugin::GD::Text::Align;

require 5.004;

use strict;
use GD::Text::Align;
use Template::Plugin;
use base qw( GD::Text::Align Template::Plugin );
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

Template::Plugin::GD::Text::Align - Draw aligned strings in GD images

=head1 SYNOPSIS

    [% USE align = GD.Text.Align(gd_image); %]

=head1 EXAMPLES

    [% FILTER null;
        USE im  = GD.Image(100,100);
        USE gdc = GD.Constants;
        # allocate some colors
        black = im.colorAllocate(0,   0, 0);
        red   = im.colorAllocate(255,0,  0);
        blue  = im.colorAllocate(0,  0,  255);
        # Draw a blue oval
        im.arc(50,50,95,75,0,360,blue);

        USE a = GD.Text.Align(im);
        a.set_font(gdc.gdLargeFont);
        a.set_text("Hello");
        a.set(colour => red, halign => "center");
        a.draw(50,70,0);

        # Output image in PNG format
        im.png | stdout(1);
       END;
    -%]

=head1 DESCRIPTION

The GD.Text.Align plugin provides an interface to the GD::Text::Align
module. It allows text to be drawn in GD images with various alignments
and orientations.

See L<GD::Text::Align> for more details. See
L<Template::Plugin::GD::Text::Wrap> for a plugin
that allow you to render wrapped text in GD images.

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

L<Template::Plugin|Template::Plugin>, L<Template::Plugin::GD|Template::Plugin::GD>, L<Template::Plugin::GD::Text|Template::Plugin::GD::Text>, L<Template::Plugin::GD::Text::Wrap|Template::Plugin::GD::Text::Wrap>, L<GD|GD>, L<GD::Text::Align|GD::Text::Align>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
