#============================================================= -*-Perl-*-
#
# Template::Plugin::XML::DOM
#
# DESCRIPTION
#
#   Simple Template Toolkit plugin interfacing to the XML::DOM.pm module.
#
# AUTHORS
#   Andy Wardley   <abw@kfs.org>
#   Simon Matthews <sam@knowledgepool.com>
#
# COPYRIGHT
#   Copyright (C) 2000 Andy Wardley, Simon Matthews.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#----------------------------------------------------------------------------
#
# $Id: DOM.pm,v 2.55 2004/01/30 19:33:34 abw Exp $
#
#============================================================================

package Template::Plugin::XML::DOM;

require 5.004;

use strict;
use Template::Plugin;
use XML::DOM;

use base qw( Template::Plugin );
use vars qw( $VERSION $DEBUG );

$VERSION  = 2.6;
$DEBUG    = 0 unless defined $DEBUG;


#------------------------------------------------------------------------
# new($context, \%config)
#
# Constructor method for XML::DOM plugin.  Creates an XML::DOM::Parser
# object and initialise plugin configuration.
#------------------------------------------------------------------------

sub new {
    my $class   = shift;
    my $context = shift;
    my $args    = ref $_[-1] eq 'HASH' ? pop(@_) : { };
    
    my $parser ||= XML::DOM::Parser->new(%$args)
	|| return $class->_throw("failed to create XML::DOM::Parser\n");

    # we've had to deprecate the old usage because it broke things big time
    # with DOM trees never getting cleaned up.
    return $class->_throw("XML::DOM usage has changed - you must now call parse()\n")
	if @_;
    
    bless { 
	_PARSER  => $parser,
	_DOCS    => [ ],
	_CONTEXT => $context,
	_PREFIX  => $args->{ prefix  } || '',
	_SUFFIX  => $args->{ suffix  } || '',
	_DEFAULT => $args->{ default } || '',
	_VERBOSE => $args->{ verbose } || 0,
	_NOSPACE => $args->{ nospace } || 0,
	_DEEP    => $args->{ deep    } || 0,
    }, $class;
}


#------------------------------------------------------------------------
# parse($content, \%named_params)
#
# Parses an XML stream, provided as the first positional argument (assumed
# to be a filename unless it contains a '<' character) or specified in 
# the named parameter hash as one of 'text', 'xml' (same as text), 'file'
# or 'filename'.
#------------------------------------------------------------------------

sub parse {
    my $self   = shift;
    my $args   = ref $_[-1] eq 'HASH' ? pop(@_) : { };
    my $parser = $self->{ _PARSER };
    my ($content, $about, $method, $doc);

    # determine the input source from a positional parameter (may be a 
    # filename or XML text if it contains a '<' character) or by using
    # named parameters which may specify one of 'file', 'filename', 'text'
    # or 'xml'

    if ($content = shift) {
	if ($content =~ /\</) {
	    $about  = 'xml text';
	    $method = 'parse';
	}
	else {
	    $about = "xml file $content";
	    $method = 'parsefile';
	}
    }
    elsif ($content = $args->{ text } || $args->{ xml }) {
	$about = 'xml text';
	$method = 'parse';
    }
    elsif ($content = $args->{ file } || $args->{ filename }) {
	$about = "xml file $content";
	$method = 'parsefile';
    }
    else {
	return $self->_throw('no filename or xml text specified');
    }

    # parse the input source using the appropriate method determined above
    eval { $doc = $parser->$method($content) } and not $@
	or return $self->_throw("failed to parse $about: $@");

    # update XML::DOM::Document _UserData to contain config details
    $doc->[ XML::DOM::Node::_UserData ] = {
	map { ( $_ => $self->{ $_ } ) } 
	qw( _CONTEXT _PREFIX _SUFFIX _VERBOSE _NOSPACE _DEEP _DEFAULT ),
    };

    # keep track of all DOM docs for subsequent dispose()
#    print STDERR "DEBUG: $self adding doc: $doc\n"
#	if $DEBUG;

    push(@{ $self->{ _DOCS } }, $doc);

    return $doc;
}


