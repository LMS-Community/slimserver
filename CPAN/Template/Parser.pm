#============================================================= -*-Perl-*-
#
# Template::Parser
#
# DESCRIPTION
#   This module implements a LALR(1) parser and assocated support 
#   methods to parse template documents into the appropriate "compiled"
#   format.  Much of the parser DFA code (see _parse() method) is based 
#   on Francois Desarmenien's Parse::Yapp module.  Kudos to him.
# 
# AUTHOR
#   Andy Wardley <abw@cpan.org>
#
# COPYRIGHT
#   Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
#   Copyright (C) 1998-2000 Canon Research Centre Europe Ltd.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#   The following copyright notice appears in the Parse::Yapp 
#   documentation.  
#
#      The Parse::Yapp module and its related modules and shell
#      scripts are copyright (c) 1998 Francois Desarmenien,
#      France. All rights reserved.
#
#      You may use and distribute them under the terms of either
#      the GNU General Public License or the Artistic License, as
#      specified in the Perl README file.
# 
# REVISION
#   $Id: Parser.pm,v 2.86 2006/05/25 11:43:39 abw Exp $
#
#============================================================================

package Template::Parser;

use strict;
use warnings;
use base 'Template::Base';

use Template::Constants qw( :status :chomp );
use Template::Directive;
use Template::Grammar;

# parser state constants
use constant CONTINUE => 0;
use constant ACCEPT   => 1;
use constant ERROR    => 2;
use constant ABORT    => 3;

our $VERSION = sprintf("%d.%02d", q$Revision: 2.86 $ =~ /(\d+)\.(\d+)/);
our $DEBUG   = 0 unless defined $DEBUG;
our $ERROR   = '';


#========================================================================
#                        -- COMMON TAG STYLES --
#========================================================================

our $TAG_STYLE   = {
    'default'   => [ '\[%',    '%\]'    ],
    'template1' => [ '[\[%]%', '%[\]%]' ],
    'metatext'  => [ '%%',     '%%'     ],
    'html'      => [ '<!--',   '-->'    ],
    'mason'     => [ '<%',     '>'      ],
    'asp'       => [ '<%',     '%>'     ],
    'php'       => [ '<\?',    '\?>'    ],
    'star'      => [ '\[\*',   '\*\]'   ],
};
$TAG_STYLE->{ template } = $TAG_STYLE->{ tt2 } = $TAG_STYLE->{ default };


our $DEFAULT_STYLE = {
    START_TAG   => $TAG_STYLE->{ default }->[0],
    END_TAG     => $TAG_STYLE->{ default }->[1],
#    TAG_STYLE   => 'default',
    ANYCASE     => 0,
    INTERPOLATE => 0,
    PRE_CHOMP   => 0,
    POST_CHOMP  => 0,
    V1DOLLAR    => 0,
    EVAL_PERL   => 0,
};

our $QUOTED_ESCAPES = {
	n => "\n",
	r => "\r",
	t => "\t",
};

# note that '-' must come first so Perl doesn't think it denotes a range
our $CHOMP_FLAGS  = qr/[-=~+]/;



#========================================================================
#                      -----  PUBLIC METHODS -----
#========================================================================

#------------------------------------------------------------------------
# new(\%config)
#
# Constructor method. 
#------------------------------------------------------------------------

sub new {
    my $class  = shift;
    my $config = $_[0] && UNIVERSAL::isa($_[0], 'HASH') ? shift(@_) : { @_ };
    my ($tagstyle, $debug, $start, $end, $defaults, $grammar, $hash, $key, $udef);

    my $self = bless { 
        START_TAG   => undef,
        END_TAG     => undef,
        TAG_STYLE   => 'default',
        ANYCASE     => 0,
        INTERPOLATE => 0,
        PRE_CHOMP   => 0,
        POST_CHOMP  => 0,
        V1DOLLAR    => 0,
        EVAL_PERL   => 0,
        FILE_INFO   => 1,
        GRAMMAR     => undef,
        _ERROR      => '',
        FACTORY     => 'Template::Directive',
    }, $class;

    # update self with any relevant keys in config
    foreach $key (keys %$self) {
        $self->{ $key } = $config->{ $key } if defined $config->{ $key };
    }
    $self->{ FILEINFO } = [ ];
    
    # DEBUG config item can be a bitmask
    if (defined ($debug = $config->{ DEBUG })) {
        $self->{ DEBUG } = $debug & ( Template::Constants::DEBUG_PARSER
                                    | Template::Constants::DEBUG_FLAGS );
        $self->{ DEBUG_DIRS } = $debug & Template::Constants::DEBUG_DIRS;
    }
    # package variable can be set to 1 to support previous behaviour
    elsif ($DEBUG == 1) {
        $self->{ DEBUG } = Template::Constants::DEBUG_PARSER;
        $self->{ DEBUG_DIRS } = 0;
    }
    # otherwise let $DEBUG be a bitmask
    else {
        $self->{ DEBUG } = $DEBUG & ( Template::Constants::DEBUG_PARSER
                                    | Template::Constants::DEBUG_FLAGS );
        $self->{ DEBUG_DIRS } = $DEBUG & Template::Constants::DEBUG_DIRS;
    }

    $grammar = $self->{ GRAMMAR } ||= do {
        require Template::Grammar;
        Template::Grammar->new();
    };

    # build a FACTORY object to include any NAMESPACE definitions,
    # but only if FACTORY isn't already an object
    if ($config->{ NAMESPACE } && ! ref $self->{ FACTORY }) {
        my $fclass = $self->{ FACTORY };
        $self->{ FACTORY } = $fclass->new( NAMESPACE => $config->{ NAMESPACE } )
            || return $class->error($fclass->error());
    }
    
    # load grammar rules, states and lex table
    @$self{ qw( LEXTABLE STATES RULES ) } 
        = @$grammar{ qw( LEXTABLE STATES RULES ) };
    
    $self->new_style($config)
        || return $class->error($self->error());
	
    return $self;
}


