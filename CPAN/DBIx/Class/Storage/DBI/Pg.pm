package DBIx::Class::Storage::DBI::Pg;

use strict;
use warnings;

use DBD::Pg qw(:pg_types);

use base qw/DBIx::Class::Storage::DBI::MultiColumnIn/;

# __PACKAGE__->load_components(qw/PK::Auto/);

# Warn about problematic versions of DBD::Pg
warn "DBD::Pg 1.49 is strongly recommended"
  if ($DBD::Pg::VERSION < 1.49);

sub with_deferred_fk_checks {
  my ($self, $sub) = @_;

  $self->dbh->do('SET CONSTRAINTS ALL DEFERRED');
  $sub->();
}

sub _dbh_last_insert_id {
  my ($self, $dbh, $seq) = @_;
  $dbh->last_insert_id(undef, undef, undef, undef, {sequence => $seq});
}

sub last_insert_id {
  my ($self,$source,$col) = @_;
  my $seq = ($source->column_info($col)->{sequence} ||= $self->get_autoinc_seq($source,$col));
  $self->throw_exception("could not fetch primary key for " . $source->name . ", could not "
    . "get autoinc sequence for $col (check that table and column specifications are correct "
    . "and in the correct case)") unless defined $seq;
  $self->dbh_do('_dbh_last_insert_id', $seq);
}

sub _dbh_get_autoinc_seq {
  my ($self, $dbh, $schema, $table, @pri) = @_;

  while (my $col = shift @pri) {
    my $info = $dbh->column_info(undef,$schema,$table,$col)->fetchrow_hashref;
    if(defined $info->{COLUMN_DEF} and
       $info->{COLUMN_DEF} =~ /^nextval\(+'([^']+)'::(?:text|regclass)\)/) {
      my $seq = $1;
      # may need to strip quotes -- see if this works
      return $seq =~ /\./ ? $seq : $info->{TABLE_SCHEM} . "." . $seq;
    }
  }
  return;
}

sub get_autoinc_seq {
  my ($self,$source,$col) = @_;
    
  my @pri = $source->primary_columns;
  my ($schema,$table) = $source->name =~ /^(.+)\.(.+)$/ ? ($1,$2)
    : (undef,$source->name);

  $self->dbh_do('_dbh_get_autoinc_seq', $schema, $table, @pri);
}

sub sqlt_type {
  return 'PostgreSQL';
}

sub datetime_parser_type { return "DateTime::Format::Pg"; }

sub bind_attribute_by_data_type {
  my ($self,$data_type) = @_;

  my $bind_attributes = {
    bytea => { pg_type => DBD::Pg::PG_BYTEA },
    blob  => { pg_type => DBD::Pg::PG_BYTEA },
  };
 
  if( defined $bind_attributes->{$data_type} ) {
    return $bind_attributes->{$data_type};
  }
  else {
    return;
  }
}

sub _sequence_fetch {
  my ( $self, $type, $seq ) = @_;
  my ($id) = $self->dbh->selectrow_array("SELECT nextval('${seq}')");
  return $id;
}

sub _svp_begin {
    my ($self, $name) = @_;

    $self->dbh->pg_savepoint($name);
}

sub _svp_release {
    my ($self, $name) = @_;

    $self->dbh->pg_release($name);
}

sub _svp_rollback {
    my ($self, $name) = @_;

    $self->dbh->pg_rollback_to($name);
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::Pg - Automatic primary key class for PostgreSQL

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->set_primary_key('id');
  __PACKAGE__->sequence('mysequence');

=head1 DESCRIPTION

This class implements autoincrements for PostgreSQL.

=head1 AUTHORS

Marcus Ramberg <m.ramberg@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