#------------------------------------------------------------------------
# _throw($errmsg)
#
# Raised a Template::Exception of type XML.DOM via die().
#------------------------------------------------------------------------

sub _throw {
    my ($self, $error) = @_;
    die (Template::Exception->new('XML.DOM', $error));
}


#------------------------------------------------------------------------
# DESTROY
#
# Cleanup method which calls dispose() on any and all DOM documents 
# created by this object.  Also breaks any circular references that
# may exist with the context object.
#------------------------------------------------------------------------

sub DESTROY {
    my $self = shift;

    # call dispose() on each document produced by this parser
    foreach my $doc (@{ $self->{ _DOCS } }) {
#	print STDERR "DEBUG: $self destroying $doc\n"
#	    if $DEBUG;
	if (ref $doc) {
#	    print STDERR "disposing of $doc\n";
	    undef $doc->[ XML::DOM::Node::_UserData ]->{ _CONTEXT };
	    $doc->dispose();
	}
    }
    delete $self->{ _CONTEXT };
    delete $self->{ _PARSER };
}



#========================================================================
package XML::DOM::Node;
#========================================================================


#------------------------------------------------------------------------
# present($view)
#
# Method to present node via a view (supercedes all that messy toTemplate
# stuff below).
#------------------------------------------------------------------------

sub present {
    my ($self, $view) = @_;

    if ($self->getNodeType() == XML::DOM::ELEMENT_NODE) {
	# it's an element
	$view->view($self->getTagName(), $self);
    }
    else {
	my $text = $self->toString();
	$view->view('text', $text);
    }
}

sub content {
    my ($self, $view) = @_;
    my $output = '';
    foreach my $node (@{ $self->getChildNodes }) {
	$output .= $node->present($view);

# abw test passing args, Aug 2001
#	$output .= $view->print($node);
    }
    return $output;
}


#------------------------------------------------------------------------
# toTemplate($prefix, $suffix, \%named_params)
#
# Process the current node as a template.
#------------------------------------------------------------------------

sub toTemplate {
    my $self = shift;
    _template_node($self, $self->_args(@_));
}


#------------------------------------------------------------------------
# childrenToTemplate($prefix, $suffix, \%named_params)
#
# Process all the current node's children as templates.
#------------------------------------------------------------------------

sub childrenToTemplate {
    my $self = shift;
    _template_kids($self, $self->_args(@_));
}


#------------------------------------------------------------------------
# allChildrenToTemplate($prefix, $suffix, \%named_params)
#
# Process all the current node's children, and their children, and 
# their children, etc., etc., as templates.  Same effect as calling the
# childrenToTemplate() method with the 'deep' option set.
#------------------------------------------------------------------------

sub allChildrenToTemplate {
    my $self = shift;
    my $args = $self->_args(@_);
    $args->{ deep } = 1;
    _template_kids($self, $args);
}


#------------------------------------------------------------------------
# _args($prefix, $suffix, \%name_params)
#
# Reads the optional positional parameters, $prefix and $suffix, and 
# also examines any named parameters hash to construct a set of 
# current configuration parameters.  Where not specified directly, the 
# object defaults are used.
#------------------------------------------------------------------------

sub _args {
    my $self = shift;
    my $args = ref $_[-1] eq 'HASH' ? pop(@_) : { };
    my $doc  = $self->getOwnerDocument() || $self;
    my $data = $doc->[ XML::DOM::Node::_UserData ];

    return {
	prefix  => @_ ? shift : $args->{ prefix  } || $data->{ _PREFIX  },
	suffix  => @_ ? shift : $args->{ suffix  } || $data->{ _SUFFIX  },
	verbose =>              $args->{ verbose } || $data->{ _VERBOSE },
	nospace =>              $args->{ nospace } || $data->{ _NOSPACE },
	deep    =>              $args->{ deep    } || $data->{ _DEEP    },
	default =>              $args->{ default } || $data->{ _DEFAULT },
	context =>                                    $data->{ _CONTEXT },
    };
}



