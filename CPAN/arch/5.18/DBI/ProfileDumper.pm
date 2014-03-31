package DBI::ProfileDumper;
use strict;

=head1 NAME

DBI::ProfileDumper - profile DBI usage and output data to a file

=head1 SYNOPSIS

To profile an existing program using DBI::ProfileDumper, set the
DBI_PROFILE environment variable and run your program as usual.  For
example, using bash:

  DBI_PROFILE=2/DBI::ProfileDumper program.pl

Then analyze the generated file (F<dbi.prof>) with L<dbiprof|dbiprof>:

  dbiprof

You can also activate DBI::ProfileDumper from within your code:

  use DBI;

  # profile with default path (2) and output file (dbi.prof)
  $dbh->{Profile} = "!Statement/DBI::ProfileDumper";

  # same thing, spelled out
  $dbh->{Profile} = "!Statement/DBI::ProfileDumper/File:dbi.prof";

  # another way to say it
  use DBI::ProfileDumper;
  $dbh->{Profile} = DBI::ProfileDumper->new(
                        Path => [ '!Statement' ],
                        File => 'dbi.prof' );

  # using a custom path
  $dbh->{Profile} = DBI::ProfileDumper->new(
      Path => [ "foo", "bar" ],
      File => 'dbi.prof',
  );


=head1 DESCRIPTION

DBI::ProfileDumper is a subclass of L<DBI::Profile|DBI::Profile> which
dumps profile data to disk instead of printing a summary to your
screen.  You can then use L<dbiprof|dbiprof> to analyze the data in
a number of interesting ways, or you can roll your own analysis using
L<DBI::ProfileData|DBI::ProfileData>.

B<NOTE:> For Apache/mod_perl applications, use
L<DBI::ProfileDumper::Apache|DBI::ProfileDumper::Apache>.

=head1 USAGE

One way to use this module is just to enable it in your C<$dbh>:

  $dbh->{Profile} = "1/DBI::ProfileDumper";

This will write out profile data by statement into a file called
F<dbi.prof>.  If you want to modify either of these properties, you
can construct the DBI::ProfileDumper object yourself:

  use DBI::ProfileDumper;
  $dbh->{Profile} = DBI::ProfileDumper->new(
      Path => [ '!Statement' ],
      File => 'dbi.prof'
  );

The C<Path> option takes the same values as in
L<DBI::Profile>.  The C<File> option gives the name of the
file where results will be collected.  If it already exists it will be
overwritten.

You can also activate this module by setting the DBI_PROFILE
environment variable:

  $ENV{DBI_PROFILE} = "!Statement/DBI::ProfileDumper";

This will cause all DBI handles to share the same profiling object.

=head1 METHODS

The following methods are available to be called using the profile
object.  You can get access to the profile object from the Profile key
in any DBI handle:

  my $profile = $dbh->{Profile};

=head2 flush_to_disk

  $profile->flush_to_disk()

Flushes all collected profile data to disk and empties the Data hash.  Returns
the filename written to.  If no profile data has been collected then the file is
not written and flush_to_disk() returns undef.

The file is locked while it's being written. A process 'consuming' the files
while they're being written to, should rename the file first, then lock it,
then read it, then close and delete it. The C<DeleteFiles> option to
L<DBI::ProfileData> does the right thing.

This method may be called multiple times during a program run.

=head2 empty

  $profile->empty()

Clears the Data hash without writing to disk.

=head2 filename

  $filename = $profile->filename();

Get or set the filename.

The filename can be specified as a CODE reference, in which case the referenced
code should return the filename to be used. The code will be called with the
profile object as its first argument.

=head1 DATA FORMAT

The data format written by DBI::ProfileDumper starts with a header
containing the version number of the module used to generate it.  Then
a block of variable declarations describes the profile.  After two
newlines, the profile data forms the body of the file.  For example:

  DBI::ProfileDumper 2.003762
  Path = [ '!Statement', '!MethodName' ]
  Program = t/42profile_data.t

  + 1 SELECT name FROM users WHERE id = ?
  + 2 prepare
  = 1 0.0312958955764771 0.000490069389343262 0.000176072120666504 0.00140702724456787 1023115819.83019 1023115819.86576
  + 2 execute
  1 0.0312958955764771 0.000490069389343262 0.000176072120666504 0.00140702724456787 1023115819.83019 1023115819.86576
  + 2 fetchrow_hashref
  = 1 0.0312958955764771 0.000490069389343262 0.000176072120666504 0.00140702724456787 1023115819.83019 1023115819.86576
  + 1 UPDATE users SET name = ? WHERE id = ?
  + 2 prepare
  = 1 0.0312958955764771 0.000490069389343262 0.000176072120666504 0.00140702724456787 1023115819.83019 1023115819.86576
  + 2 execute
  = 1 0.0312958955764771 0.000490069389343262 0.000176072120666504 0.00140702724456787 1023115819.83019 1023115819.86576

The lines beginning with C<+> signs signify keys.  The number after
the C<+> sign shows the nesting level of the key.  Lines beginning
with C<=> are the actual profile data, in the same order as
in DBI::Profile.

Note that the same path may be present multiple times in the data file
since C<format()> may be called more than once.  When read by
DBI::ProfileData the data points will be merged to produce a single
data set for each distinct path.

