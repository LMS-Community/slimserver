package DBIx::Class::Core;

use strict;
use warnings;
no warnings 'qw';

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/
  Relationship
  InflateColumn
  PK::Auto
  PK
  Row
  ResultSourceProxy::Table/);

1;

=head1 NAME

DBIx::Class::Core - Core set of DBIx::Class modules

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/Core/);

=head1 DESCRIPTION

This class just inherits from the various modules that make up the
L<DBIx::Class> core features.  You almost certainly want these.

The core modules currently are:

=over 4

=item L<DBIx::Class::Serialize::Storable>

=item L<DBIx::Class::InflateColumn>

=item L<DBIx::Class::Relationship>

=item L<DBIx::Class::PK::Auto>

=item L<DBIx::Class::PK>

=item L<DBIx::Class::Row>

=item L<DBIx::Class::ResultSourceProxy::Table>

=back

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
