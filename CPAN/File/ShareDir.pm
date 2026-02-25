package File::ShareDir;

=pod

=head1 NAME

File::ShareDir - Locate per-dist and per-module shared files

=begin html

<a href="https://travis-ci.org/perl5-utils/File-ShareDir"><img src="https://travis-ci.org/perl5-utils/File-ShareDir.svg?branch=master" alt="Travis CI"/></a>
<a href='https://coveralls.io/github/perl5-utils/File-ShareDir?branch=master'><img src='https://coveralls.io/repos/github/perl5-utils/File-ShareDir/badge.svg?branch=master' alt='Coverage Status' /></a>
<a href="https://saythanks.io/to/rehsack"><img src="https://img.shields.io/badge/Say%20Thanks-!-1EAEDB.svg" alt="Say Thanks" /></a>

=end html

=head1 SYNOPSIS

  use File::ShareDir ':ALL';
  
  # Where are distribution-level shared data files kept
  $dir = dist_dir('File-ShareDir');
  
  # Where are module-level shared data files kept
  $dir = module_dir('File::ShareDir');
  
  # Find a specific file in our dist/module shared dir
  $file = dist_file(  'File-ShareDir',  'file/name.txt');
  $file = module_file('File::ShareDir', 'file/name.txt');
  
  # Like module_file, but search up the inheritance tree
  $file = class_file( 'Foo::Bar', 'file/name.txt' );

=head1 DESCRIPTION

The intent of L<File::ShareDir> is to provide a companion to
L<Class::Inspector> and L<File::HomeDir>, modules that take a
process that is well-known by advanced Perl developers but gets a
little tricky, and make it more available to the larger Perl community.

Quite often you want or need your Perl module (CPAN or otherwise)
to have access to a large amount of read-only data that is stored
on the file-system at run-time.

On a linux-like system, this would be in a place such as /usr/share,
however Perl runs on a wide variety of different systems, and so
the use of any one location is unreliable.

Perl provides a little-known method for doing this, but almost
nobody is aware that it exists. As a result, module authors often
go through some very strange ways to make the data available to
their code.

The most common of these is to dump the data out to an enormous
Perl data structure and save it into the module itself. The
result are enormous multi-megabyte .pm files that chew up a
lot of memory needlessly.

Another method is to put the data "file" after the __DATA__ compiler
tag and limit yourself to access as a filehandle.

The problem to solve is really quite simple.

  1. Write the data files to the system at install time.
  
  2. Know where you put them at run-time.

Perl's install system creates an "auto" directory for both
every distribution and for every module file.

These are used by a couple of different auto-loading systems
to store code fragments generated at install time, and various
other modules written by the Perl "ancient masters".

But the same mechanism is available to any dist or module to
store any sort of data.

=head2 Using Data in your Module

C<File::ShareDir> forms one half of a two part solution.

Once the files have been installed to the correct directory,
you can use C<File::ShareDir> to find your files again after
the installation.

For the installation half of the solution, see L<File::ShareDir::Install>
and its C<install_share> directive.

Using L<File::ShareDir::Install> together with L<File::ShareDir>
allows one to rely on the files in appropriate C<dist_dir()>
or C<module_dir()> in development phase, too.

=head1 FUNCTIONS

C<File::ShareDir> provides four functions for locating files and
directories.

For greater maintainability, none of these are exported by default
and you are expected to name the ones you want at use-time, or provide
the C<':ALL'> tag. All of the following are equivalent.

  # Load but don't import, and then call directly
  use File::ShareDir;
  $dir = File::ShareDir::dist_dir('My-Dist');
  
  # Import a single function
  use File::ShareDir 'dist_dir';
  dist_dir('My-Dist');
  
  # Import all the functions
  use File::ShareDir ':ALL';
  dist_dir('My-Dist');

All of the functions will check for you that the dir/file actually
exists, and that you have read permissions, or they will throw an
exception.

=cut

use 5.005;
use strict;
use warnings;

use base ('Exporter');
use constant IS_MACOS => !!($^O eq 'MacOS');
use constant IS_WIN32 => !!($^O eq 'MSWin32');

use Carp             ();
use Exporter         ();
use File::Spec       ();
use Class::Inspector ();

our %DIST_SHARE;
our %MODULE_SHARE;

our @CARP_NOT;
our @EXPORT_OK = qw{
  dist_dir
  dist_file
  module_dir
  module_file
  class_dir
  class_file
};
our %EXPORT_TAGS = (
    ALL => [@EXPORT_OK],
);
our $VERSION = '1.118';