The key strings are transformed in three ways.  First, all backslashes
are doubled.  Then all newlines and carriage-returns are transformed
into C<\n> and C<\r> respectively.  Finally, any NULL bytes (C<\0>)
are entirely removed.  When DBI::ProfileData reads the file the first
two transformations will be reversed, but NULL bytes will not be
restored.

=head1 AUTHOR

Sam Tregar <sam@tregar.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2002 Sam Tregar

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl 5 itself.

=cut

# inherit from DBI::Profile
use DBI::Profile;

our @ISA = ("DBI::Profile");

our $VERSION = "2.015325";

use Carp qw(croak);
use Fcntl qw(:flock);
use Symbol;

my $HAS_FLOCK = (defined $ENV{DBI_PROFILE_FLOCK})
    ? $ENV{DBI_PROFILE_FLOCK}
    : do { local $@; eval { flock STDOUT, 0; 1 } };

my $program_header;


# validate params and setup default
sub new {
    my $pkg = shift;
    my $self = $pkg->SUPER::new(
        LockFile => $HAS_FLOCK,
        @_,
    );

    # provide a default filename
    $self->filename("dbi.prof") unless $self->filename;

    DBI->trace_msg("$self: @{[ %$self ]}\n",0)
        if $self->{Trace} && $self->{Trace} >= 2;

    return $self;
}


# get/set filename to use
sub filename {
    my $self = shift;
    $self->{File} = shift if @_;
    my $filename = $self->{File};
    $filename = $filename->($self) if ref($filename) eq 'CODE';
    return $filename;
}


# flush available data to disk
sub flush_to_disk {
    my $self = shift;
    my $class = ref $self;
    my $filename = $self->filename;
    my $data = $self->{Data};

    if (1) { # make an option
        if (not $data or ref $data eq 'HASH' && !%$data) {
            DBI->trace_msg("flush_to_disk skipped for empty profile\n",0) if $self->{Trace};
            return undef;
        }
    }

    my $fh = gensym;
    if (($self->{_wrote_header}||'') eq $filename) {
        # append more data to the file
        # XXX assumes that Path hasn't changed
        open($fh, ">>", $filename)
          or croak("Unable to open '$filename' for $class output: $!");
    } else {
        # create new file (or overwrite existing)
        if (-f $filename) {
            my $bak = $filename.'.prev';
            unlink($bak);
            rename($filename, $bak)
                or warn "Error renaming $filename to $bak: $!\n";
        }
        open($fh, ">", $filename)
          or croak("Unable to open '$filename' for $class output: $!");
    }
    # lock the file (before checking size and writing the header)
    flock($fh, LOCK_EX) if $self->{LockFile};
    # write header if file is empty - typically because we just opened it
    # in '>' mode, or perhaps we used '>>' but the file had been truncated externally.
    if (-s $fh == 0) {
        DBI->trace_msg("flush_to_disk wrote header to $filename\n",0) if $self->{Trace};
        $self->write_header($fh);
        $self->{_wrote_header} = $filename;
    }

    my $lines = $self->write_data($fh, $self->{Data}, 1);
    DBI->trace_msg("flush_to_disk wrote $lines lines to $filename\n",0) if $self->{Trace};

    close($fh)  # unlocks the file
        or croak("Error closing '$filename': $!");

    $self->empty();


    return $filename;
}


# write header to a filehandle
sub write_header {
    my ($self, $fh) = @_;

    # isolate us against globals which effect print
    local($\, $,);

    # $self->VERSION can return undef during global destruction
    my $version = $self->VERSION || $VERSION;

    # module name and version number
    print $fh ref($self)." $version\n";

    # print out Path (may contain CODE refs etc)
    my @path_words = map { escape_key($_) } @{ $self->{Path} || [] };
    print $fh "Path = [ ", join(', ', @path_words), " ]\n";

    # print out $0 and @ARGV
    if (!$program_header) {
        # XXX should really quote as well as escape
        $program_header = "Program = "
            . join(" ", map { escape_key($_) } $0, @ARGV)
            . "\n";
    }
    print $fh $program_header;

    # all done
    print $fh "\n";
}


# write data in the proscribed format
sub write_data {
    my ($self, $fh, $data, $level) = @_;

    # XXX it's valid for $data to be an ARRAY ref, i.e., Path is empty.
    # produce an empty profile for invalid $data
    return 0 unless $data and UNIVERSAL::isa($data,'HASH');

    # isolate us against globals which affect print
    local ($\, $,);

    my $lines = 0;
    while (my ($key, $value) = each(%$data)) {
        # output a key
        print $fh "+ $level ". escape_key($key). "\n";
        if (UNIVERSAL::isa($value,'ARRAY')) {
            # output a data set for a leaf node
            print $fh "= ".join(' ', @$value)."\n";
            $lines += 1;
        } else {
            # recurse through keys - this could be rewritten to use a
            # stack for some small performance gain
            $lines += $self->write_data($fh, $value, $level + 1);
        }
    }
    return $lines;
}


# escape a key for output
sub escape_key {
    my $key = shift;
    $key =~ s!\\!\\\\!g;
    $key =~ s!\n!\\n!g;
    $key =~ s!\r!\\r!g;
    $key =~ s!\0!!g;
    return $key;
}


# flush data to disk when profile object goes out of scope
sub on_destroy {
    shift->flush_to_disk();
}

1;
