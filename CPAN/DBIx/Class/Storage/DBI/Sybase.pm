package DBIx::Class::Storage::DBI::Sybase;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::NoBindVars/;

1;

=head1 NAME

DBIx::Class::Storage::DBI::Sybase - Storage::DBI subclass for Sybase

=head1 SYNOPSIS

This subclass supports L<DBD::Sybase> for real Sybase databases.  If
you are using an MSSQL database via L<DBD::Sybase>, see
L<DBIx::Class::Storage::DBI::Sybase::MSSQL>.

=head1 AUTHORS

Brandon L Black <blblack@gmail.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
