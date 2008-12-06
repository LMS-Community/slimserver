#============================================================= -*-Perl-*-
#
# Template::Provider
#
# DESCRIPTION
#   This module implements a class which handles the loading, compiling
#   and caching of templates.  Multiple Template::Provider objects can
#   be stacked and queried in turn to effect a Chain-of-Command between 
#   them.  A provider will attempt to return the requested template,
#   an error (STATUS_ERROR) or decline to provide the template 
#   (STATUS_DECLINE), allowing subsequent providers to attempt to 
#   deliver it.   See 'Design Patterns' for further details.
#
# AUTHOR
#   Andy Wardley   <abw@wardley.org>
#
# COPYRIGHT
#   Copyright (C) 1996-2003 Andy Wardley.  All Rights Reserved.
#   Copyright (C) 1998-2000 Canon Research Centre Europe Ltd.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
# TODO:
#   * optional provider prefix (e.g. 'http:')
#   * fold ABSOLUTE and RELATIVE test cases into one regex?
#
#----------------------------------------------------------------------------
#
# $Id: Provider.pm,v 2.88 2006/02/02 13:12:52 abw Exp $
#
#============================================================================

package Template::Provider;

use strict;
use warnings;
use base 'Template::Base';
use Template::Config;
use Template::Constants;
use Template::Document;
use File::Basename;
use File::Spec;
use Digest::MD5 qw(md5_hex);

use constant PREV   => 0;
use constant NAME   => 1;
use constant DATA   => 2; 
use constant LOAD   => 3;
use constant NEXT   => 4;
use constant STAT   => 5;

our $VERSION = sprintf("%d.%02d", q$Revision: 2.88 $ =~ /(\d+)\.(\d+)/);
our $DEBUG   = 0 unless defined $DEBUG;
our $ERROR   = '';

# name of document class
our $DOCUMENT = 'Template::Document' unless defined $DOCUMENT;

# maximum time between performing stat() on file to check staleness
our $STAT_TTL = 1 unless defined $STAT_TTL;

# maximum number of directories in an INCLUDE_PATH, to prevent runaways
our $MAX_DIRS = 64 unless defined $MAX_DIRS;

# UNICODE is supported in versions of Perl from 5.007 onwards
our $UNICODE = $] > 5.007 ? 1 : 0;

my $boms = [
    'UTF-8'    => "\x{ef}\x{bb}\x{bf}",
    'UTF-32BE' => "\x{0}\x{0}\x{fe}\x{ff}",
    'UTF-32LE' => "\x{ff}\x{fe}\x{0}\x{0}",
    'UTF-16BE' => "\x{fe}\x{ff}",
    'UTF-16LE' => "\x{ff}\x{fe}",
];

# regex to match relative paths
our $RELATIVE_PATH = qr[(?:^|/)\.+/];


# hack so that 'use bytes' will compile on versions of Perl earlier than 
# 5.6, even though we never call _decode_unicode() on those systems
BEGIN { 
    if ($] < 5.006) { 
        package bytes; 
        $INC{'bytes.pm'} = 1; 
    } 
}


#========================================================================
#                         -- PUBLIC METHODS --
#========================================================================

#------------------------------------------------------------------------
# fetch($name)
#
# Returns a compiled template for the name specified by parameter.
# The template is returned from the internal cache if it exists, or
# loaded and then subsequently cached.  The ABSOLUTE and RELATIVE
# configuration flags determine if absolute (e.g. '/something...')
# and/or relative (e.g. './something') paths should be honoured.  The
# INCLUDE_PATH is otherwise used to find the named file. $name may
# also be a reference to a text string containing the template text,
# or a file handle from which the content is read.  The compiled
# template is not cached in these latter cases given that there is no
# filename to cache under.  A subsequent call to store($name,
# $compiled) can be made to cache the compiled template for future
# fetch() calls, if necessary. 
#
# Returns a compiled template or (undef, STATUS_DECLINED) if the 
# template could not be found.  On error (e.g. the file was found 
# but couldn't be read or parsed), the pair ($error, STATUS_ERROR)
# is returned.  The TOLERANT configuration option can be set to 
# downgrade any errors to STATUS_DECLINE.
#------------------------------------------------------------------------

sub fetch {
    my ($self, $name) = @_;
    my ($data, $error);

    if (ref $name) {
        # $name can be a reference to a scalar, GLOB or file handle
        ($data, $error) = $self->_load($name);
        ($data, $error) = $self->_compile($data)
            unless $error;
        $data = $data->{ data }
	    unless $error;
    }
    elsif (File::Spec->file_name_is_absolute($name)) {
        # absolute paths (starting '/') allowed if ABSOLUTE set
        ($data, $error) = $self->{ ABSOLUTE } 
	    ? $self->_fetch($name) 
            : $self->{ TOLERANT } 
		? (undef, Template::Constants::STATUS_DECLINED)
            : ("$name: absolute paths are not allowed (set ABSOLUTE option)",
               Template::Constants::STATUS_ERROR);
    }
    elsif ($name =~ m/$RELATIVE_PATH/o) {
        # anything starting "./" is relative to cwd, allowed if RELATIVE set
        ($data, $error) = $self->{ RELATIVE } 
	    ? $self->_fetch($name) 
            : $self->{ TOLERANT } 
		? (undef, Template::Constants::STATUS_DECLINED)
            : ("$name: relative paths are not allowed (set RELATIVE option)",
               Template::Constants::STATUS_ERROR);
    }
    else {
        # otherwise, it's a file name relative to INCLUDE_PATH
        ($data, $error) = $self->{ INCLUDE_PATH } 
	    ? $self->_fetch_path($name) 
            : (undef, Template::Constants::STATUS_DECLINED);
    }
    
#    $self->_dump_cache() 
#	if $DEBUG > 1;

    return ($data, $error);
}


