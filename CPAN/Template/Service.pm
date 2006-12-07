#============================================================= -*-Perl-*-
#
# Template::Service
#
# DESCRIPTION
#   Module implementing a template processing service which wraps a
#   template within PRE_PROCESS and POST_PROCESS templates and offers 
#   ERROR recovery.
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
# $Id: Service.pm,v 2.78 2006/01/30 20:04:55 abw Exp $
#
#============================================================================

package Template::Service;

require 5.004;

use strict;
use vars qw( $VERSION $DEBUG $ERROR );
use base qw( Template::Base );
use Template::Base;
use Template::Config;
use Template::Exception;
use Template::Constants;

$VERSION = sprintf("%d.%02d", q$Revision: 2.78 $ =~ /(\d+)\.(\d+)/);
$DEBUG   = 0 unless defined $DEBUG;


#========================================================================
#                     -----  PUBLIC METHODS -----
#========================================================================

#------------------------------------------------------------------------
# process($template, \%params)
#
# Process a template within a service framework.  A service may encompass
# PRE_PROCESS and POST_PROCESS templates and an ERROR hash which names
# templates to be substituted for the main template document in case of
# error.  Each service invocation begins by resetting the state of the 
# context object via a call to reset().  The AUTO_RESET option may be set 
# to 0 (default: 1) to bypass this step.
#------------------------------------------------------------------------

sub process {
    my ($self, $template, $params) = @_;
    my $context = $self->{ CONTEXT };
    my ($name, $output, $procout, $error);
    $output = '';

    $self->debug("process($template, ", 
                 defined $params ? $params : '<no params>',
                 ')') if $self->{ DEBUG };

    $context->reset()
        if $self->{ AUTO_RESET };

    # pre-request compiled template from context so that we can alias it 
    # in the stash for pre-processed templates to reference
    eval { $template = $context->template($template) };
    return $self->error($@)
        if $@;

    # localise the variable stash with any parameters passed
    # and set the 'template' variable
    $params ||= { };
    $params->{ template } = $template 
        unless ref $template eq 'CODE';
    $context->localise($params);

    SERVICE: {
        # PRE_PROCESS
        eval {
            foreach $name (@{ $self->{ PRE_PROCESS } }) {
                $self->debug("PRE_PROCESS: $name") if $self->{ DEBUG };
                $output .= $context->process($name);
            }
        };
        last SERVICE if ($error = $@);

        # PROCESS
        eval {
            foreach $name (@{ $self->{ PROCESS } || [ $template ] }) {
                $self->debug("PROCESS: $name") if $self->{ DEBUG };
                $procout .= $context->process($name);
            }
        };
        if ($error = $@) {
            last SERVICE
                unless defined ($procout = $self->_recover(\$error));
        }
        
        if (defined $procout) {
            # WRAPPER
            eval {
                foreach $name (reverse @{ $self->{ WRAPPER } }) {
                    $self->debug("WRAPPER: $name") if $self->{ DEBUG };
                    $procout = $context->process($name, { content => $procout });
                }
            };
            last SERVICE if ($error = $@);
            $output .= $procout;
        }
        
        # POST_PROCESS
        eval {
            foreach $name (@{ $self->{ POST_PROCESS } }) {
                $self->debug("POST_PROCESS: $name") if $self->{ DEBUG };
                $output .= $context->process($name);
            }
        };
        last SERVICE if ($error = $@);
    }

    $context->delocalise();
    delete $params->{ template };

    if ($error) {
    #	$error = $error->as_string if ref $error;
        return $self->error($error);
    }

    return $output;
}


#------------------------------------------------------------------------
# context()
# 
# Returns the internal CONTEXT reference.
#------------------------------------------------------------------------

sub context {
    return $_[0]->{ CONTEXT };
}


#========================================================================
#                     -- PRIVATE METHODS --
#========================================================================