#------------------------------------------------------------------------
# new_style(\%config)
# 
# Install a new (stacked) parser style.  This feature is currently 
# experimental but should mimic the previous behaviour with regard to 
# TAG_STYLE, START_TAG, END_TAG, etc.
#------------------------------------------------------------------------

sub new_style {
    my ($self, $config) = @_;
    my $styles = $self->{ STYLE } ||= [ ];
    my ($tagstyle, $tags, $start, $end, $key);

    # clone new style from previous or default style
    my $style  = { %{ $styles->[-1] || $DEFAULT_STYLE } };

    # expand START_TAG and END_TAG from specified TAG_STYLE
    if ($tagstyle = $config->{ TAG_STYLE }) {
        return $self->error("Invalid tag style: $tagstyle")
            unless defined ($tags = $TAG_STYLE->{ $tagstyle });
        ($start, $end) = @$tags;
        $config->{ START_TAG } ||= $start;
        $config->{   END_TAG } ||= $end;
    }

    foreach $key (keys %$DEFAULT_STYLE) {
        $style->{ $key } = $config->{ $key } if defined $config->{ $key };
    }
    push(@$styles, $style);
    return $style;
}


#------------------------------------------------------------------------
# old_style()
#
# Pop the current parser style and revert to the previous one.  See 
# new_style().   ** experimental **
#------------------------------------------------------------------------

sub old_style {
    my $self = shift;
    my $styles = $self->{ STYLE };
    return $self->error('only 1 parser style remaining')
        unless (@$styles > 1);
    pop @$styles;
    return $styles->[-1];
}


#------------------------------------------------------------------------
# parse($text, $data)
#
# Parses the text string, $text and returns a hash array representing
# the compiled template block(s) as Perl code, in the format expected
# by Template::Document.
#------------------------------------------------------------------------

sub parse {
    my ($self, $text, $info) = @_;
    my ($tokens, $block);

    $info->{ DEBUG } = $self->{ DEBUG_DIRS }
	unless defined $info->{ DEBUG };

#    print "info: { ", join(', ', map { "$_ => $info->{ $_ }" } keys %$info), " }\n";

    # store for blocks defined in the template (see define_block())
    my $defblock = $self->{ DEFBLOCK } = { };
    my $metadata = $self->{ METADATA } = [ ];

    $self->{ _ERROR } = '';

    # split file into TEXT/DIRECTIVE chunks
    $tokens = $self->split_text($text)
        || return undef;				    ## RETURN ##

    push(@{ $self->{ FILEINFO } }, $info);

    # parse chunks
    $block = $self->_parse($tokens, $info);

    pop(@{ $self->{ FILEINFO } });

    return undef unless $block;				    ## RETURN ##

    $self->debug("compiled main template document block:\n$block")
        if $self->{ DEBUG } & Template::Constants::DEBUG_PARSER;

    return {
        BLOCK     => $block,
        DEFBLOCKS => $defblock,
        METADATA  => { @$metadata },
    };
}



#------------------------------------------------------------------------
# split_text($text)
#
# Split input template text into directives and raw text chunks.
#------------------------------------------------------------------------

