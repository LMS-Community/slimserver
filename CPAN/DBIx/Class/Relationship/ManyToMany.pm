package # hide from PAUSE
    DBIx::Class::Relationship::ManyToMany;

use strict;
use warnings;

use Carp::Clan qw/^DBIx::Class/;
use Sub::Name ();

our %_pod_inherit_config = 
  (
   class_map => { 'DBIx::Class::Relationship::ManyToMany' => 'DBIx::Class::Relationship' }
  );

sub many_to_many {
  my ($class, $meth, $rel, $f_rel, $rel_attrs) = @_;

  $class->throw_exception(
    "missing relation in many-to-many"
  ) unless $rel;

  $class->throw_exception(
    "missing foreign relation in many-to-many"
  ) unless $f_rel;

  {
    no strict 'refs';
    no warnings 'redefine';

    my $add_meth = "add_to_${meth}";
    my $remove_meth = "remove_from_${meth}";
    my $set_meth = "set_${meth}";
    my $rs_meth = "${meth}_rs";

    for ($add_meth, $remove_meth, $set_meth, $rs_meth) {
      if ( $class->can ($_) ) {
        carp (<<"EOW") unless $ENV{DBIC_OVERWRITE_HELPER_METHODS_OK};

***************************************************************************
The many-to-many relationship '$meth' is trying to create a utility method
called $_.
This will completely overwrite one such already existing method on class
$class.

You almost certainly want to rename your method or the many-to-many
relationship, as the functionality of the original method will not be
accessible anymore.

To disable this warning set to a true value the environment variable
DBIC_OVERWRITE_HELPER_METHODS_OK

***************************************************************************
EOW
      }
    }

    $rel_attrs->{alias} ||= $f_rel;

    my $rs_meth_name = join '::', $class, $rs_meth;
    *$rs_meth_name = Sub::Name::subname $rs_meth_name, sub {
      my $self = shift;
      my $attrs = @_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {};
      my @args = ($f_rel, @_ > 0 ? @_ : undef, { %{$rel_attrs||{}}, %$attrs });
      my $rs = $self->search_related($rel)->search_related(
        $f_rel, @_ > 0 ? @_ : undef, { %{$rel_attrs||{}}, %$attrs }
      );
	  return $rs;
    };

    my $meth_name = join '::', $class, $meth;
    *$meth_name = Sub::Name::subname $meth_name, sub {
		my $self = shift;
		my $rs = $self->$rs_meth( @_ );
  		return (wantarray ? $rs->all : $rs);
	};

    my $add_meth_name = join '::', $class, $add_meth;
    *$add_meth_name = Sub::Name::subname $add_meth_name, sub {
      my $self = shift;
      @_ > 0 or $self->throw_exception(
        "${add_meth} needs an object or hashref"
      );
      my $source = $self->result_source;
      my $schema = $source->schema;
      my $rel_source_name = $source->relationship_info($rel)->{source};
      my $rel_source = $schema->resultset($rel_source_name)->result_source;
      my $f_rel_source_name = $rel_source->relationship_info($f_rel)->{source};
      my $f_rel_rs = $schema->resultset($f_rel_source_name)->search({}, $rel_attrs||{});

      my $obj;
      if (ref $_[0]) {
        if (ref $_[0] eq 'HASH') {
          $obj = $f_rel_rs->find_or_create($_[0]);
        } else {
          $obj = $_[0];
        }
      } else {
        $obj = $f_rel_rs->find_or_create({@_});
      }

      my $link_vals = @_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {};
      my $link = $self->search_related($rel)->new_result($link_vals);
      $link->set_from_related($f_rel, $obj);
      $link->insert();
	  return $obj;
    };

    my $set_meth_name = join '::', $class, $set_meth;
    *$set_meth_name = Sub::Name::subname $set_meth_name, sub {
      my $self = shift;
      @_ > 0 or $self->throw_exception(
        "{$set_meth} needs a list of objects or hashrefs"
      );
      my @to_set = (ref($_[0]) eq 'ARRAY' ? @{ $_[0] } : @_);
      # if there is a where clause in the attributes, ensure we only delete
      # rows that are within the where restriction
      if ($rel_attrs && $rel_attrs->{where}) {
        $self->search_related( $rel, $rel_attrs->{where},{join => $f_rel})->delete;
      } else {
        $self->search_related( $rel, {} )->delete;
      }
      # add in the set rel objects
      $self->$add_meth($_, ref($_[1]) ? $_[1] : {}) for (@to_set);
    };

    my $remove_meth_name = join '::', $class, $remove_meth;
    *$remove_meth_name = Sub::Name::subname $remove_meth_name, sub {
      my $self = shift;
      @_ > 0 && ref $_[0] ne 'HASH'
        or $self->throw_exception("${remove_meth} needs an object");
      my $obj = shift;
      my $rel_source = $self->search_related($rel)->result_source;
      my $cond = $rel_source->relationship_info($f_rel)->{cond};
      my $link_cond = $rel_source->_resolve_condition(
        $cond, $obj, $f_rel
      );
      $self->search_related($rel, $link_cond)->delete;
    };

  }
}

1;
