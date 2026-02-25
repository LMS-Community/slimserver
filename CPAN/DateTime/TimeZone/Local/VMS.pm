package DateTime::TimeZone::Local::VMS;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '2.66';

use parent 'DateTime::TimeZone::Local';

sub Methods { return qw( FromEnv ) }

sub EnvVars {
    return qw( TZ SYS$TIMEZONE_RULE SYS$TIMEZONE_NAME UCX$TZ TCPIP$TZ );
}

1;

# ABSTRACT: Determine the local system's time zone on VMS

__END__

=pod

=encoding UTF-8

=head1 NAME

DateTime::TimeZone::Local::VMS - Determine the local system's time zone on VMS

=head1 VERSION

version 2.66

=head1 SYNOPSIS

  my $tz = DateTime::TimeZone->new( name => 'local' );

  my $tz = DateTime::TimeZone::Local->TimeZone();

=head1 DESCRIPTION

This module provides methods for determining the local time zone on a VMS
platform.

NOTE: This is basically a stub pending an implementation by someone who knows
something about VMS.

=head1 HOW THE TIME ZONE IS DETERMINED

This class tries the following methods of determining the local time zone:

=over 4

=item * %ENV

We check the following environment variables:

=over 8

=item * TZ

=item * SYS$TIMEZONE_RULE

=item * SYS$TIMEZONE_NAME

=item * UCX$TZ

=item * TCPIP$TZ

=back

=back

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
