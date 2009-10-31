package DBIx::Class::Storage::DBI::Pg;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::MultiColumnIn/;
use mro 'c3';

use DBD::Pg qw(:pg_types);

# Ask for a DBD::Pg with array support
warn "DBD::Pg 2.9.2 or greater is strongly recommended\n"
  if ($DBD::Pg::VERSION < 2.009002);  # pg uses (used?) version::qv()

sub with_deferred_fk_checks {
  my ($self, $sub) = @_;

  $self->_get_dbh->do('SET CONSTRAINTS ALL DEFERRED');
  $sub->();
}

sub last_insert_id {
  my ($self,$source,@cols) = @_;

  my @values;

  for my $col (@cols) {
    my $seq = ( $source->column_info($col)->{sequence} ||= $self->dbh_do('_dbh_get_autoinc_seq', $source, $col) )
      or $self->throw_exception( "could not determine sequence for "
                                 . $source->name
                                 . ".$col, please consider adding a "
                                 . "schema-qualified sequence to its column info"
                               );

    push @values, $self->_dbh_last_insert_id ($self->_dbh, $seq);
  }

  return @values;
}

# there seems to be absolutely no reason to have this as a separate method,
# but leaving intact in case someone is already overriding it
sub _dbh_last_insert_id {
  my ($self, $dbh, $seq) = @_;
  $dbh->last_insert_id(undef, undef, undef, undef, {sequence => $seq});
}


sub _dbh_get_autoinc_seq {
  my ($self, $dbh, $source, $col) = @_;

  my $schema;
  my $table = $source->name;

  # deref table name if it needs it
  $table = $$table
      if ref $table eq 'SCALAR';

  # parse out schema name if present
  if( $table =~ /^(.+)\.(.+)$/ ) {
    ( $schema, $table ) = ( $1, $2 );
  }

  # use DBD::Pg to fetch the column info if it is recent enough to
  # work. otherwise, use custom SQL
  my $seq_expr =  $DBD::Pg::VERSION >= 2.015001
      ? eval{ $dbh->column_info(undef,$schema,$table,$col)->fetchrow_hashref->{COLUMN_DEF} }
      : $self->_dbh_get_column_default( $dbh, $schema, $table, $col );

  # if no default value is set on the column, or if we can't parse the
  # default value as a sequence, throw.
  unless ( defined $seq_expr and $seq_expr =~ /^nextval\(+'([^']+)'::(?:text|regclass)\)/i ){
    $seq_expr = '' unless defined $seq_expr;
    $schema = "$schema." if defined $schema && length $schema;
    $self->throw_exception( "no sequence found for $schema$table.$col, check table definition, "
                            . "or explicitly set the 'sequence' for this column in the "
                            . $source->source_name
                            . " class"
                          );
  }

  return $1;
}

# custom method for fetching column default, since column_info has a
# bug with older versions of DBD::Pg
sub _dbh_get_column_default {
  my ( $self, $dbh, $schema, $table, $col ) = @_;

  # Build and execute a query into the pg_catalog to find the Pg
  # expression for the default value for this column in this table.
  # If the table name is schema-qualified, query using that specific
  # schema name.

  # Otherwise, find the table in the standard Postgres way, using the
  # search path.  This is done with the pg_catalog.pg_table_is_visible
  # function, which returns true if a given table is 'visible',
  # meaning the first table of that name to be found in the search
  # path.

  # I *think* we can be assured that this query will always find the
  # correct column according to standard Postgres semantics.
  #
  # -- rbuels

  my $sqlmaker = $self->sql_maker;
  local $sqlmaker->{bindtype} = 'normal';

  my ($where, @bind) = $sqlmaker->where ({
    'a.attnum' => {'>', 0},
    'c.relname' => $table,
    'a.attname' => $col,
    -not_bool => 'a.attisdropped',
    (defined $schema && length $schema)
      ? ( 'n.nspname' => $schema )
      : ( -bool => \'pg_catalog.pg_table_is_visible(c.oid)' )
  });

  my ($seq_expr) = $dbh->selectrow_array(<<EOS,undef,@bind);

SELECT
  (SELECT pg_catalog.pg_get_expr(d.adbin, d.adrelid)
   FROM pg_catalog.pg_attrdef d
   WHERE d.adrelid = a.attrelid AND d.adnum = a.attnum AND a.atthasdef)
FROM pg_catalog.pg_class c
     LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
$where

EOS

  return $seq_expr;
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
  my ($id) = $self->_get_dbh->selectrow_array("SELECT nextval('${seq}')");
  return $id;
}

sub _svp_begin {
    my ($self, $name) = @_;

    $self->_get_dbh->pg_savepoint($name);
}

sub _svp_release {
    my ($self, $name) = @_;

    $self->_get_dbh->pg_release($name);
}

sub _svp_rollback {
    my ($self, $name) = @_;

    $self->_get_dbh->pg_rollback_to($name);
}

1;

__END__

=head1 NAME

DBIx::Class::Storage::DBI::Pg - Automatic primary key class for PostgreSQL

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->set_primary_key('id');
  __PACKAGE__->sequence('mysequence');

=head1 DESCRIPTION

This class implements autoincrements for PostgreSQL.

=head1 POSTGRESQL SCHEMA SUPPORT

This driver supports multiple PostgreSQL schemas, with one caveat: for
performance reasons, data about the search path, sequence names, and
so forth is queried as needed and CACHED for subsequent uses.

For this reason, once your schema is instantiated, you should not
change the PostgreSQL schema search path for that schema's database
connection. If you do, Bad Things may happen.

You should do any necessary manipulation of the search path BEFORE
instantiating your schema object, or as part of the on_connect_do
option to connect(), for example:

   my $schema = My::Schema->connect
                  ( $dsn,$user,$pass,
                    { on_connect_do =>
                        [ 'SET search_path TO myschema, foo, public' ],
                    },
                  );

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
