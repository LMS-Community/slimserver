#================================================================= -*-Perl-*- 
#
# Template::Directive
#
# DESCRIPTION
#   Factory module for constructing templates from Perl code.
#
# AUTHOR
#   Andy Wardley   <abw@kfs.org>
#
# WARNING
#   Much of this module is hairy, even furry in places.  It needs
#   a lot of tidying up and may even be moved into a different place 
#   altogether.  The generator code is often inefficient, particulary in 
#   being very anal about pretty-printing the Perl code all neatly, but 
#   at the moment, that's still high priority for the sake of easier
#   debugging.
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
# $Id: Directive.pm,v 2.19 2004/05/20 08:46:54 abw Exp $
#
#============================================================================

package Template::Directive;

require 5.004;

use strict;
use Template::Base;
use Template::Constants;
use Template::Exception;

use base qw( Template::Base );
use vars qw( $VERSION $DEBUG $PRETTY $WHILE_MAX $OUTPUT );

$VERSION = sprintf("%d.%02d", q$Revision: 2.19 $ =~ /(\d+)\.(\d+)/);

$WHILE_MAX = 1000 unless defined $WHILE_MAX;
$PRETTY    = 0 unless defined $PRETTY;
$OUTPUT    = '$output .= ';


sub _init {
    my ($self, $config) = @_;
    $self->{ NAMESPACE } = $config->{ NAMESPACE };
    return $self;
}


