package File::ShareDir::Install; # git description: v0.13-6-g9916db6
# ABSTRACT: Install shared files

use strict;
use warnings;

use Carp ();

use File::Spec;
use IO::Dir;

our $VERSION = '0.14';

our @DIRS;
our %ALREADY;

require Exporter;

our @ISA = qw( Exporter );
our @EXPORT = qw( install_share delete_share );
our @EXPORT_OK = qw( postamble install_share delete_share );
our $INCLUDE_DOTFILES = 0;
our $INCLUDE_DOTDIRS = 0;

#####################################################################
sub install_share
{
    my $dir  = @_ ? pop : 'share';
    my $type = @_ ? shift : 'dist';
    unless ( defined $type and
            ( $type =~ /^(module|dist)$/ ) ) {
        Carp::confess "Illegal or invalid share dir type '$type'";
    }

    if( $type eq 'dist' and @_ ) {
        Carp::confess "Too many parameters to install_share";
    }

    my $def = _mk_def( $type );
    _add_module( $def, $_[0] );

    _add_dir( $def, $dir );
}


#####################################################################
sub delete_share
{
    my $dir  = @_ ? pop : '';
    my $type = @_ ? shift : 'dist';
    unless ( defined $type and
            ( $type =~ /^(module|dist)$/ ) ) {
        Carp::confess "Illegal or invalid share dir type '$type'";
    }

    if( $type eq 'dist' and @_ ) {
        Carp::confess "Too many parameters to delete_share";
    }

    my $def = _mk_def( "delete-$type" );
    _add_module( $def, $_[0] );
    _add_dir( $def, $dir );
}



#
# Build a task definition
sub _mk_def
{
    my( $type ) = @_;
    return { type=>$type,
             dotfiles => $INCLUDE_DOTFILES,
             dotdirs => $INCLUDE_DOTDIRS
           };
}

#
# Add the module to a task definition
sub _add_module
{
    my( $def, $class ) =  @_;
    if( $def->{type} =~ /module$/ ) {
        my $module = _CLASS( $class );
        unless ( defined $module ) {
            Carp::confess "Missing or invalid module name '$_[0]'";
        }
        $def->{module} = $module;
    }
}

#
# Add directories to a task definition
# Save the definition
sub _add_dir
{
    my( $def, $dir ) = @_;

    $dir = [ $dir ] unless ref $dir;

    my $del = 0;
    $del = 1 if $def->{type} =~ /^delete-/;

    foreach my $d ( @$dir ) {
        unless ( $del or (defined $d and -d $d) ) {
            Carp::confess "Illegal or missing directory '$d'";
        }
        if( not $del and $ALREADY{ $d }++ ) {
            Carp::confess "Directory '$d' is already being installed";
        }
        push @DIRS, { %$def };
        $DIRS[-1]{dir} = $d;
    }
}


#####################################################################
# Build the postamble section
sub postamble
{
    my $self = shift;

    my @ret; # = $self->SUPER::postamble( @_ );
    foreach my $def ( @DIRS ) {
        push @ret, __postamble_share_dir( $self, $def );
    }
    return join "\n", @ret;
}

#####################################################################
sub __postamble_share_dir
{
    my( $self, $def ) = @_;

    my $dir = $def->{dir};

    my( $idir );

    if( $def->{type} eq 'delete-dist' ) {
        $idir = File::Spec->catdir( _dist_dir(), $dir );
    }
    elsif( $def->{type} eq 'delete-module' ) {
        $idir = File::Spec->catdir( _module_dir( $def ), $dir );
    }
    elsif ( $def->{type} eq 'dist' ) {
        $idir = _dist_dir();
    }
    else {                                  # delete-share and share
        $idir = _module_dir( $def );
    }

    my @cmds;
    if( $def->{type} =~ /^delete-/ ) {
        @cmds = "\$(RM_RF) $idir";
    }
    else {
        my $autodir = '$(INST_LIB)';
        my $pm_to_blib = $self->oneliner(<<CODE, ['-MExtUtils::Install']);
pm_to_blib({\@ARGV}, '$autodir')
CODE

        my $files = {};
        _scan_share_dir( $files, $idir, $dir, $def );
        @cmds = $self->split_command( $pm_to_blib,
            map { ($self->quote_literal($_) => $self->quote_literal($files->{$_})) } sort keys %$files );
    }

    my $r = join '', map { "\t\$(NOECHO) $_\n" } @cmds;

#    use Data::Dumper;
#    die Dumper $files;
    # Set up the install
    return "config::\n$r";
}

# Get the per-dist install directory.
# We depend on the Makefile for most of the info
sub _dist_dir
{
    return File::Spec->catdir( '$(INST_LIB)',
                                    qw( auto share dist ),
                                    '$(DISTNAME)'
                                  );
}

# Get the per-module install directory
# We depend on the Makefile for most of the info
sub _module_dir
{
    my( $def ) = @_;
    my $module = $def->{module};
    $module =~ s/::/-/g;
    return  File::Spec->catdir( '$(INST_LIB)',
                                    qw( auto share module ),
                                    $module
                                  );
}

