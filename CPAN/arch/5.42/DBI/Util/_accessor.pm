package DBI::Util::_accessor;
use strict;
use Carp;
our $VERSION = "0.009479";

# inspired by Class::Accessor::Fast

sub new {
    my($proto, $fields) = @_;
    my($class) = ref $proto || $proto;
    $fields ||= {};

    my @dubious = grep { !m/^_/ && !$proto->can($_) } keys %$fields;
    carp "$class doesn't have accessors for fields: @dubious" if @dubious;

    # make a (shallow) copy of $fields.
    bless {%$fields}, $class;
}

sub mk_accessors {
    my($self, @fields) = @_;
    $self->mk_accessors_using('make_accessor', @fields);
}

sub mk_accessors_using {
    my($self, $maker, @fields) = @_;
    my $class = ref $self || $self;

    # So we don't have to do lots of lookups inside the loop.
    $maker = $self->can($maker) unless ref $maker;

    no strict 'refs';
    foreach my $field (@fields) {
        my $accessor = $self->$maker($field);
        *{$class."\:\:$field"} = $accessor
            unless defined &{$class."\:\:$field"};
    }
    #my $hash_ref = \%{$class."\:\:_accessors_hash};
    #$hash_ref->{$_}++ for @fields;
    # XXX also copy down _accessors_hash of base class(es)
    # so one in this class is complete
    return;
}

sub make_accessor {
    my($class, $field) = @_;
    return sub {
        my $self = shift;
        return $self->{$field} unless @_;
        croak "Too many arguments to $field" if @_ > 1;
        return $self->{$field} = shift;
    };
}

sub make_accessor_autoviv_hashref {
    my($class, $field) = @_;
    return sub {
        my $self = shift;
        return $self->{$field} ||= {} unless @_;
        croak "Too many arguments to $field" if @_ > 1;
        return $self->{$field} = shift;
    };
}

1;
