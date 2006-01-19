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
# $Id: Simple.pm,v 2.65 2004/09/24 06:49:13 abw Exp $
#
#============================================================================

package Template::Plugin::XML::Simple;

require 5.004;

use strict;
use Template::Plugin;
use XML::Simple;

use base qw( Template::Plugin );
use vars qw( $VERSION );

$VERSION = sprintf("%d.%02d", q$Revision: 2.65 $ =~ /(\d+)\.(\d+)/);


#------------------------------------------------------------------------
# new($context, $file_or_text, \%config)
#------------------------------------------------------------------------

sub new {
    my $class   = shift;
    my $context = shift;
    my $input   = shift;
    my $args    = ref $_[-1] eq 'HASH' ? pop(@_) : { };

    if (defined($input)) {  
        # an input parameter can been be provided and can contain 
        # XML text or the filename of an XML file, which we load
        # using insert() to honour the INCLUDE_PATH; then we feed 
        # it into XMLin().
        $input = $context->insert($input) unless ( $input =~ /</ );
        return XMLin($input, %$args);
    } 
    else {
        # otherwise return a XML::Simple object
        return new XML::Simple;
    }
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

    # load plugin and specify XML text or file to parse
    [% USE xml = XML.Simple(xml_file_or_text) %]

    # or load plugin as an object...
    [% USE xml = XML.Simple %]

    # ...then use XMLin or XMLout as usual
    [% xml.XMLout(data_ref, args) %]
    [% xml.XMLin(xml_file_or_text, args) %]

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

2.65, distributed as part of the
Template Toolkit version 2.14, released on 04 October 2004.

=head1 COPYRIGHT

  Copyright (C) 1996-2004 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>, L<XML::Simple|XML::Simple>, L<XML::Parser|XML::Parser>

