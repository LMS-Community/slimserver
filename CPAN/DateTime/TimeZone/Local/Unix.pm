package DateTime::TimeZone::Local::Unix;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '2.66';

use Cwd 3;
use Try::Tiny;

use parent 'DateTime::TimeZone::Local';

sub Methods {
    return qw(
        FromEnv
        FromEtcTimezone
        FromEtcLocaltime
        FromEtcTIMEZONE
        FromEtcSysconfigClock
        FromEtcDefaultInit
    );
}

sub EnvVars { return 'TZ' }

## no critic (Variables::ProhibitPackageVars)
our $EtcDir = '/etc';
## use critic

sub _EtcFile {
    shift;
    return File::Spec->catfile( $EtcDir, @_ );
}

sub FromEtcLocaltime {
    my $class = shift;

    my $lt_file = $class->_EtcFile('localtime');
    return unless -r $lt_file && -s _;

    my $real_name;
    if ( -l $lt_file ) {

        # The _Readlink sub exists so the test suite can mock it.
        $real_name = $class->_Readlink($lt_file);
    }

    $real_name ||= $class->_FindMatchingZoneinfoFile($lt_file);

    if ( defined $real_name ) {
        my ( undef, $dirs, $file ) = File::Spec->splitpath($real_name);

        my @parts = grep { defined && length } File::Spec->splitdir($dirs),
            $file;

        foreach my $x ( reverse 0 .. $#parts ) {
            my $name = (
                $x < $#parts
                ? join '/', @parts[ $x .. $#parts ]
                : $parts[$x]
            );

            my $tz = try {
                ## no critic (Variables::RequireInitializationForLocalVars)
                local $SIG{__DIE__};
                DateTime::TimeZone->new( name => $name );
            };

            return $tz if $tz;
        }
    }
}

sub _Readlink {
    my $link = $_[1];

    # Using abs_path will resolve multiple levels of link indirection,
    # whereas readlink just follows the link to the next target.
    return Cwd::abs_path($link);
}

## no critic (Variables::ProhibitPackageVars)
our $ZoneinfoDir = '/usr/share/zoneinfo';
## use critic

# for systems where /etc/localtime is a copy of a zoneinfo file
sub _FindMatchingZoneinfoFile {
    shift;
    my $file_to_match = shift;

    # For some reason, under at least macOS 10.13 High Sierra,
    # /usr/share/zoneinfo is a link to a link to a directory. And no, I didn't
    # stutter. This is fine, and it passes the -d below. But File::Find does
    # not understand a link to be a directory, so rather than incur the
    # overhead of telling File::Find::find() to follow symbolic links, we just
    # resolve it here.
    my $zone_info_dir = $ZoneinfoDir;
    $zone_info_dir = readlink $zone_info_dir while -l $zone_info_dir;

    return unless -d $zone_info_dir;

    require File::Basename;
    require File::Compare;
    require File::Find;

    my $size = -s $file_to_match;

    my $real_name;
    try {
        ## no critic (Variables::RequireInitializationForLocalVars)
        local $SIG{__DIE__};
        local $_;

        File::Find::find(
            {
                wanted => sub {
                    if (
                           !defined $real_name
                        && -f $_
                        && !-l $_
                        && $size == -s _

                        # This fixes RT 24026 - apparently such a
                        # file exists on FreeBSD and it can cause a
                        # false positive
                        && File::Basename::basename($_) ne 'posixrules'
                        && File::Compare::compare( $_, $file_to_match ) == 0
                    ) {
                        $real_name = $_;

                        # File::Find has no mechanism for bailing in the
                        # middle of a find.
                        die { found => 1 };
                    }
                },
                no_chdir => 1,
            },
            $zone_info_dir,
        );
    }
    catch {
        die $_ unless ref $_ && $_->{found};
    };

    return $real_name;
}

sub FromEtcTimezone {
    my $class = shift;

    my $tz_file = $class->_EtcFile('timezone');
    return unless -f $tz_file && -r _;

    open my $fh, '<', $tz_file
        or die "Cannot read $tz_file: $!";
    my $name = do { local $/ = undef; <$fh> };
    close $fh or die $!;

    $name =~ s/^\s+|\s+$//g;

    return unless $class->_IsValidName($name);

    return try {
        ## no critic (Variables::RequireInitializationForLocalVars)
        local $SIG{__DIE__};
        DateTime::TimeZone->new( name => $name );
    };
}

sub FromEtcTIMEZONE {
    my $class = shift;

    my $tz_file = $class->_EtcFile('TIMEZONE');
    return unless -f $tz_file && -r _;

    ## no critic (InputOutput::RequireBriefOpen)
    open my $fh, '<', $tz_file
        or die "Cannot read $tz_file: $!";

    my $name;
    while ( defined( $name = <$fh> ) ) {
        if ( $name =~ /\A\s*TZ\s*=\s*(\S+)/ ) {
            $name = $1;
            last;
        }
    }

    close $fh or die $!;

    return unless $class->_IsValidName($name);

    return try {
        ## no critic (Variables::RequireInitializationForLocalVars)
        local $SIG{__DIE__};
        DateTime::TimeZone->new( name => $name );
    };
}

# RedHat uses this
sub FromEtcSysconfigClock {
    my $class = shift;

    my $clock_file = $class->_EtcFile('sysconfig/clock');
    return unless -r $clock_file && -f _;

    my $name = $class->_ReadEtcSysconfigClock($clock_file);

    return unless $class->_IsValidName($name);

    return try {
        ## no critic (Variables::RequireInitializationForLocalVars)
        local $SIG{__DIE__};
        DateTime::TimeZone->new( name => $name );
    };
}

# this is a separate function so that it can be overridden in the test suite
sub _ReadEtcSysconfigClock {
    shift;
    my $clock_file = shift;

    open my $fh, '<', $clock_file
        or die "Cannot read $clock_file: $!";

    ## no critic (Variables::RequireInitializationForLocalVars)
    local $_;
    while (<$fh>) {
        return $1 if /^(?:TIME)?ZONE="([^"]+)"/;
    }

    close $fh or die $!;
}