sub pad {
    my ($text, $pad) = @_;
    $pad = ' ' x ($pad * 4);
    $text =~ s/^(?!#line)/$pad/gm;
    $text;
}

#========================================================================
# FACTORY METHODS
#
# These methods are called by the parser to construct directive instances.
#========================================================================

#------------------------------------------------------------------------
# template($block)
#------------------------------------------------------------------------

sub template {
    my ($class, $block) = @_;
    $block = pad($block, 2) if $PRETTY;

    return "sub { return '' }" unless $block =~ /\S/;

    return <<EOF;
sub {
    my \$context = shift || die "template sub called without context\\n";
    my \$stash   = \$context->stash;
    my \$output  = '';
    my \$error;
    
    eval { BLOCK: {
$block
    } };
    if (\$@) {
        \$error = \$context->catch(\$@, \\\$output);
        die \$error unless \$error->type eq 'return';
    }

    return \$output;
}
EOF
}


#------------------------------------------------------------------------
# anon_block($block)                            [% BLOCK %] ... [% END %]
#------------------------------------------------------------------------

sub anon_block {
    my ($class, $block) = @_;
    $block = pad($block, 2) if $PRETTY;

    return <<EOF;

# BLOCK
$OUTPUT do {
    my \$output  = '';
    my \$error;
    
    eval { BLOCK: {
$block
    } };
    if (\$@) {
        \$error = \$context->catch(\$@, \\\$output);
        die \$error unless \$error->type eq 'return';
    }

    \$output;
};
EOF
}


#------------------------------------------------------------------------
# block($blocktext)
#------------------------------------------------------------------------

sub block {
    my ($class, $block) = @_;
    return join("\n", @{ $block || [] });
}


#------------------------------------------------------------------------
# textblock($text)
#------------------------------------------------------------------------

sub textblock {
    my ($class, $text) = @_;
    return "$OUTPUT " . &text($class, $text) . ';';
}


#------------------------------------------------------------------------
# text($text)
#------------------------------------------------------------------------

sub text {
    my ($class, $text) = @_;
    for ($text) {
        s/(["\$\@\\])/\\$1/g;
        s/\n/\\n/g;
    }
    return '"' . $text . '"';
}


#------------------------------------------------------------------------
# quoted(\@items)                                               "foo$bar"
#------------------------------------------------------------------------

sub quoted {
    my ($class, $items) = @_;
    return '' unless @$items;
    return ("('' . " . $items->[0] . ')') if scalar @$items == 1;
    return '(' . join(' . ', @$items) . ')';
#    my $r = '(' . join(' . ', @$items) . ' . "")';
#    print STDERR "[$r]\n";
#    return $r;
}


#------------------------------------------------------------------------
# ident(\@ident)                                             foo.bar(baz)
#------------------------------------------------------------------------

sub ident {
    my ($class, $ident) = @_;
    return "''" unless @$ident;
    my $ns;

    # does the first element of the identifier have a NAMESPACE
    # handler defined?
    if (ref $class && @$ident > 2 && ($ns = $class->{ NAMESPACE })) {
	my $key = $ident->[0];
	$key =~ s/^'(.+)'$/$1/s;
	if ($ns = $ns->{ $key }) {
	    return $ns->ident($ident);
	}
    }
	
    if (scalar @$ident <= 2 && ! $ident->[1]) {
        $ident = $ident->[0];
    }
    else {
        $ident = '[' . join(', ', @$ident) . ']';
    }
    return "\$stash->get($ident)";
}

#------------------------------------------------------------------------
# identref(\@ident)                                         \foo.bar(baz)
#------------------------------------------------------------------------

sub identref {
    my ($class, $ident) = @_;
    return "''" unless @$ident;
    if (scalar @$ident <= 2 && ! $ident->[1]) {
        $ident = $ident->[0];
    }
    else {
        $ident = '[' . join(', ', @$ident) . ']';
    }
    return "\$stash->getref($ident)";
}


#------------------------------------------------------------------------
# assign(\@ident, $value, $default)                             foo = bar
#------------------------------------------------------------------------

sub assign {
    my ($class, $var, $val, $default) = @_;

    if (ref $var) {
        if (scalar @$var == 2 && ! $var->[1]) {
            $var = $var->[0];
        }
        else {
            $var = '[' . join(', ', @$var) . ']';
        }
    }
    $val .= ', 1' if $default;
    return "\$stash->set($var, $val)";
}


#------------------------------------------------------------------------
# args(\@args)                                        foo, bar, baz = qux
#------------------------------------------------------------------------

sub args {
    my ($class, $args) = @_;
    my $hash = shift @$args;
    push(@$args, '{ ' . join(', ', @$hash) . ' }')
        if @$hash;

    return '0' unless @$args;
    return '[ ' . join(', ', @$args) . ' ]';
}

#------------------------------------------------------------------------
# filenames(\@names)
#------------------------------------------------------------------------

sub filenames {
    my ($class, $names) = @_;
    if (@$names > 1) {
        $names = '[ ' . join(', ', @$names) . ' ]';
    }
    else {
        $names = shift @$names;
    }
    return $names;
}


#------------------------------------------------------------------------
# get($expr)                                                    [% foo %]
#------------------------------------------------------------------------

sub get {
    my ($class, $expr) = @_;  
    return "$OUTPUT $expr;";
}


#------------------------------------------------------------------------
# call($expr)                                              [% CALL bar %]
#------------------------------------------------------------------------

sub call {
    my ($class, $expr) = @_;  
    $expr .= ';';
    return $expr;
}


#------------------------------------------------------------------------
# set(\@setlist)                               [% foo = bar, baz = qux %]
#------------------------------------------------------------------------

sub set {
    my ($class, $setlist) = @_;
    my $output;
    while (my ($var, $val) = splice(@$setlist, 0, 2)) {
        $output .= &assign($class, $var, $val) . ";\n";
    }
    chomp $output;
    return $output;
}


#------------------------------------------------------------------------
# default(\@setlist)                   [% DEFAULT foo = bar, baz = qux %]
#------------------------------------------------------------------------

sub default {
    my ($class, $setlist) = @_;  
    my $output;
    while (my ($var, $val) = splice(@$setlist, 0, 2)) {
        $output .= &assign($class, $var, $val, 1) . ";\n";
    }
    chomp $output;
    return $output;
}


#------------------------------------------------------------------------
# insert(\@nameargs)                                    [% INSERT file %] 
#         # => [ [ $file, ... ], \@args ]
#------------------------------------------------------------------------

sub insert {
    my ($class, $nameargs) = @_;
    my ($file, $args) = @$nameargs;
    $file = $class->filenames($file);
    return "$OUTPUT \$context->insert($file);"; 
}


#------------------------------------------------------------------------
# include(\@nameargs)                    [% INCLUDE template foo = bar %] 
#          # => [ [ $file, ... ], \@args ]    
#------------------------------------------------------------------------

sub include {
    my ($class, $nameargs) = @_;
    my ($file, $args) = @$nameargs;
    my $hash = shift @$args;
    $file = $class->filenames($file);
    $file .= @$hash ? ', { ' . join(', ', @$hash) . ' }' : '';
    return "$OUTPUT \$context->include($file);"; 
}


#------------------------------------------------------------------------
# process(\@nameargs)                    [% PROCESS template foo = bar %] 
#         # => [ [ $file, ... ], \@args ]
#------------------------------------------------------------------------

sub process {
    my ($class, $nameargs) = @_;
    my ($file, $args) = @$nameargs;
    my $hash = shift @$args;
    $file = $class->filenames($file);
    $file .= @$hash ? ', { ' . join(', ', @$hash) . ' }' : '';
    return "$OUTPUT \$context->process($file);"; 
}


#------------------------------------------------------------------------
# if($expr, $block, $else)                             [% IF foo < bar %]
#                                                         ...
#                                                      [% ELSE %]
#                                                         ...
#                                                      [% END %]
#------------------------------------------------------------------------

sub if {
    my ($class, $expr, $block, $else) = @_;
    my @else = $else ? @$else : ();
    $else = pop @else;
    $block = pad($block, 1) if $PRETTY;

    my $output = "if ($expr) {\n$block\n}\n";

    foreach my $elsif (@else) {
        ($expr, $block) = @$elsif;
        $block = pad($block, 1) if $PRETTY;
        $output .= "elsif ($expr) {\n$block\n}\n";
    }
    if (defined $else) {
        $else = pad($else, 1) if $PRETTY;
        $output .= "else {\n$else\n}\n";
    }

    return $output;
}


#------------------------------------------------------------------------
# foreach($target, $list, $args, $block)    [% FOREACH x = [ foo bar ] %]
#                                              ...
#                                           [% END %]
#------------------------------------------------------------------------

sub foreach {
    my ($class, $target, $list, $args, $block) = @_;
    $args  = shift @$args;
    $args  = @$args ? ', { ' . join(', ', @$args) . ' }' : '';

    my ($loop_save, $loop_set, $loop_restore, $setiter);
    if ($target) {
        $loop_save    = 'eval { $oldloop = ' . &ident($class, ["'loop'"]) . ' }';
        $loop_set     = "\$stash->{'$target'} = \$value";
        $loop_restore = "\$stash->set('loop', \$oldloop)";
    }
    else {
        $loop_save    = '$stash = $context->localise()';
#       $loop_set     = "\$stash->set('import', \$value) "
#                       . "if ref \$value eq 'HASH'";
        $loop_set     = "\$stash->get(['import', [\$value]]) "
                        . "if ref \$value eq 'HASH'";
        $loop_restore = '$stash = $context->delocalise()';
    }
    $block = pad($block, 3) if $PRETTY;

    return <<EOF;

# FOREACH 
do {
    my (\$value, \$error, \$oldloop);
    my \$list = $list;
    
    unless (UNIVERSAL::isa(\$list, 'Template::Iterator')) {
        \$list = Template::Config->iterator(\$list)
            || die \$Template::Config::ERROR, "\\n"; 
    }

    (\$value, \$error) = \$list->get_first();
    $loop_save;
    \$stash->set('loop', \$list);
    eval {
LOOP:   while (! \$error) {
            $loop_set;
$block;
            (\$value, \$error) = \$list->get_next();
        }
    };
    $loop_restore;
    die \$@ if \$@;
    \$error = 0 if \$error && \$error eq Template::Constants::STATUS_DONE;
    die \$error if \$error;
};
EOF
}

#------------------------------------------------------------------------
# next()                                                       [% NEXT %]
#
# Next iteration of a FOREACH loop (experimental)
#------------------------------------------------------------------------

sub next {
    return <<EOF;
(\$value, \$error) = \$list->get_next();
next LOOP;
EOF
}


#------------------------------------------------------------------------
# wrapper(\@nameargs, $block)            [% WRAPPER template foo = bar %] 
#          # => [ [$file,...], \@args ]    
#------------------------------------------------------------------------

sub wrapper {
    my ($class, $nameargs, $block) = @_;
    my ($file, $args) = @$nameargs;
    my $hash = shift @$args;

    local $" = ', ';
#    print STDERR "wrapper([@$file], { @$hash })\n";

    return $class->multi_wrapper($file, $hash, $block)
        if @$file > 1;
    $file = shift @$file;

    $block = pad($block, 1) if $PRETTY;
    push(@$hash, "'content'", '$output');
    $file .= @$hash ? ', { ' . join(', ', @$hash) . ' }' : '';

    return <<EOF;

# WRAPPER
$OUTPUT do {
    my \$output = '';
$block
    \$context->include($file); 
};
EOF
}


sub multi_wrapper {
    my ($class, $file, $hash, $block) = @_;
    $block = pad($block, 1) if $PRETTY;

    push(@$hash, "'content'", '$output');
    $hash = @$hash ? ', { ' . join(', ', @$hash) . ' }' : '';

    $file = join(', ', reverse @$file);
#    print STDERR "multi wrapper: $file\n";

    return <<EOF;

# WRAPPER
$OUTPUT do {
    my \$output = '';
$block
    foreach ($file) {
        \$output = \$context->include(\$_$hash); 
    }
    \$output;
};
EOF
}


#------------------------------------------------------------------------
# while($expr, $block)                                 [% WHILE x < 10 %]
#                                                         ...
#                                                      [% END %]
#------------------------------------------------------------------------

sub while {
    my ($class, $expr, $block) = @_;
    $block = pad($block, 2) if $PRETTY;

    return <<EOF;

# WHILE
do {
    my \$failsafe = $WHILE_MAX;
LOOP:
    while (--\$failsafe && ($expr)) {
$block
    }
    die "WHILE loop terminated (> $WHILE_MAX iterations)\\n"
        unless \$failsafe;
};
EOF
}


#------------------------------------------------------------------------
# switch($expr, \@case)                                    [% SWITCH %]
#                                                          [% CASE foo %]
#                                                             ...
#                                                          [% END %]
#------------------------------------------------------------------------

sub switch {
    my ($class, $expr, $case) = @_;
    my @case = @$case;
    my ($match, $block, $default);
    my $caseblock = '';

    $default = pop @case;

    foreach $case (@case) {
        $match = $case->[0];
        $block = $case->[1];
        $block = pad($block, 1) if $PRETTY;
        $caseblock .= <<EOF;
\$match = $match;
\$match = [ \$match ] unless ref \$match eq 'ARRAY';
if (grep(/^\$result\$/, \@\$match)) {
$block
    last SWITCH;
}
EOF
    }

    $caseblock .= $default
        if defined $default;
    $caseblock = pad($caseblock, 2) if $PRETTY;

return <<EOF;

# SWITCH
do {
    my \$result = $expr;
    my \$match;
    SWITCH: {
$caseblock
    }
};
EOF
}


#------------------------------------------------------------------------
# try($block, \@catch)                                        [% TRY %]
#                                                                ...
#                                                             [% CATCH %] 
#                                                                ...
#                                                             [% END %]
#------------------------------------------------------------------------

sub try {
    my ($class, $block, $catch) = @_;
    my @catch = @$catch;
    my ($match, $mblock, $default, $final, $n);
    my $catchblock = '';
    my $handlers = [];

    $block = pad($block, 2) if $PRETTY;
    $final = pop @catch;
    $final = "# FINAL\n" . ($final ? "$final\n" : '')
           . 'die $error if $error;' . "\n" . '$output;';
    $final = pad($final, 1) if $PRETTY;

    $n = 0;
    foreach $catch (@catch) {
        $match = $catch->[0] || do {
            $default ||= $catch->[1];
            next;
        };
        $mblock = $catch->[1];
        $mblock = pad($mblock, 1) if $PRETTY;
        push(@$handlers, "'$match'");
        $catchblock .= $n++ 
            ? "elsif (\$handler eq '$match') {\n$mblock\n}\n" 
               : "if (\$handler eq '$match') {\n$mblock\n}\n";
    }
    $catchblock .= "\$error = 0;";
    $catchblock = pad($catchblock, 3) if $PRETTY;
    if ($default) {
        $default = pad($default, 1) if $PRETTY;
        $default = "else {\n    # DEFAULT\n$default\n    \$error = '';\n}";
    }
    else {
        $default = '# NO DEFAULT';
    }
    $default = pad($default, 2) if $PRETTY;

    $handlers = join(', ', @$handlers);
return <<EOF;

# TRY
$OUTPUT do {
    my \$output = '';
    my (\$error, \$handler);
    eval {
$block
    };
    if (\$@) {
        \$error = \$context->catch(\$@, \\\$output);
        die \$error if \$error->type =~ /^return|stop\$/;
        \$stash->set('error', \$error);
        \$stash->set('e', \$error);
        if (defined (\$handler = \$error->select_handler($handlers))) {
$catchblock
        }
$default
    }
$final
};
EOF
}


#------------------------------------------------------------------------
# throw(\@nameargs)                           [% THROW foo "bar error" %]
#       # => [ [$type], \@args ]
#------------------------------------------------------------------------

sub throw {
    my ($class, $nameargs) = @_;
    my ($type, $args) = @$nameargs;
    my $hash = shift(@$args);
    my $info = shift(@$args);
    $type = shift @$type;           # uses same parser production as INCLUDE
                                    # etc., which allow multiple names
                                    # e.g. INCLUDE foo+bar+baz

    if (! $info) {
        $args = "$type, undef";
    }
    elsif (@$hash || @$args) {
        local $" = ', ';
        my $i = 0;
        $args = "$type, { args => [ " 
              . join(', ', $info, @$args) 
              . ' ], '
              . join(', ', 
                     (map { "'" . $i++ . "' => $_" } ($info, @$args)),
                     @$hash)
              . ' }';
    }
    else {
        $args = "$type, $info";
    }
    
    return "\$context->throw($args, \\\$output);";
}


#------------------------------------------------------------------------
# clear()                                                     [% CLEAR %]
#
# NOTE: this is redundant, being hard-coded (for now) into Parser.yp
#------------------------------------------------------------------------

sub clear {
    return "\$output = '';";
}

#------------------------------------------------------------------------
# break()                                                     [% BREAK %]
#
# NOTE: this is redundant, being hard-coded (for now) into Parser.yp
#------------------------------------------------------------------------

sub break {
    return 'last LOOP;';
}

#------------------------------------------------------------------------
# return()                                                   [% RETURN %]
#------------------------------------------------------------------------

sub return {
    return "\$context->throw('return', '', \\\$output);";
}

#------------------------------------------------------------------------
# stop()                                                       [% STOP %]
#------------------------------------------------------------------------

sub stop {
    return "\$context->throw('stop', '', \\\$output);";
}


#------------------------------------------------------------------------
# use(\@lnameargs)                         [% USE alias = plugin(args) %]
#     # => [ [$file, ...], \@args, $alias ]
#------------------------------------------------------------------------

sub use {
    my ($class, $lnameargs) = @_;
    my ($file, $args, $alias) = @$lnameargs;
    $file = shift @$file;       # same production rule as INCLUDE
    $alias ||= $file;
    $args = &args($class, $args);
    $file .= ", $args" if $args;
#    my $set = &assign($class, $alias, '$plugin'); 
    return "# USE\n"
         . "\$stash->set($alias,\n"
         . "            \$context->plugin($file));";
}

#------------------------------------------------------------------------
# view(\@nameargs, $block)                           [% VIEW name args %]
#     # => [ [$file, ... ], \@args ]
#------------------------------------------------------------------------

sub view {
    my ($class, $nameargs, $block, $defblocks) = @_;
    my ($name, $args) = @$nameargs;
    my $hash = shift @$args;
    $name = shift @$name;       # same production rule as INCLUDE
    $block = pad($block, 1) if $PRETTY;

    if (%$defblocks) {
        $defblocks = join(",\n", map { "'$_' => $defblocks->{ $_ }" }
                                keys %$defblocks);
        $defblocks = pad($defblocks, 1) if $PRETTY;
        $defblocks = "{\n$defblocks\n}";
        push(@$hash, "'blocks'", $defblocks);
    }
    $hash = @$hash ? '{ ' . join(', ', @$hash) . ' }' : '';

    return <<EOF;
# VIEW
do {
    my \$output = '';
    my \$oldv = \$stash->get('view');
    my \$view = \$context->view($hash);
    \$stash->set($name, \$view);
    \$stash->set('view', \$view);

$block

    \$stash->set('view', \$oldv);
    \$view->seal();
#    \$output;     # not used - commented out to avoid warning
};
EOF
}


#------------------------------------------------------------------------
# perl($block)
#------------------------------------------------------------------------

sub perl {
    my ($class, $block) = @_;
    $block = pad($block, 1) if $PRETTY;

    return <<EOF;

# PERL
\$context->throw('perl', 'EVAL_PERL not set')
    unless \$context->eval_perl();

$OUTPUT do {
    my \$output = "package Template::Perl;\\n";

$block

    local(\$Template::Perl::context) = \$context;
    local(\$Template::Perl::stash)   = \$stash;

    my \$result = '';
    tie *Template::Perl::PERLOUT, 'Template::TieString', \\\$result;
    my \$save_stdout = select *Template::Perl::PERLOUT;

    eval \$output;
    select \$save_stdout;
    \$context->throw(\$@) if \$@;
    \$result;
};
EOF
}


#------------------------------------------------------------------------
# no_perl()
#------------------------------------------------------------------------

sub no_perl {
    my $class = shift;
    return "\$context->throw('perl', 'EVAL_PERL not set');";
}


#------------------------------------------------------------------------
# rawperl($block)
#
# NOTE: perhaps test context EVAL_PERL switch at compile time rather than
# runtime?
#------------------------------------------------------------------------

sub rawperl {
    my ($class, $block, $line) = @_;
    for ($block) {
        s/^\n+//;
        s/\n+$//;
    }
    $block = pad($block, 1) if $PRETTY;
    $line = $line ? " (starting line $line)" : '';

    return <<EOF;
# RAWPERL
#line 1 "RAWPERL block$line"
$block
EOF
}



#------------------------------------------------------------------------
# filter()
#------------------------------------------------------------------------

sub filter {
    my ($class, $lnameargs, $block) = @_;
    my ($name, $args, $alias) = @$lnameargs;
    $name = shift @$name;
    $args = &args($class, $args);
    $args = $args ? "$args, $alias" : ", undef, $alias"
        if $alias;
    $name .= ", $args" if $args;
    $block = pad($block, 1) if $PRETTY;
 
    return <<EOF;

# FILTER
$OUTPUT do {
    my \$output = '';
    my \$filter = \$context->filter($name)
              || \$context->throw(\$context->error);

$block
    
    &\$filter(\$output);
};
EOF
}


#------------------------------------------------------------------------
# capture($name, $block)
#------------------------------------------------------------------------

sub capture {
    my ($class, $name, $block) = @_;

    if (ref $name) {
        if (scalar @$name == 2 && ! $name->[1]) {
            $name = $name->[0];
        }
        else {
            $name = '[' . join(', ', @$name) . ']';
        }
    }
    $block = pad($block, 1) if $PRETTY;

    return <<EOF;

# CAPTURE
\$stash->set($name, do {
    my \$output = '';
$block
    \$output;
});
EOF

}


#------------------------------------------------------------------------
# macro($name, $block, \@args)
#------------------------------------------------------------------------

sub macro {
    my ($class, $ident, $block, $args) = @_;
    $block = pad($block, 2) if $PRETTY;

    if ($args) {
        my $nargs = scalar @$args;
        $args = join(', ', map { "'$_'" } @$args);
        $args = $nargs > 1 
            ? "\@args{ $args } = splice(\@_, 0, $nargs)"
            : "\$args{ $args } = shift";

        return <<EOF;

# MACRO
\$stash->set('$ident', sub {
    my \$output = '';
    my (%args, \$params);
    $args;
    \$params = shift;
    \$params = { } unless ref(\$params) eq 'HASH';
    \$params = { \%args, %\$params };

    my \$stash = \$context->localise(\$params);
    eval {
$block
    };
    \$stash = \$context->delocalise();
    die \$@ if \$@;
    return \$output;
});
EOF

    }
    else {
        return <<EOF;

# MACRO
\$stash->set('$ident', sub {
    my \$params = \$_[0] if ref(\$_[0]) eq 'HASH';
    my \$output = '';

    my \$stash = \$context->localise(\$params);
    eval {
$block
    };
    \$stash = \$context->delocalise();
    die \$@ if \$@;
    return \$output;
});
EOF
    }
}


sub debug {
    my ($class, $nameargs) = @_;
    my ($file, $args) = @$nameargs;
    my $hash = shift @$args;
    $args  = join(', ', @$file, @$args);
    $args .= @$hash ? ', { ' . join(', ', @$hash) . ' }' : '';
    return "$OUTPUT \$context->debugging($args); ## DEBUG ##"; 
}


1;

__END__

