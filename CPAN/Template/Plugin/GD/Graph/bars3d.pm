#============================================================= -*-Perl-*-
#
# Template::Plugin::GD::Graph::bars3d
#
# DESCRIPTION
#
#   Simple Template Toolkit plugin interfacing to the GD::Graph::bars3d
#   package in the GD::Graph3D.pm module.
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
# $Id: bars3d.pm,v 1.58 2004/01/30 19:33:31 abw Exp $
#
#============================================================================

package Template::Plugin::GD::Graph::bars3d;

require 5.004;

use strict;
use GD::Graph::bars3d;
use Template::Plugin;
use base qw( GD::Graph::bars3d Template::Plugin );
use vars qw( $VERSION );

$VERSION = sprintf("%d.%02d", q$Revision: 1.58 $ =~ /(\d+)\.(\d+)/);

sub new
{
    my $class   = shift;
    my $context = shift;
    return $class->SUPER::new(@_);
}

sub set
{
    my $self = shift;

    push(@_, %{pop(@_)}) if ( @_ & 1 && ref($_[@_-1]) eq "HASH" );
    $self->SUPER::set(@_);
}


sub set_legend
{
    my $self = shift;
	
    $self->SUPER::set_legend(ref $_[0] ? @{$_[0]} : @_);
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

Template::Plugin::GD::Graph::bars3d - Create 3D bar graphs with axes and legends

=head1 SYNOPSIS

    [% USE g = GD.Graph.bars3d(x_size, y_size); %]

=head1 EXAMPLES

    [% FILTER null;
        data = [
            ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug",
                                         "Sep", "Oct", "Nov", "Dec", ],
            [-5, -4, -3, -3, -1,  0,  2,  1,  3,  4,  6,  7],
            [4,   3,  5,  6,  3,1.5, -1, -3, -4, -6, -7, -8],
            [1,   2,  2,  3,  4,  3,  1, -1,  0,  2,  3,  2],
        ];
        
        USE my_graph = GD.Graph.bars3d();
        
        my_graph.set( 
                x_label => 'Month',
                y_label => 'Measure of success',
                title => 'A 3d Bar Chart',

                y_max_value => 8,
                y_min_value => -8,
                y_tick_number => 16,
                y_label_skip => 2,
                box_axis => 0,
                line_width => 3,
                zero_axis_only => 1,
                x_label_position => 1,  
                y_label_position => 1,  
        
                x_label_skip => 3,
                x_tick_offset => 2,
        
                transparent => 0,
        );      
        my_graph.set_legend("Us", "Them", "Others");
        my_graph.plot(data).png | stdout(1);
       END;
    -%]

=head1 DESCRIPTION

The GD.Graph.bars3d plugin provides an interface to the GD::Graph::bars3d
class defined by the GD::Graph3d module. It allows one or more (x,y) data
sets to be plotted as y versus x bars with a 3-dimensional appearance,
together with axes and legends.

See L<GD::Graph3d> for more details.

=head1 AUTHOR

Craig Barratt E<lt>craig@arraycomm.comE<gt>


The GD::Graph3d module was written by Jeremy Wadsack.


=head1 VERSION

1.58, distributed as part of the
Template Toolkit version 2.14, released on 04 October 2004.

=head1 COPYRIGHT


Copyright (C) 2001 Craig Barratt E<lt>craig@arraycomm.comE<gt>

GD::Graph3d is copyright (C) 1999,2000 Wadsack-Allen. All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>, L<Template::Plugin::GD|Template::Plugin::GD>, L<Template::Plugin::GD::Graph::lines|Template::Plugin::GD::Graph::lines>, L<Template::Plugin::GD::Graph::lines3d|Template::Plugin::GD::Graph::lines3d>, L<Template::Plugin::GD::Graph::bars|Template::Plugin::GD::Graph::bars>, L<Template::Plugin::GD::Graph::points|Template::Plugin::GD::Graph::points>, L<Template::Plugin::GD::Graph::linespoints|Template::Plugin::GD::Graph::linespoints>, L<Template::Plugin::GD::Graph::area|Template::Plugin::GD::Graph::area>, L<Template::Plugin::GD::Graph::mixed|Template::Plugin::GD::Graph::mixed>, L<Template::Plugin::GD::Graph::pie|Template::Plugin::GD::Graph::pie>, L<Template::Plugin::GD::Graph::pie3d|Template::Plugin::GD::Graph::pie3d>, L<GD::Graph|GD::Graph>, L<GD::Graph3d|GD::Graph3d>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
