package File::Next;

use strict;
use warnings;

=head1 NAME

File::Next - File-finding iterator

=head1 VERSION

Version 1.06

=cut

our $VERSION = '1.06';

=head1 SYNOPSIS

File::Next is a lightweight, taint-safe file-finding module.
It's lightweight and has no non-core prerequisites.

    use File::Next;

    my $files = File::Next::files( '/tmp' );

    while ( defined ( my $file = $files->() ) ) {
        # do something...
    }

=head1 OPERATIONAL THEORY

The two major functions, I<files()> and I<dirs()>, return an iterator
that will walk through a directory tree.  The simplest use case is:

    use File::Next;

    my $iter = File::Next::files( '/tmp' );

    while ( defined ( my $file = $iter->() ) ) {
        print $file, "\n";
    }

    # Prints...
    /tmp/foo.txt
    /tmp/bar.pl
    /tmp/baz/1
    /tmp/baz/2.txt
    /tmp/baz/wango/tango/purple.txt

Note that only files are returned by C<files()>'s iterator.
Directories are ignored.

In list context, the iterator returns a list containing I<$dir>,
I<$file> and I<$fullpath>, where I<$fullpath> is what would get
returned in scalar context.

The first parameter to any of the iterator factory functions may
be a hashref of options.

=head1 ITERATORS

For the three iterators, the \%options are optional.

=head2 files( [ \%options, ] @starting_points )

Returns an iterator that walks directories starting with the items
in I<@starting_points>.  Each call to the iterator returns another
regular file.

=head2 dirs( [ \%options, ] @starting_points )

Returns an iterator that walks directories starting with the items
in I<@starting_points>.  Each call to the iterator returns another
directory.

=head2 everything( [ \%options, ] @starting_points )

Returns an iterator that walks directories starting with the items
in I<@starting_points>.  Each call to the iterator returns another
file, whether it's a regular file, directory, symlink, socket, or
whatever.

=head1 SUPPORT FUNCTIONS

=head2 sort_standard( $a, $b )

A sort function for passing as a C<sort_files> option:

    my $iter = File::Next::files( {
        sort_files => \&File::Next::sort_standard,
    }, 't/swamp' );

This function is the default, so the code above is identical to:

    my $iter = File::Next::files( {
        sort_files => 1,
    }, 't/swamp' );

=head2 sort_reverse( $a, $b )

Same as C<sort_standard>, but in reverse.

=head2 reslash( $path )

Takes a path with all forward slashes and rebuilds it with whatever
is appropriate for the platform.  For example 'foo/bar/bat' will
become 'foo\bar\bat' on Windows.

This is really just a convenience function.  I'd make it private,
but F<ack> wants it, too.

=cut

=head1 CONSTRUCTOR PARAMETERS

=head2 file_filter -> \&file_filter

The file_filter lets you check to see if it's really a file you
want to get back.  If the file_filter returns a true value, the
file will be returned; if false, it will be skipped.

The file_filter function takes no arguments but rather does its work through
a collection of variables.

=over 4

=item * C<$_> is the current filename within that directory

=item * C<$File::Next::dir> is the current directory name

=item * C<$File::Next::name> is the complete pathname to the file

=back

These are analogous to the same variables in L<File::Find>.

    my $iter = File::Next::files( { file_filter => sub { /\.txt$/ } }, '/tmp' );

By default, the I<file_filter> is C<sub {1}>, or "all files".

This filter has no effect if your iterator is only returning directories.

=head2 descend_filter => \&descend_filter

The descend_filter lets you check to see if the iterator should
descend into a given directory.  Maybe you want to skip F<CVS> and
F<.svn> directories.

    my $descend_filter = sub { $_ ne "CVS" && $_ ne ".svn" }

The descend_filter function takes no arguments but rather does its work through
a collection of variables.

=over 4

=item * C<$_> is the current filename of the directory

=item * C<$File::Next::dir> is the complete directory name

=back

The descend filter is NOT applied to any directory names specified
in as I<@starting_points> in the constructor.  For example,

    my $iter = File::Next::files( { descend_filter => sub{0} }, '/tmp' );

always descends into I</tmp>, as you would expect.

By default, the I<descend_filter> is C<sub {1}>, or "always descend".

=head2 error_handler => \&error_handler

If I<error_handler> is set, then any errors will be sent through
it.  By default, this value is C<CORE::die>.