sub _scan_share_dir
{
    my( $files, $idir, $dir, $def ) = @_;
    my $dh = IO::Dir->new( $dir ) or die "Unable to read $dir: $!";
    my $entry;
    while( defined( $entry = $dh->read ) ) {
        next if $entry =~ /(~|,v|#)$/;
        my $full = File::Spec->catfile( $dir, $entry );
        if( -f $full ) {
            next if not $def->{dotfiles} and $entry =~ /^\./;
            $files->{ $full } = File::Spec->catfile( $idir, $entry );
        }
        elsif( -d $full ) {
            if( $def->{dotdirs} ) {
                next if $entry eq '.' or $entry eq '..' or
                        $entry =~ /^\.(svn|git|cvs)$/;
            }
            else {
                next if $entry =~ /^\./;
            }
            _scan_share_dir( $files, File::Spec->catdir( $idir, $entry ), $full, $def );
        }
    }
}


#####################################################################
# Cloned from Params::Util::_CLASS
sub _CLASS ($) {
    (
        defined $_[0]
        and
        ! ref $_[0]
        and
        $_[0] =~ m/^[^\W\d]\w*(?:::\w+)*$/s
    ) ? $_[0] : undef;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

File::ShareDir::Install - Install shared files

=head1 VERSION

version 0.14

=head1 SYNOPSIS

    use ExtUtils::MakeMaker;
    use File::ShareDir::Install;

    install_share 'share';
    install_share dist => 'dist-share';
    install_share module => 'My::Module' => 'other-share';

    WriteMakefile( ... );       # As you normally would

    package MY;
    use File::ShareDir::Install qw(postamble);

=head1 DESCRIPTION

File::ShareDir::Install allows you to install read-only data files from a
distribution. It is a companion module to L<File::ShareDir>, which
allows you to locate these files after installation.

It is a port of L<Module::Install::Share> to L<ExtUtils::MakeMaker> with the
improvement of only installing the files you want; C<.svn>, C<.git> and other
source-control junk will be ignored.

Please note that this module installs read-only data files; empty
directories will be ignored.

=head1 EXPORT

=head2 install_share

    install_share $dir;
    install_share dist => $dir;
    install_share module => $module, $dir;

Causes all the files in C<$dir> and its sub-directories to be installed
into a per-dist or per-module share directory.  Must be called before
C<WriteMakefile>.

The first 2 forms are equivalent; the files are installed in a per-distribution
directory.  For example C</usr/lib/perl5/site_perl/auto/share/dist/My-Dist>.  The
name of that directory can be recovered with L<File::ShareDir/dist_dir>.

The last form installs files in a per-module directory.  For example
C</usr/lib/perl5/site_perl/auto/share/module/My-Dist-Package>.  The name of that
directory can be recovered with L<File::ShareDir/module_dir>.

The parameter C<$dir> may be an array of directories.

The files will be installed when you run C<make install>.  However, the list
of files to install is generated when Makefile.PL is run.

Note that if you make multiple calls to C<install_share> on different
directories that contain the same filenames, the last of these calls takes
precedence.  In other words, if you do:

    install_share 'share1';
    install_share 'share2';

And both C<share1> and C<share2> contain a file called C<info.txt>, the file
C<share2/info.txt> will be installed into your C<dist_dir()>.

=head2 delete_share

    delete_share $list;
    delete_share dist => $list;
    delete_share module => $module, $list;

Remove previously installed files or directories.

Unlike L</install_share>, the last parameter is a list of files or
directories that were previously installed.  These files and directories will
be deleted when you run C<make install>.

The parameter C<$list> may be an array of files or directories.

Deletion happens in-order along with installation.  This means that you may
delete all previously installed files by putting the following at the top of
your Makefile.PL.

    delete_share '.';

You can also selectively remove some files from installation.

    install_share 'some-dir';
    if( ... ) {
        delete_share 'not-this-file.rc';
    }

=head2 postamble

This function must be exported into the MY package.  You will normally do this
with the following.

    package MY;
    use File::ShareDir::Install qw( postamble );

If you need to overload postamble, use the following.

    package MY;
    use File::ShareDir::Install;

    sub postamble {
        my $self = shift;
        my @ret = File::ShareDir::Install::postamble( $self );
        # ... add more things to @ret;
        return join "\n", @ret;
    }

=head1 CONFIGURATION

Two variables control the handling of dot-files and dot-directories.

A dot-file has a filename that starts with a period (.).  For example
C<.htaccess>. A dot-directory is a directory that starts with a
period (.).  For example C<.config/>.  Not all filesystems support the use
of dot-files.

=head2 $INCLUDE_DOTFILES

If set to a true value, dot-files will be copied.  Default is false.

=head2 $INCLUDE_DOTDIRS

If set to a true value, the files inside dot-directories will be copied.
Known version control directories are still ignored.  Default is false.

=head2 Note

These variables only influence subsequent calls to C<install_share()>.  This allows
you to control the behaviour for each directory.

For example:

    $INCLUDE_DOTDIRS = 1;
    install_share 'share1';
    $INCLUDE_DOTFILES = 1;
    $INCLUDE_DOTDIRS = 0;
    install_share 'share2';

The directory C<share1> will have files in its dot-directories installed,
but not dot-files.  The directory C<share2> will have files in its dot-files
installed, but dot-directories will be ignored.

=head1 SEE ALSO

L<File::ShareDir>, L<Module::Install>.

=head1 SUPPORT

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=File-ShareDir-Install>
(or L<bug-File-ShareDir-Install@rt.cpan.org|mailto:bug-File-ShareDir-Install@rt.cpan.org>).

=head1 AUTHOR

Philip Gwyn <gwyn@cpan.org>

=head1 CONTRIBUTORS

=for stopwords Karen Etheridge Shoichi Kaji

=over 4

=item *

Karen Etheridge <ether@cpan.org>

=item *

Shoichi Kaji <skaji@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2009 by Philip Gwyn.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
