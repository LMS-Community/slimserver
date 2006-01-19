#============================================================= -*-Perl-*-
#
# Template::Plugin::GD::Graph::mixed
#
# DESCRIPTION
#
#   Simple Template Toolkit plugin interfacing to the GD::Graph::mixed
#   package in the GD::Graph.pm module.
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
# $Id: mixed.pm,v 1.58 2004/01/30 19:33:31 abw Exp $
#
#============================================================================

package Template::Plugin::GD::Graph::mixed;

require 5.004;

use strict;
use GD::Graph::mixed;
use Template::Plugin;
use base qw( GD::Graph::mixed Template::Plugin );
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

Template::Plugin::GD::Graph::mixed - Create mixed graphs with axes and legends

=head1 SYNOPSIS

    [% USE g = GD.Graph.mixed(x_size, y_size); %]

=head1 EXAMPLES

    [% FILTER null;
        data = [
            ["1st","2nd","3rd","4th","5th","6th","7th", "8th", "9th"],
            [    1,    2,    5,    6,    3,  1.5,   -1,    -3,    -4],
            [   -4,   -3,    1,    1,   -3, -1.5,   -2,    -1,     0],
            [    9,    8,    9,  8.4,  7.1,  7.5,    8,     3,    -3],
            [  0.1,  0.2,  0.5,  0.4,  0.3,  0.5,  0.1,     0,   0.4],
            [ -0.1,    2,    5,    4,   -3,  2.5,  3.2,     4,    -4],
        ];  
            
        USE my_graph = GD.Graph.mixed();
        
        my_graph.set(
            types => ['lines', 'lines', 'points', 'area', 'linespoints'],
            default_type => 'points',
        );  
        
        my_graph.set(
       
            x_label         => 'X Label',
            y_label         => 'Y label',
            title           => 'A Mixed Type Graph',

            y_max_value     => 10, 
            y_min_value     => -5,
            y_tick_number   => 3,
            y_label_skip    => 0,
            x_plot_values   => 0,
            y_plot_values   => 0,
                
            long_ticks      => 1, 
            x_ticks         => 0,  
                
            legend_marker_width => 24,
            line_width      => 3,
            marker_size     => 5,

            bar_spacing     => 8,

            transparent     => 0,
        );
         
        my_graph.set_legend('one', 'two', 'three', 'four', 'five', 'six');
        my_graph.plot(data).png | stdout(1);
       END;
    -%]

=head1 DESCRIPTION

The GD.Graph.mixed plugin provides an interface to the GD::Graph::mixed
class defined by the GD::Graph module. It allows one or more (x,y) data
sets to be plotted with various styles (lines, points, bars, areas etc).

See L<GD::Graph> for more details.

=head1 AUTHOR

Craig Barratt E<lt>craig@arraycomm.comE<gt>


The GD::Graph module was written by Martien Verbruggen.


=head1 VERSION

1.58, distributed as part of the
Template Toolkit version 2.14, released on 04 October 2004.

=head1 COPYRIGHT


Copyright (C) 2001 Craig Barratt E<lt>craig@arraycomm.comE<gt>

GD::Graph is copyright 1999 Martien Verbruggen.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>, L<Template::Plugin::GD|Template::Plugin::GD>, L<Template::Plugin::GD::Graph::lines|Template::Plugin::GD::Graph::lines>, L<Template::Plugin::GD::Graph::lines3d|Template::Plugin::GD::Graph::lines3d>, L<Template::Plugin::GD::Graph::bars|Template::Plugin::GD::Graph::bars>, L<Template::Plugin::GD::Graph::bars3d|Template::Plugin::GD::Graph::bars3d>, L<Template::Plugin::GD::Graph::points|Template::Plugin::GD::Graph::points>, L<Template::Plugin::GD::Graph::linespoints|Template::Plugin::GD::Graph::linespoints>, L<Template::Plugin::GD::Graph::area|Template::Plugin::GD::Graph::area>, L<Template::Plugin::GD::Graph::pie|Template::Plugin::GD::Graph::pie>, L<Template::Plugin::GD::Graph::pie3d|Template::Plugin::GD::Graph::pie3d>, L<GD::Graph|GD::Graph>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
