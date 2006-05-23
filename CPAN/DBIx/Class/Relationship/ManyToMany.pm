package # hide from PAUSE 
    DBIx::Class::Relationship::ManyToMany;

use strict;
use warnings;

sub many_to_many {
  my ($class, $meth, $rel, $f_rel, $rel_attrs) = @_;
  {
    no strict 'refs';
    no warnings 'redefine';
    *{"${class}::${meth}"} = sub {
      my $self = shift;
      my $attrs = @_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {};
      $self->search_related($rel)->search_related($f_rel, @_ > 0 ? @_ : undef, { %{$rel_attrs||{}}, %$attrs });
    };
  }
}

1;
