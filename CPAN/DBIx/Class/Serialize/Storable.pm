package DBIx::Class::Serialize::Storable;
use strict;
use warnings;
use Storable;

sub STORABLE_freeze {
    my ($self,$cloning) = @_;
    my $to_serialize = { %$self };
    delete $to_serialize->{result_source};
    return (Storable::freeze($to_serialize));
}

sub STORABLE_thaw {
    my ($self,$cloning,$serialized) = @_;
    %$self = %{ Storable::thaw($serialized) };
    $self->result_source($self->result_source_instance)
      if $self->can('result_source_instance');
}

1;

__END__

=head1 NAME 

    DBIx::Class::Serialize::Storable - hooks for Storable freeze/thaw
    (EXPERIMENTAL)

=head1 SYNOPSIS

    # in a table class definition
    __PACKAGE__->load_components(qw/Serialize::Storable/);
    
    # meanwhile, in a nearby piece of code
    my $cd = $schema->resultset('CD')->find(12);
    $cache->set($cd->ID, $cd); # if the cache uses Storable, this
			       # will work automatically

=head1 DESCRIPTION

This component adds hooks for Storable so that row objects can be
serialized. It assumes that your row object class (C<result_class>) is
the same as your table class, which is the normal situation. However,
this code is not yet well tested, and so should be considered
experimental.

=head1 AUTHORS

David Kamholz <dkamholz@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