#------------------------------------------------------------------------
# store($name, $data)
#
# Store a compiled template ($data) in the cached as $name.
#------------------------------------------------------------------------

sub store {
    my ($self, $name, $data) = @_;
    $self->_store($name, {
        data => $data,
        load => 0,
    });
}


#------------------------------------------------------------------------
# load($name)
#
# Load a template without parsing/compiling it, suitable for use with 
# the INSERT directive.  There's some duplication with fetch() and at
# some point this could be reworked to integrate them a little closer.
#------------------------------------------------------------------------

sub load {
    my ($self, $name) = @_;
    my ($data, $error);
    my $path = $name;

    if (File::Spec->file_name_is_absolute($name)) {
        # absolute paths (starting '/') allowed if ABSOLUTE set
        $error = "$name: absolute paths are not allowed (set ABSOLUTE option)" 
            unless $self->{ ABSOLUTE };
    }
    elsif ($name =~ m[$RELATIVE_PATH]o) {
        # anything starting "./" is relative to cwd, allowed if RELATIVE set
        $error = "$name: relative paths are not allowed (set RELATIVE option)"
            unless $self->{ RELATIVE };
    }
    else {
      INCPATH: {
          # otherwise, it's a file name relative to INCLUDE_PATH
          my $paths = $self->paths()
              || return ($self->error(), Template::Constants::STATUS_ERROR);

          foreach my $dir (@$paths) {
              $path = "$dir/$name";
              last INCPATH
                  if -f $path;
          }
          undef $path;	    # not found
      }
    }

    if (defined $path && ! $error) {
        local $/ = undef;    # slurp files in one go
        local *FH;
        if (open(FH, $path)) {
            $data = <FH>;
            close(FH);
        }
        else {
            $error = "$name: $!";
        }
    }
    
    if ($error) {
        return $self->{ TOLERANT } 
            ? (undef, Template::Constants::STATUS_DECLINED)
            : ($error, Template::Constants::STATUS_ERROR);
    }
    elsif (! defined $path) {
        return (undef, Template::Constants::STATUS_DECLINED);
    }
    else {
        return ($data, Template::Constants::STATUS_OK);
    }
}

 

#------------------------------------------------------------------------
# include_path(\@newpath)
#
# Accessor method for the INCLUDE_PATH setting.  If called with an
# argument, this method will replace the existing INCLUDE_PATH with
# the new value.
#------------------------------------------------------------------------

sub include_path {
     my ($self, $path) = @_;
     $self->{ INCLUDE_PATH } = $path if $path;
     return $self->{ INCLUDE_PATH };
}


#------------------------------------------------------------------------
# paths()
#
# Evaluates the INCLUDE_PATH list, ignoring any blank entries, and 
# calling and subroutine or object references to return dynamically
# generated path lists.  Returns a reference to a new list of paths 
# or undef on error.
#------------------------------------------------------------------------

sub paths {
    my $self   = shift;
    my @ipaths = @{ $self->{ INCLUDE_PATH } };
    my (@opaths, $dpaths, $dir);
    my $count = $MAX_DIRS;
    
    while (@ipaths && --$count) {
        $dir = shift @ipaths || next;
        
        # $dir can be a sub or object ref which returns a reference
        # to a dynamically generated list of search paths.
        
        if (ref $dir eq 'CODE') {
            eval { $dpaths = &$dir() };
            if ($@) {
                chomp $@;
                return $self->error($@);
            }
            unshift(@ipaths, @$dpaths);
            next;
        }
        elsif (UNIVERSAL::can($dir, 'paths')) {
            $dpaths = $dir->paths() 
                || return $self->error($dir->error());
            unshift(@ipaths, @$dpaths);
            next;
        }
        else {
            push(@opaths, $dir);
        }
    }
    return $self->error("INCLUDE_PATH exceeds $MAX_DIRS directories")
	if @ipaths;

    return \@opaths;
}


#------------------------------------------------------------------------
# DESTROY
#
# The provider cache is implemented as a doubly linked list which Perl
# cannot free by itself due to the circular references between NEXT <=> 
# PREV items.  This cleanup method walks the list deleting all the NEXT/PREV 
# references, allowing the proper cleanup to occur and memory to be 
# repooled.
#------------------------------------------------------------------------

sub DESTROY {
    my $self = shift;
    my ($slot, $next);

    $slot = $self->{ HEAD };
    while ($slot) {
        $next = $slot->[ NEXT ];
        undef $slot->[ PREV ];
        undef $slot->[ NEXT ];
        $slot = $next;
    }
    undef $self->{ HEAD };
    undef $self->{ TAIL };
}




#========================================================================
#                        -- PRIVATE METHODS --
#========================================================================

#------------------------------------------------------------------------
# _init()
#
# Initialise the cache.
#------------------------------------------------------------------------

