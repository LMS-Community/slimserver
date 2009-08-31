package # hide from PAUSE
    DBIx::Class::Storage::DBI::Sybase::Base;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

=head1 NAME

DBIx::Class::Storage::DBI::Sybase::Base - Common functionality for drivers using
DBD::Sybase

=cut

sub _ping {
  my $self = shift;

  my $dbh = $self->_dbh or return 0;

  local $dbh->{RaiseError} = 1;
  eval {
    $dbh->do('select 1');
  };

  return $@ ? 0 : 1;
}

sub _placeholders_supported {
  my $self = shift;
  my $dbh  = $self->_get_dbh;

  return eval {
# There's also $dbh->{syb_dynamic_supported} but it can be inaccurate for this
# purpose.
    local $dbh->{PrintError} = 0;
    local $dbh->{RaiseError} = 1;
# this specifically tests a bind that is NOT a string
    $dbh->selectrow_array('select 1 where 1 = ?', {}, 1);
  };
}

1;

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
