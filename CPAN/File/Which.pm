package File::Which;

use strict;

require Exporter;

@File::Which::ISA       = qw(Exporter);

@File::Which::EXPORT    = qw(which);
@File::Which::EXPORT_OK = qw(where);

$File::Which::VERSION = '0.05';

use File::Spec;

my $Is_VMS    = ($^O eq 'VMS');
my $Is_MacOS  = ($^O eq 'MacOS');
my $Is_DOSish = (($^O eq 'MSWin32') or
                ($^O eq 'dos')     or
                ($^O eq 'os2'));

# For Win32 systems, stores the extensions used for
# executable files
# For others, the empty string is used
# because 'perl' . '' eq 'perl' => easier
my @path_ext = ('');
if ($Is_DOSish) {
    if ($ENV{PATHEXT} and $Is_DOSish) {    # WinNT. PATHEXT might be set on Cygwin, but not used.
        push @path_ext, split ';', $ENV{PATHEXT};
    }
    else {
        push @path_ext, qw(.com .exe .bat); # Win9X or other: doesn't have PATHEXT, so needs hardcoded.
    }
}
elsif ($Is_VMS) { 
    push @path_ext, qw(.exe .com);
}

sub which {
    my ($exec) = @_;

    return undef unless $exec;

    my $all = wantarray;
    my @results = ();
    
    # check for aliases first
    if ($Is_VMS) {
        my $symbol = `SHOW SYMBOL $exec`;
        chomp($symbol);
        if (!$?) {
            return $symbol unless $all;
            push @results, $symbol;
        }
    }
    if ($Is_MacOS) {
        my @aliases = split /\,/, $ENV{Aliases};
        foreach my $alias (@aliases) {
            # This has not been tested!!
            # PPT which says MPW-Perl cannot resolve `Alias $alias`,
            # let's just hope it's fixed
            if (lc($alias) eq lc($exec)) {
                chomp(my $file = `Alias $alias`);
                last unless $file;  # if it failed, just go on the normal way
                return $file unless $all;
                push @results, $file;
                # we can stop this loop as if it finds more aliases matching,
                # it'll just be the same result anyway
                last;
            }
        }
    }

    my @path = File::Spec->path();
    unshift @path, File::Spec->curdir if $Is_DOSish or $Is_VMS or $Is_MacOS;

    for my $base (map { File::Spec->catfile($_, $exec) } @path) {
       for my $ext (@path_ext) {
            my $file = $base.$ext;
# print STDERR "$file\n";

            if ((-x $file or    # executable, normal case
                 ($Is_MacOS ||  # MacOS doesn't mark as executable so we check -e
                  ($Is_DOSish and grep { $file =~ /$_$/i } @path_ext[1..$#path_ext])
                                # DOSish systems don't pass -x on non-exe/bat/com files.
                                # so we check -e. However, we don't want to pass -e on files
                                # that aren't in PATHEXT, like README.
                 and -e _)
                ) and !-d _)
            {                   # and finally, we don't want dirs to pass (as they are -x)

# print STDERR "-x: ", -x $file, " -e: ", -e _, " -d: ", -d _, "\n";

                    return $file unless $all;
                    push @results, $file;       # Make list to return later
            }
        }
    }
    
    if($all) {
        return @results;
    } else {
        return undef;
    }
}

sub where {
    my @res = which($_[0]); # force wantarray
    return @res;
}

1;
__END__

=head1 NAME

File::Which - Portable implementation of the `which' utility

=head1 SYNOPSIS

  use File::Which;                  # exports which()
  use File::Which qw(which where);  # exports which() and where()
  
  my $exe_path = which('perldoc');
  
  my @paths = where('perl');
  - Or -
  my @paths = which('perl'); # an array forces search for all of them

=head1 DESCRIPTION

C<File::Which> was created to be able to get the paths to executable programs
on systems under which the `which' program wasn't implemented in the shell.

C<File::Which> searches the directories of the user's C<PATH> (as returned by
C<File::Spec-E<gt>path()>), looking for executable files having the name specified
as a parameter to C<which()>. Under Win32 systems, which do not have a notion of
directly executable files, but uses special extensions such as C<.exe> and
C<.bat> to identify them, C<File::Which> takes extra steps to assure that you
will find the correct file (so for example, you might be searching for C<perl>,
it'll try C<perl.exe>, C<perl.bat>, etc.)

=head1 Steps Used on Win32, DOS, OS2 and VMS

=head2 Windows NT

Windows NT has a special environment variable called C<PATHEXT>, which is used
by the shell to look for executable files. Usually, it will contain a list in
the form C<.EXE;.BAT;.COM;.JS;.VBS> etc. If C<File::Which> finds such an
environment variable, it parses the list and uses it as the different extensions.

=head2 Windows 9x and other ancient Win/DOS/OS2

This set of operating systems don't have the C<PATHEXT> variable, and usually
you will find executable files there with the extensions C<.exe>, C<.bat> and
(less likely) C<.com>. C<File::Which> uses this hardcoded list if it's running
under Win32 but does not find a C<PATHEXT> variable.

=head2 VMS

Same case as Windows 9x: uses C<.exe> and C<.com> (in that order).

=head1 Functions

=head2 which($short_exe_name)

Exported by default.

C<$short_exe_name> is the name used in the shell to call the program (for
example, C<perl>).

If it finds an executable with the name you specified, C<which()> will return
the absolute path leading to this executable (for example, C</usr/bin/perl> or
C<C:\Perl\Bin\perl.exe>).

If it does I<not> find the executable, it returns C<undef>.

If C<which()> is called in list context, it will return I<all> the
matches.

=head2 where($short_exe_name)

Not exported by default.

Same as C<which($short_exe_name)> in array context. Same as the
C<`where'> utility, will return an array containing all the path names
matching C<$short_exe_name>.


=head1 Bugs and Caveats

Not tested on VMS or MacOS, although there is platform specific code
for those. Anyone who haves a second would be very kind to send me a
report of how it went.

File::Spec adds the current directory to the front of PATH if on
Win32, VMS or MacOS. I have no knowledge of those so don't know if the
current directory is searced first or not. Could someone please tell
me?

=head1 Author

Per Einar Ellefsen, E<lt>per.einar (at) skynet.beE<gt>

Originated in I<modperl-2.0/lib/Apache/Build.pm>. Changed for use in DocSet
(for the mod_perl site) and Win32-awareness by me, with slight modifications
by Stas Bekman, then extracted to create C<File::Which>.

Version 0.04 had some significant platform-related changes, taken from
the Perl Power Tools C<`which'> implementation by Abigail with
enhancements from Peter Prymmer. See
http://www.perl.com/language/ppt/src/which/index.html for more
information.

=head1 License

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 See Also

L<File::Spec>, L<which(1)>, Perl Power Tools:
http://www.perl.com/language/ppt/index.html .

=cut