sub _init {
    my ($self, $params) = @_;
    my $size = $params->{ CACHE_SIZE   };
    my $path = $params->{ INCLUDE_PATH } || '.';
    my $cdir = $params->{ COMPILE_DIR  } || '';
    my $dlim = $params->{ DELIMITER    };
    my $debug;

    # tweak delim to ignore C:/
    unless (defined $dlim) {
        $dlim = ($^O eq 'MSWin32') ? ':(?!\\/)' : ':';
    }

    # coerce INCLUDE_PATH to an array ref, if not already so
    $path = [ split(/$dlim/, $path) ]
        unless ref $path eq 'ARRAY';
    
    # don't allow a CACHE_SIZE 1 because it breaks things and the 
    # additional checking isn't worth it
    $size = 2 
        if defined $size && ($size == 1 || $size < 0);

    if (defined ($debug = $params->{ DEBUG })) {
        $self->{ DEBUG } = $debug & ( Template::Constants::DEBUG_PROVIDER
                                    | Template::Constants::DEBUG_FLAGS );
    }
    else {
        $self->{ DEBUG } = $DEBUG;
    }

    if ($self->{ DEBUG }) {
        local $" = ', ';
        $self->debug("creating cache of ", 
                     defined $size ? $size : 'unlimited',
                     " slots for [ @$path ]");
    }
    
    # create COMPILE_DIR and sub-directories representing each INCLUDE_PATH
    # element in which to store compiled files
    if ($cdir) {
        require File::Path;
        foreach my $dir (@$path) {
            next if ref $dir;
            my $wdir = $dir;
            $wdir =~ s[:][]g if $^O eq 'MSWin32';
            $wdir =~ /(.*)/;  # untaint
            $wdir = $1;
            $wdir = File::Spec->catfile($cdir, $1);
            File::Path::mkpath($wdir) unless -d $wdir;
        }
    }

    $self->{ LOOKUP       } = { };
    $self->{ SLOTS        } = 0;
    $self->{ SIZE         } = $size;
    $self->{ INCLUDE_PATH } = $path;
    $self->{ DELIMITER    } = $dlim;
    $self->{ COMPILE_DIR  } = $cdir;
    $self->{ COMPILE_EXT  } = $params->{ COMPILE_EXT } || '';
    $self->{ ABSOLUTE     } = $params->{ ABSOLUTE } || 0;
    $self->{ RELATIVE     } = $params->{ RELATIVE } || 0;
    $self->{ TOLERANT     } = $params->{ TOLERANT } || 0;
    $self->{ DOCUMENT     } = $params->{ DOCUMENT } || $DOCUMENT;
    $self->{ PARSER       } = $params->{ PARSER   };
    $self->{ DEFAULT      } = $params->{ DEFAULT  };
    $self->{ ENCODING     } = $params->{ ENCODING };
#   $self->{ PREFIX       } = $params->{ PREFIX   };
    $self->{ PARAMS       } = $params;

    # look for user-provided UNICODE parameter or use default from package var
    $self->{ UNICODE      } = defined $params->{ UNICODE } 
                                    ? $params->{ UNICODE } : $UNICODE;

    return $self;
}


#------------------------------------------------------------------------
# _fetch($name)
#
# Fetch a file from cache or disk by specification of an absolute or
# relative filename.  No search of the INCLUDE_PATH is made.  If the 
# file is found and loaded, it is compiled and cached.
#------------------------------------------------------------------------

sub _fetch {
    my ($self, $name) = @_;
    my $size = $self->{ SIZE };
    my ($slot, $data, $error);

    $self->debug("_fetch($name)") if $self->{ DEBUG };

    my $compiled = $self->_compiled_filename($name);

    if (defined $size && ! $size) {
        # caching disabled so load and compile but don't cache
        if ($compiled && -f $compiled 
            && ! $self->_modified($name, (stat(_))[9])) {
            $data = $self->_load_compiled($compiled);
            $error = $self->error() unless $data;
        }
        else {
            ($data, $error) = $self->_load($name);
            ($data, $error) = $self->_compile($data, $compiled)
                unless $error;
            $data = $data->{ data }
            unless $error;
        }
    }
    elsif ($slot = $self->{ LOOKUP }->{ $name }) {
        # cached entry exists, so refresh slot and extract data
        ($data, $error) = $self->_refresh($slot);
        $data = $slot->[ DATA ]
            unless $error;
    }
    else {
        # nothing in cache so try to load, compile and cache
        if ($compiled && -f $compiled 
            && (stat($name))[9] <= (stat($compiled))[9]) {
            $data = $self->_load_compiled($compiled);
            $error = $self->error() unless $data;
            $self->store($name, $data) unless $error;
        }
        else {
            ($data, $error) = $self->_load($name);
            ($data, $error) = $self->_compile($data, $compiled)
                unless $error;
            $data = $self->_store($name, $data)
                unless $error;
        }
    }
    
    return ($data, $error);
}


#------------------------------------------------------------------------
# _fetch_path($name)
#
# Fetch a file from cache or disk by specification of an absolute cache
# name (e.g. 'header') or filename relative to one of the INCLUDE_PATH 
# directories.  If the file isn't already cached and can be found and 
# loaded, it is compiled and cached under the full filename.
#------------------------------------------------------------------------

