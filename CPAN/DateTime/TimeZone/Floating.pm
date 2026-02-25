package DateTime::TimeZone::Floating;

use strict;
use warnings;
use namespace::autoclean;

our $VERSION = '2.66';

use parent 'Class::Singleton', 'DateTime::TimeZone::OffsetOnly';

sub new {
    return shift->instance;
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _new_instance {
    my $class = shift;

    return bless {
        name   => 'floating',
        offset => 0
    }, $class;
}
## use critic

sub is_floating {1}

sub STORABLE_thaw {
    my $self = shift;

    my $class = ref $self || $self;

    my $obj;
    if ( $class->isa(__PACKAGE__) ) {
        $obj = __PACKAGE__->new();
    }
    else {
        $obj = $class->new();
    }

    %$self = %$obj;

    return $self;
}

1;

# ABSTRACT: A time zone that is always local

__END__

=pod

=encoding UTF-8

=head1 NAME

DateTime::TimeZone::Floating - A time zone that is always local

=head1 VERSION

version 2.66

=head1 SYNOPSIS

  my $floating_tz = DateTime::TimeZone::Floating->new;

=head1 DESCRIPTION

This class is used to provide the DateTime::TimeZone API needed by DateTime.pm,
but for floating times, as defined by the RFC 2445 spec. A floating time has no
time zone, and has an effective offset of zero.

=head1 USAGE

This class has the same methods as a real time zone object. The
C<short_name_for_datetime()> method returns the string "floating" and the
C<category()> method returns C<undef>.

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