#------------------------------------------------------------------------
# _template_node($node, $args, $vars)
#
# Process a template for the current DOM node where the template name 
# is taken from the node TagName, with any specified 'prefix' and/or 
# 'suffix' applied.  The 'default' argument can also be provided to 
# specify a default template to be used when a specific template can't
# be found.  The $args parameter referenced a hash array through which
# these configuration items are passed (see _args()).  The current DOM 
# node is made available to the template as the variable 'node', along 
# with any other variables passed in the optional $vars hash reference.
# To permit the 'children' and 'prune' callbacks to be raised as node
# methods (see _template_kids() below), these items, if defined in the
# $vars hash, are copied into the node object where its AUTOLOAD method
# can find them.
#------------------------------------------------------------------------

sub _template_node {
    my $node = shift || die "no XML::DOM::Node reference\n";
    my $args = shift || die "no XML::DOM args passed to _template_node\n";
    my $vars = shift || { };
    my $context = $args->{ context } || die "no context in XML::DOM args\n";
    my $template;
    my $output = '';

    # if this is not an element then it is text so output it
    unless ($node->getNodeType() == XML::DOM::ELEMENT_NODE ) {
	if ($args->{ verbose }) {
	    $output = $node->toString();
	    $output =~ s/\s+$// if $args->{ nospace };
	}
    }
    else {
	my $element = ( $args->{ prefix  } || '' )
	            .   $node->getTagName()
                    . ( $args->{ suffix  } || '' );

	# locate a template by name built from prefix, tagname and suffix
	# or fall back on any default template specified
	eval { $template = $context->template($element) };
	eval { $template = $context->template($args->{ default }) }
	    if $@ && $args->{ default };
	$template = $element unless $template;

	# copy 'children' and 'prune' callbacks into node object (see AUTOLOAD)
	my $doc  = $node->getOwnerDocument() || $node;
	my $data = $doc->[ XML::DOM::Node::_UserData ];

	$data->{ _TT_CHILDREN } = $vars->{ children };
	$data->{ _TT_PRUNE } = $vars->{ prune };

	# add node reference to existing vars hash
	$vars->{ node } = $node;
	
	$output = $context->include($template, $vars); 
	
	# break any circular references
	delete $vars->{ node };
	delete $data->{ _TT_CHILDREN };
	delete $data->{ _TT_PRUNE };
    }

    return $output;
}


#------------------------------------------------------------------------
# _template_kids($node, $args)
#
# Process all the children of the current node as templates, via calls 
# to _template_node().  If the 'deep' argument is set, then the process
# will continue recursively.  In this case, the node template is first 
# processed, followed by any children of that node (i.e. depth first, 
# parent before).  A closure called 'children' is created and added
# to the Stash variables passed to _template_node().  This can be called 
# from the parent template to process all child nodes at the current point.
# This then "prunes" the tree preventing the children from being processed
# after the parent template.  A 'prune' callback is also added to prune 
# the tree without processing the children.  Note that _template_node()
# copies these callbacks into each parent node, allowing them to be called
# as [% node.
#------------------------------------------------------------------------

sub _template_kids {
    my $node = shift || die "no XML::DOM::Node reference\n";
    my $args = shift || die "no XML::DOM args passed to _template_kids\n";
    my $context = $args->{ context } || die "no context in XML::DOM args\n";
    my $output = '';

    foreach my $kid ( $node->getChildNodes() ) {
	# define some callbacks to allow template to call [% content %]
	# or [% prune %].  They are also inserted into each node reference
	# so they can be called as [% node.content %] and [% node.prune %]
	my $prune = 0;
	my $vars  = { };
	$vars->{ children } = sub {
	    $prune = 1;
	    _template_kids($kid, $args);
	};
	$vars->{ prune } = sub {
	    $prune = 1;
	    return '';
	};
		
	$output .= _template_node($kid, $args, $vars);
	$output .= _template_kids($kid, $args)
	    if $args->{ deep } && ! $prune;
    }
    return $output;
}


