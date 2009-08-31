package DBIx::Class::ResultSource::View;

use strict;
use warnings;

use DBIx::Class::ResultSet;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/ResultSource/);
__PACKAGE__->mk_group_accessors(
  'simple' => qw(is_virtual view_definition)
);

=head1 NAME

DBIx::Class::ResultSource::View - ResultSource object representing a view

=head1 SYNOPSIS

  package MyDB::Schema::Result::Year2000CDs;

  use base qw/DBIx::Class/;

  __PACKAGE__->load_components('Core');
  __PACKAGE__->table_class('DBIx::Class::ResultSource::View');

  __PACKAGE__->table('year2000cds');
  __PACKAGE__->result_source_instance->is_virtual(1);
  __PACKAGE__->result_source_instance->view_definition(
      "SELECT cdid, artist, title FROM cd WHERE year ='2000'"
  );
  __PACKAGE__->add_columns(
    'cdid' => {
      data_type => 'integer',
      is_auto_increment => 1,
    },
    'artist' => {
      data_type => 'integer',
    },
    'title' => {
      data_type => 'varchar',
      size      => 100,
    },
  );

=head1 DESCRIPTION

View object that inherits from L<DBIx::Class::ResultSource>

This class extends ResultSource to add basic view support.

A view has a L</view_definition>, which contains a SQL query. The query can
only have parameters if L</is_virtual> is set to true. It may contain JOINs,
sub selects and any other SQL your database supports.

View definition SQL is deployed to your database on
L<DBIx::Class::Schema/deploy> unless you set L</is_virtual> to true.

Deploying the view does B<not> translate it between different database
syntaxes, so be careful what you write in your view SQL.

Virtual views (L</is_virtual> true), are assumed to not
exist in your database as a real view. The L</view_definition> in this
case replaces the view name in a FROM clause in a subselect.

=head1 EXAMPLES

Having created the MyDB::Schema::Year2000CDs schema as shown in the SYNOPSIS
above, you can then:

  $2000_cds = $schema->resultset('Year2000CDs')
                     ->search()
                     ->all();
  $count    = $schema->resultset('Year2000CDs')
                     ->search()
                     ->count();

If you modified the schema to include a placeholder

  __PACKAGE__->result_source_instance->view_definition(
      "SELECT cdid, artist, title FROM cd WHERE year ='?'"
  );

and ensuring you have is_virtual set to true:

  __PACKAGE__->result_source_instance->is_virtual(1);

You could now say:

  $2001_cds = $schema->resultset('Year2000CDs')
                     ->search({}, { bind => [2001] })
                     ->all();
  $count    = $schema->resultset('Year2000CDs')
                     ->search({}, { bind => [2001] })
                     ->count();

=head1 SQL EXAMPLES

=over

=item is_virtual set to false

  $schema->resultset('Year2000CDs')->all();

  SELECT cdid, artist, title FROM year2000cds me

=item is_virtual set to true

  $schema->resultset('Year2000CDs')->all();

  SELECT cdid, artist, title FROM 
    (SELECT cdid, artist, title FROM cd WHERE year ='2000') me

=back

=head1 METHODS

=head2 is_virtual

  __PACKAGE__->result_source_instance->is_virtual(1);

Set to true for a virtual view, false or unset for a real
database-based view.

=head2 view_definition

  __PACKAGE__->result_source_instance->view_definition(
      "SELECT cdid, artist, title FROM cd WHERE year ='2000'"
      );

An SQL query for your view. Will not be translated across database
syntaxes.


=head1 OVERRIDDEN METHODS

=head2 from

Returns the FROM entry for the table (i.e. the view name)
or the SQL as a subselect if this is a virtual view.

=cut

sub from {
  my $self = shift;
  return \"(${\$self->view_definition})" if $self->is_virtual;
  return $self->name;
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

With Contributions from:

Guillermo Roditi E<lt>groditi@cpan.orgE<gt>

Jess Robinson <castaway@desert-island.me.uk>

Wallace Reis <wreis@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

