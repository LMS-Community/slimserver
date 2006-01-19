#============================================================= -*-Perl-*-
#
# Template::Plugin::GD::Text
#
# DESCRIPTION
#
#   Simple Template Toolkit plugin interfacing to the GD::Text
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
# $Id: Text.pm,v 1.56 2004/01/30 19:33:27 abw Exp $
#
#============================================================================

package Template::Plugin::GD::Text;

require 5.004;

use strict;
use GD::Text;
use Template::Plugin;
use base qw( GD::Text Template::Plugin );
use vars qw( $VERSION );

$VERSION = sprintf("%d.%02d", q$Revision: 1.56 $ =~ /(\d+)\.(\d+)/);

sub new
{
    my $class   = shift;
    my $context = shift;

    push(@_, %{pop(@_)}) if ( @_ & 1 && ref($_[@_-1]) eq "HASH" );
    return new GD::Text(@_);
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

Template::Plugin::GD::Text - Text utilities for use with GD

=head1 SYNOPSIS

    [% USE gd_text = GD.Text %]

=head1 EXAMPLES

    [%
        USE gd_c = GD.Constants;
        USE t = GD.Text;
        x = t.set_text('Some text');
        r = t.get('width', 'height', 'char_up', 'char_down');
        r.join(":"); "\n";     # returns 54:13:13:0.
    -%]

    [%
        USE gd_c = GD.Constants;
        USE t = GD.Text(text => 'FooBar Banana', font => gd_c.gdGiantFont);
        t.get('width'); "\n";  # returns 117.
    -%]

=head1 DESCRIPTION

The GD.Text plugin provides an interface to the GD::Text module.
It allows attributes of strings such as width and height in pixels
to be computed.

See L<GD::Text> for more details. See
L<Template::Plugin::GD::Text::Align> and
L<Template::Plugin::GD::Text::Wrap> for plugins that
allow you to render aligned or wrapped text in GD images.

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

L<Template::Plugin|Template::Plugin>, L<Template::Plugin::GD|Template::Plugin::GD>, L<Template::Plugin::GD::Text::Wrap|Template::Plugin::GD::Text::Wrap>, L<Template::Plugin::GD::Text::Align|Template::Plugin::GD::Text::Align>, L<GD|GD>, L<GD::Text|GD::Text>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