sub split_text {
    my ($self, $text) = @_;
    my ($pre, $dir, $prelines, $dirlines, $postlines, $chomp, $tags, @tags);
    my $style = $self->{ STYLE }->[-1];
    my ($start, $end, $prechomp, $postchomp, $interp ) = 
        @$style{ qw( START_TAG END_TAG PRE_CHOMP POST_CHOMP INTERPOLATE ) };

    my @tokens = ();
    my $line = 1;

    return \@tokens					    ## RETURN ##
	unless defined $text && length $text;

    # extract all directives from the text
    while ($text =~ s/
           ^(.*?)               # $1 - start of line up to directive
           (?:
            $start          # start of tag
            (.*?)           # $2 - tag contents
            $end            # end of tag
            )
           //sx) {
        
        ($pre, $dir) = ($1, $2);
        $pre = '' unless defined $pre;
        $dir = '' unless defined $dir;
        
        $prelines  = ($pre =~ tr/\n//);  # newlines in preceeding text
        $dirlines  = ($dir =~ tr/\n//);  # newlines in directive tag
        $postlines = 0;                  # newlines chomped after tag
        
        for ($dir) {
            if (/^\#/) {
                # comment out entire directive except for any end chomp flag
                $dir = ($dir =~ /($CHOMP_FLAGS)$/o) ? $1 : '';
            }
            else {
                s/^($CHOMP_FLAGS)?\s*//so;
                # PRE_CHOMP: process whitespace before tag
                $chomp = $1 ? $1 : $prechomp;
                $chomp =~ tr/-=~+/1230/;
                if ($chomp && $pre) {
                    # chomp off whitespace and newline preceding directive
                    if ($chomp == CHOMP_ALL) { 
                        $pre =~ s{ (\n|^) [^\S\n]* \z }{}mx;
                    }
                    elsif ($chomp == CHOMP_COLLAPSE) { 
                        $pre =~ s{ (\s+) \z }{ }x;
                    }
                    elsif ($chomp == CHOMP_GREEDY) { 
                        $pre =~ s{ (\s+) \z }{}x;
                    }
                }
            }
            
            # POST_CHOMP: process whitespace after tag
            s/\s*($CHOMP_FLAGS)?\s*$//so;
            $chomp = $1 ? $1 : $postchomp;
            $chomp =~ tr/-=~+/1230/;
            if ($chomp) {
                if ($chomp == CHOMP_ALL) { 
                    $text =~ s{ ^ ([^\S\n]* \n) }{}x  
                        && $postlines++;
                }
                elsif ($chomp == CHOMP_COLLAPSE) { 
                    $text =~ s{ ^ (\s+) }{ }x  
                        && ($postlines += $1=~y/\n//);
                }
                # any trailing whitespace
                elsif ($chomp == CHOMP_GREEDY) { 
                    $text =~ s{ ^ (\s+) }{}x  
                        && ($postlines += $1=~y/\n//);
                }
            }
        }
            
        # any text preceding the directive can now be added
        if (length $pre) {
            push(@tokens, $interp
                 ? [ $pre, $line, 'ITEXT' ]
                 : ('TEXT', $pre) );
        }
        $line += $prelines;
            
        # and now the directive, along with line number information
        if (length $dir) {
            # the TAGS directive is a compile-time switch
            if ($dir =~ /^TAGS\s+(.*)/i) {
                my @tags = split(/\s+/, $1);
                if (scalar @tags > 1) {
                    ($start, $end) = map { quotemeta($_) } @tags;
                }
                elsif ($tags = $TAG_STYLE->{ $tags[0] }) {
                    ($start, $end) = @$tags;
                }
                else {
                    warn "invalid TAGS style: $tags[0]\n";
                }
            }
            else {
                # DIRECTIVE is pushed as:
                #   [ $dirtext, $line_no(s), \@tokens ]
                push(@tokens, 
                     [ $dir, 
                       ($dirlines 
                        ? sprintf("%d-%d", $line, $line + $dirlines)
                        : $line),
                       $self->tokenise_directive($dir) ]);
            }
        }
            
        # update line counter to include directive lines and any extra
        # newline chomped off the start of the following text
        $line += $dirlines + $postlines;
    }
        
    # anything remaining in the string is plain text 
    push(@tokens, $interp 
         ? [ $text, $line, 'ITEXT' ]
         : ( 'TEXT', $text) )
        if length $text;
        
    return \@tokens;					    ## RETURN ##
}
    


#------------------------------------------------------------------------
# interpolate_text($text, $line)
#
# Examines $text looking for any variable references embedded like
# $this or like ${ this }.
#------------------------------------------------------------------------

sub interpolate_text {
    my ($self, $text, $line) = @_;
    my @tokens  = ();
    my ($pre, $var, $dir);


   while ($text =~
           /
           ( (?: \\. | [^\$] ){1,3000} ) # escaped or non-'$' character [$1]
           |
	   ( \$ (?:		    # embedded variable	           [$2]
	     (?: \{ ([^\}]*) \} )   # ${ ... }                     [$3]
	     |
	     ([\w\.]+)		    # $word                        [$4]
	     )
	   )
	/gx) {

	($pre, $var, $dir) = ($1, $3 || $4, $2);

	# preceding text
	if (defined($pre) && length($pre)) {
	    $line += $pre =~ tr/\n//;
	    $pre =~ s/\\\$/\$/g;
	    push(@tokens, 'TEXT', $pre);
	}
	# $variable reference
        if ($var) {
	    $line += $dir =~ tr/\n/ /;
	    push(@tokens, [ $dir, $line, $self->tokenise_directive($var) ]);
	}
	# other '$' reference - treated as text
	elsif ($dir) {
	    $line += $dir =~ tr/\n//;
	    push(@tokens, 'TEXT', $dir);
	}
    }

    return \@tokens;
}



#------------------------------------------------------------------------
# tokenise_directive($text)
#
# Called by the private _parse() method when it encounters a DIRECTIVE
# token in the list provided by the split_text() or interpolate_text()
# methods.  The directive text is passed by parameter.
#
# The method splits the directive into individual tokens as recognised
# by the parser grammar (see Template::Grammar for details).  It
# constructs a list of tokens each represented by 2 elements, as per
# split_text() et al.  The first element contains the token type, the
# second the token itself.
#
# The method tokenises the string using a complex (but fast) regex.
# For a deeper understanding of the regex magic at work here, see
# Jeffrey Friedl's excellent book "Mastering Regular Expressions",
# from O'Reilly, ISBN 1-56592-257-3
#
# Returns a reference to the list of chunks (each one being 2 elements) 
# identified in the directive text.  On error, the internal _ERROR string 
# is set and undef is returned.
#------------------------------------------------------------------------

sub tokenise_directive {
    my ($self, $text, $line) = @_;
    my ($token, $uctoken, $type, $lookup);
    my $lextable = $self->{ LEXTABLE };
    my $style    = $self->{ STYLE }->[-1];
    my ($anycase, $start, $end) = @$style{ qw( ANYCASE START_TAG END_TAG ) };
    my @tokens = ( );

    while ($text =~ 
	    / 
		# strip out any comments
	        (\#[^\n]*)
	   |
		# a quoted phrase matches in $3
		(["'])                   # $2 - opening quote, ' or "
		(                        # $3 - quoted text buffer
		    (?:                  # repeat group (no backreference)
			\\\\             # an escaped backslash \\
		    |                    # ...or...
			\\\2             # an escaped quote \" or \' (match $1)
		    |                    # ...or...
			.                # any other character
		    |	\n
		    )*?                  # non-greedy repeat
		)                        # end of $3
		\2                       # match opening quote
	    |
		# an unquoted number matches in $4
		(-?\d+(?:\.\d+)?)       # numbers
	    |
		# filename matches in $5
	    	( \/?\w+(?:(?:\/|::?)\w*)+ | \/\w+)
	    |
		# an identifier matches in $6
		(\w+)                    # variable identifier
	    |   
		# an unquoted word or symbol matches in $7
		(   [(){}\[\]:;,\/\\]    # misc parenthesis and symbols
#		|   \->                  # arrow operator (for future?)
		|   [+\-*]               # math operations
		|   \$\{?                # dollar with option left brace
		|   =>			 # like '='
		|   [=!<>]?= | [!<>]     # eqality tests
		|   &&? | \|\|?          # boolean ops
		|   \.\.?                # n..n sequence
 		|   \S+                  # something unquoted
		)                        # end of $7
	    /gmxo) {

	# ignore comments to EOL
	next if $1;

	# quoted string
	if (defined ($token = $3)) {
            # double-quoted string may include $variable references
	    if ($2 eq '"') {
	        if ($token =~ /[\$\\]/) {
		    $type = 'QUOTED';
		    # unescape " and \ but leave \$ escaped so that 
			# interpolate_text() doesn't incorrectly treat it
		    # as a variable reference
#		    $token =~ s/\\([\\"])/$1/g;
			for ($token) {
				s/\\([^\$nrt])/$1/g;
				s/\\([nrt])/$QUOTED_ESCAPES->{ $1 }/ge;
			}
		    push(@tokens, ('"') x 2,
				  @{ $self->interpolate_text($token) },
				  ('"') x 2);
		    next;
		}
                else {
	            $type = 'LITERAL';
		    $token =~ s['][\\']g;
		    $token = "'$token'";
		}
	    } 
	    else {
		$type = 'LITERAL';
		$token = "'$token'";
	    }
	}
	# number
	elsif (defined ($token = $4)) {
	    $type = 'NUMBER';
	}
	elsif (defined($token = $5)) {
	    $type = 'FILENAME';
	}
	elsif (defined($token = $6)) {
	    # reserved words may be in lower case unless case sensitive
	    $uctoken = $anycase ? uc $token : $token;
	    if (defined ($type = $lextable->{ $uctoken })) {
		$token = $uctoken;
	    }
	    else {
		$type = 'IDENT';
	    }
	}
	elsif (defined ($token = $7)) {
	    # reserved words may be in lower case unless case sensitive
	    $uctoken = $anycase ? uc $token : $token;
	    unless (defined ($type = $lextable->{ $uctoken })) {
		$type = 'UNQUOTED';
	    }
	}

	push(@tokens, $type, $token);

#	print(STDERR " +[ $type, $token ]\n")
#	    if $DEBUG;
    }

#    print STDERR "tokenise directive() returning:\n  [ @tokens ]\n"
#	if $DEBUG;

    return \@tokens;					    ## RETURN ##
}


#------------------------------------------------------------------------
# define_block($name, $block)
#
# Called by the parser 'defblock' rule when a BLOCK definition is 
# encountered in the template.  The name of the block is passed in the 
# first parameter and a reference to the compiled block is passed in
# the second.  This method stores the block in the $self->{ DEFBLOCK }
# hash which has been initialised by parse() and will later be used 
# by the same method to call the store() method on the calling cache
# to define the block "externally".
#------------------------------------------------------------------------

sub define_block {
    my ($self, $name, $block) = @_;
    my $defblock = $self->{ DEFBLOCK } 
        || return undef;

    $self->debug("compiled block '$name':\n$block")
	if $self->{ DEBUG } & Template::Constants::DEBUG_PARSER;

    $defblock->{ $name } = $block;
    
    return undef;
}

sub push_defblock {
    my $self = shift;
    my $stack = $self->{ DEFBLOCK_STACK } ||= [];
    push(@$stack, $self->{ DEFBLOCK } );
    $self->{ DEFBLOCK } = { };
}

sub pop_defblock {
    my $self  = shift;
    my $defs  = $self->{ DEFBLOCK };
    my $stack = $self->{ DEFBLOCK_STACK } || return $defs;
    return $defs unless @$stack;
    $self->{ DEFBLOCK } = pop @$stack;
    return $defs;
}


#------------------------------------------------------------------------
# add_metadata(\@setlist)
#------------------------------------------------------------------------

sub add_metadata {
    my ($self, $setlist) = @_;
    my $metadata = $self->{ METADATA } 
        || return undef;

    push(@$metadata, @$setlist);
    
    return undef;
}


#------------------------------------------------------------------------
# location()
#
# Return Perl comment indicating current parser file and line
#------------------------------------------------------------------------

sub location {
    my $self = shift;
    return "\n" unless $self->{ FILE_INFO };
    my $line = ${ $self->{ LINE } };
    my $info = $self->{ FILEINFO }->[-1];
    my $file = $info->{ path } || $info->{ name } 
        || '(unknown template)';
    $line =~ s/\-.*$//; # might be 'n-n'
    return "#line $line \"$file\"\n";
}


#========================================================================
#                     -----  PRIVATE METHODS -----
#========================================================================

#------------------------------------------------------------------------
# _parse(\@tokens, \@info)
#
# Parses the list of input tokens passed by reference and returns a 
# Template::Directive::Block object which contains the compiled 
# representation of the template. 
#
# This is the main parser DFA loop.  See embedded comments for 
# further details.
#
# On error, undef is returned and the internal _ERROR field is set to 
# indicate the error.  This can be retrieved by calling the error() 
# method.
#------------------------------------------------------------------------

sub _parse {
    my ($self, $tokens, $info) = @_;
    my ($token, $value, $text, $line, $inperl);
    my ($state, $stateno, $status, $action, $lookup, $coderet, @codevars);
    my ($lhs, $len, $code);	    # rule contents
    my $stack = [ [ 0, undef ] ];   # DFA stack

# DEBUG
#   local $" = ', ';

    # retrieve internal rule and state tables
    my ($states, $rules) = @$self{ qw( STATES RULES ) };

    # call the grammar set_factory method to install emitter factory
    $self->{ GRAMMAR }->install_factory($self->{ FACTORY });

    $line = $inperl = 0;
    $self->{ LINE   } = \$line;
    $self->{ FILE   } = $info->{ name };
    $self->{ INPERL } = \$inperl;

    $status = CONTINUE;
    my $in_string = 0;

    while(1) {
	# get state number and state
	$stateno =  $stack->[-1]->[0];
	$state   = $states->[$stateno];

	# see if any lookaheads exist for the current state
	if (exists $state->{'ACTIONS'}) {

	    # get next token and expand any directives (i.e. token is an 
	    # array ref) onto the front of the token list
	    while (! defined $token && @$tokens) {
		$token = shift(@$tokens);
		if (ref $token) {
		    ($text, $line, $token) = @$token;
		    if (ref $token) {
			if ($info->{ DEBUG } && ! $in_string) {
                            # - - - - - - - - - - - - - - - - - - - - - - - - -
			    # This is gnarly.  Look away now if you're easily
                            # frightened.  We're pushing parse tokens onto the
                            # pending list to simulate a DEBUG directive like so:
			    # [% DEBUG msg line='20' text='INCLUDE foo' %]
                            # - - - - - - - - - - - - - - - - - - - - - - - - -
			    my $dtext = $text;
			    $dtext =~ s[(['\\])][\\$1]g;
			    unshift(@$tokens, 
				    DEBUG   => 'DEBUG',
				    IDENT   => 'msg',
				    IDENT   => 'line',
				    ASSIGN  => '=',
				    LITERAL => "'$line'",
				    IDENT   => 'text',
				    ASSIGN  => '=',
				    LITERAL => "'$dtext'",
				    IDENT   => 'file',
				    ASSIGN  => '=',
				    LITERAL => "'$info->{ name }'",
				    (';') x 2,
				    @$token, 
				    (';') x 2);
			}
			else {
			    unshift(@$tokens, @$token, (';') x 2);
			}
			$token = undef;  # force redo
		    }
		    elsif ($token eq 'ITEXT') {
			if ($inperl) {
			    # don't perform interpolation in PERL blocks
			    $token = 'TEXT';
			    $value = $text;
			}
			else {
			    unshift(@$tokens, 
				    @{ $self->interpolate_text($text, $line) });
			    $token = undef; # force redo
			}
		    }
		}
		else {
		    # toggle string flag to indicate if we're crossing
		    # a string boundary
		    $in_string = ! $in_string if $token eq '"';
		    $value = shift(@$tokens);
		}
	    };
	    # clear undefined token to avoid 'undefined variable blah blah'
	    # warnings and let the parser logic pick it up in a minute
	    $token = '' unless defined $token;

	    # get the next state for the current lookahead token
	    $action = defined ($lookup = $state->{'ACTIONS'}->{ $token })
	              ? $lookup
		      : defined ($lookup = $state->{'DEFAULT'})
		        ? $lookup
		        : undef;
	}
	else {
	    # no lookahead actions
	    $action = $state->{'DEFAULT'};
	}

	# ERROR: no ACTION
	last unless defined $action;

	# - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	# shift (+ive ACTION)
	# - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	if ($action > 0) {
	    push(@$stack, [ $action, $value ]);
	    $token = $value = undef;
	    redo;
	};

	# - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	# reduce (-ive ACTION)
	# - - - - - - - - - - - - - - - - - - - - - - - - - - - -
	($lhs, $len, $code) = @{ $rules->[ -$action ] };

	# no action imples ACCEPTance
	$action
	    or $status = ACCEPT;

	# use dummy sub if code ref doesn't exist
	$code = sub { $_[1] }
	    unless $code;

	@codevars = $len
		?   map { $_->[1] } @$stack[ -$len .. -1 ]
		:   ();

	eval {
	    $coderet = &$code( $self, @codevars );
	};
	if ($@) {
	    my $err = $@;
	    chomp $err;
	    return $self->_parse_error($err);
	}

	# reduce stack by $len
	splice(@$stack, -$len, $len);

	# ACCEPT
	return $coderet					    ## RETURN ##
	    if $status == ACCEPT;

	# ABORT
	return undef					    ## RETURN ##
	    if $status == ABORT;

	# ERROR
	last 
	    if $status == ERROR;
    }
    continue {
	push(@$stack, [ $states->[ $stack->[-1][0] ]->{'GOTOS'}->{ $lhs }, 
	      $coderet ]), 
    }

    # ERROR						    ## RETURN ##
    return $self->_parse_error('unexpected end of input')
	unless defined $value;

    # munge text of last directive to make it readable
#    $text =~ s/\n/\\n/g;

    return $self->_parse_error("unexpected end of directive", $text)
	if $value eq ';';   # end of directive SEPARATOR

    return $self->_parse_error("unexpected token ($value)", $text);
}



#------------------------------------------------------------------------
# _parse_error($msg, $dirtext)
#
# Method used to handle errors encountered during the parse process
# in the _parse() method.  
#------------------------------------------------------------------------

sub _parse_error {
    my ($self, $msg, $text) = @_;
    my $line = $self->{ LINE };
    $line = ref($line) ? $$line : $line;
    $line = 'unknown' unless $line;

    $msg .= "\n  [% $text %]"
	if defined $text;

    return $self->error("line $line: $msg");
}


#------------------------------------------------------------------------
# _dump()
# 
# Debug method returns a string representing the internal state of the 
# object.
#------------------------------------------------------------------------

sub _dump {
    my $self = shift;
    my $output = "[Template::Parser] {\n";
    my $format = "    %-16s => %s\n";
    my $key;

    foreach $key (qw( START_TAG END_TAG TAG_STYLE ANYCASE INTERPOLATE 
		      PRE_CHOMP POST_CHOMP V1DOLLAR )) {
	my $val = $self->{ $key };
	$val = '<undef>' unless defined $val;
	$output .= sprintf($format, $key, $val);
    }

    $output .= '}';
    return $output;
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

Template::Parser - LALR(1) parser for compiling template documents

=head1 SYNOPSIS

    use Template::Parser;

    $parser   = Template::Parser->new(\%config);
    $template = $parser->parse($text)
        || die $parser->error(), "\n";

=head1 DESCRIPTION

The Template::Parser module implements a LALR(1) parser and associated methods
for parsing template documents into Perl code.  

=head1 PUBLIC METHODS

=head2 new(\%params)

The new() constructor creates and returns a reference to a new 
Template::Parser object.  A reference to a hash may be supplied as a 
parameter to provide configuration values.  These may include:

=over




=item START_TAG, END_TAG

The START_TAG and END_TAG options are used to specify character
sequences or regular expressions that mark the start and end of a
template directive.  The default values for START_TAG and END_TAG are
'[%' and '%]' respectively, giving us the familiar directive style:

    [% example %]

Any Perl regex characters can be used and therefore should be escaped
(or use the Perl C<quotemeta> function) if they are intended to
represent literal characters.

    my $parser = Template::Parser->new({ 
  	START_TAG => quotemeta('<+'),
  	END_TAG   => quotemeta('+>'),
    });

example:

    <+ INCLUDE foobar +>

The TAGS directive can also be used to set the START_TAG and END_TAG values
on a per-template file basis.

    [% TAGS <+ +> %]






=item TAG_STYLE

The TAG_STYLE option can be used to set both START_TAG and END_TAG
according to pre-defined tag styles.  

    my $parser = Template::Parser->new({ 
  	TAG_STYLE => 'star',
    });

Available styles are:

    template    [% ... %]               (default)
    template1   [% ... %] or %% ... %%  (TT version 1)
    metatext    %% ... %%               (Text::MetaText)
    star        [* ... *]               (TT alternate)
    php         <? ... ?>               (PHP)
    asp         <% ... %>               (ASP)
    mason       <% ...  >               (HTML::Mason)
    html        <!-- ... -->            (HTML comments)

Any values specified for START_TAG and/or END_TAG will over-ride
those defined by a TAG_STYLE.  

The TAGS directive may also be used to set a TAG_STYLE

    [% TAGS html %]
    <!-- INCLUDE header -->






=item PRE_CHOMP, POST_CHOMP

Anything outside a directive tag is considered plain text and is
generally passed through unaltered (but see the INTERPOLATE option).
This includes all whitespace and newlines characters surrounding
directive tags.  Directives that don't generate any output will leave
gaps in the output document.

Example:

    Foo
    [% a = 10 %]
    Bar

Output:

    Foo

    Bar

The PRE_CHOMP and POST_CHOMP options can help to clean up some of this
extraneous whitespace.  Both are disabled by default.

    my $parser = Template::Parser-E<gt>new({
        PRE_CHOMP  =E<gt> 1,
        POST_CHOMP =E<gt> 1,
    });

With PRE_CHOMP set to 1, the newline and whitespace preceding a directive
at the start of a line will be deleted.  This has the effect of 
concatenating a line that starts with a directive onto the end of the 
previous line.

        Foo E<lt>----------.
                       |
    ,---(PRE_CHOMP)----'
    |
    `-- [% a = 10 %] --.
                       |
    ,---(POST_CHOMP)---'
    |
    `-E<gt> Bar

With POST_CHOMP set to 1, any whitespace after a directive up to and
including the newline will be deleted.  This has the effect of joining
a line that ends with a directive onto the start of the next line.

If PRE_CHOMP or POST_CHOMP is set to 2, all whitespace including any
number of newline will be removed and replaced with a single space.
This is useful for HTML, where (usually) a contiguous block of
whitespace is rendered the same as a single space.

With PRE_CHOMP or POST_CHOMP set to 3, all adjacent whitespace
(including newlines) will be removed entirely.

These values are defined as CHOMP_NONE, CHOMP_ONE, CHOMP_COLLAPSE and
CHOMP_GREEDY constants in the Template::Constants module.  CHOMP_ALL
is also defined as an alias for CHOMP_ONE to provide backwards
compatability with earlier version of the Template Toolkit.  

Additionally the chomp tag modifiers listed below may also be used for
the PRE_CHOMP and POST_CHOMP configuration.
 
     my $template = Template-E<gt>new({
        PRE_CHOMP  =E<lt> '~',
        POST_CHOMP =E<gt> '-',
     });

PRE_CHOMP and POST_CHOMP can be activated for individual directives by
placing a '-' immediately at the start and/or end of the directive.

    [% FOREACH user IN userlist %]
       [%- user -%]
    [% END %]

This has the same effect as CHOMP_ONE in removing all whitespace
before or after the directive up to and including the newline.  The
template will be processed as if written:

    [% FOREACH user IN userlist %][% user %][% END %]

To remove all whitespace including any number of newlines, use the '~' 
character instead.

    [% FOREACH user IN userlist %]
    
       [%~ user ~%]
    
    [% END %]

To collapse all whitespace to a single space, use the '=' character.

    [% FOREACH user IN userlist %]
 
       [%= user =%]
    
    [% END %]

Here the template is processed as if written:

    [% FOREACH user IN userlist %] [% user %] [% END %]

If you have PRE_CHOMP or POST_CHOMP set as configuration options then
you can use '+' to disable any chomping options (i.e.  leave the
whitespace intact) on a per-directive basis.

    [% FOREACH user = userlist %]
    User: [% user +%]
    [% END %]

With POST_CHOMP set to CHOMP_ONE, the above example would be parsed as
if written:

    [% FOREACH user = userlist %]User: [% user %]
    [% END %]

For reference, the PRE_CHOMP and POST_CHOMP configuration options may be set to any of the following:

     Constant      Value   Tag Modifier
     ----------------------------------
     CHOMP_NONE      0          +
     CHOMP_ONE       1          -
     CHOMP_COLLAPSE  2          =
     CHOMP_GREEDY    3          ~





=item INTERPOLATE

The INTERPOLATE flag, when set to any true value will cause variable 
references in plain text (i.e. not surrounded by START_TAG and END_TAG)
to be recognised and interpolated accordingly.  

    my $parser = Template::Parser->new({ 
  	INTERPOLATE => 1,
    });

Variables should be prefixed by a '$' to identify them.  Curly braces
can be used in the familiar Perl/shell style to explicitly scope the
variable name where required.

    # INTERPOLATE => 0
    <a href="http://[% server %]/[% help %]">
    <img src="[% images %]/help.gif"></a>
    [% myorg.name %]
  
    # INTERPOLATE => 1
    <a href="http://$server/$help">
    <img src="$images/help.gif"></a>
    $myorg.name
  
    # explicit scoping with {  }
    <img src="$images/${icon.next}.gif">

Note that a limitation in Perl's regex engine restricts the maximum length
of an interpolated template to around 32 kilobytes or possibly less.  Files
that exceed this limit in size will typically cause Perl to dump core with
a segmentation fault.  If you routinely process templates of this size 
then you should disable INTERPOLATE or split the templates in several 
smaller files or blocks which can then be joined backed together via 
PROCESS or INCLUDE.







=item ANYCASE

By default, directive keywords should be expressed in UPPER CASE.  The 
ANYCASE option can be set to allow directive keywords to be specified
in any case.

    # ANYCASE => 0 (default)
    [% INCLUDE foobar %]	# OK
    [% include foobar %]        # ERROR
    [% include = 10   %]        # OK, 'include' is a variable

    # ANYCASE => 1
    [% INCLUDE foobar %]	# OK
    [% include foobar %]	# OK
    [% include = 10   %]        # ERROR, 'include' is reserved word

One side-effect of enabling ANYCASE is that you cannot use a variable
of the same name as a reserved word, regardless of case.  The reserved
words are currently:

        GET CALL SET DEFAULT INSERT INCLUDE PROCESS WRAPPER 
    IF UNLESS ELSE ELSIF FOR FOREACH WHILE SWITCH CASE
    USE PLUGIN FILTER MACRO PERL RAWPERL BLOCK META
    TRY THROW CATCH FINAL NEXT LAST BREAK RETURN STOP 
    CLEAR TO STEP AND OR NOT MOD DIV END


The only lower case reserved words that cannot be used for variables,
regardless of the ANYCASE option, are the operators:

    and or not mod div








=item V1DOLLAR

In version 1 of the Template Toolkit, an optional leading '$' could be placed
on any template variable and would be silently ignored.

    # VERSION 1
    [% $foo %]       ===  [% foo %]
    [% $hash.$key %] ===  [% hash.key %]

To interpolate a variable value the '${' ... '}' construct was used.
Typically, one would do this to index into a hash array when the key
value was stored in a variable.

example:

    my $vars = {
	users => {
	    aba => { name => 'Alan Aardvark', ... },
	    abw => { name => 'Andy Wardley', ... },
            ...
	},
	uid => 'aba',
        ...
    };

    $template->process('user/home.html', $vars)
	|| die $template->error(), "\n";

'user/home.html':

    [% user = users.${uid} %]     # users.aba
    Name: [% user.name %]         # Alan Aardvark

This was inconsistent with double quoted strings and also the
INTERPOLATE mode, where a leading '$' in text was enough to indicate a
variable for interpolation, and the additional curly braces were used
to delimit variable names where necessary.  Note that this use is
consistent with UNIX and Perl conventions, among others.

    # double quoted string interpolation
    [% name = "$title ${user.name}" %]

    # INTERPOLATE = 1
    <img src="$images/help.gif"></a>
    <img src="$images/${icon.next}.gif">

For version 2, these inconsistencies have been removed and the syntax
clarified.  A leading '$' on a variable is now used exclusively to
indicate that the variable name should be interpolated
(e.g. subsituted for its value) before being used.  The earlier example
from version 1:

    # VERSION 1
    [% user = users.${uid} %]
    Name: [% user.name %]

can now be simplified in version 2 as:

    # VERSION 2
    [% user = users.$uid %]
    Name: [% user.name %]

The leading dollar is no longer ignored and has the same effect of
interpolation as '${' ... '}' in version 1.  The curly braces may
still be used to explicitly scope the interpolated variable name
where necessary.

e.g.

    [% user = users.${me.id} %]
    Name: [% user.name %]

The rule applies for all variables, both within directives and in
plain text if processed with the INTERPOLATE option.  This means that
you should no longer (if you ever did) add a leading '$' to a variable
inside a directive, unless you explicitly want it to be interpolated.

One obvious side-effect is that any version 1 templates with variables
using a leading '$' will no longer be processed as expected.  Given
the following variable definitions,

    [% foo = 'bar'
       bar = 'baz'
    %]

version 1 would interpret the following as:

    # VERSION 1
    [% $foo %] => [% GET foo %] => bar

whereas version 2 interprets it as:

    # VERSION 2
    [% $foo %] => [% GET $foo %] => [% GET bar %] => baz

In version 1, the '$' is ignored and the value for the variable 'foo' is 
retrieved and printed.  In version 2, the variable '$foo' is first interpolated
to give the variable name 'bar' whose value is then retrieved and printed.

The use of the optional '$' has never been strongly recommended, but
to assist in backwards compatibility with any version 1 templates that
may rely on this "feature", the V1DOLLAR option can be set to 1
(default: 0) to revert the behaviour and have leading '$' characters
ignored.

    my $parser = Template::Parser->new({
	V1DOLLAR => 1,
    });






=item GRAMMAR

The GRAMMAR configuration item can be used to specify an alternate
grammar for the parser.  This allows a modified or entirely new
template language to be constructed and used by the Template Toolkit.

Source templates are compiled to Perl code by the Template::Parser
using the Template::Grammar (by default) to define the language
structure and semantics.  Compiled templates are thus inherently
"compatible" with each other and there is nothing to prevent any
number of different template languages being compiled and used within
the same Template Toolkit processing environment (other than the usual
time and memory constraints).

The Template::Grammar file is constructed from a YACC like grammar
(using Parse::YAPP) and a skeleton module template.  These files are
provided, along with a small script to rebuild the grammar, in the
'parser' sub-directory of the distribution.  You don't have to know or
worry about these unless you want to hack on the template language or
define your own variant.  There is a README file in the same directory
which provides some small guidance but it is assumed that you know
what you're doing if you venture herein.  If you grok LALR parsers,
then you should find it comfortably familiar.

By default, an instance of the default Template::Grammar will be
created and used automatically if a GRAMMAR item isn't specified.

    use MyOrg::Template::Grammar;

    my $parser = Template::Parser->new({ 
       	GRAMMAR = MyOrg::Template::Grammar->new();
    });



=item DEBUG

The DEBUG option can be used to enable various debugging features
of the Template::Parser module.  

    use Template::Constants qw( :debug );

    my $template = Template->new({
	DEBUG => DEBUG_PARSER | DEBUG_DIRS,
    });

The DEBUG value can include any of the following.  Multiple values
should be combined using the logical OR operator, '|'.

=over 4

=item DEBUG_PARSER

This flag causes the L<Template::Parser|Template::Parser> to generate
debugging messages that show the Perl code generated by parsing and
compiling each template.

=item DEBUG_DIRS

This option causes the Template Toolkit to generate comments
indicating the source file, line and original text of each directive
in the template.  These comments are embedded in the template output
using the format defined in the DEBUG_FORMAT configuration item, or a
simple default format if unspecified.

For example, the following template fragment:

    
    Hello World

would generate this output:

    ## input text line 1 :  ##
    Hello 
    ## input text line 2 : World ##
    World


=back




=back

=head2 parse($text)

The parse() method parses the text passed in the first parameter and
returns a reference to a hash array of data defining the compiled
representation of the template text, suitable for passing to the
Template::Document new() constructor method.  On error, undef is
returned.

Example:

    $data = $parser->parse($text)
    	|| die $parser->error();

The $data hash reference returned contains a BLOCK item containing the
compiled Perl code for the template, a DEFBLOCKS item containing a
reference to a hash array of sub-template BLOCKs defined within in the
template, and a METADATA item containing a reference to a hash array
of metadata values defined in META tags.

=head1 AUTHOR

Andy Wardley E<lt>abw@wardley.orgE<gt>

L<http://wardley.org/|http://wardley.org/>






=head1 VERSION

2.86, distributed as part of the
Template Toolkit version 2.15, released on 26 May 2006.

 

=head1 COPYRIGHT

  Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.



The original Template::Parser module was derived from a standalone
parser generated by version 0.16 of the Parse::Yapp module.  The
following copyright notice appears in the Parse::Yapp documentation.

    The Parse::Yapp module and its related modules and shell
    scripts are copyright (c) 1998 Francois Desarmenien,
    France. All rights reserved.

    You may use and distribute them under the terms of either
    the GNU General Public License or the Artistic License, as
    specified in the Perl README file.

=head1 SEE ALSO

L<Template|Template>, L<Template::Grammar|Template::Grammar>, L<Template::Directive|Template::Directive>

