package # hide from PAUSE
    DBIx::Class::ResultSourceProxy;

use strict;
use warnings;

use base qw/DBIx::Class/;
use Scalar::Util qw/blessed/;
use Carp::Clan qw/^DBIx::Class/;

sub iterator_class  { shift->result_source_instance->resultset_class(@_) }
sub resultset_class { shift->result_source_instance->resultset_class(@_) }
sub result_class { shift->result_source_instance->result_class(@_) }
sub source_info { shift->result_source_instance->source_info(@_) }

sub set_inherited_ro_instance {
    my $self = shift;

    croak "Cannot set @{[shift]} on an instance" if blessed $self;

    return $self->set_inherited(@_);
}

sub get_inherited_ro_instance {
    return shift->get_inherited(@_);
}

__PACKAGE__->mk_group_accessors('inherited_ro_instance' => 'source_name');


sub resultset_attributes {
  shift->result_source_instance->resultset_attributes(@_);
}

sub add_columns {
  my ($class, @cols) = @_;
  my $source = $class->result_source_instance;
  $source->add_columns(@cols);
  foreach my $c (grep { !ref } @cols) {
    $class->register_column($c => $source->column_info($c));
  }
}

*add_column = \&add_columns;

sub has_column {
  shift->result_source_instance->has_column(@_);
}

sub column_info {
  shift->result_source_instance->column_info(@_);
}

sub column_info_from_storage {
  shift->result_source_instance->column_info_from_storage(@_);
}

sub columns {
  shift->result_source_instance->columns(@_);
}

sub remove_columns {
  shift->result_source_instance->remove_columns(@_);
}

*remove_column = \&remove_columns;

sub set_primary_key {
  shift->result_source_instance->set_primary_key(@_);
}

sub primary_columns {
  shift->result_source_instance->primary_columns(@_);
}

sub add_unique_constraint {
  shift->result_source_instance->add_unique_constraint(@_);
}

sub unique_constraints {
  shift->result_source_instance->unique_constraints(@_);
}

sub unique_constraint_names {
  shift->result_source_instance->unique_constraint_names(@_);
}

sub unique_constraint_columns {
  shift->result_source_instance->unique_constraint_columns(@_);
}

sub add_relationship {
  my ($class, $rel, @rest) = @_;
  my $source = $class->result_source_instance;
  $source->add_relationship($rel => @rest);
  $class->register_relationship($rel => $source->relationship_info($rel));
}

sub relationships {
  shift->result_source_instance->relationships(@_);
}

sub relationship_info {
  shift->result_source_instance->relationship_info(@_);
}

1;
