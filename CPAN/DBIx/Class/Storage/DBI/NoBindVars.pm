package DBIx::Class::Storage::DBI::NoBindVars;

use strict;
use warnings;

use base 'DBIx::Class::Storage::DBI';

=head1 NAME 

DBIx::Class::Storage::DBI::NoBindVars - Sometime DBDs have poor to no support for bind variables

=head1 DESCRIPTION

This class allows queries to work when the DBD or underlying library does not
support the usual C<?> placeholders, or at least doesn't support them very
well, as is the case with L<DBD::Sybase>

=head1 METHODS

=head2 connect_info

We can't cache very effectively without bind variables, so force the C<disable_sth_caching> setting to be turned on when the connect info is set.

=cut

sub connect_info {
    my $self = shift;
    my $retval = $self->next::method(@_);
    $self->disable_sth_caching(1);
    $retval;
}

=head2 _prep_for_execute

Manually subs in the values for the usual C<?> placeholders.

=cut

sub _prep_for_execute {
  my $self = shift;

  my ($op, $extra_bind, $ident) = @_;

  my ($sql, $bind) = $self->next::method(@_);

  # stringify args, quote via $dbh, and manually insert

  my @sql_part = split /\?/, $sql;
  my $new_sql;

  foreach my $bound (@$bind) {
    my $col = shift @$bound;
    my $datatype = 'FIXME!!!';
    foreach my $data (@$bound) {
        if(ref $data) {
            $data = ''.$data;
        }
        $data = $self->_dbh->quote($data);
        $new_sql .= shift(@sql_part) . $data;
    }
  }
  $new_sql .= join '', @sql_part;

  return ($new_sql, []);
}

=head1 AUTHORS

Brandon Black <blblack@gmail.com>

Trym Skaar <trym@tryms.no>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