#####################################################################
# Interface Functions

=pod

=head2 dist_dir

  # Get a distribution's shared files directory
  my $dir = dist_dir('My-Distribution');

The C<dist_dir> function takes a single parameter of the name of an
installed (CPAN or otherwise) distribution, and locates the shared
data directory created at install time for it.

Returns the directory path as a string, or dies if it cannot be
located or is not readable.

=cut

sub dist_dir
{
    my $dist = _DIST(shift);
    my $dir;

    # Try the new version, then fall back to the legacy version
    $dir = _dist_dir_new($dist) || _dist_dir_old($dist);

    return $dir if defined $dir;

    # Ran out of options
    Carp::croak("Failed to find share dir for dist '$dist'");
}

sub _dist_dir_new
{
    my $dist = shift;

    return $DIST_SHARE{$dist} if exists $DIST_SHARE{$dist};

    # Create the subpath
    my $path = File::Spec->catdir('auto', 'share', 'dist', $dist);

    # Find the full dir within @INC
    return _search_inc_path($path);
}

sub _dist_dir_old
{
    my $dist = shift;

    # Create the subpath
    my $path = File::Spec->catdir('auto', split(/-/, $dist),);

    # Find the full dir within @INC
    return _search_inc_path($path);
}

=pod

=head2 module_dir

  # Get a module's shared files directory
  my $dir = module_dir('My::Module');

The C<module_dir> function takes a single parameter of the name of an
installed (CPAN or otherwise) module, and locates the shared data
directory created at install time for it.

In order to find the directory, the module B<must> be loaded when
calling this function.

Returns the directory path as a string, or dies if it cannot be
located or is not readable.

=cut

sub module_dir
{
    my $module = _MODULE(shift);

    return $MODULE_SHARE{$module} if exists $MODULE_SHARE{$module};

    # Try the new version first, then fall back to the legacy version
    return _module_dir_new($module) || _module_dir_old($module);
}

sub _module_dir_new
{
    my $module = shift;

    # Create the subpath
    my $path = File::Spec->catdir('auto', 'share', 'module', _module_subdir($module),);

    # Find the full dir within @INC
    return _search_inc_path($path);
}

sub _module_dir_old
{
    my $module = shift;
    my $short  = Class::Inspector->filename($module);
    my $long   = Class::Inspector->loaded_filename($module);
    $short =~ tr{/}{:}   if IS_MACOS;
    $short =~ tr{\\} {/} if IS_WIN32;
    $long  =~ tr{\\} {/} if IS_WIN32;
    substr($short, -3, 3, '');
    $long =~ m/^(.*)\Q$short\E\.pm\z/s or Carp::croak("Failed to find base dir");
    my $dir = File::Spec->catdir("$1", 'auto', $short);

    -d $dir or Carp::croak("Directory '$dir': No such directory");
    -r $dir or Carp::croak("Directory '$dir': No read permission");

    return $dir;
}

=pod

=head2 dist_file

  # Find a file in our distribution shared dir
  my $dir = dist_file('My-Distribution', 'file/name.txt');

The C<dist_file> function takes two parameters of the distribution name
and file name, locates the dist directory, and then finds the file within
it, verifying that the file actually exists, and that it is readable.

The filename should be a relative path in the format of your local
filesystem. It will simply added to the directory using L<File::Spec>'s
C<catfile> method.

Returns the file path as a string, or dies if the file or the dist's
directory cannot be located, or the file is not readable.

=cut

sub dist_file
{
    my $dist = _DIST(shift);
    my $file = _FILE(shift);

    # Try the new version first, in doubt hand off to the legacy version
    my $path = _dist_file_new($dist, $file) || _dist_file_old($dist, $file);
    $path or Carp::croak("Failed to find shared file '$file' for dist '$dist'");

    -f $path or Carp::croak("File '$path': No such file");
    -r $path or Carp::croak("File '$path': No read permission");

    return $path;
}

sub _dist_file_new
{
    my $dist = shift;
    my $file = shift;

    # If it exists, what should the path be
    my $dir = _dist_dir_new($dist);
    return undef unless defined $dir;
    my $path = File::Spec->catfile($dir, $file);

    # Does the file exist
    return undef unless -e $path;

    return $path;
}