=head2 sort_files => [ 0 | 1 | \&sort_sub]

If you want files sorted, pass in some true value, as in
C<< sort_files => 1 >>.

If you want a special sort order, pass in a sort function like
C<< sort_files => sub { $a->[1] cmp $b->[1] } >>.
Note that the parms passed in to the sub are arrayrefs, where $a->[0]
is the directory name, $a->[1] is the file name and $a->[2] is the
full path.  Typically you're going to be sorting on $a->[2].

=head2 follow_symlinks => [ 0 | 1 ]

If set to false, the iterator will ignore any files and directories
that are actually symlinks.  This has no effect on non-Unixy systems
such as Windows.  By default, this is true.

Note that this filter does not apply to any of the I<@starting_points>
passed in to the constructor.

You should not set C<< follow_symlinks => 0 >> unless you specifically
need that behavior.  Setting C<< follow_symlinks => 0 >> can be a
speed hit, because File::Next must check to see if the file or
directory you're about to follow is actually a symlink.

=cut

use File::Spec ();

## no critic (ProhibitPackageVars)
our $name; # name of the current file
our $dir;  # dir of the current file

our %files_defaults;
our %skip_dirs;

BEGIN {
    %files_defaults = (
        file_filter     => undef,
        descend_filter  => undef,
        error_handler   => sub { CORE::die @_ },
        sort_files      => undef,
        follow_symlinks => 1,
    );
    %skip_dirs = map {($_,1)} (File::Spec->curdir, File::Spec->updir);
}


sub files {
    ($_[0] eq __PACKAGE__) && die 'File::Next::files must not be invoked as File::Next->files';

    my ($parms,@queue) = _setup( \%files_defaults, @_ );
    my $filter = $parms->{file_filter};

    return sub {
        while (@queue) {
            my ($dir,$file,$fullpath) = splice( @queue, 0, 3 );
            if ( -f $fullpath ) {
                if ( $filter ) {
                    local $_ = $file;
                    local $File::Next::dir = $dir;
                    local $File::Next::name = $fullpath;
                    next if not $filter->();
                }
                return wantarray ? ($dir,$file,$fullpath) : $fullpath;
            }
            elsif ( -d _ ) {
                unshift( @queue, _candidate_files( $parms, $fullpath ) );
            }
        } # while

        return;
    }; # iterator
}


sub dirs {
    ($_[0] eq __PACKAGE__) && die 'File::Next::dirs must not be invoked as File::Next->dirs';

    my ($parms,@queue) = _setup( \%files_defaults, @_ );

    return sub {
        while (@queue) {
            my (undef,undef,$fullpath) = splice( @queue, 0, 3 );
            if ( -d $fullpath ) {
                unshift( @queue, _candidate_files( $parms, $fullpath ) );
                return $fullpath;
            }
        } # while

        return;
    }; # iterator
}


sub everything {
    ($_[0] eq __PACKAGE__) && die 'File::Next::everything must not be invoked as File::Next->everything';

    my ($parms,@queue) = _setup( \%files_defaults, @_ );
    my $filter = $parms->{file_filter};

    return sub {
        while (@queue) {
            my ($dir,$file,$fullpath) = splice( @queue, 0, 3 );
            if ( -d $fullpath ) {
                unshift( @queue, _candidate_files( $parms, $fullpath ) );
            }
            if ( $filter ) {
                local $_ = $file;
                local $File::Next::dir = $dir;
                local $File::Next::name = $fullpath;
                next if not $filter->();
            }
            return wantarray ? ($dir,$file,$fullpath) : $fullpath;
        } # while

        return;
    }; # iterator
}

sub sort_standard($$)   { return $_[0]->[1] cmp $_[1]->[1] } ## no critic (ProhibitSubroutinePrototypes)
sub sort_reverse($$)    { return $_[1]->[1] cmp $_[0]->[1] } ## no critic (ProhibitSubroutinePrototypes)

