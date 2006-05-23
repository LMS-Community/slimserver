package # hide from PAUSE
    DBIx::Class::Relationship::ProxyMethods;

use strict;
use warnings;

use base qw/DBIx::Class/;

sub register_relationship {
  my ($class, $rel, $info) = @_;
  if (my $proxy_list = $info->{attrs}{proxy}) {
    $class->proxy_to_related($rel,
              (ref $proxy_list ? @$proxy_list : $proxy_list));
  }
  $class->next::method($rel, $info);
}

sub proxy_to_related {
  my ($class, $rel, @proxy) = @_;
  no strict 'refs';
  no warnings 'redefine';
  foreach my $proxy (@proxy) {
    *{"${class}::${proxy}"} =
      sub {
        my $self = shift;
        my $val = $self->$rel;
        if (@_ && !defined $val) {
          $val = $self->create_related($rel, { $proxy => $_[0] });
          @_ = ();
        }
        return ($val ? $val->$proxy(@_) : undef);
     }
  }
}

1;
