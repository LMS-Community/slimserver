package # hide from PAUSE
    DBIx::Class::Relationship::Accessor;

use strict;
use warnings;
use Sub::Name ();
use Class::Inspector ();

our %_pod_inherit_config = 
  (
   class_map => { 'DBIx::Class::Relationship::Accessor' => 'DBIx::Class::Relationship' }
  );

sub register_relationship {
  my ($class, $rel, $info) = @_;
  if (my $acc_type = $info->{attrs}{accessor}) {
    $class->add_relationship_accessor($rel => $acc_type);
  }
  $class->next::method($rel => $info);
}

sub add_relationship_accessor {
  my ($class, $rel, $acc_type) = @_;
  my %meth;
  if ($acc_type eq 'single') {
    my $rel_info = $class->relationship_info($rel);
    $meth{$rel} = sub {
      my $self = shift;
      if (@_) {
        $self->set_from_related($rel, @_);
        return $self->{_relationship_data}{$rel} = $_[0];
      } elsif (exists $self->{_relationship_data}{$rel}) {
        return $self->{_relationship_data}{$rel};
      } else {
        my $cond = $self->result_source->_resolve_condition(
          $rel_info->{cond}, $rel, $self
        );
        if ($rel_info->{attrs}->{undef_on_null_fk}){
          return undef unless ref($cond) eq 'HASH';
          return undef if grep { not defined $_ } values %$cond;
        }
        my $val = $self->find_related($rel, {}, {});
        return $val unless $val;  # $val instead of undef so that null-objects can go through

        return $self->{_relationship_data}{$rel} = $val;
      }
    };
  } elsif ($acc_type eq 'filter') {
    $class->throw_exception("No such column $rel to filter")
       unless $class->has_column($rel);
    my $f_class = $class->relationship_info($rel)->{class};
    $class->inflate_column($rel,
      { inflate => sub {
          my ($val, $self) = @_;
          return $self->find_or_new_related($rel, {}, {});
        },
        deflate => sub {
          my ($val, $self) = @_;
          $self->throw_exception("$val isn't a $f_class") unless $val->isa($f_class);
          return ($val->_ident_values)[0];
            # WARNING: probably breaks for multi-pri sometimes. FIXME
        }
      }
    );
  } elsif ($acc_type eq 'multi') {
    $meth{$rel} = sub { shift->search_related($rel, @_) };
    $meth{"${rel}_rs"} = sub { shift->search_related_rs($rel, @_) };
    $meth{"add_to_${rel}"} = sub { shift->create_related($rel, @_); };
  } else {
    $class->throw_exception("No such relationship accessor type $acc_type");
  }
  {
    no strict 'refs';
    no warnings 'redefine';
    foreach my $meth (keys %meth) {
      my $name = join '::', $class, $meth;
      *$name = Sub::Name::subname($name, $meth{$meth});
    }
  }
}

1;
