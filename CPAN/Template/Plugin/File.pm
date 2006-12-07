#============================================================= -*-Perl-*-
#
# Template::Plugin::File
#
# DESCRIPTION
#  Plugin for encapsulating information about a system file.
#
# AUTHOR
#   Originally written by Michael Stevens <michael@etla.org> as the
#   Directory plugin, then mutilated by Andy Wardley <abw@kfs.org> 
#   into separate File and Directory plugins, with some additional 
#   code for working with views, etc.
#
# COPYRIGHT
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
# REVISION
#   $Id: File.pm,v 2.68 2006/01/30 20:05:48 abw Exp $
#
#============================================================================

package Template::Plugin::File;

use strict;
use warnings;
use Cwd;
use File::Spec;
use File::Basename;
use base 'Template::Plugin';

our $VERSION = sprintf("%d.%02d", q$Revision: 2.68 $ =~ /(\d+)\.(\d+)/);

our @STAT_KEYS = qw( dev ino mode nlink uid gid rdev size 
                     atime mtime ctime blksize blocks );


#------------------------------------------------------------------------
# new($context, $file, \%config)
#
# Create a new File object.  Takes the pathname of the file as
# the argument following the context and an optional 
# hash reference of configuration parameters.
#------------------------------------------------------------------------

sub new {
    my $config = ref($_[-1]) eq 'HASH' ? pop(@_) : { };
    my ($class, $context, $path) = @_;
    my ($root, $home, @stat, $abs);

    return $class->throw('no file specified')
	unless defined $path and length $path;

    # path, dir, name, root, home

    if (File::Spec->file_name_is_absolute($path)) {
        $root = '';
    }
    elsif (($root = $config->{ root })) {
        # strip any trailing '/' from root
        $root =~ s[/$][];
    }
    else {
        $root = '';
    }

    my ($name, $dir, $ext) = fileparse($path, '\.\w+');
    # fixup various items
    $dir  =~ s[/$][];
    $dir  = '' if $dir eq '.';
    $name = $name . $ext;
    $ext  =~ s/^\.//g;

    my @fields = File::Spec->splitdir($dir);
    shift @fields if @fields && ! length $fields[0];
    $home = join('/', ('..') x @fields);
    $abs = File::Spec->catfile($root ? $root : (), $path);

    my $self = { 
        path  => $path,
        name  => $name,
        root  => $root,
        home  => $home,
        dir   => $dir,
        ext   => $ext,
        abs   => $abs,
        user  => '',
        group => '',
        isdir => '',
        stat  => defined $config->{ stat } 
                       ? $config->{ stat } 
                       : ! $config->{ nostat },
        map { ($_ => '') } @STAT_KEYS,
    };

    if ($self->{ stat }) {
        (@stat = stat( $abs ))
            || return $class->throw("$abs: $!");

        @$self{ @STAT_KEYS } = @stat;

        unless ($config->{ noid }) {
            $self->{ user  } = eval { getpwuid( $self->{ uid }) || $self->{ uid } };
            $self->{ group } = eval { getgrgid( $self->{ gid }) || $self->{ gid } };
        }
        $self->{ isdir } = -d $abs;
    }

    bless $self, $class;
}


#-------------------------------------------------------------------------
# rel($file)
#
# Generate a relative filename for some other file relative to this one.
#------------------------------------------------------------------------

sub rel {
    my ($self, $path) = @_;
    $path = $path->{ path } if ref $path eq ref $self;  # assumes same root
    return $path if $path =~ m[^/];
    return $path unless $self->{ home };
    return $self->{ home } . '/' . $path;
}


#------------------------------------------------------------------------
# present($view)
#
# Present self to a Template::View.
#------------------------------------------------------------------------

sub present {
    my ($self, $view) = @_;
    $view->view_file($self);
}


sub throw {
    my ($self, $error) = @_;
    die (Template::Exception->new('File', $error));
}

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

Template::Plugin::File - Plugin providing information about files

=head1 SYNOPSIS

    [% USE File(filepath) %]
    [% File.path %]         # full path
    [% File.name %]	    # filename
    [% File.dir %]          # directory

=head1 DESCRIPTION

This plugin provides an abstraction of a file.  It can be used to 
fetch details about files from the file system, or to represent abstract
files (e.g. when creating an index page) that may or may not exist on 
a file system.

A file name or path should be specified as a constructor argument.  e.g.

    [% USE File('foo.html') %]
    [% USE File('foo/bar/baz.html') %]
    [% USE File('/foo/bar/baz.html') %]

The file should exist on the current file system (unless 'nostat'
option set, see below) as an absolute file when specified with as
leading '/' as per '/foo/bar/baz.html', or otherwise as one relative
to the current working directory.  The constructor performs a stat()
on the file and makes the 13 elements returned available as the plugin
items:

    dev ino mode nlink uid gid rdev size 
    atime mtime ctime blksize blocks

e.g.

    [% USE File('/foo/bar/baz.html') %]

    [% File.mtime %]
    [% File.mode %]
    ...

In addition, the 'user' and 'group' items are set to contain the user
and group names as returned by calls to getpwuid() and getgrgid() for
the file 'uid' and 'gid' elements, respectively.  On Win32 platforms
on which getpwuid() and getgrid() are not available, these values are
undefined.

    [% USE File('/tmp/foo.html') %]
    [% File.uid %]	# e.g. 500
    [% File.user %]     # e.g. abw

This user/group lookup can be disabled by setting the 'noid' option.

    [% USE File('/tmp/foo.html', noid=1) %]
    [% File.uid %]	# e.g. 500
    [% File.user %]     # nothing

