package Class::DBI::Relationship::HasA;

use strict;
use warnings;

use base 'Class::DBI::Relationship';

sub remap_arguments {
	my $proto = shift;
	my $class = shift;
	$class->_invalid_object_method('has_a()') if ref $class;
	my $column = $class->find_column(+shift)
		or return $class->_croak("has_a needs a valid column");
	my $a_class = shift
		or $class->_croak("$class $column needs an associated class");
	my %meths = @_;
	return ($class, $column, $a_class, \%meths);
}

sub triggers {
	my $self = shift;
	$self->class->_require_class($self->foreign_class);
	my $column = $self->accessor;
	return (
		select              => $self->_inflator,
		"after_set_$column" => $self->_inflator,
		deflate_for_create  => $self->_deflator(1),
		deflate_for_update  => $self->_deflator,
	);
}

sub _inflator {
	my $self = shift;
	my $col  = $self->accessor;
	return sub {
		my $self = shift;
		defined(my $value = $self->_attrs($col)) or return;
		my $meta = $self->meta_info(has_a => $col);
		my ($a_class, %meths) = ($meta->foreign_class, %{ $meta->args });

		return if ref $value and $value->isa($a_class);
		my $inflator;

		my $get_new_value = sub {
			my ($inflator, $value, $want_class, $obj) = @_;
			my $new_value =
				(ref $inflator eq 'CODE')
				? $inflator->($value, $obj)
				: $want_class->$inflator($value);
			return $new_value;
		};

		# If we have a custom inflate ...
		if (exists $meths{'inflate'}) {
			$value = $get_new_value->($meths{'inflate'}, $value, $a_class, $self);
			return $self->_attribute_store($col, $value)
				if ref $value
				and $value->isa($a_class);
			$self->_croak("Inflate method didn't inflate right") if ref $value;
		}

		return $self->_croak("Can't inflate $col to $a_class using '$value': "
				. ref($value)
				. " is not a $a_class")
			if ref $value;

		$inflator = $a_class->isa('Class::DBI') ? "_simple_bless" : "new";
		$value = $get_new_value->($inflator, $value, $a_class);

		return $self->_attribute_store($col, $value)
			if ref $value
			and $value->isa($a_class);

		# use ref as $obj may be overloaded and appear 'false'
		return $self->_croak(
			"Can't inflate $col to $a_class " . "via $inflator using '$value'")
			unless ref $value;
	};
}

sub _deflator {
	my ($self, $always) = @_;
	my $col = $self->accessor;
	return sub {
		my $self = shift;
		return unless $self->_attribute_exists($col);
		$self->_attribute_store($col => $self->_deflated_column($col))
			if ($always or $self->{__Changed}->{$col});
	};
}

sub _set_up_class_data {
	my $self = shift;
	$self->class->_extend_class_data(__hasa_rels => $self->accessor =>
			[ $self->foreign_class, %{ $self->args } ]);
	$self->SUPER::_set_up_class_data;
}

1;
