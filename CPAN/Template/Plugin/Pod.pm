#==============================================================================
# 
# Template::Plugin::Pod
#
# DESCRIPTION
#  Pod parser and object model.
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
#   $Id: Pod.pm,v 2.66 2006/01/30 20:05:48 abw Exp $
#
#============================================================================

package Template::Plugin::Pod;

require 5.004;

use strict;
use Template::Plugin;
use vars qw( $VERSION );
use base qw( Template::Plugin );

$VERSION = sprintf("%d.%02d", q$Revision: 2.66 $ =~ /(\d+)\.(\d+)/);

use Pod::POM;

#------------------------------------------------------------------------
# new($context, \%config)
#------------------------------------------------------------------------

sub new {
    my $class = shift;
    my $context = shift;

    Pod::POM->new(@_);
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

Template::Plugin::Pod - Plugin interface to Pod::POM (Pod Object Model)

=head1 SYNOPSIS

    [% USE Pod(podfile) %]

    [% FOREACH head1 = Pod.head1;
	 FOREACH head2 = head1/head2;
	   ...
         END;
       END
    %]

=head1 DESCRIPTION

This plugin is an interface to the Pod::POM module.

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

L<Template::Plugin|Template::Plugin>, L<Pod::POM|Pod::POM>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
