package DBIx::Class::ResultSourceProxy::Table;

use strict;
use warnings;

use base qw/DBIx::Class::ResultSourceProxy/;

use DBIx::Class::ResultSource::Table;
use Scalar::Util ();

__PACKAGE__->mk_classdata(table_class => 'DBIx::Class::ResultSource::Table');

__PACKAGE__->mk_classdata('table_alias'); # FIXME: Doesn't actually do
                                          # anything yet!

sub _init_result_source_instance {
    my $class = shift;

    $class->mk_classdata('result_source_instance')
        unless $class->can('result_source_instance');

    my $table = $class->result_source_instance;
    my $class_has_table_instance = ($table and $table->result_class eq $class);
    return $table if $class_has_table_instance;

    my $table_class = $class->table_class;
    $class->ensure_class_loaded($table_class);

    if( $table ) {
        $table = $table_class->new({
            %$table,
            result_class => $class,
            source_name => undef,
            schema => undef
        });
    }
    else {
        $table = $table_class->new({
            name            => undef,
            result_class    => $class,
            source_name     => undef,
        });
    }

    $class->result_source_instance($table);

    return $table;
}

=head1 NAME

DBIx::Class::ResultSourceProxy::Table - provides a classdata table
object and method proxies

=head1 SYNOPSIS

  __PACKAGE__->table('cd');
  __PACKAGE__->add_columns(qw/cdid artist title year/);
  __PACKAGE__->set_primary_key('cdid');

=head1 METHODS

=head2 add_columns

  __PACKAGE__->add_columns(qw/cdid artist title year/);

Adds columns to the current class and creates accessors for them.

=cut

=head2 table

  __PACKAGE__->table('tbl_name');

Gets or sets the table name.

=cut

sub table {
  my ($class, $table) = @_;
  return $class->result_source_instance->name unless $table;

  unless (Scalar::Util::blessed($table) && $table->isa($class->table_class)) {

    my $table_class = $class->table_class;
    $class->ensure_class_loaded($table_class);

    $table = $table_class->new({
        $class->can('result_source_instance') ?
          %{$class->result_source_instance||{}} : (),
        name => $table,
        result_class => $class,
        source_name => undef,
    });
  }

  $class->mk_classdata('result_source_instance')
    unless $class->can('result_source_instance');

  $class->result_source_instance($table);

  return $class->result_source_instance->name;
}

=head2 has_column

  if ($obj->has_column($col)) { ... }

Returns 1 if the class has a column of this name, 0 otherwise.

=cut

=head2 column_info

  my $info = $obj->column_info($col);

Returns the column metadata hashref for a column. For a description of
the various types of column data in this hashref, see
L<DBIx::Class::ResultSource/add_column>

=cut

=head2 columns

  my @column_names = $obj->columns;

=cut

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

