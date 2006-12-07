#============================================================= -*-Perl-*-
#
# Template::Plugin
#
# DESCRIPTION
#
#   Module defining a base class for a plugin object which can be loaded
#   and instantiated via the USE directive.
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
# $Id: Plugin.pm,v 2.67 2006/01/30 20:04:54 abw Exp $
#
#============================================================================

package Template::Plugin;

require 5.004;

use strict;
use Template::Base;

use vars qw( $VERSION $DEBUG $ERROR $AUTOLOAD );
use base qw( Template::Base );

$VERSION = sprintf("%d.%02d", q$Revision: 2.67 $ =~ /(\d+)\.(\d+)/);
$DEBUG   = 0;


#========================================================================
#                      -----  CLASS METHODS -----
#========================================================================

#------------------------------------------------------------------------
# load()
#
# Class method called when the plugin module is first loaded.  It 
# returns the name of a class (by default, its own class) or a prototype
# object which will be used to instantiate new objects.  The new() 
# method is then called against the class name (class method) or 
# prototype object (object method) to create a new instances of the 
# object.
#------------------------------------------------------------------------

sub load {
    return $_[0];
}


#------------------------------------------------------------------------
# new($context, $delegate, @params)
#
# Object constructor which is called by the Template::Context to 
# instantiate a new Plugin object.  This base class constructor is 
# used as a general mechanism to load and delegate to other Perl 
# modules.  The context is passed as the first parameter, followed by
# a reference to a delegate object or the name of the module which 
# should be loaded and instantiated.  Any additional parameters passed 
# to the USE directive are forwarded to the new() constructor.
# 
# A plugin object is returned which has an AUTOLOAD method to delegate 
# requests to the underlying object.
#------------------------------------------------------------------------

sub new {
    my $class = shift;
    bless {
    }, $class;
}

sub old_new {
    my ($class, $context, $delclass, @params) = @_;
    my ($delegate, $delmod);

    return $class->error("no context passed to $class constructor\n")
	unless defined $context;

    if (ref $delclass) {
	# $delclass contains a reference to a delegate object
	$delegate = $delclass;
    }
    else {
	# delclass is the name of a module to load and instantiate
	($delmod = $delclass) =~ s|::|/|g;

	eval {
	    require "$delmod.pm";
	    $delegate = $delclass->new(@params)
		|| die "failed to instantiate $delclass object\n";
	};
	return $class->error($@) if $@;
    }

    bless {
	_CONTEXT  => $context, 
	_DELEGATE => $delegate,
	_PARAMS   => \@params,
    }, $class;
}


#------------------------------------------------------------------------
# fail($error)
# 
# Version 1 error reporting function, now replaced by error() inherited
# from Template::Base.  Raises a "deprecated function" warning and then
# calls error().
#------------------------------------------------------------------------

sub fail {
    my $class = shift;
    my ($pkg, $file, $line) = caller();
    warn "Template::Plugin::fail() is deprecated at $file line $line.  Please use error()\n";
    $class->error(@_);
}


#========================================================================
#                      -----  OBJECT METHODS -----
#========================================================================

#------------------------------------------------------------------------
# AUTOLOAD
#
# General catch-all method which delegates all calls to the _DELEGATE 
# object.  
#------------------------------------------------------------------------