sub _dist_file_old
{
    my $dist = shift;
    my $file = shift;

    # If it exists, what should the path be
    my $dir = _dist_dir_old($dist);
    return undef unless defined $dir;
    my $path = File::Spec->catfile($dir, $file);

    # Does the file exist
    return undef unless -e $path;

    return $path;
}

=pod

=head2 module_file

  # Find a file in our module shared dir
  my $dir = module_file('My::Module', 'file/name.txt');

The C<module_file> function takes two parameters of the module name
and file name. It locates the module directory, and then finds the file
within it, verifying that the file actually exists, and that it is readable.

In order to find the directory, the module B<must> be loaded when
calling this function.

The filename should be a relative path in the format of your local
filesystem. It will simply added to the directory using L<File::Spec>'s
C<catfile> method.

Returns the file path as a string, or dies if the file or the dist's
directory cannot be located, or the file is not readable.

=cut

sub module_file
{
    my $module = _MODULE(shift);
    my $file   = _FILE(shift);
    my $dir    = module_dir($module);
    my $path   = File::Spec->catfile($dir, $file);

    -e $path or Carp::croak("File '$path' does not exist in module dir");
    -r $path or Carp::croak("File '$path': No read permission");

    return $path;
}

=pod

=head2 class_file

  # Find a file in our module shared dir, or in our parent class
  my $dir = class_file('My::Module', 'file/name.txt');

The C<module_file> function takes two parameters of the module name
and file name. It locates the module directory, and then finds the file
within it, verifying that the file actually exists, and that it is readable.

In order to find the directory, the module B<must> be loaded when
calling this function.

The filename should be a relative path in the format of your local
filesystem. It will simply added to the directory using L<File::Spec>'s
C<catfile> method.

If the file is NOT found for that module, C<class_file> will scan up
the module's @ISA tree, looking for the file in all of the parent
classes.

This allows you to, in effect, "subclass" shared files.

Returns the file path as a string, or dies if the file or the dist's
directory cannot be located, or the file is not readable.

=cut