sub _fetch_path {
    my ($self, $name) = @_;
    my ($size, $compext, $compdir) = 
	@$self{ qw( SIZE COMPILE_EXT COMPILE_DIR ) };
    my ($dir, $paths, $path, $compiled, $slot, $data, $error);
    local *FH;

    $self->debug("_fetch_path($name)") if $self->{ DEBUG };

    # caching is enabled if $size is defined and non-zero or undefined
    my $caching = (! defined $size || $size);

    INCLUDE: {

        # the template may have been stored using a non-filename name
        if ($caching && ($slot = $self->{ LOOKUP }->{ $name })) {
            # cached entry exists, so refresh slot and extract data
            ($data, $error) = $self->_refresh($slot);
            $data = $slot->[ DATA ] 
                unless $error;
            last INCLUDE;
        }
        
        $paths = $self->paths() || do {
            $error = Template::Constants::STATUS_ERROR;
            $data  = $self->error();
            last INCLUDE;
        };
        
        # search the INCLUDE_PATH for the file, in cache or on disk
        foreach $dir (@$paths) {
            $path = File::Spec->catfile($dir, $name);
            
            $self->debug("searching path: $path\n") if $self->{ DEBUG };
            
            if ($caching && ($slot = $self->{ LOOKUP }->{ $path })) {
                # cached entry exists, so refresh slot and extract data
                ($data, $error) = $self->_refresh($slot);
                $data = $slot->[ DATA ]
                    unless $error;
                last INCLUDE;
            }
            elsif (-f $path) {
                $compiled = $self->_compiled_filename($path)
                    if $compext || $compdir;
                
                if ($compiled && -f $compiled 
                    && (stat($path))[9] <= (stat($compiled))[9]) {
                    if ($data = $self->_load_compiled($compiled)) {
                        # store in cache
                        $data  = $self->store($path, $data);
                        $error = Template::Constants::STATUS_OK;
                        last INCLUDE;
                    }
                    else {
                        warn($self->error(), "\n");
                    }
                }
                # $compiled is set if an attempt to write the compiled 
                # template to disk should be made
                
                ($data, $error) = $self->_load($path, $name);
                ($data, $error) = $self->_compile($data, $compiled)
                    unless $error;
                $data = $self->_store($path, $data)
                    unless $error || ! $caching;
                $data = $data->{ data } if ! $caching;
                # all done if $error is OK or ERROR
                last INCLUDE if ! $error 
                    || $error == Template::Constants::STATUS_ERROR;
            }
        }
        # template not found, so look for a DEFAULT template
        my $default;
        if (defined ($default = $self->{ DEFAULT }) && $name ne $default) {
            $name = $default;
            redo INCLUDE;
        }
        ($data, $error) = (undef, Template::Constants::STATUS_DECLINED);
    } # INCLUDE
    
    return ($data, $error);
}



sub _compiled_filename {
    my ($self, $file) = @_;
    my ($compext, $compdir) = @$self{ qw( COMPILE_EXT COMPILE_DIR ) };
    my ($path, $compiled);

    return undef
	unless $compext || $compdir;

    $path = $file;
    $path =~ /^(.+)$/s or die "invalid filename: $path";
    $path =~ s[:][]g if $^O eq 'MSWin32';

	# bug 10211: we're outgrowing Windows' max. path length
	$path = md5_hex($path);

    $compiled = "$path$compext";
    $compiled = File::Spec->catfile($compdir, $compiled) if length $compdir;

    return $compiled;
}


sub _load_compiled {
    my ($self, $file) = @_;
    my $compiled;

    # load compiled template via require();  we zap any
    # %INC entry to ensure it is reloaded (we don't 
    # want 1 returned by require() to say it's in memory)
    delete $INC{ $file };
    eval { $compiled = require $file; };
    return $@
        ? $self->error("compiled template $compiled: $@")
        : $compiled;
}



#------------------------------------------------------------------------
# _load($name, $alias)
#
# Load template text from a string ($name = scalar ref), GLOB or file 
# handle ($name = ref), or from an absolute filename ($name = scalar).
# Returns a hash array containing the following items:
#   name    filename or $alias, if provided, or 'input text', etc.
#   text    template text
#   time    modification time of file, or current time for handles/strings
#   load    time file was loaded (now!)  
#
# On error, returns ($error, STATUS_ERROR), or (undef, STATUS_DECLINED)
# if TOLERANT is set.
#------------------------------------------------------------------------

sub _load {
    my ($self, $name, $alias) = @_;
    my ($data, $error);
    my $tolerant = $self->{ TOLERANT };
    my $now = time;
    local $/ = undef;    # slurp files in one go
    local *FH;

    $alias = $name unless defined $alias or ref $name;

    $self->debug("_load($name, ", defined $alias ? $alias : '<no alias>', 
                 ')') if $self->{ DEBUG };

    LOAD: {
        if (ref $name eq 'SCALAR') {
            # $name can be a SCALAR reference to the input text...
            $data = {
                name => defined $alias ? $alias : 'input text',
                text => $$name,
                time => $now,
                load => 0,
            };
        }
        elsif (ref $name) {
            # ...or a GLOB or file handle...
            my $text = <$name>;
            $text = $self->_decode_unicode($text) if $self->{ UNICODE };
            $data = {
                name => defined $alias ? $alias : 'input file handle',
                text => $text,
                time => $now,
                load => 0,
            };
        }
        elsif (-f $name) {
            if (open(FH, $name)) {
                my $text = <FH>;
                $text = $self->_decode_unicode($text) if $self->{ UNICODE };
                $data = {
                    name => $alias,
                    path => $name,
                    text => $text,
                    time => (stat $name)[9],
                    load => $now,
                };
            }
            elsif ($tolerant) {
                ($data, $error) = (undef, Template::Constants::STATUS_DECLINED);
            }
            else {
                $data  = "$alias: $!";
                $error = Template::Constants::STATUS_ERROR;
            }
        }
        else {
            ($data, $error) = (undef, Template::Constants::STATUS_DECLINED);
        }
    }
    
    $data->{ path } = $data->{ name }
        if $data and ref $data and ! defined $data->{ path };

    return ($data, $error);
}


#------------------------------------------------------------------------
# _refresh(\@slot)
#
# Private method called to mark a cache slot as most recently used.
# A reference to the slot array should be passed by parameter.  The 
# slot is relocated to the head of the linked list.  If the file from
# which the data was loaded has been upated since it was compiled, then
# it is re-loaded from disk and re-compiled.
#------------------------------------------------------------------------

