package Class::DBI::Relationship;

use strict;
use warnings;

use base 'Class::Accessor';

__PACKAGE__->mk_accessors(qw/name class accessor foreign_class args/);

sub set_up {
	my $proto = shift;
	my $self  = $proto->_init(@_);
	$self->_set_up_class_data;
	$self->_add_triggers;
	$self->_add_methods;
	$self;
}

sub _init {
	my $proto = shift;
	my $name  = shift;
	my ($class, $accessor, $foreign_class, $args) = $proto->remap_arguments(@_);
	return $proto->new({
			name          => $name,
			class         => $class,
			foreign_class => $foreign_class,
			accessor      => $accessor,
			args          => $args,
		});
}

sub remap_arguments {
	my $self = shift;
	return @_;
}

sub _set_up_class_data {
	my $self = shift;
	$self->class->_extend_meta($self->name => $self->accessor => $self);
}

sub triggers { () }

sub _add_triggers {
	my $self = shift;

	# need to treat as list in case there are multiples for the same point.
	my @triggers = $self->triggers or return;
	while (my ($point, $subref) = (splice @triggers, 0, 2)) {
		$self->class->add_trigger($point => $subref);
	}
}

sub methods { () }

sub _add_methods {
	my $self    = shift;
	my %methods = $self->methods or return;
	my $class   = $self->class;
	no strict 'refs';
	foreach my $method (keys %methods) {
		*{"$class\::$method"} = $methods{$method};
	}
}

1;

__END__

=head1 NAME

Class::DBI::Relationship - base class for Relationships

=head1 DESCRIPTION

A Class::DBI class represents a database table. But merely being able
to represent single tables isn't really that useful - databases are all
about relationships.

So, Class::DBI provides a variety of Relationship models to represent
common database occurences (HasA, HasMany and MightHave), and provides
a way to add others.

=head1 SUBCLASSING

Relationships should inherit from Class::DBI::Relationship, and
provide a variety of methods to represent the relationship. For
examples of how these are used see Class::DBI::Relationship::HasA,
Class::DBI::Relationship::HasMany and Class::DBI::Relationship::MightHave.

=head2 remap_arguments

	sub remap_arguments { 
		my $self = shift;
		# process @_;
		return ($class, accessor, $foreign_class, $args)
	}

Subclasses should define a 'remap_arguments' method that takes the
arguments with which your relationship method will be called, and
transforms them into the structure that the Relationship modules requires.
If this method is not provided, then it is assumed that your method will
be called with these 3 arguments in this order.

This should return a list of 4 items:

=over 4 

=item class

The Class::DBI subclass to which this relationship applies. This will be
passed in to you from the caller who actually set up the relationship,
and is available for you to call methods on whilst performing this
mapping. You should almost never need to change this.

This usually an entire application base class (or Class::DBI itself),
but could be a single class wishing to override a default relationship.

=item accessor

The method in the class which will provide access to the results of
the relationship.

=item foreign_class

The class for the table with which the class has a relationship.

=item args

Any additional args that your relationship requires.  It is recommended
that you use this as a hashref to store any extra information your
relationship needs rather than adding extra accessors, as this information
will all be stored in the 'meta_info'.

=back

=head2 triggers

	sub triggers { 
		return (
			before_create => sub { ... },
			after_create  => sub { ... },
		);
	}

Subclasses may define a 'triggers' method that returns a list of
triggers that the relationship needs. This method can be omitted if
there are no triggers to be set up.

=head2 methods

	sub methods { 
		return (
			method1 => sub { ... },
			method2 => sub { ... },
		);
	}

Subclasses may define a 'methods' method that returns a list of methods
to facilitate the relationship that should be created in the calling
Class::DBI class.  This method can be omitted if there are no methods
to be set up.

=cut
