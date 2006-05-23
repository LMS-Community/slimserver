package DBIx::Class::Storage::DBI::Oracle;

use strict;
use warnings;

use Carp qw/croak/;

use base qw/DBIx::Class::Storage::DBI::MultiDistinctEmulation/;

# __PACKAGE__->load_components(qw/PK::Auto/);

sub last_insert_id {
  my ($self,$source,$col) = @_;
  my $seq = ($source->column_info($col)->{sequence} ||= $self->get_autoinc_seq($source,$col));
  my $sql = "SELECT " . $seq . ".currval FROM DUAL";
  my ($id) = $self->_dbh->selectrow_array($sql);
  return $id;
}

sub get_autoinc_seq {
  my ($self,$source,$col) = @_;
    
  # look up the correct sequence automatically
  my $dbh = $self->_dbh;
  my $sql = q{
    SELECT trigger_body FROM ALL_TRIGGERS t
    WHERE t.table_name = ?
    AND t.triggering_event = 'INSERT'
    AND t.status = 'ENABLED'
  };
  # trigger_body is a LONG
  $dbh->{LongReadLen} = 64 * 1024 if ($dbh->{LongReadLen} < 64 * 1024);
  my $sth = $dbh->prepare($sql);
  $sth->execute( uc($source->name) );
  while (my ($insert_trigger) = $sth->fetchrow_array) {
    return uc($1) if $insert_trigger =~ m!(\w+)\.nextval!i; # col name goes here???
  }
  croak "Unable to find a sequence INSERT trigger on table '" . $source->name . "'.";
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::Oracle - Automatic primary key class for Oracle

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->set_primary_key('id');
  __PACKAGE__->sequence('mysequence');

=head1 DESCRIPTION

This class implements autoincrements for Oracle.

=head1 AUTHORS

Andy Grundman <andy@hybridized.org>

Scott Connelly <scottsweep@yahoo.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