#========================================================================
package XML::DOM::Element;
#========================================================================

use vars qw( $AUTOLOAD );

sub AUTOLOAD {
    my $self   = shift;
    my $method = $AUTOLOAD;
    my $attrib;

    $method =~ s/.*:://;
    return if $method eq 'DESTROY';

    my $doc  = $self->getOwnerDocument() || $self;
    my $data = $doc->[ XML::DOM::Node::_UserData ];

    # call 'content' or 'prune' callbacks, if defined (see _template_node())
    return &$attrib()
	if ($method =~ /^children|prune$/)
	    && defined($attrib = $data->{ "_TT_\U$method" })
		&& ref $attrib eq 'CODE';

    return $attrib
	if defined ($attrib = $self->getAttribute($method));

    return '';
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

Template::Plugin::XML::DOM - Plugin interface to XML::DOM

=head1 SYNOPSIS

    # load plugin
    [% USE dom = XML.DOM %]

    # also provide XML::Parser options
    [% USE dom = XML.DOM(ProtocolEncoding =E<gt> 'ISO-8859-1') %]

    # parse an XML file
    [% doc = dom.parse(filename) %]
    [% doc = dom.parse(file => filename) %]

    # parse XML text
    [% doc = dom.parse(xmltext) %]
    [% doc = dom.parse(text => xmltext) %]

    # call any XML::DOM methods on document/element nodes
    [% FOREACH node = doc.getElementsByTagName('report') %]
       * [% node.getAttribute('title') %]     # or just '[% node.title %]'
    [% END %]

    # define VIEW to present node(s)
    [% VIEW report notfound='xmlstring' %]
       # handler block for a <report>...</report> element
       [% BLOCK report %]
          [% item.content(view) %]
       [% END %]

       # handler block for a <section title="...">...</section> element
       [% BLOCK section %]
       <h1>[% item.title %]</h1>
       [% item.content(view) %]
       [% END %]

       # default template block converts item to string representation
       [% BLOCK xmlstring; item.toString; END %]
       
       # block to generate simple text
       [% BLOCK text; item; END %]
    [% END %]

    # now present node (and children) via view
    [% report.print(node) %]

    # or print node content via view
    [% node.content(report) %]

    # following methods are soon to be deprecated in favour of views
    [% node.toTemplate %]
    [% node.childrenToTemplate %]
    [% node.allChildrenToTemplate %]

=head1 PRE-REQUISITES

This plugin requires that the XML::Parser (2.19 or later) and XML::DOM
(1.27 or later) modules be installed.  These are available from CPAN:

    http://www.cpan.org/modules/by-module/XML

Note that the XML::DOM module is now distributed as part of the
'libxml-enno' bundle.

=head1 DESCRIPTION

This is a Template Toolkit plugin interfacing to the XML::DOM module.
The plugin loads the XML::DOM module and creates an XML::DOM::Parser
object which is stored internally.  The parse() method can then be
called on the plugin to parse an XML stream into a DOM document.

    [% USE dom = XML.DOM %]
    [% doc = dom.parse('/tmp/myxmlfile') %]

NOTE: earlier versions of this XML::DOM plugin expected a filename to
be passed as an argument to the constructor.  This is no longer
supported due to the fact that it caused a serious memory leak.  We
apologise for the inconvenience but must insist that you change your
templates as shown:

    # OLD STYLE: now fails with a warning
    [% USE dom = XML.DOM('tmp/myxmlfile') %]

    # NEW STYLE: do this instead
    [% USE dom = XML.DOM %]
    [% doc = dom.parse('tmp/myxmlfile') %]

The root of the problem lies in XML::DOM creating massive circular
references in the object models it constructs.  The dispose() method
must be called on each document to release the memory that it would
otherwise hold indefinately.  The XML::DOM plugin object (i.e. 'dom'
in these examples) acts as a sentinel for the documents it creates
('doc' and any others).  When the plugin object goes out of scope at
the end of the current template, it will automatically call dispose()
on any documents that it has created.  Note that if you dispose of the
the plugin object before the end of the block (i.e.  by assigning a
new value to the 'dom' variable) then the documents will also be
disposed at that point and should not be used thereafter.

    [% USE dom = XML.DOM %]
    [% doc = dom.parse('/tmp/myfile') %]
    [% dom = 'new value' %]     # releases XML.DOM plugin and calls
                                # dispose() on 'doc', so don't use it!

Any template processing parameters (see toTemplate() method and
friends, below) can be specified with the constructor and will be used
to define defaults for the object.

    [% USE dom = XML.DOM(prefix => 'theme1/') %]

The plugin constructor will also accept configuration options destined
for the XML::Parser object:

    [% USE dom = XML.DOM(ProtocolEncoding => 'ISO-8859-1') %]

=head1 METHODS

=head2 parse()

The parse() method accepts a positional parameter which contains a filename
or XML string.  It is assumed to be a filename unless it contains a E<lt>
character.

    [% xmlfile = '/tmp/foo.xml' %]
    [% doc = dom.parse(xmlfile) %]

    [% xmltext = BLOCK %]
    <xml>
      <blah><etc/></blah>
      ...
    </xml>
    [% END %]
    [% doc = dom.parse(xmltext) %]

The named parameters 'file' (or 'filename') and 'text' (or 'xml') can also
be used:

    [% doc = dom.parse(file = xmlfile) %]
    [% doc = dom.parse(text = xmltext) %]

The parse() method returns an instance of the XML::DOM::Document object 
representing the parsed document in DOM form.  You can then call any 
XML::DOM methods on the document node and other nodes that its methods
may return.  See L<XML::DOM> for full details.

    [% FOREACH node = doc.getElementsByTagName('CODEBASE') %]
       * [% node.getAttribute('href') %]
    [% END %]

This plugin also provides an AUTOLOAD method for XML::DOM::Node which 
calls getAttribute() for any undefined methods.  Thus, you can use the 
short form of 

    [% node.attrib %]

in place of

    [% node.getAttribute('attrib') %]

=head2 toTemplate()

B<NOTE: This method will soon be deprecated in favour of the VIEW based
approach desribed below.>

This method will process a template for the current node on which it is 
called.  The template name is constructed from the node TagName with any
optional 'prefix' and/or 'suffix' options applied.  A 'default' template 
can be named to be used when the specific template cannot be found.  The 
node object is available to the template as the 'node' variable.

Thus, for this XML fragment:

    <page title="Hello World!">
       ...
    </page>

and this template definition:

    [% BLOCK page %]
    Page: [% node.title %]
    [% END %]

the output of calling toTemplate() on the E<lt>pageE<gt> node would be:

    Page: Hello World!

=head2 childrenToTemplate()

B<NOTE: This method will soon be deprecated in favour of the VIEW based
approach desribed below.>

Effectively calls toTemplate() for the current node and then for each of 
the node's children.  By default, the parent template is processed first,
followed by each of the children.  The 'children' closure can be called
from within the parent template to have them processed and output 
at that point.  This then suppresses the children from being processed
after the parent template.

Thus, for this XML fragment:

    <foo>
      <bar id="1"/>
      <bar id="2"/>
    </foo>

and these template definitions:

    [% BLOCK foo %]
    start of foo
    end of foo 
    [% END %]

    [% BLOCK bar %]
    bar [% node.id %]
    [% END %]

the output of calling childrenToTemplate() on the parent E<lt>fooE<gt> node 
would be:

    start of foo
    end of foo
    bar 1
    bar 2

Adding a call to [% children %] in the 'foo' template:

    [% BLOCK foo %]
    start of foo
    [% children %]
    end of foo 
    [% END %]

then creates output as:

    start of foo
    bar 1 
    bar 2
    end of foo

The 'children' closure can also be called as a method of the node, if you 
prefer:

    [% BLOCK foo %]
    start of foo
    [% node.children %]
    end of foo 
    [% END %]

The 'prune' closure is also defined and can be called as [% prune %] or
[% node.prune %].  It prunes the currrent node, preventing any descendants
from being further processed.

    [% BLOCK anynode %]
    [% node.toString; node.prune %]
    [% END %]

=head2 allChildrenToTemplate()

B<NOTE: This method will soon be deprecated in favour of the VIEW based
approach desribed below.>

Similar to childrenToTemplate() but processing all descendants (i.e. children
of children and so on) recursively.  This is identical to calling the 
childrenToTemplate() method with the 'deep' flag set to any true value.

=head1 PRESENTING DOM NODES USING VIEWS

You can define a VIEW to present all or part of a DOM tree by automatically
mapping elements onto templates.  Consider a source document like the
following:

    <report>
      <section title="Introduction">
        <p>
        Blah blah.
        <ul>
          <li>Item 1</li>
          <li>item 2</li>
        </ul>
        </p>
      </section>
      <section title="The Gory Details">
        ...
      </section>
    </report>

We can load it up via the XML::DOM plugin and fetch the node for the 
E<lt>reportE<gt> element.

    [% USE dom = XML.DOM;
       doc = dom.parse(file => filename);
       report = doc.getElementsByTagName('report')
    %]

We can then define a VIEW as follows to present this document fragment in 
a particular way.  The L<Template::Manual::Views> documentation
contains further details on the VIEW directive and various configuration
options it supports.

    [% VIEW report_view notfound='xmlstring' %]
       # handler block for a <report>...</report> element
       [% BLOCK report %]
          [% item.content(view) %]
       [% END %]

       # handler block for a <section title="...">...</section> element
       [% BLOCK section %]
       <h1>[% item.title %]</h1>
       [% item.content(view) %]
       [% END %]

       # default template block converts item to string representation
       [% BLOCK xmlstring; item.toString; END %]
       
       # block to generate simple text
       [% BLOCK text; item; END %]
    [% END %]

Each BLOCK defined within the VIEW represents a presentation style for 
a particular element or elements.  The current node is available via the
'item' variable.  Elements that contain other content can generate it
according to the current view by calling [% item.content(view) %].
Elements that don't have a specific template defined are mapped to the
'xmlstring' template via the 'notfound' parameter specified in the VIEW
header.  This replicates the node as an XML string, effectively allowing
general XML/XHTML markup to be passed through unmodified.

To present the report node via the view, we simply call:

    [% report_view.print(report) %]

The output from the above example would look something like this:

    <h1>Introduction</h1>
    <p>
    Blah blah.
    <ul>
      <li>Item 1</li>
      <li>item 2</li>
    </ul>
    </p>
  
    <h1>The Gory Details</h1>
    ...

To print just the content of the report node (i.e. don't process the
'report' template for the report node), you can call:

    [% report.content(report_view) %]

=head1 AUTHORS

This plugin module was written by Andy Wardley E<lt>abw@wardley.orgE<gt>
and Simon Matthews E<lt>sam@knowledgepool.comE<gt>.

The XML::DOM module is by Enno Derksen E<lt>enno@att.comE<gt> and Clark 
Cooper E<lt>coopercl@sch.ge.comE<gt>.  It extends the the XML::Parser 
module, also by Clark Cooper which itself is built on James Clark's expat
library.

=head1 VERSION

2.6, distributed as part of the
Template Toolkit version 2.14, released on 04 October 2004.



=head1 HISTORY

Version 2.5 : updated for use with version 1.27 of the XML::DOM module.

=over 4

=item *

XML::DOM 1.27 now uses array references as the underlying data type
for DOM nodes instead of hash array references.  User data is now
bound to the _UserData node entry instead of being forced directly
into the node hash.

=back

=head1 BUGS

The childrenToTemplate() and allChildrenToTemplate() methods can easily
slip into deep recursion.

The 'verbose' and 'nospace' options are not documented.  They may 
change in the near future.

=head1 COPYRIGHT

Copyright (C) 2000-2001 Andy Wardley, Simon Matthews.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>, L<XML::DOM|XML::DOM>, L<XML::Parser|XML::Parser>