sub _refresh {
    my ($self, $slot) = @_;
    my ($head, $file, $data, $error);


    $self->debug("_refresh([ ", 
                 join(', ', map { defined $_ ? $_ : '<undef>' } @$slot),
                 '])') if $self->{ DEBUG };

    # if it's more than $STAT_TTL seconds since we last performed a 
    # stat() on the file then we need to do it again and see if the file
    # time has changed
    if ( (time - $slot->[ STAT ]) > $STAT_TTL && stat $slot->[ NAME ] ) {
        $slot->[ STAT ] = time;

        if ( (stat(_))[9] != $slot->[ LOAD ]) {
            
            $self->debug("refreshing cache file ", $slot->[ NAME ]) 
                if $self->{ DEBUG };
            
            ($data, $error) = $self->_load($slot->[ NAME ],
                                           $slot->[ DATA ]->{ name });
            ($data, $error) = $self->_compile($data)
                unless $error;
            
            unless ($error) {
                $slot->[ DATA ] = $data->{ data };
                $slot->[ LOAD ] = $data->{ time };
            }
        }
    }
    
    unless( $self->{ HEAD } == $slot ) {
        # remove existing slot from usage chain...
        if ($slot->[ PREV ]) {
            $slot->[ PREV ]->[ NEXT ] = $slot->[ NEXT ];
        }
        else {
            $self->{ HEAD } = $slot->[ NEXT ];
        }
        if ($slot->[ NEXT ]) {
            $slot->[ NEXT ]->[ PREV ] = $slot->[ PREV ];
        }
        else {
            $self->{ TAIL } = $slot->[ PREV ];
        }
        
        # ..and add to start of list
        $head = $self->{ HEAD };
        $head->[ PREV ] = $slot if $head;
        $slot->[ PREV ] = undef;
        $slot->[ NEXT ] = $head;
        $self->{ HEAD } = $slot;
    }
    
    return ($data, $error);
}


#------------------------------------------------------------------------
# _store($name, $data)
#
# Private method called to add a data item to the cache.  If the cache
# size limit has been reached then the oldest entry at the tail of the 
# list is removed and its slot relocated to the head of the list and 
# reused for the new data item.  If the cache is under the size limit,
# or if no size limit is defined, then the item is added to the head 
# of the list.  
#------------------------------------------------------------------------

sub _store {
    my ($self, $name, $data, $compfile) = @_;
    my $size = $self->{ SIZE };
    my ($slot, $head);

    # check the modification time
    my $load = $self->_modified($name);

    # extract the compiled template from the data hash
    $data = $data->{ data };

    $self->debug("_store($name, $data)") if $self->{ DEBUG };

    if (defined $size && $self->{ SLOTS } >= $size) {
        # cache has reached size limit, so reuse oldest entry
        
        $self->debug("reusing oldest cache entry (size limit reached: $size)\nslots: $self->{ SLOTS }") if $self->{ DEBUG };
        
        # remove entry from tail of list
        $slot = $self->{ TAIL };
        $slot->[ PREV ]->[ NEXT ] = undef;
        $self->{ TAIL } = $slot->[ PREV ];
        
        # remove name lookup for old node
        delete $self->{ LOOKUP }->{ $slot->[ NAME ] };
        
        # add modified node to head of list
        $head = $self->{ HEAD };
        $head->[ PREV ] = $slot if $head;
        @$slot = ( undef, $name, $data, $load, $head, time );
        $self->{ HEAD } = $slot;
        
        # add name lookup for new node
        $self->{ LOOKUP }->{ $name } = $slot;
    }
    else {
        # cache is under size limit, or none is defined
        
        $self->debug("adding new cache entry") if $self->{ DEBUG };
        
        # add new node to head of list
        $head = $self->{ HEAD };
        $slot = [ undef, $name, $data, $load, $head, time ];
        $head->[ PREV ] = $slot if $head;
        $self->{ HEAD } = $slot;
        $self->{ TAIL } = $slot unless $self->{ TAIL };
        
        # add lookup from name to slot and increment nslots
        $self->{ LOOKUP }->{ $name } = $slot;
        $self->{ SLOTS }++;
    }

    return $data;
}


#------------------------------------------------------------------------
# _compile($data)
#
# Private method called to parse the template text and compile it into 
# a runtime form.  Creates and delegates a Template::Parser object to
# handle the compilation, or uses a reference passed in PARSER.  On 
# success, the compiled template is stored in the 'data' item of the 
# $data hash and returned.  On error, ($error, STATUS_ERROR) is returned,
# or (undef, STATUS_DECLINED) if the TOLERANT flag is set.
# The optional $compiled parameter may be passed to specify
# the name of a compiled template file to which the generated Perl
# code should be written.  Errors are (for now...) silently 
# ignored, assuming that failures to open a file for writing are 
# intentional (e.g directory write permission).
#------------------------------------------------------------------------

