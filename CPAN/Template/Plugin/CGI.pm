#============================================================= -*-Perl-*-
#
# Template::Plugin::CGI
#
# DESCRIPTION
#
#   Simple Template Toolkit plugin interfacing to the CGI.pm module.
#
# AUTHOR
#   Andy Wardley   <abw@kfs.org>
#
# COPYRIGHT
#   Copyright (C) 1996-2000 Andy Wardley.  All Rights Reserved.
#   Copyright (C) 1998-2000 Canon Research Centre Europe Ltd.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#----------------------------------------------------------------------------
#
# $Id: CGI.pm,v 2.67 2006/01/30 20:05:47 abw Exp $
#
#============================================================================

package Template::Plugin::CGI;

require 5.004;

use strict;
use vars qw( $VERSION );
use base qw( Template::Plugin );
use Template::Plugin;
use CGI;

$VERSION = sprintf("%d.%02d", q$Revision: 2.67 $ =~ /(\d+)\.(\d+)/);

sub new {
    my $class   = shift;
    my $context = shift;
    CGI->new(@_);
}

package CGI;

sub params {
    my $self = shift;
    local $" = ', ';

    return $self->{ _TT_PARAMS } ||= do {
        # must call Vars() in a list context to receive
        # plain list of key/vals rather than a tied hash
        my $params = { $self->Vars() };

        # convert any null separated values into lists
        @$params{ keys %$params } = map { 
            /\0/ ? [ split /\0/ ] : $_ 
        } values %$params;

        $params;
    };
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

Template::Plugin::CGI - Interface to the CGI module

=head1 SYNOPSIS

    [% USE CGI %]
    [% CGI.param('parameter') %]

    [% USE things = CGI %]
    [% things.param('name') %]
    
    # see CGI docs for other methods provided by the CGI object

=head1 DESCRIPTION

This is a very simple Template Toolkit Plugin interface to the CGI module.
A CGI object will be instantiated via the following directive:

    [% USE CGI %]

CGI methods may then be called as follows:

    [% CGI.header %]
    [% CGI.param('parameter') %]

An alias can be used to provide an alternate name by which the object should
be identified.

    [% USE mycgi = CGI %]
    [% mycgi.start_form %]
    [% mycgi.popup_menu({ Name   => 'Color'
			  Values => [ 'Green' 'Black' 'Brown' ] }) %]

Parenthesised parameters to the USE directive will be passed to the plugin 
constructor:
    
    [% USE cgiprm = CGI('uid=abw&name=Andy+Wardley') %]
    [% cgiprm.param('uid') %]

=head1 METHODS

In addition to all the methods supported by the CGI module, this
plugin defines the following.

=head2 params()

This method returns a reference to a hash of all the CGI parameters.
Any parameters that have multiple values will be returned as lists.

    [% USE CGI('user=abw&item=foo&item=bar') %]

    [% CGI.params.user %]            # abw
    [% CGI.params.item.join(', ') %] # foo, bar

=head1 AUTHOR

Andy Wardley E<lt>abw@wardley.orgE<gt>

L<http://wardley.org/|http://wardley.org/>




=head1 VERSION

2.67, distributed as part of the
Template Toolkit version 2.15, released on 26 May 2006.

=head1 COPYRIGHT

  Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>, L<CGI|CGI>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
