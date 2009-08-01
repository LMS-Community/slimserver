package DBIx::Class::ResultSetManager;
use strict;
use warnings;
use base 'DBIx::Class';
use Sub::Name ();
use Class::Inspector;

warn "DBIx::Class::ResultSetManager never left experimental status and
has now been DEPRECATED. This module will be deleted in 09000 so please
migrate any and all code using it to explicit resultset classes using either
__PACKAGE__->resultset_class(...) calls or by switching from using
DBIx::Class::Schema->load_classes() to load_namespaces() and creating
appropriate My::Schema::ResultSet::* classes for it to pick up.";

=head1 NAME

DBIx::Class::ResultSetManager - scheduled for deletion in 09000

=head1 DESCRIPTION

DBIx::Class::ResultSetManager never left experimental status and
has now been DEPRECATED. This module will be deleted in 09000 so please
migrate any and all code using it to explicit resultset classes using either
__PACKAGE__->resultset_class(...) calls or by switching from using
DBIx::Class::Schema->load_classes() to load_namespaces() and creating
appropriate My::Schema::ResultSet::* classes for it to pick up.";

=cut

__PACKAGE__->mk_classdata($_)
  for qw/ base_resultset_class table_resultset_class_suffix /;
__PACKAGE__->base_resultset_class('DBIx::Class::ResultSet');
__PACKAGE__->table_resultset_class_suffix('::_resultset');

sub table {
    my ($self,@rest) = @_;
    my $ret = $self->next::method(@rest);
    if (@rest) {
        $self->_register_attributes;
        $self->_register_resultset_class;
    }
    return $ret;
}

sub load_resultset_components {
    my ($self,@comp) = @_;
    my $resultset_class = $self->_setup_resultset_class;
    $resultset_class->load_components(@comp);
}

sub _register_attributes {
    my $self = shift;
    my $cache = $self->_attr_cache;
    return if keys %$cache == 0;

    foreach my $meth (@{Class::Inspector->methods($self) || []}) {
        my $attrs = $cache->{$self->can($meth)};
        next unless $attrs;
        if ($attrs->[0] eq 'ResultSet') {
            no strict 'refs';
            my $resultset_class = $self->_setup_resultset_class;
            my $name = join '::',$resultset_class, $meth;
            *$name = Sub::Name::subname $name, $self->can($meth);
            delete ${"${self}::"}{$meth};
        }
    }
}

sub _setup_resultset_class {
    my $self = shift;
    my $resultset_class = $self . $self->table_resultset_class_suffix;
    no strict 'refs';
    unless (@{"$resultset_class\::ISA"}) {
        @{"$resultset_class\::ISA"} = ($self->base_resultset_class);
    }
    return $resultset_class;
}

sub _register_resultset_class {
    my $self = shift;
    my $resultset_class = $self . $self->table_resultset_class_suffix;
    no strict 'refs';
    if (@{"$resultset_class\::ISA"}) {
        $self->result_source_instance->resultset_class($resultset_class);
    } else {
        $self->result_source_instance->resultset_class
          ($self->base_resultset_class);
    }
}

1;