sub FromEtcDefaultInit {
    my $class = shift;

    my $init_file = $class->_EtcFile('default/init');
    return unless -r $init_file && -f _;

    my $name = $class->_ReadEtcDefaultInit($init_file);

    return unless $class->_IsValidName($name);

    return try {
        ## no critic (Variables::RequireInitializationForLocalVars)
        local $SIG{__DIE__};
        DateTime::TimeZone->new( name => $name );
    };
}

# this is a separate function so that it can be overridden in the test
# suite
sub _ReadEtcDefaultInit {
    shift;
    my $init_file = shift;

    open my $fh, '<', $init_file
        or die "Cannot read $init_file: $!";

    ## no critic (Variables::RequireInitializationForLocalVars)
    local $_;
    while (<$fh>) {
        return $1 if /^TZ=(.+)/;
    }

    close $fh or die $!;
}

1;

# ABSTRACT: Determine the local system's time zone on Unix

__END__

=pod

=encoding UTF-8

=head1 NAME

DateTime::TimeZone::Local::Unix - Determine the local system's time zone on Unix

=head1 VERSION

version 2.66

=head1 SYNOPSIS

  my $tz = DateTime::TimeZone->new( name => 'local' );

  my $tz = DateTime::TimeZone::Local->TimeZone();

=head1 DESCRIPTION

This module provides methods for determining the local time zone on a Unix
platform.

=head1 HOW THE TIME ZONE IS DETERMINED

This class tries the following methods of determining the local time zone, in
the order listed here:

=over 4

=item * $ENV{TZ}

It checks C<< $ENV{TZ} >> for a valid time zone name.

=item * F</etc/timezone>

If this file exists, it is read and its contents are used as a time zone name.

Note that this file may be out of date on many systems, as modern distros may
not do a good job of updating this file. If you find that this file is not
being updated, you may want to consider deleting it so that one of the
following methods can be used.

=item * F</etc/localtime>

If this file is a symlink to an Olson database time zone file (usually in
F</usr/share/zoneinfo>) then it uses the target file's path name to determine
the time zone name. For example, if the path is
F</usr/share/zoneinfo/America/Chicago>, the time zone is "America/Chicago".

Some systems just copy the relevant file to F</etc/localtime> instead of making
a symlink.  In this case, we look in F</usr/share/zoneinfo> for a file that has
the same size and content as F</etc/localtime> to determine the local time
zone.

=item * F</etc/TIMEZONE>

If this file exists, it is opened and we look for a line starting like "TZ =
...". If this is found, it should indicate a time zone name.

=item * F</etc/sysconfig/clock>

If this file exists, it is opened and we look for a line starting like
"TIMEZONE = ..." or "ZONE = ...". If this is found, it should indicate a time
zone name.

=item * F</etc/default/init>

If this file exists, it is opened and we look for a line starting like
"TZ=...". If this is found, it should indicate a time zone name.

=back

B<Note:> Some systems such as virtual machine boxes may lack any of these
files. You can confirm that this is case by running:

    $ ls -l /etc/localtime /etc/timezone /etc/TIMEZONE \
        /etc/sysconfig/clock /etc/default/init

If this is the case, then when checking for timezone handling you are likely to
get an exception:

    $ perl -wle 'use DateTime; DateTime->now( time_zone => "local" )'
    Cannot determine local time zone

In that case, you should consult your system F<man> pages for details on how to
address that problem. In one such case reported to us, a FreeBSD virtual
machine had been built without any of these files. The user was able to run the
FreeBSD F<tzsetup> utility. That installed F</etc/localtime>, after which the
above timezone diagnostic ran silently, I<i.e.>, without throwing an exception.

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/DateTime-TimeZone/issues>.

=head1 SOURCE

The source code repository for DateTime-TimeZone can be found at L<https://github.com/houseabsolute/DateTime-TimeZone>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2025 by Dave Rolsky.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
