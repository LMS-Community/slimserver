package DBIx::Class::Storage::DBI::Oracle::Generic;

use strict;
use warnings;

=head1 NAME

DBIx::Class::Storage::DBI::Oracle::Generic - Oracle Support for DBIx::Class

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->add_columns({ id => { sequence => 'mysequence', auto_nextval => 1 } });
  __PACKAGE__->set_primary_key('id');
  __PACKAGE__->sequence('mysequence');

=head1 DESCRIPTION

This class implements autoincrements for Oracle.

=head1 METHODS

=cut

use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, @columns) = @_;
  my @ids = ();
  foreach my $col (@columns) {
    my $seq = ($source->column_info($col)->{sequence} ||= $self->get_autoinc_seq($source,$col));
    my $id = $self->_sequence_fetch( 'currval', $seq );
    push @ids, $id;
  }
  return @ids;
}

sub _dbh_get_autoinc_seq {
  my ($self, $dbh, $source, $col) = @_;

  # look up the correct sequence automatically
  my $sql = q{
    SELECT trigger_body FROM ALL_TRIGGERS t
    WHERE t.table_name = ?
    AND t.triggering_event = 'INSERT'
    AND t.status = 'ENABLED'
  };

  # trigger_body is a LONG
  local $dbh->{LongReadLen} = 64 * 1024 if ($dbh->{LongReadLen} < 64 * 1024);

  my $sth;

  # check for fully-qualified name (eg. SCHEMA.TABLENAME)
  if ( my ( $schema, $table ) = $source->name =~ /(\w+)\.(\w+)/ ) {
    $sql = q{
      SELECT trigger_body FROM ALL_TRIGGERS t
      WHERE t.owner = ? AND t.table_name = ?
      AND t.triggering_event = 'INSERT'
      AND t.status = 'ENABLED'
    };
    $sth = $dbh->prepare($sql);
    $sth->execute( uc($schema), uc($table) );
  }
  else {
    $sth = $dbh->prepare($sql);
    $sth->execute( uc( $source->name ) );
  }
  while (my ($insert_trigger) = $sth->fetchrow_array) {
    return uc($1) if $insert_trigger =~ m!(\w+)\.nextval!i; # col name goes here???
  }
  $self->throw_exception("Unable to find a sequence INSERT trigger on table '" . $source->name . "'.");
}

sub _sequence_fetch {
  my ( $self, $type, $seq ) = @_;
  my ($id) = $self->_get_dbh->selectrow_array("SELECT ${seq}.${type} FROM DUAL");
  return $id;
}

sub _ping {
  my $self = shift;

  my $dbh = $self->_dbh or return 0;

  local $dbh->{RaiseError} = 1;

  eval {
    $dbh->do("select 1 from dual");
  };

  return $@ ? 0 : 1;
}

sub _dbh_execute {
  my $self = shift;
  my ($dbh, $op, $extra_bind, $ident, $bind_attributes, @args) = @_;

  my $wantarray = wantarray;

  my (@res, $exception, $retried);

  RETRY: {
    do {
      eval {
        if ($wantarray) {
          @res    = $self->next::method(@_);
        } else {
          $res[0] = $self->next::method(@_);
        }
      };
      $exception = $@;
      if ($exception =~ /ORA-01003/) {
        # ORA-01003: no statement parsed (someone changed the table somehow,
        # invalidating your cursor.)
        my ($sql, $bind) = $self->_prep_for_execute($op, $extra_bind, $ident, \@args);
        delete $dbh->{CachedKids}{$sql};
      } else {
        last RETRY;
      }
    } while (not $retried++);
  }

  $self->throw_exception($exception) if $exception;

  wantarray ? @res : $res[0]
}

=head2 get_autoinc_seq

Returns the sequence name for an autoincrement column

=cut

sub get_autoinc_seq {
  my ($self, $source, $col) = @_;

  $self->dbh_do('_dbh_get_autoinc_seq', $source, $col);
}

=head2 columns_info_for

This wraps the superclass version of this method to force table
names to uppercase

