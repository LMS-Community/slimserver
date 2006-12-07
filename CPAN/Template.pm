#============================================================= -*-perl-*-
#
# Template
#
# DESCRIPTION
#   Module implementing a simple, user-oriented front-end to the Template 
#   Toolkit.
#
# AUTHOR
#   Andy Wardley   <abw@andywardley.com>
#
# COPYRIGHT
#   Copyright (C) 1996-2002 Andy Wardley.  All Rights Reserved.
#   Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
# REVISION
#   $Id: Template.pm,v 2.84 2006/02/01 11:55:27 abw Exp $
#
#========================================================================
 
package Template;
use base qw( Template::Base );

require 5.005;

use strict;
use vars qw( $VERSION $AUTOLOAD $ERROR $DEBUG $BINMODE );
use Template::Base;
use Template::Config;
use Template::Constants;
use Template::Provider;  
use Template::Service;
use File::Basename;
use File::Path;

## This is the main version number for the Template Toolkit.
## It is extracted by ExtUtils::MakeMaker and inserted in various places.
$VERSION     = '2.15';
$ERROR       = '';
$DEBUG       = 0;
$BINMODE     = 0 unless defined $BINMODE;

# preload all modules if we're running under mod_perl
Template::Config->preload() if $ENV{ MOD_PERL };


#------------------------------------------------------------------------
# process($input, \%replace, $output)
#
# Main entry point for the Template Toolkit.  The Template module 
# delegates most of the processing effort to the underlying SERVICE
# object, an instance of the Template::Service class.  
#------------------------------------------------------------------------

sub process {
    my ($self, $template, $vars, $outstream, @opts) = @_;
    my ($output, $error);
    my $options = (@opts == 1) && UNIVERSAL::isa($opts[0], 'HASH')
        ? shift(@opts) : { @opts };

    $options->{ binmode } = $BINMODE
        unless defined $options->{ binmode };
    
    # we're using this for testing in t/output.t and t/filter.t so 
    # don't remove it if you don't want tests to fail...
    $self->DEBUG("set binmode\n") if $DEBUG && $options->{ binmode };

    $output = $self->{ SERVICE }->process($template, $vars);
    
    if (defined $output) {
        $outstream ||= $self->{ OUTPUT };
        unless (ref $outstream) {
            my $outpath = $self->{ OUTPUT_PATH };
            $outstream = "$outpath/$outstream" if $outpath;
        }	

        # send processed template to output stream, checking for error
        return ($self->error($error))
            if ($error = &_output($outstream, \$output, $options));
        
        return 1;
    }
    else {
        return $self->error($self->{ SERVICE }->error);
    }
}


#------------------------------------------------------------------------
# service()
#
# Returns a reference to the the internal SERVICE object which handles
# all requests for this Template object
#------------------------------------------------------------------------

sub service {
    my $self = shift;
    return $self->{ SERVICE };
}


#------------------------------------------------------------------------
# context()
#
# Returns a reference to the the CONTEXT object withint the SERVICE 
# object.
#------------------------------------------------------------------------

sub context {
    my $self = shift;
    return $self->{ SERVICE }->{ CONTEXT };
}


#========================================================================
#                     -- PRIVATE METHODS --
#========================================================================

#------------------------------------------------------------------------
# _init(\%config)
#------------------------------------------------------------------------
sub _init {
    my ($self, $config) = @_;

    # convert any textual DEBUG args to numerical form
    my $debug = $config->{ DEBUG };
    $config->{ DEBUG } = Template::Constants::debug_flags($self, $debug)
        || return if defined $debug && $debug !~ /^\d+$/;
    
    # prepare a namespace handler for any CONSTANTS definition
    if (my $constants = $config->{ CONSTANTS }) {
        my $ns  = $config->{ NAMESPACE } ||= { };
        my $cns = $config->{ CONSTANTS_NAMESPACE } || 'constants';
        $constants = Template::Config->constants($constants)
            || return $self->error(Template::Config->error);
        $ns->{ $cns } = $constants;
    }
    
    $self->{ SERVICE } = $config->{ SERVICE }
        || Template::Config->service($config)
        || return $self->error(Template::Config->error);
    
    $self->{ OUTPUT      } = $config->{ OUTPUT } || \*STDOUT;
    $self->{ OUTPUT_PATH } = $config->{ OUTPUT_PATH };

    return $self;
}


#------------------------------------------------------------------------
# _output($where, $text)
#------------------------------------------------------------------------

