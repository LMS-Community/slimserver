#============================================================= -*-Perl-*-
#
# Template::Stash
#
# DESCRIPTION
#   Definition of an object class which stores and manages access to 
#   variables for the Template Toolkit. 
#
# AUTHOR
#   Andy Wardley   <abw@cpan.org>
#
# COPYRIGHT
#   Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
#   Copyright (C) 1998-2000 Canon Research Centre Europe Ltd.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#----------------------------------------------------------------------------
#
# $Id: Stash.pm,v 2.102 2006/05/25 11:23:35 abw Exp $
#
#============================================================================

package Template::Stash;

require 5.004;

use strict;

our $VERSION = sprintf("%d.%02d", q$Revision: 2.102 $ =~ /(\d+)\.(\d+)/);
our $DEBUG   = 0 unless defined $DEBUG;
our $PRIVATE = qr/^[_.]/;


#========================================================================
#                    -- PACKAGE VARIABLES AND SUBS --
#========================================================================

#------------------------------------------------------------------------
# Definitions of various pseudo-methods.  ROOT_OPS are merged into all
# new Template::Stash objects, and are thus default global functions.
# SCALAR_OPS are methods that can be called on a scalar, and ditto 
# respectively for LIST_OPS and HASH_OPS
#------------------------------------------------------------------------

our $ROOT_OPS = {
    'inc'  => sub { local $^W = 0; my $item = shift; ++$item }, 
    'dec'  => sub { local $^W = 0; my $item = shift; --$item }, 
#    import => \&hash_import,
    defined $ROOT_OPS ? %$ROOT_OPS : (),
};

