package DBIx::Class::AccessorGroup;

use strict;
use warnings;

use Carp::Clan qw/^DBIx::Class/;

=head1 NAME

DBIx::Class::AccessorGroup -  Lets you build groups of accessors

=head1 SYNOPSIS

=head1 DESCRIPTION

This class lets you build groups of accessors that will call different
getters and setters.

=head1 METHODS

=head2 mk_group_accessors

=over 4

=item Arguments: $group, @fieldspec

Returns: none

=back

Creates a set of accessors in a given group.

$group is the name of the accessor group for the generated accessors; they
will call get_$group($field) on get and set_$group($field, $value) on set.

@fieldspec is a list of field/accessor names; if a fieldspec is a scalar
this is used as both field and accessor name, if a listref it is expected to
be of the form [ $accessor, $field ].

=cut

sub mk_group_accessors {
  my ($self, $group, @fields) = @_;

  $self->_mk_group_accessors('make_group_accessor', $group, @fields);
  return;
}


{
    no strict 'refs';
    no warnings 'redefine';

    sub _mk_group_accessors {
        my($self, $maker, $group, @fields) = @_;
        my $class = ref $self || $self;

        # So we don't have to do lots of lookups inside the loop.
        $maker = $self->can($maker) unless ref $maker;

        foreach my $field (@fields) {
            if( $field eq 'DESTROY' ) {
                carp("Having a data accessor named DESTROY  in ".
                             "'$class' is unwise.");
            }

            my $name = $field;

            ($name, $field) = @$field if ref $field;

            my $accessor = $self->$maker($group, $field);
            my $alias = "_${name}_accessor";

            #warn "$class $group $field $alias";

            *{$class."\:\:$name"}  = $accessor;
              #unless defined &{$class."\:\:$field"}

            *{$class."\:\:$alias"}  = $accessor;
              #unless defined &{$class."\:\:$alias"}
        }
    }
}

=head2 mk_group_ro_accessors

=over 4

=item Arguments: $group, @fieldspec

Returns: none

=back

Creates a set of read only accessors in a given group. Identical to
<L:/mk_group_accessors> but accessors will throw an error if passed a value
rather than setting the value.

=cut

sub mk_group_ro_accessors {
    my($self, $group, @fields) = @_;

    $self->_mk_group_accessors('make_group_ro_accessor', $group, @fields);
}

=head2 mk_group_wo_accessors

=over 4

=item Arguments: $group, @fieldspec

Returns: none

=back

Creates a set of write only accessors in a given group. Identical to
<L:/mk_group_accessors> but accessors will throw an error if not passed a
value rather than getting the value.

=cut

sub mk_group_wo_accessors {
    my($self, $group, @fields) = @_;

    $self->_mk_group_accessors('make_group_wo_accessor', $group, @fields);
}

=head2 make_group_accessor

=over 4

=item Arguments: $group, $field

Returns: $sub (\CODE)

=back

Returns a single accessor in a given group; called by mk_group_accessors
for each entry in @fieldspec.

=cut

sub make_group_accessor {
    my ($class, $group, $field) = @_;

    my $set = "set_$group";
    my $get = "get_$group";

    # Build a closure around $field.
    return sub {
        my $self = shift;

        if(@_) {
            return $self->$set($field, @_);
        }
        else {
            return $self->$get($field);
        }
    };
}

=head2 make_group_ro_accessor

=over 4

=item Arguments: $group, $field

Returns: $sub (\CODE)

=back

Returns a single read-only accessor in a given group; called by
mk_group_ro_accessors for each entry in @fieldspec.

=cut

sub make_group_ro_accessor {
    my($class, $group, $field) = @_;

    my $get = "get_$group";

    return sub {
        my $self = shift;

        if(@_) {
            my $caller = caller;
            croak("'$caller' cannot alter the value of '$field' on ".
                        "objects of class '$class'");
        }
        else {
            return $self->$get($field);
        }
    };
}

=head2 make_group_wo_accessor

=over 4

=item Arguments: $group, $field

Returns: $sub (\CODE)

=back

Returns a single write-only accessor in a given group; called by
mk_group_wo_accessors for each entry in @fieldspec.

=cut

sub make_group_wo_accessor {
    my($class, $group, $field) = @_;

    my $set = "set_$group";

    return sub {
        my $self = shift;

        unless (@_) {
            my $caller = caller;
            croak("'$caller' cannot access the value of '$field' on ".
                        "objects of class '$class'");
        }
        else {
            return $self->$set($field, @_);
        }
    };
}

=head2 get_simple

=over 4

=item Arguments: $field

Returns: $value

=back

Simple getter for hash-based objects which returns the value for the field
name passed as an argument.

=cut

sub get_simple {
  my ($self, $get) = @_;
  return $self->{$get};
}

=head2 set_simple

=over 4

=item Arguments: $field, $new_value

Returns: $new_value

=back

Simple setter for hash-based objects which sets and then returns the value
for the field name passed as an argument.

=cut

sub set_simple {
  my ($self, $set, $val) = @_;
  return $self->{$set} = $val;
}

=head2 get_component_class

=over 4

=item Arguments: $name

Returns: $component_class

=back

Returns the class name for a component; returns an object key if called on
an object, or attempts to return classdata referenced by _$name if called
on a class.

=cut

sub get_component_class {
  my ($self, $get) = @_;
  if (ref $self) {
      return $self->{$get};
  } else {
      $get = "_$get";
      return $self->can($get) ? $self->$get : undef;
  }
}

=head2 set_component_class

=over 4

=item Arguments: $name, $new_component_class

Returns: $new_component_class

=back

Sets a component class name; attempts to require the class before setting
but does not error if unable to do so. Sets an object key of the given name
if called or an object or classdata called _$name if called on a class.

=cut

sub set_component_class {
  my ($self, $set, $val) = @_;
  eval "require $val";
  if ($@) {
      my $val_path = $val;
      $val_path =~ s{::}{/}g;
      carp $@ unless $@ =~ /^Can't locate $val_path\.pm/;
  }
  if (ref $self) {
      return $self->{$set} = $val;
  } else {
      $set = "_$set";
      return $self->can($set) ?
        $self->$set($val) :
        $self->mk_classdata($set => $val);
  }
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