sub class_file
{
    my $module = _MODULE(shift);
    my $file   = _FILE(shift);

    # Get the super path ( not including UNIVERSAL )
    # Rather than using Class::ISA, we'll use an inlined version
    # that implements the same basic algorithm.
    my @path  = ();
    my @queue = ($module);
    my %seen  = ($module => 1);
    while (my $cl = shift @queue)
    {
        push @path, $cl;
        no strict 'refs';    ## no critic (TestingAndDebugging::ProhibitNoStrict)
        unshift @queue, grep { !$seen{$_}++ }
          map { my $s = $_; $s =~ s/^::/main::/; $s =~ s/\'/::/g; $s } (@{"${cl}::ISA"});
    }

    # Search up the path
    foreach my $class (@path)
    {
        my $dir = eval { module_dir($class); };
        next if $@;
        my $path = File::Spec->catfile($dir, $file);
        -e $path or next;
        -r $path or Carp::croak("File '$file' cannot be read, no read permissions");
        return $path;
    }
    Carp::croak("File '$file' does not exist in class or parent shared files");
}

## no critic (BuiltinFunctions::ProhibitStringyEval)
if (eval "use List::MoreUtils 0.428; 1;")
{
    List::MoreUtils->import("firstres");
}
else
{
    ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
    eval <<'END_OF_BORROWED_CODE';
sub firstres (&@)
{
    my $test = shift;
    foreach (@_)
    {
        my $testval = $test->();
        $testval and return $testval;
    }
    return undef;
}
END_OF_BORROWED_CODE
}

#####################################################################
# Support Functions

sub _search_inc_path
{
    my $path = shift;

    # Find the full dir within @INC
    my $dir = firstres(
        sub {
            my $d;
            $d = File::Spec->catdir($_, $path) if defined _STRING($_);
            defined $d and -d $d ? $d : 0;
        },
        @INC
    ) or return;

    Carp::croak("Found directory '$dir', but no read permissions") unless -r $dir;

    return $dir;
}

sub _module_subdir
{
    my $module = shift;
    $module =~ s/::/-/g;
    return $module;
}

## no critic (BuiltinFunctions::ProhibitStringyEval)
if (eval "use Params::Util 1.07; 1;")
{
    Params::Util->import("_CLASS", "_STRING");
}
else
{
    ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
    eval <<'END_OF_BORROWED_CODE';
# Inlined from Params::Util pure perl version
sub _CLASS ($)
{
    return (defined $_[0] and !ref $_[0] and $_[0] =~ m/^[^\W\d]\w*(?:::\w+)*\z/s) ? $_[0] : undef;
}

sub _STRING ($)
{
    (defined $_[0] and ! ref $_[0] and length($_[0])) ? $_[0] : undef;
}
END_OF_BORROWED_CODE
}

# Maintainer note: The following private functions are used by
#                  File::ShareDir::PAR. (It has to or else it would have to copy&fork)
#                  So if you significantly change or even remove them, please
#                  notify the File::ShareDir::PAR maintainer(s). Thank you!

# Matches a valid distribution name
### This is a total guess at this point
sub _DIST    ## no critic (Subroutines::RequireArgUnpacking)
{
    defined _STRING($_[0]) and $_[0] =~ /^[a-z0-9+_-]+$/is and return $_[0];
    Carp::croak("Not a valid distribution name");
}

# A valid and loaded module name
sub _MODULE
{
    my $module = _CLASS(shift) or Carp::croak("Not a valid module name");
    Class::Inspector->loaded($module) and return $module;
    Carp::croak("Module '$module' is not loaded");
}

# A valid file name
sub _FILE
{
    my $file = shift;
    _STRING($file) or Carp::croak("Did not pass a file name");
    File::Spec->file_name_is_absolute($file) and Carp::croak("Cannot use absolute file name '$file'");
    return $file;
}

1;

=pod

=head1 EXTENDING

=head2 Overriding Directory Resolution

C<File::ShareDir> has two convenience hashes for people who have advanced usage
requirements of C<File::ShareDir> such as using uninstalled C<share>
directories during development.

  #
  # Dist-Name => /absolute/path/for/DistName/share/dir
  #
  %File::ShareDir::DIST_SHARE

  #
  # Module::Name => /absolute/path/for/Module/Name/share/dir
  #
  %File::ShareDir::MODULE_SHARE

Setting these values any time before the corresponding calls

  dist_dir('Dist-Name')
  dist_file('Dist-Name','some/file');

  module_dir('Module::Name');
  module_file('Module::Name','some/file');

Will override the base directory for resolving those calls.

An example of where this would be useful is in a test for a module that
depends on files installed into a share directory, to enable the tests
to use the development copy without needing to install them first.

  use File::ShareDir;
  use Cwd qw( getcwd );
  use File::Spec::Functions qw( rel2abs catdir );

  $File::ShareDir::MODULE_SHARE{'Foo::Module'} = rel2abs(catfile(getcwd,'share'));

  use Foo::Module;

  # internal calls in Foo::Module to module_file('Foo::Module','bar') now resolves to
  # the source trees share/ directory instead of something in @INC

=head1 SUPPORT

Bugs should always be submitted via the CPAN request tracker, see below.

You can find documentation for this module with the perldoc command.

    perldoc File::ShareDir

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=File-ShareDir>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/File-ShareDir>

=item * CPAN Ratings

L<http://cpanratings.perl.org/s/File-ShareDir>

=item * CPAN Search

L<http://search.cpan.org/dist/File-ShareDir/>

=back

=head2 Where can I go for other help?

If you have a bug report, a patch or a suggestion, please open a new
report ticket at CPAN (but please check previous reports first in case
your issue has already been addressed).

Report tickets should contain a detailed description of the bug or
enhancement request and at least an easily verifiable way of
reproducing the issue or fix. Patches are always welcome, too.

=head2 Where can I go for help with a concrete version?

Bugs and feature requests are accepted against the latest version
only. To get patches for earlier versions, you need to get an
agreement with a developer of your choice - who may or not report the
issue and a suggested fix upstream (depends on the license you have
chosen).

=head2 Business support and maintenance

For business support you can contact the maintainer via his CPAN
email address. Please keep in mind that business support is neither
available for free nor are you eligible to receive any support
based on the license distributed with this package.

=head1 AUTHOR

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

=head2 MAINTAINER

Jens Rehsack E<lt>rehsack@cpan.orgE<gt>

=head1 SEE ALSO

L<File::ShareDir::Install>,
L<File::ConfigDir>, L<File::HomeDir>,
L<Module::Install>, L<Module::Install::Share>,
L<File::ShareDir::PAR>, L<Dist::Zilla::Plugin::ShareDir>

=head1 COPYRIGHT

Copyright 2005 - 2011 Adam Kennedy,
Copyright 2014 - 2018 Jens Rehsack.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