sub _init {
    my ($self, $config) = @_;
    my ($item, $data, $context, $block, $blocks);
    my $delim = $config->{ DELIMITER };
    $delim = ':' unless defined $delim;

    # coerce PRE_PROCESS, PROCESS and POST_PROCESS to arrays if necessary, 
    # by splitting on non-word characters
    foreach $item (qw( PRE_PROCESS PROCESS POST_PROCESS WRAPPER )) {
        $data = $config->{ $item };
        $self->{ $item } = [ ], next unless (defined $data);
        $data = [ split($delim, $data || '') ]
            unless ref $data eq 'ARRAY';
        $self->{ $item } = $data;
    }
    # unset PROCESS option unless explicitly specified in config
    $self->{ PROCESS } = undef
        unless defined $config->{ PROCESS };
    
    $self->{ ERROR      } = $config->{ ERROR } || $config->{ ERRORS };
    $self->{ AUTO_RESET } = defined $config->{ AUTO_RESET }
                            ? $config->{ AUTO_RESET } : 1;
    $self->{ DEBUG      } = ( $config->{ DEBUG } || 0 )
                            & Template::Constants::DEBUG_SERVICE;
    
    $context = $self->{ CONTEXT } = $config->{ CONTEXT }
        || Template::Config->context($config)
        || return $self->error(Template::Config->error);
    
    return $self;
}


#------------------------------------------------------------------------
# _recover(\$exception)
#
# Examines the internal ERROR hash array to find a handler suitable 
# for the exception object passed by reference.  Selecting the handler
# is done by delegation to the exception's select_handler() method, 
# passing the set of handler keys as arguments.  A 'default' handler 
# may also be provided.  The handler value represents the name of a 
# template which should be processed. 
#------------------------------------------------------------------------

sub _recover {
    my ($self, $error) = @_;
    my $context = $self->{ CONTEXT };
    my ($hkey, $handler, $output);

    # there shouldn't ever be a non-exception object received at this
    # point... unless a module like CGI::Carp messes around with the 
    # DIE handler. 
    return undef
	unless (ref $$error);

    # a 'stop' exception is thrown by [% STOP %] - we return the output
    # buffer stored in the exception object
    return $$error->text()
        if $$error->type() eq 'stop';

    my $handlers = $self->{ ERROR }
        || return undef;					## RETURN

    if (ref $handlers eq 'HASH') {
        if ($hkey = $$error->select_handler(keys %$handlers)) {
            $handler = $handlers->{ $hkey };
            $self->debug("using error handler for $hkey") if $self->{ DEBUG };
        }
        elsif ($handler = $handlers->{ default }) {
            # use default handler
            $self->debug("using default error handler") if $self->{ DEBUG };
        }
        else {
            return undef;					## RETURN
        }
    }
    else {
        $handler = $handlers;
        $self->debug("using default error handler") if $self->{ DEBUG };
    }
    
    eval { $handler = $context->template($handler) };
    if ($@) {
        $$error = $@;
        return undef;						## RETURN
    };
    
    $context->stash->set('error', $$error);
    eval {
        $output .= $context->process($handler);
    };
    if ($@) {
        $$error = $@;
        return undef;						## RETURN
    }

    return $output;
}



#------------------------------------------------------------------------
# _dump()
#
# Debug method which return a string representing the internal object
# state. 
#------------------------------------------------------------------------