The 'isdir' flag will be set if the file is a directory.

    [% USE File('/tmp') %]
    [% File.isdir %]	# 1

If the stat() on the file fails (e.g. file doesn't exists, bad
permission, etc) then the constructor will throw a 'File' exception.
This can be caught within a TRY...CATCH block.

    [% TRY %]
       [% USE File('/tmp/myfile') %]
       File exists!
    [% CATCH File %]
       File error: [% error.info %]
    [% END %]

Note the capitalisation of the exception type, 'File' to indicate an
error thrown by the 'File' plugin, to distinguish it from a regular
'file' exception thrown by the Template Toolkit.

Note that the 'File' plugin can also be referenced by the lower case
name 'file'.  However, exceptions are always thrown of the 'File'
type, regardless of the capitalisation of the plugin named used.

    [% USE file('foo.html') %]
    [% file.mtime %]

As with any other Template Toolkit plugin, an alternate name can be 
specified for the object created.

    [% USE foo = file('foo.html') %]
    [% foo.mtime %]

The 'nostat' option can be specified to prevent the plugin constructor
from performing a stat() on the file specified.  In this case, the
file does not have to exist in the file system, no attempt will be made
to verify that it does, and no error will be thrown if it doesn't.
The entries for the items usually returned by stat() will be set 
empty.

    [% USE file('/some/where/over/the/rainbow.html', nostat=1) 
    [% file.mtime %]     # nothing

All File plugins, regardless of the nostat option, have set a number
of items relating to the original path specified.

=over 4

=item path

The full, original file path specified to the constructor.

    [% USE file('/foo/bar.html') %]
    [% file.path %]	# /foo/bar.html

=item name

The name of the file without any leading directories.

    [% USE file('/foo/bar.html') %]
    [% file.name %]	# bar.html

=item dir

The directory element of the path with the filename removed.

    [% USE file('/foo/bar.html') %]
    [% file.name %]	# /foo

=item ext

The file extension, if any, appearing at the end of the path following 
a '.' (not included in the extension).

    [% USE file('/foo/bar.html') %]
    [% file.ext %]	# html

=item home

This contains a string of the form '../..' to represent the upward path
from a file to its root directory.

    [% USE file('bar.html') %]
    [% file.home %]	# nothing

    [% USE file('foo/bar.html') %]
    [% file.home %]	# ..

    [% USE file('foo/bar/baz.html') %]
    [% file.home %]	# ../..

=item root

The 'root' item can be specified as a constructor argument, indicating
a root directory in which the named file resides.  This is otherwise
set empty.

    [% USE file('foo/bar.html', root='/tmp') %]
    [% file.root %]	# /tmp

=item abs

This returns the absolute file path by constructing a path from the 
'root' and 'path' options.

    [% USE file('foo/bar.html', root='/tmp') %]
    [% file.path %]	# foo/bar.html
    [% file.root %]	# /tmp
    [% file.abs %]	# /tmp/foo/bar.html

=back

In addition, the following method is provided:

=over 4 

=item rel(path)

This returns a relative path from the current file to another path specified
as an argument.  It is constructed by appending the path to the 'home' 
item.

    [% USE file('foo/bar/baz.html') %]
    [% file.rel('wiz/waz.html') %]	# ../../wiz/waz.html

=back

=head1 EXAMPLES

    [% USE file('/foo/bar/baz.html') %]

    [% file.path  %]      # /foo/bar/baz.html
    [% file.dir   %]      # /foo/bar
    [% file.name  %]      # baz.html
    [% file.home  %]      # ../..
    [% file.root  %]      # ''
    [% file.abs   %]      # /foo/bar/baz.html
    [% file.ext   %]      # html
    [% file.mtime %]	  # 987654321
    [% file.atime %]      # 987654321
    [% file.uid   %]      # 500
    [% file.user  %]      # abw

    [% USE file('foo.html') %]

    [% file.path %]	      # foo.html
    [% file.dir  %]       # ''
    [% file.name %]	      # foo.html
    [% file.root %]       # ''
    [% file.home %]       # ''
    [% file.abs  %]       # foo.html

    [% USE file('foo/bar/baz.html') %]

    [% file.path %]	      # foo/bar/baz.html
    [% file.dir  %]       # foo/bar
    [% file.name %]	      # baz.html
    [% file.root %]       # ''
    [% file.home %]       # ../..
    [% file.abs  %]       # foo/bar/baz.html

    [% USE file('foo/bar/baz.html', root='/tmp') %]

    [% file.path %]	      # foo/bar/baz.html
    [% file.dir  %]       # foo/bar
    [% file.name %]	      # baz.html
    [% file.root %]       # /tmp
    [% file.home %]       # ../..
    [% file.abs  %]       # /tmp/foo/bar/baz.html

    # calculate other file paths relative to this file and its root
    [% USE file('foo/bar/baz.html', root => '/tmp/tt2') %]

    [% file.path('baz/qux.html') %]	    # ../../baz/qux.html
    [% file.dir('wiz/woz.html')  %]     # ../../wiz/woz.html


=head1 AUTHORS

Michael Stevens E<lt>michael@etla.orgE<gt> wrote the original Directory plugin
on which this is based.  Andy Wardley E<lt>abw@wardley.orgE<gt> split it into 
separate File and Directory plugins, added some extra code and documentation
for VIEW support, and made a few other minor tweaks.

=head1 VERSION

2.68, distributed as part of the
Template Toolkit version 2.15, released on 26 May 2006.



=head1 COPYRIGHT

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>, L<Template::Plugin::Directory|Template::Plugin::Directory>, L<Template::View|Template::View>