sub _compile {
    my ($self, $data, $compfile) = @_;
    my $text = $data->{ text };
    my ($parsedoc, $error);

    $self->debug("_compile($data, ", 
                 defined $compfile ? $compfile : '<no compfile>', ')') 
        if $self->{ DEBUG };

    my $parser = $self->{ PARSER } 
        ||= Template::Config->parser($self->{ PARAMS })
        ||  return (Template::Config->error(), Template::Constants::STATUS_ERROR);

    # discard the template text - we don't need it any more
    delete $data->{ text };   
    
    # call parser to compile template into Perl code
    if ($parsedoc = $parser->parse($text, $data)) {

        $parsedoc->{ METADATA } = { 
            'name'    => $data->{ name },
            'modtime' => $data->{ time },
            %{ $parsedoc->{ METADATA } },
        };
        
        # write the Perl code to the file $compfile, if defined
        if ($compfile) {
            my $basedir = &File::Basename::dirname($compfile);
            $basedir =~ /(.*)/;
            $basedir = $1;

            unless (-d $basedir) {
                eval { File::Path::mkpath($basedir) };
                $error = "failed to create compiled templates directory: $basedir ($@)"
                    if ($@);
            }

            unless ($error) {
                my $docclass = $self->{ DOCUMENT };
                $error = 'cache failed to write '
                    . &File::Basename::basename($compfile)
                    . ': ' . $docclass->error()
                    unless $docclass->write_perl_file($compfile, $parsedoc);
            }
            
            # set atime and mtime of newly compiled file, don't bother
            # if time is undef
            if (!defined($error) && defined $data->{ time }) {
                my ($cfile) = $compfile =~ /^(.+)$/s or do {
                    return("invalid filename: $compfile", 
                           Template::Constants::STATUS_ERROR);
                };
                
                my ($ctime) = $data->{ time } =~ /^(\d+)$/;
                unless ($ctime || $ctime eq 0) {
                    return("invalid time: $ctime", 
                           Template::Constants::STATUS_ERROR);
                }
                utime($ctime, $ctime, $cfile);
            }
        }
        
        unless ($error) {
            return $data				        ## RETURN ##
                if $data->{ data } = $DOCUMENT->new($parsedoc);
            $error = $Template::Document::ERROR;
        }
    }
    else {
        $error = Template::Exception->new( 'parse', "$data->{ name } " .
                                           $parser->error() );
    }
    
    # return STATUS_ERROR, or STATUS_DECLINED if we're being tolerant
    return $self->{ TOLERANT } 
        ? (undef, Template::Constants::STATUS_DECLINED)
        : ($error,  Template::Constants::STATUS_ERROR)
}


#------------------------------------------------------------------------
# _modified($name)        
# _modified($name, $time) 
#
# When called with a single argument, it returns the modification time 
# of the named template.  When called with a second argument it returns 
# true if $name has been modified since $time.
#------------------------------------------------------------------------

sub _modified {
    my ($self, $name, $time) = @_;
    my $load = (stat($name))[9] 
        || return $time ? 1 : 0;

    return $time 
         ? $load > $time 
         : $load;
}

#------------------------------------------------------------------------
# _dump()
#
# Debug method which returns a string representing the internal object 
# state.
#------------------------------------------------------------------------

sub _dump {
    my $self = shift;
    my $size = $self->{ SIZE };
    my $parser = $self->{ PARSER };
    $parser = $parser ? $parser->_dump() : '<no parser>';
    $parser =~ s/\n/\n    /gm;
    $size = 'unlimited' unless defined $size;

    my $output = "[Template::Provider] {\n";
    my $format = "    %-16s => %s\n";
    my $key;
    
    $output .= sprintf($format, 'INCLUDE_PATH', 
                       '[ ' . join(', ', @{ $self->{ INCLUDE_PATH } }) . ' ]');
    $output .= sprintf($format, 'CACHE_SIZE', $size);
    
    foreach $key (qw( ABSOLUTE RELATIVE TOLERANT DELIMITER
                      COMPILE_EXT COMPILE_DIR )) {
        $output .= sprintf($format, $key, $self->{ $key });
    }
    $output .= sprintf($format, 'PARSER', $parser);


    local $" = ', ';
    my $lookup = $self->{ LOOKUP };
    $lookup = join('', map { 
        sprintf("    $format", $_, defined $lookup->{ $_ }
                ? ('[ ' . join(', ', map { defined $_ ? $_ : '<undef>' }
                               @{ $lookup->{ $_ } }) . ' ]') : '<undef>');
    } sort keys %$lookup);
    $lookup = "{\n$lookup    }";
    
    $output .= sprintf($format, LOOKUP => $lookup);
    
    $output .= '}';
    return $output;
}


#------------------------------------------------------------------------
# _dump_cache()
#
# Debug method which prints the current state of the cache to STDERR.
#------------------------------------------------------------------------

sub _dump_cache {
    my $self = shift;
    my ($node, $lut, $count);

    $count = 0;
    if ($node = $self->{ HEAD }) {
	while ($node) {
	    $lut->{ $node } = $count++;
	    $node = $node->[ NEXT ];
	}
	$node = $self->{ HEAD };
	print STDERR "CACHE STATE:\n";
	print STDERR "  HEAD: ", $self->{ HEAD }->[ NAME ], "\n";
	print STDERR "  TAIL: ", $self->{ TAIL }->[ NAME ], "\n";
	while ($node) {
	    my ($prev, $name, $data, $load, $next) = @$node;
#	    $name = '...' . substr($name, -10) if length $name > 10;
	    $prev = $prev ? "#$lut->{ $prev }<-": '<undef>';
	    $next = $next ? "->#$lut->{ $next }": '<undef>';
	    print STDERR "   #$lut->{ $node } : [ $prev, $name, $data, $load, $next ]\n";
	    $node = $node->[ NEXT ];
	}
    }
}


#------------------------------------------------------------------------
# _decode_unicode
#
# Decodes encoded unicode text that starts with a BOM and
# turns it into perl's internal representation
#------------------------------------------------------------------------


