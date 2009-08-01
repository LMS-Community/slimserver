package DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server;

use strict;
use warnings;

use base qw/
  DBIx::Class::Storage::DBI::ODBC::Microsoft_SQL_Server
  DBIx::Class::Storage::DBI::Sybase
/;

1;

=head1 NAME

DBIx::Class::Storage::DBI::Sybase::Microsoft_SQL_Server - Storage::DBI subclass for MSSQL via
DBD::Sybase

=head1 SYNOPSIS

This subclass supports MSSQL server connections via L<DBD::Sybase>.

=head1 CAVEATS

This storage driver uses L<DBIx::Class::Storage::DBI::NoBindVars> as a base.
This means that bind variables will be interpolated (properly quoted of course)
into the SQL query itself, without using bind placeholders.

More importantly this means that caching of prepared statements is explicitly
disabled, as the interpolation renders it useless.

=head1 AUTHORS

Brandon L Black <blblack@gmail.com>

Justin Hunter <justin.d.hunter@gmail.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