our $SCALAR_OPS = {
    'item'    => sub {   $_[0] },
    'list'    => sub { [ $_[0] ] },
    'hash'    => sub { { value => $_[0] } },
    'length'  => sub { length $_[0] },
    'size'    => sub { return 1 },
    'defined' => sub { return 1 },
    'match' => sub {
        my ($str, $search, $global) = @_;
        return $str unless defined $str and defined $search;
        my @matches = $global ? ($str =~ /$search/g)
                              : ($str =~ /$search/);
        return @matches ? \@matches : '';
    },
    'search'  => sub { 
        my ($str, $pattern) = @_;
        return $str unless defined $str and defined $pattern;
        return $str =~ /$pattern/;
    },
    'repeat'  => sub { 
        my ($str, $count) = @_;
        $str = '' unless defined $str;  
        return '' unless $count;
        $count ||= 1;
        return $str x $count;
    },
    'replace' => sub {
        my ($text, $pattern, $replace, $global) = @_;
        $text    = '' unless defined $text;
        $pattern = '' unless defined $pattern;
        $replace = '' unless defined $replace;
        $global  = 1  unless defined $global;

        if ($replace =~ /\$\d+/) {
            # replacement string may contain backrefs
            my $expand = sub {
                my ($chunk, $start, $end) = @_;
                $chunk =~ s{ \\(\\|\$) | \$ (\d+) }{
                    $1 ? $1
                        : ($2 > $#$start || $2 == 0) ? '' 
                        : substr($text, $start->[$2], $end->[$2] - $start->[$2]);
                }exg;
                $chunk;
            };
            if ($global) {
                $text =~ s{$pattern}{ &$expand($replace, [@-], [@+]) }eg;
            } 
            else {
                $text =~ s{$pattern}{ &$expand($replace, [@-], [@+]) }e;
            }
        }
        else {
            if ($global) {
                $text =~ s/$pattern/$replace/g;
            } 
            else {
                $text =~ s/$pattern/$replace/;
            }
        }
        return $text;
    },
    'remove'  => sub { 
        my ($str, $search) = @_;
        return $str unless defined $str and defined $search;
        $str =~ s/$search//g;
        return $str;
    },
    'split' => sub {
        my ($str, $split, $limit) = @_;
        $str = '' unless defined $str;

        # we have to be very careful about spelling out each possible 
        # combination of arguments because split() is very sensitive
        # to them, for example C<split(' ', ...)> behaves differently 
        # to C<$space=' '; split($space, ...)>

        if (defined $limit) {
            return [ defined $split 
                     ? split($split, $str, $limit)
                     : split(' ', $str, $limit) ];
        }
        else {
            return [ defined $split 
                     ? split($split, $str)
                     : split(' ', $str) ];
        }
    },
    'chunk' => sub {
        my ($string, $size) = @_;
        my @list;
        $size ||= 1;
        if ($size < 0) {
            # sexeger!  It's faster to reverse the string, search
            # it from the front and then reverse the output than to 
            # search it from the end, believe it nor not!
            $string = reverse $string;
            $size = -$size;
            unshift(@list, scalar reverse $1) 
                while ($string =~ /((.{$size})|(.+))/g);
        }
        else {
            push(@list, $1) while ($string =~ /((.{$size})|(.+))/g);
        }
        return \@list;
    },
    'substr' => sub {
        my ($text, $offset, $length, $replacement) = @_;
        $offset ||= 0;

        if(defined $length) {
            if (defined $replacement) {
                substr( $text, $offset, $length, $replacement );
                return $text;
            }
            else {
                return substr( $text, $offset, $length );
            }
        }
        else {
            return substr( $text, $offset );
        }
    },

    defined $SCALAR_OPS ? %$SCALAR_OPS : (),
};

our $HASH_OPS = {
    'item'   => sub { 
        my ($hash, $item) = @_; 
        $item = '' unless defined $item;
        return if $PRIVATE && $item =~ /$PRIVATE/;
        $hash->{ $item };
    },
    'hash'   => sub { $_[0] },
    'size'   => sub { scalar keys %{$_[0]} },
    'each'   => sub { # this will be changed in TT3 to do what pairs does
                      [        %{ $_[0] } ] },
    'keys'   => sub { [ keys   %{ $_[0] } ] },
    'values' => sub { [ values %{ $_[0] } ] },
    'items'  => sub { [        %{ $_[0] } ] },
    'pairs'  => sub { [ map   { { key => $_ , value => $_[0]->{ $_ } } }
                        sort keys %{ $_[0] } ] },
    'list'   => sub { 
        my ($hash, $what) = @_;  
        $what ||= '';
        return ($what eq 'keys')   ? [   keys %$hash ]
            :  ($what eq 'values') ? [ values %$hash ]
            :  ($what eq 'each')   ? [        %$hash ]
            :  # for now we do what pairs does but this will be changed 
               # in TT3 to return [ $hash ] by default
               [ map { { key => $_ , value => $hash->{ $_ } } }
                 sort keys %$hash 
               ];
    },
    'exists'  => sub { exists $_[0]->{ $_[1] } },
    'defined' => sub { 
        # return the item requested, or 1 if no argument 
        # to indicate that the hash itself is defined
        my $hash = shift;
        return @_ ? defined $hash->{ $_[0] } : 1;
    },
    'delete'  => sub { 
        my $hash = shift; 
        delete $hash->{ $_ } for @_;
    },
    'import'  => \&hash_import,
    'sort'    => sub {
        my ($hash) = @_;
        [ sort { lc $hash->{$a} cmp lc $hash->{$b} } (keys %$hash) ];
    },
    'nsort'    => sub {
        my ($hash) = @_;
        [ sort { $hash->{$a} <=> $hash->{$b} } (keys %$hash) ];
    },
    defined $HASH_OPS ? %$HASH_OPS : (),
};

our $LIST_OPS = {
    'item'    => sub { $_[0]->[ $_[1] || 0 ] },
    'list'    => sub { $_[0] },
    'hash'    => sub { 
        my $list = shift;
        if (@_) {
            my $n = shift || 0;
            return { map { ($n++, $_) } @$list }; 
        }
        no warnings;
        return { @$list };
    },
    'push'    => sub { my $list = shift; push(@$list, @_); return '' },
    'pop'     => sub { my $list = shift; pop(@$list) },
    'unshift' => sub { my $list = shift; unshift(@$list, @_); return '' },
    'shift'   => sub { my $list = shift; shift(@$list) },
    'max'     => sub { local $^W = 0; my $list = shift; $#$list; },
    'size'    => sub { local $^W = 0; my $list = shift; $#$list + 1; },
    'defined' => sub { 
        # return the item requested, or 1 if no argument to 
        # indicate that the hash itself is defined
        my $list = shift;
        return @_ ? defined $list->[$_[0]] : 1;
    },
    'first'   => sub {
        my $list = shift;
        return $list->[0] unless @_;
        return [ @$list[0..$_[0]-1] ];
    },
    'last'    => sub {
        my $list = shift;
        return $list->[-1] unless @_;
        return [ @$list[-$_[0]..-1] ];
    },
    'reverse' => sub { my $list = shift; [ reverse @$list ] },
    'grep'    => sub { 
        my ($list, $pattern) = @_;
        $pattern ||= '';
        return [ grep /$pattern/, @$list ];
    },
    'join'    => sub { 
        my ($list, $joint) = @_; 
        join(defined $joint ? $joint : ' ', 
             map { defined $_ ? $_ : '' } @$list) 
        },
    'sort'    => sub {
        $^W = 0;
        my ($list, $field) = @_;
        return $list unless @$list > 1;     # no need to sort 1 item lists
        return [
            $field                          # Schwartzian Transform 
            ?  map  { $_->[0] }             # for case insensitivity
               sort { $a->[1] cmp $b->[1] }
               map  { [ $_, lc(ref($_) eq 'HASH' 
                   ? $_->{ $field } : 
                   UNIVERSAL::can($_, $field)
                   ? $_->$field() : $_) ] } 
               @$list 
            :  map  { $_->[0] }
               sort { $a->[1] cmp $b->[1] }
               map  { [ $_, lc $_ ] } 
               @$list,
       ];
   },
   'nsort'    => sub {
        my ($list, $field) = @_;
        return $list unless @$list > 1;     # no need to sort 1 item lists
        return [ 
            $field                          # Schwartzian Transform 
            ?  map  { $_->[0] }             # for case insensitivity
               sort { $a->[1] <=> $b->[1] }
               map  { [ $_, lc(ref($_) eq 'HASH' 
                   ? $_->{ $field } : 
                   UNIVERSAL::can($_, $field)
                   ? $_->$field() : $_) ] } 
               @$list 
            :  map  { $_->[0] }
               sort { $a->[1] <=> $b->[1] }
               map  { [ $_, lc $_ ] } 
               @$list,
        ];
    },
    'unique'  => sub { my %u; [ grep { ++$u{$_} == 1 } @{$_[0]} ] },
    'import'  => sub {
        my $list = shift;
        push(@$list, grep defined, map ref eq 'ARRAY' ? @$_ : undef, @_);
        return $list;
    },
    'merge'   => sub {
        my $list = shift;
        return [ @$list, grep defined, map ref eq 'ARRAY' ? @$_ : undef, @_ ];
    },
    'slice' => sub {
        my ($list, $from, $to) = @_;
        $from ||= 0;
        $to = $#$list unless defined $to;
        return [ @$list[$from..$to] ];
    },
    'splice'  => sub {
        my ($list, $offset, $length, @replace) = @_;
        if (@replace) {
            # @replace can contain a list of multiple replace items, or 
            # be a single reference to a list
            @replace = @{ $replace[0] }
            if @replace == 1 && ref $replace[0] eq 'ARRAY';
            return [ splice @$list, $offset, $length, @replace ];
        }
        elsif (defined $length) {
            return [ splice @$list, $offset, $length ];
        }
        elsif (defined $offset) {
            return [ splice @$list, $offset ];
        }
        else {
            return [ splice(@$list) ];
        }
    },

    defined $LIST_OPS ? %$LIST_OPS : (),
};

sub hash_import { 
    my ($hash, $imp) = @_;
    $imp = {} unless ref $imp eq 'HASH';
    @$hash{ keys %$imp } = values %$imp;
    return '';
}


#------------------------------------------------------------------------
# define_vmethod($type, $name, \&sub)
#
# Defines a virtual method of type $type (SCALAR, HASH, or LIST), with
# name $name, that invokes &sub when called.  It is expected that &sub
# be able to handle the type that it will be called upon.
#------------------------------------------------------------------------

sub define_vmethod {
    my ($class, $type, $name, $sub) = @_;
    my $op;
    $type = lc $type;

    if ($type =~ /^scalar|item$/) {
        $op = $SCALAR_OPS;
    }
    elsif ($type eq 'hash') {
        $op = $HASH_OPS;
    }
    elsif ($type =~ /^list|array$/) {
        $op = $LIST_OPS;
    }
    else {
        die "invalid vmethod type: $type\n";
    }

    $op->{ $name } = $sub;

    return 1;
}


#========================================================================
#                      -----  CLASS METHODS -----
#========================================================================

#------------------------------------------------------------------------
# new(\%params)
#
# Constructor method which creates a new Template::Stash object.
# An optional hash reference may be passed containing variable 
# definitions that will be used to initialise the stash.
#
# Returns a reference to a newly created Template::Stash.
#------------------------------------------------------------------------

sub new {
    my $class  = shift;
    my $params = ref $_[0] eq 'HASH' ? shift(@_) : { @_ };

    my $self   = {
        global  => { },
        %$params,
        %$ROOT_OPS,
        '_PARENT' => undef,
    };

    bless $self, $class;
}


#========================================================================
#                   -----  PUBLIC OBJECT METHODS -----
#========================================================================

#------------------------------------------------------------------------
# clone(\%params)
#
# Creates a copy of the current stash object to effect localisation 
# of variables.  The new stash is blessed into the same class as the 
# parent (which may be a derived class) and has a '_PARENT' member added
# which contains a reference to the parent stash that created it
# ($self).  This member is used in a successive declone() method call to
# return the reference to the parent.
# 
# A parameter may be provided which should reference a hash of 
# variable/values which should be defined in the new stash.  The 
# update() method is called to define these new variables in the cloned
# stash.
#
# Returns a reference to a cloned Template::Stash.
#------------------------------------------------------------------------

sub clone {
    my ($self, $params) = @_;
    $params ||= { };

    # look out for magical 'import' argument which imports another hash
    my $import = $params->{ import };
    if (defined $import && UNIVERSAL::isa($import, 'HASH')) {
        delete $params->{ import };
    }
    else {
        undef $import;
    }

    my $clone = bless { 
        %$self,         # copy all parent members
        %$params,       # copy all new data
        '_PARENT' => $self,     # link to parent
    }, ref $self;
    
    # perform hash import if defined
    &{ $HASH_OPS->{ import }}($clone, $import)
        if defined $import;

    return $clone;
}

    
#------------------------------------------------------------------------
# declone($export) 
#
# Returns a reference to the PARENT stash.  When called in the following
# manner:
#    $stash = $stash->declone();
# the reference count on the current stash will drop to 0 and be "freed"
# and the caller will be left with a reference to the parent.  This 
# contains the state of the stash before it was cloned.  
#------------------------------------------------------------------------

sub declone {
    my $self = shift;
    $self->{ _PARENT } || $self;
}


#------------------------------------------------------------------------
# get($ident)
# 
# Returns the value for an variable stored in the stash.  The variable
# may be specified as a simple string, e.g. 'foo', or as an array 
# reference representing compound variables.  In the latter case, each
# pair of successive elements in the list represent a node in the 
# compound variable.  The first is the variable name, the second a 
# list reference of arguments or 0 if undefined.  So, the compound 
# variable [% foo.bar('foo').baz %] would be represented as the list
# [ 'foo', 0, 'bar', ['foo'], 'baz', 0 ].  Returns the value of the
# identifier or an empty string if undefined.  Errors are thrown via
# die().
#------------------------------------------------------------------------

sub get {
    my ($self, $ident, $args) = @_;
    my ($root, $result);
    $root = $self;

    if (ref $ident eq 'ARRAY'
        || ($ident =~ /\./) 
        && ($ident = [ map { s/\(.*$//; ($_, 0) } split(/\./, $ident) ])) {
        my $size = $#$ident;

        # if $ident is a list reference, then we evaluate each item in the 
        # identifier against the previous result, using the root stash 
        # ($self) as the first implicit 'result'...
        
        foreach (my $i = 0; $i <= $size; $i += 2) {
            $result = $self->_dotop($root, @$ident[$i, $i+1]);
            last unless defined $result;
            $root = $result;
        }
    }
    else {
        $result = $self->_dotop($root, $ident, $args);
    }

    return defined $result ? $result : $self->undefined($ident, $args);
}


#------------------------------------------------------------------------
# set($ident, $value, $default)
#
# Updates the value for a variable in the stash.  The first parameter
# should be the variable name or array, as per get().  The second 
# parameter should be the intended value for the variable.  The third,
# optional parameter is a flag which may be set to indicate 'default'
# mode.  When set true, the variable will only be updated if it is
# currently undefined or has a false value.  The magical 'IMPORT'
# variable identifier may be used to indicate that $value is a hash
# reference whose values should be imported.  Returns the value set,
# or an empty string if not set (e.g. default mode).  In the case of 
# IMPORT, returns the number of items imported from the hash.
#------------------------------------------------------------------------

sub set {
    my ($self, $ident, $value, $default) = @_;
    my ($root, $result, $error);

    $root = $self;

    ELEMENT: {
        if (ref $ident eq 'ARRAY'
            || ($ident =~ /\./) 
            && ($ident = [ map { s/\(.*$//; ($_, 0) }
                           split(/\./, $ident) ])) {
            
            # a compound identifier may contain multiple elements (e.g. 
            # foo.bar.baz) and we must first resolve all but the last, 
            # using _dotop() with the $lvalue flag set which will create 
            # intermediate hashes if necessary...
            my $size = $#$ident;
            foreach (my $i = 0; $i < $size - 2; $i += 2) {
                $result = $self->_dotop($root, @$ident[$i, $i+1], 1);
                last ELEMENT unless defined $result;
                $root = $result;
            }
            
            # then we call _assign() to assign the value to the last element
            $result = $self->_assign($root, @$ident[$size-1, $size], 
                                     $value, $default);
        }
        else {
            $result = $self->_assign($root, $ident, 0, $value, $default);
        }
    }
    
    return defined $result ? $result : '';
}


#------------------------------------------------------------------------
# getref($ident)
# 
# Returns a "reference" to a particular item.  This is represented as a 
# closure which will return the actual stash item when called.  
# WARNING: still experimental!
#------------------------------------------------------------------------

sub getref {
    my ($self, $ident, $args) = @_;
    my ($root, $item, $result);
    $root = $self;

    if (ref $ident eq 'ARRAY') {
        my $size = $#$ident;
        
        foreach (my $i = 0; $i <= $size; $i += 2) {
            ($item, $args) = @$ident[$i, $i + 1]; 
            last if $i >= $size - 2;  # don't evaluate last node
            last unless defined 
                ($root = $self->_dotop($root, $item, $args));
        }
    }
    else {
        $item = $ident;
    }
    
    if (defined $root) {
        return sub { my @args = (@{$args||[]}, @_);
                     $self->_dotop($root, $item, \@args);
                 }
    }
    else {
        return sub { '' };
    }
}




#------------------------------------------------------------------------
# update(\%params)
#
# Update multiple variables en masse.  No magic is performed.  Simple
# variable names only.
#------------------------------------------------------------------------

sub update {
    my ($self, $params) = @_;

    # look out for magical 'import' argument to import another hash
    my $import = $params->{ import };
    if (defined $import && UNIVERSAL::isa($import, 'HASH')) {
        @$self{ keys %$import } = values %$import;
        delete $params->{ import };
    }

    @$self{ keys %$params } = values %$params;
}


#------------------------------------------------------------------------
# undefined($ident, $args)
#
# Method called when a get() returns an undefined value.  Can be redefined
# in a subclass to implement alternate handling.
#------------------------------------------------------------------------

sub undefined {
    my ($self, $ident, $args);
    return '';
}


#========================================================================
#                  -----  PRIVATE OBJECT METHODS -----
#========================================================================

#------------------------------------------------------------------------
# _dotop($root, $item, \@args, $lvalue)
#
# This is the core 'dot' operation method which evaluates elements of 
# variables against their root.  All variables have an implicit root 
# which is the stash object itself (a hash).  Thus, a non-compound 
# variable 'foo' is actually '(stash.)foo', the compound 'foo.bar' is
# '(stash.)foo.bar'.  The first parameter is a reference to the current
# root, initially the stash itself.  The second parameter contains the 
# name of the variable element, e.g. 'foo'.  The third optional
# parameter is a reference to a list of any parenthesised arguments 
# specified for the variable, which are passed to sub-routines, object 
# methods, etc.  The final parameter is an optional flag to indicate 
# if this variable is being evaluated on the left side of an assignment
# (e.g. foo.bar.baz = 10).  When set true, intermediated hashes will 
# be created (e.g. bar) if necessary.  
#
# Returns the result of evaluating the item against the root, having
# performed any variable "magic".  The value returned can then be used
# as the root of the next _dotop() in a compound sequence.  Returns
# undef if the variable is undefined.
#------------------------------------------------------------------------

sub _dotop {
    my ($self, $root, $item, $args, $lvalue) = @_;
    my $rootref = ref $root;
    my $atroot  = ($root eq $self);
    my ($value, @result);

    $args ||= [ ];
    $lvalue ||= 0;

#    print STDERR "_dotop(root=$root, item=$item, args=[@$args])\n"
#   if $DEBUG;

    # return undef without an error if either side of the dot is unviable
    return undef unless defined($root) and defined($item);

    # or if an attempt is made to access a private member, starting _ or .
    return undef if $PRIVATE && $item =~ /$PRIVATE/;

    if ($atroot || $rootref eq 'HASH') {
        # if $root is a regular HASH or a Template::Stash kinda HASH (the 
        # *real* root of everything).  We first lookup the named key 
        # in the hash, or create an empty hash in its place if undefined
        # and the $lvalue flag is set.  Otherwise, we check the HASH_OPS
        # pseudo-methods table, calling the code if found, or return undef.
        
        if (defined($value = $root->{ $item })) {
            return $value unless ref $value eq 'CODE';      ## RETURN
            @result = &$value(@$args);                      ## @result
        }
        elsif ($lvalue) {
            # we create an intermediate hash if this is an lvalue
            return $root->{ $item } = { };                  ## RETURN
        }
        # ugly hack: only allow import vmeth to be called on root stash
        elsif (($value = $HASH_OPS->{ $item })
               && ! $atroot || $item eq 'import') {
            @result = &$value($root, @$args);               ## @result
        }
        elsif ( ref $item eq 'ARRAY' ) {
            # hash slice
            return [@$root{@$item}];                        ## RETURN
        }
    }
    elsif ($rootref eq 'ARRAY') {    
        # if root is an ARRAY then we check for a LIST_OPS pseudo-method 
        # or return the numerical index into the array, or undef
        if ($value = $LIST_OPS->{ $item }) {
            @result = &$value($root, @$args);               ## @result
        }
        elsif ($item =~ /^-?\d+$/) {
            $value = $root->[$item];
            return $value unless ref $value eq 'CODE';      ## RETURN
            @result = &$value(@$args);                      ## @result
        }
        elsif ( ref $item eq 'ARRAY' ) {
            # array slice
            return [@$root[@$item]];                        ## RETURN
        }
    }
    
    # NOTE: we do the can-can because UNIVSERAL::isa($something, 'UNIVERSAL')
    # doesn't appear to work with CGI, returning true for the first call
    # and false for all subsequent calls. 
    
    elsif (ref($root) && UNIVERSAL::can($root, 'can')) {

        # if $root is a blessed reference (i.e. inherits from the 
        # UNIVERSAL object base class) then we call the item as a method.
        # If that fails then we try to fallback on HASH behaviour if 
        # possible.
        eval { @result = $root->$item(@$args); };       
        
        if ($@) {
            # temporary hack - required to propogate errors thrown
            # by views; if $@ is a ref (e.g. Template::Exception
            # object then we assume it's a real error that needs
            # real throwing

            my $class = ref($root) || $root;
            die $@ if ref($@) || ($@ !~ /Can't locate object method "\Q$item\E" via package "\Q$class\E"/);

            # failed to call object method, so try some fallbacks
            if (UNIVERSAL::isa($root, 'HASH') ) {
                if( defined($value = $root->{ $item })) {
                    return $value unless ref $value eq 'CODE';      ## RETURN
                    @result = &$value(@$args);
                }
                elsif ($value = $HASH_OPS->{ $item }) {
                    @result = &$value($root, @$args);
                }
            }
            elsif (UNIVERSAL::isa($root, 'ARRAY') ) {
                if( $value = $LIST_OPS->{ $item }) {
                   @result = &$value($root, @$args);
                }
                elsif( $item =~ /^-?\d+$/ ) {
                   $value = $root->[$item];
                   return $value unless ref $value eq 'CODE';      ## RETURN
                   @result = &$value(@$args);                      ## @result
                }
                elsif ( ref $item eq 'ARRAY' ) {
                    # array slice
                    return [@$root[@$item]];                        ## RETURN
                }
            }
            elsif ($value = $SCALAR_OPS->{ $item }) {
                @result = &$value($root, @$args);
            }
            elsif ($value = $LIST_OPS->{ $item }) {
                @result = &$value([$root], @$args);
            }
            elsif ($self->{ _DEBUG }) {
                @result = (undef, $@);
            }
        }
    }
    elsif (($value = $SCALAR_OPS->{ $item }) && ! $lvalue) {
        # at this point, it doesn't look like we've got a reference to
        # anything we know about, so we try the SCALAR_OPS pseudo-methods
        # table (but not for l-values)
        @result = &$value($root, @$args);           ## @result
    }
    elsif (($value = $LIST_OPS->{ $item }) && ! $lvalue) {
        # last-ditch: can we promote a scalar to a one-element
        # list and apply a LIST_OPS virtual method?
        @result = &$value([$root], @$args);
    }
    elsif ($self->{ _DEBUG }) {
        die "don't know how to access [ $root ].$item\n";   ## DIE
    }
    else {
        @result = ();
    }

    # fold multiple return items into a list unless first item is undef
    if (defined $result[0]) {
        return                              ## RETURN
        scalar @result > 1 ? [ @result ] : $result[0];
    }
    elsif (defined $result[1]) {
        die $result[1];                     ## DIE
    }
    elsif ($self->{ _DEBUG }) {
        die "$item is undefined\n";         ## DIE
    }

    return undef;
}


#------------------------------------------------------------------------
# _assign($root, $item, \@args, $value, $default)
#
# Similar to _dotop() above, but assigns a value to the given variable
# instead of simply returning it.  The first three parameters are the
# root item, the item and arguments, as per _dotop(), followed by the 
# value to which the variable should be set and an optional $default
# flag.  If set true, the variable will only be set if currently false
# (undefined/zero)
#------------------------------------------------------------------------

sub _assign {
    my ($self, $root, $item, $args, $value, $default) = @_;
    my $rootref = ref $root;
    my $atroot  = ($root eq $self);
    my $result;
    $args ||= [ ];
    $default ||= 0;

    # return undef without an error if either side of the dot is unviable
    return undef unless $root and defined $item;

    # or if an attempt is made to update a private member, starting _ or .
    return undef if $PRIVATE && $item =~ /$PRIVATE/;
    
    if ($rootref eq 'HASH' || $atroot) {
        # if the root is a hash we set the named key
        return ($root->{ $item } = $value)          ## RETURN
            unless $default && $root->{ $item };
    }
    elsif ($rootref eq 'ARRAY' && $item =~ /^-?\d+$/) {
        # or set a list item by index number
        return ($root->[$item] = $value)            ## RETURN
            unless $default && $root->{ $item };
    }
    elsif (UNIVERSAL::isa($root, 'UNIVERSAL')) {
        # try to call the item as a method of an object
        
        return $root->$item(@$args, $value)         ## RETURN
            unless $default && $root->$item();
        
# 2 issues:
#   - method call should be wrapped in eval { }
#   - fallback on hash methods if object method not found
#
#     eval { $result = $root->$item(@$args, $value); };     
# 
#     if ($@) {
#         die $@ if ref($@) || ($@ !~ /Can't locate object method/);
# 
#         # failed to call object method, so try some fallbacks
#         if (UNIVERSAL::isa($root, 'HASH') && exists $root->{ $item }) {
#         $result = ($root->{ $item } = $value)
#             unless $default && $root->{ $item };
#         }
#     }
#     return $result;                       ## RETURN
    }
    else {
        die "don't know how to assign to [$root].[$item]\n";    ## DIE
    }

    return undef;
}


#------------------------------------------------------------------------
# _dump()
#
# Debug method which returns a string representing the internal state
# of the object.  The method calls itself recursively to dump sub-hashes.
#------------------------------------------------------------------------

sub _dump {
    my $self   = shift;
    return "[Template::Stash] " . $self->_dump_frame(2);
}

sub _dump_frame {
    my ($self, $indent) = @_;
    $indent ||= 1;
    my $buffer = '    ';
    my $pad    = $buffer x $indent;
    my $text   = "{\n";
    local $" = ', ';

    my ($key, $value);

    return $text . "...excessive recursion, terminating\n"
        if $indent > 32;
    
    foreach $key (keys %$self) {
        $value = $self->{ $key };
        $value = '<undef>' unless defined $value;
        next if $key =~ /^\./;
        if (ref($value) eq 'ARRAY') {
            $value = '[ ' . join(', ', map { defined $_ ? $_ : '<undef>' }
                                 @$value) . ' ]';
        }
        elsif (ref $value eq 'HASH') {
            $value = _dump_frame($value, $indent + 1);
        }
        
        $text .= sprintf("$pad%-16s => $value\n", $key);
    }
    $text .= $buffer x ($indent - 1) . '}';
    return $text;
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

Template::Stash - Magical storage for template variables

=head1 SYNOPSIS

    use Template::Stash;

    my $stash = Template::Stash->new(\%vars);

    # get variable values
    $value = $stash->get($variable);
    $value = $stash->get(\@compound);

    # set variable value
    $stash->set($variable, $value);
    $stash->set(\@compound, $value);

    # default variable value
    $stash->set($variable, $value, 1);
    $stash->set(\@compound, $value, 1);

    # set variable values en masse
    $stash->update(\%new_vars)

    # methods for (de-)localising variables
    $stash = $stash->clone(\%new_vars);
    $stash = $stash->declone();

=head1 DESCRIPTION

The Template::Stash module defines an object class which is used to store
variable values for the runtime use of the template processor.  Variable
values are stored internally in a hash reference (which itself is blessed 
to create the object) and are accessible via the get() and set() methods.

Variables may reference hash arrays, lists, subroutines and objects
as well as simple values.  The stash automatically performs the right
magic when dealing with variables, calling code or object methods,
indexing into lists, hashes, etc.

The stash has clone() and declone() methods which are used by the
template processor to make temporary copies of the stash for
localising changes made to variables.

=head1 PUBLIC METHODS

=head2 new(\%params)

The new() constructor method creates and returns a reference to a new
Template::Stash object.  

    my $stash = Template::Stash->new();

A hash reference may be passed to provide variables and values which
should be used to initialise the stash.

    my $stash = Template::Stash->new({ var1 => 'value1', 
				       var2 => 'value2' });

=head2 get($variable)

The get() method retrieves the variable named by the first parameter.

    $value = $stash->get('var1');

Dotted compound variables can be retrieved by specifying the variable
elements by reference to a list.  Each node in the variable occupies
two entries in the list.  The first gives the name of the variable
element, the second is a reference to a list of arguments for that 
element, or 0 if none.

    [% foo.bar(10).baz(20) %]

    $stash->get([ 'foo', 0, 'bar', [ 10 ], 'baz', [ 20 ] ]);

=head2 set($variable, $value, $default)

The set() method sets the variable name in the first parameter to the 
value specified in the second.

    $stash->set('var1', 'value1');

If the third parameter evaluates to a true value, the variable is
set only if it did not have a true value before.

    $stash->set('var2', 'default_value', 1);

Dotted compound variables may be specified as per get() above.

    [% foo.bar = 30 %]

    $stash->set([ 'foo', 0, 'bar', 0 ], 30);

The magical variable 'IMPORT' can be specified whose corresponding
value should be a hash reference.  The contents of the hash array are
copied (i.e. imported) into the current namespace.

    # foo.bar = baz, foo.wiz = waz
    $stash->set('foo', { 'bar' => 'baz', 'wiz' => 'waz' });

    # import 'foo' into main namespace: bar = baz, wiz = waz
    $stash->set('IMPORT', $stash->get('foo'));

=head2 clone(\%params)

The clone() method creates and returns a new Template::Stash object which
represents a localised copy of the parent stash.  Variables can be
freely updated in the cloned stash and when declone() is called, the
original stash is returned with all its members intact and in the
same state as they were before clone() was called.

For convenience, a hash of parameters may be passed into clone() which 
is used to update any simple variable (i.e. those that don't contain any 
namespace elements like 'foo' and 'bar' but not 'foo.bar') variables while 
cloning the stash.  For adding and updating complex variables, the set() 
method should be used after calling clone().  This will correctly resolve
and/or create any necessary namespace hashes.

A cloned stash maintains a reference to the stash that it was copied 
from in its '_PARENT' member.

=head2 declone()

The declone() method returns the '_PARENT' reference and can be used to
restore the state of a stash as described above.

=head1 AUTHOR

Andy Wardley E<lt>abw@wardley.orgE<gt>

L<http://wardley.org/|http://wardley.org/>




=head1 VERSION

2.102, distributed as part of the
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