sub _decode_unicode {
    my $self   = shift;
    my $string = shift;

    use bytes;
    require Encode;
    
    return $string if Encode::is_utf8( $string );
    
    # try all the BOMs in order looking for one (order is important
    # 32bit BOMs look like 16bit BOMs)

    my $count  = 0;

    while ($count < @{ $boms }) {
        my $enc = $boms->[$count++];
        my $bom = $boms->[$count++];
        
        # does the string start with the bom?
        if ($bom eq substr($string, 0, length($bom))) {
            # decode it and hand it back
            return Encode::decode($enc, substr($string, length($bom)), 1);
        }
    }

    return $self->{ ENCODING }
        ? Encode::decode( $self->{ ENCODING }, $string )
        : $string;
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

Template::Provider - Provider module for loading/compiling templates

=head1 SYNOPSIS

    $provider = Template::Provider->new(\%options);

    ($template, $error) = $provider->fetch($name);

=head1 DESCRIPTION

The Template::Provider is used to load, parse, compile and cache template
documents.  This object may be sub-classed to provide more specific 
facilities for loading, or otherwise providing access to templates.

The Template::Context objects maintain a list of Template::Provider 
objects which are polled in turn (via fetch()) to return a requested
template.  Each may return a compiled template, raise an error, or 
decline to serve the reqest, giving subsequent providers a chance to
do so.

This is the "Chain of Responsiblity" pattern.  See 'Design Patterns' for
further information.

This documentation needs work.

=head1 PUBLIC METHODS

=head2 new(\%options) 

Constructor method which instantiates and returns a new Template::Provider
object.  The optional parameter may be a hash reference containing any of
the following items:

=over 4




=item INCLUDE_PATH

The INCLUDE_PATH is used to specify one or more directories in which
template files are located.  When a template is requested that isn't
defined locally as a BLOCK, each of the INCLUDE_PATH directories is
searched in turn to locate the template file.  Multiple directories
can be specified as a reference to a list or as a single string where
each directory is delimited by ':'.

    my $provider = Template::Provider->new({
        INCLUDE_PATH => '/usr/local/templates',
    });
  
    my $provider = Template::Provider->new({
        INCLUDE_PATH => '/usr/local/templates:/tmp/my/templates',
    });
  
    my $provider = Template::Provider->new({
        INCLUDE_PATH => [ '/usr/local/templates', 
                          '/tmp/my/templates' ],
    });

On Win32 systems, a little extra magic is invoked, ignoring delimiters
that have ':' followed by a '/' or '\'.  This avoids confusion when using
directory names like 'C:\Blah Blah'.

When specified as a list, the INCLUDE_PATH path can contain elements 
which dynamically generate a list of INCLUDE_PATH directories.  These 
generator elements can be specified as a reference to a subroutine or 
an object which implements a paths() method.

    my $provider = Template::Provider->new({
        INCLUDE_PATH => [ '/usr/local/templates', 
                          \&incpath_generator, 
			  My::IncPath::Generator->new( ... ) ],
    });

Each time a template is requested and the INCLUDE_PATH examined, the
subroutine or object method will be called.  A reference to a list of
directories should be returned.  Generator subroutines should report
errors using die().  Generator objects should return undef and make an
error available via its error() method.

For example:

    sub incpath_generator {

	# ...some code...
	
	if ($all_is_well) {
	    return \@list_of_directories;
	}
	else {
	    die "cannot generate INCLUDE_PATH...\n";
	}
    }

or:

    package My::IncPath::Generator;

    # Template::Base (or Class::Base) provides error() method
    use Template::Base;
    use base qw( Template::Base );

    sub paths {
	my $self = shift;

	# ...some code...

        if ($all_is_well) {
	    return \@list_of_directories;
	}
	else {
	    return $self->error("cannot generate INCLUDE_PATH...\n");
	}
    }

    1;





=item DELIMITER

Used to provide an alternative delimiter character sequence for 
separating paths specified in the INCLUDE_PATH.  The default
value for DELIMITER is ':'.

    # tolerate Silly Billy's file system conventions
    my $provider = Template::Provider->new({
	DELIMITER    => '; ',
        INCLUDE_PATH => 'C:/HERE/NOW; D:/THERE/THEN',
    });

    # better solution: install Linux!  :-)

On Win32 systems, the default delimiter is a little more intelligent,
splitting paths only on ':' characters that aren't followed by a '/'.
This means that the following should work as planned, splitting the 
INCLUDE_PATH into 2 separate directories, C:/foo and C:/bar.

    # on Win32 only
    my $provider = Template::Provider->new({
	INCLUDE_PATH => 'C:/Foo:C:/Bar'
    });

However, if you're using Win32 then it's recommended that you
explicitly set the DELIMITER character to something else (e.g. ';')
rather than rely on this subtle magic.




=item ABSOLUTE

The ABSOLUTE flag is used to indicate if templates specified with
absolute filenames (e.g. '/foo/bar') should be processed.  It is
disabled by default and any attempt to load a template by such a
name will cause a 'file' exception to be raised.

    my $provider = Template::Provider->new({
	ABSOLUTE => 1,
    });

    # this is why it's disabled by default
    [% INSERT /etc/passwd %]

On Win32 systems, the regular expression for matching absolute 
pathnames is tweaked slightly to also detect filenames that start
with a driver letter and colon, such as:

    C:/Foo/Bar






=item RELATIVE

The RELATIVE flag is used to indicate if templates specified with
filenames relative to the current directory (e.g. './foo/bar' or
'../../some/where/else') should be loaded.  It is also disabled by
default, and will raise a 'file' error if such template names are
encountered.  

    my $provider = Template::Provider->new({
	RELATIVE => 1,
    });

    [% INCLUDE ../logs/error.log %]





=item DEFAULT

The DEFAULT option can be used to specify a default template which should 
be used whenever a specified template can't be found in the INCLUDE_PATH.

    my $provider = Template::Provider->new({
	DEFAULT => 'notfound.html',
    });

If a non-existant template is requested through the Template process()
method, or by an INCLUDE, PROCESS or WRAPPER directive, then the
DEFAULT template will instead be processed, if defined.  Note that the
DEFAULT template is not used when templates are specified with
absolute or relative filenames, or as a reference to a input file
handle or text string.





=item CACHE_SIZE

The Template::Provider module caches compiled templates to avoid the need
to re-parse template files or blocks each time they are used.  The CACHE_SIZE
option is used to limit the number of compiled templates that the module
should cache.

By default, the CACHE_SIZE is undefined and all compiled templates are
cached.  When set to any positive value, the cache will be limited to
storing no more than that number of compiled templates.  When a new
template is loaded and compiled and the cache is full (i.e. the number
of entries == CACHE_SIZE), the least recently used compiled template
is discarded to make room for the new one.

The CACHE_SIZE can be set to 0 to disable caching altogether.

    my $provider = Template::Provider->new({
	CACHE_SIZE => 64,   # only cache 64 compiled templates
    });

    my $provider = Template::Provider->new({
	CACHE_SIZE => 0,   # don't cache any compiled templates
    });






=item COMPILE_EXT

From version 2 onwards, the Template Toolkit has the ability to
compile templates to Perl code and save them to disk for subsequent
use (i.e. cache persistence).  The COMPILE_EXT option may be
provided to specify a filename extension for compiled template files.
It is undefined by default and no attempt will be made to read or write 
any compiled template files.

    my $provider = Template::Provider->new({
	COMPILE_EXT => '.ttc',
    });

If COMPILE_EXT is defined (and COMPILE_DIR isn't, see below) then compiled
template files with the COMPILE_EXT extension will be written to the same
directory from which the source template files were loaded.

Compiling and subsequent reuse of templates happens automatically
whenever the COMPILE_EXT or COMPILE_DIR options are set.  The Template
Toolkit will automatically reload and reuse compiled files when it 
finds them on disk.  If the corresponding source file has been modified
since the compiled version as written, then it will load and re-compile
the source and write a new compiled version to disk.  

This form of cache persistence offers significant benefits in terms of 
time and resources required to reload templates.  Compiled templates can
be reloaded by a simple call to Perl's require(), leaving Perl to handle
all the parsing and compilation.  This is a Good Thing.

=item COMPILE_DIR

The COMPILE_DIR option is used to specify an alternate directory root
under which compiled template files should be saved.  

    my $provider = Template::Provider->new({
	COMPILE_DIR => '/tmp/ttc',
    });

The COMPILE_EXT option may also be specified to have a consistent file
extension added to these files.  

    my $provider1 = Template::Provider->new({
	COMPILE_DIR => '/tmp/ttc',
	COMPILE_EXT => '.ttc1',
    });

    my $provider2 = Template::Provider->new({
	COMPILE_DIR => '/tmp/ttc',
	COMPILE_EXT => '.ttc2',
    });


When COMPILE_EXT is undefined, the compiled template files have the
same name as the original template files, but reside in a different
directory tree.

Each directory in the INCLUDE_PATH is replicated in full beneath the 
COMPILE_DIR directory.  This example:

    my $provider = Template::Provider->new({
	COMPILE_DIR  => '/tmp/ttc',
	INCLUDE_PATH => '/home/abw/templates:/usr/share/templates',
    });

would create the following directory structure:

    /tmp/ttc/home/abw/templates/
    /tmp/ttc/usr/share/templates/

Files loaded from different INCLUDE_PATH directories will have their
compiled forms save in the relevant COMPILE_DIR directory.

On Win32 platforms a filename may by prefixed by a drive letter and
colon.  e.g.

    C:/My Templates/header

The colon will be silently stripped from the filename when it is added
to the COMPILE_DIR value(s) to prevent illegal filename being generated.
Any colon in COMPILE_DIR elements will be left intact.  For example:

    # Win32 only
    my $provider = Template::Provider->new({
	DELIMITER    => ';',
	COMPILE_DIR  => 'C:/TT2/Cache',
	INCLUDE_PATH => 'C:/TT2/Templates;D:/My Templates',
    });

This would create the following cache directories:

    C:/TT2/Cache/C/TT2/Templates
    C:/TT2/Cache/D/My Templates




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






=item PARSER

The Template::Parser module implements a parser object for compiling
templates into Perl code which can then be executed.  A default object
of this class is created automatically and then used by the
Template::Provider whenever a template is loaded and requires 
compilation.  The PARSER option can be used to provide a reference to 
an alternate parser object.

    my $provider = Template::Provider->new({
	PARSER => MyOrg::Template::Parser->new({ ... }),
    });



=item DEBUG

The DEBUG option can be used to enable debugging messages from the
Template::Provider module by setting it to include the DEBUG_PROVIDER
value.

    use Template::Constants qw( :debug );

    my $template = Template->new({
	DEBUG => DEBUG_PROVIDER,
    });



=back

=head2 fetch($name)

Returns a compiled template for the name specified.  If the template 
cannot be found then (undef, STATUS_DECLINED) is returned.  If an error
occurs (e.g. read error, parse error) then ($error, STATUS_ERROR) is 
returned, where $error is the error message generated.  If the TOLERANT
flag is set the the method returns (undef, STATUS_DECLINED) instead of
returning an error.

=head2 store($name, $template)

Stores the compiled template, $template, in the cache under the name, 
$name.  Susbequent calls to fetch($name) will return this template in
preference to any disk-based file.

=head2 include_path(\@newpath))

Accessor method for the INCLUDE_PATH setting.  If called with an
argument, this method will replace the existing INCLUDE_PATH with
the new value.

=head2 paths()

This method generates a copy of the INCLUDE_PATH list.  Any elements in the
list which are dynamic generators (e.g. references to subroutines or objects
implementing a paths() method) will be called and the list of directories 
returned merged into the output list.

It is possible to provide a generator which returns itself, thus sending
this method into an infinite loop.  To detect and prevent this from happening,
the C<$MAX_DIRS> package variable, set to 64 by default, limits the maximum
number of paths that can be added to, or generated for the output list.  If
this number is exceeded then the method will immediately return an error 
reporting as much.

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

L<Template|Template>, L<Template::Parser|Template::Parser>, L<Template::Context|Template::Context>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
