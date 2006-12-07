#============================================================= -*-Perl-*-
#
# Template::Plugin::View
#
# DESCRIPTION
#   A user-definable view based on templates.  Similar to the concept of
#   a "Skin".
#
# AUTHOR
#   Andy Wardley   <abw@kfs.org>
#
# COPYRIGHT
#   Copyright (C) 2000 Andy Wardley.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
# REVISION
#   $Id: View.pm,v 2.66 2006/01/30 20:05:49 abw Exp $
#
#============================================================================

package Template::Plugin::View;

require 5.004;

use strict;
use Template::Plugin;
use vars qw( $VERSION );
use base qw( Template::Plugin );

$VERSION = sprintf("%d.%02d", q$Revision: 2.66 $ =~ /(\d+)\.(\d+)/);

use Template::View;

#------------------------------------------------------------------------
# new($context, \%config)
#------------------------------------------------------------------------

sub new {
    my $class = shift;
    my $context = shift;
    my $view = Template::View->new($context, @_)
	|| return $class->error($Template::View::ERROR);
    $view->seal();
    return $view;
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

Template::Plugin::View - Plugin to create views (Template::View)

=head1 SYNOPSIS

    [% USE view(
	    prefix = 'splash/'		# template prefix/suffix
	    suffix = '.tt2'		
	    bgcol  = '#ffffff'		# and any other variables you 
	    style  = 'Fancy HTML'       # care to define as view metadata,
	    items  = [ foo, bar.baz ]	# including complex data and
	    foo    = bar ? baz : x.y.z  # expressions
    %]

    [% view.title %]			# access view metadata

    [% view.header(title = 'Foo!') %]	# view "methods" process blocks or
    [% view.footer %]			# templates with prefix/suffix added

=head1 DESCRIPTION

This plugin module creates Template::View objects.  Views are an
experimental feature and are subject to change in the near future.
In the mean time, please consult L<Template::View> for further info.

=head1 AUTHOR

Andy Wardley E<lt>abw@wardley.orgE<gt>

L<http://wardley.org/|http://wardley.org/>




=head1 VERSION

2.66, distributed as part of the
Template Toolkit version 2.15, released on 26 May 2006.

=head1 COPYRIGHT

  Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>, L<Template::View|Template::View>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
