package DBIx::Class::Storage::DBI::Sybase::MSSQL;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::MSSQL DBIx::Class::Storage::DBI::Sybase/;

1;

=head1 NAME

DBIx::Class::Storage::DBI::Sybase::MSSQL - Storage::DBI subclass for MSSQL via
DBD::Sybase

=head1 SYNOPSIS

This subclass supports MSSQL connected via L<DBD::Sybase>.

  $schema->storage_type('::DBI::Sybase::MSSQL');
  $schema->connect_info('dbi:Sybase:....', ...);

=head1 AUTHORS

Brandon L Black <blblack@gmail.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
