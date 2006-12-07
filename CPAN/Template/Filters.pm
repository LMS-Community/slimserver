#============================================================= -*-Perl-*-
#
# Template::Filters
#
# DESCRIPTION
#   Defines filter plugins as used by the FILTER directive.
#
# AUTHORS
#   Andy Wardley <abw@kfs.org>, with a number of filters contributed
#   by Leslie Michael Orchard <deus_x@nijacode.com>
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
# $Id: Filters.pm,v 2.81 2006/01/30 20:04:54 abw Exp $
#
#============================================================================

package Template::Filters;

require 5.004;

use strict;
use warnings;
use locale;
use base qw( Template::Base );
use vars qw( $VERSION $DEBUG $FILTERS $URI_ESCAPES $PLUGIN_FILTER );
use Template::Constants;

$VERSION = sprintf("%d.%02d", q$Revision: 2.81 $ =~ /(\d+)\.(\d+)/);


#------------------------------------------------------------------------
# standard filters, defined in one of the following forms:
#   name =>   \&static_filter
#   name => [ \&subref, $is_dynamic ]
# If the $is_dynamic flag is set then the sub-routine reference 
# is called to create a new filter each time it is requested;  if
# not set, then it is a single, static sub-routine which is returned
# for every filter request for that name.
#------------------------------------------------------------------------

