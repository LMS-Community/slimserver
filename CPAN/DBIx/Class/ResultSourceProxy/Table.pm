package DBIx::Class::ResultSourceProxy::Table;

use strict;
use warnings;

use base qw/DBIx::Class::ResultSourceProxy/;
__PACKAGE__->load_components(qw/AccessorGroup/);

__PACKAGE__->mk_group_accessors('component_class' => 'table_class');
__PACKAGE__->table_class('DBIx::Class::ResultSource::Table');

__PACKAGE__->mk_classdata('table_alias'); # FIXME: Doesn't actually do
                                          # anything yet!

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
  unless (ref $table) {
    $table = $class->table_class->new({
        $class->can('result_source_instance') ?
          %{$class->result_source_instance} : (),
        name => $table,
        result_class => $class,
        source_name => undef,
    });
  }
  $class->mk_classdata('result_source_instance' => $table);
  if ($class->can('schema_instance')) {
    $class =~ m/([^:]+)$/;
    $class->schema_instance->register_class($class, $class);
  }
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