sub OLD_AUTOLOAD {
    my $self     = shift;
    my $method   = $AUTOLOAD;

    $method =~ s/.*:://;
    return if $method eq 'DESTROY';

    if (ref $self eq 'HASH') {
	my $delegate = $self->{ _DELEGATE } || return;
	return $delegate->$method(@_);
    }
    my ($pkg, $file, $line) = caller();
#    warn "no such '$method' method called on $self at $file line $line\n";
    return undef;
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

Template::Plugin - Base class for Template Toolkit plugins

=head1 SYNOPSIS

    package MyOrg::Template::Plugin::MyPlugin;
    use base qw( Template::Plugin );
    use Template::Plugin;
    use MyModule;

    sub new {
        my $class   = shift;
        my $context = shift;
	bless {
	    ...
	}, $class;
    }

=head1 DESCRIPTION

A "plugin" for the Template Toolkit is simply a Perl module which 
exists in a known package location (e.g. Template::Plugin::*) and 
conforms to a regular standard, allowing it to be loaded and used 
automatically.

The Template::Plugin module defines a base class from which other 
plugin modules can be derived.  A plugin does not have to be derived
from Template::Plugin but should at least conform to its object-oriented
interface.

It is recommended that you create plugins in your own package namespace
to avoid conflict with toolkit plugins.  e.g. 

    package MyOrg::Template::Plugin::FooBar;

Use the PLUGIN_BASE option to specify the namespace that you use.  e.g.

    use Template;
    my $template = Template->new({ 
	PLUGIN_BASE => 'MyOrg::Template::Plugin',
    });

=head1 PLUGIN API

The following methods form the basic interface between the Template
Toolkit and plugin modules.

=over 4

=item load($context)

This method is called by the Template Toolkit when the plugin module
is first loaded.  It is called as a package method and thus implicitly
receives the package name as the first parameter.  A reference to the
Template::Context object loading the plugin is also passed.  The
default behaviour for the load() method is to simply return the class
name.  The calling context then uses this class name to call the new()
package method.

    package MyPlugin;

    sub load {               # called as MyPlugin->load($context)
	my ($class, $context) = @_;
	return $class;       # returns 'MyPlugin'
    }

=item new($context, @params)

This method is called to instantiate a new plugin object for the USE 
directive.  It is called as a package method against the class name 
returned by load().  A reference to the Template::Context object creating
the plugin is passed, along with any additional parameters specified in
the USE directive.

    sub new {                # called as MyPlugin->new($context)
	my ($class, $context, @params) = @_;
	bless {
	    _CONTEXT => $context,
	}, $class;	     # returns blessed MyPlugin object
    }

=item error($error)

This method, inherited from the Template::Base module, is used for 
reporting and returning errors.   It can be called as a package method
to set/return the $ERROR package variable, or as an object method to 
set/return the object _ERROR member.  When called with an argument, it
sets the relevant variable and returns undef.  When called without an
argument, it returns the value of the variable.

    sub new {
	my ($class, $context, $dsn) = @_;

	return $class->error('No data source specified')
	    unless $dsn;

	bless {
	    _DSN => $dsn,
	}, $class;
    }

    ...

    my $something = MyModule->new()
	|| die MyModule->error(), "\n";

    $something->do_something()
	|| die $something->error(), "\n";

=back

=head1 DEEPER MAGIC

The Template::Context object that handles the loading and use of
plugins calls the new() and error() methods against the package name
returned by the load() method.  In pseudo-code terms, it might look
something like this:

    $class  = MyPlugin->load($context);       # returns 'MyPlugin'

    $object = $class->new($context, @params)  # MyPlugin->new(...)
	|| die $class->error();               # MyPlugin->error()

The load() method may alterately return a blessed reference to an
object instance.  In this case, new() and error() are then called as
I<object> methods against that prototype instance.

    package YourPlugin;

    sub load {
        my ($class, $context) = @_;
	bless {
	    _CONTEXT => $context,
	}, $class;
    }

    sub new {
	my ($self, $context, @params) = @_;
	return $self;
    }

In this example, we have implemented a 'Singleton' plugin.  One object 
gets created when load() is called and this simply returns itself for
each call to new().   

Another implementation might require individual objects to be created
for every call to new(), but with each object sharing a reference to
some other object to maintain cached data, database handles, etc.
This pseudo-code example demonstrates the principle.

    package MyServer;

    sub load {
        my ($class, $context) = @_;
	bless {
	    _CONTEXT => $context,
	    _CACHE   => { },
	}, $class;
    }

    sub new {
	my ($self, $context, @params) = @_;
	MyClient->new($self, @params);
    }

    sub add_to_cache   { ... }

    sub get_from_cache { ... }


    package MyClient;

    sub new {
	my ($class, $server, $blah) = @_;
	bless {
	    _SERVER => $server,
	    _BLAH   => $blah,
	}, $class;
    }

    sub get {
	my $self = shift;
	$self->{ _SERVER }->get_from_cache(@_);
    }

    sub put {
	my $self = shift;
	$self->{ _SERVER }->add_to_cache(@_);
    }

When the plugin is loaded, a MyServer instance is created.  The new() 
method is called against this object which instantiates and returns a 
MyClient object, primed to communicate with the creating MyServer.

=head1 Template::Plugin Delegation

As of version 2.01, the Template::Plugin module no longer provides an
AUTOLOAD method to delegate to other objects or classes.  This was a
badly designed feature that caused more trouble than good.  You can
easily add your own AUTOLOAD method to perform delegation if you
require this kind of functionality.

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

L<Template|Template>, L<Template::Plugins|Template::Plugins>, L<Template::Context|Template::Context>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
