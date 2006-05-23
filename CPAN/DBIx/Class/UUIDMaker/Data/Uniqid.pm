package DBIx::Class::UUIDMaker::Data::Uniqid;

use strict;
use warnings;

use base qw/DBIx::Class::UUIDMaker/;
use Data::Uniqid ();

sub as_string {
    return Data::Uniqid->luniqid;
};

1;
__END__

=head1 NAME

DBIx::Class::UUIDMaker::Data::Uniqid - Create uuids using Data::Uniqid

=head1 SYNOPSIS

  package Artist;
  __PACKAGE__->load_components(qw/UUIDColumns Core DB/);
  __PACKAGE__->uuid_columns( 'artist_id' );
  __PACKAGE__->uuid_class('::Data::Uniqid');

=head1 DESCRIPTION

This DBIx::Class::UUIDMaker subclass uses Data::Uniqid to generate uuid
strings using Data::Uniqid::luniqid.

=head1 METHODS

=head2 as_string

Returns the new uuid as a string.

=head1 SEE ALSO

L<Data::Data::Uniqid>

=head1 AUTHOR

Chris Laco <claco@chrislaco.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.
