#============================================================= -*-Perl-*-
#
# Template::Plugin::XML::Style
#
# DESCRIPTION
#   Template Toolkit plugin which performs some basic munging of XML 
#   to perform simple stylesheet like transformations.
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
# REVISION
#   $Id: Style.pm,v 2.35 2004/01/30 19:33:36 abw Exp $
#
#============================================================================

package Template::Plugin::XML::Style;

require 5.004;

use strict;
use Template::Plugin::Filter;

use base qw( Template::Plugin::Filter );
use vars qw( $VERSION $DYNAMIC $FILTER_NAME );

$VERSION = sprintf("%d.%02d", q$Revision: 2.35 $ =~ /(\d+)\.(\d+)/);
$DYNAMIC = 1;
$FILTER_NAME = 'xmlstyle';


#------------------------------------------------------------------------
# new($context, \%config)
#------------------------------------------------------------------------

sub init {
    my $self = shift;
    my $name = $self->{ _ARGS }->[0] || $FILTER_NAME;
    $self->install_filter($name);
    return $self;
}


sub filter {
    my ($self, $text, $args, $config) = @_;

    # munge start tags
    $text =~ s/ < ([\w\.\:]+) ( \s+ [^>]+ )? > 
	      / $self->start_tag($1, $2, $config)
	      /gsex;

    # munge end tags
    $text =~ s/ < \/ ([\w\.\:]+) > 
	      / $self->end_tag($1, $config)
	      /gsex;

    return $text;

}


sub start_tag {
    my ($self, $elem, $textattr, $config) = @_;
    $textattr ||= '';
    my ($pre, $post);

    # look for an element match in the stylesheet
    my $match = $config->{ $elem } 
	|| $self->{ _CONFIG }->{ $elem }
	    || return "<$elem$textattr>";
	
    # merge element attributes into copy of stylesheet attributes
    my $attr = { %{ $match->{ attributes } || { } } };
    while ($textattr =~ / \s* ([\w\.\:]+) = " ([^"]+) " /gsx ) {
	$attr->{ $1 } = $2;
    }
    $textattr = join(' ', map { "$_=\"$attr->{$_}\"" } keys %$attr);
    $textattr = " $textattr" if $textattr;

    $elem = $match->{ element    } || $elem;
    $pre  = $match->{ pre_start  } || '';
    $post = $match->{ post_start } || '';

    return "$pre<$elem$textattr>$post";
}


sub end_tag {
    my ($self, $elem, $config) = @_;
    my ($pre, $post);

    # look for an element match in the stylesheet
    my $match = $config->{ $elem } 
	|| $self->{ _CONFIG }->{ $elem }
	|| return "</$elem>";
	
    $elem = $match->{ element  } || $elem;
    $pre  = $match->{ pre_end  } || '';
    $post = $match->{ post_end } || '';
    
    return "$pre</$elem>$post";
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

Template::Plugin::XML::Style - Simple XML stylesheet transfomations

=head1 SYNOPSIS

    [% USE xmlstyle 
           table = { 
               attributes = { 
                   border      = 0
                   cellpadding = 4
                   cellspacing = 1
               }
           }
    %]

    [% FILTER xmlstyle %]
    <table>
    <tr>
      <td>Foo</td> <td>Bar</td> <td>Baz</td>
    </tr>
    </table>
    [% END %]

=head1 DESCRIPTION

This plugin defines a filter for performing simple stylesheet based 
transformations of XML text.  

Named parameters are used to define those XML elements which require
transformation.  These may be specified with the USE directive when
the plugin is loaded and/or with the FILTER directive when the plugin
is used.

This example shows how the default attributes C<border="0"> and
C<cellpadding="4"> can be added to E<lt>tableE<gt> elements.

    [% USE xmlstyle 
           table = { 
               attributes = { 
                   border      = 0
                   cellpadding = 4
               }
           }
    %]

    [% FILTER xmlstyle %]
    <table>
       ...
    </table>
    [% END %]

This produces the output:

    <table border="0" cellpadding="4">
       ...
    </table>

Parameters specified within the USE directive are applied automatically each
time the C<xmlstyle> FILTER is used.  Additional parameters passed to the 
FILTER directive apply for only that block.

    [% USE xmlstyle 
           table = { 
               attributes = { 
                   border      = 0
                   cellpadding = 4
               }
           }
    %]

    [% FILTER xmlstyle
           tr = {
               attributes = {
                   valign="top"
               }
           }
    %]
    <table>
       <tr>
         ...
       </tr>
    </table>
    [% END %]

Of course, you may prefer to define your stylesheet structures once and 
simply reference them by name.  Passing a hash reference of named parameters
is just the same as specifying the named parameters as far as the Template 
Toolkit is concerned.

    [% style_one = {
          table = { ... }
          tr    = { ... }
       }
       style_two = {
          table = { ... }
          td    = { ... }
       }
       style_three = {
          th = { ... }
          tv = { ... }
       }
    %]

    [% USE xmlstyle style_one %]

    [% FILTER xmlstyle style_two %]
       # style_one and style_two applied here 
    [% END %]
      
    [% FILTER xmlstyle style_three %]
       # style_one and style_three applied here 
    [% END %]

Any attributes defined within the source tags will override those specified
in the style sheet.

    [% USE xmlstyle 
           div = { attributes = { align = 'left' } } 
    %]


    [% FILTER xmlstyle %]
    <div>foo</div>
    <div align="right">bar</div>
    [% END %]

The output produced is:

    <div align="left">foo</div>
    <div align="right">bar</div>

The filter can also be used to change the element from one type to another.

    [% FILTER xmlstyle 
              th = { 
                  element = 'td'
                  attributes = { bgcolor='red' }
              }
    %]
    <tr>
      <th>Heading</th>
    </tr>
    <tr>
      <td>Value</td>
    </tr>
    [% END %]

The output here is as follows.  Notice how the end tag C<E<lt>/thE<gt>> is
changed to C<E<lt>/tdE<gt>> as well as the start tag.

    <tr>
      <td bgcolor="red">Heading</td>
    </tr>
    <tr>
      <td>Value</td>
    </tr>

You can also define text to be added immediately before or after the 
start or end tags.  For example:

    [% FILTER xmlstyle 
              table = {
                  pre_start = '<div align="center">'
                  post_end  = '</div>'
              }
              th = { 
                  element    = 'td'
                  attributes = { bgcolor='red' }
                  post_start = '<b>'
                  pre_end    = '</b>'
              }
    %]
    <table>
    <tr>
      <th>Heading</th>
    </tr>
    <tr>
      <td>Value</td>
    </tr>
    </table>
    [% END %]

The output produced is:

    <div align="center">
    <table>
    <tr>
      <td bgcolor="red"><b>Heading</b></td>
    </tr>
    <tr>
      <td>Value</td>
    </tr>
    </table>
    </div>

=head1 AUTHOR

Andy Wardley E<lt>abw@andywardley.comE<gt>

L<http://www.andywardley.com/|http://www.andywardley.com/>




=head1 VERSION

2.35, distributed as part of the
Template Toolkit version 2.14, released on 04 October 2004.

=head1 COPYRIGHT

  Copyright (C) 1996-2004 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