sub _output {
    my ($where, $textref, $options) = @_;
    my $reftype;
    my $error = 0;
    
    # call a CODE reference
    if (($reftype = ref($where)) eq 'CODE') {
        &$where($$textref);
    }
    # print to a glob (such as \*STDOUT)
    elsif ($reftype eq 'GLOB') {
        print $where $$textref;
    }   
    # append output to a SCALAR ref
    elsif ($reftype eq 'SCALAR') {
        $$where .= $$textref;
    }
    # push onto ARRAY ref
    elsif ($reftype eq 'ARRAY') {
        push @$where, $$textref;
    }
    # call the print() method on an object that implements the method
    # (e.g. IO::Handle, Apache::Request, etc)
    elsif (UNIVERSAL::can($where, 'print')) {
        $where->print($$textref);
    }
    # a simple string is taken as a filename
    elsif (! $reftype) {
        local *FP;
        # make destination directory if it doesn't exist
        my $dir = dirname($where);
        eval { mkpath($dir) unless -d $dir; };
        if ($@) {
            # strip file name and line number from error raised by die()
            ($error = $@) =~ s/ at \S+ line \d+\n?$//;
        }
        elsif (open(FP, ">$where")) { 
            # binmode option can be 1 or a specific layer, e.g. :utf8
            my $bm = $options->{ binmode  };
            if ($bm && +$bm == 1) { 
                binmode FP;
            }
            elsif ($bm){ 
                binmode FP, $bm;
            }
            print FP $$textref;
            close FP;
        }
        else {
            $error  = "$where: $!";
        }
    }
    # give up, we've done our best
    else {
        $error = "output_handler() cannot determine target type ($where)\n";
    }

    return $error;
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

Template - Front-end module to the Template Toolkit

=head1 SYNOPSIS 

  use Template;

  # some useful options (see below for full list)
  my $config = {
      INCLUDE_PATH => '/search/path',  # or list ref
      INTERPOLATE  => 1,               # expand "$var" in plain text
      POST_CHOMP   => 1,               # cleanup whitespace 
      PRE_PROCESS  => 'header',        # prefix each template
      EVAL_PERL    => 1,               # evaluate Perl code blocks
  };

  # create Template object
  my $template = Template->new($config);

  # define template variables for replacement
  my $vars = {
      var1  => $value,
      var2  => \%hash,
      var3  => \@list,
      var4  => \&code,
      var5  => $object,
  };

  # specify input filename, or file handle, text reference, etc.
  my $input = 'myfile.html';

  # process input template, substituting variables
  $template->process($input, $vars)
      || die $template->error();

=head1 DESCRIPTION

This documentation describes the Template module which is the direct
Perl interface into the Template Toolkit.  It covers the use of the
module and gives a brief summary of configuration options and template
directives.  Please see L<Template::Manual> for the complete reference
manual which goes into much greater depth about the features and use
of the Template Toolkit.  The L<Template::Tutorial> is also available
as an introductory guide to using the Template Toolkit.

=head1 METHODS

=head2 new(\%config)

The new() constructor method (implemented by the Template::Base base
class) instantiates a new Template object.  A reference to a hash
array of configuration items may be passed as a parameter.

    my $tt = Template->new({
    	INCLUDE_PATH => '/usr/local/templates',
	    EVAL_PERL    => 1,
    }) || die $Template::ERROR, "\n";

A reference to a new Template object is returned, or undef on error.
In the latter case, the error message can be retrieved by calling
error() as a class method (e.g. C<Template-E<gt>error()>) or by
examining the $ERROR package variable directly
(e.g. C<$Template::ERROR>).

    my $tt = Template->new(\%config)
        || die Template->error(), "\n";

    my $tt = Template->new(\%config)
        || die $Template::ERROR, "\n";

For convenience, configuration items may also be specified as a list
of items instead of a hash array reference.  These are automatically
folded into a hash array by the constructor.

    my $tt = Template->new(INCLUDE_PATH => '/tmp', POST_CHOMP => 1)
	|| die $Template::ERROR, "\n";

=head2 process($template, \%vars, $output, %options)

The process() method is called to process a template.  The first
parameter indicates the input template as one of: a filename relative
to INCLUDE_PATH, if defined; a reference to a text string containing
the template text; or a file handle reference (e.g. IO::Handle or
sub-class) or GLOB (e.g. \*STDIN), from which the template can be
read.  A reference to a hash array may be passed as the second
parameter, containing definitions of template variables.

    $text = "[% INCLUDE header %]\nHello world!\n[% INCLUDE footer %]";

    # filename
    $tt->process('welcome.tt2')
        || die $tt->error(), "\n";

    # text reference
    $tt->process(\$text)
        || die $tt->error(), "\n";

    # GLOB
    $tt->process(\*DATA)
        || die $tt->error(), "\n";

    __END__
    [% INCLUDE header %]
    This is a template defined in the __END__ section which is 
    accessible via the DATA "file handle".
    [% INCLUDE footer %]

By default, the processed template output is printed to STDOUT.  The
process() method then returns 1 to indicate success.  A third
parameter may be passed to the process() method to specify a different
output location.  This value may be one of: a plain string indicating
a filename which will be opened (relative to OUTPUT_PATH, if defined)
and the output written to; a file GLOB opened ready for output; a
reference to a scalar (e.g. a text string) to which output/error is
appended; a reference to a subroutine which is called, passing the
output as a parameter; or any object reference which implements a
'print' method (e.g. IO::Handle, Apache::Request, etc.) which will 
be called, passing the generated output as a parameter.

Examples:

    # output filename
    $tt->process('welcome.tt2', $vars, 'welcome.html')
        || die $tt->error(), "\n";

    # reference to output subroutine
    sub myout {
    	my $output = shift;
	    ...
    }
    $tt->process('welcome.tt2', $vars, \&myout)
        || die $tt->error(), "\n";

    # reference to output text string
    my $output = '';
    $tt->process('welcome.tt2', $vars, \$output)
        || die $tt->error(), "\n";
    
    print "output: $output\n";

In an Apache/mod_perl handler:

    sub handler {
	my $req = shift;

        ...

	# direct output to Apache::Request via $req->print($output)
	$tt->process($file, $vars, $req) || do {
	    $req->log_reason($tt->error());
	    return SERVER_ERROR;
	};

	return OK;
    }

After the optional third output argument can come an optional
reference to a hash or a list of (name, value) pairs providing further
options for the output.  The only option currently supported is
"binmode" which, when set to any true value will ensure that files
created (but not any existing file handles passed) will be set to
binary mode.

    # either: hash reference of options
    $tt->process($infile, $vars, $outfile, { binmode => 1 })
        || die $tt->error(), "\n";

    # or: list of name, value pairs
    $tt->process($infile, $vars, $outfile, binmode => 1)
        || die $tt->error(), "\n";

Alternately, the binmode argument can specify a particular IO layer such 
as ":utf8".

    $tt->process($infile, $vars, $outfile, binmode => ':utf8')
        || die $tt->error(), "\n";

The OUTPUT configuration item can be used to specify a default output 
location other than \*STDOUT.  The OUTPUT_PATH specifies a directory
which should be prefixed to all output locations specified as filenames.

    my $tt = Template->new({
    	OUTPUT      => sub { ... },       # default
	    OUTPUT_PATH => '/tmp',
	...
    }) || die Template->error(), "\n";

    # use default OUTPUT (sub is called)
    $tt->process('welcome.tt2', $vars)
        || die $tt->error(), "\n";

    # write file to '/tmp/welcome.html'
    $tt->process('welcome.tt2', $vars, 'welcome.html')
        || die $tt->error(), "\n";

The process() method returns 1 on success or undef on error.  The error
message generated in the latter case can be retrieved by calling the
error() method.  See also L<CONFIGURATION SUMMARY> which describes how
error handling may be further customised.

=head2 error()

When called as a class method, it returns the value of the $ERROR package
variable.  Thus, the following are equivalent.

    my $tt = Template->new()
        || die Template->error(), "\n";

    my $tt = Template->new()
        || die $Template::ERROR, "\n";

When called as an object method, it returns the value of the internal
_ERROR variable, as set by an error condition in a previous call to
process().

    $tt->process('welcome.tt2')
        || die $tt->error(), "\n";

Errors are represented in the Template Toolkit by objects of the
Template::Exception class.  If the process() method returns a false
value then the error() method can be called to return an object of
this class.  The type() and info() methods can called on the object to
retrieve the error type and information string, respectively.  The
as_string() method can be called to return a string of the form "$type
- $info".  This method is also overloaded onto the stringification
operator allowing the object reference itself to be printed to return
the formatted error string.

    $tt->process('somefile') || do {
    	my $error = $tt->error();
	    print "error type: ", $error->type(), "\n";
    	print "error info: ", $error->info(), "\n";
	    print $error, "\n";
    };

=head2 service()

The Template module delegates most of the effort of processing templates
to an underlying Template::Service object.  This method returns a reference
to that object.

=head2 context()

The Template::Service module uses a core Template::Context object for
runtime processing of templates.  This method returns a reference to 
that object and is equivalent to $template-E<gt>service-E<gt>context();

=head1 CONFIGURATION SUMMARY

The following list gives a short summary of each Template Toolkit 
configuration option.  See L<Template::Manual::Config> for full details.

=head2 Template Style and Parsing Options

=over 4

=item START_TAG, END_TAG

Define tokens that indicate start and end of directives (default: '[%' and 
'%]').

=item TAG_STYLE

Set START_TAG and END_TAG according to a pre-defined style (default: 
'template', as above).

=item PRE_CHOMP, POST_CHOMP

Remove whitespace before/after directives (default: 0/0).

=item TRIM

Remove leading and trailing whitespace from template output (default: 0).

=item INTERPOLATE

Interpolate variables embedded like $this or ${this} (default: 0).

=item ANYCASE

Allow directive keywords in lower case (default: 0 - UPPER only).

=back

=head2 Template Files and Blocks

=over 4

=item INCLUDE_PATH

One or more directories to search for templates.

=item DELIMITER

Delimiter for separating paths in INCLUDE_PATH (default: ':').

=item ABSOLUTE

Allow absolute file names, e.g. /foo/bar.html (default: 0).

=item RELATIVE

Allow relative filenames, e.g. ../foo/bar.html (default: 0).

=item DEFAULT

Default template to use when another not found.

=item BLOCKS

Hash array pre-defining template blocks.

=item AUTO_RESET

Enabled by default causing BLOCK definitions to be reset each time a 
template is processed.  Disable to allow BLOCK definitions to persist.

=item RECURSION

Flag to permit recursion into templates (default: 0).

=back

=head2 Template Variables

=over 4

=item VARIABLES, PRE_DEFINE

Hash array of variables and values to pre-define in the stash.

=back

=head2 Runtime Processing Options

=over 4

=item EVAL_PERL

Flag to indicate if PERL/RAWPERL blocks should be processed (default: 0).

=item PRE_PROCESS, POST_PROCESS

Name of template(s) to process before/after main template.

=item PROCESS

Name of template(s) to process instead of main template.

=item ERROR

Name of error template or reference to hash array mapping error types to
templates.

=item  OUTPUT

Default output location or handler.

=item  OUTPUT_PATH

Directory into which output files can be written.

=item DEBUG

Enable debugging messages.

=back

=head2 Caching and Compiling Options

=over 4

=item CACHE_SIZE

Maximum number of compiled templates to cache in memory (default:
undef - cache all)

=item COMPILE_EXT

Filename extension for compiled template files (default: undef - don't
compile).

=item COMPILE_DIR

Root of directory in which compiled template files should be written
(default: undef - don't compile).

=back

=head2 Plugins and Filters

=over 4

=item PLUGINS

Reference to a hash array mapping plugin names to Perl packages.

=item PLUGIN_BASE

One or more base classes under which plugins may be found.

=item LOAD_PERL

Flag to indicate regular Perl modules should be loaded if a named plugin 
can't be found  (default: 0).

=item FILTERS

Hash array mapping filter names to filter subroutines or factories.

=back

=head2 Compatibility, Customisation and Extension

=over 4

=item V1DOLLAR

Backwards compatibility flag enabling version 1.* handling (i.e. ignore it) 
of leading '$' on variables (default: 0 - '$' indicates interpolation).

=item LOAD_TEMPLATES

List of template providers.

=item LOAD_PLUGINS

List of plugin providers.

=item LOAD_FILTERS

List of filter providers.

=item TOLERANT

Set providers to tolerate errors as declinations (default: 0).

=item SERVICE

Reference to a custom service object (default: Template::Service).

=item CONTEXT

Reference to a custom context object (default: Template::Context).

=item STASH

Reference to a custom stash object (default: Template::Stash).

=item PARSER

Reference to a custom parser object (default: Template::Parser).

=item GRAMMAR

Reference to a custom grammar object (default: Template::Grammar).

=back

=head1 DIRECTIVE SUMMARY

The following list gives a short summary of each Template Toolkit directive.
See L<Template::Manual::Directives> for full details.

=over 4

=item GET

Evaluate and print a variable or value.

    [%   GET variable %]    # 'GET' keyword is optional

    [%       variable %]
    [%       hash.key %]
    [%         list.n %]
    [%     code(args) %]
    [% obj.meth(args) %]
    [%  "value: $var" %]

=item CALL

As per GET but without printing result (e.g. call code)

    [%  CALL variable %]

=item SET

Assign a values to variables.

    [% SET variable = value %]    # 'SET' also optional

    [%     variable = other_variable
    	   variable = 'literal text @ $100'
    	   variable = "interpolated text: $var"
    	   list     = [ val, val, val, val, ... ]
    	   list     = [ val..val ]
    	   hash     = { var => val, var => val, ... }
    %]

=item DEFAULT

Like SET above, but variables are only set if currently unset (i.e. have no
true value).

    [% DEFAULT variable = value %]

=item INSERT

Insert a file without any processing performed on the contents.

    [% INSERT legalese.txt %]

=item INCLUDE

Process another template file or block and include the output.  Variables
are localised.

    [% INCLUDE template %]
    [% INCLUDE template  var = val, ... %]

=item PROCESS

As INCLUDE above, but without localising variables.

    [% PROCESS template %]
    [% PROCESS template  var = val, ... %]

=item WRAPPER

Process the enclosed block WRAPPER ... END block then INCLUDE the 
named template, passing the block output in the 'content' variable.

    [% WRAPPER template %]
       content...
    [% END %]

=item BLOCK

Define a named template block for subsequent INCLUDE, PROCESS, etc., 

    [% BLOCK template %]
       content
    [% END %]

=item FOREACH

Repeat the enclosed FOREACH ... END block for each value in the list.

    [% FOREACH variable = [ val, val, val ] %]	  # either
    [% FOREACH variable = list %]                 # or
    [% FOREACH list %]                            # or 
       content...
       [% variable %]
    [% END %]

=item WHILE

Enclosed WHILE ... END block is processed while condition is true.

    [% WHILE condition %]
       content
    [% END %]

=item IF / UNLESS / ELSIF / ELSE

Enclosed block is processed if the condition is true / false.

    [% IF condition %]
       content
    [% ELSIF condition %]
	 content
    [% ELSE %]
	 content
    [% END %]

    [% UNLESS condition %]
       content
    [% # ELSIF/ELSE as per IF, above %]
       content
    [% END %]

=item SWITCH / CASE

Multi-way switch/case statement.

    [% SWITCH variable %]
    [% CASE val1 %]
       content
    [% CASE [ val2, val3 ] %]
       content
    [% CASE %]         # or [% CASE DEFAULT %]
       content
    [% END %]

=item MACRO

Define a named macro.

    [% MACRO name <directive> %]
    [% MACRO name(arg1, arg2) <directive> %]
    ...
    [% name %]
    [% name(val1, val2) %]

=item FILTER

Process enclosed FILTER ... END block then pipe through a filter.

    [% FILTER name %]			    # either
    [% FILTER name( params ) %]		    # or
    [% FILTER alias = name( params ) %]	    # or
       content
    [% END %]

=item USE

Load a "plugin" module, or any regular Perl module if LOAD_PERL option is
set.

    [% USE name %]			    # either
    [% USE name( params ) %]		    # or
    [% USE var = name( params ) %]	    # or
    ...
    [% name.method %]
    [% var.method %]

=item PERL / RAWPERL

Evaluate enclosed blocks as Perl code (requires EVAL_PERL option to be set).

    [% PERL %]
	 # perl code goes here
	 $stash->set('foo', 10);
	 print "set 'foo' to ", $stash->get('foo'), "\n";
	 print $context->include('footer', { var => $val });
    [% END %]

    [% RAWPERL %]
       # raw perl code goes here, no magic but fast.
       $output .= 'some output';
    [% END %]

=item TRY / THROW / CATCH / FINAL

Exception handling.

    [% TRY %]
	 content
       [% THROW type info %]
    [% CATCH type %]
	 catch content
       [% error.type %] [% error.info %]
    [% CATCH %]	# or [% CATCH DEFAULT %]
	 content
    [% FINAL %]
       this block is always processed
    [% END %]

=item NEXT

Jump straight to the next item in a FOREACH/WHILE loop.

    [% NEXT %]

=item LAST

Break out of FOREACH/WHILE loop.

    [% LAST %]

=item RETURN

Stop processing current template and return to including templates.

    [% RETURN %]

=item STOP

Stop processing all templates and return to caller.

    [% STOP %]

=item TAGS

Define new tag style or characters (default: [% %]).

    [% TAGS html %]
    [% TAGS <!-- --> %]

=item COMMENTS

Ignored and deleted.

    [% # this is a comment to the end of line
       foo = 'bar'
    %]

    [%# placing the '#' immediately inside the directive
        tag comments out the entire directive
    %]

=back

=head1 AUTHOR

Andy Wardley E<lt>abw@wardley.orgE<gt>

L<http://wardley.org/|http://wardley.org/>




=head1 VERSION

Template Toolkit version 2.15, released on 26 May 2006.

=head1 COPYRIGHT

  Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.



=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
