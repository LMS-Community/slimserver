package DBIx::Class::UUIDMaker;

use strict;
use warnings;

sub new {
    return bless {}, shift;
};

sub as_string {
    return undef;
};

1;
__END__

=head1 NAME

DBIx::Class::UUIDMaker - UUID wrapper module

=head1 SYNOPSIS

  package CustomUUIDMaker;
  use base qw/DBIx::Class::/;

  sub as_string {
    my $uuid;
    ...magic incantations...
    return $uuid;
  };

=head1 DESCRIPTION

DBIx::Class::UUIDMaker is a base class used by the various uuid generation
subclasses.

=head1 METHODS

=head2 as_string

Returns the new uuid as a string.

=head1 SEE ALSO

L<DBIx::Class::UUIDMaker>,
L<DBIx::Class::UUIDMaker::UUID>,
L<DBIx::Class::UUIDMaker::APR::UUID>,
L<DBIx::Class::UUIDMaker::Data::UUID>,
L<DBIx::Class::UUIDMaker::Win32::Guidgen>,
L<DBIx::Class::UUIDMaker::Win32API::GUID>,
L<DBIx::Class::UUIDMaker::Data::Uniqid>

=head1 AUTHOR

Chris Laco <claco@chrislaco.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.
