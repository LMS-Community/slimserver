package DBI::ProfileDumper::Apache;

=head1 NAME

DBI::ProfileDumper::Apache - capture DBI profiling data from Apache/mod_perl

=head1 SYNOPSIS

Add this line to your F<httpd.conf>:

  PerlSetEnv DBI_PROFILE DBI::ProfileDumper::Apache

Then restart your server.  Access the code you wish to test using a
web browser, then shutdown your server.  This will create a set of
F<dbi.prof.*> files in your Apache log directory.  Get a profiling
report with L<dbiprof|dbiprof>:

  dbiprof /usr/local/apache/logs/dbi.prof.*

When you're ready to perform another profiling run, delete the old
files

  rm /usr/local/apache/logs/dbi.prof.*

and start again.

=head1 DESCRIPTION

This module interfaces DBI::ProfileDumper to Apache/mod_perl.  Using
this module you can collect profiling data from mod_perl applications.
It works by creating a DBI::ProfileDumper data file for each Apache
process.  These files are created in your Apache log directory.  You
can then use dbiprof to analyze the profile files.

=head1 USAGE

=head2 LOADING THE MODULE

The easiest way to use this module is just to set the DBI_PROFILE
environment variable in your F<httpd.conf>:

  PerlSetEnv DBI_PROFILE DBI::ProfileDumper::Apache

If you want to use one of DBI::Profile's other Path settings, you can
use a string like:

  PerlSetEnv DBI_PROFILE 2/DBI::ProfileDumper::Apache

It's also possible to use this module by setting the Profile attribute
of any DBI handle:

  $dbh->{Profile} = "DBI::ProfileDumper::Apache";

See L<DBI::ProfileDumper> for more possibilities.

=head2 GATHERING PROFILE DATA

Once you have the module loaded, use your application as you normally
would.  Stop the webserver when your tests are complete.  Profile data
files will be produced when Apache exits and you'll see something like
this in your error_log:

  DBI::ProfileDumper::Apache writing to /usr/local/apache/logs/dbi.prof.2619

Now you can use dbiprof to examine the data:

  dbiprof /usr/local/apache/logs/dbi.prof.*

By passing dbiprof a list of all generated files, dbiprof will
automatically merge them into one result set.  You can also pass
dbiprof sorting and querying options, see L<dbiprof> for details.

=head2 CLEANING UP

Once you've made some code changes, you're ready to start again.
First, delete the old profile data files:

  rm /usr/local/apache/logs/dbi.prof.* 

Then restart your server and get back to work.

=head1 MEMORY USAGE

DBI::Profile can use a lot of memory for very active applications.  It
collects profiling data in memory for each distinct query your
application runs.  You can avoid this problem with a call like this:

  $dbh->{Profile}->flush_to_disk() if $dbh->{Profile};

Calling C<flush_to_disk()> will clear out the profile data and write
it to disk.  Put this someplace where it will run on every request,
like a CleanupHandler, and your memory troubles should go away.  Well,
at least the ones caused by DBI::Profile anyway.

=head1 AUTHOR

Sam Tregar <sam@tregar.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2002 Sam Tregar

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl 5 itself.

=cut

use vars qw($VERSION @ISA);
$VERSION = "1.0";
@ISA = qw(DBI::ProfileDumper);
use DBI::ProfileDumper;
use Apache;
use File::Spec;

# Override flush_to_disk() to setup File just in time for output.
# Overriding new() would work unless the user creates a DBI handle
# during server startup, in which case all the children would try to
# write to the same file.
sub flush_to_disk {
    my $self = shift;
    
    # setup File per process
    my $path = Apache->server_root_relative("logs/");
    my $old_file = $self->{File};
    $self->{File} = File::Spec->catfile($path, "$old_file.$$");

    # write out to disk
    print STDERR "DBI::ProfileDumper::Apache writing to $self->{File}\n";
    $self->SUPER::flush_to_disk(@_);
   
    # reset File to previous setting
    $self->{File} = $old_file;    
}

1;
