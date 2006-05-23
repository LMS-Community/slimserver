package DBIx::Class::UUIDMaker::Data::UUID;

use strict;
use warnings;

use base qw/DBIx::Class::UUIDMaker/;
use Data::UUID ();

sub as_string {
    return Data::UUID->new->to_string(Data::UUID->new->create);
};

1;
__END__

=head1 NAME

DBIx::Class::UUIDMaker::Data::UUID - Create uuids using Data::UUID

=head1 SYNOPSIS

  package Artist;
  __PACKAGE__->load_components(qw/UUIDColumns Core DB/);
  __PACKAGE__->uuid_columns( 'artist_id' );
  __PACKAGE__->uuid_class('::Data::UUID');

=head1 DESCRIPTION

This DBIx::Class::UUIDMaker subclass uses Data::UUID to generate uuid
strings in the following format:

  098f2470-bae0-11cd-b579-08002b30bfeb

=head1 METHODS

=head2 as_string

Returns the new uuid as a string.

=head1 SEE ALSO

L<Data::UUID>

=head1 AUTHOR

Chris Laco <claco@chrislaco.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.
