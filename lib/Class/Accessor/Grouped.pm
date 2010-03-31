package Class::Accessor::Grouped;
use strict;
use warnings;
use Carp ();
use Class::Inspector ();
use Scalar::Util ();
use MRO::Compat;
use Sub::Name ();

our $VERSION = '0.08004';

BEGIN {
    our $hasXS;

    sub _hasXS {
        return $hasXS if defined $hasXS;
    
        $hasXS = 0;
        eval {
            require Class::XSAccessor;
            die if $Class::XSAccessor::VERSION lt '1.05';
            $hasXS = 1;
        };
    
        return $hasXS;
    }
}

=head1 NAME

Class::Accessor::Grouped - Lets you build groups of accessors

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

If you want to mimic Class::Accessor's mk_accessors $group has to be 'simple'
to tell Class::Accessor::Grouped to use its own get_simple and set_simple
methods.

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
        my $class = Scalar::Util::blessed $self || $self;

        # So we don't have to do lots of lookups inside the loop.
        $maker = $self->can($maker) unless ref $maker;
        
        my $hasXS = _hasXS();

        foreach my $field (@fields) {
            if( $field eq 'DESTROY' ) {
                Carp::carp("Having a data accessor named DESTROY  in ".
                             "'$class' is unwise.");
            }

            my $name = $field;

            ($name, $field) = @$field if ref $field;
            
            my $alias = "_${name}_accessor";
            my $full_name = join('::', $class, $name);
            my $full_alias = join('::', $class, $alias);
            
            if ( $hasXS && $group eq 'simple' ) {
                Class::XSAccessor->import(
                    class     => $class,
                    accessors => { $name, $field }
                );
                
                # XXX: is the alias accessor really necessary?
                Class::XSAccessor->import(
                    class     => $class,
                    accessors => { $alias, $field }
                );
            }
            else {
                my $accessor = $self->$maker($group, $field);
                my $alias_accessor = $self->$maker($group, $field);
                
                *$full_name = Sub::Name::subname($full_name, $accessor);
                  #unless defined &{$class."\:\:$field"}
                
                *$full_alias = Sub::Name::subname($full_alias, $alias_accessor);
                  #unless defined &{$class."\:\:$alias"}
            }
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

    # eval for faster fastiness
    return eval "sub {
        if(\@_ > 1) {
            return shift->$set('$field', \@_);
        }
        else {
            return shift->$get('$field');
        }
    };"
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

    return eval "sub {
        if(\@_ > 1) {
            my \$caller = caller;
            Carp::croak(\"'\$caller' cannot alter the value of '$field' on \".
                        \"objects of class '$class'\");
        }
        else {
            return shift->$get('$field');
        }
    };"
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

    return eval "sub {
        unless (\@_ > 1) {
            my \$caller = caller;
            Carp::croak(\"'\$caller' cannot access the value of '$field' on \".
                        \"objects of class '$class'\");
        }
        else {
            return shift->$set('$field', \@_);
        }
    };"
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
  return $_[0]->{$_[1]};
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
  return $_[0]->{$_[1]} = $_[2];
}


=head2 get_inherited

=over 4

=item Arguments: $field

Returns: $value

=back

Simple getter for Classes and hash-based objects which returns the value for
the field name passed as an argument. This behaves much like
L<Class::Data::Accessor> where the field can be set in a base class,
inherited and changed in subclasses, and inherited and changed for object
instances.

=cut

sub get_inherited {
    my $class;

    if (Scalar::Util::blessed $_[0]) {
        my $reftype = Scalar::Util::reftype $_[0];
        $class = ref $_[0];

        if ($reftype eq 'HASH' && exists $_[0]->{$_[1]}) {
            return $_[0]->{$_[1]};
        } elsif ($reftype ne 'HASH') {
            Carp::croak('Cannot get inherited value on an object instance that is not hash-based');
        };
    } else {
        $class = $_[0];
    };

    no strict 'refs';
    no warnings qw/uninitialized/;
    return ${$class.'::__cag_'.$_[1]} if defined(${$class.'::__cag_'.$_[1]});

    # we need to be smarter about recalculation, as @ISA (thus supers) can very well change in-flight
    my $pkg_gen = mro::get_pkg_gen ($class);
    if ( ${$class.'::__cag_pkg_gen'} != $pkg_gen ) {
        @{$class.'::__cag_supers'} = $_[0]->get_super_paths;
        ${$class.'::__cag_pkg_gen'} = $pkg_gen;
    };

    foreach (@{$class.'::__cag_supers'}) {
        return ${$_.'::__cag_'.$_[1]} if defined(${$_.'::__cag_'.$_[1]});
    };

    return undef;
}

=head2 set_inherited

=over 4

=item Arguments: $field, $new_value

Returns: $new_value

=back

Simple setter for Classes and hash-based objects which sets and then returns
the value for the field name passed as an argument. When called on a hash-based
object it will set the appropriate hash key value. When called on a class, it
will set a class level variable.

B<Note:>: This method will die if you try to set an object variable on a non
hash-based object.

=cut

sub set_inherited {
    if (Scalar::Util::blessed $_[0]) {
        if (Scalar::Util::reftype $_[0] eq 'HASH') {
            return $_[0]->{$_[1]} = $_[2];
        } else {
            Carp::croak('Cannot set inherited value on an object instance that is not hash-based');
        };
    } else {
        no strict 'refs';

        return ${$_[0].'::__cag_'.$_[1]} = $_[2];
    };
}

=head2 get_component_class

=over 4

=item Arguments: $field

Returns: $value

=back

Gets the value of the specified component class.

    __PACKAGE__->mk_group_accessors('component_class' => 'result_class');

    $self->result_class->method();

    ## same as
    $self->get_component_class('result_class')->method();

=cut

sub get_component_class {
    return $_[0]->get_inherited($_[1]);
};

=head2 set_component_class

=over 4

=item Arguments: $field, $class

Returns: $new_value

=back

Inherited accessor that automatically loads the specified class before setting
it. This method will die if the specified class could not be loaded.

    __PACKAGE__->mk_group_accessors('component_class' => 'result_class');
    __PACKAGE__->result_class('MyClass');

    $self->result_class->method();

=cut

sub set_component_class {
    if ($_[2]) {
        local $^W = 0;
        if (Class::Inspector->installed($_[2]) && !Class::Inspector->loaded($_[2])) {
            eval "use $_[2]";

            Carp::croak("Could not load $_[1] '$_[2]': ", $@) if $@;
        };
    };

    return $_[0]->set_inherited($_[1], $_[2]);
};

=head2 get_super_paths

Returns a list of 'parent' or 'super' class names that the current class inherited from.

=cut

sub get_super_paths {
    my $class = Scalar::Util::blessed $_[0] || $_[0];

    return @{mro::get_linear_isa($class)};
};

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>
Christopher H. Laco <claco@chrislaco.com>

With contributions from:

Guillermo Roditi <groditi@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