sub reslash {
    my $path = shift;

    my @parts = split( /\//, $path );

    return $path if @parts < 2;

    return File::Spec->catfile( @parts );
}


=head1 PRIVATE FUNCTIONS

=head2 _setup( $default_parms, @whatever_was_passed_to_files() )

Handles all the scut-work for setting up the parms passed in.

Returns a hashref of operational options, combined between
I<$passed_parms> and I<$defaults>, plus the queue.

The queue prep stuff takes the strings in I<@starting_points> and
puts them in the format that queue needs.

The C<@queue> that gets passed around is an array that has three
elements for each of the entries in the queue: $dir, $file and
$fullpath.  Items must be pushed and popped off the queue three at
a time (spliced, really).

=cut

sub _setup {
    my $defaults = shift;
    my $passed_parms = ref $_[0] eq 'HASH' ? {%{+shift}} : {}; # copy parm hash

    my %passed_parms = %{$passed_parms};

    my $parms = {};
    for my $key ( keys %{$defaults} ) {
        $parms->{$key} =
            exists $passed_parms{$key}
                ? delete $passed_parms{$key}
                : $defaults->{$key};
    }

    # Any leftover keys are bogus
    for my $badkey ( keys %passed_parms ) {
        my $sub = (caller(1))[3];
        $parms->{error_handler}->( "Invalid option passed to $sub(): $badkey" );
    }

    # If it's not a code ref, assume standard sort
    if ( $parms->{sort_files} && ( ref($parms->{sort_files}) ne 'CODE' ) ) {
        $parms->{sort_files} = \&sort_standard;
    }
    my @queue;

    for ( @_ ) {
        my $start = reslash( $_ );
        if (-d $start) {
            push @queue, ($start,undef,$start);
        }
        else {
            push @queue, (undef,$start,$start);
        }
    }

    return ($parms,@queue);
}

=head2 _candidate_files( $parms, $dir )

Pulls out the files/dirs that might be worth looking into in I<$dir>.
If I<$dir> is the empty string, then search the current directory.

I<$parms> is the hashref of parms passed into File::Next constructor.

=cut

sub _candidate_files {
    my $parms = shift;
    my $dir = shift;

    my $dh;
    if ( !opendir $dh, $dir ) {
        $parms->{error_handler}->( "$dir: $!" );
        return;
    }

    my @newfiles;
    my $descend_filter = $parms->{descend_filter};
    my $follow_symlinks = $parms->{follow_symlinks};
    my $sort_sub = $parms->{sort_files};

    for my $file ( grep { !exists $skip_dirs{$_} } readdir $dh ) {
        my $has_stat;

        # Only do directory checking if we have a descend_filter
        my $fullpath = File::Spec->catdir( $dir, $file );
        if ( !$follow_symlinks ) {
            next if -l $fullpath;
            $has_stat = 1;
        }

        if ( $descend_filter ) {
            if ( $has_stat ? (-d _) : (-d $fullpath) ) {
                local $File::Next::dir = $fullpath;
                local $_ = $file;
                next if not $descend_filter->();
            }
        }
        if ( $sort_sub ) {
            push( @newfiles, [ $dir, $file, $fullpath ] );
        }
        else {
            push( @newfiles, $dir, $file, $fullpath );
        }
    }
    closedir $dh;

    if ( $sort_sub ) {
        return map { @{$_} } sort $sort_sub @newfiles;
    }

    return @newfiles;
}

=head1 SPEED TWEAKS

=over 4

=item * Don't set C<< follow_symlinks => 0 >> unless you need it.

=back

=head1 AUTHOR

Andy Lester, C<< <andy at petdance.com> >>

=head1 BUGS

Please report any bugs or feature requests to
L<http://github.com/petdance/file-next/issues>.

Note that File::Next does NOT use L<http://rt.cpan.org> for bug tracking.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc File::Next

You can also look for information at:

=over 4

=item * File::Next's bug queue

L<http://github.com/petdance/file-next/issues>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/File-Next>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/File-Next>

=item * Search CPAN

L<http://search.cpan.org/dist/File-Next>

=item * Source code repository

L<http://github.com/petdance/file-next/tree/master>

=back

=head1 ACKNOWLEDGEMENTS

All file-finding in this module is adapted from Mark Jason Dominus'
marvelous I<Higher Order Perl>, page 126.

=head1 COPYRIGHT & LICENSE

Copyright 2005-2009 Andy Lester.

This program is free software; you can redistribute it and/or modify
it under the terms of either:

=over 4

=item * the GNU General Public License as published by the Free
Software Foundation; either version 1, or (at your option) any later
version, or

=item * the Artistic License version 2.0.

=back

=cut

1; # End of File::Next
