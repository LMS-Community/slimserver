package DBI::ProfileDumper;
use strict;

=head1 NAME

DBI::ProfileDumper - profile DBI usage and output data to a file

=head1 SYNOPSIS

To profile an existing program using DBI::ProfileDumper, set the
DBI_PROFILE environment variable and run your program as usual.  For
example, using bash:

  DBI_PROFILE=DBI::ProfileDumper program.pl

Then analyze the generated file (F<dbi.prof>) with L<dbiprof|dbiprof>:

  dbiprof

You can also activate DBI::ProfileDumper from within your code:

  use DBI;

  # profile with default path (2) and output file (dbi.prof)
  $dbh->{Profile} = "DBI::ProfileDumper";

  # same thing, spelled out
  $dbh->{Profile} = "2/DBI::ProfileDumper/File/dbi.prof";

  # another way to say it
  use DBI::Profile qw(DBIprofile_Statement);
  $dbh->{Profile} = DBI::ProfileDumper->new(
                        Path => [ DBIprofile_Statement ]
                        File => 'dbi.prof' );

  # using a custom path
  $dbh->{Profile} = DBI::ProfileDumper->new( Path => [ "foo", "bar" ],
                                             File => 'dbi.prof' );


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

  $dbh->{Profile} = "DBI::ProfileDumper";

This will write out profile data by statement into a file called
F<dbi.prof>.  If you want to modify either of these properties, you
can construct the DBI::ProfileDumper object yourself:

  use DBI::Profile qw(DBIprofile_Statement);
  $dbh->{Profile} = DBI::ProfileDumper->new(
                        Path => [ DBIprofile_Statement ]
                        File => 'dbi.prof' );

The C<Path> option takes the same values as in
L<DBI::Profile>.  The C<File> option gives the name of the
file where results will be collected.  If it already exists it will be
overwritten.

You can also activate this module by setting the DBI_PROFILE
environment variable:

  $ENV{DBI_PROFILE} = "DBI::ProfileDumper";

This will cause all DBI handles to share the same profiling object.

=head1 METHODS

The following methods are available to be called using the profile
object.  You can get access to the profile object from the Profile key
in any DBI handle:

  my $profile = $dbh->{Profile};

=over 4

=item $profile->flush_to_disk()

Flushes all collected profile data to disk and empties the Data hash.
This method may be called multiple times during a program run.

=item $profile->empty()

Clears the Data hash without writing to disk.

=back

=head1 DATA FORMAT

The data format written by DBI::ProfileDumper starts with a header
containing the version number of the module used to generate it.  Then
a block of variable declarations describes the profile.  After two
newlines, the profile data forms the body of the file.  For example:

  DBI::ProfileDumper 1.0
  Path = [ DBIprofile_Statement, DBIprofile_MethodName ]
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
use vars qw(@ISA $VERSION);
@ISA = ("DBI::Profile");
$VERSION = "1.0";

use Carp qw(croak);
use Symbol;

# validate params and setup default
sub new {
    my $pkg = shift;
    my $self = $pkg->SUPER::new(@_);

    # File defaults to dbi.prof
    $self->{File} = "dbi.prof" unless exists $self->{File};

    return $self;
}

# flush available data to disk
sub flush_to_disk {
    my $self = shift;
    my $data = $self->{Data};

    my $fh = gensym;
    if ($self->{_wrote_header}) {
        # append more data to the file
        open($fh, ">>$self->{File}") 
          or croak("Unable to open '$self->{File}' for profile output: $!");
    } else {
        # create new file and write the header
        open($fh, ">$self->{File}") 
          or croak("Unable to open '$self->{File}' for profile output: $!");
        $self->write_header($fh);
        $self->{_wrote_header} = 1;
    }

    $self->write_data($fh, $self->{Data}, 1);

    close($fh) or croak("Unable to close '$self->{File}': $!");

    $self->empty();
}

# empty out profile data
sub empty {
    shift->{Data} = {};
}

# write header to a filehandle
sub write_header {
    my ($self, $fh) = @_;

    # module name and version number
    print $fh ref($self), " ", $self->VERSION, "\n";

    # print out Path
    my @path_words;
    if ($self->{Path}) {
        foreach (@{$self->{Path}}) {
            if ($_ eq DBI::Profile::DBIprofile_Statement) {
                push @path_words, "DBIprofile_Statement";
            } elsif ($_ eq DBI::Profile::DBIprofile_MethodName) {
                push @path_words, "DBIprofile_MethodName";
            } elsif ($_ eq DBI::Profile::DBIprofile_MethodClass) {
                push @path_words, "DBIprofile_MethodClass";
            } else {
                push @path_words, $_;
            }
        }
    }
    print $fh "Path = [ ", join(', ', @path_words), " ]\n";

    # print out $0 and @ARGV
    print $fh "Program = $0";
    print $fh " ", join(", ", @ARGV) if @ARGV;
    print $fh "\n";

    # all done
    print $fh "\n";
}

# write data in the proscribed format
sub write_data {
    my ($self, $fh, $data, $level) = @_;

    # produce an empty profile for invalid $data
    return unless $data and UNIVERSAL::isa($data,'HASH');
    
    while (my ($key, $value) = each(%$data)) {
        # output a key
        print $fh "+ ", $level, " ", quote_key($key), "\n";
        if (UNIVERSAL::isa($value,'ARRAY')) {
            # output a data set for a leaf node
            printf $fh "= %4d %.6f %.6f %.6f %.6f %.6f %.6f\n", @$value;
        } else {
            # recurse through keys - this could be rewritten to use a
            # stack for some small performance gain
            $self->write_data($fh, $value, $level + 1);
        }
    }
}

# quote a key for output
sub quote_key {
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