=cut

sub columns_info_for {
  my ($self, $table) = @_;

  $self->next::method(uc($table));
}

=head2 datetime_parser_type

This sets the proper DateTime::Format module for use with
L<DBIx::Class::InflateColumn::DateTime>.

=cut

sub datetime_parser_type { return "DateTime::Format::Oracle"; }

=head2 connect_call_datetime_setup

Used as:

    on_connect_call => 'datetime_setup'

In L<DBIx::Class::Storage::DBI/connect_info> to set the session nls date, and
timestamp values for use with L<DBIx::Class::InflateColumn::DateTime> and the
necessary environment variables for L<DateTime::Format::Oracle>, which is used
by it.

Maximum allowable precision is used, unless the environment variables have
already been set.

These are the defaults used:

  $ENV{NLS_DATE_FORMAT}         ||= 'YYYY-MM-DD HH24:MI:SS';
  $ENV{NLS_TIMESTAMP_FORMAT}    ||= 'YYYY-MM-DD HH24:MI:SS.FF';
  $ENV{NLS_TIMESTAMP_TZ_FORMAT} ||= 'YYYY-MM-DD HH24:MI:SS.FF TZHTZM';

To get more than second precision with L<DBIx::Class::InflateColumn::DateTime>
for your timestamps, use something like this:

  use Time::HiRes 'time';
  my $ts = DateTime->from_epoch(epoch => time);

=cut

sub connect_call_datetime_setup {
  my $self = shift;

  my $date_format = $ENV{NLS_DATE_FORMAT} ||= 'YYYY-MM-DD HH24:MI:SS';
  my $timestamp_format = $ENV{NLS_TIMESTAMP_FORMAT} ||=
    'YYYY-MM-DD HH24:MI:SS.FF';
  my $timestamp_tz_format = $ENV{NLS_TIMESTAMP_TZ_FORMAT} ||=
    'YYYY-MM-DD HH24:MI:SS.FF TZHTZM';

  $self->_do_query("alter session set nls_date_format = '$date_format'");
  $self->_do_query(
"alter session set nls_timestamp_format = '$timestamp_format'");
  $self->_do_query(
"alter session set nls_timestamp_tz_format='$timestamp_tz_format'");
}

=head2 source_bind_attributes

Handle LOB types in Oracle.  Under a certain size (4k?), you can get away
with the driver assuming your input is the deprecated LONG type if you
encode it as a hex string.  That ain't gonna fly at larger values, where
you'll discover you have to do what this does.

This method had to be overridden because we need to set ora_field to the
actual column, and that isn't passed to the call (provided by Storage) to
bind_attribute_by_data_type.

According to L<DBD::Oracle>, the ora_field isn't always necessary, but
adding it doesn't hurt, and will save your bacon if you're modifying a
table with more than one LOB column.

=cut

sub source_bind_attributes 
{
	require DBD::Oracle;
	my $self = shift;
	my($source) = @_;

	my %bind_attributes;

	foreach my $column ($source->columns) {
		my $data_type = $source->column_info($column)->{data_type} || '';
		next unless $data_type;

		my %column_bind_attrs = $self->bind_attribute_by_data_type($data_type);

		if ($data_type =~ /^[BC]LOB$/i) {
			$column_bind_attrs{'ora_type'} = uc($data_type) eq 'CLOB' ?
				DBD::Oracle::ORA_CLOB() :
				DBD::Oracle::ORA_BLOB();
			$column_bind_attrs{'ora_field'} = $column;
		}

		$bind_attributes{$column} = \%column_bind_attrs;
	}

	return \%bind_attributes;
}

sub _svp_begin {
    my ($self, $name) = @_;

    $self->_get_dbh->do("SAVEPOINT $name");
}

# Oracle automatically releases a savepoint when you start another one with the
# same name.
sub _svp_release { 1 }

sub _svp_rollback {
    my ($self, $name) = @_;

    $self->_get_dbh->do("ROLLBACK TO SAVEPOINT $name")
}

=head1 AUTHOR

See L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
