#============================================================= -*-Perl-*-
#
# Template::Plugin::GD::Constants
#
# DESCRIPTION
#
#   Simple Template Toolkit plugin interfacing to the GD constants
#   in the GD.pm module.
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
# $Id: Constants.pm,v 1.56 2004/01/30 19:33:27 abw Exp $
#
#============================================================================

package Template::Plugin::GD::Constants;

require 5.004;

use strict;
use GD qw(/^gd/ /^GD/);
use Template::Plugin;
use base qw( Template::Plugin );
use vars qw( @ISA $VERSION );

$VERSION = sprintf("%d.%02d", q$Revision: 1.56 $ =~ /(\d+)\.(\d+)/);

sub new
{
    my $class   = shift;
    my $context = shift;
    my $self    = { };
    bless $self, $class;

    #
    # GD has exported various gd* and GD_* contstants.  Find them.
    #
    foreach my $v ( keys(%Template::Plugin::GD::Constants::) ) {
        $self->{$v} = eval($v) if ( $v =~ /^gd/ || $v =~ /^GD_/ );
    }
    return $self;
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

Template::Plugin::GD::Constants - Interface to GD module constants

=head1 SYNOPSIS

    [% USE gdc = GD.Constants %]

    # --> the constants gdc.gdBrushed, gdc.gdSmallFont, gdc.GD_CMP_IMAGE
    #     are now available

=head1 EXAMPLES

    [% FILTER null;
        USE gdc = GD.Constants;
        USE im  = GD.Image(200,100);
        black = im.colorAllocate(0  ,0,  0);
        red   = im.colorAllocate(255,0,  0);
        r = im.string(gdc.gdLargeFont, 10, 10, "Large Red Text", red);
        im.png | stdout(1);
       END;
    -%]

=head1 DESCRIPTION

The GD.Constants plugin provides access to the various GD module's
constants (such as gdBrushed, gdSmallFont, gdTransparent, GD_CMP_IMAGE
etc).  When GD.pm is used in perl it exports various contstants
into the caller's namespace.  This plugin makes those exported
constants available as template variables.

See L<Template::Plugin::GD::Image> and L<GD> for further examples and
details.

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

L<Template::Plugin|Template::Plugin>, L<Template::Plugin::GD|Template::Plugin::GD>, L<Template::Plugin::GD::Image|Template::Plugin::GD::Image>, L<Template::Plugin::GD::Polygon|Template::Plugin::GD::Polygon>, L<GD|GD>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
