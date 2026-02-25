package DateTime::TimeZone::Local;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '2.66';

use DateTime::TimeZone;
use File::Spec;
use Module::Runtime qw( require_module );
use Try::Tiny;

sub TimeZone {
    my $class = shift;

    my $subclass = $class->_load_subclass();

    for my $meth ( $subclass->Methods() ) {
        my $tz = $subclass->$meth();

        return $tz if $tz;
    }

    die "Cannot determine local time zone\n";
}

{
    # Stolen from File::Spec. My theory is that other folks can write
    # the non-existent modules if they feel a need, and release them
    # to CPAN separately.
    my %subclass = (
        android => 'Android',
        cygwin  => 'Unix',
        dos     => 'OS2',
        epoc    => 'Epoc',
        MacOS   => 'Mac',
        MSWin32 => 'Win32',
        NetWare => 'Win32',
        os2     => 'OS2',
        symbian => 'Win32',
        VMS     => 'VMS',
    );

    sub _load_subclass {
        my $class = shift;

        my $os_name  = $subclass{$^O} || $^O;
        my $subclass = $class . '::' . $os_name;

        return $subclass if $subclass->can('Methods');

        return $subclass if try {
            ## no critic (Variables::RequireInitializationForLocalVars)
            local $SIG{__DIE__};
            require_module($subclass);
        };

        $subclass = $class . '::Unix';

        require_module($subclass);

        return $subclass;
    }
}

sub FromEnv {
    my $class = shift;

    foreach my $var ( $class->EnvVars() ) {
        if ( $class->_IsValidName( $ENV{$var} ) ) {
            my $tz = try {
                ## no critic (Variables::RequireInitializationForLocalVars)
                local $SIG{__DIE__};
                DateTime::TimeZone->new( name => $ENV{$var} );
            };

            return $tz if $tz;
        }
    }

    return;
}

sub _IsValidName {
    shift;

    return 0 unless defined $_[0];
    return 0 if $_[0] eq 'local';

    return $_[0] =~ m{^[\w/\-\+]+$};
}

1;

# ABSTRACT: Determine the local system's time zone

__END__

=pod

=encoding UTF-8

=head1 NAME

DateTime::TimeZone::Local - Determine the local system's time zone

=head1 VERSION

version 2.66

=head1 SYNOPSIS

  my $tz = DateTime::TimeZone->new( name => 'local' );

  my $tz = DateTime::TimeZone::Local->TimeZone();

=head1 DESCRIPTION

This module provides an interface for determining the local system's time zone.
Most of the functionality for doing this is in OS-specific subclasses.

=head1 USAGE

This class provides the following methods:

=head2 DateTime::TimeZone::Local->TimeZone()

This attempts to load an appropriate subclass and asks it to find the local
time zone. This method is called by when you pass "local" as the time zone name
to C<< DateTime:TimeZone->new() >>.

If your OS is not explicitly handled, you can create a module with a name of
the form C<DateTime::TimeZone::Local::$^O>. If it exists, it will be used
instead of falling back to the Unix subclass.

If no OS-specific module exists, we fall back to using the Unix subclass.

See L<DateTime::TimeZone::Local::Unix>, L<DateTime::TimeZone::Local::Android>,
L<DateTime::TimeZone::Local::hpux>, L<DateTime::TimeZone::Local::Win32>, and
L<DateTime::TimeZone::Local::VMS> for OS-specific details.

=head1 SUBCLASSING

If you want to make a new OS-specific subclass, there are several methods
provided by this module you should know about.

=head2 $class->Methods()

This method should be provided by your class. It should provide a list of
methods that will be called to try to determine the local time zone.

Each of these methods is expected to return a new C<DateTime::TimeZone> object
if it can successfully determine the time zone.

=head2 $class->FromEnv()

This method tries to find a valid time zone in an C<%ENV> value. It calls C<<
$class->EnvVars() >> to determine which keys to look at.

To use this from a subclass, simply return "FromEnv" as one of the items from
C<< $class->Methods() >>.

=head2 $class->EnvVars()

This method should be provided by your subclass. It should return a list of env
vars to be checked by C<< $class->FromEnv() >>.

Your class should always include the C<TZ> key as one of the variables to
check.

=head2 $class->_IsValidName($name)

Given a possible time zone name, this returns a boolean indicating whether or
not the name looks valid. It always return false for "local" in order to avoid
infinite loops.

=head1 EXAMPLE SUBCLASS

Here is a simple example subclass:

  package DateTime::TimeZone::SomeOS;

  use strict;
  use warnings;

  use base 'DateTime::TimeZone::Local';


  sub Methods { qw( FromEnv FromEther ) }

  sub EnvVars { qw( TZ ZONE ) }

  sub FromEther
  {
      my $class = shift;

      ...
  }

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
