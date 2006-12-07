package File::Next;

use strict;
use warnings;

=head1 NAME

File::Next - File-finding iterator

=head1 VERSION

Version 0.30

=cut

our $VERSION = '0.30';

=head1 SYNOPSIS

File::Next is a lightweight, taint-safe file-finding module.
It's lightweight and has no non-core prerequisites.

    use File::Next;

    my $files = File::Next->files( '/tmp' );

    while ( my $file = $files->() ) {
        # do something...
    }

=head1 OPERATIONAL THEORY

Each of the public functions in File::Next returns an iterator that
will walk through a directory tree.  The simplest use case is:

    use File::Next;

    my $iter = File::Next->files( '/tmp' );

    while ( my $file = $iter->() ) {
        print $file, "\n";
    }

    # Prints...
    /tmp/foo.txt
    /tmp/bar.pl
    /tmp/baz/1
    /tmp/baz/2.txt
    /tmp/baz/wango/tango/purple.txt

Note that only files are returned by C<files()>'s iterator.

The first parameter to any of the iterator factory functions may
be a hashref of parameters.

Note that the iterator will only return files, not directories.

=head1 PARAMETERS

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

    my $iter = File::Find::files( { file_filter => sub { /\.txt$/ } }, '/tmp' );

By default, the I<file_filter> is C<sub {1}>, or "all files".

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
in the constructor.  For example,

    my $iter = File::Find::files( { descend_filter => sub{0} }, '/tmp' );

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
is the directory name and $a->[1] is the file name.  Typically
you're going to be sorting on $a->[1].

=head1 FUNCTIONS

=head2 files( { \%parameters }, @starting points )

Returns an iterator that walks directories starting with the items
in I<@starting_points>.

All file-finding in this module is adapted from Mark Jason Dominus'
marvelous I<Higher Order Perl>, page 126.

=head2 sort_standard( $a, $b )

A sort function for passing as a C<sort_files> parameter:

    my $iter = File::Next::files( {
        sort_files => \&File::Next::sort_reverse
    }, 't/swamp' );

This function is the default, so the code above is identical to:

    my $iter = File::Next::files( {
        sort_files => \&File::Next::sort_reverse
    }, 't/swamp' );

=head2 sort_reverse( $a, $b )

Same as C<sort_standard>, but in reverse.

=cut

use File::Spec ();

## no critic (ProhibitPackageVars)
our $name; # name of the current file
our $dir;  # dir of the current file

my %files_defaults = (
    file_filter => sub{1},
    descend_filter => sub {1},
    error_handler => sub { CORE::die @_ },
    sort_files => undef,
);

sub files {
    my $passed_parms = ref $_[0] eq 'HASH' ? {%{+shift}} : {}; # copy parm hash
    my %passed_parms = %{$passed_parms};

    my $parms = {};
    for my $key ( keys %files_defaults ) {
        $parms->{$key} = delete( $passed_parms{$key} ) || $files_defaults{$key};
    }

    # Any leftover keys are bogus
    for my $badkey ( keys %passed_parms ) {
        $parms->{error_handler}->( "Invalid parameter passed to files(): $badkey" );
    }

    my @queue;
    for ( @_ ) {
        my $start = _reslash( $_ );
        if (-d $start) {
            push @queue, [$start,undef];
        }
        else {
            push @queue, [undef,$start];
        }
    }

    return sub {
        while (@queue) {
            my ($dir,$file) = @{shift @queue};

            my $fullpath =
                defined $dir
                    ? defined $file
                        ? File::Spec->catfile( $dir, $file )
                        : $dir
                    : $file;

            if (-d $fullpath) {
                unshift( @queue, _candidate_files( $parms, $fullpath ) );
            }
            elsif (-f $fullpath) {
                local $_ = $file;
                local $File::Next::dir = $dir;
                local $File::Next::name = $fullpath;
                if ( $parms->{file_filter}->() ) {
                    if (wantarray) {
                        return ($dir,$file);
                    }
                    else {
                        return $fullpath;
                    }
                }
            }
        } # while

        return;
    }; # iterator
}

sub _reslash {
    my $path = shift;

    my @parts = split( /\//, $path );

    return $path if @parts < 2;

    return File::Spec->catfile( @parts );
}

=for private _candidate_files( $parms, $dir )

Pulls out the files/dirs that might be worth looking into in I<$dir>.
If I<$dir> is the empty string, then search the current directory.
This is different than explicitly passing in a ".", because that
will get prepended to the path names.

I<$parms> is the hashref of parms passed into File::Next constructor.

=cut

my %ups;

sub _candidate_files {
    my $parms = shift;
    my $dir = shift;

    my $dh;
    if ( !opendir $dh, $dir ) {
        $parms->{error_handler}->( "$dir: $!" );
        return;
    }

    %ups or %ups = map {($_,1)} (File::Spec->curdir, File::Spec->updir);
    my @newfiles;
    while ( my $file = readdir $dh ) {
        next if $ups{$file};

        local $File::Next::dir = File::Spec->catdir( $dir, $file );
        if ( -d $File::Next::dir ) {
            local $_ = $file;
            next unless $parms->{descend_filter}->();
        }
        push( @newfiles, [$dir, $file] );
    }
    if ( my $sub = $parms->{sort_files} ) {
        $sub = \&sort_standard unless ref($sub) eq 'CODE';
        @newfiles = sort $sub @newfiles;
    }

    return @newfiles;
}

sub sort_standard($$)   { return $_[0]->[1] cmp $_[1]->[1] }; ## no critic (ProhibitSubroutinePrototypes)
sub sort_reverse($$)    { return $_[1]->[1] cmp $_[0]->[1] }; ## no critic (ProhibitSubroutinePrototypes)

=head1 AUTHOR

Andy Lester, C<< <andy at petdance.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-file-next at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=File-Next>.
I will be notified, and then you'll automatically be notified of
progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc File::Next

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/File-Next>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/File-Next>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=File-Next>

=item * Search CPAN

L<http://search.cpan.org/dist/File-Next>

=item * Subversion repository

L<https://file-next.googlecode.com/svn/trunk>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2006 Andy Lester, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of File::Next
