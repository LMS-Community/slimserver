package Tie::Cache::LRU::Array;

use strict;
use vars qw($VERSION);
$VERSION = '0.02';

use Carp::Assert;
use base qw(Tie::Cache::LRU::Virtual);

use constant SUCCESS => 1;
use constant FAILURE => 0;

# Node members.
use enum qw(KEY VALUE PREV NEXT);


=pod

=head1 NAME

Tie::Cache::LRU::Array - Tie::Cache::LRU implemented using arrays

=head1 SYNOPSIS

  use Tie::Cache::LRU::Array;

  tie %cache, 'Tie::Cache::LRU::Array', 500;

  ...the rest is as Tie::Cache::LRU...

=head1 DESCRIPTION

This is an alternative implementation of Tie::Cache::LRU using Perl
arrays and built-in array operations instead of a linked list.  The
theory is that even though the algorithm employed is more expensive,
it will still be faster for small cache sizes (where small <= ??) 
because the work is done inside perl (ie. higer big O, lower
constant).  If nothing else, it should use less memory.


=cut

sub TIEHASH {
    my($class, $max_size) = @_;
    my $self = bless {}, $class;

    $max_size = $class->DEFAULT_MAX_SIZE unless defined $max_size;

    $self->_init;
    $self->max_size($max_size);

    return $self;
}


sub _init {
    my($self) = @_;

    $self->{size}  = 0;
    $self->{index} = {};
    $self->{cache} = [];
    $self->{low_idx} = -1;

    return SUCCESS;
}


sub FETCH {
    my($self, $key) = @_;

    return unless exists $self->{index}{$key};

    $self->_promote($key);
    return $self->{cache}[-1][VALUE];
}


sub _promote {
    my($self, $key) = @_;
    my $cache = $self->{cache};

    my $idx  = $self->{index}{$key};
    my $node = $cache->[$idx];

    return $node if $idx == $#{$cache};

    $cache->[$idx] = undef;
    push @$cache, $node;
    $self->{index}{$key} = $#{$cache};

    $self->_reorder_cache if $#$cache > $self->{size} * 2;
    return $node;
}


sub _cull {
    my($self) = @_;

    my $max_size = $self->max_size;
    my $cache = $self->{cache};

    $self->_reorder_cache if $#$cache > $self->{size} * 2;

    my $idx = $self->{low_idx};
    my $cache_size = $#{$cache};

    for( ; $self->{size} > $max_size; $self->{size}-- ) {
        my $node;
        do { $node = $cache->[++$idx]; }
          until defined $node or $idx > $cache_size;

        delete $self->{index}{$node->[KEY]};
        $cache->[$idx] = undef;
    }

    $self->{low_idx} = $idx;

    return SUCCESS;
}


sub _reorder_cache {
    my($self) = shift;
    my $cache = $self->{cache};
    my $next_spot = 0;

    foreach my $idx (0..$#{$cache}) {
        my $node = $cache->[$idx];
        next unless defined $node;
        if( $idx == $next_spot ) {
            $next_spot++;
        }
        else {
            $cache->[$next_spot] = $node;
            $self->{index}{$node->[KEY]} = $next_spot++;
        }
    }

    $#{$cache} = $next_spot - 1;
    $self->{low_idx} = -1;
}


sub EXISTS {
    my($self, $key) = @_;

    return exists $self->{index}{$key};
}


sub CLEAR {
    my($self) = @_;
    $self->_init;
}


sub STORE {
    my($self, $key, $val) = @_;

    if( exists $self->{index}{$key} ) {
        my $node = $self->_promote($key);
        $node->[VALUE] = $val;
    }
    else {
        my $node = [];
        @{$node}[KEY, VALUE] = ($key, $val);

        my $cache = $self->{cache};
        push @$cache, $node;
        $self->{index}{$key} = $#{$cache};
        $self->{size}++;
        $self->_cull if $self->{size} > $self->{max_size};
    }
    return SUCCESS;
}


sub DELETE {
    my($self, $key) = @_;

    return unless exists $self->{index}{$key};

    my $cache = $self->{cache};

    my $idx  = delete $self->{index}{$key};
    my $node = $cache->[$idx];
    $cache->[$idx] = undef;

    $self->{size}--;

    return $node->[VALUE];
}


sub FIRSTKEY {
    my($self) = shift;

    return unless $self->{size};

    my $cache = $self->{cache};

    my $idx = $#{$cache} + 1;
    my $node;
    do { $node = $self->{cache}[--$idx]; } until defined $node or $idx <= 0;
    return $self->{cache}[$idx][KEY];
}


sub NEXTKEY {
    my($self, $last_key) = @_;

    my $idx = $self->{index}{$last_key};
    return undef if $idx == 0;

    my $node;
    do { $node = $self->{cache}[--$idx]; } until defined $node or $idx <= 0;

    return defined $node ? $node->[KEY] : undef;
}


sub max_size {
    my($self) = shift;

    if(@_) {
        my($new_max_size) = shift;
        assert( defined $new_max_size && $new_max_size !~ /\D/ ) if DEBUG;
        $self->{max_size} = $new_max_size;

        $self->_cull if $self->{size} > $new_max_size;

        return SUCCESS;
    }
    else {
        return $self->{max_size};
    }
}


sub curr_size {
    my($self) = shift;

    assert(!@_) if DEBUG;

    return $self->{size};
}


sub DESTROY { }


=pod

=head1 AUTHOR

Michael G Schwern <schwern@pobox.com>

=head1 SEE ALSO

L<Tie::Cache::LRU>, L<Tie::Cache::LRU::Virtual>, L<Tie::Cache>

=cut

1;