$FILTERS = {
    # static filters 
    'html'            => \&html_filter,
    'html_para'       => \&html_paragraph,
    'html_break'      => \&html_para_break,
    'html_para_break' => \&html_para_break,
    'html_line_break' => \&html_line_break,
    'uri'             => \&uri_filter,
    'upper'           => sub { uc $_[0] },
    'lower'           => sub { lc $_[0] },
    'ucfirst'         => sub { ucfirst $_[0] },
    'lcfirst'         => sub { lcfirst $_[0] },
    'stderr'          => sub { print STDERR @_; return '' },
    'trim'            => sub { for ($_[0]) { s/^\s+//; s/\s+$// }; $_[0] },
    'null'            => sub { return '' },
    'collapse'        => sub { for ($_[0]) { s/^\s+//; s/\s+$//; s/\s+/ /g };
                               $_[0] },

    # dynamic filters
    'html_entity' => [ \&html_entity_filter_factory, 1 ],
    'indent'      => [ \&indent_filter_factory,      1 ],
    'format'      => [ \&format_filter_factory,      1 ],
    'truncate'    => [ \&truncate_filter_factory,    1 ],
    'repeat'      => [ \&repeat_filter_factory,      1 ],
    'replace'     => [ \&replace_filter_factory,     1 ],
    'remove'      => [ \&remove_filter_factory,      1 ],
    'eval'        => [ \&eval_filter_factory,        1 ],
    'evaltt'      => [ \&eval_filter_factory,        1 ],  # alias
    'perl'        => [ \&perl_filter_factory,        1 ],
    'evalperl'    => [ \&perl_filter_factory,        1 ],  # alias
    'redirect'    => [ \&redirect_filter_factory,    1 ],
    'file'        => [ \&redirect_filter_factory,    1 ],  # alias
    'stdout'      => [ \&stdout_filter_factory,      1 ],
    'latex'       => [ \&latex_filter_factory,       1 ],
};

# name of module implementing plugin filters
$PLUGIN_FILTER = 'Template::Plugin::Filter';


#========================================================================
#                         -- PUBLIC METHODS --
#========================================================================

#------------------------------------------------------------------------
# fetch($name, \@args, $context)
#
# Attempts to instantiate or return a reference to a filter sub-routine 
# named by the first parameter, $name, with additional constructor 
# arguments passed by reference to a list as the second parameter, 
# $args.  A reference to the calling Template::Context object is 
# passed as the third paramter.
#
# Returns a reference to a filter sub-routine or a pair of values
# (undef, STATUS_DECLINED) or ($error, STATUS_ERROR) to decline to
# deliver the filter or to indicate an error.
#------------------------------------------------------------------------

sub fetch {
    my ($self, $name, $args, $context) = @_;
    my ($factory, $is_dynamic, $filter, $error);

    $self->debug("fetch($name, ", 
                 defined $args ? ('[ ', join(', ', @$args), ' ]') : '<no args>', ', ',
                 defined $context ? $context : '<no context>', 
                 ')') if $self->{ DEBUG };

    # allow $name to be specified as a reference to 
    # a plugin filter object;  any other ref is 
    # assumed to be a coderef and hence already a filter;
    # non-refs are assumed to be regular name lookups

    if (ref $name) {
        if (UNIVERSAL::isa($name, $PLUGIN_FILTER)) {
            $factory = $name->factory()
                || return $self->error($name->error());
        }
        else {
            return $name;
        }
    }
    else {
        return (undef, Template::Constants::STATUS_DECLINED)
            unless ($factory = $self->{ FILTERS }->{ $name }
                    || $FILTERS->{ $name });
    }

    # factory can be an [ $code, $dynamic ] or just $code
    if (ref $factory eq 'ARRAY') {
        ($factory, $is_dynamic) = @$factory;
    }
    else {
        $is_dynamic = 0;
    }

    if (ref $factory eq 'CODE') {
        if ($is_dynamic) {
            # if the dynamic flag is set then the sub-routine is a 
            # factory which should be called to create the actual 
            # filter...
            eval {
                ($filter, $error) = &$factory($context, $args ? @$args : ());
            };
            $error ||= $@;
            $error = "invalid FILTER for '$name' (not a CODE ref)"
                unless $error || ref($filter) eq 'CODE';
        }
        else {
            # ...otherwise, it's a static filter sub-routine
            $filter = $factory;
        }
    }
    else {
        $error = "invalid FILTER entry for '$name' (not a CODE ref)";
    }

    if ($error) {
        return $self->{ TOLERANT } 
               ? (undef,  Template::Constants::STATUS_DECLINED) 
               : ($error, Template::Constants::STATUS_ERROR) ;
    }
    else {
        return $filter;
    }
}


#------------------------------------------------------------------------
# store($name, \&filter)
#
# Stores a new filter in the internal FILTERS hash.  The first parameter
# is the filter name, the second a reference to a subroutine or 
# array, as per the standard $FILTERS entries.
#------------------------------------------------------------------------

sub store {
    my ($self, $name, $filter) = @_;

    $self->debug("store($name, $filter)") if $self->{ DEBUG };

    $self->{ FILTERS }->{ $name } = $filter;
    return 1;
}


#========================================================================
#                        -- PRIVATE METHODS --
#========================================================================

#------------------------------------------------------------------------
# _init(\%config)
#
# Private initialisation method.
#------------------------------------------------------------------------

sub _init {
    my ($self, $params) = @_;

    $self->{ FILTERS  } = $params->{ FILTERS } || { };
    $self->{ TOLERANT } = $params->{ TOLERANT }  || 0;
    $self->{ DEBUG    } = ( $params->{ DEBUG } || 0 )
                          & Template::Constants::DEBUG_FILTERS;


    return $self;
}



#------------------------------------------------------------------------
# _dump()
# 
# Debug method
#------------------------------------------------------------------------

sub _dump {
    my $self = shift;
    my $output = "[Template::Filters] {\n";
    my $format = "    %-16s => %s\n";
    my $key;

    foreach $key (qw( TOLERANT )) {
        my $val = $self->{ $key };
        $val = '<undef>' unless defined $val;
        $output .= sprintf($format, $key, $val);
    }

    my $filters = $self->{ FILTERS };
    $filters = join('', map { 
        sprintf("    $format", $_, $filters->{ $_ });
    } keys %$filters);
    $filters = "{\n$filters    }";
    
    $output .= sprintf($format, 'FILTERS (local)' => $filters);

    $filters = $FILTERS;
    $filters = join('', map { 
        my $f = $filters->{ $_ };
        my ($ref, $dynamic) = ref $f eq 'ARRAY' ? @$f : ($f, 0);
        sprintf("    $format", $_, $dynamic ? 'dynamic' : 'static');
    } sort keys %$filters);
    $filters = "{\n$filters    }";
    
    $output .= sprintf($format, 'FILTERS (global)' => $filters);

    $output .= '}';
    return $output;
}


#========================================================================
#                         -- STATIC FILTER SUBS --
#========================================================================

#------------------------------------------------------------------------
# uri_filter()                                           [% FILTER uri %]
#
# URI escape a string.  This code is borrowed from Gisle Aas' URI::Escape
# module.  For something so simple, I can't see any validation in making
# the user install the URI modules just for this, so we cut and paste.
#
# URI::Escape is Copyright 1995-2000 Gisle Aas.
#------------------------------------------------------------------------

sub uri_filter {
    my $text = shift;

    # construct and cache a lookup table for escapes (faster than
    # doing a sprintf() for every character in every string each 
    # time)
    $URI_ESCAPES ||= {
        map { ( chr($_), sprintf("%%%02X", $_) ) } (0..255),
    };
    
    $text =~ s/([^;\/?:@&=+\$,A-Za-z0-9\-_.!~*'()])/$URI_ESCAPES->{$1}/g;
    $text;
}


#------------------------------------------------------------------------
# html_filter()                                         [% FILTER html %]
#
# Convert any '<', '>' or '&' characters to the HTML equivalents, '&lt;',
# '&gt;' and '&amp;', respectively. 
#------------------------------------------------------------------------

sub html_filter {
    my $text = shift;
    for ($text) {
        s/&/&amp;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
        s/"/&quot;/g;
    }
    return $text;
}


#------------------------------------------------------------------------
# html_paragraph()                                 [% FILTER html_para %]
#
# Wrap each paragraph of text (delimited by two or more newlines) in the
# <p>...</p> HTML tags.
#------------------------------------------------------------------------

sub html_paragraph  {
    my $text = shift;
    return "<p>\n" 
           . join("\n</p>\n\n<p>\n", split(/(?:\r?\n){2,}/, $text))
           . "</p>\n";
}


#------------------------------------------------------------------------
# html_para_break()                          [% FILTER html_para_break %]
#                                               
# Join each paragraph of text (delimited by two or more newlines) with
# <br><br> HTML tags.
#------------------------------------------------------------------------

sub html_para_break  {
    my $text = shift;
    $text =~ s|(\r?\n){2,}|$1<br />$1<br />$1|g;
    return $text;
}

#------------------------------------------------------------------------
# html_line_break()                          [% FILTER html_line_break %]
#
# replaces any newlines with <br> HTML tags.
#------------------------------------------------------------------------

sub html_line_break  {
    my $text = shift;
    $text =~ s|(\r?\n)|<br />$1|g;
    return $text;
}

#========================================================================
#                    -- DYNAMIC FILTER FACTORIES --
#========================================================================

#------------------------------------------------------------------------
# html_entity_filter_factory(\%options)                 [% FILTER html %]
#
# Dynamic version of the static html filter which attempts to locate the
# Apache::Util or HTML::Entities modules to perform full entity encoding
# of the text passed.  Returns an exception if one or other of the 
# modules can't be located.
#------------------------------------------------------------------------

sub html_entity_filter_factory {
    my $context = shift;

    # if Apache::Util is installed then we use it
    eval { 
        require Apache::Util;
        Apache::Util::escape_html('');
    };
    return \&Apache::Util::escape_html
        unless $@;

    # otherwise if HTML::Entities is installed then we use that
    eval {
        require HTML::Entities;
    };
    return \&HTML::Entities::encode_entities
        unless $@;

    return (undef, Template::Exception->new( html_entity => 
                    'cannot locate Apache::Util or HTML::Entities' ));

}


#------------------------------------------------------------------------
# indent_filter_factory($pad)                    [% FILTER indent(pad) %]
#
# Create a filter to indent text by a fixed pad string or when $pad is
# numerical, a number of space. 
#------------------------------------------------------------------------

sub indent_filter_factory {
    my ($context, $pad) = @_;
    $pad = 4 unless defined $pad;
    $pad = ' ' x $pad if $pad =~ /^\d+$/;

    return sub {
        my $text = shift;
        $text = '' unless defined $text;
        $text =~ s/^/$pad/mg;
        return $text;
    }
}

#------------------------------------------------------------------------
# format_filter_factory()                     [% FILTER format(format) %]
#
# Create a filter to format text according to a printf()-like format
# string.
#------------------------------------------------------------------------

sub format_filter_factory {
    my ($context, $format) = @_;
    $format = '%s' unless defined $format;

    return sub {
        my $text = shift;
        $text = '' unless defined $text;
        return join("\n", map{ sprintf($format, $_) } split(/\n/, $text));
    }
}


#------------------------------------------------------------------------
# repeat_filter_factory($n)                        [% FILTER repeat(n) %]
#
# Create a filter to repeat text n times.
#------------------------------------------------------------------------

sub repeat_filter_factory {
    my ($context, $iter) = @_;
    $iter = 1 unless defined $iter and length $iter;

    return sub {
        my $text = shift;
        $text = '' unless defined $text;
        return join('\n', $text) x $iter;
    }
}


#------------------------------------------------------------------------
# replace_filter_factory($s, $r)    [% FILTER replace(search, replace) %]
#
# Create a filter to replace 'search' text with 'replace'
#------------------------------------------------------------------------

sub replace_filter_factory {
    my ($context, $search, $replace) = @_;
    $search = '' unless defined $search;
    $replace = '' unless defined $replace;

    return sub {
        my $text = shift;
        $text = '' unless defined $text;
        $text =~ s/$search/$replace/g;
        return $text;
    }
}


#------------------------------------------------------------------------
# remove_filter_factory($text)                  [% FILTER remove(text) %]
#
# Create a filter to remove 'search' string from the input text.
#------------------------------------------------------------------------

sub remove_filter_factory {
    my ($context, $search) = @_;

    return sub {
        my $text = shift;
        $text = '' unless defined $text;
        $text =~ s/$search//g;
        return $text;
    }
}


#------------------------------------------------------------------------
# truncate_filter_factory($n)                    [% FILTER truncate(n) %]
#
# Create a filter to truncate text after n characters.
#------------------------------------------------------------------------

sub truncate_filter_factory {
    my ($context, $len, $char) = @_;
    $len = 32 unless defined $len;
    $char = "..." unless defined $char;

    return sub {
        my $text = shift;
        return $text if length $text <= $len;
        return substr($text, 0, $len - length($char)) . $char;
    }
}



#------------------------------------------------------------------------
# eval_filter_factory                                   [% FILTER eval %]
# 
# Create a filter to evaluate template text.
#------------------------------------------------------------------------

sub eval_filter_factory {
    my $context = shift;

    return sub {
        my $text = shift;
        $context->process(\$text);
    }
}


#------------------------------------------------------------------------
# perl_filter_factory                                   [% FILTER perl %]
# 
# Create a filter to process Perl text iff the context EVAL_PERL flag 
# is set.
#------------------------------------------------------------------------

sub perl_filter_factory {
    my $context = shift;
    my $stash = $context->stash;

    return (undef, Template::Exception->new('perl', 'EVAL_PERL is not set'))
        unless $context->eval_perl();

    return sub {
        my $text = shift;
        local($Template::Perl::context) = $context;
        local($Template::Perl::stash)   = $stash;
        my $out = eval <<EOF;
package Template::Perl; 
\$stash = \$context->stash(); 
$text
EOF
        $context->throw($@) if $@;
        return $out;
    }
}


#------------------------------------------------------------------------
# redirect_filter_factory($context, $file)    [% FILTER redirect(file) %]
#
# Create a filter to redirect the block text to a file.
#------------------------------------------------------------------------

sub redirect_filter_factory {
    my ($context, $file, $options) = @_;
    my $outpath = $context->config->{ OUTPUT_PATH };

    return (undef, Template::Exception->new('redirect', 
                                            'OUTPUT_PATH is not set'))
        unless $outpath;

    $options = { binmode => $options } unless ref $options;

    sub {
        my $text = shift;
        my $outpath = $context->config->{ OUTPUT_PATH }
            || return '';
        $outpath .= "/$file";
        my $error = Template::_output($outpath, \$text, $options);
        die Template::Exception->new('redirect', $error)
            if $error;
        return '';
    }
}


#------------------------------------------------------------------------
# stdout_filter_factory($context, $binmode)    [% FILTER stdout(binmode) %]
#
# Create a filter to print a block to stdout, with an optional binmode.
#------------------------------------------------------------------------

sub stdout_filter_factory {
    my ($context, $options) = @_;

    $options = { binmode => $options } unless ref $options;

    sub {
        my $text = shift;
        binmode(STDOUT) if $options->{ binmode };
        print STDOUT $text;
        return '';
    }
}


#------------------------------------------------------------------------
# latex_filter_factory($context, $outputType)   [% FILTER latex(outputType) %]
#
# Return a filter sub that converts a (hopefully) complete LaTeX source
# file to either "ps", "dvi", or "pdf".  Output type should be "ps", "dvi"
# or "pdf" (pdf is default).
#
# Creates a temporary directory below File::Spec->tmpdir() (often /tmp)
# and writes the text into doc.tex. It then runs either pdflatex or
# latex and optionally dvips. Based on the exit status either returns
# the entire doc.(pdf|ps|dvi) output or throws an error with a summary
# of the error messages from doc.log.
#
# Written by Craig Barratt, Apr 28 2001.
# Win32 additions by Richard Tietjen.
#------------------------------------------------------------------------
use File::Path;
use File::Spec;
use Cwd;

sub latex_filter_factory
{
    my($context, $output) = @_;

    $output = lc($output);
    my $fName = "latex";
    my($LaTeXPath, $PdfLaTeXPath, $DviPSPath)
                        = @{Template::Config->latexpaths()};
    if ( $output eq "ps" || $output eq "dvi" ) {
        $context->throw($fName,
                "latex not installed (see Template::Config::LATEX_PATH)")
                                if ( $LaTeXPath eq "" );
    } else {
        $output = "pdf";
        $LaTeXPath = $PdfLaTeXPath;
        $context->throw($fName,
                "pdflatex not installed (see Template::Config::PDFLATEX_PATH)")
                                if ( $LaTeXPath eq "" );
    }
    if ( $output eq "ps" && $DviPSPath eq "" ) {
        $context->throw($fName,
                "dvips not installed (see Template::Config::DVIPS_PATH)");
    }
    if ( $^O !~ /^(MacOS|os2|VMS)$/i ) {
        return sub {
            local(*FH);
            my $text = shift;
            my $tmpRootDir = File::Spec->tmpdir();
            my $cnt = 0;
            my($tmpDir, $fileName, $devnull);
            my $texDoc = 'doc';

            do {
                $tmpDir = File::Spec->catdir($tmpRootDir,
                                             "tt2latex$$" . "_$cnt");
                $cnt++;
            } while ( -e $tmpDir );
            mkpath($tmpDir, 0, 0700);
            $context->throw($fName, "can't create temp dir $tmpDir")
                    if ( !-d $tmpDir );
            $fileName = File::Spec->catfile($tmpDir, "$texDoc.tex");
            $devnull  = File::Spec->devnull();
            if ( !open(FH, ">$fileName") ) {
                rmtree($tmpDir);
                $context->throw($fName, "can't open $fileName for output");
            }
            print(FH $text);
            close(FH);

            # latex must run in tmpDir directory
            my $currDir = cwd();
            if ( !chdir($tmpDir) ) {
                rmtree($tmpDir);
                $context->throw($fName, "can't chdir $tmpDir");
            }
            #
            # We don't need to quote the backslashes on windows, but we
            # do on other OSs
            #
            my $LaTeX_arg = "\\nonstopmode\\input{$texDoc}";
            $LaTeX_arg = "'$LaTeX_arg'" if ( $^O ne 'MSWin32' );
            if ( system("$LaTeXPath $LaTeX_arg"
                   . " 1>$devnull 2>$devnull 0<$devnull") ) {
                my $texErrs = "";
                $fileName = File::Spec->catfile($tmpDir, "$texDoc.log");
                if ( open(FH, "<$fileName") ) {
                    my $state = 0;
                    #
                    # Try to extract just the interesting errors from
                    # the verbose log file
                    #
                    while ( <FH> ) {
                        #
                        # TeX errors seems to start with a "!" at the
                        # start of the line, and are followed several
                        # lines later by a line designator of the
                        # form "l.nnn" where nnn is the line number.
                        # We make sure we pick up every /^!/ line, and
                        # the first /^l.\d/ line after each /^!/ line.
                        #
                        if ( /^(!.*)/ ) {
                            $texErrs .= $1 . "\n";
                            $state = 1;
                        }
                        if ( $state == 1 && /^(l\.\d.*)/ ) {
                            $texErrs .= $1 . "\n";
                            $state = 0;
                        }
                    }
                    close(FH);
                } else {
                    $texErrs = "Unable to open $fileName\n";
                }
                my $ok = chdir($currDir);
                rmtree($tmpDir);
                $context->throw($fName, "can't chdir $currDir") if ( !$ok );
                $context->throw($fName, "latex exited with errors:\n$texErrs");
            }
            if ( $output eq "ps" ) {
                $fileName = File::Spec->catfile($tmpDir, "$texDoc.dvi");
                if ( system("$DviPSPath $texDoc -o"
                       . " 1>$devnull 2>$devnull 0<$devnull") ) {
                    my $ok = chdir($currDir);
                    rmtree($tmpDir);
                    $context->throw($fName, "can't chdir $currDir") if ( !$ok );
                    $context->throw($fName, "can't run $DviPSPath $fileName");
                }
            }
            if ( !chdir($currDir) ) {
                rmtree($tmpDir);
                $context->throw($fName, "can't chdir $currDir");
            }

            my $retStr;
            $fileName = File::Spec->catfile($tmpDir, "$texDoc.$output");
            if ( open(FH, $fileName) ) {
                local $/ = undef;       # slurp file in one go
                binmode(FH);
                $retStr = <FH>;
                close(FH);
            } else {
                rmtree($tmpDir);
                $context->throw($fName, "Can't open output file $fileName");
            }
            rmtree($tmpDir);
            return $retStr;
        }
    } else {
        $context->throw("$fName not yet supported on $^O OS."
                      . "  Please contribute code!!");
    }
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

Template::Filters - Post-processing filters for template blocks

=head1 SYNOPSIS

    use Template::Filters;

    $filters = Template::Filters->new(\%config);

    ($filter, $error) = $filters->fetch($name, \@args, $context);

=head1 DESCRIPTION

The Template::Filters module implements a provider for creating and/or
returning subroutines that implement the standard filters.  Additional 
custom filters may be provided via the FILTERS options.

=head1 METHODS

=head2 new(\%params) 

Constructor method which instantiates and returns a reference to a
Template::Filters object.  A reference to a hash array of configuration
items may be passed as a parameter.  These are described below.  

    my $filters = Template::Filters->new({
        FILTERS => { ... },
    });

    my $template = Template->new({
        LOAD_FILTERS => [ $filters ],
    });

A default Template::Filters module is created by the Template.pm module
if the LOAD_FILTERS option isn't specified.  All configuration parameters
are forwarded to the constructor.

    $template = Template->new({
        FILTERS => { ... },
    });

=head2 fetch($name, \@args, $context)

Called to request that a filter of a given name be provided.  The name
of the filter should be specified as the first parameter.  This should
be one of the standard filters or one specified in the FILTERS
configuration hash.  The second argument should be a reference to an
array containing configuration parameters for the filter.  This may be
specified as 0, or undef where no parameters are provided.  The third
argument should be a reference to the current Template::Context
object.

The method returns a reference to a filter sub-routine on success.  It
may also return (undef, STATUS_DECLINE) to decline the request, to allow
delegation onto other filter providers in the LOAD_FILTERS chain of 
responsibility.  On error, ($error, STATUS_ERROR) is returned where $error
is an error message or Template::Exception object indicating the error
that occurred. 

When the TOLERANT option is set, errors are automatically downgraded to
a STATUS_DECLINE response.


=head1 CONFIGURATION OPTIONS

The following list details the configuration options that can be provided
to the Template::Filters new() constructor.

=over 4




=item FILTERS

The FILTERS option can be used to specify custom filters which can
then be used with the FILTER directive like any other.  These are
added to the standard filters which are available by default.  Filters
specified via this option will mask any standard filters of the same
name.

The FILTERS option should be specified as a reference to a hash array
in which each key represents the name of a filter.  The corresponding
value should contain a reference to an array containing a subroutine
reference and a flag which indicates if the filter is static (0) or
dynamic (1).  A filter may also be specified as a solitary subroutine
reference and is assumed to be static.

    $filters = Template::Filters->new({
        FILTERS => {
            'sfilt1' =>   \&static_filter,      # static
            'sfilt2' => [ \&static_filter, 0 ], # same as above
            'dfilt1' => [ \&dyanamic_filter_factory, 1 ],
        },
    });

Additional filters can be specified at any time by calling the 
define_filter() method on the current Template::Context object.
The method accepts a filter name, a reference to a filter 
subroutine and an optional flag to indicate if the filter is 
dynamic.

    my $context = $template->context();
    $context->define_filter('new_html', \&new_html);
    $context->define_filter('new_repeat', \&new_repeat, 1);

Static filters are those where a single subroutine reference is used
for all invocations of a particular filter.  Filters that don't accept
any configuration parameters (e.g. 'html') can be implemented
statically.  The subroutine reference is simply returned when that
particular filter is requested.  The subroutine is called to filter
the output of a template block which is passed as the only argument.
The subroutine should return the modified text.

    sub static_filter {
        my $text = shift;
        # do something to modify $text...
        return $text;
    }

The following template fragment:

    [% FILTER sfilt1 %]
    Blah blah blah.
    [% END %]

is approximately equivalent to:

    &static_filter("\nBlah blah blah.\n");

Filters that can accept parameters (e.g. 'truncate') should be
implemented dynamically.  In this case, the subroutine is taken to be
a filter 'factory' that is called to create a unique filter subroutine
each time one is requested.  A reference to the current
Template::Context object is passed as the first parameter, followed by
any additional parameters specified.  The subroutine should return
another subroutine reference (usually a closure) which implements the
filter.

    sub dynamic_filter_factory {
        my ($context, @args) = @_;

        return sub {
            my $text = shift;
            # do something to modify $text...
            return $text;           
        }
    }

The following template fragment:

    [% FILTER dfilt1(123, 456) %] 
    Blah blah blah
    [% END %]              

is approximately equivalent to:

    my $filter = &dynamic_filter_factory($context, 123, 456);
    &$filter("\nBlah blah blah.\n");

See the FILTER directive for further examples.




=item TOLERANT

The TOLERANT flag is used by the various Template Toolkit provider
modules (Template::Provider, Template::Plugins, Template::Filters) to
control their behaviour when errors are encountered.  By default, any
errors are reported as such, with the request for the particular
resource (template, plugin, filter) being denied and an exception
raised.  When the TOLERANT flag is set to any true values, errors will
be silently ignored and the provider will instead return
STATUS_DECLINED.  This allows a subsequent provider to take
responsibility for providing the resource, rather than failing the
request outright.  If all providers decline to service the request,
either through tolerated failure or a genuine disinclination to
comply, then a 'E<lt>resourceE<gt> not found' exception is raised.




=item DEBUG

The DEBUG option can be used to enable debugging messages from the
Template::Filters module by setting it to include the DEBUG_FILTERS
value.

    use Template::Constants qw( :debug );

    my $template = Template->new({
	DEBUG => DEBUG_FILTERS | DEBUG_PLUGINS,
    });




=back

=head1 TEMPLATE TOOLKIT FILTERS

The following standard filters are distributed with the Template Toolkit.



=head2 format(format)

The 'format' filter takes a format string as a parameter (as per
printf()) and formats each line of text accordingly.

    [% FILTER format('<!-- %-40s -->') %]
    This is a block of text filtered 
    through the above format.
    [% END %]

output:

    <!-- This is a block of text filtered        -->
    <!-- through the above format.               -->

=head2 upper

Folds the input to UPPER CASE.

    [% "hello world" FILTER upper %]

output:

    HELLO WORLD

=head2 lower

Folds the input to lower case.

    [% "Hello World" FILTER lower %]

output:

    hello world

=head2 ucfirst

Folds the first character of the input to UPPER CASE.

    [% "hello" FILTER ucfirst %]

output:

    Hello

=head2 lcfirst

Folds the first character of the input to lower case.

    [% "HELLO" FILTER lcfirst %]

output:

    hELLO

=head2 trim

Trims any leading or trailing whitespace from the input text.  Particularly 
useful in conjunction with INCLUDE, PROCESS, etc., having the same effect
as the TRIM configuration option.

    [% INCLUDE myfile | trim %]

=head2 collapse

Collapse any whitespace sequences in the input text into a single space.
Leading and trailing whitespace (which would be reduced to a single space)
is removed, as per trim.

    [% FILTER collapse %]

       The   cat

       sat    on

       the   mat

    [% END %]

output:

    The cat sat on the mat

=head2 html

Converts the characters 'E<lt>', 'E<gt>', '&' and '"' to '&lt;',
'&gt;', '&amp;', and '&quot;' respectively, protecting them from being
interpreted as representing HTML tags or entities.

    [% FILTER html %]
    Binary "<=>" returns -1, 0, or 1 depending on...
    [% END %]

output:

    Binary "&lt;=&gt;" returns -1, 0, or 1 depending on...

=head2 html_entity

The html filter is fast and simple but it doesn't encode the full
range of HTML entities that your text may contain.  The html_entity
filter uses either the Apache::Util module (which is written in C and
is therefore faster) or the HTML::Entities module (written in Perl but
equally as comprehensive) to perform the encoding.  If one or other of
these modules are installed on your system then the text will be
encoded (via the escape_html() or encode_entities() subroutines
respectively) to convert all extended characters into their
appropriate HTML entities (e.g. converting 'é' to '&eacute;').  If
neither module is available on your system then an 'html_entity' exception
will be thrown reporting an appropriate message.   

For further information on HTML entity encoding, see
http://www.w3.org/TR/REC-html40/sgml/entities.html.

=head2 html_para

This filter formats a block of text into HTML paragraphs.  A sequence of 
two or more newlines is used as the delimiter for paragraphs which are 
then wrapped in HTML E<lt>pE<gt>...E<lt>/pE<gt> tags.

    [% FILTER html_para %]
    The cat sat on the mat.

    Mary had a little lamb.
    [% END %]

output:

    <p>
    The cat sat on the mat.
    </p>

    <p>
    Mary had a little lamb.
    </p>

=head2 html_break / html_para_break

Similar to the html_para filter described above, but uses the HTML tag
sequence E<lt>brE<gt>E<lt>brE<gt> to join paragraphs.

    [% FILTER html_break %]
    The cat sat on the mat.

    Mary had a little lamb.
    [% END %]

output:

    The cat sat on the mat.
    <br>
    <br>
    Mary had a little lamb.

=head2 html_line_break

This filter replaces any newlines with E<lt>brE<gt> HTML tags,
thus preserving the line breaks of the original text in the 
HTML output.

    [% FILTER html_line_break %]
    The cat sat on the mat.
    Mary had a little lamb.
    [% END %]

output:

    The cat sat on the mat.<br>
    Mary had a little lamb.<br>

=head2 uri

This filter URI escapes the input text, converting any characters 
outside of the permitted URI character set (as defined by RFC 2396)
into a C<%nn> hex escape.

    [% 'my file.html' | uri %]

output:

    my%20file.html

Note that URI escaping isn't always enough when generating hyperlinks in
an HTML document.  The C<&> character, for example, is valid in a URI and
will not be escaped by the URI filter.  In this case you should also filter
the text through the 'html' filter.

    <a href="[% filename | uri | html %]">click here</a>

=head2 indent(pad)

Indents the text block by a fixed pad string or width.  The 'pad' argument
can be specified as a string, or as a numerical value to indicate a pad
width (spaces).  Defaults to 4 spaces if unspecified.

    [% FILTER indent('ME> ') %]
    blah blah blah
    cabbages, rhubard, onions
    [% END %]

output:

    ME> blah blah blah
    ME> cabbages, rhubard, onions

=head2 truncate(length,dots)

Truncates the text block to the length specified, or a default length
of 32.  Truncated text will be terminated with '...' (i.e. the '...'
falls inside the required length, rather than appending to it).

    [% FILTER truncate(21) %]
    I have much to say on this matter that has previously 
    been said on more than one occasion.
    [% END %]

output:

    I have much to say...

If you want to use something other than '...' you can pass that as a 
second argument.

    [% FILTER truncate(26, '&hellip;') %]
    I have much to say on this matter that has previously 
    been said on more than one occasion.
    [% END %]

output:

    I have much to say&hellip;

=head2 repeat(iterations)

Repeats the text block for as many iterations as are specified (default: 1).

    [% FILTER repeat(3) %]
    We want more beer and we want more beer,
    [% END %]
    We are the more beer wanters!

output:

    We want more beer and we want more beer,
    We want more beer and we want more beer,
    We want more beer and we want more beer,
    We are the more beer wanters!

=head2 remove(string) 

Searches the input text for any occurrences of the specified string and 
removes them.  A Perl regular expression may be specified as the search 
string.

    [% "The  cat  sat  on  the  mat" FILTER remove('\s+') %]

output: 

    Thecatsatonthemat

=head2 replace(search, replace) 

Similar to the remove filter described above, but taking a second parameter
which is used as a replacement string for instances of the search string.

    [% "The  cat  sat  on  the  mat" | replace('\s+', '_') %]

output: 

    The_cat_sat_on_the_mat

=head2 redirect(file, options)

The 'redirect' filter redirects the output of the block into a separate
file, specified relative to the OUTPUT_PATH configuration item.

    [% FOREACH user = myorg.userlist %]
       [% FILTER redirect("users/${user.id}.html") %]
          [% INCLUDE userinfo %]
       [% END %]
    [% END %]

or more succinctly, using side-effect notation:

    [% INCLUDE userinfo 
         FILTER redirect("users/${user.id}.html")
	   FOREACH user = myorg.userlist 
    %]

A 'file' exception will be thrown if the OUTPUT_PATH option is undefined.

An optional 'binmode' argument can follow the filename to explicitly set
the output file to binary mode.

    [% PROCESS my/png/generator 
         FILTER redirect("images/logo.png", binmode=1) %]

For backwards compatibility with earlier versions, a single true/false
value can be used to set binary mode.

    [% PROCESS my/png/generator 
         FILTER redirect("images/logo.png", 1) %]

For the sake of future compatibility and clarity, if nothing else, we
would strongly recommend you explicitly use the named 'binmode' option
as shown in the first example.

=head2 eval / evaltt

The 'eval' filter evaluates the block as template text, processing
any directives embedded within it.  This allows template variables to
contain template fragments, or for some method to be provided for
returning template fragments from an external source such as a
database, which can then be processed in the template as required.

    my $vars  = {
	fragment => "The cat sat on the [% place %]",
    };
    $template->process($file, $vars);

The following example:

    [% fragment | eval %]

is therefore equivalent to 

    The cat sat on the [% place %]

The 'evaltt' filter is provided as an alias for 'eval'.

=head2 perl / evalperl

The 'perl' filter evaluates the block as Perl code.  The EVAL_PERL
option must be set to a true value or a 'perl' exception will be
thrown.

    [% my_perl_code | perl %]

In most cases, the [% PERL %] ... [% END %] block should suffice for 
evaluating Perl code, given that template directives are processed 
before being evaluate as Perl.  Thus, the previous example could have
been written in the more verbose form:

    [% PERL %]
    [% my_perl_code %]
    [% END %]

as well as

    [% FILTER perl %]
    [% my_perl_code %]
    [% END %]

The 'evalperl' filter is provided as an alias for 'perl' for backwards
compatibility.

=head2 stdout(options)

The stdout filter prints the output generated by the enclosing block to
STDOUT.  The 'binmode' option can be passed as either a named parameter
or a single argument to set STDOUT to binary mode (see the
binmode perl function).

    [% PROCESS something/cool
           FILTER stdout(binmode=1) # recommended %]

    [% PROCESS something/cool
           FILTER stdout(1)         # alternate %]

The stdout filter can be used to force binmode on STDOUT, or also inside
redirect, null or stderr blocks to make sure that particular output goes
to stdout. See the null filter below for an example.

=head2 stderr

The stderr filter prints the output generated by the enclosing block to
STDERR.

=head2 null

The null filter prints nothing.  This is useful for plugins whose
methods return values that you don't want to appear in the output.
Rather than assigning every plugin method call to a dummy variable
to silence it, you can wrap the block in a null filter:

    [% FILTER null;
        USE im = GD.Image(100,100);
        black = im.colorAllocate(0,   0, 0);
        red   = im.colorAllocate(255,0,  0);
        blue  = im.colorAllocate(0,  0,  255);
        im.arc(50,50,95,75,0,360,blue);
        im.fill(50,50,red);
        im.png | stdout(1);
       END;
    -%]

Notice the use of the stdout filter to ensure that a particular expression
generates output to stdout (in this case in binary mode).

=head2 latex(outputType)

The latex() filter is no longer part of the core Template Toolkit
distribution as of version 2.15.  You can download it as a 
separate Template-Latex distribution from CPAN.

=head1 AUTHOR

Andy Wardley E<lt>abw@wardley.orgE<gt>

L<http://wardley.org/|http://wardley.org/>




=head1 VERSION

2.81, distributed as part of the
Template Toolkit version 2.15, released on 26 May 2006.

=head1 COPYRIGHT

  Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template|Template>, L<Template::Context|Template::Context>, L<Template::Manual::Filters|Template::Manual::Filters>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