sub _dump {
    my $self = shift;
    my $context = $self->{ CONTEXT }->_dump();
    $context =~ s/\n/\n    /gm;

    my $error = $self->{ ERROR };
    $error = join('', 
		  "{\n",
		  (map { "    $_ => $error->{ $_ }\n" }
		   keys %$error),
		  "}\n")
	if ref $error;
    
    local $" = ', ';
    return <<EOF;
$self
PRE_PROCESS  => [ @{ $self->{ PRE_PROCESS } } ]
POST_PROCESS => [ @{ $self->{ POST_PROCESS } } ]
ERROR        => $error
CONTEXT      => $context
EOF
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

Template::Service - General purpose template processing service

=head1 SYNOPSIS

    use Template::Service;

    my $service = Template::Service->new({
	PRE_PROCESS  => [ 'config', 'header' ],
	POST_PROCESS => 'footer',
	ERROR        => {
	    user     => 'user/index.html', 
	    dbi      => 'error/database',
	    default  => 'error/default',
	},
    });

    my $output = $service->process($template_name, \%replace)
	|| die $service->error(), "\n";

=head1 DESCRIPTION

The Template::Service module implements an object class for providing
a consistent template processing service. 

Standard header (PRE_PROCESS) and footer (POST_PROCESS) templates may
be specified which are prepended and appended to all templates
processed by the service (but not any other templates or blocks
INCLUDEd or PROCESSed from within).  An ERROR hash may be specified
which redirects the service to an alternate template file in the case
of uncaught exceptions being thrown.  This allows errors to be
automatically handled by the service and a guaranteed valid response
to be generated regardless of any processing problems encountered.

A default Template::Service object is created by the Template module.
Any Template::Service options may be passed to the Template new()
constructor method and will be forwarded to the Template::Service
constructor.

    use Template;
    
    my $template = Template->new({
	PRE_PROCESS  => 'header',
	POST_PROCESS => 'footer',
    });

Similarly, the Template::Service constructor will forward all configuration
parameters onto other default objects (e.g. Template::Context) that it may 
need to instantiate.

A Template::Service object (or subclass/derivative) can be explicitly
instantiated and passed to the Template new() constructor method as 
the SERVICE item.

    use Template;
    use Template::Service;

    my $service = Template::Service->new({
	PRE_PROCESS  => 'header',
	POST_PROCESS => 'footer',
    });

    my $template = Template->new({
	SERVICE => $service,
    });

The Template::Service module can be sub-classed to create custom service
handlers.

    use Template;
    use MyOrg::Template::Service;

    my $service = MyOrg::Template::Service->new({
	PRE_PROCESS  => 'header',
	POST_PROCESS => 'footer',
	COOL_OPTION  => 'enabled in spades',
    });

    my $template = Template->new({
	SERVICE => $service,
    });

The Template module uses the Template::Config service() factory method
to create a default service object when required.  The
$Template::Config::SERVICE package variable may be set to specify an
alternate service module.  This will be loaded automatically and its
new() constructor method called by the service() factory method when
a default service object is required.  Thus the previous example could 
be written as:

    use Template;

    $Template::Config::SERVICE = 'MyOrg::Template::Service';

    my $template = Template->new({
	PRE_PROCESS  => 'header',
	POST_PROCESS => 'footer',
	COOL_OPTION  => 'enabled in spades',
    });

=head1 METHODS

=head2 new(\%config)

The new() constructor method is called to instantiate a Template::Service
object.  Configuration parameters may be specified as a HASH reference or
as a list of (name =E<gt> value) pairs.

    my $service1 = Template::Service->new({
	PRE_PROCESS  => 'header',
	POST_PROCESS => 'footer',
    });

    my $service2 = Template::Service->new( ERROR => 'error.html' );

The new() method returns a Template::Service object (or sub-class) or
undef on error.  In the latter case, a relevant error message can be
retrieved by the error() class method or directly from the
$Template::Service::ERROR package variable.

    my $service = Template::Service->new(\%config)
	|| die Template::Service->error();

    my $service = Template::Service->new(\%config)
	|| die $Template::Service::ERROR;

The following configuration items may be specified:

=over 4




=item PRE_PROCESS, POST_PROCESS

These values may be set to contain the name(s) of template files
(relative to INCLUDE_PATH) which should be processed immediately
before and/or after each template.  These do not get added to 
templates processed into a document via directives such as INCLUDE, 
PROCESS, WRAPPER etc.

    my $service = Template::Service->new({
	PRE_PROCESS  => 'header',
	POST_PROCESS => 'footer',
    };

Multiple templates may be specified as a reference to a list.  Each is 
processed in the order defined.

    my $service = Template::Service->new({
	PRE_PROCESS  => [ 'config', 'header' ],
	POST_PROCESS => 'footer',
    };

Alternately, multiple template may be specified as a single string, 
delimited by ':'.  This delimiter string can be changed via the 
DELIMITER option.

    my $service = Template::Service->new({
	PRE_PROCESS  => 'config:header',
	POST_PROCESS => 'footer',
    };

The PRE_PROCESS and POST_PROCESS templates are evaluated in the same
variable context as the main document and may define or update
variables for subsequent use.

config:

    [% # set some site-wide variables
       bgcolor = '#ffffff'
       version = 2.718
    %]

header:

    [% DEFAULT title = 'My Funky Web Site' %]
    <html>
    <head>
    <title>[% title %]</title>
    </head>
    <body bgcolor="[% bgcolor %]">

footer:

    <hr>
    Version [% version %]
    </body>
    </html>

The Template::Document object representing the main template being processed
is available within PRE_PROCESS and POST_PROCESS templates as the 'template'
variable.  Metadata items defined via the META directive may be accessed 
accordingly.

    $service->process('mydoc.html', $vars);

mydoc.html:

    [% META title = 'My Document Title' %]
    blah blah blah
    ...

header:

    <html>
    <head>
    <title>[% template.title %]</title></head>
    <body bgcolor="[% bgcolor %]">














=item PROCESS

The PROCESS option may be set to contain the name(s) of template files
(relative to INCLUDE_PATH) which should be processed instead of the 
main template passed to the Template::Service process() method.  This can 
be used to apply consistent wrappers around all templates, similar to 
the use of PRE_PROCESS and POST_PROCESS templates.

    my $service = Template::Service->new({
	PROCESS  => 'content',
    };

    # processes 'content' instead of 'foo.html'
    $service->process('foo.html');

A reference to the original template is available in the 'template'
variable.  Metadata items can be inspected and the template can be
processed by specifying it as a variable reference (i.e. prefixed by
'$') to an INCLUDE, PROCESS or WRAPPER directive.

content:

    <html>
    <head>
    <title>[% template.title %]</title>
    </head>
    
    <body>
    [% PROCESS $template %]
    <hr>
    &copy; Copyright [% template.copyright %]
    </body>
    </html>

foo.html:

    [% META 
       title     = 'The Foo Page'
       author    = 'Fred Foo'
       copyright = '2000 Fred Foo'
    %]
    <h1>[% template.title %]</h1>
    Welcome to the Foo Page, blah blah blah

output:    

    <html>
    <head>
    <title>The Foo Page</title>
    </head>

    <body>
    <h1>The Foo Page</h1>
    Welcome to the Foo Page, blah blah blah
    <hr>
    &copy; Copyright 2000 Fred Foo
    </body>
    </html>







=item ERROR

The ERROR (or ERRORS if you prefer) configuration item can be used to
name a single template or specify a hash array mapping exception types
to templates which should be used for error handling.  If an uncaught
exception is raised from within a template then the appropriate error
template will instead be processed.

If specified as a single value then that template will be processed 
for all uncaught exceptions. 

    my $service = Template::Service->new({
	ERROR => 'error.html'
    });

If the ERROR item is a hash reference the keys are assumed to be
exception types and the relevant template for a given exception will
be selected.  A 'default' template may be provided for the general
case.  Note that 'ERROR' can be pluralised to 'ERRORS' if you find
it more appropriate in this case.

    my $service = Template::Service->new({
	ERRORS => {
	    user     => 'user/index.html',
	    dbi      => 'error/database',
	    default  => 'error/default',
	},
    });

In this example, any 'user' exceptions thrown will cause the
'user/index.html' template to be processed, 'dbi' errors are handled
by 'error/database' and all others by the 'error/default' template.
Any PRE_PROCESS and/or POST_PROCESS templates will also be applied
to these error templates.

Note that exception types are hierarchical and a 'foo' handler will
catch all 'foo.*' errors (e.g. foo.bar, foo.bar.baz) if a more
specific handler isn't defined.  Be sure to quote any exception types
that contain periods to prevent Perl concatenating them into a single
string (i.e. C<user.passwd> is parsed as 'user'.'passwd').

    my $service = Template::Service->new({
	ERROR => {
	    'user.login'  => 'user/login.html',
	    'user.passwd' => 'user/badpasswd.html',
	    'user'        => 'user/index.html',
	    'default'     => 'error/default',
	},
    });

In this example, any template processed by the $service object, or
other templates or code called from within, can raise a 'user.login'
exception and have the service redirect to the 'user/login.html'
template.  Similarly, a 'user.passwd' exception has a specific 
handling template, 'user/badpasswd.html', while all other 'user' or
'user.*' exceptions cause a redirection to the 'user/index.html' page.
All other exception types are handled by 'error/default'.


Exceptions can be raised in a template using the THROW directive,

    [% THROW user.login 'no user id: please login' %]

or by calling the throw() method on the current Template::Context object,

    $context->throw('user.passwd', 'Incorrect Password');
    $context->throw('Incorrect Password');    # type 'undef'

or from Perl code by calling die() with a Template::Exception object,

    die (Template::Exception->new('user.denied', 'Invalid User ID'));

or by simply calling die() with an error string.  This is
automagically caught and converted to an  exception of 'undef'
type which can then be handled in the usual way.

    die "I'm sorry Dave, I can't do that";







=item AUTO_RESET

The AUTO_RESET option is set by default and causes the local BLOCKS
cache for the Template::Context object to be reset on each call to the
Template process() method.  This ensures that any BLOCKs defined
within a template will only persist until that template is finished
processing.  This prevents BLOCKs defined in one processing request
from interfering with other independent requests subsequently
processed by the same context object.

The BLOCKS item may be used to specify a default set of block definitions
for the Template::Context object.  Subsequent BLOCK definitions in templates
will over-ride these but they will be reinstated on each reset if AUTO_RESET
is enabled (default), or if the Template::Context reset() method is called.







=item DEBUG

The DEBUG option can be used to enable debugging messages from the
Template::Service module by setting it to include the DEBUG_SERVICE
value.

    use Template::Constants qw( :debug );

    my $template = Template->new({
	DEBUG => DEBUG_SERVICE,
    });




=back

=head2 process($input, \%replace)

The process() method is called to process a template specified as the first
parameter, $input.  This may be a file name, file handle (e.g. GLOB or IO::Handle)
or a reference to a text string containing the template text.  An additional
hash reference may be passed containing template variable definitions.

The method processes the template, adding any PRE_PROCESS or POST_PROCESS 
templates defined, and returns the output text.  An uncaught exception thrown 
by the template will be handled by a relevant ERROR handler if defined.
Errors that occur in the PRE_PROCESS or POST_PROCESS templates, or those that
occur in the main input template and aren't handled, cause the method to 
return undef to indicate failure.  The appropriate error message can be
retrieved via the error() method.

    $service->process('myfile.html', { title => 'My Test File' })
	|| die $service->error();


=head2 context()

Returns a reference to the internal context object which is, by default, an
instance of the Template::Context class.

=head2 error()

Returns the most recent error message.

=head1 AUTHOR

Andy Wardley E<lt>abw@wardley.orgE<gt>

L<http://wardley.org/|http://wardley.org/>




=head1 VERSION

2.88, distributed as part of the
Template Toolkit version 2.15, released on 26 May 2006.

=head1 COPYRIGHT

  Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template|Template>, L<Template::Context|Template::Context>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
