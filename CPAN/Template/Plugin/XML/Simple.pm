#============================================================= -*-Perl-*-
#
# Template::Plugin::XML::Simple
#
# DESCRIPTION
#   Template Toolkit plugin interfacing to the XML::Simple.pm module.
#
# AUTHOR
#   Andy Wardley   <abw@kfs.org>
#
# COPYRIGHT
#   Copyright (C) 2001 Andy Wardley.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#----------------------------------------------------------------------------
#
# $Id: Simple.pm,v 1.1 2004/03/14 19:04:49 grotus Exp $
#
#============================================================================

package Template::Plugin::XML::Simple;

require 5.004;

use strict;
use Template::Plugin;
use XML::Simple;

use base qw( Template::Plugin );
use vars qw( $VERSION );

$VERSION = sprintf("%d.%02d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/);


#------------------------------------------------------------------------
# new($context, $file_or_text, \%config)
#------------------------------------------------------------------------

sub new {
    my $class   = shift;
    my $context = shift;
    my $input   = shift;
    my $args    = ref $_[-1] eq 'HASH' ? pop(@_) : { };

    XMLin($input, %$args);
}



#------------------------------------------------------------------------
# _throw($errmsg)
#
# Raise a Template::Exception of type XML.Simple via die().
#------------------------------------------------------------------------

sub _throw {
    my ($self, $error) = @_;
    die (Template::Exception->new('XML.Simple', $error));
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

Template::Plugin::XML::Simple - Plugin interface to XML::Simple

=head1 SYNOPSIS

    # load plugin and specify XML file to parse
    [% USE xml = XML.Simple(xml_file_or_text) %]

=head1 DESCRIPTION

This is a Template Toolkit plugin interfacing to the XML::Simple module.

=head1 PRE-REQUISITES

This plugin requires that the XML::Parser and XML::Simple modules be 
installed.  These are available from CPAN:

    http://www.cpan.org/modules/by-module/XML

=head1 AUTHORS

This plugin wrapper module was written by Andy Wardley
E<lt>abw@wardley.orgE<gt>.

The XML::Simple module which implements all the core functionality 
was written by Grant McLean E<lt>grantm@web.co.nzE<gt>.

=head1 VERSION

2.63, distributed as part of the
Template Toolkit version 2.13, released on 30 January 2004.

=head1 COPYRIGHT

  Copyright (C) 1996-2004 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>, L<XML::Simple|XML::Simple>, L<XML::Parser|XML::Parser>

