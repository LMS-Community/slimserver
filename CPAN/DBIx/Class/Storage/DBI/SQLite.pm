package DBIx::Class::Storage::DBI::SQLite;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;

sub last_insert_id {
  return $_[0]->dbh->func('last_insert_rowid');
}

1;

=head1 NAME 

DBIx::Class::PK::Auto::SQLite - Automatic primary key class for SQLite

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class implements autoincrements for SQLite.

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
